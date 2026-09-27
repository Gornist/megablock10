// Прошивка дисплея как программа для ПК (docs/firmware-plan.md, Ф2): то же ядро (lib/core), что на плате, с драйверами ПК —
// POSIX-сокеты вместо lwIP, каталог вместо LittleFS, PNG вместо e-paper. Сервер мастера работает с ней как с платой; флаги те
// же, что у `npm run mock-display`, так что это прямая замена mock-дисплею.
//
//   display_host --id display-017 --secret <64 hex> [--port 47200] [--width 272 --height 792] [--delay 3000] [--out dir]
//                [--header-timeout 2000 --payload-timeout 5000] [--watchdog-ms 15000] [--battery-mv 3900]
//   сбои (снимаются при «перезагрузке»): --fail-display N, --crash-on-save N, --hang-on-image N
//
// Перезагрузка (REBOOT, сторож) — повторный exec самого себя: кадр и версия восстанавливаются из каталога, как из flash.
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "device.h"
#include "png.h"

using namespace mb10d;

namespace {

struct Options {
  std::string id, secret, host = "0.0.0.0", out = "./fw-host";
  int port = 47200, width = 272, height = 792, delayMs = 3000, headerTimeoutMs = 2000, payloadTimeoutMs = 5000, watchdogMs = 15000;
  int batteryMv = -1, failDisplay = 0, crashOnSave = 0, hangOnImage = 0;
};

// Для сторожа: обработчик сигнала может только exec — путь и аргументы готовятся заранее.
std::string g_exe;
std::vector<std::string> g_rebootArgs;
std::vector<char*> g_rebootArgv;
std::string g_prefix;

void logLine(const char* line) {
  std::fprintf(stderr, "%s %s\n", g_prefix.c_str(), line);
  std::fflush(stderr);
}

[[noreturn]] void reexec() {
  execv(g_exe.c_str(), g_rebootArgv.data());
  const char msg[] = "reboot: exec failed\n";
  ssize_t ignored = write(2, msg, sizeof msg - 1);
  (void)ignored;
  _exit(70);
}

void onWatchdog(int) {
  const char msg[] = "[FW] WATCHDOG RESET — перезапуск\n";
  ssize_t ignored = write(2, msg, sizeof msg - 1);
  (void)ignored;
  reexec();
}

bool mkdirs(const std::string& dir) {
  std::string path;
  for (size_t i = 0; i <= dir.size(); i++) {
    if (i == dir.size() || dir[i] == '/') {
      if (!path.empty()) mkdir(path.c_str(), 0755);
    }
    if (i < dir.size()) path += dir[i];
  }
  struct stat st;
  return stat(dir.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

class HostPlatform : public Platform {
 public:
  HostPlatform(const Options& o) : o_(o) { hw_ = "host-" + o.id; }
  uint32_t nowMs() override {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return uint32_t(uint64_t(ts.tv_sec) * 1000 + uint64_t(ts.tv_nsec) / 1000000);
  }
  void random(uint8_t* out, size_t len) override {
    FILE* f = std::fopen("/dev/urandom", "rb");
    if (!f || std::fread(out, 1, len, f) != len) {
      logLine("no /dev/urandom — abort");
      std::abort();
    }
    std::fclose(f);
  }
  void feedWatchdog() override {
    itimerval t{};
    t.it_value.tv_sec = o_.watchdogMs / 1000;
    t.it_value.tv_usec = (o_.watchdogMs % 1000) * 1000;
    setitimer(ITIMER_REAL, &t, nullptr);
  }
  void reboot() override {
    logLine("rebooting");
    reexec();
  }
  void log(const char* line) override { logLine(line); }
  const char* firmwareVersion() override { return MB10_FW_VERSION; }
  const char* hardwareId() override { return hw_.c_str(); }
  const char* ipAddress() override { return o_.host == "0.0.0.0" ? "127.0.0.1" : o_.host.c_str(); }
  int rssi() override { return 0; }
  int batteryMillivolts() override { return o_.batteryMv; }

 private:
  const Options& o_;
  std::string hw_;
};

class DirStorage : public Storage {
 public:
  DirStorage(const Options& o, int& crashOnSave) : dir_(o.out + "/" + o.id), crashOnSave_(crashOnSave) { mkdirs(dir_); }
  bool writeAtomic(const char* name, const uint8_t* a, size_t aLen, const uint8_t* b, size_t bLen) override {
    std::string path = dir_ + "/" + name, tmp = path + ".tmp";
    int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return false;
    bool ok = writeAll(fd, a, aLen);
    if (crashOnSave_ > 0 && --crashOnSave_ == 0) {
      // «Питание пропало посреди записи»: половина кадра во временном файле, основной файл не тронут.
      writeAll(fd, b, bLen / 2);
      logLine("FAULT crash-on-save: exit посреди записи кадра");
      _exit(3);
    }
    ok = ok && writeAll(fd, b, bLen) && fsync(fd) == 0;
    ok = close(fd) == 0 && ok;
    return ok && rename(tmp.c_str(), path.c_str()) == 0;
  }
  bool read(const char* name, size_t offset, uint8_t* buf, size_t len) override {
    FILE* f = std::fopen((dir_ + "/" + name).c_str(), "rb");
    if (!f) return false;
    bool ok = std::fseek(f, long(offset), SEEK_SET) == 0 && std::fread(buf, 1, len, f) == len;
    std::fclose(f);
    return ok;
  }

 private:
  static bool writeAll(int fd, const uint8_t* p, size_t n) {
    while (n > 0) {
      ssize_t w = write(fd, p, n);
      if (w <= 0) return false;
      p += w;
      n -= size_t(w);
    }
    return true;
  }
  std::string dir_;
  int& crashOnSave_;
};

class PngPanel : public Panel {
 public:
  PngPanel(const Options& o, int& failDisplay, int& hangOnImage)
      : png_(o.out + "/" + o.id + ".png"), txt_(o.out + "/" + o.id + "-test.txt"), delayMs_(o.delayMs), fail_(failDisplay), hang_(hangOnImage) {}
  bool show(const uint8_t* frame, uint16_t w, uint16_t h) override {
    if (hang_ > 0 && --hang_ == 0) {
      logLine("FAULT hang-on-image: зависли в обновлении панели, сторож не кормится");
      for (;;) pause();
    }
    usleep(useconds_t(delayMs_) * 1000);
    if (fail_ > 0) {
      fail_--;
      logLine("FAULT fail-display: панель не обновилась");
      return false;
    }
    return host::writePng(png_.c_str(), frame, w, h);
  }
  bool showText(const char* const* lines, size_t count) override {
    usleep(useconds_t(delayMs_) * 1000);
    FILE* f = std::fopen(txt_.c_str(), "w");
    if (!f) return false;
    for (size_t i = 0; i < count; i++) std::fprintf(f, "%s\n", lines[i]);
    std::fclose(f);
    return true;
  }

 private:
  std::string png_, txt_;
  int delayMs_;
  int& fail_;
  int& hang_;
};

class LogBacklight : public Backlight {
 public:
  void set(uint8_t level) override {
    char line[48];
    std::snprintf(line, sizeof line, "backlight level=%u", unsigned(level));
    logLine(line);
  }
};

class SocketLink : public Link {
 public:
  explicit SocketLink(int fd) : fd_(fd) {}
  void send(const uint8_t* data, size_t len) override {
    while (len > 0 && !failed_) {
      ssize_t n = ::send(fd_, data, len, MSG_NOSIGNAL);
      if (n < 0 && errno == EINTR) continue;
      if (n <= 0) {
        failed_ = true;
        break;
      }
      data += n;
      len -= size_t(n);
    }
  }
  void close() override { closeRequested_ = true; }
  bool closeRequested() const { return closeRequested_ || failed_; }
  int fd() const { return fd_; }

 private:
  int fd_;
  bool closeRequested_ = false;
  bool failed_ = false;
};

// Закрыть так, чтобы уже отправленный NACK дошёл: сначала FIN, непрочитанное дочитать и выбросить (иначе close() с данными в
// приёмном буфере шлёт RST, и клиент может потерять последний ответ). То же нужно делать на плате с lwIP.
void gracefulClose(int fd) {
  shutdown(fd, SHUT_WR);
  uint8_t sink[1024];
  timespec start;
  clock_gettime(CLOCK_MONOTONIC, &start);
  for (;;) {
    pollfd p{fd, POLLIN, 0};
    if (poll(&p, 1, 100) <= 0) break;
    if (recv(fd, sink, sizeof sink, 0) <= 0) break;
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (now.tv_sec - start.tv_sec >= 1) break;
  }
  ::close(fd);
}

bool parseArgs(int argc, char** argv, Options& o) {
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto val = [&](void) -> const char* { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--id") o.id = val();
    else if (a == "--secret") o.secret = val();
    else if (a == "--host") o.host = val();
    else if (a == "--out") o.out = val();
    else if (a == "--port") o.port = std::atoi(val());
    else if (a == "--width") o.width = std::atoi(val());
    else if (a == "--height") o.height = std::atoi(val());
    else if (a == "--delay") o.delayMs = std::atoi(val());
    else if (a == "--header-timeout") o.headerTimeoutMs = std::atoi(val());
    else if (a == "--payload-timeout") o.payloadTimeoutMs = std::atoi(val());
    else if (a == "--watchdog-ms") o.watchdogMs = std::atoi(val());
    else if (a == "--battery-mv") o.batteryMv = std::atoi(val());
    else if (a == "--fail-display") o.failDisplay = std::atoi(val());
    else if (a == "--crash-on-save") o.crashOnSave = std::atoi(val());
    else if (a == "--hang-on-image") o.hangOnImage = std::atoi(val());
    else {
      std::fprintf(stderr, "unknown option %s\n", a.c_str());
      return false;
    }
  }
  return !o.id.empty() && o.id.size() <= kDeviceIdSize && o.secret.size() == 64 && o.width > 0 && o.height > 0 && o.width < 65536 &&
         o.height < 65536;
}

// Аргументы для «перезагрузки» — без флагов сбоев: сбой случается один раз, после перезапуска дисплей здоров.
void prepareReboot(int argc, char** argv) {
  char buf[4096];
  ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
  g_exe = n > 0 ? std::string(buf, size_t(n)) : std::string(argv[0]);
  for (int i = 0; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--fail-display" || a == "--crash-on-save" || a == "--hang-on-image") {
      i++;
      continue;
    }
    g_rebootArgs.push_back(a);
  }
  for (auto& s : g_rebootArgs) g_rebootArgv.push_back(&s[0]);
  g_rebootArgv.push_back(nullptr);
}

int listenOn(const Options& o) {
  int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(uint16_t(o.port));
  if (inet_pton(AF_INET, o.host.c_str(), &addr.sin_addr) != 1 || bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof addr) != 0 || listen(fd, 4) != 0) {
    std::fprintf(stderr, "cannot listen on %s:%d: %s\n", o.host.c_str(), o.port, std::strerror(errno));
    std::exit(1);
  }
  return fd;
}

}  // namespace

int main(int argc, char** argv) {
  Options o;
  if (!parseArgs(argc, argv, o)) {
    std::fprintf(stderr,
                 "usage: display_host --id <id> --secret <64 hex> [--port 47200] [--width 272 --height 792] [--delay 3000] [--out dir]\n"
                 "       [--header-timeout 2000 --payload-timeout 5000 --watchdog-ms 15000 --battery-mv N]\n"
                 "       [--fail-display N --crash-on-save N --hang-on-image N]\n");
    return 2;
  }
  g_prefix = "[FW " + o.id + "]";
  prepareReboot(argc, argv);
  signal(SIGALRM, onWatchdog);
  signal(SIGPIPE, SIG_IGN);
  if (!mkdirs(o.out)) {
    std::fprintf(stderr, "cannot create %s\n", o.out.c_str());
    return 1;
  }

  Config cfg{};
  std::snprintf(cfg.deviceId, sizeof cfg.deviceId, "%s", o.id.c_str());
  if (!parseHex(o.secret.c_str(), cfg.key, sizeof cfg.key)) {
    std::fprintf(stderr, "--secret must be 64 hex chars\n");
    return 2;
  }
  cfg.width = uint16_t(o.width);
  cfg.height = uint16_t(o.height);
  cfg.headerTimeoutMs = uint32_t(o.headerTimeoutMs);
  cfg.payloadTimeoutMs = uint32_t(o.payloadTimeoutMs);

  HostPlatform platform(o);
  DirStorage storage(o, o.crashOnSave);
  PngPanel panel(o, o.failDisplay, o.hangOnImage);
  LogBacklight backlight;
  size_t size = frameBytes(cfg.width, cfg.height);
  std::vector<uint8_t> frame(size), incoming(size < 64 ? 64 : size);
  Device device(cfg, panel, storage, backlight, platform, frame.data(), incoming.data());

  platform.feedWatchdog();
  logLine("BOOT");
  device.boot();  // кадр из «flash» — до сети, как на плате
  int lfd = listenOn(o);
  char line[160];
  std::snprintf(line, sizeof line, "listening on %s:%d, shows version %u, frames -> %s/%s.png", o.host.c_str(), o.port, unsigned(device.displayedVersion()),
                o.out.c_str(), o.id.c_str());
  logLine(line);

  std::unique_ptr<SocketLink> link;
  std::unique_ptr<Session> session;
  auto drop = [&]() {
    if (!link) return;
    session.reset();
    gracefulClose(link->fd());
    link.reset();
  };

  for (;;) {
    platform.feedWatchdog();
    pollfd fds[2] = {{lfd, POLLIN, 0}, {link ? link->fd() : -1, POLLIN, 0}};
    int ready = poll(fds, link ? 2 : 1, 20);
    if (ready < 0 && errno != EINTR) break;
    if (fds[0].revents & POLLIN) {
      int cfd = accept4(lfd, nullptr, nullptr, SOCK_CLOEXEC);
      if (cfd >= 0) {
        if (link) {
          logLine("new connection replaces the previous one");
          session.reset();
          ::close(link->fd());
          link.reset();
        }
        int one = 1;
        setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        link.reset(new SocketLink(cfd));
        session.reset(new Session(device, *link));
      }
    }
    if (link && (fds[1].revents & (POLLIN | POLLHUP | POLLERR))) {
      uint8_t buf[4096];
      ssize_t n = recv(link->fd(), buf, sizeof buf, 0);
      if (n <= 0) drop();
      else session->onData(buf, size_t(n));
    }
    if (session) session->poll();
    if (link && (session->closed() || link->closeRequested())) drop();
    device.tick();
    if (device.rebootRequested()) {
      drop();
      ::close(lfd);
      platform.reboot();
    }
  }
  return 0;
}

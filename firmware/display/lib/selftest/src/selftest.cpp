#include "selftest.h"

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <vector>

#include "sha256.h"

// BSD-сокеты: на ESP32 — lwIP (close сокета — lwip_close, VFS не нужен), на ПК — POSIX.
#if defined(ESP_PLATFORM)
#include <lwip/inet.h>
#include <lwip/sockets.h>
#define MB10_SOCK_CLOSE lwip_close
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#define MB10_SOCK_CLOSE ::close
#endif
#include <unistd.h>

namespace mb10d {
namespace selftest {

namespace {

uint32_t nowMs() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return uint32_t(uint64_t(ts.tv_sec) * 1000 + uint64_t(ts.tv_nsec) / 1000000);
}

void sleepMs(uint32_t ms) { usleep(useconds_t(ms) * 1000); }

const char* typeName(uint8_t t) {
  switch (static_cast<MsgType>(t)) {
    case MsgType::Hello: return "HELLO";
    case MsgType::Received: return "RECEIVED";
    case MsgType::Displayed: return "DISPLAYED";
    case MsgType::Nack: return "NACK";
    case MsgType::Ok: return "OK";
    default: return "?";
  }
}

// «NACK BAD_CRC» / «DISPLAYED 5» — для сообщений о провале.
template <typename R>
const char* describe(const R& r, char* buf, size_t cap) {
  if (r.h.type == uint8_t(MsgType::Nack) && r.h.payloadLength >= 1) std::snprintf(buf, cap, "NACK %s", nackName(static_cast<Nack>(r.payload[0])));
  else std::snprintf(buf, cap, "%s %u", typeName(r.h.type), unsigned(r.h.seq));
  return buf;
}

// Ответы дисплея короткие: HELLO — nonce и JSON статуса (у звуковой точки — до 1280 байт, как в прошивке), LIST — до 1 КБ.
constexpr size_t kReplyMax = kNonceSize + 1280 + 64;

// Есть ли подстрока в JSON статуса / ответа (payload не завершён нулём).
bool contains(const uint8_t* p, size_t len, const char* want) {
  size_t n = std::strlen(want);
  for (size_t i = 0; i + n <= len; i++)
    if (std::memcmp(p + i, want, n) == 0) return true;
  return false;
}

}  // namespace

// Одно TCP-соединение к дисплею. read: 1 — прочитано, 0 — дисплей закрыл соединение, -1 — таймаут.
class Runner::Conn {
 public:
  ~Conn() { close(); }
  bool open(const char* host, uint16_t port) {
    close();
    fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (fd_ < 0) return false;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) != 1 || connect(fd_, reinterpret_cast<sockaddr*>(&addr), sizeof addr) != 0) {
      close();
      return false;
    }
    int one = 1;
    setsockopt(fd_, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    return true;
  }
  bool send(const uint8_t* p, size_t n) {
    while (n > 0) {
      ssize_t w = ::send(fd_, p, n, 0);
      if (w < 0 && errno == EINTR) continue;
      if (w <= 0) return false;
      p += w;
      n -= size_t(w);
    }
    return true;
  }
  int read(uint8_t* p, size_t n, uint32_t timeoutMs) {
    uint32_t until = nowMs() + timeoutMs;
    while (n > 0) {
      int32_t left = int32_t(until - nowMs());
      if (left <= 0) return -1;
      timeval tv{};
      tv.tv_sec = left / 1000;
      tv.tv_usec = (left % 1000) * 1000;
      setsockopt(fd_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
      ssize_t r = recv(fd_, p, n, 0);
      if (r == 0) return 0;
      if (r < 0) {
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) return -1;
        return 0;  // RST — тоже «закрыл»
      }
      p += r;
      n -= size_t(r);
    }
    return 1;
  }
  void close() {
    if (fd_ >= 0) MB10_SOCK_CLOSE(fd_);
    fd_ = -1;
  }

 private:
  int fd_ = -1;
};

struct Runner::Reply {
  Header h;
  uint8_t head[kHeaderSize];
  uint8_t payload[kReplyMax];
  uint8_t nonce[kNonceSize];
};

Runner::Runner(const Target& target, uint8_t* work, LogFn log, void* ctx) : t_(target), work_(work), log_(log), ctx_(ctx) {}

void Runner::log(const char* fmt, ...) {
  char line[200];
  va_list ap;
  va_start(ap, fmt);
  std::vsnprintf(line, sizeof line, fmt, ap);
  va_end(ap);
  log_(line, ctx_);
}

void Runner::pass(const char* name) { log("SELFTEST PASS %s", name); }

void Runner::fail(const char* name, const char* fmt, ...) {
  char why[160];
  va_list ap;
  va_start(ap, fmt);
  std::vsnprintf(why, sizeof why, fmt, ap);
  va_end(ap);
  failures_++;
  log("SELFTEST FAIL %s: %s", name, why);
}

// Кадр ответа: заголовок, payload, подпись nonce этого соединения (у HELLO nonce — начало его же payload).
bool Runner::readReply(Conn& c, const uint8_t* nonce, Reply& r, uint32_t timeoutMs, const char*& why) {
  int got = c.read(r.head, kHeaderSize, timeoutMs);
  if (got <= 0) {
    why = got == 0 ? "соединение закрыто вместо ответа" : "нет ответа (таймаут)";
    return false;
  }
  Nack bad = parseHeader(r.head, kReplyMax, r.h);
  if (bad != Nack::None) {
    why = nackName(bad);
    return false;
  }
  if (r.h.payloadLength > 0 && c.read(r.payload, r.h.payloadLength, timeoutMs) != 1) {
    why = "оборван payload ответа";
    return false;
  }
  if (!nonce) {
    if (r.h.type != uint8_t(MsgType::Hello) || r.h.payloadLength < kNonceSize) {
      why = "первым пришёл не HELLO";
      return false;
    }
    std::memcpy(r.nonce, r.payload, kNonceSize);
    nonce = r.nonce;
  }
  Nack integrity = checkIntegrity(r.h, r.head, r.payload, t_.key, nonce);
  if (integrity != Nack::None) {
    why = integrity == Nack::BadCrc ? "CRC ответа не сходится" : "подпись ответа не сходится (не тот секрет?)";
    return false;
  }
  if (std::strncmp(r.h.deviceId, t_.deviceId, kDeviceIdSize) != 0) {
    why = "в ответе чужой id дисплея";
    return false;
  }
  return true;
}

bool Runner::connectHello(Conn& c, Reply& hello, const char*& why, uint32_t timeoutMs) {
  if (!c.open(t_.host, t_.port)) {
    why = "не подключиться";
    return false;
  }
  return readReply(c, nullptr, hello, timeoutMs, why);
}

size_t Runner::buildImage(uint32_t version, const uint8_t* nonce, const uint8_t* key, const char* deviceId) {
  size_t size = frameBytes(t_.width, t_.height), stride = frameStride(t_.width);
  uint8_t* p = work_ + kHeaderSize;
  // Узор зависит от версии: на панели видно, что кадр сменился, а CRC у каждой версии свой.
  for (size_t i = 0; i < size; i++) p[i] = uint8_t(((i / stride + i % stride + version) & 1) ? 0xAA : 0x55) ^ uint8_t(version);
  FrameOut f{MsgType::Image, deviceId ? deviceId : t_.deviceId, version, t_.width, t_.height, Format::Bpp1, p, size};
  return encodeFrame(f, key, nonce, work_, workSize(t_.width, t_.height));
}

size_t Runner::buildCommand(MsgType type, const uint8_t* payload, size_t len, const uint8_t* nonce) {
  FrameOut f{type, t_.deviceId, 0, 0, 0, Format::None, payload, len};
  return encodeFrame(f, t_.key, nonce, work_, workSize(t_.width, t_.height));
}

size_t Runner::imageNextVersion(const uint8_t* nonce) { return buildImage(displayed_ + 1, nonce, t_.key); }
size_t Runner::imageBadCrc(const uint8_t* nonce) {
  size_t n = imageNextVersion(nonce);
  work_[kHeaderSize + 10] ^= 0x01;  // порча по дороге: подпись и CRC посчитаны до неё
  return n;
}
size_t Runner::imageForeignKey(const uint8_t* nonce) {
  uint8_t other[kKeySize];
  std::memset(other, 7, sizeof other);
  return buildImage(displayed_ + 1, nonce, other);
}
size_t Runner::imageStale(const uint8_t* nonce) { return buildImage(displayed_, nonce, t_.key); }
size_t Runner::imageWrongDevice(const uint8_t* nonce) { return buildImage(displayed_ + 1, nonce, t_.key, "display-other"); }
size_t Runner::imageBadMagic(const uint8_t* nonce) {
  size_t n = imageNextVersion(nonce);
  work_[0] = 'X';
  return n;
}
size_t Runner::unknownType(const uint8_t* nonce) { return buildCommand(static_cast<MsgType>(0x7f), nullptr, 0, nonce); }

void Runner::expectNack(const char* name, Nack expected, bool closes, size_t (Runner::*build)(const uint8_t* nonce)) {
  Conn c;
  Reply hello, r;
  const char* why = "";
  if (!connectHello(c, hello, why)) return fail(name, "%s", why);
  size_t n = (this->*build)(hello.nonce);
  if (n == 0 || !c.send(work_, n)) return fail(name, "не отправить кадр");
  if (!readReply(c, hello.nonce, r, 5000, why)) return fail(name, "%s", why);
  if (r.h.type != uint8_t(MsgType::Nack) || r.h.payloadLength < 1 || r.payload[0] != uint8_t(expected)) {
    char got[48];
    return fail(name, "ждали NACK %s, пришёл %s", nackName(expected), describe(r, got, sizeof got));
  }
  if (r.h.seq != displayed_) return fail(name, "NACK с версией %u, на экране %u", unsigned(r.h.seq), unsigned(displayed_));
  if (closes) {
    uint8_t b;
    if (c.read(&b, 1, 2000) != 0) return fail(name, "после NACK соединение не закрыто");
  }
  pass(name);
}

void Runner::checkHello() {
  const char* name = "hello";
  Conn c;
  Reply hello;
  const char* why = "";
  // Дисплей может ещё грузиться (плата — поднимать Wi-Fi и сервер): подключаться до 20 с.
  uint32_t until = nowMs() + 20000;
  while (!connectHello(c, hello, why)) {
    if (int32_t(until - nowMs()) <= 0) return fail(name, "%s за 20 с", why);
    sleepMs(300);
  }
  if (hello.h.width != t_.width || hello.h.height != t_.height) {
    return fail(name, "панель %ux%u, ждали %ux%u", hello.h.width, hello.h.height, t_.width, t_.height);
  }
  displayed_ = hello.h.seq;
  audio_ = contains(hello.payload + kNonceSize, hello.h.payloadLength - kNonceSize, "\"audio\":{");
  sd_ = contains(hello.payload + kNonceSize, hello.h.payloadLength - kNonceSize, "\"sd\":true");
  log("SELFTEST info: дисплей %s показывает версию %u, статус %.*s", t_.deviceId, unsigned(displayed_), int(hello.h.payloadLength - kNonceSize),
      reinterpret_cast<const char*>(hello.payload + kNonceSize));
  pass(name);
}

void Runner::checkImage() {
  const char* name = "image";
  Conn c;
  Reply hello, r;
  const char* why = "";
  if (!connectHello(c, hello, why)) return fail(name, "%s", why);
  uint32_t version = displayed_ + 1;
  size_t n = buildImage(version, hello.nonce, t_.key);
  uint32_t started = nowMs();
  if (n == 0 || !c.send(work_, n)) return fail(name, "не отправить кадр");
  if (!readReply(c, hello.nonce, r, 5000, why)) return fail(name, "RECEIVED: %s", why);
  if (r.h.type != uint8_t(MsgType::Received) || r.h.seq != version) {
    char got[48];
    return fail(name, "ждали RECEIVED %u, пришёл %s", unsigned(version), describe(r, got, sizeof got));
  }
  // Обновление e-paper — секунды; запас как у сервера (DISPLAY_DISPLAYED_TIMEOUT_MS).
  if (!readReply(c, hello.nonce, r, 30000, why)) return fail(name, "DISPLAYED: %s", why);
  if (r.h.type != uint8_t(MsgType::Displayed) || r.h.seq != version) {
    char got[48];
    return fail(name, "ждали DISPLAYED %u, пришёл %s", unsigned(version), describe(r, got, sizeof got));
  }
  displayed_ = version;
  log("SELFTEST info: кадр %u показан за %u мс", unsigned(version), unsigned(nowMs() - started));
  pass(name);
  c.close();
  expectVersion("image-version-persists", version, 5000);
}

// Молчание после HELLO (sendPartial = false) или оборванный кадр (true) — дисплей закрывает соединение по своему таймауту.
void Runner::checkClosesAfter(const char* name, bool sendPartial, uint32_t expectMs) {
  Conn c;
  Reply hello;
  const char* why = "";
  if (!connectHello(c, hello, why)) return fail(name, "%s", why);
  uint32_t started = nowMs();
  if (sendPartial) {
    size_t n = buildImage(displayed_ + 1, hello.nonce, t_.key);
    if (n == 0 || !c.send(work_, kHeaderSize + (n - kHeaderSize) / 2)) return fail(name, "не отправить начало кадра");
  }
  uint8_t b;
  int got = c.read(&b, 1, expectMs + 3000);
  uint32_t took = nowMs() - started;
  if (got == -1) return fail(name, "соединение не закрыто за %u мс", unsigned(expectMs + 3000));
  if (got == 1) return fail(name, "вместо закрытия пришли данные");
  // Раньше таймаута закрывать нельзя: медленный сервер на плохом Wi-Fi тоже должен успеть.
  if (took + 200 < expectMs) return fail(name, "закрыто через %u мс, раньше таймаута %u мс", unsigned(took), unsigned(expectMs));
  log("SELFTEST info: %s — закрыто через %u мс", name, unsigned(took));
  pass(name);
}

void Runner::checkPreempt() {
  const char* name = "preempt";
  Conn first, second;
  Reply hello1, hello2, r;
  const char* why = "";
  if (!connectHello(first, hello1, why)) return fail(name, "первое: %s", why);
  if (!connectHello(second, hello2, why)) return fail(name, "второе: %s", why);
  uint8_t b;
  if (first.read(&b, 1, 2000) != 0) return fail(name, "первое соединение не закрыто после второго");
  uint8_t level[3] = {0, 0, 0};
  size_t n = buildCommand(MsgType::Backlight, level, sizeof level, hello2.nonce);
  if (!second.send(work_, n) || !readReply(second, hello2.nonce, r, 3000, why)) return fail(name, "второе: %s", why);
  if (r.h.type != uint8_t(MsgType::Ok)) return fail(name, "второе: ждали OK, пришёл %s", typeName(r.h.type));
  pass(name);
}

void Runner::checkTestAndBacklight() {
  {
    const char* name = "test-screen";
    Conn c;
    Reply hello, r;
    const char* why = "";
    uint8_t seconds[2];
    putU16(seconds, 1);
    if (!connectHello(c, hello, why)) {
      fail(name, "%s", why);
    } else {
      size_t n = buildCommand(MsgType::Test, seconds, sizeof seconds, hello.nonce);
      if (!c.send(work_, n) || !readReply(c, hello.nonce, r, 3000, why)) fail(name, "%s", why);
      else if (r.h.type != uint8_t(MsgType::Ok)) fail(name, "ждали OK, пришёл %s", typeName(r.h.type));
      else pass(name);
    }
  }
  // Тестовый экран держится секунду, затем дисплей сам возвращает кадр (и рисует его заново).
  sleepMs(1500);
  const char* name = "backlight";
  Conn c;
  Reply hello, r;
  const char* why = "";
  uint8_t cmd[3] = {uint8_t(BacklightLevel::Medium), 0, 0};
  putU16(cmd + 1, 30);
  if (!connectHello(c, hello, why)) return fail(name, "%s", why);
  size_t n = buildCommand(MsgType::Backlight, cmd, sizeof cmd, hello.nonce);
  if (!c.send(work_, n) || !readReply(c, hello.nonce, r, 3000, why)) return fail(name, "%s", why);
  if (r.h.type != uint8_t(MsgType::Ok)) return fail(name, "ждали OK, пришёл %s", typeName(r.h.type));
  c.close();
  // Уровень виден в статусе следующего HELLO.
  Conn again;
  if (!connectHello(again, hello, why)) return fail(name, "повторное подключение: %s", why);
  const char* json = reinterpret_cast<const char*>(hello.payload + kNonceSize);
  size_t len = hello.h.payloadLength - kNonceSize;
  const char want[] = "\"backlight\":2";
  bool found = false;
  for (size_t i = 0; i + sizeof want - 1 <= len && !found; i++) found = std::memcmp(json + i, want, sizeof want - 1) == 0;
  if (!found) return fail(name, "в статусе HELLO нет %s: %.*s", want, int(len), json);
  // Погасить, чтобы не мешать следующим проверкам.
  uint8_t off[3] = {0, 0, 0};
  n = buildCommand(MsgType::Backlight, off, sizeof off, hello.nonce);
  if (!again.send(work_, n) || !readReply(again, hello.nonce, r, 3000, why)) return fail(name, "выключение: %s", why);
  pass(name);
}

int Runner::runProtocol() {
  int before = failures_;
  checkHello();
  if (failures_ > before) return failures_ - before;  // без HELLO дальше проверять нечего
  checkImage();
  expectNack("bad-crc", Nack::BadCrc, false, &Runner::imageBadCrc);
  expectNack("auth-failed", Nack::AuthFailed, false, &Runner::imageForeignKey);
  expectNack("stale-version", Nack::StaleVersion, false, &Runner::imageStale);
  expectNack("wrong-device", Nack::WrongDevice, false, &Runner::imageWrongDevice);
  expectNack("unsupported-type", Nack::UnsupportedType, false, &Runner::unknownType);
  expectNack("bad-magic", Nack::BadMagic, true, &Runner::imageBadMagic);
  checkClosesAfter("header-timeout", false, t_.headerTimeoutMs);
  checkClosesAfter("payload-timeout", true, t_.payloadTimeoutMs);
  checkPreempt();
  checkTestAndBacklight();
  // Отвергнутое не показано: версия на экране та же.
  expectVersion("rejected-not-shown", displayed_, 5000);
  return failures_ - before;
}

bool Runner::command(const char* name, MsgType type, uint32_t seq, const uint8_t* payload, size_t len, Reply& r) {
  Conn c;
  Reply hello;
  const char* why = "";
  if (!connectHello(c, hello, why)) {
    fail(name, "%s", why);
    return false;
  }
  FrameOut f{type, t_.deviceId, seq, 0, 0, Format::None, payload, len};
  size_t n = encodeFrame(f, t_.key, hello.nonce, work_, workSize(t_.width, t_.height));
  if (n == 0 || !c.send(work_, n) || !readReply(c, hello.nonce, r, 5000, why)) {
    fail(name, "%s", why);
    return false;
  }
  return true;
}

int Runner::runAudio(uint32_t version) {
  if (!audio_) {
    log("SELFTEST info: роли audio в HELLO нет — звук не проверяется");
    return 0;
  }
  int before = failures_;
  Reply r;
  char got[48];
  {
    const char* name = "audio-state";
    char json[160];
    int n = std::snprintf(json, sizeof json, "{\"tracks\":[\"selftest-a.mp3\",\"selftest-b.mp3\"],\"shuffle\":false,\"gapMs\":0,\"volume\":42,\"fadeMs\":0}");
    if (command(name, MsgType::AudioState, version, reinterpret_cast<const uint8_t*>(json), size_t(n), r)) {
      if (r.h.type != uint8_t(MsgType::Ok) || r.h.seq != version) fail(name, "ждали OK %u, пришёл %s", unsigned(version), describe(r, got, sizeof got));
      else pass(name);
    }
  }
  {
    const char* name = "audio-stale";
    const char json[] = "{\"tracks\":[]}";
    if (command(name, MsgType::AudioState, version - 1, reinterpret_cast<const uint8_t*>(json), sizeof json - 1, r)) {
      if (r.h.type != uint8_t(MsgType::Nack) || r.payload[0] != uint8_t(Nack::StaleVersion)) fail(name, "ждали NACK STALE_VERSION, пришёл %s", describe(r, got, sizeof got));
      else pass(name);
    }
  }
  {
    const char* name = "audio-list";
    uint8_t start[2] = {0, 0};
    if (command(name, MsgType::List, 0, start, sizeof start, r)) {
      if (r.h.type != uint8_t(MsgType::Ok) || !contains(r.payload, r.h.payloadLength, "{\"total\":")) fail(name, "ждали OK с каталогом, пришёл %s", describe(r, got, sizeof got));
      else pass(name);
    }
  }
  {
    const char* name = "audio-missing-clip";
    char json[128];
    int n = std::snprintf(json, sizeof json, "{\"clip\":\"%064d\",\"volume\":50}", 0);
    if (command(name, MsgType::Announce, 1, reinterpret_cast<const uint8_t*>(json), size_t(n), r)) {
      if (r.h.type != uint8_t(MsgType::Nack) || r.payload[0] != uint8_t(Nack::MissingClip)) fail(name, "ждали NACK MISSING_CLIP, пришёл %s", describe(r, got, sizeof got));
      else pass(name);
    }
  }
  expectAudioVersion("audio-version-in-hello", version, 5000);
  if (sd_) checkClipAndAnnounce();
  else log("SELFTEST info: карты в точке нет — клип и объявление не проверяются");
  return failures_ - before;
}

bool Runner::exchange(Conn& c, const uint8_t* nonce, MsgType type, uint32_t seq, const uint8_t* payload, size_t len, Reply& r, const char*& why) {
  FrameOut f{type, t_.deviceId, seq, 0, 0, Format::None, payload, len};
  size_t n = encodeFrame(f, t_.key, nonce, work_, workSize(t_.width, t_.height));
  if (n == 0 || !c.send(work_, n)) {
    why = "не отправить кадр";
    return false;
  }
  return readReply(c, nonce, r, 5000, why);
}

void Runner::checkClipAndAnnounce() {
  // Клип: WAV PCM 16 кГц моно, 0,3 с (9644 байта) — два куска: 4096 и остаток.
  const uint32_t samples = 4800, size = 44 + samples * 2;
  std::vector<uint8_t> wav(size);
  auto le = [&](size_t o, uint32_t v, int bytes) {
    for (int i = 0; i < bytes; i++) wav[o + size_t(i)] = uint8_t(v >> (8 * i));
  };
  std::memcpy(wav.data(), "RIFF", 4);
  le(4, size - 8, 4);
  std::memcpy(wav.data() + 8, "WAVEfmt ", 8);
  le(16, 16, 4), le(20, 1, 2), le(22, 1, 2), le(24, 16000, 4), le(28, 32000, 4), le(32, 2, 2), le(34, 16, 2);
  std::memcpy(wav.data() + 36, "data", 4);
  le(40, samples * 2, 4);
  for (uint32_t i = 0; i < samples; i++) le(44 + 2 * i, uint16_t(int16_t((i % 40) * 600 - 12000)), 2);
  uint8_t begin[36];
  Sha256 sha;
  sha.update(wav.data(), wav.size());
  sha.finish(begin);
  putU32(begin + 32, size);
  char id[65];
  for (int i = 0; i < 32; i++) std::snprintf(id + 2 * i, 3, "%02x", begin[i]);
  std::vector<uint8_t> chunk(4 + size);
  Reply hello, r;
  const char* why = "";
  char got[48];

  const char* name = "audio-clip-resume";
  {
    Conn c;
    if (!connectHello(c, hello, why) || !exchange(c, hello.nonce, MsgType::ClipBegin, 0, begin, sizeof begin, r, why)) return fail(name, "BEGIN: %s", why);
    if (r.h.type != uint8_t(MsgType::Ok) || getU32(r.payload) != 0) return fail(name, "BEGIN: ждали OK 0, пришёл %s", describe(r, got, sizeof got));
    putU32(chunk.data(), 0);
    std::memcpy(chunk.data() + 4, wav.data(), 4096);
    if (!exchange(c, hello.nonce, MsgType::ClipChunk, 0, chunk.data(), 4 + 4096, r, why)) return fail(name, "CHUNK: %s", why);
    if (r.h.type != uint8_t(MsgType::Ok) || getU32(r.payload) != 4096) return fail(name, "CHUNK: ждали OK 4096, пришёл %s", describe(r, got, sizeof got));
  }  // «Wi-Fi пропал»: соединение закрыто посреди загрузки
  {
    Conn c;
    if (!connectHello(c, hello, why) || !exchange(c, hello.nonce, MsgType::ClipBegin, 0, begin, sizeof begin, r, why)) return fail(name, "BEGIN 2: %s", why);
    if (r.h.type != uint8_t(MsgType::Ok) || getU32(r.payload) != 4096) {
      return fail(name, "после обрыва ждали «уже есть 4096», пришло %s %u", describe(r, got, sizeof got), unsigned(r.h.payloadLength >= 4 ? getU32(r.payload) : 0));
    }
    putU32(chunk.data(), 4096);
    std::memcpy(chunk.data() + 4, wav.data() + 4096, size - 4096);
    if (!exchange(c, hello.nonce, MsgType::ClipChunk, 0, chunk.data(), 4 + size - 4096, r, why)) return fail(name, "CHUNK 2: %s", why);
    if (r.h.type != uint8_t(MsgType::Ok) || getU32(r.payload) != size) return fail(name, "CHUNK 2: ждали OK %u, пришёл %s", unsigned(size), describe(r, got, sizeof got));
    if (!exchange(c, hello.nonce, MsgType::ClipCommit, 0, nullptr, 0, r, why)) return fail(name, "COMMIT: %s", why);
    if (r.h.type != uint8_t(MsgType::Ok)) return fail(name, "COMMIT: ждали OK, пришёл %s", describe(r, got, sizeof got));
    // Клип уже на карте — BEGIN отвечает полной длиной, грузить нечего.
    if (!exchange(c, hello.nonce, MsgType::ClipBegin, 0, begin, sizeof begin, r, why)) return fail(name, "BEGIN 3: %s", why);
    if (r.h.type != uint8_t(MsgType::Ok) || getU32(r.payload) != size) return fail(name, "повторный BEGIN: ждали %u, пришёл %s", unsigned(size), describe(r, got, sizeof got));
  }
  pass(name);

  name = "audio-announce";
  const uint32_t annId = 9;
  char json[160];
  int n = std::snprintf(json, sizeof json, "{\"clip\":\"%s\",\"volume\":70,\"chime\":true,\"duck\":20}", id);
  if (!command(name, MsgType::Announce, annId, reinterpret_cast<const uint8_t*>(json), size_t(n), r)) return;
  if (r.h.type != uint8_t(MsgType::Ok) || !contains(r.payload, r.h.payloadLength, "{\"durationMs\":1200}")) {
    return fail(name, "ждали OK {\"durationMs\":1200} (0,3 с + сигнал 0,9 с), пришёл %s %.*s", describe(r, got, sizeof got), int(r.h.payloadLength), r.payload);
  }
  pass(name);

  name = "audio-announce-done";
  char want[48];
  std::snprintf(want, sizeof want, "\"ann\":{\"id\":%u,\"state\":\"done\"}", unsigned(annId));
  uint32_t until = nowMs() + 6000;
  for (;;) {
    Conn c;
    if (connectHello(c, hello, why) && contains(hello.payload + kNonceSize, hello.h.payloadLength - kNonceSize, want)) break;
    if (int32_t(until - nowMs()) <= 0) {
      return fail(name, "за 6 с в HELLO нет %s: %.*s", want, int(hello.h.payloadLength > kNonceSize ? hello.h.payloadLength - kNonceSize : 0),
                  reinterpret_cast<const char*>(hello.payload + kNonceSize));
    }
    sleepMs(300);
  }
  pass(name);
}

bool Runner::expectAudioVersion(const char* name, uint32_t expected, uint32_t timeoutMs) {
  uint32_t until = nowMs() + timeoutMs;
  const char* why = "";
  char want[40];
  std::snprintf(want, sizeof want, "\"audio\":{\"v\":%u,", unsigned(expected));
  for (;;) {
    Conn c;
    Reply hello;
    if (connectHello(c, hello, why)) {
      const uint8_t* json = hello.payload + kNonceSize;
      size_t len = hello.h.payloadLength - kNonceSize;
      if (!contains(json, len, want)) {
        fail(name, "в HELLO нет %s: %.*s", want, int(len > 200 ? 200 : len), reinterpret_cast<const char*>(json));
        return false;
      }
      pass(name);
      return true;
    }
    if (int32_t(until - nowMs()) <= 0) break;
    sleepMs(300);
  }
  fail(name, "%s за %u мс", why, unsigned(timeoutMs));
  return false;
}

bool Runner::reboot() {
  const char* name = "reboot-command";
  Conn c;
  Reply hello, r;
  const char* why = "";
  if (!connectHello(c, hello, why)) {
    fail(name, "%s", why);
    return false;
  }
  size_t n = buildCommand(MsgType::Reboot, nullptr, 0, hello.nonce);
  if (!c.send(work_, n) || !readReply(c, hello.nonce, r, 3000, why)) {
    fail(name, "%s", why);
    return false;
  }
  if (r.h.type != uint8_t(MsgType::Ok)) {
    fail(name, "ждали OK, пришёл %s", typeName(r.h.type));
    return false;
  }
  pass(name);
  return true;
}

bool Runner::expectVersion(const char* name, uint32_t expected, uint32_t timeoutMs) {
  uint32_t until = nowMs() + timeoutMs;
  const char* why = "";
  for (;;) {
    Conn c;
    Reply hello;
    if (connectHello(c, hello, why)) {
      if (hello.h.seq != expected) {
        fail(name, "HELLO с версией %u, ждали %u", unsigned(hello.h.seq), unsigned(expected));
        return false;
      }
      pass(name);
      return true;
    }
    if (int32_t(until - nowMs()) <= 0) break;
    sleepMs(300);
  }
  fail(name, "%s за %u мс", why, unsigned(timeoutMs));
  return false;
}

}  // namespace selftest
}  // namespace mb10d

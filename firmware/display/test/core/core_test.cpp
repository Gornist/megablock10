// Тесты ядра прошивки на ПК (CMake + g++): общие векторы протокола с сервером, RFC 4231, сессия байт в байт, таймауты,
// восстановление кадра, подсветка, тестовый экран, Wi-Fi-backoff. Запуск: cmake -S firmware/display -B build && cmake --build
// build && ctest --test-dir build.
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "battery.h"
#include "connectivity.h"
#include "crc32.h"
#include "device.h"
#include "protocol.h"
#include "receiver.h"
#include "session.h"
#include "sha256.h"
#include "vectors.inc"

using namespace mb10d;
using Bytes = std::vector<uint8_t>;

static int g_failures = 0;
static int g_checks = 0;
static const char* g_test = "";

#define CHECK(cond)                                                                   \
  do {                                                                                \
    g_checks++;                                                                       \
    if (!(cond)) {                                                                    \
      g_failures++;                                                                   \
      std::printf("FAIL %s:%d [%s] %s\n", __FILE__, __LINE__, g_test, #cond);         \
    }                                                                                 \
  } while (0)
#define CHECK_EQ_STR(a, b)                                                                                         \
  do {                                                                                                             \
    g_checks++;                                                                                                    \
    std::string sa = (a), sb = (b);                                                                                \
    if (sa != sb) {                                                                                                \
      g_failures++;                                                                                                \
      std::printf("FAIL %s:%d [%s] %s != %s\n  got:  %.160s\n  want: %.160s\n", __FILE__, __LINE__, g_test, #a, #b, \
                  sa.c_str(), sb.c_str());                                                                         \
    }                                                                                                              \
  } while (0)

static Bytes fromHex(const std::string& h) {
  Bytes b(h.size() / 2);
  parseHex(h.c_str(), b.data(), b.size());
  return b;
}
static std::string toHex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; i++) {
    s += d[p[i] >> 4];
    s += d[p[i] & 15];
  }
  return s;
}
static std::string toHex(const Bytes& b) { return toHex(b.data(), b.size()); }

// ── Подделки платформы ──

struct FakePanel : Panel {
  int shows = 0;
  int texts = 0;
  bool fail = false;
  Bytes last;
  bool show(const uint8_t* frame, uint16_t w, uint16_t h) override {
    shows++;
    if (fail) return false;
    last.assign(frame, frame + frameBytes(w, h));
    return true;
  }
  bool showText(const char* const*, size_t) override {
    texts++;
    return true;
  }
};

struct FakeStorage : Storage {
  std::map<std::string, Bytes> files;
  bool failWrite = false;
  bool writeAtomic(const char* name, const uint8_t* a, size_t aLen, const uint8_t* b, size_t bLen) override {
    if (failWrite) return false;
    Bytes v(a, a + aLen);
    v.insert(v.end(), b, b + bLen);
    files[name] = v;
    return true;
  }
  bool read(const char* name, size_t offset, uint8_t* buf, size_t len) override {
    auto it = files.find(name);
    if (it == files.end() || it->second.size() < offset + len) return false;
    std::memcpy(buf, it->second.data() + offset, len);
    return true;
  }
};

struct FakeBacklight : Backlight {
  uint8_t level = 99;
  void set(uint8_t l) override { level = l; }
};

struct FakePlatform : Platform {
  uint32_t now = 1000;
  Bytes nonce = fromHex(kVecNonceHex);
  int feeds = 0;
  std::vector<std::string> logs;
  uint32_t nowMs() override { return now; }
  void random(uint8_t* out, size_t len) override { std::memcpy(out, nonce.data(), len); }
  void feedWatchdog() override { feeds++; }
  void reboot() override {}
  void log(const char* line) override { logs.emplace_back(line); }
  const char* firmwareVersion() override { return "0.1.0"; }
  const char* hardwareId() override { return "24:0a:c4:00:00:17"; }
  const char* ipAddress() override { return ""; }
  int rssi() override { return -61; }
  BatteryStatus bat = [] {
    BatteryStatus b;
    b.milliVolts = 3910;  // как делитель: только мВ — HELLO совпадает с общими векторами
    return b;
  }();
  BatteryStatus battery() override { return bat; }
};

struct FakeLink : Link {
  Bytes sent;
  bool closed = false;
  void send(const uint8_t* d, size_t n) override { sent.insert(sent.end(), d, d + n); }
  void close() override { closed = true; }
  // Кадры, отправленные дисплеем, по порядку.
  std::vector<Bytes> frames() const {
    std::vector<Bytes> out;
    size_t i = 0;
    while (i + kHeaderSize <= sent.size()) {
      size_t len = kHeaderSize + getU32(sent.data() + i + 52);
      out.emplace_back(sent.begin() + long(i), sent.begin() + long(i + len));
      i += len;
    }
    return out;
  }
};

struct Rig {
  Config cfg{};
  FakePanel panel;
  FakeStorage storage;
  FakeBacklight backlight;
  FakePlatform platform;
  Bytes frame, incoming;
  Device* device = nullptr;
  Rig(uint16_t w = kVecWidth, uint16_t h = kVecHeight) {
    std::snprintf(cfg.deviceId, sizeof cfg.deviceId, "%s", kVecDeviceId);
    parseHex(kVecKeyHex, cfg.key, sizeof cfg.key);
    cfg.width = w;
    cfg.height = h;
    frame.resize(frameBytes(w, h));
    incoming.resize(frameBytes(w, h) < 64 ? 64 : frameBytes(w, h));
    device = new Device(cfg, panel, storage, backlight, platform, frame.data(), incoming.data());
  }
  ~Rig() { delete device; }
  // Дисплей уже показывает версию displayed (как в векторах).
  void showVersion(uint32_t v) {
    Bytes img(frameBytes(cfg.width, cfg.height), 0x55);
    device->showImage(v, img.data());
  }
};

static const FrameVector& vec(const char* name) {
  for (const auto& f : kVecFrames)
    if (std::strcmp(f.name, name) == 0) return f;
  std::printf("no vector %s\n", name);
  return kVecFrames[0];
}
static const ReplyVector& reply(const char* name) {
  for (const auto& r : kVecReplies)
    if (std::strcmp(r.name, name) == 0) return r;
  return kVecReplies[0];
}

// ── Тесты ──

static void testCrcAndHash() {
  g_test = "crc/sha/hmac";
  for (const auto& c : kVecCrc) CHECK(crc32(reinterpret_cast<const uint8_t*>(c.input), std::strlen(c.input)) == c.crc);
  CHECK(crc32(reinterpret_cast<const uint8_t*>("123456789"), 9) == 0xCBF43926u);
  uint32_t st = crc32Begin();
  st = crc32Update(st, reinterpret_cast<const uint8_t*>("1234"), 4);
  st = crc32Update(st, reinterpret_cast<const uint8_t*>("56789"), 5);
  CHECK(crc32End(st) == 0xCBF43926u);

  uint8_t out[32];
  Sha256 sha;
  sha.update(reinterpret_cast<const uint8_t*>("abc"), 3);
  sha.finish(out);
  CHECK_EQ_STR(toHex(out, 32), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  sha.update(nullptr, 0);
  sha.finish(out);
  CHECK_EQ_STR(toHex(out, 32), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  // 1 000 000 × 'a' кусками — проверка буферизации между блоками.
  Bytes a(1000, 'a');
  for (int i = 0; i < 1000; i++) sha.update(a.data(), a.size());
  sha.finish(out);
  CHECK_EQ_STR(toHex(out, 32), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

  // RFC 4231, случаи 1, 2 и 6 (ключ длиннее блока).
  Bytes k1(20, 0x0b);
  HmacSha256 h1(k1.data(), k1.size());
  h1.update(reinterpret_cast<const uint8_t*>("Hi There"), 8);
  h1.finish(out);
  CHECK_EQ_STR(toHex(out, 32), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
  HmacSha256 h2(reinterpret_cast<const uint8_t*>("Jefe"), 4);
  const char* m2 = "what do ya want for nothing?";
  h2.update(reinterpret_cast<const uint8_t*>(m2), std::strlen(m2));
  h2.finish(out);
  CHECK_EQ_STR(toHex(out, 32), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  Bytes k6(131, 0xaa);
  HmacSha256 h6(k6.data(), k6.size());
  const char* m6 = "Test Using Larger Than Block-Size Key - Hash Key First";
  h6.update(reinterpret_cast<const uint8_t*>(m6), std::strlen(m6));
  h6.finish(out);
  CHECK_EQ_STR(toHex(out, 32), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
}

// Решение дисплея по кадру из векторов при подаче кусками chunk байт.
static std::string decide(const FrameVector& f, size_t chunk) {
  Bytes bytes = fromHex(f.hex);
  Bytes buf(frameBytes(kVecWidth, kVecHeight) < 64 ? 64 : frameBytes(kVecWidth, kVecHeight));
  Receiver r(buf.data(), buf.size());
  Bytes key = fromHex(kVecKeyHex), nonce = fromHex(kVecNonceHex);
  size_t pos = 0;
  while (pos < bytes.size()) {
    size_t n = chunk < bytes.size() - pos ? chunk : bytes.size() - pos;
    size_t off = 0;
    while (off < n) {
      size_t used = 0;
      Receiver::Event ev = r.feed(bytes.data() + pos + off, n - off, used);
      off += used;
      if (ev == Receiver::Event::Error) return std::string("close:") + nackName(r.error());
      if (ev == Receiver::Event::Frame) {
        PanelState panel{kVecDeviceId, kVecWidth, kVecHeight, kVecDisplayed};
        Nack code = validateIncoming(r.header(), r.signedHeader(), r.payload(), key.data(), nonce.data(), panel);
        return code == Nack::None ? "accept" : std::string("nack:") + nackName(code);
      }
      if (used == 0) break;
    }
    pos += n;
  }
  return "incomplete";
}

static void testFrameVectors() {
  for (const auto& f : kVecFrames) {
    g_test = f.name;
    std::string want = std::strcmp(f.action, "accept") == 0 || std::strcmp(f.action, "incomplete") == 0 ? f.action : std::string(f.action) + ":" + f.code;
    for (size_t chunk : {size_t(100000), size_t(1), size_t(7), size_t(92)}) CHECK_EQ_STR(decide(f, chunk), want);
  }
}

static void testReplyVectors() {
  Bytes key = fromHex(kVecKeyHex), nonce = fromHex(kVecNonceHex);
  for (const auto& r : kVecReplies) {
    g_test = r.name;
    MsgType type = std::strcmp(r.type, "RECEIVED") == 0 ? MsgType::Received
                   : std::strcmp(r.type, "DISPLAYED") == 0 ? MsgType::Displayed
                   : std::strcmp(r.type, "NACK") == 0     ? MsgType::Nack
                                                          : MsgType::Ok;
    Bytes payload = fromHex(r.payloadHex);
    uint8_t out[512];
    FrameOut f{type, kVecDeviceId, r.seq, kVecWidth, kVecHeight, Format::Bpp1, payload.data(), payload.size()};
    size_t n = encodeFrame(f, key.data(), nonce.data(), out, sizeof out);
    CHECK_EQ_STR(toHex(out, n), r.hex);
  }
  g_test = "hello";
  Bytes payload = nonce;
  payload.insert(payload.end(), kVecHelloStatus, kVecHelloStatus + std::strlen(kVecHelloStatus));
  uint8_t out[512];
  FrameOut f{MsgType::Hello, kVecDeviceId, kVecHelloDisplayed, kVecWidth, kVecHeight, Format::Bpp1, payload.data(), payload.size()};
  size_t n = encodeFrame(f, key.data(), nonce.data(), out, sizeof out);
  CHECK_EQ_STR(toHex(out, n), kVecHelloHex);
}

static void testSessionAgainstVectors() {
  g_test = "session image_ok";
  {
    Rig rig;
    rig.showVersion(kVecDisplayed);
    FakeLink link;
    Session s(*rig.device, link);
    auto hello = link.frames();
    CHECK(hello.size() == 1 && hello[0][6] == uint8_t(MsgType::Hello) && getU32(hello[0].data() + 40) == kVecDisplayed);
    // Подпись HELLO проверяется ключом и nonce из его payload.
    Header h{};
    CHECK(parseHeader(hello[0].data(), 1024, h) == Nack::None);
    CHECK(checkIntegrity(h, hello[0].data(), hello[0].data() + kHeaderSize, rig.cfg.key, hello[0].data() + kHeaderSize) == Nack::None);
    std::string status(reinterpret_cast<const char*>(hello[0].data() + kHeaderSize + kNonceSize), h.payloadLength - kNonceSize);
    CHECK_EQ_STR(status, "{\"fw\":\"0.1.0\",\"hw\":\"24:0a:c4:00:00:17\",\"rssi\":-61,\"batteryMv\":3910,\"backlight\":0}");
    link.sent.clear();
    Bytes img = fromHex(vec("image_ok").hex);
    s.onData(img.data(), img.size());
    auto out = link.frames();
    CHECK(out.size() == 2);
    if (out.size() == 2) {
      CHECK_EQ_STR(toHex(out[0]), reply("received").hex);
      CHECK_EQ_STR(toHex(out[1]), reply("displayed").hex);
    }
    CHECK(rig.device->displayedVersion() == 142);
    CHECK(rig.panel.last == Bytes(img.begin() + long(kHeaderSize), img.end()));
    CHECK(!link.closed);
  }
  g_test = "session bad_crc";
  {
    Rig rig;
    rig.showVersion(kVecDisplayed);
    FakeLink link;
    Session s(*rig.device, link);
    link.sent.clear();
    Bytes b = fromHex(vec("bad_crc").hex);
    s.onData(b.data(), b.size());
    auto out = link.frames();
    CHECK(out.size() == 1 && toHex(out[0]) == reply("nack_bad_crc").hex);
    CHECK(rig.device->displayedVersion() == kVecDisplayed);
    CHECK(!link.closed);
  }
  g_test = "session bad_magic closes";
  {
    Rig rig;
    FakeLink link;
    Session s(*rig.device, link);
    link.sent.clear();
    Bytes b = fromHex(vec("bad_magic").hex);
    s.onData(b.data(), b.size());
    auto out = link.frames();
    CHECK(out.size() == 1 && out[0][6] == uint8_t(MsgType::Nack) && out[0][kHeaderSize] == uint8_t(Nack::BadMagic));
    CHECK(link.closed && s.closed());
  }
  g_test = "session commands";
  {
    Rig rig;
    rig.showVersion(kVecDisplayed);
    FakeLink link;
    Session s(*rig.device, link);
    link.sent.clear();
    Bytes b = fromHex(vec("backlight_ok").hex);
    s.onData(b.data(), b.size());
    CHECK(rig.backlight.level == 2);
    Bytes t = fromHex(vec("test_ok").hex);
    s.onData(t.data(), t.size());
    CHECK(rig.panel.texts == 1);
    Bytes r = fromHex(vec("reboot_ok").hex);
    s.onData(r.data(), r.size());
    auto out = link.frames();
    CHECK(out.size() == 3);
    for (auto& f : out) CHECK(toHex(f) == reply("ok").hex);
    CHECK(link.closed && rig.device->rebootRequested());
  }
  g_test = "session two frames in one chunk";
  {
    Rig rig;
    rig.showVersion(kVecDisplayed);
    FakeLink link;
    Session s(*rig.device, link);
    link.sent.clear();
    Bytes both = fromHex(vec("bad_crc").hex);
    Bytes ok = fromHex(vec("image_ok").hex);
    both.insert(both.end(), ok.begin(), ok.end());
    s.onData(both.data(), both.size());
    auto out = link.frames();
    CHECK(out.size() == 3);
    CHECK(rig.device->displayedVersion() == 142);
  }
}

static void testTimeouts() {
  g_test = "header timeout";
  {
    Rig rig;
    FakeLink link;
    Session s(*rig.device, link);
    rig.platform.now += 1999;
    s.poll();
    CHECK(!link.closed);
    rig.platform.now += 1;
    s.poll();
    CHECK(link.closed);
  }
  g_test = "payload timeout";
  {
    Rig rig;
    rig.showVersion(kVecDisplayed);
    FakeLink link;
    Session s(*rig.device, link);
    Bytes b = fromHex(vec("image_ok").hex);
    s.onData(b.data(), 100);
    rig.platform.now += 3000;
    s.poll();
    CHECK(!link.closed);  // заголовок уже шёл — действует таймаут payload, не заголовка
    s.onData(b.data() + 100, 5);
    rig.platform.now += 1999;
    s.poll();
    CHECK(!link.closed);  // 5 с от начала кадра, а не от последнего байта
    rig.platform.now += 1;
    s.poll();
    CHECK(link.closed);
    CHECK(rig.device->displayedVersion() == kVecDisplayed);
  }
}

static void testDevice() {
  g_test = "boot restores frame";
  {
    Rig a;
    a.showVersion(7);
    Rig b;
    b.storage = a.storage;
    b.device->boot();
    CHECK(b.device->displayedVersion() == 7);
    CHECK(b.panel.shows == 1 && b.panel.last == Bytes(frameBytes(kVecWidth, kVecHeight), 0x55));
    CHECK(b.backlight.level == 0);
  }
  g_test = "boot ignores corrupt / foreign frame";
  {
    Rig a;
    a.showVersion(7);
    Rig b;
    b.storage = a.storage;
    b.storage.files[kFrameFile][kStoredHeaderSize + 3] ^= 1;
    b.device->boot();
    CHECK(b.device->displayedVersion() == 0 && b.panel.shows == 0);
    Rig c(24, kVecHeight);
    c.storage = a.storage;
    c.device->boot();
    CHECK(c.device->displayedVersion() == 0 && c.panel.shows == 0);
    Rig d;
    d.device->boot();
    CHECK(d.device->displayedVersion() == 0);
  }
  g_test = "storage/panel failure keeps old version";
  {
    Rig rig;
    rig.showVersion(5);
    rig.storage.failWrite = true;
    Bytes img(frameBytes(kVecWidth, kVecHeight), 0x11);
    CHECK(!rig.device->showImage(6, img.data()));
    CHECK(rig.device->displayedVersion() == 5);
    rig.storage.failWrite = false;
    rig.panel.fail = true;
    CHECK(!rig.device->showImage(6, img.data()));
    CHECK(rig.device->displayedVersion() == 5);
  }
  g_test = "session: panel failure → NACK DISPLAY_FAILED";
  {
    Rig rig;
    rig.showVersion(kVecDisplayed);
    rig.panel.fail = true;
    FakeLink link;
    Session s(*rig.device, link);
    link.sent.clear();
    Bytes b = fromHex(vec("image_ok").hex);
    s.onData(b.data(), b.size());
    auto out = link.frames();
    CHECK(out.size() == 2 && out[0][6] == uint8_t(MsgType::Received) && out[1][6] == uint8_t(MsgType::Nack) &&
          out[1][kHeaderSize] == uint8_t(Nack::DisplayFailed));
  }
  g_test = "backlight timer and test screen";
  {
    Rig rig;
    rig.showVersion(3);
    int shows = rig.panel.shows;
    rig.device->setBacklight(3, 10);
    rig.device->showTest(30);
    rig.platform.now += 9999;
    rig.device->tick();
    CHECK(rig.backlight.level == 3);
    rig.platform.now += 1;
    rig.device->tick();
    CHECK(rig.backlight.level == 0);
    CHECK(rig.panel.shows == shows);
    rig.platform.now += 20000;
    rig.device->tick();
    CHECK(rig.panel.shows == shows + 1);  // тестовый экран сменился последним кадром
    rig.device->setBacklight(2, 0);       // 0 с — пока не скажут иначе
    rig.platform.now += 3600000;
    rig.device->tick();
    CHECK(rig.backlight.level == 2);
  }
}

static void testConnectivity() {
  g_test = "backoff";
  Backoff b;
  uint32_t seq[] = {1000, 2000, 4000, 8000, 16000, 30000, 30000};
  for (uint32_t want : seq) CHECK(b.next() == want);
  b.reset();
  CHECK(b.next() == 1000);

  g_test = "connectivity";
  Connectivity c(15000);
  uint32_t t = 0;
  CHECK(c.update(false, t) == Connectivity::Action::StartConnect);
  CHECK(c.update(false, t += 14999) == Connectivity::Action::None);
  CHECK(c.update(false, t += 1) == Connectivity::Action::Disconnected);
  CHECK(c.state() == Connectivity::State::Backoff && c.retryAt() == t + 1000);
  CHECK(c.update(false, t += 999) == Connectivity::Action::None);
  CHECK(c.update(false, t += 1) == Connectivity::Action::StartConnect);
  CHECK(c.update(false, t += 15000) == Connectivity::Action::Disconnected);
  CHECK(c.retryAt() == t + 2000);
  CHECK(c.update(false, t += 2000) == Connectivity::Action::StartConnect);
  CHECK(c.update(true, t += 500) == Connectivity::Action::None);
  CHECK(c.state() == Connectivity::State::Online);
  CHECK(c.update(false, t += 1) == Connectivity::Action::Disconnected);
  CHECK(c.retryAt() == t + 1000);  // после успеха backoff сброшен
}

static void testBattery() {
  g_test = "battery";
  // MAX17048: VCELL 78,125 мкВ/ед., SOC — старший байт %, CRATE — 0,208 %/ч (даташит).
  CHECK(max17048::milliVolts(0) == 0);
  CHECK(max17048::milliVolts(0xFFFF) == 5120);
  CHECK(max17048::milliVolts(50048) == 3910);  // 50048 × 78,125 мкВ = 3,91 В
  CHECK(max17048::percent(0x4B00) == 75);
  CHECK(max17048::percent(0x4B80) == 76);  // 75,5 % → 76
  CHECK(max17048::percent(0x4A7F) == 74);
  CHECK(max17048::percent(0x6500) == 100);  // топливомер бывает выше 100 % — не показываем
  CHECK(max17048::rateTenthsPerHour(0) == 0);
  CHECK(max17048::rateTenthsPerHour(uint16_t(-10)) == -21);  // −2,08 %/ч
  CHECK(max17048::rateTenthsPerHour(5) == 10);
  CHECK(max17048::versionOk(0x0012));
  CHECK(max17048::versionOk(0x0011));
  CHECK(!max17048::versionOk(0x0000));
  CHECK(!max17048::versionOk(0xFFFF));
  // Кривая Li-ion: края, узлы, середина между узлами, обратимость.
  CHECK(liionPercentFromMilliVolts(4300) == 100);
  CHECK(liionPercentFromMilliVolts(3000) == 0);
  CHECK(liionPercentFromMilliVolts(3840) == 50);
  CHECK(liionPercentFromMilliVolts(3830) == 48);
  CHECK(liionMilliVoltsFromPercent(50) == 3840);
  CHECK(liionMilliVoltsFromPercent(0) == 3270);
  for (int p = 0; p <= 100; p += 5) CHECK(liionPercentFromMilliVolts(liionMilliVoltsFromPercent(p)) == p);

  // HELLO: с топливомером — процент и скорость; без него — прежний JSON (его сверяют общие векторы).
  Rig rig;
  rig.platform.bat.percent = 73;
  rig.platform.bat.hasRate = true;
  rig.platform.bat.rateTenthsPerHour = -21;
  Device& device = *rig.device;
  char json[256];
  device.statusJson(json, sizeof json);
  CHECK(std::strstr(json, "\"batteryMv\":3910,\"batteryPct\":73,\"batteryRate\":-2.1,") != nullptr);
  rig.platform.bat.rateTenthsPerHour = 5;
  device.statusJson(json, sizeof json);
  CHECK(std::strstr(json, "\"batteryRate\":0.5,") != nullptr);
}

int main() {
  testCrcAndHash();
  testFrameVectors();
  testReplyVectors();
  testSessionAgainstVectors();
  testTimeouts();
  testDevice();
  testConnectivity();
  testBattery();
  std::printf("%d checks, %d failed\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}

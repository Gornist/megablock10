// Тесты звука в ядре прошивки (docs/sound-nodes.md): JSON команд, WAV/IMA ADPCM, плейлист (порядок, перемешивание, пропуск
// отсутствующих, пауза), смена канала без обрыва общего трека, сохранение состояния через перезагрузку, клип с докачкой и
// проверкой sha256, объявление с приглушением, статус HELLO и LIST; сессия целиком — кадрами протокола.
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "device.h"
#include "json.h"
#include "protocol.h"
#include "sha256.h"
#include "sound.h"
#include "wav.h"

using namespace mb10d;
using Bytes = std::vector<uint8_t>;

static int g_failures = 0, g_checks = 0;
static const char* g_test = "";
#define CHECK(cond)                                                           \
  do {                                                                        \
    g_checks++;                                                               \
    if (!(cond)) {                                                            \
      g_failures++;                                                           \
      std::printf("FAIL %s:%d [%s] %s\n", __FILE__, __LINE__, g_test, #cond); \
    }                                                                         \
  } while (0)
#define CHECK_STR(a, b)                                                                                                    \
  do {                                                                                                                     \
    g_checks++;                                                                                                            \
    std::string sa = (a), sb = (b);                                                                                        \
    if (sa != sb) {                                                                                                        \
      g_failures++;                                                                                                        \
      std::printf("FAIL %s:%d [%s] %s\n  got:  %.300s\n  want: %.300s\n", __FILE__, __LINE__, g_test, #a, sa.c_str(), sb.c_str()); \
    }                                                                                                                      \
  } while (0)

static std::string hex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; i++) (s += d[p[i] >> 4]) += d[p[i] & 15];
  return s;
}
static std::string sha(const Bytes& b) {
  Sha256 s;
  s.update(b.data(), b.size());
  uint8_t d[32];
  s.finish(d);
  return hex(d, 32);
}
static Bytes str(const std::string& s) { return Bytes(s.begin(), s.end()); }

// ── Подделки ──

struct MemStorage : Storage {
  std::map<std::string, Bytes> files;
  bool writeAtomic(const char* name, const uint8_t* a, size_t aLen, const uint8_t* b, size_t bLen) override {
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

struct Clock : Platform {
  uint32_t now = 1000;
  uint8_t seed = 7;
  std::vector<std::string> logs;
  uint32_t nowMs() override { return now; }
  void random(uint8_t* out, size_t len) override {
    for (size_t i = 0; i < len; i++) out[i] = uint8_t(seed + i * 31);
  }
  void feedWatchdog() override {}
  void reboot() override {}
  void log(const char* line) override { logs.emplace_back(line); }
  const char* firmwareVersion() override { return "0.2.0"; }
  const char* hardwareId() override { return "hw"; }
  const char* ipAddress() override { return ""; }
  int rssi() override { return 0; }
  BatteryStatus battery() override { return BatteryStatus(); }
};

struct Card : SoundCard {
  bool inserted = true;
  std::set<std::string> tracks;
  std::map<std::string, Bytes> clips, parts;
  int failWrites = 0;
  bool present() override { return inserted; }
  size_t trackCount() override { return tracks.size(); }
  bool trackName(size_t i, char* out, size_t cap) override {
    if (i >= tracks.size()) return false;
    auto it = tracks.begin();
    std::advance(it, long(i));
    std::snprintf(out, cap, "%s", it->c_str());
    return true;
  }
  bool hasTrack(const char* n) override { return tracks.count(n) > 0; }
  bool hasClip(const char* id) override { return clips.count(id) > 0; }
  uint32_t clipSize(const char* id) override { return clips.count(id) ? uint32_t(clips[id].size()) : 0; }
  bool readClip(const char* id, uint32_t off, uint8_t* buf, size_t len) override {
    auto& c = clips[id];
    if (off + len > c.size()) return false;
    std::memcpy(buf, c.data() + off, len);
    return true;
  }
  uint32_t partSize(const char* id) override { return parts.count(id) ? uint32_t(parts[id].size()) : 0; }
  bool writePart(const char* id, uint32_t off, const uint8_t* d, size_t len) override {
    if (failWrites > 0 && failWrites-- > 0) return false;
    auto& p = parts[id];
    p.resize(off);
    p.insert(p.end(), d, d + len);
    return true;
  }
  bool readPart(const char* id, uint32_t off, uint8_t* buf, size_t len) override {
    auto& p = parts[id];
    if (off + len > p.size()) return false;
    std::memcpy(buf, p.data() + off, len);
    return true;
  }
  bool commitPart(const char* id) override {
    clips[id] = parts[id];
    parts.erase(id);
    return true;
  }
  void removePart(const char* id) override { parts.erase(id); }
};

struct Speaker : AudioOut {
  std::string track, clip;
  uint8_t trackVol = 0, clipVol = 0;
  bool trackOn = false, clipOn = false, chime = false;
  std::vector<std::string> played;
  std::set<std::string> broken;
  bool startTrack(const char* name, uint8_t volume, uint32_t) override {
    if (broken.count(name)) return false;
    track = name;
    trackVol = volume;
    trackOn = true;
    played.push_back(name);
    return true;
  }
  void stopTrack(uint32_t) override {
    trackOn = false;
    track.clear();
  }
  void setTrackVolume(uint8_t v, uint32_t) override { trackVol = v; }
  bool trackPlaying() override { return trackOn; }
  bool startClip(const char* id, uint8_t v, bool c) override {
    clip = id;
    clipVol = v;
    chime = c;
    clipOn = true;
    return true;
  }
  void stopClip() override { clipOn = false; }
  bool clipPlaying() override { return clipOn; }
};

// WAV PCM16 моно 16 кГц: ms миллисекунд.
static Bytes wavPcm(uint32_t ms) {
  uint32_t samples = 16 * ms, data = samples * 2;
  Bytes b(44 + data, 0);
  auto le32 = [&](size_t o, uint32_t v) {
    for (int i = 0; i < 4; i++) b[o + size_t(i)] = uint8_t(v >> (8 * i));
  };
  auto le16 = [&](size_t o, uint16_t v) {
    b[o] = uint8_t(v);
    b[o + 1] = uint8_t(v >> 8);
  };
  std::memcpy(b.data(), "RIFF", 4);
  le32(4, 36 + data);
  std::memcpy(b.data() + 8, "WAVEfmt ", 8);
  le32(16, 16);
  le16(20, 1);
  le16(22, 1);
  le32(24, 16000);
  le32(28, 32000);
  le16(32, 2);
  le16(34, 16);
  std::memcpy(b.data() + 36, "data", 4);
  le32(40, data);
  for (uint32_t i = 0; i < samples; i++) le16(44 + 2 * i, uint16_t(int16_t(std::sin(i / 7.0) * 9000)));
  return b;
}

struct Node {
  Card card;
  Speaker speaker;
  MemStorage storage;
  Clock clock;
  Sound* sound;
  Node() {
    card.tracks = {"ad-arasaka.mp3", "bar-jazz-1.mp3", "bar-jazz-2.mp3", "radio-1.mp3", "rain.mp3"};
    sound = new Sound(card, speaker, storage, clock);
  }
  ~Node() { delete sound; }
  Nack state(uint32_t v, const std::string& json) {
    Bytes b = str(json);
    return sound->applyState(v, b.data(), b.size());
  }
  std::string status() {
    char out[1280];
    size_t n = sound->statusJson(out, sizeof out);
    return std::string(out, n);
  }
  // Плеер доиграл трек.
  void finishTrack() {
    speaker.trackOn = false;
    sound->tick();
  }
  void reboot() {
    delete sound;
    speaker = Speaker();
    sound = new Sound(card, speaker, storage, clock);
    sound->boot();
  }
};

// ── Тесты ──

static void testJson() {
  g_test = "json";
  const char* s = R"({"tracks":["a.mp3","b\"cЖ.mp3"],"shuffle":true,"gapMs":2500,"x":{"deep":[1,{"y":"}"}]},"volume":55.4})";
  JsonCursor c(s, std::strlen(s));
  CHECK(c.beginObject());
  char key[16], val[64];
  std::vector<std::string> tracks;
  bool shuffle = false;
  double gap = 0, vol = 0;
  while (c.nextKey(key, sizeof key)) {
    if (!std::strcmp(key, "tracks")) {
      CHECK(c.beginArray());
      while (c.nextItem()) {
        CHECK(c.readString(val, sizeof val));
        tracks.push_back(val);
      }
    } else if (!std::strcmp(key, "shuffle")) CHECK(c.readBool(shuffle));
    else if (!std::strcmp(key, "gapMs")) CHECK(c.readNumber(gap));
    else if (!std::strcmp(key, "volume")) CHECK(c.readNumber(vol));
    else CHECK(c.skip());
  }
  CHECK(c.ok());
  CHECK(tracks.size() == 2);
  CHECK_STR(tracks[1], "b\"c\xD0\x96.mp3");
  CHECK(shuffle && gap == 2500 && vol > 55 && vol < 56);
  JsonCursor bad("{\"a\":", 5);
  CHECK(bad.beginObject());
  CHECK(bad.nextKey(key, sizeof key));
  CHECK(!bad.skip());
  char out[32];
  size_t len = 0;
  CHECK(jsonAppendString(out, sizeof out, len, "q\"\\\n"));
  CHECK_STR(std::string(out, len), "\"q\\\"\\\\\\u000a\"");
  len = 0;
  CHECK(!jsonAppendString(out, 6, len, "toolong"));
}

static void testWav() {
  g_test = "wav";
  Bytes w = wavPcm(1500);
  WavInfo info;
  CHECK(parseWavHeader(w.data(), 128, uint32_t(w.size()), info));
  CHECK(info.format == kWavPcm && info.durationMs == 1500 && info.dataOffset == 44);
  Bytes stereo = w;
  stereo[22] = 2;
  CHECK(!parseWavHeader(stereo.data(), 128, uint32_t(stereo.size()), info));
  // IMA ADPCM: блок с нулевыми кодами держит предсказание; код 7 растит его.
  uint8_t block[256] = {0};
  block[0] = 0x10;  // pred = 16
  block[2] = 0;
  int16_t pcm[505];
  CHECK(decodeImaBlock(block, sizeof block, pcm, 505) == 505);
  CHECK(pcm[0] == 16 && pcm[1] == 16 + (7 >> 3));
  block[4] = 0x77;
  CHECK(decodeImaBlock(block, sizeof block, pcm, 505) == 505);
  CHECK(pcm[1] > pcm[0] && pcm[2] > pcm[1]);
}

static void testPlaylist() {
  g_test = "playlist";
  Node n;
  n.sound->boot();
  CHECK(n.speaker.played.empty());
  CHECK(n.state(3, R"({"tracks":["bar-jazz-1.mp3","lost.mp3","bar-jazz-2.mp3"],"shuffle":false,"gapMs":0,"volume":45,"fadeMs":1500})") == Nack::None);
  CHECK_STR(n.speaker.track, "bar-jazz-1.mp3");
  CHECK(n.speaker.trackVol == 45);
  n.finishTrack();
  CHECK_STR(n.speaker.track, "bar-jazz-2.mp3");  // lost.mp3 пропущен
  n.finishTrack();
  CHECK_STR(n.speaker.track, "bar-jazz-1.mp3");  // по кругу
  CHECK(n.status().find("\"missing\":[\"lost.mp3\"]") != std::string::npos);
  CHECK(n.status().find("\"playing\":\"bar-jazz-1.mp3\"") != std::string::npos);
  // Старая версия не принимается, та же — повтор без эффекта.
  CHECK(n.state(2, R"({"tracks":[]})") == Nack::StaleVersion);
  size_t before = n.speaker.played.size();
  CHECK(n.state(3, R"({"tracks":["bar-jazz-1.mp3","lost.mp3","bar-jazz-2.mp3"],"shuffle":false,"gapMs":0,"volume":45,"fadeMs":1500})") == Nack::None);
  CHECK(n.speaker.played.size() == before);
  CHECK(n.state(4, "{not json") == Nack::BadFormat);
  CHECK(n.state(4, R"({"tracks":["../etc/passwd"]})") == Nack::BadFormat);
  CHECK(n.sound->version() == 3);

  // Только громкость — трек не перезапускается.
  CHECK(n.state(5, R"({"tracks":["bar-jazz-1.mp3","lost.mp3","bar-jazz-2.mp3"],"shuffle":false,"gapMs":0,"volume":70,"fadeMs":1500})") == Nack::None);
  CHECK(n.speaker.played.size() == before);
  CHECK(n.speaker.trackVol == 70);

  // Новый канал, где текущий трек тоже есть, — не обрывать его.
  CHECK(n.state(6, R"({"tracks":["radio-1.mp3","bar-jazz-1.mp3"],"shuffle":false,"gapMs":0,"volume":60,"fadeMs":1500})") == Nack::None);
  CHECK(n.speaker.played.size() == before);
  n.finishTrack();
  CHECK_STR(n.speaker.track, "radio-1.mp3");

  // Канал без общего трека — сразу другой.
  CHECK(n.state(7, R"({"tracks":["rain.mp3"],"volume":30})") == Nack::None);
  CHECK_STR(n.speaker.track, "rain.mp3");
  // Тишина.
  CHECK(n.state(8, R"({"tracks":[],"volume":30})") == Nack::None);
  CHECK(!n.speaker.trackOn);
  CHECK(n.status().find("\"playing\":null") != std::string::npos);
}

static void testGapShuffleAndBroken() {
  g_test = "gap-shuffle";
  Node n;
  n.sound->boot();
  CHECK(n.state(1, R"({"tracks":["radio-1.mp3","rain.mp3"],"shuffle":false,"gapMs":3000,"volume":50})") == Nack::None);
  CHECK_STR(n.speaker.track, "radio-1.mp3");
  n.finishTrack();
  CHECK(!n.speaker.trackOn);  // пауза
  n.clock.now += 2999;
  n.sound->tick();
  CHECK(!n.speaker.trackOn);
  n.clock.now += 1;
  n.sound->tick();
  CHECK_STR(n.speaker.track, "rain.mp3");

  // Битый файл — следующий.
  n.speaker.broken = {"ad-arasaka.mp3"};
  CHECK(n.state(2, R"({"tracks":["ad-arasaka.mp3","bar-jazz-2.mp3"],"shuffle":false})") == Nack::None);
  CHECK_STR(n.speaker.track, "bar-jazz-2.mp3");

  // Перемешивание: за круг каждый трек по разу, без повтора на стыке кругов.
  Node m;
  m.sound->boot();
  CHECK(m.state(1, R"({"tracks":["ad-arasaka.mp3","bar-jazz-1.mp3","bar-jazz-2.mp3","radio-1.mp3","rain.mp3"],"shuffle":true})") == Nack::None);
  for (int i = 0; i < 14; i++) m.finishTrack();
  CHECK(m.speaker.played.size() == 15);
  std::set<std::string> round(m.speaker.played.begin(), m.speaker.played.begin() + 5);
  CHECK(round.size() == 5);
  bool repeat = false;
  for (size_t i = 1; i < m.speaker.played.size(); i++) repeat = repeat || m.speaker.played[i] == m.speaker.played[i - 1];
  CHECK(!repeat);
}

static void testPersistAndCard() {
  g_test = "persist";
  Node n;
  n.sound->boot();
  CHECK(n.state(12, R"({"tracks":["rain.mp3","radio-1.mp3"],"shuffle":false,"volume":40})") == Nack::None);
  n.reboot();
  CHECK(n.sound->version() == 12);
  CHECK_STR(n.speaker.track, "rain.mp3");  // фон — сразу после загрузки, до сети
  CHECK(n.speaker.trackVol == 40);
  // Испорченный файл состояния — тишина, версия 0 (сервер пришлёт заново).
  n.storage.files[kAudioFile][20] ^= 0xff;
  n.reboot();
  CHECK(n.sound->version() == 0);
  CHECK(!n.speaker.trackOn);

  g_test = "card";
  Node c;
  c.card.inserted = false;
  c.sound->boot();
  CHECK(c.state(1, R"({"tracks":["rain.mp3"]})") == Nack::None);
  CHECK(!c.speaker.trackOn);
  CHECK(c.status().find("\"sd\":false") != std::string::npos);
  c.card.inserted = true;
  c.sound->tick();
  CHECK_STR(c.speaker.track, "rain.mp3");
  c.card.inserted = false;
  c.sound->tick();
  CHECK(!c.speaker.trackOn);
}

static void testClipAndAnnounce() {
  g_test = "clip";
  Node n;
  n.sound->boot();
  CHECK(n.state(1, R"({"tracks":["radio-1.mp3"],"volume":80})") == Nack::None);
  Bytes clip = wavPcm(2000);  // 64 044 байта — пять кусков
  std::string id = sha(clip);
  uint8_t begin[36];
  for (int i = 0; i < 32; i++) begin[i] = uint8_t(std::stoi(id.substr(size_t(2 * i), 2), nullptr, 16));
  putU32(begin + 32, uint32_t(clip.size()));
  uint32_t have = 99;
  CHECK(n.sound->clipBegin(begin, have) == Nack::None && have == 0);
  auto chunk = [&](uint32_t off, size_t len) {
    Bytes p(4 + len);
    putU32(p.data(), off);
    std::memcpy(p.data() + 4, clip.data() + off, len);
    uint32_t h = 0;
    Nack code = n.sound->clipChunk(p.data(), p.size(), h);
    return code == Nack::None ? h : 0xffffffffu;
  };
  CHECK(chunk(0, 16384) == 16384);
  CHECK(chunk(0, 16384) == 0xffffffffu);  // не с того места
  // Обрыв: новое соединение, BEGIN говорит, сколько уже есть.
  n.sound->resetUpload();
  CHECK(n.sound->clipBegin(begin, have) == Nack::None && have == 16384);
  for (uint32_t off = have; off < clip.size(); off += 16384) CHECK(chunk(off, std::min<size_t>(16384, clip.size() - off)) == std::min<uint32_t>(off + 16384, uint32_t(clip.size())));
  CHECK(n.sound->clipCommit() == Nack::None);
  CHECK(n.card.clips.count(id) == 1);
  // Уже есть — BEGIN отвечает полной длиной.
  n.sound->resetUpload();
  CHECK(n.sound->clipBegin(begin, have) == Nack::None && have == clip.size());

  // Порченый клип: sha256 не сходится — выброшен.
  Bytes bad = clip;
  bad[1000] ^= 1;
  n.sound->resetUpload();
  uint8_t begin2[36];
  std::memcpy(begin2, begin, 32);
  begin2[0] ^= 0xff;  // другой id
  putU32(begin2 + 32, uint32_t(bad.size()));
  CHECK(n.sound->clipBegin(begin2, have) == Nack::None && have == 0);
  Bytes p(4 + 16384);
  for (uint32_t off = 0; off < bad.size(); off += 16384) {
    size_t len = std::min<size_t>(16384, bad.size() - off);
    putU32(p.data(), off);
    std::memcpy(p.data() + 4, bad.data() + off, len);
    uint32_t h;
    CHECK(n.sound->clipChunk(p.data(), 4 + len, h) == Nack::None);
  }
  CHECK(n.sound->clipCommit() == Nack::BadCrc);
  CHECK(n.card.parts.empty());

  g_test = "announce";
  uint32_t duration = 0;
  Bytes missing = str(R"({"clip":")" + std::string(64, 'a') + R"(","volume":90})");
  CHECK(n.sound->announce(5, missing.data(), missing.size(), duration) == Nack::MissingClip);
  Bytes a = str(R"({"clip":")" + id + R"(","volume":90,"chime":true,"duck":25})");
  CHECK(n.sound->announce(77, a.data(), a.size(), duration) == Nack::None);
  CHECK(duration == 2000 + kChimeMs);
  CHECK(n.speaker.clipOn && n.speaker.clipVol == 90 && n.speaker.chime);
  CHECK(n.speaker.trackVol == 20);  // 80 × 25 %
  CHECK(n.status().find("\"ann\":{\"id\":77,\"state\":\"playing\"}") != std::string::npos);
  CHECK(n.status().find("\"playing\":null") != std::string::npos);  // пока объявление — фон не докладывается
  // Трек кончился во время объявления — следующий тоже приглушён.
  n.finishTrack();
  CHECK(n.speaker.trackVol == 20);
  n.speaker.clipOn = false;
  n.sound->tick();
  CHECK(n.speaker.trackVol == 80);
  CHECK(n.status().find("\"state\":\"done\"") != std::string::npos);
  CHECK(n.sound->announce(78, a.data(), a.size(), duration) == Nack::None);
  n.sound->stopAnnounce();
  CHECK(!n.speaker.clipOn);
  CHECK(n.status().find("\"ann\":{\"id\":78,\"state\":\"stopped\"}") != std::string::npos);
}

static void testListAndStatusLimits() {
  g_test = "list";
  Node n;
  n.card.tracks.clear();
  for (int i = 0; i < 70; i++) {
    char name[80];
    std::snprintf(name, sizeof name, "ambient-%02d-cyberpunk-city-at-night.mp3", i);
    n.card.tracks.insert(name);
  }
  std::vector<std::string> all;
  uint16_t start = 0;
  for (int page = 0; page < 10 && all.size() < 70; page++) {
    char out[kListReplyMax + 1];
    size_t len = n.sound->listJson(start, out, sizeof out);
    CHECK(len > 0 && len <= kListReplyMax);
    JsonCursor c(out, len);
    CHECK(c.beginObject());
    char key[16];
    size_t got = 0;
    while (c.nextKey(key, sizeof key)) {
      if (!std::strcmp(key, "names")) {
        CHECK(c.beginArray());
        char name[128];
        while (c.nextItem() && c.readString(name, sizeof name)) {
          all.push_back(name);
          got++;
        }
      } else CHECK(c.skip());
    }
    CHECK(got > 0);
    start = uint16_t(all.size());
  }
  CHECK(all.size() == 70);
  CHECK_STR(all[69], "ambient-69-cyberpunk-city-at-night.mp3");

  g_test = "status-limit";
  // 110 недостающих треков (JSON ≈ 4 КБ — предел команды) — статус всё равно влезает в HELLO и остаётся JSON.
  std::string json = R"({"tracks":[)";
  for (int i = 0; i < 110; i++) json += (i ? ",\"" : "\"") + std::string("missing-track-number-") + std::to_string(i) + ".mp3\"";
  json += "]}";
  n.sound->boot();
  CHECK(n.state(1, json) == Nack::None);
  std::string st = n.status();
  CHECK(!st.empty() && st.size() < 1280);
  if (st.size() >= 1280 || st.empty()) std::printf("status %zu: %.200s\n", st.size(), st.c_str());
  CHECK(st.back() == '}');
}

// Сессия целиком: кадры с подписью, как их шлёт сервер.
struct Wire : Link {
  Bytes sent;
  bool closed = false;
  void send(const uint8_t* d, size_t n) override { sent.insert(sent.end(), d, d + n); }
  void close() override { closed = true; }
};

static void testSession() {
  g_test = "session";
  Node n;
  Config cfg{};
  std::snprintf(cfg.deviceId, sizeof cfg.deviceId, "snd-01");
  for (size_t i = 0; i < kKeySize; i++) cfg.key[i] = uint8_t(i);
  cfg.width = 792;
  cfg.height = 272;
  cfg.audio = true;
  struct : Panel {
    bool show(const uint8_t*, uint16_t, uint16_t) override { return true; }
    bool showText(const char* const*, size_t) override { return true; }
  } panel;
  struct : Backlight {
    void set(uint8_t) override {}
  } backlight;
  Bytes frame(frameBytes(792, 272)), incoming(Device::incomingBytes(cfg));
  CHECK(incoming.size() >= kAudioPayloadMax);
  Device dev(cfg, panel, n.storage, backlight, n.clock, frame.data(), incoming.data());
  dev.attachSound(n.sound);
  n.sound->boot();
  Wire wire;
  Session s(dev, wire);
  // HELLO: nonce из платформы, в статусе — роли и звук.
  CHECK(wire.sent.size() > kHeaderSize + kNonceSize);
  std::string hello(wire.sent.begin() + long(kHeaderSize + kNonceSize), wire.sent.end());
  CHECK(hello.find("\"roles\":[\"display\",\"audio\"]") != std::string::npos);
  CHECK(hello.find("\"audio\":{\"v\":0,") != std::string::npos);
  uint8_t nonce[kNonceSize];
  std::memcpy(nonce, wire.sent.data() + kHeaderSize, kNonceSize);
  auto send = [&](MsgType t, uint32_t seq, const Bytes& payload) {
    wire.sent.clear();
    Bytes out(kHeaderSize + payload.size());
    FrameOut f{t, "snd-01", seq, 792, 272, Format::None, payload.data(), payload.size()};
    CHECK(encodeFrame(f, cfg.key, nonce, out.data(), out.size()) == out.size());
    s.onData(out.data(), out.size());
    CHECK(wire.sent.size() >= kHeaderSize);
    return std::make_pair(wire.sent.size() >= kHeaderSize ? wire.sent[6] : 0, Bytes(wire.sent.begin() + long(kHeaderSize), wire.sent.end()));
  };
  auto r = send(MsgType::AudioState, 4, str(R"({"tracks":["radio-1.mp3"],"volume":55})"));
  CHECK(r.first == uint8_t(MsgType::Ok));
  CHECK(getU32(wire.sent.data() + 40) == 4);  // ответ — с seq запроса
  CHECK_STR(n.speaker.track, "radio-1.mp3");
  r = send(MsgType::AudioState, 3, str(R"({"tracks":[]})"));
  CHECK(r.first == uint8_t(MsgType::Nack) && r.second[0] == uint8_t(Nack::StaleVersion));
  Bytes list(2, 0);
  r = send(MsgType::List, 0, list);
  CHECK(r.first == uint8_t(MsgType::Ok));
  CHECK_STR(std::string(r.second.begin(), r.second.end()).substr(0, 20), "{\"total\":5,\"names\":[");
  Bytes stop;
  r = send(MsgType::AnnounceStop, 0, stop);
  CHECK(r.first == uint8_t(MsgType::Ok));
  // Точка без роли audio отвечает UNSUPPORTED_TYPE.
  PanelState ps{"snd-01", 792, 272, 0, false};
  Header h{};
  std::snprintf(h.deviceId, sizeof h.deviceId, "snd-01");
  h.type = uint8_t(MsgType::AudioState);
  Bytes body = str("{}");
  Bytes framed(kHeaderSize + body.size());
  FrameOut f{MsgType::AudioState, "snd-01", 1, 792, 272, Format::None, body.data(), body.size()};
  encodeFrame(f, cfg.key, nonce, framed.data(), framed.size());
  CHECK(parseHeader(framed.data(), 4096, h) == Nack::None);
  CHECK(validateIncoming(h, framed.data(), framed.data() + kHeaderSize, cfg.key, nonce, ps) == Nack::UnsupportedType);
  ps.audio = true;
  CHECK(validateIncoming(h, framed.data(), framed.data() + kHeaderSize, cfg.key, nonce, ps) == Nack::None);
}

int main() {
  testJson();
  testWav();
  testPlaylist();
  testGapShuffleAndBroken();
  testPersistAndCard();
  testClipAndAnnounce();
  testListAndStatusLimits();
  testSession();
  std::printf("%d checks, %d failed\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}

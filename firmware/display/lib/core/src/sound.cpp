#include "sound.h"

#include <cstdio>
#include <cstring>

#include "crc32.h"
#include "json.h"
#include "sha256.h"
#include "util.h"
#include "wav.h"

namespace mb10d {

const char* const kAudioFile = "audio.bin";

namespace {
const uint8_t kAudioMagic[4] = {'M', 'B', 'A', 'U'};
constexpr size_t kAudioHead = 16;  // MBAU, версия, длина JSON, CRC32 JSON
// Пределы AUDIO_STATE: пауза между треками до 10 мин, переход до 30 с.
constexpr uint32_t kMaxGapMs = 600000;
constexpr uint32_t kMaxFadeMs = 30000;
// Фон на время объявления: приглушить быстро, вернуть плавнее.
constexpr uint32_t kDuckFadeMs = 300;
constexpr uint32_t kUnduckFadeMs = 600;

bool isHexId(const char* s) {
  if (std::strlen(s) != kClipIdLen) return false;
  for (const char* p = s; *p; p++)
    if (!((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f'))) return false;
  return true;
}

// Имя трека — путь внутри /mb10/tracks: без каталогов и управляющих символов (сервер проверяет так же).
bool safeTrackName(const char* s) {
  if (!*s) return false;
  for (const unsigned char* p = reinterpret_cast<const unsigned char*>(s); *p; p++)
    if (*p < 0x20 || *p == '/' || *p == '\\') return false;
  return std::strcmp(s, ".") != 0 && std::strcmp(s, "..") != 0;
}

uint8_t clampPct(double v) { return v < 0 ? 0 : v > 100 ? 100 : uint8_t(v + 0.5); }
}  // namespace

Sound::Sound(SoundCard& card, AudioOut& out, Storage& storage, Platform& platform) : card_(card), out_(out), storage_(storage), platform_(platform) {
  json_[0] = '\0';
  std::memset(missing_, 0, sizeof missing_);
}

uint32_t Sound::rand32() {
  // xorshift32: перемешивание плейлиста, не криптография.
  rng_ ^= rng_ << 13;
  rng_ ^= rng_ >> 17;
  rng_ ^= rng_ << 5;
  return rng_;
}

uint8_t Sound::bgVolume() const { return annState_ == AnnState::Playing ? uint8_t(uint32_t(volume_) * duck_ / 100) : volume_; }

bool Sound::parseState(const char* json, size_t len) {
  JsonCursor c(json, len);
  if (!c.beginObject()) return false;
  char key[16];
  uint16_t count = 0;
  size_t used = 0;
  bool shuffle = false;
  double gap = 0, vol = kDefaultVolume, fade = kDefaultFadeMs;
  static char names[kAudioJsonMax];
  static uint16_t offs[kMaxTracks];
  while (c.nextKey(key, sizeof key)) {
    if (std::strcmp(key, "tracks") == 0) {
      if (!c.beginArray()) return false;
      while (c.nextItem()) {
        char name[kTrackNameMax + 1];
        if (!c.readString(name, sizeof name) || !safeTrackName(name) || count >= kMaxTracks) return false;
        size_t n = std::strlen(name) + 1;
        if (used + n > sizeof names) return false;
        std::memcpy(names + used, name, n);
        offs[count++] = uint16_t(used);
        used += n;
      }
    } else if (std::strcmp(key, "shuffle") == 0) {
      if (!c.readBool(shuffle)) return false;
    } else if (std::strcmp(key, "gapMs") == 0) {
      if (!c.readNumber(gap)) return false;
    } else if (std::strcmp(key, "volume") == 0) {
      if (!c.readNumber(vol)) return false;
    } else if (std::strcmp(key, "fadeMs") == 0) {
      if (!c.readNumber(fade)) return false;
    } else if (!c.skip()) {
      return false;
    }
  }
  if (!c.ok()) return false;
  std::memcpy(names_, names, used);
  std::memcpy(offs_, offs, count * sizeof offs[0]);
  count_ = count;
  shuffle_ = shuffle;
  gapMs_ = gap < 0 ? 0 : gap > kMaxGapMs ? kMaxGapMs : uint32_t(gap);
  fadeMs_ = fade < 0 ? 0 : fade > kMaxFadeMs ? kMaxFadeMs : uint32_t(fade);
  volume_ = clampPct(vol);
  return true;
}

void Sound::refreshMissing() {
  bool present = card_.present();
  for (size_t i = 0; i < count_; i++) missing_[i] = !present || !card_.hasTrack(track(i));
}

// Новый порядок. keep — трек, который сейчас играет и остаётся в канале: он становится «текущим», дальше — остальные.
void Sound::rebuildOrder(const char* keep) {
  for (uint16_t i = 0; i < count_; i++) order_[i] = i;
  if (shuffle_) {
    for (uint16_t i = count_; i > 1; i--) {
      uint16_t j = uint16_t(rand32() % i);
      uint16_t t = order_[i - 1];
      order_[i - 1] = order_[j];
      order_[j] = t;
    }
  }
  pos_ = 0;
  if (keep) {
    for (uint16_t i = 0; i < count_; i++) {
      if (std::strcmp(track(order_[i]), keep) == 0) {
        uint16_t t = order_[0];
        order_[0] = order_[i];
        order_[i] = t;
        pos_ = 1;
        break;
      }
    }
  }
}

void Sound::playNext() {
  if (count_ == 0 || !card_.present()) {
    if (bg_ == Bg::Playing) out_.stopTrack(fadeMs_);
    bg_ = Bg::Silent;
    current_[0] = '\0';
    return;
  }
  for (uint16_t tries = 0; tries < count_; tries++) {
    if (pos_ >= count_) {
      // Круг пройден: при перемешивании — новый порядок, но не тот же трек подряд.
      char last[kTrackNameMax + 1];
      std::snprintf(last, sizeof last, "%s", current_);
      rebuildOrder(nullptr);
      if (shuffle_ && count_ > 1 && std::strcmp(track(order_[0]), last) == 0) {
        uint16_t t = order_[0];
        order_[0] = order_[1];
        order_[1] = t;
      }
    }
    uint16_t idx = order_[pos_++];
    if (missing_[idx]) continue;
    if (out_.startTrack(track(idx), bgVolume(), fadeMs_)) {
      std::snprintf(current_, sizeof current_, "%s", track(idx));
      bg_ = Bg::Playing;
      logFmt(platform_, "audio: track %s vol=%u", current_, unsigned(bgVolume()));
      return;
    }
    logFmt(platform_, "audio: track %s failed to start — skipped", track(idx));
  }
  logFmt(platform_, "audio: no playable tracks in channel — silence");
  bg_ = Bg::Silent;
  current_[0] = '\0';
}

bool Sound::loadSaved() {
  uint8_t head[kAudioHead];
  if (!storage_.read(kAudioFile, 0, head, sizeof head)) {
    logFmt(platform_, "audio boot: no saved state — silence");
    return false;
  }
  uint32_t version = getU32(head + 4), len = getU32(head + 8);
  if (std::memcmp(head, kAudioMagic, 4) != 0 || len > kAudioJsonMax || !storage_.read(kAudioFile, kAudioHead, reinterpret_cast<uint8_t*>(json_), len) ||
      crc32(reinterpret_cast<uint8_t*>(json_), len) != getU32(head + 12) || !parseState(json_, len)) {
    logFmt(platform_, "audio boot: saved state corrupt — ignored");
    json_[0] = '\0';
    return false;
  }
  json_[len] = '\0';
  jsonLen_ = len;
  version_ = version;
  return true;
}

void Sound::save(uint32_t version, const uint8_t* json, size_t len) {
  uint8_t head[kAudioHead];
  std::memcpy(head, kAudioMagic, 4);
  putU32(head + 4, version);
  putU32(head + 8, uint32_t(len));
  putU32(head + 12, crc32(json, len));
  if (!storage_.writeAtomic(kAudioFile, head, sizeof head, json, len)) logFmt(platform_, "audio v%u: state not saved (storage)", unsigned(version));
}

void Sound::unduck() {
  if (bg_ == Bg::Playing) out_.setTrackVolume(volume_, kUnduckFadeMs);
}

void Sound::boot() {
  cardWasPresent_ = card_.present();
  if (!loadSaved()) return;
  uint8_t seed[4];
  platform_.random(seed, sizeof seed);
  rng_ ^= getU32(seed) | 1;
  refreshMissing();
  rebuildOrder(nullptr);
  logFmt(platform_, "audio boot: state v%u, %u tracks, card %s", unsigned(version_), unsigned(count_), cardWasPresent_ ? "present" : "missing");
  playNext();
}

Nack Sound::applyState(uint32_t version, const uint8_t* json, size_t len) {
  if (version < version_) return Nack::StaleVersion;
  if (len > kAudioJsonMax) return Nack::BadLength;
  const char* s = reinterpret_cast<const char*>(json);
  if (version == version_ && len == jsonLen_ && std::memcmp(s, json_, len) == 0) return Nack::None;  // повтор после обрыва
  bool sameList = false;
  uint16_t oldCount = count_;
  bool oldShuffle = shuffle_;
  static char oldNames[kAudioJsonMax];
  static uint16_t oldOffs[kMaxTracks];
  std::memcpy(oldNames, names_, sizeof names_);
  std::memcpy(oldOffs, offs_, sizeof offs_);
  if (!parseState(s, len)) {
    logFmt(platform_, "audio v%u: bad JSON — rejected", unsigned(version));
    return Nack::BadFormat;
  }
  if (oldCount == count_ && oldShuffle == shuffle_) {
    sameList = true;
    for (uint16_t i = 0; i < count_ && sameList; i++) sameList = std::strcmp(oldNames + oldOffs[i], track(i)) == 0;
  }
  // Сначала на flash, потом играть: перезагрузка сразу после OK заиграет уже новое.
  save(version, json, len);
  std::memcpy(json_, s, len);
  json_[len] = '\0';
  jsonLen_ = len;
  version_ = version;
  refreshMissing();
  if (sameList && bg_ != Bg::Silent) {
    out_.setTrackVolume(bgVolume(), fadeMs_);
    logFmt(platform_, "audio v%u: volume %u", unsigned(version), unsigned(volume_));
    return Nack::None;
  }
  // Текущий трек остаётся в новом канале — не обрывать его, дальше по новому списку.
  const char* keep = nullptr;
  if (bg_ == Bg::Playing) {
    for (uint16_t i = 0; i < count_; i++)
      if (!missing_[i] && std::strcmp(track(i), current_) == 0) keep = current_;
  }
  rebuildOrder(keep);
  logFmt(platform_, "audio v%u: %u tracks%s, vol=%u", unsigned(version), unsigned(count_), shuffle_ ? " shuffled" : "", unsigned(volume_));
  if (keep) {
    out_.setTrackVolume(bgVolume(), fadeMs_);
  } else {
    bg_ = Bg::Silent;
    playNext();
    if (bg_ == Bg::Silent) out_.stopTrack(fadeMs_);
  }
  return Nack::None;
}

void Sound::tick() {
  uint32_t now = platform_.nowMs();
  bool present = card_.present();
  if (present != cardWasPresent_) {
    cardWasPresent_ = present;
    logFmt(platform_, "audio: card %s", present ? "inserted" : "removed");
    refreshMissing();
    if (!present) {
      out_.stopTrack(0);
      bg_ = Bg::Silent;
      current_[0] = '\0';
    } else if (bg_ == Bg::Silent) {
      playNext();
    }
  }
  if (annState_ == AnnState::Playing && !out_.clipPlaying()) {
    annState_ = AnnState::Done;
    logFmt(platform_, "announce %u done", unsigned(annId_));
    unduck();
  }
  if (bg_ == Bg::Playing && !out_.trackPlaying()) {
    if (gapMs_ > 0) {
      bg_ = Bg::Gap;
      gapUntil_ = now + gapMs_;
    } else {
      playNext();
    }
  } else if (bg_ == Bg::Gap && reached(now, gapUntil_)) {
    playNext();
  }
}

Nack Sound::clipBegin(const uint8_t* p, uint32_t& have) {
  if (!card_.present()) return Nack::DisplayFailed;
  toHex(p, 32, uploadId_);
  uploadLen_ = getU32(p + 32);
  if (card_.hasClip(uploadId_) && card_.clipSize(uploadId_) == uploadLen_) {
    uploading_ = false;
    have = uploadLen_;
    return Nack::None;
  }
  have = card_.partSize(uploadId_);
  if (have > uploadLen_) {
    card_.removePart(uploadId_);
    have = 0;
  }
  uploading_ = true;
  logFmt(platform_, "clip %.12s: %u of %u bytes already here", uploadId_, unsigned(have), unsigned(uploadLen_));
  return Nack::None;
}

Nack Sound::clipChunk(const uint8_t* p, size_t len, uint32_t& have) {
  if (!uploading_ || len <= 4) return Nack::BadLength;
  uint32_t offset = getU32(p);
  uint32_t part = card_.partSize(uploadId_);
  size_t n = len - 4;
  if (offset != part || offset + n > uploadLen_) return Nack::BadLength;
  if (!card_.writePart(uploadId_, offset, p + 4, n)) return Nack::DisplayFailed;
  have = offset + uint32_t(n);
  return Nack::None;
}

Nack Sound::clipCommit() {
  if (!uploading_) return Nack::BadLength;
  uploading_ = false;
  if (card_.partSize(uploadId_) != uploadLen_) return Nack::BadLength;
  Sha256 sha;
  uint8_t buf[1024];
  for (uint32_t off = 0; off < uploadLen_;) {
    size_t n = uploadLen_ - off < sizeof buf ? uploadLen_ - off : sizeof buf;
    if (!card_.readPart(uploadId_, off, buf, n)) return Nack::DisplayFailed;
    sha.update(buf, n);
    off += uint32_t(n);
    platform_.feedWatchdog();
  }
  uint8_t digest[32];
  sha.finish(digest);
  char hex[kClipIdLen + 1];
  toHex(digest, 32, hex);
  if (std::strcmp(hex, uploadId_) != 0) {
    card_.removePart(uploadId_);
    logFmt(platform_, "clip %.12s: sha256 mismatch — discarded", uploadId_);
    return Nack::BadCrc;
  }
  if (!card_.commitPart(uploadId_)) return Nack::DisplayFailed;
  logFmt(platform_, "clip %.12s: stored, %u bytes", uploadId_, unsigned(uploadLen_));
  return Nack::None;
}

Nack Sound::announce(uint32_t id, const uint8_t* json, size_t len, uint32_t& durationMs) {
  JsonCursor c(reinterpret_cast<const char*>(json), len);
  if (!c.beginObject()) return Nack::BadFormat;
  char key[16], clip[kClipIdLen + 1] = {0};
  double vol = kDefaultAnnounceVolume, duck = kDefaultDuckPct;
  bool chime = true;
  while (c.nextKey(key, sizeof key)) {
    bool ok = std::strcmp(key, "clip") == 0     ? c.readString(clip, sizeof clip)
              : std::strcmp(key, "volume") == 0 ? c.readNumber(vol)
              : std::strcmp(key, "duck") == 0   ? c.readNumber(duck)
              : std::strcmp(key, "chime") == 0  ? c.readBool(chime)
                                                : c.skip();
    if (!ok) return Nack::BadFormat;
  }
  if (!c.ok() || !isHexId(clip)) return Nack::BadFormat;
  if (!card_.present() || !card_.hasClip(clip)) return Nack::MissingClip;
  uint8_t head[128];
  uint32_t size = card_.clipSize(clip);
  size_t headLen = size < sizeof head ? size : sizeof head;
  WavInfo info;
  if (!card_.readClip(clip, 0, head, headLen) || !parseWavHeader(head, headLen, size, info)) return Nack::BadFormat;
  if (annState_ == AnnState::Playing) out_.stopClip();
  annId_ = id;
  duck_ = clampPct(duck);
  if (!out_.startClip(clip, clampPct(vol), chime)) {
    annState_ = AnnState::Failed;
    logFmt(platform_, "announce %u: clip %.12s failed to start", unsigned(id), clip);
    return Nack::DisplayFailed;
  }
  annState_ = AnnState::Playing;
  if (bg_ == Bg::Playing) out_.setTrackVolume(bgVolume(), kDuckFadeMs);
  durationMs = info.durationMs + (chime ? kChimeMs : 0);
  logFmt(platform_, "announce %u: clip %.12s %u ms, background to %u%%", unsigned(id), clip, unsigned(durationMs), unsigned(duck_));
  return Nack::None;
}

void Sound::stopAnnounce() {
  if (annState_ != AnnState::Playing) return;
  out_.stopClip();
  annState_ = AnnState::Stopped;
  unduck();
  logFmt(platform_, "announce %u stopped", unsigned(annId_));
}

size_t Sound::listJson(uint16_t start, char* out, size_t cap) {
  size_t total = card_.present() ? card_.trackCount() : 0;
  int n = std::snprintf(out, cap, "{\"total\":%u,\"names\":[", unsigned(total));
  if (n < 0 || size_t(n) + 3 > cap) return 0;
  size_t len = size_t(n);
  bool first = true;
  for (size_t i = start; i < total; i++) {
    char name[kTrackNameMax + 1];
    if (!card_.trackName(i, name, sizeof name)) break;
    size_t save = len;
    if (!first) {
      if (len + 1 >= cap - 2) break;
      out[len++] = ',';
    }
    // Место под "]}" оставляем.
    if (!jsonAppendString(out, cap - 2, len, name)) {
      len = save;
      break;
    }
    first = false;
  }
  out[len++] = ']';
  out[len++] = '}';
  out[len] = '\0';
  return len;
}

size_t Sound::statusJson(char* out, size_t cap) {
  bool present = card_.present();
  int n = std::snprintf(out, cap, "{\"v\":%u,\"playing\":", unsigned(version_));
  if (n < 0 || size_t(n) >= cap) return 0;
  size_t len = size_t(n);
  auto raw = [&](const char* s) {
    size_t k = std::strlen(s);
    if (len + k + 1 > cap) return false;
    std::memcpy(out + len, s, k + 1);
    len += k;
    return true;
  };
  bool ok = bg_ == Bg::Playing && annState_ != AnnState::Playing ? jsonAppendString(out, cap, len, current_) : raw("null");
  char num[96];
  std::snprintf(num, sizeof num, ",\"vol\":%u,\"tracks\":%u,\"sd\":%s,\"missing\":[", unsigned(volume_), unsigned(present ? card_.trackCount() : 0),
                present ? "true" : "false");
  ok = ok && raw(num);
  // Список недостающих — сколько влезет, оставив место под хвост с объявлением.
  bool first = true;
  for (size_t i = 0; ok && i < count_; i++) {
    if (!missing_[i]) continue;
    size_t save = len;
    if ((!first && !raw(",")) || !jsonAppendString(out, cap > 80 ? cap - 80 : 0, len, track(i))) {
      len = save;
      out[len] = '\0';
      break;
    }
    first = false;
  }
  ok = ok && raw("]");
  if (ok && annState_ != AnnState::None) {
    static const char* names[] = {"", "playing", "done", "failed", "stopped"};
    std::snprintf(num, sizeof num, ",\"ann\":{\"id\":%u,\"state\":\"%s\"}", unsigned(annId_), names[int(annState_)]);
    ok = raw(num);
  }
  ok = ok && raw("}");
  return ok ? len : 0;
}

}  // namespace mb10d

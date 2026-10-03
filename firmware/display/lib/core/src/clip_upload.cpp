// Приём клипа кусками с докачкой (ClipUpload из sound.h): .part на карте, sha256 перед переименованием в .wav.
#include <cstring>

#include "sha256.h"
#include "sound.h"
#include "util.h"

namespace mb10d {

namespace {
constexpr size_t kDigestSize = kClipIdLen / 2;  // sha256 — 32 байта
}  // namespace

bool isClipId(const char* s) {
  if (std::strlen(s) != kClipIdLen) return false;
  for (const char* p = s; *p; p++)
    if (!((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f'))) return false;
  return true;
}

Nack ClipUpload::begin(const uint8_t* p, uint32_t& have) {
  if (!card_.present()) return Nack::DisplayFailed;
  toHex(p, kDigestSize, id_);
  len_ = getU32(p + kDigestSize);
  if (card_.hasClip(id_) && card_.clipSize(id_) == len_) {
    active_ = false;
    have = len_;
    return Nack::None;
  }
  have = card_.partSize(id_);
  if (have > len_) {
    card_.removePart(id_);
    have = 0;
  }
  active_ = true;
  logFmt(platform_, "clip %.12s: %u of %u bytes already here", id_, unsigned(have), unsigned(len_));
  return Nack::None;
}

Nack ClipUpload::chunk(const uint8_t* p, size_t len, uint32_t& have) {
  if (!active_ || len <= 4) return Nack::BadLength;
  uint32_t offset = getU32(p);
  uint32_t part = card_.partSize(id_);
  size_t n = len - 4;
  if (offset != part || offset + n > len_) return Nack::BadLength;
  if (!card_.writePart(id_, offset, p + 4, n)) return Nack::DisplayFailed;
  have = offset + uint32_t(n);
  return Nack::None;
}

Nack ClipUpload::commit() {
  if (!active_) return Nack::BadLength;
  active_ = false;
  if (card_.partSize(id_) != len_) return Nack::BadLength;
  Sha256 sha;
  uint8_t buf[1024];
  for (uint32_t off = 0; off < len_;) {
    size_t n = len_ - off < sizeof buf ? len_ - off : sizeof buf;
    if (!card_.readPart(id_, off, buf, n)) return Nack::DisplayFailed;
    sha.update(buf, n);
    off += uint32_t(n);
    platform_.feedWatchdog();
  }
  uint8_t digest[kDigestSize];
  sha.finish(digest);
  char hex[kClipIdLen + 1];
  toHex(digest, kDigestSize, hex);
  if (std::strcmp(hex, id_) != 0) {
    card_.removePart(id_);
    logFmt(platform_, "clip %.12s: sha256 mismatch — discarded", id_);
    return Nack::BadCrc;
  }
  if (!card_.commitPart(id_)) return Nack::DisplayFailed;
  logFmt(platform_, "clip %.12s: stored, %u bytes", id_, unsigned(len_));
  return Nack::None;
}

}  // namespace mb10d

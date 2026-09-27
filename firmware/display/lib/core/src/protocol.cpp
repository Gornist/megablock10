#include "protocol.h"

#include <cstring>

#include "crc32.h"
#include "sha256.h"

namespace mb10d {

const uint8_t kMagic[5] = {'M', 'B', '1', '0', 'D'};

const char* nackName(Nack code) {
  switch (code) {
    case Nack::None: return "OK";
    case Nack::BadMagic: return "BAD_MAGIC";
    case Nack::BadVersion: return "BAD_VERSION";
    case Nack::BadLength: return "BAD_LENGTH";
    case Nack::BadCrc: return "BAD_CRC";
    case Nack::AuthFailed: return "AUTH_FAILED";
    case Nack::StaleVersion: return "STALE_VERSION";
    case Nack::BadFormat: return "BAD_FORMAT";
    case Nack::WrongDevice: return "WRONG_DEVICE";
    case Nack::Busy: return "BUSY";
    case Nack::DisplayFailed: return "DISPLAY_FAILED";
    case Nack::UnsupportedType: return "UNSUPPORTED_TYPE";
  }
  return "NACK_?";
}

uint16_t getU16(const uint8_t* p) { return uint16_t(p[0] << 8 | p[1]); }
uint32_t getU32(const uint8_t* p) { return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3]; }
void putU16(uint8_t* p, uint16_t v) {
  p[0] = uint8_t(v >> 8);
  p[1] = uint8_t(v);
}
void putU32(uint8_t* p, uint32_t v) {
  p[0] = uint8_t(v >> 24);
  p[1] = uint8_t(v >> 16);
  p[2] = uint8_t(v >> 8);
  p[3] = uint8_t(v);
}

Nack parseHeader(const uint8_t* b, uint32_t maxPayload, Header& out) {
  if (std::memcmp(b, kMagic, sizeof kMagic) != 0) return Nack::BadMagic;
  out.version = b[5];
  if (out.version != kProtocolVersion) return Nack::BadVersion;
  out.payloadLength = getU32(b + 52);
  if (out.payloadLength > maxPayload) return Nack::BadLength;
  out.type = b[6];
  out.flags = b[7];
  std::memcpy(out.deviceId, b + 8, kDeviceIdSize);
  out.deviceId[kDeviceIdSize] = '\0';
  out.seq = getU32(b + 40);
  out.width = getU16(b + 44);
  out.height = getU16(b + 46);
  out.format = b[48];
  out.crc32 = getU32(b + 56);
  std::memcpy(out.hmac, b + kHmacOffset, kHmacSize);
  return Nack::None;
}

void computeHmac(const uint8_t* key, const uint8_t* nonce, const uint8_t* signedHeader, const uint8_t* payload, size_t len, uint8_t out[32]) {
  HmacSha256 mac(key, kKeySize);
  mac.update(nonce, kNonceSize);
  mac.update(signedHeader, kHmacOffset);
  if (len > 0) mac.update(payload, len);
  mac.finish(out);
}

Nack checkIntegrity(const Header& h, const uint8_t* signedHeader, const uint8_t* payload, const uint8_t* key, const uint8_t* nonce) {
  if (crc32(payload, h.payloadLength) != h.crc32) return Nack::BadCrc;
  uint8_t expected[kHmacSize];
  computeHmac(key, nonce, signedHeader, payload, h.payloadLength, expected);
  return equalConstantTime(expected, h.hmac, kHmacSize) ? Nack::None : Nack::AuthFailed;
}

Nack validateIncoming(const Header& h, const uint8_t* signedHeader, const uint8_t* payload, const uint8_t* key, const uint8_t* nonce,
                      const PanelState& panel) {
  if (std::strncmp(h.deviceId, panel.deviceId, kDeviceIdSize) != 0) return Nack::WrongDevice;
  Nack integrity = checkIntegrity(h, signedHeader, payload, key, nonce);
  if (integrity != Nack::None) return integrity;
  switch (static_cast<MsgType>(h.type)) {
    case MsgType::Image:
      if (h.format != uint8_t(Format::Bpp1) || h.width != panel.width || h.height != panel.height ||
          h.payloadLength != frameBytes(panel.width, panel.height)) {
        return Nack::BadFormat;
      }
      if (h.seq <= panel.displayedVersion) return Nack::StaleVersion;
      return Nack::None;
    case MsgType::Test:
      return h.payloadLength == 2 ? Nack::None : Nack::BadLength;
    case MsgType::Backlight:
      return h.payloadLength == 3 && payload[0] <= uint8_t(BacklightLevel::High) ? Nack::None : Nack::BadLength;
    case MsgType::Reboot:
      return Nack::None;
    default:
      return Nack::UnsupportedType;
  }
}

size_t encodeFrame(const FrameOut& f, const uint8_t* key, const uint8_t* nonce, uint8_t* out, size_t cap) {
  size_t idLen = std::strlen(f.deviceId);
  size_t total = kHeaderSize + f.payloadLength;
  if (idLen > kDeviceIdSize || total > cap) return 0;
  std::memset(out, 0, kHeaderSize);
  std::memcpy(out, kMagic, sizeof kMagic);
  out[5] = kProtocolVersion;
  out[6] = uint8_t(f.type);
  std::memcpy(out + 8, f.deviceId, idLen);
  putU32(out + 40, f.seq);
  putU16(out + 44, f.width);
  putU16(out + 46, f.height);
  out[48] = uint8_t(f.format);
  putU32(out + 52, uint32_t(f.payloadLength));
  if (f.payloadLength > 0) std::memmove(out + kHeaderSize, f.payload, f.payloadLength);
  putU32(out + 56, crc32(out + kHeaderSize, f.payloadLength));
  computeHmac(key, nonce, out, out + kHeaderSize, f.payloadLength, out + kHmacOffset);
  return total;
}

namespace {
int hexDigit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}
}  // namespace

bool parseHex(const char* hex, uint8_t* out, size_t outLen) {
  if (!hex || std::strlen(hex) != outLen * 2) return false;
  for (size_t i = 0; i < outLen; i++) {
    int hi = hexDigit(hex[2 * i]), lo = hexDigit(hex[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = uint8_t(hi << 4 | lo);
  }
  return true;
}

}  // namespace mb10d

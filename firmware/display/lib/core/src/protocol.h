#pragma once
#include <cstddef>
#include <cstdint>

// Протокол «сервер мастера ↔ QR-дисплей» v1 — зеркало admin-web/server/src/displays/protocol.ts, описание — docs/displays.md.
// Совпадение байт в байт закреплено общими векторами test/vectors/protocol-v1.json.
namespace mb10d {

constexpr uint8_t kProtocolVersion = 1;
constexpr size_t kHeaderSize = 92;
constexpr size_t kDeviceIdSize = 32;
constexpr size_t kNonceSize = 16;
constexpr size_t kKeySize = 32;
constexpr size_t kHmacOffset = 60;
constexpr size_t kHmacSize = 32;
extern const uint8_t kMagic[5];

enum class MsgType : uint8_t {
  Hello = 0x01,
  Image = 0x10,
  Test = 0x11,
  Backlight = 0x12,
  Reboot = 0x13,
  // Звук (docs/sound-nodes.md) — только у точки с ролью audio; остальные отвечают UNSUPPORTED_TYPE.
  AudioState = 0x14,
  ClipBegin = 0x15,
  ClipChunk = 0x16,
  ClipCommit = 0x17,
  Announce = 0x18,
  AnnounceStop = 0x19,
  List = 0x1a,
  Received = 0x20,
  Displayed = 0x21,
  Nack = 0x22,
  Ok = 0x23,
};

// None — «принято». Коды совпадают с NackCode на сервере.
enum class Nack : uint8_t {
  None = 0,
  BadMagic = 1,
  BadVersion = 2,
  BadLength = 3,
  BadCrc = 4,
  AuthFailed = 5,
  StaleVersion = 6,
  BadFormat = 7,
  WrongDevice = 8,
  Busy = 9,
  DisplayFailed = 10,
  UnsupportedType = 11,
  MissingClip = 12,
};

enum class Format : uint8_t { None = 0, Bpp1 = 1 };

enum class BacklightLevel : uint8_t { Off = 0, Low = 1, Medium = 2, High = 3 };

const char* nackName(Nack code);

struct Header {
  uint8_t version;
  uint8_t type;
  uint8_t flags;
  char deviceId[kDeviceIdSize + 1];
  uint32_t seq;
  uint16_t width;
  uint16_t height;
  uint8_t format;
  uint32_t payloadLength;
  uint32_t crc32;
  uint8_t hmac[kHmacSize];
};

struct PanelState {
  const char* deviceId;
  uint16_t width;
  uint16_t height;
  uint32_t displayedVersion;
  // Точка со звуком: принимает AUDIO_STATE, CLIP_*, ANNOUNCE*, LIST.
  bool audio = false;
};

inline size_t frameStride(uint16_t width) { return (size_t(width) + 7) / 8; }
inline size_t frameBytes(uint16_t width, uint16_t height) { return frameStride(width) * height; }

uint16_t getU16(const uint8_t* p);
uint32_t getU32(const uint8_t* p);
void putU16(uint8_t* p, uint16_t v);
void putU32(uint8_t* p, uint32_t v);

// Первые 92 байта: MAGIC, версия протокола, длина payload ≤ maxPayload (размер приёмного буфера дисплея). Не None — граница
// кадра потеряна: ответить NACK и закрыть соединение.
Nack parseHeader(const uint8_t* bytes, uint32_t maxPayload, Header& out);

// HMAC-SHA256(key, nonce ‖ 60 байт заголовка ‖ payload).
void computeHmac(const uint8_t* key, const uint8_t* nonce, const uint8_t* signedHeader, const uint8_t* payload, size_t len, uint8_t out[32]);

// CRC, затем подпись: CRC отличает порчу по дороге (сервер повторит) от чужого секрета (повторять бесполезно).
Nack checkIntegrity(const Header& h, const uint8_t* signedHeader, const uint8_t* payload, const uint8_t* key, const uint8_t* nonce);

// Проверка входящего кадра на дисплее в порядке docs/displays.md: id → CRC → подпись → тип (формат, размер, версия).
Nack validateIncoming(const Header& h, const uint8_t* signedHeader, const uint8_t* payload, const uint8_t* key, const uint8_t* nonce,
                      const PanelState& panel);

struct FrameOut {
  MsgType type;
  const char* deviceId;
  uint32_t seq;
  uint16_t width;
  uint16_t height;
  Format format;
  const uint8_t* payload;
  size_t payloadLength;
};

// Собрать и подписать кадр в out. Возвращает длину или 0, если не влезло (или id длиннее 32 байт).
size_t encodeFrame(const FrameOut& f, const uint8_t* key, const uint8_t* nonce, uint8_t* out, size_t cap);

// «Декодер» hex-строки секрета из настроек (64 символа → 32 байта). false — не hex или не та длина.
bool parseHex(const char* hex, uint8_t* out, size_t outLen);

}  // namespace mb10d

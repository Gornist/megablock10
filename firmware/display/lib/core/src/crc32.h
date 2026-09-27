#pragma once
#include <cstddef>
#include <cstdint>

namespace mb10d {

// CRC32 IEEE 802.3 (полином 0xEDB88320, как у zlib) — та же таблица, что в admin-web/server/src/displays/protocol.ts.
// crc32("123456789") == 0xCBF43926.
uint32_t crc32(const uint8_t* data, size_t len);

// По частям: state = crc32Begin(); state = crc32Update(state, …); crc32End(state).
inline uint32_t crc32Begin() { return 0xFFFFFFFFu; }
uint32_t crc32Update(uint32_t state, const uint8_t* data, size_t len);
inline uint32_t crc32End(uint32_t state) { return state ^ 0xFFFFFFFFu; }

}  // namespace mb10d

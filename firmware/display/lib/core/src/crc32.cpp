#include "crc32.h"

namespace mb10d {

namespace {
struct Table {
  uint32_t v[256];
  Table() {
    for (uint32_t n = 0; n < 256; n++) {
      uint32_t c = n;
      for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
      v[n] = c;
    }
  }
};
const Table& table() {
  static const Table t;
  return t;
}
}  // namespace

uint32_t crc32Update(uint32_t state, const uint8_t* data, size_t len) {
  const Table& t = table();
  for (size_t i = 0; i < len; i++) state = t.v[(state ^ data[i]) & 0xFF] ^ (state >> 8);
  return state;
}

uint32_t crc32(const uint8_t* data, size_t len) { return crc32End(crc32Update(crc32Begin(), data, len)); }

}  // namespace mb10d

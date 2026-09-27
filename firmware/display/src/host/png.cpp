#include "png.h"

#include <cstdio>
#include <vector>

#include "crc32.h"
#include "protocol.h"

namespace host {

namespace {
void be32(std::vector<uint8_t>& v, uint32_t x) {
  v.push_back(uint8_t(x >> 24));
  v.push_back(uint8_t(x >> 16));
  v.push_back(uint8_t(x >> 8));
  v.push_back(uint8_t(x));
}

void chunk(std::vector<uint8_t>& out, const char* type, const std::vector<uint8_t>& data) {
  be32(out, uint32_t(data.size()));
  std::vector<uint8_t> body(type, type + 4);
  body.insert(body.end(), data.begin(), data.end());
  out.insert(out.end(), body.begin(), body.end());
  be32(out, mb10d::crc32(body.data(), body.size()));
}
}  // namespace

// PNG 1 бит оттенков серого без zlib: deflate из «сохранённых» (несжатых) блоков — файл больше, зато ноль зависимостей.
// В кадре 1 — чёрный, в PNG 1 — белый, поэтому биты инвертируются.
bool writePng(const char* path, const uint8_t* frame, uint16_t width, uint16_t height) {
  size_t stride = mb10d::frameStride(width);
  std::vector<uint8_t> raw;
  raw.reserve((stride + 1) * height);
  for (uint16_t y = 0; y < height; y++) {
    raw.push_back(0);
    for (size_t i = 0; i < stride; i++) raw.push_back(uint8_t(~frame[y * stride + i]));
  }
  std::vector<uint8_t> z = {0x78, 0x01};
  uint32_t a = 1, b = 0;
  for (uint8_t c : raw) {
    a = (a + c) % 65521;
    b = (b + a) % 65521;
  }
  for (size_t pos = 0; pos < raw.size() || pos == 0;) {
    size_t n = raw.size() - pos > 65535 ? 65535 : raw.size() - pos;
    bool last = pos + n == raw.size();
    z.push_back(last ? 1 : 0);
    z.push_back(uint8_t(n));
    z.push_back(uint8_t(n >> 8));
    z.push_back(uint8_t(~n));
    z.push_back(uint8_t(~n >> 8));
    z.insert(z.end(), raw.begin() + long(pos), raw.begin() + long(pos + n));
    pos += n;
    if (last) break;
  }
  be32(z, (b << 16) | a);

  std::vector<uint8_t> ihdr;
  be32(ihdr, width);
  be32(ihdr, height);
  ihdr.insert(ihdr.end(), {1, 0, 0, 0, 0});
  std::vector<uint8_t> out = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  chunk(out, "IHDR", ihdr);
  chunk(out, "IDAT", z);
  chunk(out, "IEND", {});

  std::string tmp = std::string(path) + ".tmp";
  FILE* f = std::fopen(tmp.c_str(), "wb");
  if (!f) return false;
  bool ok = std::fwrite(out.data(), 1, out.size(), f) == out.size();
  ok = std::fclose(f) == 0 && ok;
  return ok && std::rename(tmp.c_str(), path) == 0;
}

}  // namespace host

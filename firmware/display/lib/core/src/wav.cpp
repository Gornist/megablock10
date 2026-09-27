#include "wav.h"

#include <cstring>

namespace mb10d {

namespace {
uint16_t le16(const uint8_t* p) { return uint16_t(p[0] | p[1] << 8); }
uint32_t le32(const uint8_t* p) { return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24; }

const int16_t kSteps[89] = {7,     8,     9,     10,    11,    12,    13,    14,    16,    17,    19,    21,    23,    25,    28,
                            31,    34,    37,    41,    45,    50,    55,    60,    66,    73,    80,    88,    97,    107,   118,
                            130,   143,   157,   173,   190,   209,   230,   253,   279,   307,   337,   371,   408,   449,   494,
                            544,   598,   658,   724,   796,   876,   963,   1060,  1166,  1282,  1411,  1552,  1707,  1878,  2066,
                            2272,  2499,  2749,  3024,  3327,  3660,  4026,  4428,  4871,  5358,  5894,  6484,  7132,  7845,  8630,
                            9493,  10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767};
const int8_t kIndexAdjust[16] = {-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8};
}  // namespace

bool parseWavHeader(const uint8_t* b, size_t len, uint32_t fileSize, WavInfo& out) {
  if (len < 44 || std::memcmp(b, "RIFF", 4) != 0 || std::memcmp(b + 8, "WAVE", 4) != 0) return false;
  size_t off = 12;
  bool haveFmt = false;
  uint16_t channels = 0, bits = 0;
  while (off + 8 <= len) {
    uint32_t size = le32(b + off + 4);
    size_t body = off + 8;
    if (std::memcmp(b + off, "fmt ", 4) == 0 && size >= 16 && body + 16 <= len) {
      out.format = le16(b + body);
      channels = le16(b + body + 2);
      out.sampleRate = le32(b + body + 4);
      out.blockAlign = le16(b + body + 12);
      bits = le16(b + body + 14);
      out.samplesPerBlock = out.format == kWavImaAdpcm && size >= 20 && body + 20 <= len ? le16(b + body + 18) : 1;
      haveFmt = true;
    } else if (std::memcmp(b + off, "data", 4) == 0 && haveFmt) {
      bool ok = channels == 1 && out.sampleRate >= 8000 && out.sampleRate <= 48000 &&
                ((out.format == kWavPcm && bits == 16) ||
                 (out.format == kWavImaAdpcm && bits == 4 && out.blockAlign > 4 && out.samplesPerBlock == (out.blockAlign - 4) * 2 + 1));
      if (!ok) return false;
      out.dataOffset = uint32_t(body);
      out.dataBytes = fileSize > body ? (size < fileSize - body ? size : fileSize - uint32_t(body)) : 0;
      out.samples = out.format == kWavPcm ? out.dataBytes / 2 : out.dataBytes / out.blockAlign * out.samplesPerBlock;
      out.durationMs = uint32_t(uint64_t(out.samples) * 1000 / out.sampleRate);
      return true;
    }
    off = body + size + (size & 1);
  }
  return false;
}

size_t decodeImaBlock(const uint8_t* block, size_t blockBytes, int16_t* out, size_t outCap) {
  if (blockBytes < 4 || outCap == 0) return 0;
  int32_t pred = int16_t(le16(block));
  int index = block[2] > 88 ? 88 : block[2];
  size_t n = 0;
  out[n++] = int16_t(pred);
  for (size_t i = 4; i < blockBytes && n < outCap; i++) {
    for (int half = 0; half < 2 && n < outCap; half++) {
      uint8_t code = half ? block[i] >> 4 : block[i] & 15;
      int32_t step = kSteps[index];
      int32_t delta = step >> 3;
      if (code & 4) delta += step;
      if (code & 2) delta += step >> 1;
      if (code & 1) delta += step >> 2;
      pred += code & 8 ? -delta : delta;
      if (pred > 32767) pred = 32767;
      if (pred < -32768) pred = -32768;
      index += kIndexAdjust[code];
      if (index < 0) index = 0;
      if (index > 88) index = 88;
      out[n++] = int16_t(pred);
    }
  }
  return n;
}

}  // namespace mb10d

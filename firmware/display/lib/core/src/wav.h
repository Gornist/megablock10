#pragma once
#include <cstddef>
#include <cstdint>

// Клип громкой связи — WAV, который пишет коллектор (admin-web/client/src/screens/audio/wavEncoder.ts): IMA ADPCM 4 бит,
// моно, 16 кГц, блок 256 байт = 505 сэмплов; принимается и PCM 16 бит моно (зеркало admin-web/server/src/audio/wav.ts).
namespace mb10d {

constexpr uint16_t kWavPcm = 1;
constexpr uint16_t kWavImaAdpcm = 0x11;

struct WavInfo {
  uint16_t format = 0;
  uint32_t sampleRate = 0;
  uint16_t blockAlign = 0;
  uint16_t samplesPerBlock = 0;
  uint32_t dataOffset = 0;
  uint32_t dataBytes = 0;
  uint32_t samples = 0;
  uint32_t durationMs = 0;
};

// По началу файла (достаточно первых 128 байт: fmt, fact, заголовок data). false — не WAV или формат, который точка не играет.
bool parseWavHeader(const uint8_t* head, size_t len, uint32_t fileSize, WavInfo& out);

// Декодер IMA ADPCM по блокам: блок blockAlign байт → samplesPerBlock сэмплов. Возвращает, сколько записано в out.
size_t decodeImaBlock(const uint8_t* block, size_t blockBytes, int16_t* out, size_t outCap);

}  // namespace mb10d

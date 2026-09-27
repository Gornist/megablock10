#pragma once
#include <cstdint>
#include <string>

namespace host {
// Кадр «панели» на ПК — PNG, который можно открыть и отсканировать телефоном или декодировать в тесте.
bool writePng(const char* path, const uint8_t* frame, uint16_t width, uint16_t height);
}  // namespace host

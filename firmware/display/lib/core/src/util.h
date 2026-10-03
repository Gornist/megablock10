#pragma once
#include <cstddef>
#include <cstdint>

#include "hal.h"

// Мелочи, общие для модулей ядра: время millis() с переполнением, журнал через Platform, hex.
namespace mb10d {

// «Наступил ли момент t» с учётом переполнения millis() (≈49 суток).
inline bool reached(uint32_t now, uint32_t t) { return int32_t(now - t) >= 0; }
// «Прошло ли не меньше ms с момента since» — так же через переполнение.
inline bool elapsed(uint32_t now, uint32_t since, uint32_t ms) { return int32_t(now - since) >= int32_t(ms); }

// Строка журнала по формату printf (до 200 байт, длиннее — обрезается).
void logFmt(Platform& platform, const char* fmt, ...) __attribute__((format(printf, 2, 3)));

// n байт → 2n строчных hex-символов и '\0' (out — не меньше 2n+1).
void toHex(const uint8_t* p, size_t n, char* out);

}  // namespace mb10d

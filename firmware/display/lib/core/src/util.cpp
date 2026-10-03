#include "util.h"

#include <cstdarg>
#include <cstdio>

namespace mb10d {

void logFmt(Platform& platform, const char* fmt, ...) {
  char line[200];
  va_list ap;
  va_start(ap, fmt);
  std::vsnprintf(line, sizeof line, fmt, ap);
  va_end(ap);
  platform.log(line);
}

void toHex(const uint8_t* p, size_t n, char* out) {
  static const char* d = "0123456789abcdef";
  for (size_t i = 0; i < n; i++) {
    out[2 * i] = d[p[i] >> 4];
    out[2 * i + 1] = d[p[i] & 15];
  }
  out[2 * n] = '\0';
}

}  // namespace mb10d

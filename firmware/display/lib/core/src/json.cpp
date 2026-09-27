#include "json.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace mb10d {

void JsonCursor::ws() {
  while (p_ < end_ && (*p_ == ' ' || *p_ == '\t' || *p_ == '\n' || *p_ == '\r')) p_++;
}

bool JsonCursor::lit(const char* word) {
  size_t n = std::strlen(word);
  if (size_t(end_ - p_) < n || std::memcmp(p_, word, n) != 0) return ok_ = false;
  p_ += n;
  return true;
}

bool JsonCursor::push() {
  if (depth_ >= kDepth) return ok_ = false;
  first_[depth_++] = true;
  return true;
}

bool JsonCursor::beginObject() {
  ws();
  if (p_ >= end_ || *p_ != '{') return ok_ = false;
  p_++;
  return push();
}

bool JsonCursor::nextKey(char* key, size_t cap) {
  if (!ok_) return false;
  ws();
  if (p_ < end_ && *p_ == '}') {
    p_++;
    if (depth_ > 0) depth_--;
    return false;
  }
  if (!first()) {
    if (p_ >= end_ || *p_ != ',') return ok_ = false;
    p_++;
    ws();
  }
  first() = false;
  if (!readString(key, cap)) return false;
  ws();
  if (p_ >= end_ || *p_ != ':') return ok_ = false;
  p_++;
  return true;
}

bool JsonCursor::beginArray() {
  ws();
  if (p_ >= end_ || *p_ != '[') return ok_ = false;
  p_++;
  return push();
}

bool JsonCursor::nextItem() {
  if (!ok_) return false;
  ws();
  if (p_ < end_ && *p_ == ']') {
    p_++;
    if (depth_ > 0) depth_--;
    return false;
  }
  if (!first()) {
    if (p_ >= end_ || *p_ != ',') return ok_ = false;
    p_++;
  }
  first() = false;
  return true;
}

namespace {
int hexv(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}
}  // namespace

bool JsonCursor::readString(char* out, size_t cap) {
  ws();
  if (p_ >= end_ || *p_ != '"' || cap == 0) return ok_ = false;
  p_++;
  size_t n = 0;
  auto put = [&](char c) {
    if (n + 1 >= cap) return false;
    out[n++] = c;
    return true;
  };
  while (p_ < end_ && *p_ != '"') {
    char c = *p_++;
    if (c == '\\') {
      if (p_ >= end_) return ok_ = false;
      char e = *p_++;
      uint32_t cp = 0;
      switch (e) {
        case '"': case '\\': case '/': cp = uint8_t(e); break;
        case 'b': cp = '\b'; break;
        case 'f': cp = '\f'; break;
        case 'n': cp = '\n'; break;
        case 'r': cp = '\r'; break;
        case 't': cp = '\t'; break;
        case 'u': {
          if (end_ - p_ < 4) return ok_ = false;
          for (int i = 0; i < 4; i++) {
            int v = hexv(*p_++);
            if (v < 0) return ok_ = false;
            cp = cp << 4 | uint32_t(v);
          }
          // Суррогатная пара — вторая половина следом.
          if (cp >= 0xD800 && cp < 0xDC00 && end_ - p_ >= 6 && p_[0] == '\\' && p_[1] == 'u') {
            uint32_t lo = 0;
            for (int i = 2; i < 6; i++) {
              int v = hexv(p_[i]);
              if (v < 0) return ok_ = false;
              lo = lo << 4 | uint32_t(v);
            }
            if (lo >= 0xDC00 && lo < 0xE000) {
              p_ += 6;
              cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            }
          }
          break;
        }
        default: return ok_ = false;
      }
      bool fits = true;
      if (cp < 0x80) fits = put(char(cp));
      else if (cp < 0x800) fits = put(char(0xC0 | cp >> 6)) && put(char(0x80 | (cp & 0x3F)));
      else if (cp < 0x10000) fits = put(char(0xE0 | cp >> 12)) && put(char(0x80 | (cp >> 6 & 0x3F))) && put(char(0x80 | (cp & 0x3F)));
      else fits = put(char(0xF0 | cp >> 18)) && put(char(0x80 | (cp >> 12 & 0x3F))) && put(char(0x80 | (cp >> 6 & 0x3F))) && put(char(0x80 | (cp & 0x3F)));
      if (!fits) return ok_ = false;
    } else if (!put(c)) {
      return ok_ = false;
    }
  }
  if (p_ >= end_) return ok_ = false;
  p_++;
  out[n] = '\0';
  return true;
}

bool JsonCursor::readNumber(double& out) {
  ws();
  char buf[32];
  size_t n = 0;
  while (p_ < end_ && n + 1 < sizeof buf && (std::strchr("+-0123456789.eE", *p_) != nullptr)) buf[n++] = *p_++;
  buf[n] = '\0';
  if (n == 0) return ok_ = false;
  char* stop = nullptr;
  out = std::strtod(buf, &stop);
  if (stop != buf + n) return ok_ = false;
  return true;
}

bool JsonCursor::readBool(bool& out) {
  ws();
  if (p_ < end_ && *p_ == 't') return lit("true") && (out = true, true);
  if (p_ < end_ && *p_ == 'f') return lit("false") && (out = false, true);
  return ok_ = false;
}

bool JsonCursor::skip() {
  ws();
  if (p_ >= end_) return ok_ = false;
  char c = *p_;
  if (c == '"') {
    char sink[512];
    // Длинную строку пропускаем без буфера: до закрывающей кавычки, учитывая экранирование.
    const char* save = p_;
    if (readString(sink, sizeof sink)) return true;
    p_ = save + 1;
    ok_ = true;
    while (p_ < end_ && *p_ != '"') p_ += *p_ == '\\' ? 2 : 1;
    if (p_ >= end_) return ok_ = false;
    p_++;
    return true;
  }
  if (c == '{' || c == '[') {
    int depth = 0;
    bool inStr = false;
    while (p_ < end_) {
      char d = *p_++;
      if (inStr) {
        if (d == '\\') p_++;
        else if (d == '"') inStr = false;
      } else if (d == '"') inStr = true;
      else if (d == '{' || d == '[') depth++;
      else if (d == '}' || d == ']') {
        if (--depth == 0) return true;
      }
    }
    return ok_ = false;
  }
  if (c == 't' || c == 'f') {
    bool b;
    return readBool(b);
  }
  if (c == 'n') return lit("null");
  double d;
  return readNumber(d);
}

bool jsonAppendString(char* out, size_t cap, size_t& len, const char* s) {
  size_t n = len;
  auto put = [&](char c) {
    if (n + 1 >= cap) return false;
    out[n++] = c;
    return true;
  };
  if (!put('"')) return false;
  for (const unsigned char* p = reinterpret_cast<const unsigned char*>(s); *p; p++) {
    bool fits;
    if (*p == '"' || *p == '\\') fits = put('\\') && put(char(*p));
    else if (*p < 0x20) {
      char esc[8];
      std::snprintf(esc, sizeof esc, "\\u%04x", unsigned(*p));
      fits = true;
      for (const char* e = esc; *e && fits; e++) fits = put(*e);
    } else fits = put(char(*p));
    if (!fits) return false;
  }
  if (!put('"')) return false;
  out[n] = '\0';
  len = n;
  return true;
}

}  // namespace mb10d

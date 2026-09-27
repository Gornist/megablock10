#pragma once
#include <cstddef>
#include <cstdint>

namespace mb10d {

// SHA-256 и HMAC-SHA256 без зависимостей: одна и та же реализация на ESP32 и на ПК (на ESP32 кадр 27 КБ считается за
// миллисекунды и без аппаратного ускорителя). Проверяется векторами RFC 4231 и общими векторами протокола.
class Sha256 {
 public:
  Sha256() { reset(); }
  void reset();
  void update(const uint8_t* data, size_t len);
  void finish(uint8_t out[32]);

 private:
  void block(const uint8_t* p);
  uint32_t h_[8];
  uint8_t buf_[64];
  size_t bufLen_;
  uint64_t total_;
};

class HmacSha256 {
 public:
  HmacSha256(const uint8_t* key, size_t keyLen);
  void update(const uint8_t* data, size_t len) { inner_.update(data, len); }
  void finish(uint8_t out[32]);

 private:
  Sha256 inner_;
  uint8_t opad_[64];
};

// Сравнение за постоянное время — подпись не должна выдавать, сколько байт совпало.
bool equalConstantTime(const uint8_t* a, const uint8_t* b, size_t len);

}  // namespace mb10d

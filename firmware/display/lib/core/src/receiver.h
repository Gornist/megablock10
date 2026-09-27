#pragma once
#include <cstddef>
#include <cstdint>

#include "protocol.h"

namespace mb10d {

// Сборка кадров из TCP-потока, пришедшего кусками произвольной длины. Заголовок проверяется, как только пришли его 92 байта
// (MAGIC, версия, длина ≤ буфера) — битую длину не ждём до таймаута. Payload пишется в чужой буфер (у дисплея он один на
// кадр панели и отдельный от показанного кадра: отвергнутый кадр не портит то, что на экране).
class Receiver {
 public:
  enum class Event { NeedMore, Frame, Error };

  Receiver(uint8_t* payloadBuf, size_t capacity) : payload_(payloadBuf), cap_(capacity) {}

  // Съедает из data не больше, чем нужно до конца одного кадра; consumed — сколько съедено.
  // Frame — кадр готов (header(), signedHeader(), payload()); после обработки — next().
  // Error — граница кадра потеряна (error()): ответить NACK и закрыть соединение.
  Event feed(const uint8_t* data, size_t len, size_t& consumed);

  void next();
  // Начат, но не дочитан кадр — отсчитывается таймаут payload.
  bool partial() const { return have_ > 0; }

  const Header& header() const { return h_; }
  const uint8_t* signedHeader() const { return hdr_; }
  const uint8_t* payload() const { return payload_; }
  Nack error() const { return error_; }

 private:
  uint8_t hdr_[kHeaderSize];
  uint8_t* payload_;
  size_t cap_;
  size_t have_ = 0;
  bool ready_ = false;
  Header h_{};
  Nack error_ = Nack::None;
};

}  // namespace mb10d

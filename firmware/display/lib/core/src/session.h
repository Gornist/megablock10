#pragma once
#include <cstddef>
#include <cstdint>

#include "device.h"
#include "protocol.h"
#include "receiver.h"

namespace mb10d {

// HELLO и ответы: статус звуковой точки со списком недостающих треков длиннее прежних 256 байт.
constexpr size_t kReplyPayloadMax = 1280;

// Отправка байтов в TCP и закрытие — у платы lwIP, у ПК POSIX-сокет.
class Link {
 public:
  virtual ~Link() = default;
  virtual void send(const uint8_t* data, size_t len) = 0;
  virtual void close() = 0;
};

// Одно TCP-соединение: HELLO с новым nonce → приём кадров → проверки → ответы. Обработка синхронная: пока обновляется панель,
// следующий кадр ждёт в буфере TCP и проверяется уже против новой версии (очередь, а не BUSY — оба варианта допустимы, C20).
class Session {
 public:
  Session(Device& device, Link& link);
  void onData(const uint8_t* data, size_t len);
  // Таймауты: молчание без начатого кадра — headerTimeoutMs, начатый кадр — payloadTimeoutMs.
  void poll();
  bool closed() const { return closed_; }

 private:
  void handle();
  void handleAudio();
  void reply(MsgType type, uint32_t seq, const uint8_t* payload = nullptr, size_t len = 0);
  void nack(Nack code);
  void close(const char* why);
  Device& device_;
  Link& link_;
  Receiver receiver_;
  uint8_t nonce_[kNonceSize];
  uint32_t lastActivity_;
  uint32_t frameStarted_ = 0;
  bool inFrame_ = false;
  bool closed_ = false;
};

}  // namespace mb10d

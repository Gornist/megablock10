#pragma once
#include <cstdint>

namespace mb10d {

// Повторное подключение к Wi-Fi: 1, 2, 4, 8, 16, 30, 30… с, сброс после успеха (docs/displays.md).
class Backoff {
 public:
  uint32_t next();
  void reset() { step_ = 0; }

 private:
  uint8_t step_ = 0;
};

// Wi-Fi как машина состояний без самого Wi-Fi: CONNECTING → ONLINE; обрыв или неудача → BACKOFF → CONNECTING.
class Connectivity {
 public:
  enum class State { Connecting, Online, Backoff };
  enum class Action { None, StartConnect, Disconnected };
  explicit Connectivity(uint32_t connectTimeoutMs = 15000) : connectTimeoutMs_(connectTimeoutMs) {}
  // Вызывать в цикле с текущим состоянием линка; StartConnect — начать подключение (WiFi.begin).
  Action update(bool linkUp, uint32_t now);
  State state() const { return state_; }
  uint32_t retryAt() const { return retryAt_; }

 private:
  State state_ = State::Backoff;
  uint32_t connectTimeoutMs_;
  uint32_t since_ = 0;
  uint32_t retryAt_ = 0;
  bool started_ = false;
  Backoff backoff_;
};

}  // namespace mb10d

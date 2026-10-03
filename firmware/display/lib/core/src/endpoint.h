#pragma once
#include <cstddef>
#include <cstdint>
#include <memory>

#include "device.h"
#include "session.h"

namespace mb10d {

// Сокеты драйвера: слушающий и соединения с сервером мастера (у платы — WiFiServer/WiFiClient, у ПК — POSIX).
// Ни один вызов не ждёт: цикл прошивки один, пока он стоит, не идут ни таймауты, ни приём новых соединений.
class Transport {
 public:
  virtual ~Transport() = default;
  // Новое входящее соединение или nullptr.
  virtual Link* accept() = 0;
  // Есть ли у link что прочитать сейчас: байты или закрытие собеседником (тогда read вернёт 0). Состояние — на момент вызова.
  virtual bool readable(Link& link) = 0;
  // Только после readable(link) == true: прочитать до cap байт; 0 — соединение закрыто или сломано.
  virtual size_t read(Link& link, uint8_t* buf, size_t cap) = 0;
  // Закрыть и освободить link. graceful — FIN и дочитать непрочитанное, чтобы последний ответ (NACK) дошёл; иначе — сразу.
  virtual void release(Link* link, bool graceful) = 0;
};

// Одно обслуживаемое соединение (docs/displays.md, «Транспорт и сессия»): новое вытесняет старое, молчащее закрывается по
// таймауту сессии. Общий цикл для платы и ПК — раньше у каждого драйвера был свой, и у ПК он зависал (step()).
class Endpoint {
 public:
  Endpoint(Device& device, Transport& transport) : device_(device), transport_(transport) {}
  ~Endpoint() { drop(); }
  Endpoint(const Endpoint&) = delete;
  Endpoint& operator=(const Endpoint&) = delete;
  // Один проход цикла: принять новое соединение, прочитать доступное, проверить таймауты, закрыть отработавшее.
  void step();
  // Закрыть текущее соединение (обрыв Wi-Fi, перезагрузка).
  void drop();
  bool connected() const { return link_ != nullptr; }

 private:
  Device& device_;
  Transport& transport_;
  Link* link_ = nullptr;
  std::unique_ptr<Session> session_;
};

}  // namespace mb10d

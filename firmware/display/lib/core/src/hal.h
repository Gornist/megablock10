#pragma once
#include <cstddef>
#include <cstdint>

// Всё, чем плата отличается от ПК, — за этими интерфейсами. Реализации: src/esp32 (CrowPanel) и src/host (программа для ПК).
// В ядре (lib/core) нет ни одного #ifdef платформы.
namespace mb10d {

// Экран. show блокирует до конца обновления e-paper (секунды); false — панель не обновилась.
class Panel {
 public:
  virtual ~Panel() = default;
  virtual bool show(const uint8_t* frame, uint16_t width, uint16_t height) = 0;
  // Диагностический экран (TEST): строки текста сверху вниз.
  virtual bool showText(const char* const* lines, size_t count) = 0;
};

// Постоянная память (LittleFS на плате, каталог на ПК). writeAtomic: либо целиком новое содержимое, либо старое — даже если
// питание пропало посреди записи (временный файл + rename). Две части — чтобы не склеивать заголовок и 27 КБ кадра.
class Storage {
 public:
  virtual ~Storage() = default;
  virtual bool writeAtomic(const char* name, const uint8_t* a, size_t aLen, const uint8_t* b, size_t bLen) = 0;
  // Прочитать len байт с offset; false — нет файла или он короче.
  virtual bool read(const char* name, size_t offset, uint8_t* buf, size_t len) = 0;
};

class Backlight {
 public:
  virtual ~Backlight() = default;
  // 0 — выключена … 3 — ярко (BacklightLevel).
  virtual void set(uint8_t level) = 0;
};

// Остальное от платформы: время, случайность, сведения для HELLO и TEST, журнал, перезагрузка.
class Platform {
 public:
  virtual ~Platform() = default;
  virtual uint32_t nowMs() = 0;
  // Криптографически случайные байты (аппаратный RNG на ESP32) — nonce соединения.
  virtual void random(uint8_t* out, size_t len) = 0;
  // Сторож: сбросить таймер (перед и после долгих операций вроде обновления панели).
  virtual void feedWatchdog() = 0;
  // Перезагрузка «как по питанию»: после неё кадр восстанавливается из Storage.
  virtual void reboot() = 0;
  virtual void log(const char* line) = 0;
  virtual const char* firmwareVersion() = 0;
  virtual const char* hardwareId() = 0;
  // Пустая строка — адреса нет.
  virtual const char* ipAddress() = 0;
  // 0 — неизвестно.
  virtual int rssi() = 0;
  // < 0 — измерения нет на этой плате.
  virtual int batteryMillivolts() = 0;
};

}  // namespace mb10d

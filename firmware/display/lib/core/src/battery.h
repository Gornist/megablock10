#pragma once
#include <cstdint>

// Заряд батареи точки (docs/sound-nodes.md, «Батарея»): топливомер MAX17048 по I²C или делитель на АЦП. Здесь — только
// арифметика регистров и кривая Li-ion, без Arduino; чтение I²C — в драйвере платы (src/esp32).
namespace mb10d {

// Что доложить в HELLO. Отрицательное — нет измерения: поле в JSON не пишется.
struct BatteryStatus {
  int milliVolts = -1;
  // Заряд, % (0…100); -1 — топливомера нет, процент посчитает сервер по напряжению.
  int percent = -1;
  // Скорость, десятые % в час (минус — разряд); есть только у топливомера.
  int rateTenthsPerHour = 0;
  bool hasRate = false;
};

namespace max17048 {
constexpr uint8_t kAddress = 0x36;
constexpr uint8_t kRegVcell = 0x02;
constexpr uint8_t kRegSoc = 0x04;
constexpr uint8_t kRegVersion = 0x08;
constexpr uint8_t kRegCrate = 0x16;

// VCELL: 78,125 мкВ на единицу → мВ.
int milliVolts(uint16_t vcell);
// SOC: старший байт — целые %, младший — 1/256 %; округление до целого, 0…100 (топливомер бывает чуть выше 100).
int percent(uint16_t soc);
// CRATE: знаковое, 0,208 % в час на единицу → десятые % в час.
int rateTenthsPerHour(uint16_t crate);
// VERSION у MAX17048/49 — 0x001X: по нему отличаем топливомер от чужого устройства на том же адресе.
bool versionOk(uint16_t version);
}  // namespace max17048

// Типичная кривая разряда Li-ion (напряжение без нагрузки) — для имитации в прошивке для ПК и делителя без топливомера.
// Та же таблица — на сервере (admin-web/server/src/displays/battery.ts), по ней он считает % из милливольт.
int liionPercentFromMilliVolts(int mv);
int liionMilliVoltsFromPercent(int percent);

}  // namespace mb10d

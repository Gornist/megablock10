// Топливомер MAX17048 по I²C (docs/sound-nodes.md, «Батарея»): доработка платы — модуль на гребёнке, SDA 8 / SCL 9, питание от
// «+» пачки 21700. Нет модуля — fuelGaugeBegin() вернёт false, и заряд меряется делителем (если задан) или не шлётся вовсе.
#include <Wire.h>

#include "battery.h"
#include "board.h"

#ifndef MB10_I2C_SDA
#define MB10_I2C_SDA 8
#endif
#ifndef MB10_I2C_SCL
#define MB10_I2C_SCL 9
#endif

using namespace mb10d;

namespace {

bool present = false;
uint32_t readAt = 0;
BatteryStatus cached;

bool read16(uint8_t reg, uint16_t& out) {
  Wire.beginTransmission(max17048::kAddress);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(uint8_t(max17048::kAddress), uint8_t(2)) != 2) return false;
  uint16_t hi = Wire.read();
  out = uint16_t(hi << 8 | Wire.read());
  return true;
}

}  // namespace

bool mb10esp::fuelGaugeBegin() {
#if MB10_I2C_SDA < 0
  return false;  // вывод 8 занят делителем (MB10_BATTERY_ADC_PIN)
#endif
  Wire.begin(MB10_I2C_SDA, MB10_I2C_SCL, 100000);
  Wire.setTimeOut(20);
  uint16_t version = 0;
  present = read16(max17048::kRegVersion, version) && max17048::versionOk(version);
  char line[64];
  snprintf(line, sizeof line, present ? "battery: MAX17048 version 0x%04x" : "battery: no MAX17048 on I2C (0x%04x)", version);
  logLine(line);
  return present;
}

bool mb10esp::fuelGaugeRead(BatteryStatus& out) {
  if (!present) return false;
  // HELLO бывает на каждом соединении — I²C не чаще раза в 5 с; топливомер сам обновляет значения раз в секунды.
  if (readAt != 0 && millis() - readAt < 5000) {
    out = cached;
    return true;
  }
  uint16_t vcell, soc, crate;
  if (!read16(max17048::kRegVcell, vcell) || !read16(max17048::kRegSoc, soc)) return false;
  cached.milliVolts = max17048::milliVolts(vcell);
  cached.percent = max17048::percent(soc);
  cached.hasRate = read16(max17048::kRegCrate, crate);
  cached.rateTenthsPerHour = cached.hasRate ? max17048::rateTenthsPerHour(crate) : 0;
  readAt = millis();
  out = cached;
  return true;
}

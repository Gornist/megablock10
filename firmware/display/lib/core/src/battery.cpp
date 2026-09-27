#include "battery.h"

namespace mb10d {

namespace max17048 {

int milliVolts(uint16_t vcell) { return int((uint64_t(vcell) * 78125u + 500000u) / 1000000u); }  // 65535 × 78125 > 2³²

int percent(uint16_t soc) {
  int p = int((uint32_t(soc) + 128u) >> 8);
  return p > 100 ? 100 : p;
}

int rateTenthsPerHour(uint16_t crate) {
  int32_t raw = int16_t(crate);
  // 0,208 %/ч = 2,08 десятых: ×208 / 100, с округлением от нуля.
  int32_t scaled = raw * 208;
  return int(scaled >= 0 ? (scaled + 50) / 100 : (scaled - 50) / 100);
}

bool versionOk(uint16_t version) { return (version & 0xFFF0u) == 0x0010u; }

}  // namespace max17048

namespace {
// Напряжение → заряд (типичный элемент 21700 без нагрузки), по убыванию.
struct Point {
  int mv;
  int pct;
};
const Point kCurve[] = {{4200, 100}, {4150, 95}, {4110, 90}, {4080, 85}, {4020, 80}, {3980, 75}, {3950, 70},
                        {3910, 65},  {3870, 60}, {3850, 55}, {3840, 50}, {3820, 45}, {3800, 40}, {3790, 35},
                        {3770, 30},  {3750, 25}, {3730, 20}, {3710, 15}, {3690, 10}, {3610, 5},  {3270, 0}};
constexpr int kPoints = sizeof kCurve / sizeof kCurve[0];
}  // namespace

int liionPercentFromMilliVolts(int mv) {
  if (mv >= kCurve[0].mv) return 100;
  if (mv <= kCurve[kPoints - 1].mv) return 0;
  for (int i = 1; i < kPoints; i++) {
    if (mv >= kCurve[i].mv) {
      const Point& hi = kCurve[i - 1];
      const Point& lo = kCurve[i];
      return lo.pct + ((mv - lo.mv) * (hi.pct - lo.pct) + (hi.mv - lo.mv) / 2) / (hi.mv - lo.mv);
    }
  }
  return 0;
}

int liionMilliVoltsFromPercent(int percent) {
  if (percent >= 100) return kCurve[0].mv;
  if (percent <= 0) return kCurve[kPoints - 1].mv;
  for (int i = 1; i < kPoints; i++) {
    if (percent >= kCurve[i].pct) {
      const Point& hi = kCurve[i - 1];
      const Point& lo = kCurve[i];
      return lo.mv + ((percent - lo.pct) * (hi.mv - lo.mv) + (hi.pct - lo.pct) / 2) / (hi.pct - lo.pct);
    }
  }
  return kCurve[kPoints - 1].mv;
}

}  // namespace mb10d

#include "device.h"

#include <cstdio>
#include <cstring>

#include "crc32.h"
#include "util.h"

namespace mb10d {

const char* const kFrameFile = "frame.bin";

namespace {
const uint8_t kStoredMagic[4] = {'M', 'B', 'F', 'B'};
}  // namespace

Device::Device(const Config& cfg, Panel& panel, Storage& storage, Backlight& backlight, Platform& platform, uint8_t* frame, uint8_t* incoming)
    : cfg_(cfg), panel_(panel), storage_(storage), backlight_(backlight), platform_(platform), frame_(frame), incoming_(incoming) {}

void Device::boot() {
  backlight_.set(0);  // по умолчанию при загрузке подсветка выключена
  uint8_t head[kStoredHeaderSize];
  size_t size = frameSize();
  if (!storage_.read(kFrameFile, 0, head, sizeof head)) {
    logFmt(platform_, "boot: no stored frame, screen stays as is");
    return;
  }
  uint32_t version = getU32(head + 4);
  if (std::memcmp(head, kStoredMagic, 4) != 0 || getU16(head + 8) != cfg_.width || getU16(head + 10) != cfg_.height || getU32(head + 12) != size) {
    logFmt(platform_, "boot: stored frame is for another panel or corrupt — ignored");
    return;
  }
  if (!storage_.read(kFrameFile, kStoredHeaderSize, frame_, size) || crc32(frame_, size) != getU32(head + 16)) {
    logFmt(platform_, "boot: stored frame %u failed CRC — ignored", unsigned(version));
    return;
  }
  displayed_ = version;
  hasFrame_ = true;
  logFmt(platform_, "boot: restoring frame %u", unsigned(version));
  platform_.feedWatchdog();
  // e-paper обычно и так держит этот кадр; перерисовка — на случай, если панель сбросилась без питания.
  if (!panel_.show(frame_, cfg_.width, cfg_.height)) logFmt(platform_, "boot: panel update failed");
  platform_.feedWatchdog();
}

bool Device::showImage(uint32_t version, const uint8_t* data) {
  size_t size = frameSize();
  uint8_t head[kStoredHeaderSize];
  std::memcpy(head, kStoredMagic, 4);
  putU32(head + 4, version);
  putU16(head + 8, cfg_.width);
  putU16(head + 10, cfg_.height);
  putU32(head + 12, uint32_t(size));
  putU32(head + 16, crc32(data, size));
  platform_.feedWatchdog();
  // Сначала flash, потом панель: перезагрузка посреди обновления восстановит уже новый кадр, а не старый.
  if (!storage_.writeAtomic(kFrameFile, head, sizeof head, data, size)) {
    logFmt(platform_, "image %u: storage write failed", unsigned(version));
    return false;
  }
  platform_.feedWatchdog();
  bool ok = panel_.show(data, cfg_.width, cfg_.height);
  platform_.feedWatchdog();
  if (!ok) {
    logFmt(platform_, "image %u: panel update failed", unsigned(version));
    return false;
  }
  if (data != frame_) std::memcpy(frame_, data, size);
  displayed_ = version;
  hasFrame_ = true;
  testShown_ = false;
  logFmt(platform_, "image %u displayed", unsigned(version));
  return true;
}

void Device::showTest(uint16_t seconds) {
  char l1[48], l2[48], l3[48], l4[48], l5[48], l6[48];
  std::snprintf(l1, sizeof l1, "DISPLAY TEST");
  std::snprintf(l2, sizeof l2, "ID: %s", cfg_.deviceId);
  std::snprintf(l3, sizeof l3, "WiFi: %s", platform_.ipAddress()[0] ? "OK" : "--");
  std::snprintf(l4, sizeof l4, "IP: %s", platform_.ipAddress()[0] ? platform_.ipAddress() : "--");
  std::snprintf(l5, sizeof l5, "RSSI: %d dBm", platform_.rssi());
  std::snprintf(l6, sizeof l6, "FW: %s  QR v%u", platform_.firmwareVersion(), unsigned(displayed_));
  const char* lines[] = {l1, l2, l3, l4, l5, l6};
  logFmt(platform_, "test screen for %u s", unsigned(seconds));
  platform_.feedWatchdog();
  panel_.showText(lines, 6);
  platform_.feedWatchdog();
  testShown_ = true;
  testUntil_ = platform_.nowMs() + uint32_t(seconds) * 1000;
}

void Device::setBacklight(uint8_t level, uint16_t seconds) {
  backlight_level_ = level;
  backlight_.set(level);
  backlightTimer_ = level > 0 && seconds > 0;
  if (backlightTimer_) backlightOffAt_ = platform_.nowMs() + uint32_t(seconds) * 1000;
  logFmt(platform_, "backlight %u for %u s", unsigned(level), unsigned(seconds));
}

void Device::tick() {
  if (Sound* snd = sound()) snd->tick();
  uint32_t now = platform_.nowMs();
  if (backlightTimer_ && reached(now, backlightOffAt_)) {
    backlightTimer_ = false;
    backlight_level_ = 0;
    backlight_.set(0);
    logFmt(platform_, "backlight off by timer");
  }
  if (testShown_ && reached(now, testUntil_)) {
    testShown_ = false;
    if (hasFrame_) {
      logFmt(platform_, "test screen over — back to frame %u", unsigned(displayed_));
      platform_.feedWatchdog();
      panel_.show(frame_, cfg_.width, cfg_.height);
      platform_.feedWatchdog();
    }
  }
}

size_t Device::statusJson(char* out, size_t cap) {
  int n = std::snprintf(out, cap, "{\"fw\":\"%s\",\"hw\":\"%s\"", platform_.firmwareVersion(), platform_.hardwareId());
  auto append = [&](const char* fmt, auto value) {
    if (n >= 0 && size_t(n) < cap) n += std::snprintf(out + n, cap - size_t(n), fmt, value);
  };
  if (platform_.ipAddress()[0]) append(",\"ip\":\"%s\"", platform_.ipAddress());
  if (platform_.rssi() != 0) append(",\"rssi\":%d", platform_.rssi());
  BatteryStatus bat = platform_.battery();
  if (bat.milliVolts >= 0) append(",\"batteryMv\":%d", bat.milliVolts);
  // Процент и скорость — только с топливомером; без него JSON прежний (общие векторы с сервером).
  if (bat.percent >= 0) append(",\"batteryPct\":%d", bat.percent);
  if (bat.hasRate) {
    int r = bat.rateTenthsPerHour, a = r < 0 ? -r : r;
    append(",\"batteryRate\":%s", r < 0 ? "-" : "");
    append("%d", a / 10);
    append(".%d", a % 10);
  }
  append(",\"backlight\":%u", unsigned(backlight_level_));
  if (Sound* snd = sound()) {
    append("%s", ",\"roles\":[\"display\",\"audio\"],\"audio\":");
    if (n >= 0 && size_t(n) < cap) {
      size_t k = snd->statusJson(out + n, cap - size_t(n));
      if (k == 0) append("%s", "{}");
      else n += int(k);
    }
  }
  append("%s", "}");
  return n < 0 || size_t(n) >= cap ? 0 : size_t(n);
}

}  // namespace mb10d

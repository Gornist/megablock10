// Самопроверка изнутри платы — только в сборке для эмулятора Wokwi (crowpanel579-wokwi, -DMB10_SELFTEST; docs/firmware-plan.md, Ф4).
#ifdef MB10_SELFTEST
#include <Preferences.h>
#include <WiFi.h>
#include <esp_system.h>

#include "board.h"
#include "selftest.h"

using namespace mb10d;
using namespace mb10esp;

volatile bool mb10esp::selftestHang = false;

namespace {
Settings settings;  // копия настроек платы: задача живёт дольше setup()

// ── Самопроверка в Wokwi (docs/firmware-plan.md, Ф4) ──
// Wokwi не пробрасывает порт к плате снаружи, поэтому клиент протокола (lib/selftest, тот же, что display_selftest на ПК)
// крутится в своей задаче и стучится в TCP-сервер этой же платы через 127.0.0.1. Фазы переживают перезагрузки в NVS:
//   0 — Wi-Fi, проверки протокола, REBOOT;  1 — после программной перезагрузки кадр и версия восстановлены, затем цикл
//   зависает;  2 — сброс сторожем (ESP_RST_TASK_WDT), кадр и версия снова восстановлены → SELFTEST ALL PASSED.
constexpr char kSelftestId[] = "selftest-wokwi";
constexpr char kSelftestSecret[] = "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a";
}  // namespace

Settings mb10esp::selftestSettings() {
  Settings s;
  snprintf(s.cfg.deviceId, sizeof s.cfg.deviceId, "%s", kSelftestId);
  parseHex(kSelftestSecret, s.cfg.key, sizeof s.cfg.key);
  s.cfg.width = 792;  // дисплеи висят горизонтально
  s.cfg.height = 272;
  s.ssid = "Wokwi-GUEST";
  s.channel = 6;
  s.configured = true;
  return s;
}

namespace {

void selftestTask(void*) {
  Preferences nvs;
  nvs.begin("mb10st", false);
  uint8_t phase = nvs.getUChar("phase", 0);
  uint32_t version = nvs.getULong("ver", 0);
  esp_reset_reason_t reason = esp_reset_reason();
  Serial.printf("SELFTEST info: фаза %u, причина сброса %d, ожидаемая версия %lu\n", phase, int(reason), static_cast<unsigned long>(version));

  selftest::Target t{};
  t.host = "127.0.0.1";
  t.port = settings.port;
  t.deviceId = settings.cfg.deviceId;
  memcpy(t.key, settings.cfg.key, sizeof t.key);
  t.width = settings.cfg.width;
  t.height = settings.cfg.height;
  t.headerTimeoutMs = settings.cfg.headerTimeoutMs;
  t.payloadTimeoutMs = settings.cfg.payloadTimeoutMs;
  uint8_t* work = static_cast<uint8_t*>(malloc(selftest::Runner::workSize(t.width, t.height)));
  selftest::Runner runner(t, work, [](const char* line, void*) { logLine(line); }, nullptr);
  bool finished = false;
  if (!work) {
    runner.fail("memory", "нет памяти под кадр самопроверки");
  } else if (phase == 0) {
    uint32_t until = millis() + 30000;
    while (WiFi.status() != WL_CONNECTED && int32_t(until - millis()) > 0) delay(100);
    if (WiFi.status() == WL_CONNECTED) runner.pass("wifi");
    else runner.fail("wifi", "не подключились к %s за 30 с", settings.ssid.c_str());
    if (runner.runProtocol() == 0 && runner.failures() == 0) {
      nvs.putUChar("phase", 1);
      nvs.putULong("ver", runner.displayed());
      runner.reboot();  // дальше — фаза 1 после загрузки
    }
  } else if (phase == 1) {
    if (reason == ESP_RST_SW) runner.pass("reboot-reason");
    else runner.fail("reboot-reason", "причина сброса %d, ждали ESP_RST_SW", int(reason));
    if (runner.expectVersion("reboot-restores-frame", version, 30000) && runner.failures() == 0) {
      nvs.putUChar("phase", 2);
      logLine("SELFTEST info: вешаем основной цикл — ждём сброса сторожем");
      selftestHang = true;
    }
  } else if (phase == 2) {
    if (reason == ESP_RST_TASK_WDT) runner.pass("watchdog-reset");
    else runner.fail("watchdog-reset", "причина сброса %d, ждали ESP_RST_TASK_WDT (%d)", int(reason), int(ESP_RST_TASK_WDT));
    runner.expectVersion("watchdog-restores-frame", version, 30000);
    nvs.putUChar("phase", 3);
    finished = true;
  } else {
    logLine("SELFTEST info: самопроверка уже прошла; заново — стереть flash");
  }
  nvs.end();
  free(work);
  if (runner.failures() > 0) Serial.printf("SELFTEST DONE: %d FAIL\n", runner.failures());
  else if (finished) logLine("SELFTEST ALL PASSED");
  vTaskDelete(nullptr);
}

}  // namespace

void mb10esp::startSelftest(const Settings& s) {
  settings = s;
  xTaskCreatePinnedToCore(selftestTask, "selftest", 8192, nullptr, 1, nullptr, 0);
}
#endif

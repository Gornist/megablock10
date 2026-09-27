#pragma once
// Общее для файлов прошивки платы (src/esp32): журнал, настройки из NVS, самопроверка для Wokwi.
#include <Arduino.h>

#include "device.h"

namespace mb10esp {

constexpr uint16_t kDefaultPort = 47200;

// Строка журнала в USB-консоль: «[millis] текст».
void logLine(const char* line);

struct Settings {
  bool configured = false;
  mb10d::Config cfg{};
  uint16_t port = kDefaultPort;
  String ssid, pass;
  // Канал Wi-Fi: 0 — искать самой (у Wokwi-GUEST — 6, с ним подключение быстрее).
  int channel = 0;
  // Необязательный статический адрес (иначе DHCP с резервом на роутере).
  String ip, gateway, subnet, dns;
};

// Настройки из NVS; configured = false — плата ещё не настроена (ждёт `config {…}` в USB-консоли).
Settings loadSettings();
// Строка из дашборда (DisplaySecretResponse.provisioning + Wi-Fi) → NVS. false — в error, что не так.
bool saveSettingsJson(const char* json, String& error);

#ifdef MB10_SELFTEST
// Сборка для Wokwi: вшитые настройки и самопроверка изнутри платы (selftest_task.cpp).
Settings selftestSettings();
void startSelftest(const Settings& settings);
// Самопроверка просит основной цикл зависнуть — проверить сброс сторожем.
extern volatile bool selftestHang;
#endif

}  // namespace mb10esp

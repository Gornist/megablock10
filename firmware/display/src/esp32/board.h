#pragma once
// Общее для файлов прошивки платы (src/esp32): журнал, настройки из NVS, самопроверка для Wokwi.
#include <Arduino.h>

#include "battery.h"
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

// Топливомер MAX17048 (fuel_gauge.cpp): false — модуля нет на I²C.
bool fuelGaugeBegin();
bool fuelGaugeRead(mb10d::BatteryStatus& out);

// Звук (audio.cpp): карта microSD и вывод I²S. audioBegin — смонтировать карту и запустить задачу звука; audioPoll — из
// основного цикла (карту вставили/вынули).
mb10d::SoundCard& audioCard();
mb10d::AudioOut* audioBegin();
void audioPoll();

#ifdef MB10_SELFTEST
// Сборка для Wokwi: вшитые настройки и самопроверка изнутри платы (selftest_task.cpp).
Settings selftestSettings();
void startSelftest(const Settings& settings);
// Самопроверка просит основной цикл зависнуть — проверить сброс сторожем.
extern volatile bool selftestHang;
// Звук в самопроверке: положить трек на карту; сколько сэмплов декодировал MP3 с загрузки.
bool audioWriteTrack(const char* name, const uint8_t* data, size_t len);
uint32_t audioDecodedSamples();
#endif

}  // namespace mb10esp

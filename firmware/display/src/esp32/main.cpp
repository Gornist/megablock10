// Прошивка QR-дисплея для CrowPanel 5.79″ (ESP32-S3 + e-paper 792×272). Вся логика протокола, проверок и состояния — в ядре
// lib/core (то же, что проверено сборкой для ПК и набором совместимости C1–C20); здесь только драйверы платы: панель (GxEPD2),
// Wi-Fi, TCP-сервер (lwIP), LittleFS, сторож, подсветка, кнопка, USB-консоль (docs/displays.md). Настройки в NVS —
// settings.cpp, самопроверка для Wokwi — selftest_task.cpp, общее между ними — board.h.
//
// Порядок загрузки: питание панели → кадр из flash на экран → Wi-Fi → TCP-сервер. Без сети QR остаётся на экране.
#include <Arduino.h>
#include <LittleFS.h>
#include <SPI.h>
#include <WiFi.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#if __has_include(<esp_random.h>)
#include <esp_random.h>
#endif
#include <esp_wifi.h>
#include <lwip/sockets.h>

#include "board.h"
#include "crc32.h"
#include "device.h"
#include "protocol.h"

#ifndef MB10_PANEL_STUB
#include <Fonts/FreeMonoBold12pt7b.h>
#include <GxEPD2_BW.h>
#endif

using namespace mb10d;
using namespace mb10esp;

// Журнал в USB-консоль с отметкой времени — общий для всех файлов платы (board.h).
void mb10esp::logLine(const char* line) {
  Serial.printf("[%lu] %s\n", static_cast<unsigned long>(millis()), line);
}

namespace {

#ifdef MB10_SELFTEST
// Самопроверка вешает цикл нарочно — ждать сторожа 30 с в эмуляторе незачем.
constexpr uint32_t kWatchdogSeconds = 5;
#else
constexpr uint32_t kWatchdogSeconds = 30;
#endif
constexpr uint16_t kButtonBacklightSeconds = 15;

// ── Панель ──

#ifndef MB10_PANEL_STUB
GxEPD2_BW<GxEPD2_579_GDEY0579T93, GxEPD2_579_GDEY0579T93::HEIGHT> epd(GxEPD2_579_GDEY0579T93(MB10_EPD_CS, MB10_EPD_DC, MB10_EPD_RST, MB10_EPD_BUSY));

void feedDuringBusy(const void*) { esp_task_wdt_reset(); }

class EpdPanel : public Panel {
 public:
  void begin() {
    pinMode(MB10_EPD_POWER, OUTPUT);
    digitalWrite(MB10_EPD_POWER, HIGH);  // питание e-paper на CrowPanel
    delay(10);
    SPI.begin(MB10_EPD_SCK, -1, MB10_EPD_MOSI, MB10_EPD_CS);
    epd.epd2.selectSPI(SPI, SPISettings(4000000, MSBFIRST, SPI_MODE0));
    epd.init(0, true, 2, false);
    // Полное обновление идёт секунды — сторож кормится, пока панель занята.
    epd.epd2.setBusyCallback(feedDuringBusy);
    epd.setRotation(MB10_PANEL_ROTATION);
  }
  bool show(const uint8_t* frame, uint16_t w, uint16_t h) override {
    if (epd.width() != w || epd.height() != h) {
      logLine("panel: frame size does not match panel orientation");
      return false;
    }
    epd.setFullWindow();
    epd.firstPage();
    do {
      epd.fillScreen(GxEPD_WHITE);
      epd.drawBitmap(0, 0, frame, int16_t(w), int16_t(h), GxEPD_BLACK);
    } while (epd.nextPage());
    epd.hibernate();  // между обновлениями панель без тока, картинка остаётся
    return true;
  }
  bool showText(const char* const* lines, size_t count) override {
    epd.setFullWindow();
    epd.firstPage();
    do {
      epd.fillScreen(GxEPD_WHITE);
      epd.setFont(&FreeMonoBold12pt7b);
      epd.setTextColor(GxEPD_BLACK);
      for (size_t i = 0; i < count; i++) {
        epd.setCursor(8, int16_t(40 + i * 36));
        epd.print(lines[i]);
      }
    } while (epd.nextPage());
    epd.hibernate();
    return true;
  }
};
#else
// Wokwi: панели 5.79″ там нет — кадр подтверждается CRC в журнале (по нему сценарий Wokwi сверяет, что показано).
class EpdPanel : public Panel {
 public:
  void begin() { logLine("panel: stub (Wokwi)"); }
  bool show(const uint8_t* frame, uint16_t w, uint16_t h) override {
    char line[64];
    snprintf(line, sizeof line, "PANEL frame %ux%u crc=%08lx", w, h, static_cast<unsigned long>(mb10d::crc32(frame, frameBytes(w, h))));
    logLine(line);
    delay(200);
    return true;
  }
  bool showText(const char* const* lines, size_t count) override {
    for (size_t i = 0; i < count; i++) logLine(lines[i]);
    return true;
  }
};
#endif

// ── Flash ──

class FlashStorage : public Storage {
 public:
  bool begin() { return LittleFS.begin(true); }
  bool writeAtomic(const char* name, const uint8_t* a, size_t aLen, const uint8_t* b, size_t bLen) override {
    String path = String("/") + name, tmp = path + ".tmp";
    File f = LittleFS.open(tmp, "w");
    if (!f) return false;
    bool ok = f.write(a, aLen) == aLen && f.write(b, bLen) == bLen;
    f.close();
    // rename в littlefs атомарен и заменяет старый файл: либо прежний кадр целиком, либо новый.
    return ok && LittleFS.rename(tmp, path);
  }
  bool read(const char* name, size_t offset, uint8_t* buf, size_t len) override {
    File f = LittleFS.open(String("/") + name, "r");
    if (!f) return false;
    bool ok = f.seek(offset) && f.read(buf, len) == len;
    f.close();
    return ok;
  }
};

// ── Подсветка: GPIO → MOSFET → светодиоды, ШИМ ──

class PwmBacklight : public Backlight {
 public:
  void begin() {
#if MB10_BACKLIGHT_PIN >= 0
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcAttach(MB10_BACKLIGHT_PIN, 5000, 8);
#else
    ledcSetup(0, 5000, 8);
    ledcAttachPin(MB10_BACKLIGHT_PIN, 0);
#endif
#endif
    set(0);
  }
  void set(uint8_t level) override {
    static const uint8_t duty[] = {0, 24, 96, 255};
    uint8_t d = duty[level > 3 ? 3 : level];
#if MB10_BACKLIGHT_PIN >= 0
#if ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcWrite(MB10_BACKLIGHT_PIN, d);
#else
    ledcWrite(0, d);
#endif
#endif
    char line[40];
    snprintf(line, sizeof line, "backlight level=%u duty=%u", level, d);
    logLine(line);
  }
};

// ── Платформа ──

class Esp32Platform : public Platform {
 public:
  uint32_t nowMs() override { return millis(); }
  void random(uint8_t* out, size_t len) override { esp_fill_random(out, len); }
  void feedWatchdog() override { esp_task_wdt_reset(); }
  void reboot() override {
    logLine("rebooting");
    Serial.flush();
    ESP.restart();
  }
  void log(const char* line) override { logLine(line); }
  const char* firmwareVersion() override { return MB10_FW_VERSION; }
  const char* hardwareId() override {
    if (!hw_[0]) snprintf(hw_, sizeof hw_, "%s", WiFi.macAddress().c_str());
    return hw_;
  }
  const char* ipAddress() override {
    ip_[0] = '\0';
    if (WiFi.status() == WL_CONNECTED) snprintf(ip_, sizeof ip_, "%s", WiFi.localIP().toString().c_str());
    return ip_;
  }
  int rssi() override { return WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0; }
  int batteryMillivolts() override {
#if MB10_BATTERY_ADC_PIN >= 0
    return int(analogReadMilliVolts(MB10_BATTERY_ADC_PIN)) * MB10_BATTERY_DIVIDER;
#else
    return -1;
#endif
  }

 private:
  char hw_[24] = {0};
  char ip_[20] = {0};
};

// ── TCP ──

class ClientLink : public Link {
 public:
  explicit ClientLink(WiFiClient c) : client_(c) {}
  void send(const uint8_t* data, size_t len) override {
    while (len > 0 && client_.connected()) {
      size_t n = client_.write(data, len);
      if (n == 0) break;
      data += n;
      len -= n;
    }
  }
  void close() override { closeRequested_ = true; }
  bool closeRequested() const { return closeRequested_; }
  WiFiClient& client() { return client_; }

  // Сначала FIN, непрочитанное — выбросить: close() с данными в приёмном буфере шлёт RST, и последний NACK может потеряться.
  void closeGracefully() {
    int fd = client_.fd();
    if (fd >= 0) lwip_shutdown(fd, SHUT_WR);
    uint32_t until = millis() + 500;
    while (client_.connected() && int32_t(millis() - until) < 0) {
      while (client_.available()) client_.read();
      delay(5);
    }
    client_.stop();
  }

 private:
  WiFiClient client_;
  bool closeRequested_ = false;
};

// ── Состояние ──

Settings settings;
EpdPanel panel;
FlashStorage storage;
PwmBacklight backlight;
Esp32Platform platform;
Device* device = nullptr;
WiFiServer* server = nullptr;
ClientLink* link = nullptr;
Session* session = nullptr;
Connectivity connectivity;
String consoleLine;
bool buttonWasDown = false;
uint32_t buttonChangedAt = 0;

void dropClient() {
  if (!link) return;
  delete session;
  session = nullptr;
  link->closeGracefully();
  delete link;
  link = nullptr;
}

void startWifi() {
  WiFi.disconnect();  // не disconnect(true): тот выключает Wi-Fi целиком, а сервер уже слушает
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(false);  // переподключением управляет Connectivity (backoff 1…30 с)
  IPAddress ip, gw, mask, dns;
  if (ip.fromString(settings.ip) && gw.fromString(settings.gateway) && mask.fromString(settings.subnet)) {
    if (!dns.fromString(settings.dns)) dns = gw;
    WiFi.config(ip, gw, mask, dns);
  }
  WiFi.begin(settings.ssid.c_str(), settings.pass.c_str(), settings.channel);
  logLine("wifi: connecting");
}

void pollWifi() {
  bool up = WiFi.status() == WL_CONNECTED;
  Connectivity::State before = connectivity.state();
  switch (connectivity.update(up, millis())) {
    case Connectivity::Action::StartConnect:
      startWifi();
      break;
    case Connectivity::Action::Disconnected: {
      char line[64];
      snprintf(line, sizeof line, "wifi: down, retry in %lu ms", static_cast<unsigned long>(connectivity.retryAt() - millis()));
      logLine(line);
      dropClient();
      WiFi.disconnect();
      break;
    }
    case Connectivity::Action::None:
      break;
  }
  if (before != Connectivity::State::Online && connectivity.state() == Connectivity::State::Online) {
    // Энергосбережение: модем спит между маяками точки доступа, TCP остаётся доступным.
    esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
    char line[80];
    snprintf(line, sizeof line, "wifi: online %s rssi=%d", platform.ipAddress(), platform.rssi());
    logLine(line);
  }
}

void pollTcp() {
  if (!server) return;
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  WiFiClient incoming = server->accept();
#else
  WiFiClient incoming = server->available();
#endif
  if (incoming) {
    if (link) {
      logLine("new connection replaces the previous one");
      delete session;
      session = nullptr;
      link->client().stop();
      delete link;
    }
    incoming.setNoDelay(true);
    link = new ClientLink(incoming);
    session = new Session(*device, *link);
  }
  if (!link) return;
  uint8_t buf[1460];
  while (session && !session->closed() && link->client().available()) {
    int n = link->client().read(buf, sizeof buf);
    if (n <= 0) break;
    session->onData(buf, size_t(n));
    esp_task_wdt_reset();
  }
  if (session) session->poll();
  if (!link->client().connected() || link->closeRequested() || (session && session->closed())) dropClient();
}

void pollButton() {
#if MB10_BUTTON_PIN >= 0
  bool down = digitalRead(MB10_BUTTON_PIN) == LOW;
  if (down != buttonWasDown && millis() - buttonChangedAt > 50) {
    buttonWasDown = down;
    buttonChangedAt = millis();
    if (down && device) device->setBacklight(uint8_t(BacklightLevel::Medium), kButtonBacklightSeconds);
  }
#endif
}

void printStatus() {
  Serial.printf("id=%s configured=%d port=%u panel=%ux%u ssid=%s secret=%s wifi=%s ip=%s shows=%lu fw=%s\n", settings.cfg.deviceId,
                settings.configured, settings.port, settings.cfg.width, settings.cfg.height, settings.ssid.c_str(),
                settings.configured ? "set" : "-", WiFi.status() == WL_CONNECTED ? "up" : "down", platform.ipAddress(),
                static_cast<unsigned long>(device ? device->displayedVersion() : 0), MB10_FW_VERSION);
}

// USB-консоль: config {json} | status | reboot | clear-frame
void pollConsole() {
  while (Serial.available()) {
    char c = char(Serial.read());
    if (c != '\n' && c != '\r') {
      if (consoleLine.length() < 1024) consoleLine += c;
      continue;
    }
    String line = consoleLine;
    consoleLine = "";
    line.trim();
    if (line.isEmpty()) continue;
    if (line.startsWith("config ")) {
      String error;
      if (saveSettingsJson(line.c_str() + 7, error)) Serial.println("OK: saved, rebooting");
      else Serial.printf("ERROR: %s\n", error.c_str());
      if (!error.length()) {
        delay(100);
        ESP.restart();
      }
    } else if (line == "status") {
      printStatus();
    } else if (line == "reboot") {
      ESP.restart();
    } else if (line == "clear-frame") {
      LittleFS.remove(String("/") + kFrameFile);
      Serial.println("OK: stored frame removed");
    } else {
      Serial.println("commands: config {json from dashboard + wifiSsid/wifiPassword} | status | reboot | clear-frame");
    }
  }
}

void setupWatchdog() {
#if ESP_IDF_VERSION_MAJOR >= 5
  esp_task_wdt_config_t cfg = {};
  cfg.timeout_ms = kWatchdogSeconds * 1000;
  cfg.idle_core_mask = 0;
  cfg.trigger_panic = true;
  if (esp_task_wdt_reconfigure(&cfg) != ESP_OK) esp_task_wdt_init(&cfg);
#else
  esp_task_wdt_init(kWatchdogSeconds, true);
#endif
  esp_task_wdt_add(nullptr);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(200);
  logLine("=== BOOT mb10 display " MB10_FW_VERSION " ===");
  setupWatchdog();
#if MB10_BUTTON_PIN >= 0
  pinMode(MB10_BUTTON_PIN, INPUT_PULLUP);
#endif
  backlight.begin();
  panel.begin();
  if (!storage.begin()) logLine("storage: LittleFS mount failed");
#ifdef MB10_SELFTEST
  settings = selftestSettings();
  logLine("SELFTEST build: встроенная конфигурация, Wokwi-GUEST");
#else
  settings = loadSettings();
#endif
  if (!settings.configured) {
    logLine("NOT CONFIGURED — send: config {\"id\":…,\"secret\":…,\"wifiSsid\":…,\"wifiPassword\":…}");
    const char* lines[] = {"NOT CONFIGURED", "USB: config {...}"};
    panel.showText(lines, 2);
    return;
  }
  size_t size = frameBytes(settings.cfg.width, settings.cfg.height);
  uint8_t* frame = static_cast<uint8_t*>(malloc(size));
  uint8_t* incoming = static_cast<uint8_t*>(malloc(size < 64 ? 64 : size));
  if (!frame || !incoming) {
    logLine("out of memory for frame buffers");
    return;
  }
  device = new Device(settings.cfg, panel, storage, backlight, platform, frame, incoming);
  device->boot();  // кадр из flash — на экран до Wi-Fi
  // Стек lwIP поднимается вместе с Wi-Fi: сокет сервера до WiFi.mode роняет плату в assert «tcpip_send_msg_wait_sem
  // (Invalid mbox)» и цикл перезагрузок (нашёл Wokwi, Ф4). Слушающий сокет на INADDR_ANY переживает переподключения Wi-Fi.
  WiFi.mode(WIFI_STA);
  server = new WiFiServer(settings.port);
  server->begin();
  printStatus();
#ifdef MB10_SELFTEST
  startSelftest(settings);
#endif
}

void loop() {
#ifdef MB10_SELFTEST
  // Зависание основного цикла: сторож не кормится — через kWatchdogSeconds сброс (фаза 2 самопроверки).
  while (selftestHang) {
  }
#endif
  esp_task_wdt_reset();
  pollConsole();
  if (!device) {
    delay(50);
    return;
  }
  pollWifi();
  pollTcp();
  pollButton();
  device->tick();
  if (device->rebootRequested()) {
    dropClient();
    platform.reboot();
  }
  delay(2);
}

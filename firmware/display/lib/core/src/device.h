#pragma once
#include <cstddef>
#include <cstdint>

#include "hal.h"
#include "protocol.h"
#include "sound.h"

namespace mb10d {

struct Config {
  char deviceId[kDeviceIdSize + 1];
  uint8_t key[kKeySize];
  uint16_t width;
  uint16_t height;
  // Контракт docs/displays.md: молчащее соединение — 2 с, начатый кадр — 5 с.
  uint32_t headerTimeoutMs = 2000;
  uint32_t payloadTimeoutMs = 5000;
  // Роль «звук» (docs/sound-nodes.md): приёмный буфер не меньше куска клипа, в HELLO — roles и audio.
  bool audio = false;
};

// Кадр во «flash»: файл frame.bin = заголовок 20 байт (MBFB, версия, ширина, высота, длина, CRC32 кадра) + кадр.
constexpr size_t kStoredHeaderSize = 20;
extern const char* const kFrameFile;

// Дисплей целиком, без сети: что показано (версия и кадр), восстановление после загрузки, показ нового кадра, тест, подсветка.
// frame и incoming — два буфера по frameBytes(width, height): показанный кадр и приёмный (отвергнутый кадр не портит показанный).
class Device {
 public:
  Device(const Config& cfg, Panel& panel, Storage& storage, Backlight& backlight, Platform& platform, uint8_t* frame, uint8_t* incoming);

  // Загрузка: кадр из Storage (если есть и цел) — сразу на панель, до Wi-Fi.
  void boot();
  // Раз в цикл: гасит подсветку и тестовый экран по таймеру.
  void tick();

  const Config& config() const { return cfg_; }
  Platform& platform() { return platform_; }
  uint32_t displayedVersion() const { return displayed_; }
  bool hasFrame() const { return hasFrame_; }
  const uint8_t* frame() const { return frame_; }
  uint8_t* incomingBuffer() { return incoming_; }
  size_t frameSize() const { return frameBytes(cfg_.width, cfg_.height); }
  // Размер приёмного буфера: кадр панели, а у звуковой точки — не меньше куска клипа (CLIP_CHUNK).
  static size_t incomingBytes(const Config& cfg) {
    size_t n = frameBytes(cfg.width, cfg.height);
    if (n < 64) n = 64;
    if (cfg.audio && n < kAudioPayloadMax) n = kAudioPayloadMax;
    return n;
  }
  // Звук: Sound живёт у вызывающего (main), Device только передаёт ему команды и статус.
  void attachSound(Sound* sound) { sound_ = sound; }
  Sound* sound() { return cfg_.audio ? sound_ : nullptr; }
  uint8_t backlightLevel() const { return backlight_level_; }

  // JSON-статус для HELLO: {"fw":…,"hw":…,"ip":…,"rssi":…,"batteryMv":…,"batteryPct":…,"batteryRate":…,"backlight":…}
  // (отсутствующее — пропускается); у звуковой точки ещё "roles":["display","audio"] и "audio":{…} (Sound::statusJson).
  size_t statusJson(char* out, size_t cap);

  // Новый кадр (уже проверенный): во flash, затем на панель. false — не записался или панель не обновилась.
  bool showImage(uint32_t version, const uint8_t* data);
  void showTest(uint16_t seconds);
  void setBacklight(uint8_t level, uint16_t seconds);
  void requestReboot() { rebootRequested_ = true; }
  bool rebootRequested() const { return rebootRequested_; }

 private:
  Config cfg_;
  Panel& panel_;
  Storage& storage_;
  Backlight& backlight_;
  Platform& platform_;
  uint8_t* frame_;
  uint8_t* incoming_;
  uint32_t displayed_ = 0;
  bool hasFrame_ = false;
  uint8_t backlight_level_ = 0;
  uint32_t backlightOffAt_ = 0;
  bool backlightTimer_ = false;
  uint32_t testUntil_ = 0;
  bool testShown_ = false;
  bool rebootRequested_ = false;
  Sound* sound_ = nullptr;
};

}  // namespace mb10d

// Звук точки на CrowPanel (docs/sound-nodes.md, З5): microSD на своей шине SPI, MP3 с карты (ESP8266Audio, libmad), клипы
// громкой связи (WAV IMA ADPCM, декодер и микшер — в ядре, lib/core/src/mixer.*), вывод I²S на MAX98357A. Логика (что играть,
// плейлист, клипы) — в ядре (Sound), здесь только железо.
//
// Задача звука — на ядре 1 с высоким приоритетом: декодирует MP3 в кольцевой буфер, смешивает с объявлением и пишет в I²S
// (запись блокируется, пока DMA занят, — это и есть темп). Сеть и e-paper — в основном цикле на ядре 0: обновление панели
// (секунды) звук не прерывает. Команды из ядра (Sound → AudioOut) — под мьютексом; карта — под своим (её читают обе задачи).
#include <Arduino.h>
#include <SD.h>
#include <SPI.h>
#ifndef MB10_AUDIO_STUB
#include <driver/i2s.h>
#endif

#include <AudioFileSource.h>
#include <AudioGeneratorMP3.h>
#include <AudioOutput.h>

#include <sys/stat.h>

#include <algorithm>
#include <vector>

#include "board.h"
#include "mixer.h"
#include "sound.h"

using namespace mb10d;

namespace mb10esp {

namespace {

constexpr uint32_t kOutRate = 44100;
// Корень звука на карте; внутри — раскладка из sound.h (kSdTracksDir, kSdClipsDir).
constexpr char kSdRoot[] = "/mb10";
String tracksDir() { return String(kSdRoot) + kSdTracksDir; }
String trackPath(const char* name) { return tracksDir() + "/" + name; }
constexpr size_t kRing = 16384;  // ≈ 0,37 с фона на 44,1 кГц — хватает с запасом: декодер в той же задаче
constexpr size_t kFrames = 256;  // сэмплов за проход задачи (≈ 5,8 мс)
constexpr uint32_t kAmpOffAfterMs = 2000;

// ── Карта ──

class Guard {
 public:
  explicit Guard(SemaphoreHandle_t m) : m_(m) { xSemaphoreTakeRecursive(m_, portMAX_DELAY); }
  ~Guard() { xSemaphoreGiveRecursive(m_); }

 private:
  SemaphoreHandle_t m_;
};

SemaphoreHandle_t sdLock = nullptr;
SPIClass sdSpi(HSPI);

class SdCard : public SoundCard {
 public:
  void begin() {
    sdLock = xSemaphoreCreateRecursiveMutex();
#if MB10_SD_POWER >= 0
    pinMode(MB10_SD_POWER, OUTPUT);
    digitalWrite(MB10_SD_POWER, HIGH);  // питание слота microSD на CrowPanel
    delay(20);
#endif
    sdSpi.begin(MB10_SD_CLK, MB10_SD_MISO, MB10_SD_MOSI, MB10_SD_CS);
    mount();
  }
  // Раз в цикл: карты не было — пробуем раз в 5 с; была — раз в 10 с проверяем, что не вынули.
  void poll() {
    uint32_t now = millis();
    if (now - lastCheck_ < (mounted_ ? 10000u : 5000u)) return;
    lastCheck_ = now;
    Guard g(sdLock);
    if (!mounted_) {
      mount();
    } else {
      File d = SD.open(tracksDir());
      bool ok = d && d.isDirectory();
      if (d) d.close();
      if (!ok) {
        logLine("sd: card removed");
        closeClip();
        SD.end();
        mounted_ = false;
        tracks_.clear();
      }
    }
  }

  bool present() override { return mounted_; }
  // Записать файл на карту целиком (самопроверка кладёт трек) и перечитать список треков.
  bool writeFile(const char* path, const uint8_t* data, size_t len) {
    Guard g(sdLock);
    if (!mounted_) return false;
    File f = SD.open(path, FILE_WRITE);
    bool ok = f && f.write(data, len) == len;
    if (f) f.close();
    scan();
    return ok;
  }
  size_t trackCount() override { return tracks_.size(); }
  bool trackName(size_t i, char* out, size_t cap) override {
    Guard g(sdLock);
    if (i >= tracks_.size()) return false;
    snprintf(out, cap, "%s", tracks_[i].c_str());
    return true;
  }
  bool hasTrack(const char* name) override {
    Guard g(sdLock);
    return std::binary_search(tracks_.begin(), tracks_.end(), String(name));
  }
  bool hasClip(const char* id) override {
    Guard g(sdLock);
    return mounted_ && fileSize(clipPath(id)) >= 0;
  }
  uint32_t clipSize(const char* id) override {
    Guard g(sdLock);
    if (!openClip(id)) return 0;
    return uint32_t(clip_.size());
  }
  bool readClip(const char* id, uint32_t off, uint8_t* buf, size_t len) override {
    Guard g(sdLock);
    return openClip(id) && clip_.seek(off) && clip_.read(buf, len) == len;
  }
  uint32_t partSize(const char* id) override {
    Guard g(sdLock);
    long n = mounted_ ? fileSize(partPath(id)) : -1;
    return n > 0 ? uint32_t(n) : 0;
  }
  // Ядро пишет только подряд: с 0 (новый файл) или с конца (дописать) — смещение оно уже сверило с partSize. size() у только
  // что созданного файла в Arduino-ESP32 2.x врёт (stat до первой записи — мусор, нашёл Wokwi), поэтому здесь не проверяется.
  bool writePart(const char* id, uint32_t off, const uint8_t* d, size_t len) override {
    Guard g(sdLock);
    if (!mounted_) return false;
    File f = SD.open(partPath(id), off == 0 ? FILE_WRITE : FILE_APPEND);
    if (!f) {
      logLine("sd: cannot open clip part for writing");
      return false;
    }
    size_t wrote = f.write(d, len);
    f.close();
    if (wrote != len) {
      char line[80];
      snprintf(line, sizeof line, "sd: clip part write failed: %u of %u bytes", unsigned(wrote), unsigned(len));
      logLine(line);
      return false;
    }
    return true;
  }
  bool readPart(const char* id, uint32_t off, uint8_t* buf, size_t len) override {
    Guard g(sdLock);
    File f = SD.open(partPath(id), FILE_READ);
    bool ok = f && f.seek(off) && f.read(buf, len) == len;
    if (f) f.close();
    return ok;
  }
  bool commitPart(const char* id) override {
    Guard g(sdLock);
    closeClip();
    if (fileSize(clipPath(id)) >= 0) SD.remove(clipPath(id));
    return SD.rename(partPath(id), clipPath(id));
  }
  void removePart(const char* id) override {
    Guard g(sdLock);
    if (fileSize(partPath(id)) >= 0) SD.remove(partPath(id));
  }

 private:
  // Размер файла или -1 — через stat: SD.exists/open на отсутствующем файле пишут в журнал ошибку VFS на каждый вызов.
  static long fileSize(const String& path) {
    struct stat st;
    return stat((String("/sd") + path).c_str(), &st) == 0 && S_ISREG(st.st_mode) ? long(st.st_size) : -1;
  }
  static String clipPath(const char* id) { return String(kSdRoot) + kSdClipsDir + "/" + id + kClipExt; }
  static String partPath(const char* id) { return String(kSdRoot) + kSdClipsDir + "/" + id + kPartExt; }
  void mount() {
    if (!SD.begin(MB10_SD_CS, sdSpi, 20000000, "/sd", 4)) return;
    mounted_ = true;
    SD.mkdir(kSdRoot);
    SD.mkdir(tracksDir());
    SD.mkdir(String(kSdRoot) + kSdClipsDir);
    scan();
    char line[80];
    snprintf(line, sizeof line, "sd: card mounted, %u tracks, %llu MB", unsigned(tracks_.size()), SD.cardSize() >> 20);
    logLine(line);
  }
  void scan() {
    tracks_.clear();
    File d = SD.open(tracksDir());
    if (!d) return;
    for (File f = d.openNextFile(); f; f = d.openNextFile()) {
      const char* n = f.name();
      const char* base = strrchr(n, '/');
      String name = base ? base + 1 : n;
      if (!f.isDirectory() && name.length() > 0 && name[0] != '.') tracks_.push_back(name);
      f.close();
    }
    d.close();
    std::sort(tracks_.begin(), tracks_.end());
  }
  bool openClip(const char* id) {
    if (!mounted_) return false;
    if (clip_ && clipId_ == id) return true;
    closeClip();
    if (fileSize(clipPath(id)) < 0) return false;
    clip_ = SD.open(clipPath(id), FILE_READ);
    if (clip_) clipId_ = id;
    return bool(clip_);
  }
  void closeClip() {
    if (clip_) clip_.close();
    clipId_ = "";
  }
  bool mounted_ = false;
  uint32_t lastCheck_ = 0;
  std::vector<String> tracks_;
  File clip_;
  String clipId_;
};

// Трек с карты для декодера MP3 — каждое чтение под мьютексом карты.
class SdTrackFile : public AudioFileSource {
 public:
  bool open(const char* path) override {
    Guard g(sdLock);
    f_ = SD.open(path, FILE_READ);
    return bool(f_);
  }
  uint32_t read(void* data, uint32_t len) override {
    Guard g(sdLock);
    return f_ ? uint32_t(f_.read(static_cast<uint8_t*>(data), len)) : 0;
  }
  bool seek(int32_t pos, int dir) override {
    Guard g(sdLock);
    if (!f_) return false;
    uint32_t target = dir == SEEK_SET ? uint32_t(pos) : dir == SEEK_CUR ? uint32_t(f_.position() + pos) : uint32_t(f_.size() + pos);
    return f_.seek(target);
  }
  bool close() override {
    Guard g(sdLock);
    if (f_) f_.close();
    return true;
  }
  bool isOpen() override { return bool(f_); }
  uint32_t getSize() override { return f_ ? uint32_t(f_.size()) : 0; }
  uint32_t getPos() override { return f_ ? uint32_t(f_.position()) : 0; }

 private:
  File f_;
};

// Сколько сэмплов выдал декодер MP3 с загрузки — самопроверка (Wokwi) убеждается, что трек с карты действительно декодируется.
volatile uint32_t decodedSamples = 0;

// Выход декодера MP3 → кольцо моно-сэмплов на частоте файла; для микшера — источник PCM.
class Ring : public AudioOutput, public PcmSource {
 public:
  bool SetRate(int hz) override {
    rate_ = uint32_t(hz);
    return true;
  }
  bool SetBitsPerSample(int) override { return true; }
  bool SetChannels(int ch) override {
    channels_ = ch;
    return true;
  }
  bool begin() override { return true; }
  bool stop() override { return true; }
  bool ConsumeSample(int16_t sample[2]) override {
    if (count_ >= kRing) return false;  // полно — декодер подождёт
    int32_t v = channels_ == 2 ? (int32_t(sample[0]) + sample[1]) / 2 : sample[0];
    buf_[(head_ + count_) % kRing] = int16_t(v);
    count_++;
    decodedSamples = decodedSamples + 1;
    return true;
  }
  uint32_t rate() override { return rate_; }
  size_t read(int16_t* out, size_t n) override {
    size_t k = 0;
    while (k < n && count_ > 0) {
      out[k++] = buf_[head_];
      head_ = (head_ + 1) % kRing;
      count_--;
    }
    return k;
  }
  bool finished() override { return ended && count_ == 0; }
  size_t free() const { return kRing - count_; }
  void clear() { head_ = count_ = 0, ended = false; }
  bool ended = false;

 private:
  int16_t buf_[kRing];
  size_t head_ = 0, count_ = 0;
  uint32_t rate_ = 44100;
  int channels_ = 2;
};

// ── Вывод ──

class I2sAudio : public AudioOut {
 public:
  I2sAudio(SdCard& card) : card_(card), clipSrc_(card), mixer_(kOutRate) {}

  void begin() {
    lock_ = xSemaphoreCreateMutex();
#if MB10_AMP_SD_MODE >= 0
    pinMode(MB10_AMP_SD_MODE, OUTPUT);
    digitalWrite(MB10_AMP_SD_MODE, LOW);  // усилитель выключен в тишине — нет шипения, меньше ток
#endif
#ifndef MB10_AUDIO_STUB
    i2s_config_t cfg = {};
    cfg.mode = i2s_mode_t(I2S_MODE_MASTER | I2S_MODE_TX);
    cfg.sample_rate = kOutRate;
    cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
    cfg.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;
    cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
    cfg.dma_buf_count = 8;
    cfg.dma_buf_len = kFrames;
    cfg.tx_desc_auto_clear = true;
    i2s_pin_config_t pins = {};
    pins.mck_io_num = I2S_PIN_NO_CHANGE;
    pins.bck_io_num = MB10_I2S_BCLK;
    pins.ws_io_num = MB10_I2S_LRCK;
    pins.data_out_num = MB10_I2S_DIN;
    pins.data_in_num = I2S_PIN_NO_CHANGE;
    if (i2s_driver_install(I2S_NUM_0, &cfg, 0, nullptr) != ESP_OK || i2s_set_pin(I2S_NUM_0, &pins) != ESP_OK) logLine("audio: I2S init failed");
#else
    logLine("audio: I2S stub (Wokwi) — samples are discarded");
#endif
    xTaskCreatePinnedToCore(taskEntry, "audio", 12288, this, 5, nullptr, 1);
  }

  // ── AudioOut (из основного цикла) ──
  bool startTrack(const char* name, uint8_t volume, uint32_t fadeMs) override {
    if (!card_.hasTrack(name)) return false;
    xSemaphoreTake(lock_, portMAX_DELAY);
    snprintf(pendingTrack_, sizeof pendingTrack_, "%s", name);
    pendingVolume_ = volume;
    pendingFade_ = fadeMs;
    hasPending_ = true;
    stopRequested_ = false;
    trackActive_ = true;
    xSemaphoreGive(lock_);
    return true;
  }
  void stopTrack(uint32_t fadeMs) override {
    xSemaphoreTake(lock_, portMAX_DELAY);
    hasPending_ = false;
    stopRequested_ = true;
    pendingFade_ = fadeMs;
    xSemaphoreGive(lock_);
  }
  void setTrackVolume(uint8_t volume, uint32_t fadeMs) override {
    xSemaphoreTake(lock_, portMAX_DELAY);
    volume_ = volume;
    mixer_.setBackgroundVolume(volume, fadeMs);
    xSemaphoreGive(lock_);
  }
  bool trackPlaying() override { return trackActive_; }
  bool startClip(const char* id, uint8_t volume, bool chime) override {
    xSemaphoreTake(lock_, portMAX_DELAY);
    bool ok = clipSrc_.open(id);
    if (ok) mixer_.startClip(&clipSrc_, volume, chime);
    clipActive_ = ok;
    xSemaphoreGive(lock_);
    return ok;
  }
  void stopClip() override {
    xSemaphoreTake(lock_, portMAX_DELAY);
    mixer_.stopClip();
    clipActive_ = false;
    xSemaphoreGive(lock_);
  }
  bool clipPlaying() override { return clipActive_; }

 private:
  static void taskEntry(void* self) { static_cast<I2sAudio*>(self)->run(); }

  // Сменить трек: затухание текущего (половина fade), затем новый файл с нарастанием (вторая половина).
  void switchTrack() {
    char name[kTrackNameMax + 1];
    uint8_t volume;
    uint32_t fade;
    bool stop;
    xSemaphoreTake(lock_, portMAX_DELAY);
    bool pending = hasPending_;
    stop = stopRequested_;
    if (!pending && !stop) {
      xSemaphoreGive(lock_);
      return;
    }
    fade = pendingFade_;
    if (mp3_.isRunning() && !mixer_.backgroundSilent()) {
      if (mixer_.backgroundGain().target() != 0) mixer_.setBackgroundVolume(0, fade / 2);
      xSemaphoreGive(lock_);
      return;  // ждём, пока затихнет
    }
    snprintf(name, sizeof name, "%s", pendingTrack_);
    volume = pendingVolume_;
    hasPending_ = stopRequested_ = false;
    mixer_.setBackground(nullptr);
    xSemaphoreGive(lock_);

    if (mp3_.isRunning()) mp3_.stop();
    file_.close();
    ring_.clear();
    if (stop) {
      trackActive_ = false;
      return;
    }
    String path = trackPath(name);
    bool ok = file_.open(path.c_str()) && mp3_.begin(&file_, &ring_);
    xSemaphoreTake(lock_, portMAX_DELAY);
    if (ok) {
      mixer_.setBackground(&ring_);
      mixer_.jumpBackgroundVolume(0);
      mixer_.setBackgroundVolume(volume_ = volume, fade / 2);
    }
    xSemaphoreGive(lock_);
    if (!ok) {
      char line[160];
      snprintf(line, sizeof line, "audio: cannot play %s", name);
      logLine(line);
      file_.close();
      trackActive_ = false;  // ядро возьмёт следующий
    }
  }

  void run() {
    static int16_t mono[kFrames];
    static int16_t stereo[kFrames * 2];
    uint32_t lastAudible = 0;
    bool ampOn = false;
    for (;;) {
      switchTrack();
      // Декодировать, пока в кольце есть место под кадр MP3 (1152 сэмпла на канал).
      while (mp3_.isRunning() && ring_.free() >= 1152) {
        if (!mp3_.loop()) {
          mp3_.stop();
          ring_.ended = true;
          break;
        }
      }
      xSemaphoreTake(lock_, portMAX_DELAY);
      bool audible = mixer_.render(mono, kFrames);
      if (clipActive_ && !mixer_.clipActive()) clipActive_ = false;
      bool bgDone = mixer_.background() == &ring_ && ring_.finished();
      xSemaphoreGive(lock_);
      if (bgDone && !hasPending_) trackActive_ = false;

      uint32_t now = millis();
      if (audible) lastAudible = now;
      bool wantAmp = audible || now - lastAudible < kAmpOffAfterMs;
      if (wantAmp != ampOn) {
        ampOn = wantAmp;
#if MB10_AMP_SD_MODE >= 0
        digitalWrite(MB10_AMP_SD_MODE, ampOn ? HIGH : LOW);
#endif
      }
      for (size_t i = 0; i < kFrames; i++) stereo[2 * i] = stereo[2 * i + 1] = mono[i];
#ifndef MB10_AUDIO_STUB
      size_t written = 0;
      i2s_write(I2S_NUM_0, stereo, sizeof stereo, &written, portMAX_DELAY);
#else
      vTaskDelay(pdMS_TO_TICKS(kFrames * 1000 / kOutRate + 1));
#endif
    }
  }

  SdCard& card_;
  ClipSource clipSrc_;
  Mixer mixer_;
  Ring ring_;
  SdTrackFile file_;
  AudioGeneratorMP3 mp3_;
  SemaphoreHandle_t lock_ = nullptr;
  char pendingTrack_[kTrackNameMax + 1] = {0};
  uint8_t pendingVolume_ = 60, volume_ = 60;
  uint32_t pendingFade_ = 0;
  volatile bool hasPending_ = false, stopRequested_ = false, trackActive_ = false, clipActive_ = false;
};

SdCard card;
I2sAudio* out = nullptr;

}  // namespace

SoundCard& audioCard() { return card; }

AudioOut* audioBegin() {
  card.begin();
  static I2sAudio audio(card);
  audio.begin();
  out = &audio;
  return out;
}

void audioPoll() { card.poll(); }

#ifdef MB10_SELFTEST
bool audioWriteTrack(const char* name, const uint8_t* data, size_t len) { return card.writeFile(trackPath(name).c_str(), data, len); }
uint32_t audioDecodedSamples() { return decodedSamples; }
#endif

}  // namespace mb10esp

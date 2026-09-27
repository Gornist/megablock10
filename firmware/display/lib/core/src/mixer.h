#pragma once
#include <cstddef>
#include <cstdint>

#include "wav.h"

// Микшер звуковой точки (docs/sound-nodes.md): фон (PCM от декодера MP3 любой частоты) × громкость с плавным переходом,
// объявление (клип WAV 16 кГц) × громкость, сигнал перед объявлением. Выход — моно int16 на частоте I²S. Всё в ядре, чтобы
// проверялось на ПК; на плате этим кормится задача звука (src/esp32/audio.cpp), на ПК — не используется (там журнал).
namespace mb10d {

class SoundCard;

// Источник PCM: моно, частота rate(). read — сколько отдал (0 — пока нечего: конец или декодер не успел; различает finished()).
class PcmSource {
 public:
  virtual ~PcmSource() = default;
  virtual uint32_t rate() = 0;
  virtual size_t read(int16_t* out, size_t n) = 0;
  virtual bool finished() = 0;
};

// Громкость 0–100 → множитель Q15 по кривой «на слух» (квадрат: 50 % — вчетверо тише, а не вдвое).
int32_t volumeToGain(uint8_t volume);

// Плавное изменение множителя: за ms миллисекунд линейно от текущего к цели.
class GainRamp {
 public:
  void set(int32_t target, uint32_t ms, uint32_t rate);
  void jump(int32_t value) { cur_ = target_ = value, step_ = 0, left_ = 0; }
  int32_t next();
  int32_t current() const { return cur_; }
  int32_t target() const { return target_; }
  bool settled() const { return cur_ == target_; }

 private:
  int32_t cur_ = 0, target_ = 0, step_ = 0;
  uint32_t left_ = 0;  // шагов до цели; последний — ровно в цель (без остатка от деления)
};

// Линейная интерполяция источника к частоте выхода (голос 16 кГц → 44,1 кГц; MP3 48 кГц → 44,1 кГц).
class Resampler {
 public:
  void reset() { pos_ = 0, have_ = 0, prev_ = cur_ = 0; }
  // Сколько записано в out (меньше n — источнику нечего отдать).
  size_t pull(PcmSource& src, uint32_t outRate, int16_t* out, size_t n);

 private:
  uint32_t pos_ = 0;  // дробная позиция между prev_ и cur_, Q16
  int16_t prev_ = 0, cur_ = 0;
  uint8_t have_ = 0;
};

// Клип громкой связи с карты: IMA ADPCM (блоками) или PCM 16 бит.
class ClipSource : public PcmSource {
 public:
  explicit ClipSource(SoundCard& card) : card_(card) {}
  bool open(const char* id);
  uint32_t rate() override { return info_.sampleRate; }
  size_t read(int16_t* out, size_t n) override;
  bool finished() override { return done_; }
  uint32_t durationMs() const { return info_.durationMs; }

 private:
  SoundCard& card_;
  char id_[65] = {0};
  WavInfo info_;
  uint32_t offset_ = 0;  // байт от начала данных
  int16_t block_[1024];
  size_t blockLen_ = 0, blockPos_ = 0;
  bool done_ = true;
};

class Mixer {
 public:
  explicit Mixer(uint32_t outRate) : rate_(outRate) {}
  uint32_t rate() const { return rate_; }

  // Фон: источник (nullptr — тишина) и громкость; fadeMs — плавность.
  void setBackground(PcmSource* src);
  PcmSource* background() const { return bg_; }
  void setBackgroundVolume(uint8_t volume, uint32_t fadeMs) { bgGain_.set(volumeToGain(volume), fadeMs, rate_); }
  void jumpBackgroundVolume(uint8_t volume) { bgGain_.jump(volumeToGain(volume)); }
  // Фон затих (после fade к нулю) — можно менять трек без щелчка.
  bool backgroundSilent() const { return bgGain_.current() == 0; }
  const GainRamp& backgroundGain() const { return bgGain_; }

  // Объявление: сначала сигнал (если chime), потом клип.
  void startClip(PcmSource* clip, uint8_t volume, bool chime);
  void stopClip();
  bool clipActive() const { return clip_ != nullptr || chimeLeft_ > 0; }

  // Заполнить out n сэмплами; true — было что-то слышно (усилитель включён).
  bool render(int16_t* out, size_t n);

 private:
  int16_t chimeSample();
  uint32_t rate_;
  PcmSource* bg_ = nullptr;
  Resampler bgRs_;
  GainRamp bgGain_;
  PcmSource* clip_ = nullptr;
  Resampler clipRs_;
  int32_t clipGain_ = 0;
  uint32_t chimeLeft_ = 0, chimePos_ = 0;
  uint32_t phase_ = 0;
  int16_t scratch_[256];
};

}  // namespace mb10d

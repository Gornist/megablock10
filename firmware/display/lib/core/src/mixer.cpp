#include "mixer.h"

#include <cstdio>
#include <cstring>

#include "sound.h"

namespace mb10d {

namespace {
constexpr int32_t kUnity = 1 << 15;

// Синус четверти периода, 64 точки, Q15 — для сигнала без <cmath> и float на каждом сэмпле.
const int16_t kQuarterSine[65] = {0,     804,   1608,  2410,  3212,  4011,  4808,  5602,  6393,  7179,  7962,  8739,  9512,
                                  10278, 11039, 11793, 12539, 13279, 14010, 14732, 15446, 16151, 16846, 17530, 18204, 18868,
                                  19519, 20159, 20787, 21403, 22005, 22594, 23170, 23731, 24279, 24811, 25329, 25832, 26319,
                                  26790, 27245, 27683, 28105, 28510, 28898, 29268, 29621, 29956, 30273, 30571, 30852, 31113,
                                  31356, 31580, 31785, 31971, 32137, 32285, 32412, 32521, 32609, 32678, 32728, 32757, 32767};

// phase — 0…2^32 на период.
int32_t sine(uint32_t phase) {
  uint32_t idx = phase >> 24;  // 0..255
  uint32_t q = idx >> 6, i = idx & 63;
  int32_t v = q == 0 ? kQuarterSine[i] : q == 1 ? kQuarterSine[64 - i] : q == 2 ? -kQuarterSine[i] : -kQuarterSine[64 - i];
  return v;
}

inline int16_t sat(int32_t v) { return int16_t(v > 32767 ? 32767 : v < -32768 ? -32768 : v); }
}  // namespace

int32_t volumeToGain(uint8_t volume) {
  uint32_t v = volume > 100 ? 100 : volume;
  return int32_t(v * v * uint32_t(kUnity) / 10000);
}

void GainRamp::set(int32_t target, uint32_t ms, uint32_t rate) {
  target_ = target;
  left_ = uint32_t(uint64_t(ms) * rate / 1000);
  if (left_ == 0) {
    cur_ = target_;
    step_ = 0;
    return;
  }
  step_ = (target_ - cur_) / int32_t(left_);
}

int32_t GainRamp::next() {
  if (left_ > 0) cur_ = --left_ == 0 ? target_ : cur_ + step_;
  return cur_;
}

size_t Resampler::pull(PcmSource& src, uint32_t outRate, int16_t* out, size_t n) {
  uint32_t inRate = src.rate();
  if (inRate == 0 || outRate == 0) return 0;
  // Шаг по входу на один выходной сэмпл, Q16.
  uint32_t step = uint32_t((uint64_t(inRate) << 16) / outRate);
  size_t done = 0;
  while (done < n) {
    // Нужны два соседних входных сэмпла вокруг позиции pos_ (доля между prev_ и cur_).
    while (have_ < 2 || pos_ >= (1u << 16)) {
      int16_t s;
      if (src.read(&s, 1) == 0) return done;
      if (have_ == 0) {
        prev_ = cur_ = s;
        have_ = 1;
        continue;
      }
      prev_ = cur_;
      cur_ = s;
      if (have_ == 1) have_ = 2;
      else pos_ -= 1u << 16;
    }
    out[done++] = int16_t(prev_ + int32_t((int64_t(cur_) - prev_) * int64_t(pos_) >> 16));
    pos_ += step;
  }
  return done;
}

bool ClipSource::open(const char* id) {
  std::snprintf(id_, sizeof id_, "%s", id);
  uint8_t head[128];
  uint32_t size = card_.clipSize(id_);
  size_t n = size < sizeof head ? size : sizeof head;
  done_ = true;
  if (!card_.readClip(id_, 0, head, n) || !parseWavHeader(head, n, size, info_)) return false;
  offset_ = 0;
  blockLen_ = blockPos_ = 0;
  done_ = false;
  return true;
}

size_t ClipSource::read(int16_t* out, size_t n) {
  size_t done = 0;
  while (done < n && !done_) {
    if (blockPos_ >= blockLen_) {
      if (offset_ >= info_.dataBytes) {
        done_ = true;
        break;
      }
      if (info_.format == kWavImaAdpcm) {
        uint8_t raw[1024];
        size_t len = info_.blockAlign <= sizeof raw ? info_.blockAlign : sizeof raw;
        if (offset_ + len > info_.dataBytes) len = info_.dataBytes - offset_;
        if (!card_.readClip(id_, info_.dataOffset + offset_, raw, len)) {
          done_ = true;
          break;
        }
        offset_ += uint32_t(len);
        size_t want = info_.samplesPerBlock <= 1024 ? info_.samplesPerBlock : 1024;
        blockLen_ = decodeImaBlock(raw, len, block_, want);
      } else {
        uint8_t raw[512];
        size_t len = info_.dataBytes - offset_ < sizeof raw ? info_.dataBytes - offset_ : sizeof raw;
        len &= ~size_t(1);
        if (len == 0 || !card_.readClip(id_, info_.dataOffset + offset_, raw, len)) {
          done_ = true;
          break;
        }
        offset_ += uint32_t(len);
        for (size_t i = 0; i < len / 2; i++) block_[i] = int16_t(raw[2 * i] | raw[2 * i + 1] << 8);
        blockLen_ = len / 2;
      }
      blockPos_ = 0;
      if (blockLen_ == 0) {
        done_ = true;
        break;
      }
    }
    size_t k = blockLen_ - blockPos_ < n - done ? blockLen_ - blockPos_ : n - done;
    std::memcpy(out + done, block_ + blockPos_, k * sizeof(int16_t));
    blockPos_ += k;
    done += k;
  }
  return done;
}

void Mixer::setBackground(PcmSource* src) {
  bg_ = src;
  bgRs_.reset();
}

void Mixer::startClip(PcmSource* clip, uint8_t volume, bool chime) {
  clip_ = clip;
  clipRs_.reset();
  clipGain_ = volumeToGain(volume);
  chimeLeft_ = chime ? uint32_t(uint64_t(kChimeMs) * rate_ / 1000) : 0;
  chimePos_ = 0;
}

void Mixer::stopClip() {
  clip_ = nullptr;
  chimeLeft_ = 0;
}

// Сигнал: два тона (880 и 660 Гц) по 0,35 с с мягкими краями и паузами — «дин-дон» перед объявлением.
int16_t Mixer::chimeSample() {
  uint32_t total = uint32_t(uint64_t(kChimeMs) * rate_ / 1000);
  uint32_t t = chimePos_++;
  chimeLeft_--;
  uint32_t tone = total * 35 / 90, gap = total * 5 / 90;
  uint32_t local;
  uint32_t freq;
  if (t < tone) {
    local = t;
    freq = 880;
  } else if (t >= tone + gap && t < 2 * tone + gap) {
    local = t - tone - gap;
    freq = 660;
  } else {
    return 0;
  }
  phase_ += uint32_t((uint64_t(freq) << 32) / rate_);
  // Огибающая: 10 мс вверх, затухание к концу тона.
  uint32_t attack = rate_ / 100;
  int32_t env = local < attack ? int32_t(local * kUnity / attack) : int32_t(uint64_t(tone - local) * kUnity / tone);
  return int16_t((sine(phase_) * env >> 15) * clipGain_ >> 15 >> 1);
}

bool Mixer::render(int16_t* out, size_t n) {
  bool audible = false;
  size_t done = 0;
  while (done < n) {
    size_t k = n - done < 256 ? n - done : 256;
    // Фон.
    size_t got = bg_ ? bgRs_.pull(*bg_, rate_, scratch_, k) : 0;
    for (size_t i = 0; i < k; i++) {
      int32_t g = bgGain_.next();
      int32_t s = i < got ? scratch_[i] : 0;
      out[done + i] = int16_t(s * g >> 15);
      if (g > 0 && s != 0) audible = true;
    }
    // Сигнал и объявление поверх.
    for (size_t i = 0; i < k; i++) {
      if (chimeLeft_ > 0) {
        out[done + i] = sat(out[done + i] + chimeSample());
        audible = true;
      } else if (clip_) {
        int16_t s;
        if (clipRs_.pull(*clip_, rate_, &s, 1) == 1) {
          out[done + i] = sat(out[done + i] + (int32_t(s) * clipGain_ >> 15));
          audible = true;
        } else if (clip_->finished()) {
          clip_ = nullptr;
        }
      }
    }
    done += k;
  }
  return audible;
}

}  // namespace mb10d

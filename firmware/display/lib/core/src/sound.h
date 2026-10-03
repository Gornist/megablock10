#pragma once
#include <cstddef>
#include <cstdint>

#include "hal.h"
#include "protocol.h"

// Звук точки (docs/sound-nodes.md): фон канала с карты памяти и объявления громкой связи. Здесь — вся логика без железа:
// желаемое состояние с версией (переживает перезагрузку), плейлист (порядок, перемешивание, пропуск отсутствующих треков,
// пауза между треками), приём клипа кусками с докачкой и проверкой sha256, объявление с приглушением фона, статус для HELLO,
// каталог карты. Декодирование и вывод звука — за AudioOut (ESP32: MP3 + IMA ADPCM → I²S; ПК: журнал вместо динамика).
namespace mb10d {

constexpr size_t kAudioJsonMax = 4096;
constexpr size_t kMaxTracks = 200;
constexpr size_t kTrackNameMax = 96;
constexpr size_t kClipIdLen = 64;  // sha256 в hex
constexpr size_t kClipChunkMax = 16 * 1024;
constexpr size_t kAudioPayloadMax = 4 + kClipChunkMax;
constexpr size_t kListReplyMax = 1024;
// Сигнал перед объявлением — его длительность прибавляется к длительности клипа в ответе ANNOUNCE.
constexpr uint32_t kChimeMs = 900;
// Что не задано в AUDIO_STATE / ANNOUNCE (docs/sound-nodes.md): громкость канала, переход между треками, громкость объявления
// и до скольки процентов приглушается фон на время объявления.
constexpr uint8_t kDefaultVolume = 60;
constexpr uint32_t kDefaultFadeMs = 1500;
constexpr uint8_t kDefaultAnnounceVolume = 80;
constexpr uint8_t kDefaultDuckPct = 15;
extern const char* const kAudioFile;

// Раскладка карты — общая для реализаций SoundCard (src/esp32: корень /mb10, src/host: корень --sd): <корень>/tracks/<имя>,
// <корень>/clips/<sha256>.wav, недокачанный — <sha256>.part.
constexpr char kSdTracksDir[] = "/tracks";
constexpr char kSdClipsDir[] = "/clips";
constexpr char kClipExt[] = ".wav";
constexpr char kPartExt[] = ".part";

// Карта памяти. Треки — только чтение, заливаются руками; клипы — сервер по CLIP_*. Список треков реализация держит в памяти
// (сканирует при вставке карты), здесь — только из него.
class SoundCard {
 public:
  virtual ~SoundCard() = default;
  virtual bool present() = 0;
  virtual size_t trackCount() = 0;
  // По алфавиту (как в LIST).
  virtual bool trackName(size_t index, char* out, size_t cap) = 0;
  virtual bool hasTrack(const char* name) = 0;
  virtual bool hasClip(const char* id) = 0;
  virtual uint32_t clipSize(const char* id) = 0;
  virtual bool readClip(const char* id, uint32_t offset, uint8_t* buf, size_t len) = 0;
  // Сколько байт уже в .part (0 — нет файла).
  virtual uint32_t partSize(const char* id) = 0;
  // Записать с offset: файл обрезается до offset и дописывается. false — ошибка записи.
  virtual bool writePart(const char* id, uint32_t offset, const uint8_t* data, size_t len) = 0;
  virtual bool readPart(const char* id, uint32_t offset, uint8_t* buf, size_t len) = 0;
  // .part → .wav (rename: либо целый клип, либо никакого).
  virtual bool commitPart(const char* id) = 0;
  virtual void removePart(const char* id) = 0;
};

// Вывод звука. Фон — один трек за раз: startTrack заменяет текущий (с затуханием старого); объявление — поверх фона.
class AudioOut {
 public:
  virtual ~AudioOut() = default;
  virtual bool startTrack(const char* name, uint8_t volume, uint32_t fadeMs) = 0;
  virtual void stopTrack(uint32_t fadeMs) = 0;
  // Громкость фона: смена громкости канала, приглушение на время объявления и возврат.
  virtual void setTrackVolume(uint8_t volume, uint32_t fadeMs) = 0;
  // Трек ещё звучит; false — доиграл или не смог (битый файл) — ядро берёт следующий.
  virtual bool trackPlaying() = 0;
  virtual bool startClip(const char* id, uint8_t volume, bool chime) = 0;
  virtual void stopClip() = 0;
  virtual bool clipPlaying() = 0;
};

// Id клипа — sha256 его WAV в hex: 64 строчных hex-символа.
bool isClipId(const char* s);

// Приём клипа кусками с докачкой: CLIP_BEGIN (sha256 ‖ u32 длина) → have — сколько уже есть на карте; CLIP_CHUNK (u32 смещение
// ‖ данные) → have; CLIP_COMMIT — sha256 .part совпал → клип на карте (rename). Загрузка — одна на соединение.
class ClipUpload {
 public:
  ClipUpload(SoundCard& card, Platform& platform) : card_(card), platform_(platform) {}
  Nack begin(const uint8_t* payload, uint32_t& have);
  Nack chunk(const uint8_t* payload, size_t len, uint32_t& have);
  Nack commit();
  void reset() { active_ = false; }

 private:
  SoundCard& card_;
  Platform& platform_;
  bool active_ = false;
  char id_[kClipIdLen + 1] = {0};
  uint32_t len_ = 0;
};

class Sound {
 public:
  Sound(SoundCard& card, AudioOut& out, Storage& storage, Platform& platform);

  // Загрузка: сохранённое состояние — и сразу играть (фон стартует до Wi-Fi).
  void boot();
  // Раз в цикл: следующий трек, пауза между треками, конец объявления, карту вставили/вынули.
  void tick();

  uint32_t version() const { return version_; }
  bool announcing() const { return annState_ == AnnState::Playing; }
  const char* nowPlaying() const { return bg_ == Bg::Playing ? current_ : nullptr; }
  uint8_t volume() const { return volume_; }

  // AUDIO_STATE: JSON {tracks[], shuffle, gapMs, volume, fadeMs}, версия — seq. Меньше применённой — STALE_VERSION.
  Nack applyState(uint32_t version, const uint8_t* json, size_t len);

  // Клип: CLIP_BEGIN (sha256 ‖ u32 длина) → have — сколько уже есть; CLIP_CHUNK (u32 смещение ‖ данные) → have;
  // CLIP_COMMIT — sha256 совпал → клип на карте. Загрузка — одна на соединение (resetUpload при новом).
  Nack clipBegin(const uint8_t* payload, uint32_t& have) { return upload_.begin(payload, have); }
  Nack clipChunk(const uint8_t* payload, size_t len, uint32_t& have) { return upload_.chunk(payload, len, have); }
  Nack clipCommit() { return upload_.commit(); }
  void resetUpload() { upload_.reset(); }

  // ANNOUNCE: JSON {clip, volume, chime, duck}; id — seq. durationMs — сколько будет звучать (со сигналом).
  Nack announce(uint32_t id, const uint8_t* json, size_t len, uint32_t& durationMs);
  void stopAnnounce();

  // LIST: {"total":N,"names":[…]} начиная с start, не больше cap байт.
  size_t listJson(uint16_t start, char* out, size_t cap);
  // Для HELLO: {"v":…,"playing":…,"vol":…,"tracks":…,"sd":…,"missing":[…],"ann":{…}}.
  size_t statusJson(char* out, size_t cap);

 private:
  enum class Bg { Silent, Playing, Gap };
  enum class AnnState { None, Playing, Done, Failed, Stopped };

  bool parseState(const char* json, size_t len);
  // audio.bin: прочитать сохранённое состояние (false — нет или битое) / записать новое.
  bool loadSaved();
  void save(uint32_t version, const uint8_t* json, size_t len);
  // Фон — обратно на громкость канала после объявления.
  void unduck();
  void rebuildOrder(const char* keep);
  void refreshMissing();
  void playNext();
  uint8_t bgVolume() const;
  uint32_t rand32();
  const char* track(size_t i) const { return names_ + offs_[i]; }

  SoundCard& card_;
  AudioOut& out_;
  Storage& storage_;
  Platform& platform_;

  // Применённое состояние: сырой JSON (для сравнения и сохранения) и разобранное.
  uint32_t version_ = 0;
  char json_[kAudioJsonMax + 1];
  size_t jsonLen_ = 0;
  char names_[kAudioJsonMax];
  uint16_t offs_[kMaxTracks];
  uint16_t count_ = 0;
  bool shuffle_ = false;
  uint32_t gapMs_ = 0;
  uint32_t fadeMs_ = kDefaultFadeMs;
  uint8_t volume_ = kDefaultVolume;
  bool missing_[kMaxTracks];

  uint16_t order_[kMaxTracks];
  uint16_t pos_ = 0;
  uint32_t rng_ = 0x9e3779b9;

  Bg bg_ = Bg::Silent;
  char current_[kTrackNameMax + 1] = {0};
  uint32_t gapUntil_ = 0;
  bool cardWasPresent_ = false;

  AnnState annState_ = AnnState::None;
  uint32_t annId_ = 0;
  uint8_t duck_ = kDefaultDuckPct;

  ClipUpload upload_;
};

}  // namespace mb10d

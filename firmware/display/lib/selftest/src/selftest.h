#pragma once
#include <cstddef>
#include <cstdint>

#include "protocol.h"

// Самопроверка прошивки изнутри (docs/firmware-plan.md, Ф4): клиент протокола, который делает то же, что сервер мастера и набор
// совместимости C1–C20, но из самой платы — Wokwi не умеет пробрасывать порт снаружи к эмулируемой плате (у wokwi-cli нет
// net.forward), поэтому плата стучится в свой же TCP-сервер через 127.0.0.1. Тот же код на ПК — display_selftest против
// display_host. Сокеты BSD: POSIX на ПК, lwIP на ESP32.
//
// Вывод — строки `SELFTEST PASS <имя>` / `SELFTEST FAIL <имя>: <почему>`; по ним сценарий Wokwi решает, прошла ли проверка.
namespace mb10d {
namespace selftest {

struct Target {
  const char* host;
  uint16_t port;
  const char* deviceId;
  uint8_t key[kKeySize];
  uint16_t width;
  uint16_t height;
  // Таймауты дисплея (Config): проверки закрытия ждут их с запасом.
  uint32_t headerTimeoutMs;
  uint32_t payloadTimeoutMs;
};

using LogFn = void (*)(const char* line, void* ctx);

class Runner {
 public:
  // work — буфер под исходящий кадр картинки: не меньше workSize(width, height).
  Runner(const Target& target, uint8_t* work, LogFn log, void* ctx);
  static size_t workSize(uint16_t width, uint16_t height) { return kHeaderSize + frameBytes(width, height); }

  // Проверки протокола по порядку; число проваленных. После них на дисплее — версия displayed().
  int runProtocol();
  // REBOOT → OK: дисплей уходит в перезагрузку.
  bool reboot();
  // Подключаться до timeoutMs (дисплей грузится), HELLO должен нести версию expected — кадр восстановлен из flash.
  bool expectVersion(const char* name, uint32_t expected, uint32_t timeoutMs);

  // Звук (docs/sound-nodes.md), если HELLO докладывает роль audio: AUDIO_STATE с версией version, старая версия отвергается,
  // LIST, ANNOUNCE несуществующего клипа — MISSING_CLIP, версия видна в HELLO. Точка без звука — пропуск (0 провалов).
  int runAudio(uint32_t version);
  // HELLO несёт версию звука expected (состояние восстановлено из flash после перезагрузки).
  bool expectAudioVersion(const char* name, uint32_t expected, uint32_t timeoutMs);
  bool audio() const { return audio_; }

  uint32_t displayed() const { return displayed_; }
  int failures() const { return failures_; }
  void pass(const char* name);
  void fail(const char* name, const char* fmt, ...);

 private:
  struct Reply;
  class Conn;
  bool connectHello(Conn& c, Reply& hello, const char*& why, uint32_t timeoutMs = 3000);
  bool readReply(Conn& c, const uint8_t* nonce, Reply& r, uint32_t timeoutMs, const char*& why);
  size_t buildImage(uint32_t version, const uint8_t* nonce, const uint8_t* key, const char* deviceId = nullptr);
  size_t buildCommand(MsgType type, const uint8_t* payload, size_t len, const uint8_t* nonce);
  // Отправить кадр в новом соединении и ждать NACK с кодом expected.
  void expectNack(const char* name, Nack expected, bool closes, size_t (Runner::*build)(const uint8_t* nonce));
  size_t imageNextVersion(const uint8_t* nonce);
  size_t imageBadCrc(const uint8_t* nonce);
  size_t imageForeignKey(const uint8_t* nonce);
  size_t imageStale(const uint8_t* nonce);
  size_t imageWrongDevice(const uint8_t* nonce);
  size_t imageBadMagic(const uint8_t* nonce);
  size_t unknownType(const uint8_t* nonce);

  void checkHello();
  void checkImage();
  void checkClosesAfter(const char* name, bool sendPartial, uint32_t expectMs);
  void checkPreempt();
  void checkTestAndBacklight();
  // Отправить команду в новом соединении и прочитать ответ; false — провал уже записан.
  bool command(const char* name, MsgType type, uint32_t seq, const uint8_t* payload, size_t len, Reply& r);
  // Отправить команду в уже открытом соединении и прочитать ответ.
  bool exchange(Conn& c, const uint8_t* nonce, MsgType type, uint32_t seq, const uint8_t* payload, size_t len, Reply& r, const char*& why);
  // Клип на карту кусками с обрывом посреди и докачкой, объявление, «доиграло» в HELLO (только если карта есть).
  void checkClipAndAnnounce();
  void log(const char* fmt, ...);

  Target t_;
  uint8_t* work_;
  LogFn log_;
  void* ctx_;
  uint32_t displayed_ = 0;
  int failures_ = 0;
  bool audio_ = false;
  bool sd_ = false;
};

}  // namespace selftest
}  // namespace mb10d

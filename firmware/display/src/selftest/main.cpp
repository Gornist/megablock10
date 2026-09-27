// Самопроверка дисплея с ПК (docs/firmware-plan.md, Ф4): тот же клиент lib/selftest, что крутится внутри платы в Wokwi, —
// здесь против прошивки для ПК (display_host) или платы в сети. Сначала отлаживается тут, потом едет в ESP32.
//
//   display_selftest --id display-017 --secret <64 hex> [--host 127.0.0.1] [--port 47200] [--width 792 --height 272]
//                    [--header-timeout 2000 --payload-timeout 5000] [--reboot]
//
// --reboot — после проверок протокола REBOOT и ожидание, что после загрузки HELLO несёт ту же версию (кадр из flash).
// Код выхода 0 — всё прошло (последняя строка SELFTEST ALL PASSED), 1 — есть FAIL, 2 — неверные аргументы.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "selftest.h"

using namespace mb10d;

int main(int argc, char** argv) {
  std::string host = "127.0.0.1", id, secret;
  int port = 47200, width = 792, height = 272, headerTimeout = 2000, payloadTimeout = 5000;
  bool reboot = false;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto val = [&](void) -> const char* { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--host") host = val();
    else if (a == "--id") id = val();
    else if (a == "--secret") secret = val();
    else if (a == "--port") port = std::atoi(val());
    else if (a == "--width") width = std::atoi(val());
    else if (a == "--height") height = std::atoi(val());
    else if (a == "--header-timeout") headerTimeout = std::atoi(val());
    else if (a == "--payload-timeout") payloadTimeout = std::atoi(val());
    else if (a == "--reboot") reboot = true;
    else {
      std::fprintf(stderr, "unknown option %s\n", a.c_str());
      return 2;
    }
  }
  selftest::Target t{};
  t.host = host.c_str();
  t.port = uint16_t(port);
  t.deviceId = id.c_str();
  t.width = uint16_t(width);
  t.height = uint16_t(height);
  t.headerTimeoutMs = uint32_t(headerTimeout);
  t.payloadTimeoutMs = uint32_t(payloadTimeout);
  if (id.empty() || id.size() > kDeviceIdSize || !parseHex(secret.c_str(), t.key, sizeof t.key) || width <= 0 || height <= 0) {
    std::fprintf(stderr, "usage: display_selftest --id <id> --secret <64 hex> [--host H] [--port P] [--width W --height H] [--reboot]\n");
    return 2;
  }
  std::vector<uint8_t> work(selftest::Runner::workSize(t.width, t.height));
  selftest::Runner runner(t, work.data(), [](const char* line, void*) { std::printf("%s\n", line), std::fflush(stdout); }, nullptr);
  runner.runProtocol();
  // Звук — если точка его докладывает; версия 7 — выше нуля свежей точки.
  if (runner.failures() == 0) runner.runAudio(7);
  if (reboot && runner.failures() == 0 && runner.reboot()) {
    runner.expectVersion("reboot-restores-frame", runner.displayed(), 15000);
    if (runner.audio()) runner.expectAudioVersion("reboot-restores-audio", 7, 15000);
  }
  if (runner.failures() > 0) {
    std::printf("SELFTEST DONE: %d FAIL\n", runner.failures());
    return 1;
  }
  std::printf("SELFTEST ALL PASSED\n");
  return 0;
}

#!/bin/bash
# Самопроверка прошивки в эмуляторе Espressif esp-emulator (esp-emu, github.com/espressif/esp-emulator) — замена Wokwi без
# токена и месячной квоты. Та же самопроверка изнутри платы, что в Wokwi (lib/selftest, selftest_task.cpp), сборка
# crowpanel579-espemu. Эмулятор сам поднимает точку доступа (имя — вшитое в сборку Wokwi-GUEST, открытая) с DHCP.
# Чего в эмуляторе нет: microSD и I²S — звук проверяется только по протоколу, без карты (клип, объявление и MP3 — в Wokwi
# и на плате).
#
#   firmware/display/tools/espemu_selftest.sh [--no-build] [--timeout-s 420] [--log файл]
#
# Эмулятор скачивается из релиза (версия закреплена, sha256 сверяется) в ~/.cache/esp-emu/<версия>/; свой — ESP_EMU=путь.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=1
TIMEOUT=420
LOG=espemu-serial.log
while [ $# -gt 0 ]; do
  case $1 in
    --no-build) BUILD=0 ;;
    --timeout-s) TIMEOUT=$2; shift ;;
    --log) LOG=$2; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
VERSION=0.45.0
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) PLATFORM=x86_64-unknown-linux-gnu ;;
  Linux-aarch64) PLATFORM=aarch64-unknown-linux-gnu ;;
  Darwin-arm64) PLATFORM=aarch64-apple-darwin ;;
  *) echo "esp-emu: нет готовой сборки для $(uname -s)-$(uname -m)" >&2; exit 3 ;;
esac
EMU=${ESP_EMU:-$HOME/.cache/esp-emu/$VERSION/esp-emu}
if [ ! -x "$EMU" ]; then
  # Не через install.sh: тот ищет последнюю версию по github.com/…/releases/latest, а нужна закреплённая.
  base=https://github.com/espressif/esp-emulator/releases/download/v$VERSION
  archive=esp-emu-$VERSION-$PLATFORM.tar.gz
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$base/$archive" -o "$tmp/$archive"
  curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS"
  (cd "$tmp" && grep " $archive\$" SHA256SUMS | sha256sum -c - > /dev/null)
  tar -xzf "$tmp/$archive" -C "$tmp"
  mkdir -p "$(dirname "$EMU")"
  install -m 755 "$(find "$tmp" -type f -name esp-emu | head -1)" "$EMU"
fi
ENV=crowpanel579-espemu
OUT=.pio/build/$ENV
[ "$BUILD" = 1 ] && pio run -e "$ENV"
BOOT_APP0=$(find "${PLATFORMIO_CORE_DIR:-$HOME/.platformio}/packages/framework-arduinoespressif32/tools/partitions" -name boot_app0.bin | head -1)
# Образ flash целиком, как для Wokwi (загрузчик с 0x0 у S3, таблица разделов, boot_app0, прошивка): эмулятор грузится с ROM
# через загрузчик IDF. Файл образа эмулятор не меняет (без --save-state): каждый прогон — с чистой NVS и LittleFS.
pio pkg exec -p tool-esptoolpy -- esptool.py --chip esp32s3 merge_bin -o "$OUT/merged.bin" --flash_mode dio --flash_size 8MB \
  0x0 "$OUT/bootloader.bin" 0x8000 "$OUT/partitions.bin" 0xe000 "$BOOT_APP0" 0x10000 "$OUT/firmware.bin" > /dev/null
# --exit-on — успех; по первому «SELFTEST FAIL» обрываем сами (grep закрывает канал). Код выхода esp-emu не показатель: по
# --timeout он тоже 0 — итог только по журналу.
set +e
"$EMU" --chip esp32s3 --firmware "$OUT/merged.bin" --net user --wifi-ssid Wokwi-GUEST --wifi-auth open --wifi-password '' \
  --timeout "${TIMEOUT}s" --exit-on "SELFTEST ALL PASSED" 2>&1 | tee "$LOG" | grep -a -m1 -q "SELFTEST FAIL"
set -e
grep -a "SELFTEST \(PASS\|FAIL\|DONE\|ALL\)\|rst:0x" "$LOG" | grep -v "SELFTEST PASS" || true
if grep -aq "SELFTEST FAIL" "$LOG"; then exit 1; fi
if ! grep -aq "SELFTEST ALL PASSED" "$LOG"; then
  echo "esp-emu: нет «SELFTEST ALL PASSED» за ${TIMEOUT} с (журнал — $LOG)" >&2
  exit 1
fi
# Причину сброса после паники эмулятор пишет как сторож RTC (ESP_RST_WDT) — что сработал именно сторож задач, видно по журналу.
if ! grep -aq "task_wdt\|Task watchdog got triggered" "$LOG"; then
  echo "esp-emu: SELFTEST ALL PASSED, но в журнале нет срабатывания сторожа задач" >&2
  exit 1
fi
echo "esp-emu: SELFTEST ALL PASSED"

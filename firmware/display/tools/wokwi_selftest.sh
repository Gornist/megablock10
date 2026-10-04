#!/bin/bash
# Самопроверка прошивки в эмуляторе Wokwi (docs/firmware-plan.md, Ф4): сборка crowpanel579-wokwi, склейка образа flash
# (загрузчик + таблица разделов + прошивка — иначе Wokwi кладёт свою таблицу разделов, и LittleFS не там), прогон wokwi-cli
# до строки «SELFTEST ALL PASSED» или первого «SELFTEST FAIL».
#
#   WOKWI_CLI_TOKEN=… firmware/display/tools/wokwi_selftest.sh [--no-build] [--timeout-ms 180000] [--log файл]
# Код выхода 4 — у аккаунта Wokwi кончилась месячная квота CI-минут: самопроверка не запускалась (не провал прошивки).
#
# Токен — только из окружения (настройки облачного окружения / секрет GitHub Actions), в репозиторий и журнал не попадает.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=1
TIMEOUT=180000
LOG=wokwi-serial.log
while [ $# -gt 0 ]; do
  case $1 in
    --no-build) BUILD=0 ;;
    --timeout-ms) TIMEOUT=$2; shift ;;
    --log) LOG=$2; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "${WOKWI_CLI_TOKEN:-}" ]; then
  echo "WOKWI_CLI_TOKEN не задан — самопроверку в Wokwi не запустить" >&2
  exit 3
fi
WOKWI=$(command -v wokwi-cli || echo "$HOME/.local/bin/wokwi-cli")
ENV=crowpanel579-wokwi
OUT=.pio/build/$ENV
[ "$BUILD" = 1 ] && pio run -e "$ENV"
BOOT_APP0=$(find "${PLATFORMIO_CORE_DIR:-$HOME/.platformio}/packages/framework-arduinoespressif32/tools/partitions" -name boot_app0.bin | head -1)
# ESP32-S3: загрузчик с 0x0 (у ESP32 — 0x1000); смещения — как у pio run -t upload.
pio pkg exec -p tool-esptoolpy -- esptool.py --chip esp32s3 merge_bin -o "$OUT/merged.bin" --flash_mode dio --flash_size 8MB \
  0x0 "$OUT/bootloader.bin" 0x8000 "$OUT/partitions.bin" 0xe000 "$BOOT_APP0" 0x10000 "$OUT/firmware.bin" > /dev/null
# API Wokwi иногда рвёт соединение ещё до запуска платы («Connection to transport closed unexpectedly: code 1006», журнал
# платы пуст) — и без второй симуляции на токене (CI 2026-09-27: задачи шли по очереди, а обрыв был). Такой обрыв — не
# провал самопроверки: повторить до двух раз. Если плата успела что-то написать в журнал — итог как есть, без повторов.
for attempt in 1 2 3; do
  rm -f "$LOG"
  set +e
  "$WOKWI" . --timeout "$TIMEOUT" --expect-text "SELFTEST ALL PASSED" --fail-text "SELFTEST FAIL" --serial-log-file "$LOG" 2>&1 | tee wokwi-cli.out
  code=${PIPESTATUS[0]}
  set -e
  [ "$code" -eq 0 ] && exit 0
  # Квота кончилась (октябрь 2026: «You have used up your Free plan monthly CI minute quota») — повторы не помогут, плата не
  # запускалась. Отдельный код, чтобы CI показал «не проверено», а не «прошивка сломана».
  if grep -q "minute quota" wokwi-cli.out; then
    echo "wokwi: исчерпана месячная квота CI-минут — самопроверка НЕ запускалась" >&2
    exit 4
  fi
  if [ -s "$LOG" ] || ! grep -q "API Error" wokwi-cli.out; then exit "$code"; fi
  echo "wokwi: обрыв API до запуска платы (попытка $attempt из 3)" >&2
  [ "$attempt" -lt 3 ] && sleep 15
done
exit "$code"

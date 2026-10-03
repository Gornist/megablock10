#!/bin/bash
# ctest: самопроверка (lib/selftest) против прошивки для ПК — тот же клиент, что внутри платы в Wokwi (docs/firmware-plan.md, Ф4).
# Аргументы: путь к display_host, путь к display_selftest[, --with-sd][, дальше — флаги display_host, например --roles display,audio].
# --with-sd — карта точки (каталог) с двумя треками канала самопроверки: проверяются ещё клип с докачкой и объявление.
set -euo pipefail
HOST_BIN=$1
SELFTEST_BIN=$2
shift 2
DIR=$(mktemp -d)
EXTRA=()
if [ "${1:-}" = "--with-sd" ]; then
  shift
  mkdir -p "$DIR/sd/tracks"
  head -c 16000 /dev/zero > "$DIR/sd/tracks/selftest-a.mp3"
  head -c 16000 /dev/zero > "$DIR/sd/tracks/selftest-b.mp3"
  EXTRA=(--sd "$DIR/sd")
fi
SECRET=$(printf '5a%.0s' $(seq 32))
# Порт — ниже эфемерного диапазона Linux (32768–60999): раньше брался из 20000–39999, и в CI прошивка не могла его занять —
# «cannot listen on 127.0.0.1:39608: Address already in use» (чужое исходящее соединение). Занят всё равно — другой порт.
PID=
trap 'kill $PID 2> /dev/null || true; rm -rf "$DIR"' EXIT
for attempt in 1 2 3 4 5; do
  PORT=$((20000 + RANDOM % 12000))
  "$HOST_BIN" --id selftest-host --secret "$SECRET" --port "$PORT" --host 127.0.0.1 --out "$DIR" --delay 50 \
    --header-timeout 700 --payload-timeout 1200 "$@" "${EXTRA[@]}" > "$DIR/host.log" 2>&1 &
  PID=$!
  # Не смогла занять порт — выходит сразу; ждём это до 1 с, иначе порт её.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$PID" 2> /dev/null || break
    grep -q "cannot listen" "$DIR/host.log" && break
    sleep 0.1
  done
  grep -q "cannot listen" "$DIR/host.log" || break
  wait "$PID" 2> /dev/null || true
  echo "порт $PORT занят (попытка $attempt из 5), другой" >&2
done
code=0
"$SELFTEST_BIN" --id selftest-host --secret "$SECRET" --port "$PORT" --header-timeout 700 --payload-timeout 1200 --reboot || code=$?
if [ "$code" -ne 0 ]; then
  echo "--- журнал display_host ---"
  cat "$DIR/host.log"
fi
exit "$code"

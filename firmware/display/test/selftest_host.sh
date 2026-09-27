#!/bin/bash
# ctest: самопроверка (lib/selftest) против прошивки для ПК — тот же клиент, что внутри платы в Wokwi (docs/firmware-plan.md, Ф4).
# Аргументы: путь к display_host, путь к display_selftest.
set -euo pipefail
HOST_BIN=$1
SELFTEST_BIN=$2
DIR=$(mktemp -d)
PORT=$((20000 + RANDOM % 20000))
SECRET=$(printf '5a%.0s' $(seq 32))
"$HOST_BIN" --id selftest-host --secret "$SECRET" --port "$PORT" --host 127.0.0.1 --out "$DIR" --delay 50 \
  --header-timeout 700 --payload-timeout 1200 > "$DIR/host.log" 2>&1 &
PID=$!
trap 'kill $PID 2> /dev/null || true; rm -rf "$DIR"' EXIT
code=0
"$SELFTEST_BIN" --id selftest-host --secret "$SECRET" --port "$PORT" --header-timeout 700 --payload-timeout 1200 --reboot || code=$?
if [ "$code" -ne 0 ]; then
  echo "--- журнал display_host ---"
  cat "$DIR/host.log"
fi
exit "$code"

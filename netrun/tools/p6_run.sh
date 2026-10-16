#!/usr/bin/env bash
# Прогон П6 на очках: установить APK (~/pico-p6/netrun-client-p6.apk), положить адрес и токен, поднять сервер srv_p6.sh, вывести игру на передний план
# и держать сервер, пока не придёт слово «снял» (файл ~/pico-p6/stop) или не выйдет время. Только внутри брони Devbox и ТОЛЬКО после слова владельца «надеваю»:
#   scripts/box.sh pico run Godot <мин> --port 7777 -- bash netrun/tools/p6_run.sh      (на devbox, из этой копии netrun)
# Журналы (server.log, logcat) — в PICO_RUN_DIR; игра останавливается и очки гасит сам run. Без своих wake/sleep/KEYCODE и без нажатий в окнах.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HOME/netrun-env.sh" ] && . "$HOME/netrun-env.sh"
. "$HERE/box_guard.sh"
PACKAGE="com.megablok10.netrun"
COMPONENT="$PACKAGE/com.godot.game.GodotAppLauncher"
APK="${P6_APK:-$HOME/pico-p6/netrun-client-p6.apk}"
STOP="$HOME/pico-p6/stop"
OUT="${PICO_RUN_DIR:-$HOME/pico-p6/run-$(date +%m%d-%H%M)}"
MAX_SEC=$(( ${P6_MIN:-60} * 60 ))
mkdir -p "$OUT"; rm -f "$STOP"

box_has || { echo "p6_run: нужен devbox (box.sh), очки без брони не трогаю" >&2; exit 2; }
serial="${PICO_SERIAL:-$(adb devices | awk '$2=="device"{print $1}')}"
[ "$(echo "$serial" | grep -c .)" = 1 ] || { echo "p6_run: нужно ровно одно устройство или PICO_SERIAL" >&2; exit 1; }
export PICO_SERIAL="$serial"

[ -f "$APK" ] || { echo "p6_run: нет $APK (сборка: netrun/tools/p6_build.sh)" >&2; exit 1; }
adb -s "$serial" install -r "$APK" </dev/null 2>&1 | tail -2
[ "${PIPESTATUS[0]}" = 0 ] || { echo "p6_run: install не прошёл (несовместимая подпись — без uninstall стоп)" >&2; exit 3; }

host=$(ip -4 -o addr show scope global | awk '$2 !~ /tailscale|tun/ {sub(/\/.*/, "", $4); print $4; exit}')
[ -n "$host" ] || { echo "p6_run: нет LAN-адреса devbox" >&2; exit 1; }
"$HERE/pico.sh" provision --host="$host" --token=t03:token-t03 --port=7777 </dev/null 2>&1 | tail -2

nohup bash "$HERE/srv_p6.sh" > "$OUT/server.log" 2>&1 </dev/null &
spid=$!
trap 'kill "$spid" 2>/dev/null; adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null >/dev/null 2>&1' EXIT
sleep 8
kill -0 "$spid" 2>/dev/null || { echo "p6_run: сервер не поднялся"; tail -5 "$OUT/server.log"; exit 1; }
grep -q "ENet слушает" "$OUT/server.log" || { echo "p6_run: сервер не слушает порт"; tail -5 "$OUT/server.log"; exit 1; }

adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null
adb -s "$serial" logcat -c </dev/null
rdy=$(bash "$BOX_CTL" pico ready "$BOX_OWNER" </dev/null 2>&1) || { echo "p6_run: очки не готовы — $rdy"; exit 20; }
st=$(bash "$BOX_CTL" pico start "$BOX_OWNER" "$COMPONENT" </dev/null 2>&1) || { echo "p6_run: игра не вышла на передний план — $st"; exit 20; }
echo "p6_run: игра запущена, сервер $host:7777 (pid $spid), журнал $OUT; остановить прогон: touch $STOP"

t=0
while [ "$t" -lt "$MAX_SEC" ] && [ ! -e "$STOP" ] && kill -0 "$spid" 2>/dev/null; do
  sleep 10; t=$((t + 10))
done
adb -s "$serial" logcat -d </dev/null > "$OUT/logcat.txt" 2>/dev/null || true
"$HERE/pico.sh" log </dev/null > "$OUT/pico-log.txt" 2>&1 || true
echo "p6_run: конец (${t} с), журналы в $OUT"

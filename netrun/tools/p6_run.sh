#!/usr/bin/env bash
# Показ стенда П6 на очках: установить APK (~/pico-p6/netrun-client-p6.apk), положить адрес и токен, поднять сервер srv_p6.sh, вывести игру на передний план
# и держать сервер, пока не придёт «снял» (`pico unshow` шлёт TERM группе процессов) или файл ~/pico-p6/stop, или не выйдет время.
# Человеку в очках (бронь «Владелец», решение владельца 16.10 после первого П6): ТОЛЬКО по его слову «надеваю», через показ Devbox —
#   scripts/box.sh pico show Владелец --minutes <мин> -- bash netrun/tools/p6_run.sh      (на devbox, из этой копии netrun)
# `pico show` сам берёт бронь, проверяет очки (лобби допустимо), не гасит и не паркует карточку границы; BOX_OWNER/BOX_SHOW/PICO_RUN_DIR берёт оттуда.
# Автопрогон без человека — `pico run Godot <мин> --port 7777 -- bash netrun/tools/p6_run.sh` (тогда `pico ready` здесь обязателен).
# Не готово/игра не встала на передний план — НЕ выход: сервер остаётся (человек запустит игру из библиотеки). Сервер живёт до конца скрипта, а не до ошибки.
# Журналы (server.log, logcat, pico-log) — в PICO_RUN_DIR. Без своих wake/sleep/KEYCODE и без нажатий в окнах.
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

# Свежий сервер (старый стенд на 7777 — вон), в своей группе процессов: умирает только вместе с этим скриптом (TERM от `pico unshow`/конец времени/stop).
old=$(ss -ulpn 2>/dev/null | grep ':7777 ' | sed -nE 's/.*pid=([0-9]+).*/\1/p' | head -1)   # только то, что держит порт 7777
[ -z "$old" ] || { kill "$old" 2>/dev/null; sleep 2; }
nohup bash "$HERE/${P6_SERVER:-srv_p6.sh}" > "$OUT/server.log" 2>&1 </dev/null &   # стенд следующего показа — P6_SERVER=srv_p7.sh P6_APK=~/pico-p7/…
spid=$!
done_flag=0
cleanup() {   # журналы забираем до остановки игры; повторный вызов (TERM, потом EXIT) ничего не делает
  [ "$done_flag" = 0 ] || return 0
  done_flag=1
  adb -s "$serial" logcat -d </dev/null > "$OUT/logcat.txt" 2>/dev/null || true
  "$HERE/pico.sh" log </dev/null > "$OUT/pico-log.txt" 2>&1 || true
  kill "$spid" 2>/dev/null
  adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null >/dev/null 2>&1
}
trap 'cleanup; exit 0' TERM INT
trap cleanup EXIT
sleep 8
grep -q "ENet слушает" "$OUT/server.log" || { echo "p6_run: сервер не слушает порт"; tail -5 "$OUT/server.log"; exit 1; }

adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null
adb -s "$serial" logcat -c </dev/null
if [ "${BOX_SHOW:-0}" != 1 ]; then   # автопрогон: очки должны быть готовы; показ — их уже проверил `pico show`
  rdy=$(bash "$BOX_CTL" pico ready "$BOX_OWNER" </dev/null 2>&1) || { echo "p6_run: очки не готовы — $rdy"; exit 20; }
fi
st=$(bash "$BOX_CTL" pico start "$BOX_OWNER" "$COMPONENT" </dev/null 2>&1) \
  || echo "p6_run: игра не вышла на передний план — $st (сервер держу; человек запустит игру из библиотеки)"
echo "p6_run: сервер $host:7777 (pid $spid), журнал $OUT; остановить: pico unshow или touch $STOP"

t=0
while [ "$t" -lt "$MAX_SEC" ] && [ ! -e "$STOP" ] && kill -0 "$spid" 2>/dev/null; do
  sleep 10; t=$((t + 10))
done
echo "p6_run: конец (${t} с), журналы в $OUT"

#!/bin/bash
# Общие функции для прогонов на двух эмуляторах + дашборд. Подключается через `source`.
E2E_DIR=${E2E_DIR:-/tmp/mb10-e2e}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}
ADB=$SDK/platform-tools/adb
EMU=$SDK/emulator/emulator
export PATH="$SDK/platform-tools:$PATH"   # чтобы `adb` работал и в ручных командах после `source lib.sh`
APK=${APK:-$ROOT/app/build/outputs/apk/debug/app-debug.apk}
NODE20=${NODE20:-/opt/homebrew/opt/node@20/bin}   # на CI нет такого пути — node берётся из PATH (setup-node)
[ -n "${JAVA_HOME:-}" ] || { [ -d /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ] && export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home; }
PKG=com.megablok10.app
AVD_A=${AVD_A:-Medium_Phone_API_35}; AVD_B=${AVD_B:-Second_API_35}   # имена AVD (на CI создаются под теми же именами)
A=emulator-5554   # Alice / Neon
B=emulator-5556   # Bob / Rats
PORT=${PORT:-8080}
API=http://localhost:$PORT
COLLECTOR_FROM_EMU=http://10.0.2.2:$PORT
mkdir -p "$E2E_DIR"

log()  { echo "[e2e] $*" >&2; }
die()  { echo "[e2e] ОШИБКА: $*" >&2; exit 1; }
adb_() { local s=$1; shift; "$ADB" -s "$s" "$@"; }

FAILED=0
# check "описание" <команда...> — команда должна вернуть 0; счётчик провалов идёт в FAILED.
check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  ✓ $desc"; else echo "  ✗ $desc"; FAILED=$((FAILED+1)); fi
}
# eq "описание" ожидаемое фактическое
eq() {
  if [ "$2" == "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1 (ожидалось «$2», получено «$3»)"; FAILED=$((FAILED+1)); fi
}
# wait_until <секунды> <команда...> — ждёт, пока команда не вернёт 0.
wait_until() {
  local t=$1; shift; local end=$((SECONDS+t))
  while [ $SECONDS -lt $end ]; do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}
finish() { if [ $FAILED -eq 0 ]; then echo "ЗЕЛЁНЫЙ"; else echo "КРАСНЫЙ: провалов $FAILED"; exit 1; fi; }

# ── БД устройства (run-as, копия в E2E_DIR) ──
q() { # q <serial> "<SQL>"
  local s=$1 sql=$2 f="$E2E_DIR/db_$1.db"
  rm -f "$f" "$f-wal" "$f-shm"
  adb_ "$s" exec-out run-as $PKG cat databases/mb10.db > "$f" 2>/dev/null
  adb_ "$s" exec-out run-as $PKG cat databases/mb10.db-wal > "$f-wal" 2>/dev/null
  sqlite3 -batch -noheader "$f" "$sql"
}

# ── Сервер ──
master_name() { echo E2E; }
session() {
  local f="$E2E_DIR/session.txt"
  if [ ! -s "$f" ] || ! curl -sf -H "Authorization: Bearer $(cat "$f")" "$API/api/overview" >/dev/null; then
    curl -sf -X POST "$API/api/auth/login" -H 'content-type: application/json' \
      -d "{\"name\":\"$(master_name)\",\"token\":\"$(cat "$E2E_DIR/master.txt")\"}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sessionToken"])' > "$f"
  fi
  cat "$f"
}
api() { # api METHOD /path [json-body]
  local m=$1 p=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sf -X "$m" "$API$p" -H "Authorization: Bearer $(session)" -H 'content-type: application/json' -d "$body"
  else
    curl -sf -X "$m" "$API$p" -H "Authorization: Bearer $(session)"
  fi
}
jq_() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }

# ── Debug-команды в приложение ──
dbg() { # dbg <serial> <действие DEBUG_CONFIG|DEBUG_SET|DEBUG_QR|DEBUG_PEER> [--es k v ...]
  local s=$1 act=$2; shift 2
  # adb shell склеивает аргументы в одну строку для удалённого sh — каждый значащий аргумент берём в одинарные кавычки (пробелы, «|»).
  local q="" a; for a in "$@"; do q="$q '${a//\'/\'\\\'\'}'"; done
  adb_ "$s" shell "am broadcast -f 0x20 -n $PKG/$PKG.qr.DebugQrReceiver -a $PKG.$act$q" >/dev/null
}
pk_of() { grep -h "set applied" <(adb_ "$1" logcat -d -s MB10DBG) | tail -1 | sed 's/.*publicKeyB64=\([^,]*\),.*/\1/'; }
start_app() { adb_ "$1" shell am start -n "$PKG/.MainActivity" >/dev/null; }
restart_app() { adb_ "$1" shell am force-stop $PKG; start_app "$1"; sleep 3; resend_config "$1"; }

# ── UI по тексту (uiautomator) ──
# dump_ui <serial> — кладёт XML экрана в $E2E_DIR/ui_<serial>.xml; системные «не отвечает» закрывает и снимает дамп заново.
dump_ui() {
  local s=$1 f="$E2E_DIR/ui_$1.xml" i
  for i in 1 2 3; do
    adb_ "$s" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb_ "$s" exec-out cat /sdcard/ui.xml > "$f"
    if grep -q "isn't responding" "$f"; then tap_xml "$f" "$s" "Close app"; sleep 1; else return 0; fi
  done
}
tap_xml() { # tap_xml <xml> <serial> "<подстрока>"
  local xy
  xy=$(python3 -c '
import sys,re
import xml.etree.ElementTree as ET
needle=sys.argv[2]
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    if needle in (n.get("text") or "") or needle in (n.get("content-desc") or ""):
        b=list(map(int,re.findall(r"\d+",n.get("bounds"))))
        print((b[0]+b[2])//2,(b[1]+b[3])//2); break
' "$1" "$3")
  [ -n "$xy" ] || return 1
  adb_ "$2" shell input tap $xy
}
tap_text() { dump_ui "$1"; tap_xml "$E2E_DIR/ui_$1.xml" "$1" "$2"; }   # tap_text <serial> "<подстрока text/content-desc>"
screen_has() { dump_ui "$1"; grep -q "$2" "$E2E_DIR/ui_$1.xml"; }
scroll_down() { adb_ "$1" shell input swipe 540 1700 540 700 200; }

# reset_ui — убрать с обоих экранов то, что осталось от прошлого сценария: окно «Сообщение от мастера» (иначе оно перехватывает тапы всех
# следующих сценариев), открытый тред/оверлей — и вернуть приложение на передний план.
reset_ui() {
  local s
  for s in $A $B; do
    if screen_has $s "Сообщение от мастера"; then tap_text $s "Принято" >/dev/null; sleep 1; fi
    start_app $s >/dev/null 2>&1
  done
}

# ── Контейнеры и взлом ──
# container <id> <имя> <тир> <фракция-владелец> <копий> — контейнер с одним слотом-шардом; печатает QR-строку.
container() {
  local body
  body=$(python3 -c '
import sys,json
i,n,t,f,c=sys.argv[1:6]
print(json.dumps({"id":i,"name":n,"tier":t,"ownerFaction":f,"slots":[{"type":"SHARD","tier":"BASE","copies":int(c),"shard":{"title":"Шард "+i,"body":"тело","meta":"","valueHint":"","decryptAction":False,"moneyAmount":0}}]}))' "$@")
  api POST /api/master/containers "$body" | jq_ 'd["qr"]'
}
# Конфиг живёт в памяти приложения — запоминаем и переотправляем после каждого перезапуска (restart_app).
set_config() { # set_config <serial> clock|timer|autosolve <значение>
  echo "$3" > "$E2E_DIR/cfg_$1_$2"; dbg "$1" DEBUG_CONFIG --es "$2" "$3"
}
resend_config() { local f k; for f in "$E2E_DIR"/cfg_$1_*; do [ -f "$f" ] || continue; k=${f##*_}; dbg "$1" DEBUG_CONFIG --es "$k" "$(cat "$f")"; done; }
autosolve() { set_config "$1" autosolve "$2"; }
open_deck() { tap_text "$1" "Кибердека" >/dev/null; sleep 1; }
# breach <serial> <qr> — сканирует QR, выбирает стартового демона, запускает взлом (нужен autosolve true).
# Ждёт итог; возвращает 0 и оставляет экран результата, 1 — если взлом не дошёл до результата (например, отказ на скане).
breach() {
  local s=$1 qr=$2
  open_deck $s
  dbg $s DEBUG_QR --es qr "$qr"
  wait_until 15 screen_has $s "Datamine" || return 1
  tap_text $s "Datamine" >/dev/null; sleep 0.5
  tap_text $s "Взломать контейнер" >/dev/null
  wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; scroll_down $s; screen_has $s 'Взлом завершён\|Взлом частично\|Взлом провален'"
}
back_to_scan() { tap_text "$1" "Новый контейнер" >/dev/null 2>&1; }

# Порт приложения. Раньше брали из logcat («Слушаю входящие…»), но сценарии делают `logcat -c` и строка пропадала — после этого
# link.sh не мог связать эмуляторы. Теперь спрашиваем у самого приложения (DEBUG_CONFIG port), а старый способ оставлен запасным.
port_of() {
  local p
  dbg "$1" DEBUG_CONFIG --es port '?' >/dev/null 2>&1; sleep 0.4
  p=$(adb_ "$1" logcat -d -s MB10DBG | grep "port=" | tail -1 | sed 's/.*port=//' | tr -dc 0-9)
  [ -n "$p" ] && [ "$p" != "-1" ] || p=$(adb_ "$1" logcat -d | grep "Слушаю входящие" | tail -1 | sed 's/.*порту //' | tr -dc 0-9)
  echo "$p"
}

# ── Управление сервером ──
server_stop() { [ -f "$E2E_DIR/server.pid" ] && kill "$(cat "$E2E_DIR/server.pid")" 2>/dev/null; rm -f "$E2E_DIR/server.pid"; lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null; sleep 1; }
server_start() {
  (cd "$ROOT/admin-web/server" && PATH="$NODE20:$PATH" DB_PATH="$E2E_DIR/db.sqlite" BACKUP_DIR="$E2E_DIR/backups" PORT=$PORT nohup node dist/index.js > "$E2E_DIR/server.log" 2>&1 & echo $! > "$E2E_DIR/server.pid")
  wait_until 20 curl -s -o /dev/null "$API/api/overview"
}
# tx_of <serial> — id последнего перевода, созданного командой pay (из logcat).
tx_of() { adb_ "$1" logcat -d -s MB10DBG | grep "pay id=" | tail -1 | sed 's/.*pay id=//' | tr -d '\r'; }
ram_of() { adb_ "$1" exec-out run-as $PKG cat shared_prefs/identity_prefs.xml | grep -o 'ram_capacity" value="[0-9]*' | grep -o '[0-9]*$'; }
# item_of <serial> — id последней передачи предмета, созданной командой give (из logcat).
item_of() { adb_ "$1" logcat -d -s MB10DBG | grep "give id=" | tail -1 | sed 's/.*give id=//' | tr -d '\r'; }
# open_chat <serial> <позывной> — вкладка «Чат» → тред с контактом.
open_chat() { tap_text "$1" "Чат" >/dev/null; sleep 1; tap_text "$1" "$2" >/dev/null; sleep 1.5; }

# back_if_arrow <serial> — нажимает «←» только если она есть на экране (в треде): на списке чатов тап в этом углу открыл бы профиль.
back_if_arrow() { dump_ui "$1"; tap_xml "$E2E_DIR/ui_$1.xml" "$1" "←" || true; }

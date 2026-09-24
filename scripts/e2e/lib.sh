#!/bin/bash
# Общие функции для прогонов на двух эмуляторах + дашборд. Подключается через `source`.
E2E_DIR=${E2E_DIR:-/tmp/mb10-e2e}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}
ADB=$SDK/platform-tools/adb
EMU=$SDK/emulator/emulator
export PATH="$SDK/platform-tools:$PATH"   # чтобы `adb` работал и в ручных командах после `source lib.sh`
APK=${APK:-$ROOT/app/build/outputs/apk/debug/app-debug.apk}
# Node сервера: LTS 22 (зависимости требуют >=22), запасной — 20; NODE_BIN переопределяет. На CI таких путей нет — node берётся из PATH (setup-node).
for d in "${NODE_BIN:-}" /opt/homebrew/opt/node@22/bin /opt/homebrew/opt/node@20/bin; do [ -n "$d" ] && [ -d "$d" ] && { NODE_BIN=$d; break; }; done
NODE_BIN=${NODE_BIN:-}
[ -n "${JAVA_HOME:-}" ] || { [ -d /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ] && export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home; }
PKG=com.megablok10.app
AVD_A=${AVD_A:-Medium_Phone_API_35}; AVD_B=${AVD_B:-Second_API_35}   # имена AVD (на CI создаются под теми же именами)
A=emulator-5554   # Alice / Neon
B=emulator-5556   # Bob / Rats
PORT=${PORT:-2517}
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
  if "$@" >/dev/null 2>&1; then echo "  ✓ $desc"; else echo "  ✗ $desc$(infra_note)"; FAILED=$((FAILED+1)); fi
}
# infra_note — если экран эмулятора не ожил (маркер screen_dead_*), красная строка помечается как сбой стенда, а не приложения.
infra_note() { local m; for m in "$E2E_DIR"/screen_dead_*; do [ -e "$m" ] && { echo "  [сбой стенда: экран ${m##*_} не отвечает, не вина приложения]"; return; }; done; }
# eq "описание" ожидаемое фактическое
eq() {
  if [ "$2" == "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1 (ожидалось «$2», получено «$3»)$(infra_note)"; FAILED=$((FAILED+1)); fi
}
# wait_until <секунды> <команда...> — ждёт, пока команда не вернёт 0.
wait_until() {
  local t=$1; shift; local end=$((SECONDS+t))
  while [ $SECONDS -lt $end ]; do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}
# ── Журнал приложения (Android/data/<пакет>/files/logs, см. docs/live-test-plan.md) ──
# Журнал лежит во внешней папке приложения, а если туда писать нельзя (после переустановки на эмуляторе) — во внутренней: читаем оба места.
journal_cat() {
  adb_ "$1" shell "cat /sdcard/Android/data/$PKG/files/logs/mb10-*.log 2>/dev/null" 2>/dev/null
  adb_ "$1" shell "run-as $PKG sh -c 'cat files/logs/mb10-*.log 2>/dev/null'" 2>/dev/null
}
journal_count() { journal_cat "$1" | grep -c -- "$2"; }   # journal_count <serial> <подстрока>: сколько строк журнала её содержит
# journal_save <метка>: журналы обоих телефонов рядом со сценарием — при красном сценарии лежат в $E2E_DIR/journals/ и уходят в артефакты
journal_save() {
  local d="$E2E_DIR/journals" s
  mkdir -p "$d"
  for s in $A $B; do journal_cat "$s" > "$d/$1-$s.log"; done
}
finish() {
  if [ $FAILED -eq 0 ]; then echo "ЗЕЛЁНЫЙ"; return 0; fi
  local name; name=$(basename "$0" .sh)
  journal_save "$name" 2>/dev/null && echo "  журналы приложения: $E2E_DIR/journals/$name-*.log"
  # экран каждого телефона в момент провала: без него непонятно, чего на экране не было (кнопки, карточки)
  local s
  for s in $A $B; do
    dump_ui "$s" >/dev/null 2>&1; cp "$E2E_DIR/ui_$s.xml" "$E2E_DIR/journals/$name-ui-$s.xml" 2>/dev/null
    adb_ "$s" exec-out screencap -p > "$E2E_DIR/journals/$name-screen-$s.png" 2>/dev/null
  done
  echo "КРАСНЫЙ: провалов $FAILED"; exit 1
}

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
# app_state <serial> — одна строка для журнала стенда: жив ли процесс приложения и что на переднем плане (разбор «на экране не то»).
app_state() {
  local pid top
  pid=$(adb_ "$1" shell pidof $PKG 2>/dev/null | tr -d '\r')
  top=$(adb_ "$1" shell dumpsys activity activities 2>/dev/null | grep -m1 -E 'topResumedActivity|mResumedActivity' | sed 's/^ *//' | tr -d '\r')
  echo "процесс ${pid:-нет}; наверху: ${top:-?}"
}
restart_app() { adb_ "$1" shell am force-stop $PKG; start_app "$1"; sleep 3; resend_config "$1"; }

# ── UI по тексту (uiautomator) ──
# raw_dump <serial> — кладёт XML экрана в $E2E_DIR/ui_<serial>.xml; системные «не отвечает» закрывает и снимает дамп заново.
raw_dump() {
  local s=$1 f="$E2E_DIR/ui_$1.xml" i
  for i in 1 2 3; do
    adb_ "$s" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb_ "$s" exec-out cat /sdcard/ui.xml > "$f"
    if grep -q "isn't responding" "$f"; then tap_xml "$f" "$s" "Close app"; sleep 1; else return 0; fi
  done
}
# ui_ok <serial> — экран отвечает: в последнем дампе есть хотя бы один узел. Упавший SystemUI, блокировка или чёрный экран дают пустой дамп
# (только заголовок hierarchy) — раньше это выглядело как «нужного текста нет» и краснило сценарий, хотя виноват был стенд.
ui_ok() { [ -s "$E2E_DIR/ui_$1.xml" ] && grep -q "<node " "$E2E_DIR/ui_$1.xml"; }
wake_screen() { adb_ "$1" shell input keyevent KEYCODE_WAKEUP; adb_ "$1" shell wm dismiss-keyguard >/dev/null 2>&1; adb_ "$1" shell input keyevent 82; sleep 1; }
wait_boot() { wait_until "${2:-240}" bash -c "'$ADB' -s $1 shell getprop sys.boot_completed 2>/dev/null | grep -q 1"; }

# revive_screen <serial> — лестница восстановления мёртвого экрана эмулятора (SystemUI упал / блокировка / чёрный экран):
#   1) разбудить и снять блокировку, вернуть приложение; 2) перезапустить SystemUI; 3) перезагрузить эмулятор (≈1 мин) и вернуть приложение.
# Возвращает 0, когда экран снова отвечает. REVIVE_FORCE_REBOOT=1 — сразу третья ступень (для проверки самой лестницы).
revive_screen() {
  local s=$1
  log "$s: экран не отвечает — восстанавливаю"
  if [ -z "${REVIVE_FORCE_REBOOT:-}" ]; then
    wake_screen "$s"; start_app "$s" >/dev/null 2>&1; sleep 2; raw_dump "$s"; ui_ok "$s" && { log "$s: ожил после пробуждения"; return 0; }
    adb_ "$s" shell am crash com.android.systemui >/dev/null 2>&1; sleep 10
    wake_screen "$s"; start_app "$s" >/dev/null 2>&1; sleep 2; raw_dump "$s"; ui_ok "$s" && { log "$s: ожил после перезапуска SystemUI"; return 0; }
  fi
  log "$s: перезагружаю эмулятор"
  adb_ "$s" reboot >/dev/null 2>&1; sleep 20
  wait_boot "$s" 240 || return 1
  sleep 15
  adb_ "$s" shell svc power stayon true >/dev/null 2>&1
  wake_screen "$s"; start_app "$s" >/dev/null 2>&1; sleep 3; resend_config "$s"
  # порт приложения после перезагрузки другой — связь пиров (redir + DEBUG_PEER) надо восстановить
  "$ROOT/scripts/e2e/link.sh" >/dev/null 2>&1 || log "$s: связать пиров после перезагрузки не удалось (запустите link.sh)"
  raw_dump "$s"; ui_ok "$s" && { log "$s: ожил после перезагрузки"; return 0; }
  return 1
}
# dump_ui <serial> — как raw_dump, но с проверкой живости и восстановлением. Если экран так и не ожил, ставит маркер $E2E_DIR/screen_dead_<serial>
# (его читает check и помечает красную строку как сбой стенда, а не приложения); удачный дамп маркер снимает.
dump_ui() {
  local s=$1
  raw_dump "$s"
  if ui_ok "$s"; then rm -f "$E2E_DIR/screen_dead_$s"; return 0; fi
  if revive_screen "$s"; then rm -f "$E2E_DIR/screen_dead_$s"; return 0; fi
  touch "$E2E_DIR/screen_dead_$s"; return 1
}
# ensure_wifi_on <serial> — Wi-Fi эмулятора включён. Состояние Wi-Fi переживает перезапуск эмулятора: выключенный сценарием или лечением (heal_host_reach) Wi-Fi
# оставался бы выключенным на следующем стенде, а приложение разрешает взлом только при подключённом Wi-Fi (MeshLink.isOnline, ревизия v9 §5) —
# сценарии со взломом (sec-alert, slot-race) краснели бы «сами». Включаем ТОЛЬКО если он выключен: лишнее включение поверх работающего Wi-Fi
# переподключает сеть, и приложение может привязаться к новой сети, из которой до хоста не достучаться.
ensure_wifi_on() {
  adb_ "$1" shell "dumpsys wifi | grep -q 'Wi-Fi is enabled'" 2>/dev/null && return 0
  log "$1: Wi-Fi выключен — включаю"
  adb_ "$1" shell svc wifi enable; sleep 10
}
# players_total — сколько игроков видит дашборд (пусто, если сервер не отвечает).
players_total() { api GET /api/overview 2>/dev/null | jq_ 'd["players"]["total"]' 2>/dev/null; }
# heal_host_reach [сколько игроков ждать] — особенность эмулятора: приложение, привязанное к виртуальному Wi-Fi, не достукивается до хоста (10.0.2.2)
# и на дашборде не появляется. На реальной игровой сети сервер доступен именно по Wi-Fi, там этого нет. Если игроков меньше нужного, выключает
# виртуальный Wi-Fi у тех эмуляторов, чьё приложение жалуется «коллектор недоступен» (трафик уйдёт по сотовому каналу эмулятора).
heal_host_reach() {
  local want=${1:-2} s
  wait_until 45 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(players_total)\" -ge $want ]" && return 0
  for s in $A $B; do
    if adb_ "$s" logcat -d -t 300 2>/dev/null | grep -q "CollectorClient.*недоступен"; then
      log "$s: приложение не достукивается до сервера — выключаю виртуальный Wi-Fi (особенность эмулятора)"
      adb_ "$s" shell svc wifi disable
    fi
  done
  wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(players_total)\" -ge $want ]" || { log "ВНИМАНИЕ: на дашборде видно меньше $want игроков"; return 1; }
}
# preflight — проверка обоих эмуляторов перед сценарием: устройство на связи, система загружена, экран отвечает (иначе чинит).
preflight() {
  local s bad=0
  for s in $A $B; do
    "$ADB" -s "$s" get-state 2>/dev/null | grep -q device || { log "$s: устройство недоступно (adb)"; bad=1; continue; }
    [ "$(adb_ "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] || { wait_boot "$s" 120 || { log "$s: система не загрузилась"; bad=1; continue; }; }
    wake_screen "$s"   # экран мог погаснуть или уйти под блокировку: окна приложения (например «Сообщение от мастера») на спящем экране не показываются
    dump_ui "$s" || { log "$s: экран не удалось оживить"; bad=1; }
  done
  return $bad
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
# tap_when <serial> "<подстрока>" [сек] — ждёт, пока элемент появится, и нажимает. Экран (например, тред) открывается раньше, чем из базы
# подгрузились карточки: одиночный tap_text в этот момент молча промахивался, и сценарий валился каскадом. Нет элемента за [сек] — код 1.
tap_when() { wait_until "${3:-15}" tap_text "$1" "$2"; }
screen_has() { dump_ui "$1"; grep -q "$2" "$E2E_DIR/ui_$1.xml"; }
scroll_down() { adb_ "$1" shell input swipe 540 1700 540 700 200; }

# reset_ui — убрать с обоих экранов то, что осталось от прошлого сценария: окно «Сообщение от мастера» (иначе оно перехватывает тапы всех
# следующих сценариев), открытый тред/оверлей — и вернуть приложение на передний план.
reset_ui() {
  local s
  rm -f "$E2E_DIR"/screen_dead_*
  [ -n "${E2E_NO_PREFLIGHT:-}" ] || preflight >/dev/null 2>&1
  for s in $A $B; do
    if screen_has $s "Сообщение от мастера"; then tap_text $s "Принято" >/dev/null; sleep 1; fi
    start_app $s >/dev/null 2>&1
    # Оставшийся открытым тред прячет нижнюю панель (вкладки «Кибердека», «Финансы»): выходим из него, иначе следующий сценарий не найдёт вкладку.
    sleep 1; back_if_arrow $s
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
  ensure_wifi_on $s
  open_deck $s
  dbg $s DEBUG_QR --es qr "$qr"
  wait_until 15 screen_has $s "Datamine" || return 1
  tap_text $s "Datamine" >/dev/null; sleep 0.5
  tap_text $s "Взломать контейнер" >/dev/null
  wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; scroll_down $s; screen_has $s 'Взлом завершён\|Взлом частично\|Взлом провален'"
}

# Порт приложения. Раньше брали из logcat («Слушаю входящие…»), но сценарии делают `logcat -c` и строка пропадала — после этого
# link.sh не мог связать эмуляторы. Теперь спрашиваем у самого приложения (DEBUG_CONFIG port), а старый способ оставлен запасным.
port_of() {
  local p
  dbg "$1" DEBUG_CONFIG --es port '?' >/dev/null 2>&1; sleep 0.4
  # Минус сохраняем: сервер чата ещё не поднят → «port=-1»; без минуса это читалось как порт 1 (стенд «связывал» пиры с несуществующим портом).
  p=$(adb_ "$1" logcat -d -s MB10DBG | grep "port=" | tail -1 | sed 's/.*port=//' | tr -dc '0-9-')
  [ -n "$p" ] && [ "$p" -gt 1024 ] 2>/dev/null || p=$(adb_ "$1" logcat -d | grep "Слушаю входящие" | tail -1 | sed 's/.*порту //' | tr -dc 0-9)
  echo "$p"
}

# ── Управление сервером ──
server_stop() { [ -f "$E2E_DIR/server.pid" ] && kill "$(cat "$E2E_DIR/server.pid")" 2>/dev/null; rm -f "$E2E_DIR/server.pid"; lsof -ti tcp:$PORT -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null; sleep 1; }
server_start() {
  (cd "$ROOT/admin-web/server" && PATH="${NODE_BIN:+$NODE_BIN:}$PATH" DB_PATH="$E2E_DIR/db.sqlite" BACKUP_DIR="$E2E_DIR/backups" PORT=$PORT GAME_SECRET="${E2E_GAME_SECRET:-}" PUBLIC_URL="${PUBLIC_URL:-$COLLECTOR_FROM_EMU}" nohup env ${E2E_SERVER_ENV:-} node dist/index.js > "$E2E_DIR/server.log" 2>&1 & echo $! > "$E2E_DIR/server.pid")
  wait_until 20 curl -s -o /dev/null "$API/api/overview"
}
# tx_of <serial> — id последнего перевода, созданного командой pay (из logcat).
tx_of() { adb_ "$1" logcat -d -s MB10DBG | grep "pay id=" | tail -1 | sed 's/.*pay id=//' | tr -d '\r'; }
ram_of() { adb_ "$1" exec-out run-as $PKG cat shared_prefs/identity_prefs.xml | grep -o 'ram_capacity" value="[0-9]*' | grep -o '[0-9]*$'; }
# item_of <serial> — id последней передачи предмета, созданной командой give (из logcat).
item_of() { adb_ "$1" logcat -d -s MB10DBG | grep "give id=" | tail -1 | sed 's/.*give id=//' | tr -d '\r'; }
# open_chat <serial> <позывной> — вкладка «Чат» → тред с контактом.
# Тап по строке списка иногда не попадает (строка сдвигается, когда в этот момент приходит сообщение), поэтому проверяем, что тред открылся
# (в нём есть кнопка «Отпр.»), и при неудаче повторяем.
open_chat() {
  local n
  for n in 1 2 3; do
    tap_text "$1" "Чат" >/dev/null; sleep 1; tap_text "$1" "$2" >/dev/null; sleep 1.5
    screen_has "$1" "Отпр." && return 0
  done
  return 0
}

# back_if_arrow <serial> — нажимает «←» только если она есть на экране (в треде): на списке чатов тап в этом углу открыл бы профиль.
back_if_arrow() { dump_ui "$1"; tap_xml "$E2E_DIR/ui_$1.xml" "$1" "←" || true; }

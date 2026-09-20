#!/bin/bash
# Поднимает весь стенд одной командой: сервер-коллектор (node@20, свежая БД), два эмулятора,
# APK, персонажи Alice/Neon и Bob/Rats, связь пиров и ускоренные часы.
#   ./up.sh [--no-build] [--keep-data] [--clock N] [--timer N]
# После: ./scenarios/*.sh или ./run-all.sh; убрать всё — ./down.sh.
source "$(dirname "$0")/lib.sh"
BUILD=1; KEEP=0; CLOCK=60; TIMER=10
while [ $# -gt 0 ]; do case $1 in
  --no-build) BUILD=0;; --keep-data) KEEP=1;;
  --clock) CLOCK=$2; shift;; --timer) TIMER=$2; shift;;
  *) die "неизвестный аргумент $1";; esac; shift; done

"$(dirname "$0")/down.sh" --keep-emulators >/dev/null 2>&1

# 0. Один стенд на машину: порты эмуляторов (5554/5556) и сервера фиксированы, два одновременных up.sh (например, у двух агентов в разных
# рабочих копиях) ломают друг другу прогоны. Владелец пишется в $E2E_DIR/owner; чужой живой up.sh — отказ.
if [ -s "$E2E_DIR/owner" ] && [ "$(cat "$E2E_DIR/owner")" != "$ROOT" ] && pgrep -f "emulator.*-port 5554" >/dev/null; then
  die "стенд занят другой рабочей копией: $(cat "$E2E_DIR/owner"). Остановите её (./scripts/e2e/down.sh там) или дождитесь конца прогона"
fi
echo "$ROOT" > "$E2E_DIR/owner"

# 1. APK
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
if [ $BUILD -eq 1 ] || [ ! -f "$APK" ]; then log "сборка APK…"; (cd "$ROOT" && ./gradlew -q assembleDebug) || die "gradle assembleDebug"; fi

# 2. Сервер
SERVER="$ROOT/admin-web/server"
export PATH="$NODE20:$PATH"
[ -d "$SERVER/node_modules" ] || (cd "$SERVER" && npm ci >/dev/null) || die "npm ci"
# Сервер пересобираем только если исходники новее dist (tsc ≈ 10 с на каждый up.sh).
if [ ! -f "$SERVER/dist/index.js" ] || [ -n "$(find "$SERVER/src" "$SERVER/package.json" -newer "$SERVER/dist/index.js" -type f 2>/dev/null | head -1)" ]; then
  log "сборка сервера…"; (cd "$SERVER" && npm run build >/dev/null) || die "npm run build"
else log "сервер не менялся — сборка пропущена"; fi
[ $KEEP -eq 1 ] || rm -f "$E2E_DIR"/db.sqlite*
export DB_PATH="$E2E_DIR/db.sqlite" BACKUP_DIR="$E2E_DIR/backups"
if [ $KEEP -eq 0 ] || [ ! -s "$E2E_DIR/master.txt" ]; then
  (cd "$SERVER" && npm run --silent create-master -- "$(master_name)") | tail -1 > "$E2E_DIR/master.txt" || die "create-master"
fi
rm -f "$E2E_DIR/session.txt"
server_start || die "сервер не поднялся, см. $E2E_DIR/server.log"
log "сервер на :$PORT (pid $(cat "$E2E_DIR/server.pid"))"

# 3. Эмуляторы
start_emu() { # <avd> <порт> <serial>
  if "$ADB" devices | grep -q "^$3"; then return; fi
  log "запускаю $1 на :$2"
  nohup "$EMU" -avd "$1" -port "$2" -no-window -no-audio -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect ${EMU_EXTRA_ARGS:-} > "$E2E_DIR/emu_$3.log" 2>&1 &
  local pid=$!; sleep 6
  # Эмулятор, который сразу упал (нет AVD, нет KVM), иначе «загружался» бы весь таймаут — падаем сразу и показываем его лог.
  kill -0 $pid 2>/dev/null || { tail -20 "$E2E_DIR/emu_$3.log" >&2; die "эмулятор $1 завершился сразу после запуска"; }
}
start_emu $AVD_A 5554 $A
start_emu $AVD_B 5556 $B
for s in $A $B; do
  wait_until ${BOOT_TIMEOUT:-240} bash -c "'$ADB' -s $s shell getprop sys.boot_completed 2>/dev/null | grep -q 1" || { tail -25 "$E2E_DIR/emu_$s.log" >&2; die "$s не загрузился"; }
  wait_until 120 bash -c "'$ADB' -s $s shell cmd activity get-current-user 2>/dev/null | grep -q '^[0-9]'" || die "$s: система не готова"
  # анимации выключены — заметно ускоряет тапы; лишние системные окна убираем
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do adb_ $s shell settings put global $k 0; done
  adb_ $s shell pm disable-user --user 0 com.google.android.apps.messaging >/dev/null 2>&1
  adb_ $s shell svc power stayon true >/dev/null 2>&1   # экран не засыпает во время длинных прогонов и записи
  adb_ $s shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1
done

# 4. Приложение и персонажи
setup_device() { # <serial> <позывной:фракция>
  local s=$1
  [ $KEEP -eq 1 ] || adb_ $s uninstall $PKG >/dev/null 2>&1
  adb_ $s install -r "$APK" >/dev/null || die "install на $s"
  for p in POST_NOTIFICATIONS RECORD_AUDIO CAMERA; do adb_ $s shell pm grant $PKG android.permission.$p >/dev/null 2>&1; done
  adb_ $s logcat -c
  dbg $s DEBUG_SET --es collector "$COLLECTOR_FROM_EMU" --es create "$2"
  rm -f "$E2E_DIR"/cfg_${s}_*
  set_config $s clock "$CLOCK"; set_config $s timer "$TIMER"; set_config $s autosolve false
}
setup_device $A Alice:Neon
setup_device $B Bob:Rats
sleep 2
for s in $A $B; do
  restart_app $s
  pk_of $s > "$E2E_DIR/pk_$s.txt"
  [ -s "$E2E_DIR/pk_$s.txt" ] || die "не получил публичный ключ $s"
done

# Игроки знают друг друга (как после обмена QR-контактами) — иначе в чате «Неизвестный контакт».
dbg $A DEBUG_SET --es contact "$(cat "$E2E_DIR/pk_$B.txt"):Bob:Rats"
dbg $B DEBUG_SET --es contact "$(cat "$E2E_DIR/pk_$A.txt"):Alice:Neon"

# 5. Связь пиров и проверка, что оба на дашборде
"$(dirname "$0")/link.sh" || die "link.sh"
wait_until 60 bash -c "source '$(dirname "$0")/lib.sh'; [ \"\$(api GET /api/players | jq_ 'len(d)')\" -ge 2 ]" \
  || log "ВНИМАНИЕ: оба игрока пока не видны на дашборде (проверь коллектор в Настройках)"
log "стенд готов. Дашборд: $API (мастер E2E, токен в $E2E_DIR/master.txt)"

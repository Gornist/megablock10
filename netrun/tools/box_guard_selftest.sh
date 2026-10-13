#!/usr/bin/env bash
# Самотест защиты очков (D4): pico_stand.sh и pico_series.sh соблюдают брони devbox и не трогают устройство, когда им отказано.
# Идёт где угодно (Mac, devbox) и НЕ касается ни рабочего ~/box, ни настоящего adb, ни очков: подложные ctl.sh и adb во временном каталоге,
# HOME подменён, серийник — NOSUCH, BOX_TEST=1 (ctl.sh из #230 откажется, если подложка не подложена). Вердикт — одной строкой, код 0/1.
#   netrun/tools/box_guard_selftest.sh
# Причина появления: 13.10 17:27 проверка «отказ по чужой брони» пошла со старыми скриптами и разбудила очки — тест по ssh на рабочих
# скриптах так делать нельзя (переменные окружения с Mac до devbox не доходят, подмена BOX_SH/BOX_CTL — внутри самого теста).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home" "$T/box"

# Подложный adb: пишет вызовы; `am start` отвечает «kept for the user», `push` проходит, остальное — «нет устройства» (код 1).
cat > "$T/bin/adb" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_ADB_LOG"
case "$*" in
  *"am start"*) echo "kept for the user"; exit 0 ;;
  *" push "*) exit 0 ;;
esac
exit 1
EOF
# Подложный ctl.sh: пишет вызовы; `check <ресурс>` отказывает для ресурсов из FAKE_REFUSE (через пробел), остальное — успех.
cat > "$T/ctl.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_CTL_LOG"
if [ "${1:-}" = check ]; then
  case " ${FAKE_REFUSE:-} " in *" $2 "*) echo "занято: $2 — Другой до 23:59 (самотест)"; exit 1 ;; esac
fi
exit 0
EOF
chmod +x "$T/bin/adb" "$T/ctl.sh"

pass=0; fail=0
export HOME="$T/home" PATH="$T/bin:$PATH" BOX_TEST=1 BOX="$T/box" ADB="$T/bin/adb"
export BOX_CTL="$T/ctl.sh" PICO_SERIAL=NOSUCH STUB_ADB_LOG="$T/adb.log" STUB_CTL_LOG="$T/ctl.log" WAIT_SEC=2 OUT="$T/out"

check() { # check <описание> <условие: 0 — выполнено>
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "ПРОВАЛ: $1"; fi
}
reset() { : > "$T/adb.log"; : > "$T/ctl.log"; rm -rf "$T/out"; }
has() { grep -qE -- "$1" "$2"; echo $?; }   # 0 — строка (регулярное выражение) есть

# 1. Чужая бронь pico: pico_stand отказывает и ничего не пишет на устройство.
reset
FAKE_REFUSE="pico" bash "$HERE/pico_stand.sh" base >"$T/o1" 2>&1; rc=$?
check "pico_stand при чужой брони: код 1" "$([ $rc = 1 ]; echo $?)"
check "pico_stand при чужой брони: нет adb push" "$([ "$(has ' push ' "$T/adb.log")" != 0 ]; echo $?)"
check "pico_stand при чужой брони: в выводе «занято»" "$(has 'занято: pico' "$T/o1")"

# 2. Чужая бронь pico: pico_series отказывает до любых adb shell (input, am, svc).
reset
FAKE_REFUSE="pico" bash "$HERE/pico_series.sh" "x=base" >"$T/o2" 2>&1; rc=$?
check "pico_series при чужой брони: код 1" "$([ $rc = 1 ]; echo $?)"
check "pico_series при чужой брони: ни одного adb shell/push" "$([ "$(has ' shell | push ' "$T/adb.log")" != 0 ]; echo $?)"

# 3. Чужая бронь порта стенда при заданном сервере: отказ до запуска сервера и игры.
reset
FAKE_REFUSE="port:7777" PICO_SERVER_CMD="touch $T/server-started" bash "$HERE/pico_series.sh" "x=base" >"$T/o3" 2>&1; rc=$?
check "pico_series при чужом порте: код 1" "$([ $rc = 1 ]; echo $?)"
check "pico_series при чужом порте: сервер не запущен" "$([ ! -e "$T/server-started" ]; echo $?)"
check "pico_series при чужом порте: ни одного adb shell/push" "$([ "$(has ' shell | push ' "$T/adb.log")" != 0 ]; echo $?)"

# 4. Брони свободны: серия зовёт штатный `pico ready Godot`, при системном диалоге останавливается и гасит очки `pico sleep Godot`.
reset
FAKE_REFUSE="" bash "$HERE/pico_series.sh" "x=base" >"$T/o4" 2>&1; rc=$?
check "серия при диалоге Pico: код 2" "$([ $rc = 2 ]; echo $?)"
check "серия зовёт pico ready Godot" "$(has 'pico ready Godot' "$T/ctl.log")"
check "серия гасит очки pico sleep Godot" "$(has 'pico sleep Godot' "$T/ctl.log")"
check "серия спрашивает check pico" "$(has 'check pico Godot' "$T/ctl.log")"

# 5. Не devbox (ctl.sh нет): проверок нет, серия идёт как раньше (PICO_READY_CMD не подставляется, очки не гасятся).
reset
BOX_CTL="$T/нет-такого.sh" bash "$HERE/pico_series.sh" "x=base" >"$T/o5" 2>&1; rc=$?
check "без ctl.sh серия доходит до запуска игры (код 2 из-за диалога)" "$([ $rc = 2 ]; echo $?)"
check "без ctl.sh ctl не зовётся" "$([ ! -s "$T/ctl.log" ]; echo $?)"

if [ "$fail" = 0 ]; then
  echo "box_guard_selftest: OK — $pass проверок"
  exit 0
fi
echo "box_guard_selftest: ПРОВАЛ — $fail из $((pass + fail)) (подробности — запуск с bash -x; каталог теста удаляется по выходу)"
exit 1

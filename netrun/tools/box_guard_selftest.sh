#!/usr/bin/env bash
# Самотест защиты очков (D4/Д5): pico_stand.sh и pico_series.sh идут к очкам ОДНИМ путём (`ctl.sh pico run|ready|start`), соблюдают брони и не
# трогают устройство, когда им отказано. Идёт где угодно (Mac, devbox) и НЕ касается ни рабочего ~/box, ни настоящего adb, ни очков:
# подложные ctl.sh и adb во временном каталоге, HOME подменён, серийник — NOSUCH, BOX_TEST=1 (ctl.sh из #230 откажется, если подложка не
# подложена). Вердикт — одной строкой, код 0/1.
#   netrun/tools/box_guard_selftest.sh
# Причина появления: 13.10 17:27 проверка «отказ по чужой брони» пошла со старыми скриптами и разбудила очки — тест по ssh на рабочих
# скриптах так делать нельзя (переменные окружения с Mac до devbox не доходят, подмена BOX_SH/BOX_CTL — внутри самого теста).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home" "$T/box" "$T/run"

# Подложный adb: пишет вызовы; `pull` создаёт файл («исходный cfg»), `am start` отвечает «kept for the user», `push` проходит,
# остальное — «нет устройства» (код 1).
cat > "$T/bin/adb" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_ADB_LOG"
case "$*" in
  *" pull "*) for last in "$@"; do :; done; echo "ORIG" > "$last"; exit 0 ;;
  *"am start"*) echo "kept for the user"; exit 0 ;;
  *" push "*) exit 0 ;;
esac
exit 1
EOF
# Подложный ctl.sh: пишет вызовы. check <ресурс> — отказ для FAKE_REFUSE (через пробел); pico run <владелец> <мин> [опции] -- команда…
# — FAKE_RUN_RC задан: отказ с этим кодом, команда не стартует; иначе выполняет команду с PICO_RUN_DIR; pico ready — код FAKE_READY_RC;
# pico start — код FAKE_START_RC; pico fg — строка состояния.
cat > "$T/ctl.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_CTL_LOG"
case "${1:-} ${2:-}" in
  "check "*) case " ${FAKE_REFUSE:-} " in *" $2 "*) echo "занято: $2 — Другой до 23:59 (самотест)"; exit 1 ;; esac ;;
  "pico run")
    [ -z "${FAKE_RUN_RC:-}" ] || { echo "pico run: НЕ ГОТОВО — самотест"; exit "$FAKE_RUN_RC"; }
    shift 4
    while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done
    shift
    PICO_RUN_DIR="$STUB_RUN_DIR" PICO_SERIAL="$PICO_SERIAL" "$@"; exit $? ;;
  "pico ready") [ "${FAKE_READY_RC:-0}" = 0 ] || echo "pico ready: НЕ ГОТОВО — самотест (темно)"; exit "${FAKE_READY_RC:-0}" ;;
  "pico start") [ "${FAKE_START_RC:-0}" = 0 ] || echo "pico start: НЕ ГОТОВО — самотест"; exit "${FAKE_START_RC:-0}" ;;
  "pico fg") echo "окно=самотест вердикт=ok"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$T/bin/adb" "$T/ctl.sh"

pass=0; fail=0
export HOME="$T/home" PATH="$T/bin:$PATH" BOX_TEST=1 BOX="$T/box" ADB="$T/bin/adb"
export BOX_CTL="$T/ctl.sh" PICO_SERIAL=NOSUCH STUB_ADB_LOG="$T/adb.log" STUB_CTL_LOG="$T/ctl.log" STUB_RUN_DIR="$T/run" WAIT_SEC=2 OUT="$T/out"

check() { # check <описание> <условие: 0 — выполнено>
  if [ "$2" = 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "ПРОВАЛ: $1"
    [ -z "${CUR_OUT:-}" ] || { echo "  вывод скрипта:"; tail -6 "$CUR_OUT" | sed 's/^/    /'; echo "  вызовы ctl.sh:"; tail -6 "$T/ctl.log" | sed 's/^/    /'; }
  fi
}
reset() { : > "$T/adb.log"; : > "$T/ctl.log"; rm -rf "$T/out" "$T/server-started"; }
has() { grep -qE -- "$1" "$2"; echo $?; }   # 0 — строка (регулярное выражение) есть
no_power_taps() { # 0 — к очкам не было ни нажатий, ни питания, ни системных настроек
  grep -qE 'keyevent|input |svc |settings put|setprop' "$T/adb.log"; [ $? != 0 ]; echo $?
}

# 1. Чужая бронь pico: pico_stand отказывает и ничего не пишет на устройство.
reset; CUR_OUT="$T/o1"
FAKE_REFUSE="pico" bash "$HERE/pico_stand.sh" base >"$T/o1" 2>&1; rc=$?
check "pico_stand при чужой брони: код 1" "$([ $rc = 1 ]; echo $?)"
check "pico_stand при чужой брони: нет adb push" "$([ "$(has ' push ' "$T/adb.log")" != 0 ]; echo $?)"
check "pico_stand при чужой брони: в выводе «занято»" "$(has 'занято: pico' "$T/o1")"

# 2. Серия на devbox идёт ТОЛЬКО внутри `pico run`; run отказал (чужая бронь, 21): код run, ни одного adb shell/push, ни запуска сервера.
reset; CUR_OUT="$T/o2"
FAKE_RUN_RC=21 PICO_SERVER_CMD="touch $T/server-started" bash "$HERE/pico_series.sh" "x=base" >"$T/o2" 2>&1; rc=$?
check "серия при отказе run: код run (21)" "$([ $rc = 21 ]; echo $?)"
check "серия зовёт pico run Godot 20 с --port 7777" "$(has 'pico run Godot 20 --port 7777 -- env PICO_RUN_INNER=1' "$T/ctl.log")"
check "серия при отказе run: ни одного adb shell/push" "$([ "$(has ' shell | push ' "$T/adb.log")" != 0 ]; echo $?)"
check "серия при отказе run: сервер не запущен" "$([ ! -e "$T/server-started" ]; echo $?)"

# 3. Внутри run: ready «не готово» (темно) — серия останавливается, игру не стартует, cfg возвращён, к очкам ни нажатий, ни питания.
reset; CUR_OUT="$T/o3"
FAKE_READY_RC=20 bash "$HERE/pico_series.sh" "x=base" >"$T/o3" 2>&1; rc=$?
check "серия при ready не готов: код 2" "$([ $rc = 2 ]; echo $?)"
check "серия при ready не готов: pico start не зовётся" "$([ "$(has 'pico start' "$T/ctl.log")" != 0 ]; echo $?)"
check "серия при ready не готов: исходный cfg возвращён" "$(has 'push .*netrun.cfg.orig' "$T/adb.log")"
check "серия при ready не готов: нет нажатий/питания/настроек" "$(no_power_taps)"
check "серия при ready не готов: в выводе причина" "$(has 'очки не готовы' "$T/o3")"

# 4. Внутри run: ready ок, игра не вышла на передний план (kept for the user) — стоп, состояние `pico fg` в выводе.
reset; CUR_OUT="$T/o4"
FAKE_START_RC=1 bash "$HERE/pico_series.sh" "x=base" >"$T/o4" 2>&1; rc=$?
check "серия при start отказал: код 2" "$([ $rc = 2 ]; echo $?)"
check "серия зовёт pico ready Godot" "$(has 'pico ready Godot' "$T/ctl.log")"
check "серия зовёт pico start Godot <компонент>" "$(has 'pico start Godot com.megablok10.netrun/' "$T/ctl.log")"
check "серия при start отказал: есть строка состояния pico fg" "$(has 'состояние: окно=самотест' "$T/o4")"
check "серия при start отказал: нет нажатий/питания/настроек" "$(no_power_taps)"
check "серия сама не зовёт pico sleep/wake (это делает run)" "$([ "$(has 'pico (sleep|wake)' "$T/ctl.log")" != 0 ]; echo $?)"

# 5. Не devbox (ctl.sh нет): ни run, ни ready — `am start` напрямую; диалог → стоп; нажатий нет.
reset; CUR_OUT="$T/o5"
BOX_CTL="$T/нет-такого.sh" bash "$HERE/pico_series.sh" "x=base" >"$T/o5" 2>&1; rc=$?
check "без ctl.sh серия доходит до запуска игры (код 2 из-за диалога)" "$([ $rc = 2 ]; echo $?)"
check "без ctl.sh ctl не зовётся" "$([ ! -s "$T/ctl.log" ]; echo $?)"
check "без ctl.sh нет нажатий/питания/настроек" "$(no_power_taps)"

if [ "$fail" = 0 ]; then
  echo "box_guard_selftest: OK — $pass проверок"
  exit 0
fi
echo "box_guard_selftest: ПРОВАЛ — $fail из $((pass + fail)) (подробности — запуск с bash -x; каталог теста удаляется по выходу)"
exit 1

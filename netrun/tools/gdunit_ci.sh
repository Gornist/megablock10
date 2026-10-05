#!/usr/bin/env bash
# gdUnit4 в CI со сторожем зависания: то же, что tools/gdunit.sh (без --import), плюс «нет вывода N секунд» -> снимок состояния
# процесса -> kill -> один повтор. Зачем: 05.10 job «Netrun (Godot)» висел 50 минут (до отмены) на первом же кадре ProtoClient
# в test_cancel_on_the_deck_stops_the_charge — журнал встал через 20 мс после `start`, ни одной строки больше, gdUnit не
# дошёл даже до своего таймаута теста: встал главный поток Godot целиком, а не `await` теста (await с таймаутом сработал бы).
# Повтор того же SHA прошёл за 6:43. Без сторожа такое стоит 50 минут и ручной перезапуск; со сторожем — 4 минуты и диагноз в журнале.
#
# Использование: netrun/tools/gdunit_ci.sh [res://tests | res://tests/файл_test.gd]
# Переменные: GODOT (по умолчанию godot), GDUNIT_STALL_SEC (240), GDUNIT_TOTAL_SEC (1500), GDUNIT_ATTEMPTS (2).
# Код выхода — от gdUnit4 (0 зелёно, 100 есть упавшие тесты, 101 есть предупреждения); 124 — зависло во всех попытках.
# Упавшие тесты НЕ повторяются: повтор только при зависании (иначе сторож замаскировал бы настоящую нестабильность).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TARGET="${1:-res://tests}"
STALL_SEC="${GDUNIT_STALL_SEC:-240}"
TOTAL_SEC="${GDUNIT_TOTAL_SEC:-1500}"
ATTEMPTS="${GDUNIT_ATTEMPTS:-2}"

# Что делает зависший процесс: крутится (infinite loop: высокая нагрузка CPU) или стоит (взаимная блокировка: нагрузки нет, потоки на futex).
diagnose() {
	local pid=$1
	echo "::group::Зависание godot pid=$pid: состояние процесса"
	ps -o pid,stat,pcpu,etime,wchan:24 -p "$pid" 2>&1 || true
	local t
	for t in /proc/"$pid"/task/*; do
		printf 'поток %s: состояние/ядро %s, ждёт в %s\n' "$(basename "$t")" "$(cut -d' ' -f3,14,15 "$t/stat" 2>/dev/null)" "$(cat "$t/wchan" 2>/dev/null)"
	done
	if ! command -v gdb >/dev/null 2>&1; then
		sudo apt-get install -y -qq gdb >/dev/null 2>&1 || true
	fi
	if command -v gdb >/dev/null 2>&1; then
		echo "--- стеки всех потоков (gdb) ---"
		# На раннере sudo без пароля; без него (devbox, ptrace_scope=1) gdb не прицепится — остаётся таблица потоков выше.
		{ sudo -n gdb -p "$pid" -batch -ex 'thread apply all bt 25' 2>&1 || gdb -p "$pid" -batch -ex 'thread apply all bt 25' 2>&1; } | tail -n 300
	fi
	echo "::endgroup::"
}

rc=0
for attempt in $(seq 1 "$ATTEMPTS"); do
	log=$(mktemp)
	"$GODOT" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add "$TARGET" --ignoreHeadlessMode > >(tee "$log") 2>&1 &
	pid=$!
	start=$(date +%s)
	hung=""
	while kill -0 "$pid" 2>/dev/null; do
		sleep 5
		now=$(date +%s)
		if (( now - $(stat -c %Y "$log" 2>/dev/null || echo "$now") > STALL_SEC )); then hung="нет вывода больше ${STALL_SEC} с"; break; fi
		if (( now - start > TOTAL_SEC )); then hung="набор идёт дольше ${TOTAL_SEC} с"; break; fi
	done
	if [[ -n "$hung" ]]; then
		echo "gdunit_ci: ЗАВИСАНИЕ (попытка $attempt из $ATTEMPTS): $hung. Последние строки журнала:"
		tail -n 8 "$log" | sed 's/^/    /'
		diagnose "$pid"
		kill -9 "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
		rc=124
		continue
	fi
	wait "$pid"
	rc=$?
	sleep 1   # tee дописывает хвост
	exit "$rc"
done
echo "gdunit_ci: зависло во всех $ATTEMPTS попытках"
exit "$rc"

#!/usr/bin/env bash
# Тесты gdUnit4 без экрана — ровно то же, что делает CI (.github/workflows/netrun.yml).
# Использование (на devbox): netrun/tools/gdunit.sh [res://tests | res://tests/файл_test.gd]
# Код выхода — от gdUnit4: 0 зелёно, 100 есть упавшие тесты, 101 есть предупреждения. Отчёты — netrun/reports/.
# Редактор Godot AI может быть открыт: плагин в процессе с --headless отключается сам (GODOT_AI_ALLOW_HEADLESS не задаём).
set -uo pipefail
cd "$(dirname "$0")/.."
# Неинтерактивный ssh не читает профиль: godot лежит в ~/.local/bin, путь задаёт ~/netrun-env.sh (docs/netrun-devbox.md).
command -v "${GODOT:-godot}" >/dev/null 2>&1 || [[ ! -f "$HOME/netrun-env.sh" ]] || . "$HOME/netrun-env.sh"
GODOT="${GODOT:-godot}"
export ANDROID_ADB_SERVER_PORT=5099   # Godot на выходе зовёт `adb kill-server` (editor setting shutdown_adb_on_exit): на чужом порту он убивает пустоту, а не общий adb с очками и телефонами
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add "${1:-res://tests}" --ignoreHeadlessMode

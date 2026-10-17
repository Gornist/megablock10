#!/usr/bin/env bash
# Общая проверка стендов (srv_p6/p7/p9.sh, p6_run.sh): у копии netrun должен быть кэш классов Godot (.godot/global_script_class_cache.cfg).
# Без него сервер падает «NetConfig/RunMode not declared» и показ не встаёт (17.10: стенд запустили из копии без .godot).
# Источник: `. "$(dirname "$0")/stand_guard.sh"`; потом `stand_require_cache <каталог проекта netrun>`.
# Кэша нет — один раз импортируем проект (godot --headless --import, до 5 мин); не получилось — понятная строка и код 2.

stand_require_cache() {
  local proj="${1:-.}" cache
  cache="$proj/.godot/global_script_class_cache.cfg"
  [ -s "$cache" ] && return 0
  command -v godot >/dev/null || { echo "stand: в $proj нет .godot, а godot не найден в PATH (~/netrun-env.sh, ~/.local/bin)" >&2; exit 2; }
  echo "stand: в $proj нет .godot (кэш классов): импортирую проект, до 5 минут…" >&2
  timeout 300 godot --headless --path "$proj" --import </dev/null >/dev/null 2>&1 || true
  [ -s "$cache" ] && return 0
  echo "stand: импорт не создал $cache — выполните 'godot --headless --path $proj --import' и смотрите ошибку; без кэша классов сервер не стартует" >&2
  exit 2
}

#!/bin/bash
# Прогоняет .claude/hooks/guard-bash.sh по таблице scripts/test-hook.cases.
# Формат строки: <ожидаемый код 0|2><TAB><команда>; «#» — комментарий; в команде «\n» значит перевод строки (для heredoc).
# Печатает вердикт: «HOOK OK: N случаев» или по строке «HOOK FAIL: ждали X, получили Y: <команда>». Код 0/1.
# Зачем: хук давал ложные отказы (05–06.10) и ловил их только в живой работе.
root=$(cd "$(dirname "$0")/.." && pwd)
hook="$root/.claude/hooks/guard-bash.sh"
cases="$root/scripts/test-hook.cases"
[ -f "$hook" ] && [ -f "$cases" ] || { echo "HOOK FAIL: нет $hook или $cases"; exit 1; }
command -v jq >/dev/null || { echo "HOOK НЕ ПРОВЕРЕНО: нет jq"; exit 3; }
n=0
bad=0
while IFS=$'\t' read -r want cmd; do
  case "$want" in '' | '#'*) continue ;; esac
  cmd=${cmd//\\n/$'\n'}
  n=$((n + 1))
  got=0
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$hook" >/dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    bad=$((bad + 1))
    echo "HOOK FAIL: ждали $want, получили $got: $cmd"
  fi
done <"$cases"
[ "$bad" -eq 0 ] || exit 1
echo "HOOK OK: $n случаев"

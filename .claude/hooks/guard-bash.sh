#!/bin/bash
# PreToolUse-хук для Bash: отклоняет команды, которые правила проекта запрещают (CLAUDE.md, «Работа агента»; skill orchestrate).
# Раньше правила держались только на памяти модели и нарушались: git add -A унёс чужую незаконченную работу в коммит и сломал CI,
# правки через python-heredoc (233 раза за две сессии) гоняли файлы через контекст, sleep-циклы висели часами, rsync без --delete
# оставлял на devbox чужие *_test.gd (gdUnit зависал в отладчике).
# Вход — JSON на stdin; выход 2 + причина в stderr = отказ (причина уходит агенту). Команды, набранные владельцем через «!», хук не видит.
cmd=$(jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0
deny() { echo "Отклонено хуком .claude/hooks/guard-bash.sh: $1" >&2; exit 2; }
has() { grep -Eq -- "$1" <<<"$cmd"; }

has '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:]]|$)' &&
  deny "git add -A/./--all — добавляй файлы явными путями: в рабочих копиях бывает чужая незаконченная работа."
if has '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
  has '[[:space:]](-f|--force|--force-with-lease)([=[:space:]]|$)' &&
    deny "git push --force — историю не переписываем; force только руками владельца."
  has '[[:space:]:+](refs/heads/)?main([[:space:]]|$)' &&
    deny "push в main — только по команде владельца и только им самим (перемотка с зелёными CI)."
fi
# Исключение — пуш в удалённый devbox (skill devbox): это не публикация, а доставка на машину сборки.
has '(^|[;&|[:space:]])git[[:space:]]+(push|commit)([[:space:]].*)?[[:space:]]--no-verify' && ! has 'git[[:space:]]+push[[:space:]]+(-[^[:space:]]+[[:space:]]+)*devbox[[:space:]]' &&
  deny "--no-verify — хук не обходим, красный хук чинить (пуш в devbox — можно)."
has 'cleanTest' &&
  deny "cleanTest* удаляет закоммиченные эталоны Paparazzi; заново без кэша — --rerun-tasks."
if has 'python3?[[:space:]]+-[[:space:]]*<<'; then
  has "(open\([^)]*,[[:space:]]*(mode=)?['\"][wa]b?\+?['\"]|write_text\(|\.write\()" &&
    deny "правка файлов через python-heredoc — используй Edit/Write (файл не идёт через контекст дважды)."
fi
n=$(grep -Eo '(^|[;&|[:space:]])sleep[[:space:]]+[0-9]+' <<<"$cmd" | grep -Eo '[0-9]+$' | sort -n | tail -1)
[ -n "$n" ] && [ "$n" -gt 30 ] &&
  deny "sleep $n — не ждать вслепую: фоновый вызов с одним итогом (run_in_background: scripts/ci-wait.sh, dbx.sh, dev.sh)."
if has '(^|[;&|[:space:]])rsync[[:space:]]' && has 'devbox' && has 'netrun' && ! has '[[:space:]]--delete'; then
  deny "rsync netrun на devbox без --delete оставляет чужие *_test.gd — используй netrun/tools/dev.sh sync."
fi
has 'ssh[[:space:]].*devbox.*gdunit\.sh' &&
  deny "gdunit напрямую — через netrun/tools/dev.sh test (flock, timeout, итог строкой)."
exit 0

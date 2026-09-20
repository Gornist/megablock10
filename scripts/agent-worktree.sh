#!/bin/bash
# Отдельная рабочая копия на каждого агента/задачу: параллельные агенты не делят рабочее дерево, индекс и незакоммиченные правки.
#   scripts/agent-worktree.sh new <имя> [база]   — ../megablock10-wt/<имя> на ветке agent/<имя> от origin/main (или от [база])
#   scripts/agent-worktree.sh finish <имя>       — проверка (check.sh), пуш ветки и Pull Request в main
#   scripts/agent-worktree.sh rm <имя>           — убрать рабочую копию (ветка остаётся, пока PR не влит)
#   scripts/agent-worktree.sh ls                 — список рабочих копий
# Общее на всех: стенд e2e (порты эмуляторов и сервера фиксированы) — одновременно им владеет одна копия, см. scripts/e2e/up.sh.
set -e
MAIN=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
WT_ROOT="$(dirname "$MAIN")/$(basename "$MAIN")-wt"
cmd=${1:-}; name=${2:-}; dir="$WT_ROOT/$name"
case $cmd in
  new)
    [ -n "$name" ] || { echo "укажите имя"; exit 2; }
    git -C "$MAIN" fetch -q origin
    git -C "$MAIN" worktree add -b "agent/$name" "$dir" "${3:-origin/main}"
    # Неотслеживаемое, но нужное для сборки: путь к Android SDK. node_modules — ссылкой: одинаковый package-lock, ставить заново долго.
    [ -f "$MAIN/local.properties" ] && cp "$MAIN/local.properties" "$dir/"
    for m in server client; do
      [ -d "$MAIN/admin-web/$m/node_modules" ] && ln -s "$MAIN/admin-web/$m/node_modules" "$dir/admin-web/$m/node_modules"
    done
    git -C "$dir" config core.hooksPath .githooks
    echo "готово: $dir (ветка agent/$name). Работайте там: cd $dir"
    echo "Стенд e2e общий на машину: если он занят другой копией, up.sh откажет — остановите его (scripts/e2e/down.sh) или подождите.";;
  finish)
    [ -d "$dir" ] || { echo "нет рабочей копии $dir"; exit 2; }
    cd "$dir"
    [ -z "$(git status --porcelain)" ] || { echo "есть незакоммиченные правки — сначала коммит"; exit 1; }
    git fetch -q origin && git rebase origin/main
    scripts/check.sh || { echo "check.sh красный — PR не создан"; exit 1; }
    git push -u origin "agent/$name"
    gh pr create --base main --head "agent/$name" --fill;;
  rm)
    git -C "$MAIN" worktree remove "$dir" --force && echo "убрано: $dir";;
  ls) git -C "$MAIN" worktree list;;
  *) sed -n 2,9p "$0"; exit 2;;
esac

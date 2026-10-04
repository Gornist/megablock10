#!/usr/bin/env bash
# Готова ли ветка к слиянию в main перемоткой (только чтение — НИЧЕГО не выполняет). Само слияние — по явной команде владельца.
#   admin-web/tools/merge-ready.sh <ветка>
. "$(dirname "$0")/_lib.sh"
b=${1:?использование: merge-ready.sh <ветка>}
cd "$REPO" || exit 2
git fetch -q origin
sha=$(git rev-parse "origin/$b" 2>/dev/null) || { echo "нет origin/$b — ветка не запушена"; exit 1; }
ok=1
git merge-base --is-ancestor origin/main "origin/$b" && echo "перемотка: возможна" || { ok=0; echo "перемотка: НЕТ — main ушёл вперёд ($(git rev-list --count "origin/$b"..origin/main) коммитов). rebase на origin/main, push --force-with-lease, повторить CI"; }
ci=$(gh run list --workflow=main.yml --branch "$b" --limit 20 --json headSha,conclusion --jq "[.[]|select(.headSha==\"$sha\")][0].conclusion // \"нет запуска\"")
[ "$ci" = success ] && echo "CI main.yml на ${sha:0:7}: success" || { ok=0; echo "CI main.yml на ${sha:0:7}: $ci"; }
dirty=$(git status --porcelain | grep -v '^??' | wc -l | tr -d ' '); [ "$dirty" != 0 ] && echo "в рабочей копии $dirty незакоммиченных изменений (в origin они не попадут)"
out=$(git diff --name-only origin/main..."origin/$b" | grep -vc '^admin-web/' || true); [ "$out" != 0 ] && { ok=0; echo "в ветке $out файлов вне admin-web/ — не моя зона"; }
if [ $ok = 1 ]; then echo "ГОТОВО. По команде владельца: git push origin origin/$b:main --no-verify"; else echo "НЕ ГОТОВО"; exit 1; fi

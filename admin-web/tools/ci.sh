#!/usr/bin/env bash
# Запустить CI на ветке, дождаться и выдать вердикт одной строкой (при провале — упавшие job и хвост лога, ≤ 30 строк).
#   admin-web/tools/ci.sh [ветка] [workflow=main.yml]
# Запускать в фоне (run_in_background): придёт одно уведомление вместо 5–8 вызовов с sleep.
# Ветка должна быть уже запушена: CI идёт на её удалённом коммите, а не на локальном.
. "$(dirname "$0")/_lib.sh"
branch=${1:-$(git -C "$REPO" branch --show-current)}; wf=${2:-main.yml}
cd "$REPO" || exit 2
git fetch -q origin "$branch" 2>/dev/null || { echo "ci: ветки $branch нет на origin — сначала push"; exit 2; }
sha=$(git rev-parse "origin/$branch")
[ "$(git rev-parse "$branch" 2>/dev/null)" != "$sha" ] && echo "ci: внимание — локальный $branch не совпадает с origin ($(git rev-parse --short "$branch" 2>/dev/null) ≠ ${sha:0:7}); CI пойдёт на origin"
start=$SECONDS; before=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gh workflow run "$wf" --ref "$branch" >/dev/null 2>&1 || { echo "ci: не удалось запустить $wf на $branch"; exit 2; }
# Свой запуск ищем по sha и времени создания — иначе можно подхватить чужой.
id=""; for _ in $(seq 1 30); do
  id=$(gh run list --workflow="$wf" --branch "$branch" --event workflow_dispatch --limit 5 --json databaseId,headSha,createdAt --jq "[.[]|select(.headSha==\"$sha\" and .createdAt>=\"$before\")][0].databaseId // empty")
  [ -n "$id" ] && break; sleep 4; done
[ -z "$id" ] && { echo "ci: запуск $wf на ${sha:0:7} не появился за 2 мин"; exit 2; }
gh run watch "$id" --interval 20 >/dev/null 2>&1
res=$(gh run view "$id" --json conclusion --jq .conclusion)
jobs=$(gh run view "$id" --json jobs --jq '[.jobs[]|"\(.name): \(.conclusion)"]|join(", ")')
echo "$wf @${sha:0:7}: $res за $(dur $((SECONDS-start))) — $jobs"
if [ "$res" != success ]; then
  gh run view "$id" --log-failed 2>&1 | grep -vE '^\s*$|##\[(group|endgroup)\]' | tail -n 30 | cut -c1-200
  echo "полный журнал: gh run view $id --log-failed"; exit 1
fi

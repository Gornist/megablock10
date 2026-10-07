#!/bin/bash
# Поезд слияний: несколько готовых PR — одной веткой на свежем main, один прогон CI и одна перемотка вместо круга
# «влить → догнать следующий → ждать CI» на каждый PR (06.10: три независимых PR влились поездом за один CI вместо трёх).
#   scripts/train.sh N [M…]   — собрать agent/queue-<дата-время> из origin/main и голов PR по порядку, запушить, открыть PR «Поезд слияний»
# Берёт PR открытый, с базой main и зелёным CI; красный — только если его голова входит в другой PR поезда (пара, как #40 → #41:
# итог решает CI поезда). Конфликт — PR выпадает из поезда с пометкой, остальные едут. Чужие ветки не меняет, main не трогает.
# Дальше: scripts/ci-wait.sh pr <поезд> в фоне; зелёный — владельцу `scripts/land.sh <поезд>`, GitHub сам отметит PR поезда влитыми.
# Код 0 — поезд открыт (номер в последней строке), 1 — ни один PR не годится, 2 — ошибка вызова.
set -u
[ $# -gt 0 ] || { sed -n 2,9p "$0"; exit 2; }
REPO=Gornist/megablock10
cd "$(git rev-parse --show-toplevel)" || exit 2
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "TRAIN: в рабочей копии незакоммиченное — запусти из чистой worktree"; exit 2; }
git fetch -q origin || { echo "TRAIN: не достучался до origin"; exit 1; }

NUMS=(); HEADS=(); SHAS=(); TITLES=()
for n in "$@"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "TRAIN: «$n» — не номер PR"; exit 2; }
  j=$(gh pr view "$n" -R $REPO --json state,baseRefName,headRefName,headRefOid,title 2>/dev/null) || { echo "TRAIN #$n: не найден — пропущен"; continue; }
  [ "$(jq -r .state <<<"$j")" = OPEN ] && [ "$(jq -r .baseRefName <<<"$j")" = main ] || { echo "TRAIN #$n: не открыт или база не main — пропущен"; continue; }
  NUMS+=("$n"); HEADS+=("$(jq -r .headRefName <<<"$j")"); SHAS+=("$(jq -r .headRefOid <<<"$j")"); TITLES+=("$(jq -r .title <<<"$j" | cut -c1-80)")
done
[ ${#NUMS[@]} -gt 0 ] || { echo "TRAIN: ни один PR не годится"; exit 1; }

# CI каждого: зелёный, либо красный, но голова входит в другой PR поезда (пара).
OK=(); for i in "${!NUMS[@]}"; do
  n=${NUMS[$i]}; git fetch -q origin "${HEADS[$i]}" 2>/dev/null
  bad=$(gh pr checks "$n" -R $REPO --json name,bucket --jq '.[] | select(.bucket != "pass" and .bucket != "skipping") | "\(.name):\(.bucket)"' 2>/dev/null)
  if [ -n "$bad" ]; then
    inner=""; for k in "${!NUMS[@]}"; do [ $k != $i ] && git merge-base --is-ancestor "${SHAS[$i]}" "${SHAS[$k]}" 2>/dev/null && inner=${NUMS[$k]}; done
    [ -n "$inner" ] || { echo "TRAIN #$n: CI не зелёный ($(echo $bad)) — пропущен"; continue; }
    echo "TRAIN #$n: CI красный, но входит в #$inner — едет парой"
  fi
  OK+=("$i")
done
[ ${#OK[@]} -gt 0 ] || { echo "TRAIN: ни один PR не годится"; exit 1; }

B="agent/queue-$(date +%m%d-%H%M)"
WT=$(mktemp -d)/train; git worktree add -q -b "$B" "$WT" origin/main || exit 1
IN=(); BODY=""
for i in "${OK[@]}"; do
  if git -C "$WT" merge --no-edit -q "${SHAS[$i]}" -m "Поезд $B: #${NUMS[$i]} ${HEADS[$i]}" >/dev/null 2>&1; then
    IN+=("${NUMS[$i]}"); BODY+="- #${NUMS[$i]} \`${HEADS[$i]}\` — ${TITLES[$i]}"$'\n'; echo "TRAIN #${NUMS[$i]}: в поезде"
  else git -C "$WT" merge --abort; echo "TRAIN #${NUMS[$i]}: конфликт с поездом — выпал, сессии догнать ветку до main"; fi
done
if [ ${#IN[@]} -eq 0 ]; then git worktree remove --force "$WT"; git branch -q -D "$B"; echo "TRAIN: поезд пуст"; exit 1; fi
git -C "$WT" push -q -u origin "$B" >/tmp/mb10-train-push.log 2>&1 || { echo "TRAIN: пуш не прошёл — /tmp/mb10-train-push.log"; git worktree remove --force "$WT"; exit 1; }
BODY="Поезд слияний (scripts/train.sh): PR ниже собраны на свежем main одной веткой — один CI, одна перемотка (\`scripts/land.sh <этот PR>\`); GitHub сам отметит их влитыми. Чужие ветки не изменены.

$BODY
🤖 Generated with [Claude Code](https://claude.com/claude-code)"
url=$(gh pr create -R $REPO --base main --head "$B" --title "Поезд слияний: $(printf '#%s ' "${IN[@]}")" --body "$BODY") || { echo "TRAIN: PR не открылся (ветка $B запушена)"; exit 1; }
git worktree remove --force "$WT"; git branch -q -D "$B"   # ветка живёт на origin, локальная копия не нужна
echo "TRAIN: $url — дальше scripts/ci-wait.sh pr ${url##*/} в фоне"
echo "${url##*/}"

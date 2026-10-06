#!/bin/bash
# Очередь слияний в main одной командой владельца. Очередь собирает Pipeline manager (сессии пишут ему «готово к слиянию: PR N»),
# владелец запускает: раньше он сам ходил по сессиям и вливал каждый PR отдельной командой.
#   scripts/land.sh --check N [N…]   — только вердикт по каждому PR (агентам можно; ничего не меняет)
#   scripts/land.sh N [N…]           — влить по порядку перемоткой (только владелец; агентам запрещено хуком guard-bash)
# Для каждого PR: открыт, база main, все проверки зелёные на текущем коммите, ветка — прямое продолжение main (перемотка).
# Первый же PR, который не годится, останавливает очередь: остальное не трогается. После слияний — pull --ff-only основной папки.
# Код 0 — всё влито (или --check: всё готово), 1 — очередь остановлена, 2 — ошибка вызова.
set -u
CHECK=0; [ "${1:-}" = --check ] && { CHECK=1; shift; }
[ $# -gt 0 ] || { sed -n 2,7p "$0"; exit 2; }
REPO=Gornist/megablock10
MAIN=$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); MAIN=${MAIN%/.git}
git -C "$MAIN" fetch -q origin main || { echo "LAND: не достучался до origin"; exit 1; }
base=$(git -C "$MAIN" rev-parse origin/main)
done_n=""
for n in "$@"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "LAND: «$n» — не номер PR"; exit 2; }
  j=$(gh pr view "$n" -R $REPO --json state,baseRefName,headRefOid,headRefName,title 2>/dev/null) || { echo "LAND #$n: PR не найден"; exit 1; }
  st=$(jq -r .state <<<"$j"); br=$(jq -r .baseRefName <<<"$j"); sha=$(jq -r .headRefOid <<<"$j"); hd=$(jq -r .headRefName <<<"$j"); tt=$(jq -r .title <<<"$j" | cut -c1-70)
  [ "$st" = OPEN ] && [ "$br" = main ] || { echo "LAND #$n: не открыт или база не main ($st, $br)"; exit 1; }
  bad=$(gh pr checks "$n" -R $REPO --json name,bucket --jq '.[] | select(.bucket != "pass" and .bucket != "skipping") | "\(.name):\(.bucket)"' 2>/dev/null)
  [ -z "$(gh pr checks "$n" -R $REPO --json name --jq '.[].name' 2>/dev/null)" ] && bad="проверок нет"
  [ -z "$bad" ] || { echo "LAND #$n ($hd): CI не зелёный — $(echo $bad)"; exit 1; }
  git -C "$MAIN" fetch -q origin "$hd" 2>/dev/null
  git -C "$MAIN" merge-base --is-ancestor "$base" "$sha" 2>/dev/null || { echo "LAND #$n ($hd): отстал от main — Pipeline manager вливает main в ветку и ждёт CI"; exit 1; }
  if [ $CHECK = 1 ]; then echo "LAND #$n готов: $tt"; base=$sha; continue; fi
  gh api -X PATCH "repos/$REPO/git/refs/heads/main" -f sha="$sha" -F force=false >/dev/null || { echo "LAND #$n: сервер отказал в перемотке"; exit 1; }
  echo "LAND #$n влит: ${sha:0:7} $tt"; base=$sha; done_n="$done_n #$n"
done
[ $CHECK = 1 ] && exit 0
if [ -z "$(git -C "$MAIN" status --porcelain --untracked-files=no)" ] && [ "$(git -C "$MAIN" branch --show-current)" = main ]; then
  git -C "$MAIN" pull -q --ff-only && echo "LAND: основная папка обновлена до $(git -C "$MAIN" rev-parse --short HEAD)"
else echo "LAND: основная папка не обновлена (не на main или есть правки) — git -C $MAIN pull --ff-only вручную"; fi
echo "LAND: влито$done_n"

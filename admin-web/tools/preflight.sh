#!/usr/bin/env bash
# Перед коммитом (только чтение): куда ушёл main, не вышли ли правки за зону admin-web/, что осталось неотслеживаемым.
#   admin-web/tools/preflight.sh
# Коммит после него — `git commit -m … -- <явные пути>`; `git add -A` и `git add .` запрещены (чужие правки попадут в коммит).
. "$(dirname "$0")/_lib.sh"
cd "$REPO" || exit 2
git fetch -q origin
br=$(git branch --show-current); read -r behind ahead < <(git rev-list --left-right --count origin/main..."$br" 2>/dev/null || echo "? ?")
out=$(git status --porcelain | grep -v ' admin-web/.*node_modules' | awk '{print $NF}' | grep -v '^admin-web/' || true)
unt=$(git status --porcelain | grep '^??' | awk '{print $2}' | grep '^admin-web/' | grep -v node_modules || true)
bad=0
echo "ветка $br: впереди main на $ahead, позади на $behind"
[ "${behind:-0}" != 0 ] && echo "  main ушёл вперёд — перед слиянием нужен rebase (и повторный CI)"
if [ -n "$out" ]; then bad=1; echo "ВНЕ ЗОНЫ admin-web/ (не мои, не коммитить):"; echo "$out" | head -8 | sed 's/^/  /'; fi
[ -n "$unt" ] && { echo "неотслеживаемые в зоне (добавить явно или удалить):"; echo "$unt" | head -8 | sed 's/^/  /'; }
mod=$(git status --porcelain | grep -v '^??' | awk '{print $NF}' | grep -c '^admin-web/' || true)
echo "изменено в зоне: $mod"
[ $bad = 0 ] && echo "ок" || echo "есть правки вне зоны — коммитить только явные пути"
exit $bad

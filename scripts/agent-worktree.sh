#!/bin/bash
# Отдельная рабочая копия на каждого агента/задачу: параллельные агенты не делят рабочее дерево, индекс и незакоммиченные правки.
#   scripts/agent-worktree.sh new <имя> [база]   — ../megablock10-wt/<имя> на ветке agent/<имя> от origin/main (или от [база])
#   scripts/agent-worktree.sh finish <имя>       — проверка (check.sh), пуш ветки и Pull Request в main
#   scripts/agent-worktree.sh rm <имя>           — убрать рабочую копию (ветка остаётся, пока PR не влит)
#   scripts/agent-worktree.sh gone <имя>         — влита ли ветка в main по содержимому; печатает команды уборки, сам не удаляет
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
    # Неотслеживаемое, но нужное для сборки: путь к Android SDK. node_modules не ставим и не ссылаемся на основную копию: ссылка давала
    # чужой package-lock и нативный better-sqlite3 под другую версию Node (пуш падал на 259 тестах сервера, 04.10). Ставит при первой нужде
    # scripts/check.sh (npm ci) или вручную admin-web/tools/wt-deps.sh.
    [ -f "$MAIN/local.properties" ] && cp "$MAIN/local.properties" "$dir/"
    git -C "$dir" config core.hooksPath .githooks
    echo "готово: $dir (ветка agent/$name). Работайте там: cd $dir"
    echo "Стенд e2e общий на машину: если он занят другой копией, up.sh откажет — остановите его (scripts/e2e/down.sh) или подождите.";;
  finish)
    [ -d "$dir" ] || { echo "нет рабочей копии $dir"; exit 2; }
    cd "$dir"
    [ -z "$(git status --porcelain)" ] || { echo "есть незакоммиченные правки — сначала коммит"; exit 1; }
    # Слиянием, а не rebase: ветка могла уже быть запушена, а rebase потребовал бы force-push (его блокирует хук).
    git fetch -q origin && git merge --no-edit origin/main
    scripts/check.sh || { echo "check.sh красный — PR не создан"; exit 1; }
    git push -u origin "agent/$name"
    gh pr create --base main --head "agent/$name" --fill;;
  rm)
    # Без --force: с незакоммиченными правками или новыми файлами git откажет — работа не пропадёт молча.
    git -C "$MAIN" worktree remove "$dir" && echo "убрано: $dir (ветка agent/$name осталась)";;
  gone)
    # Только вердикт, ничего не удаляет: влита ли ветка в main по СОДЕРЖИМОМУ (после cherry-pick хеши другие, git cherry врёт),
    # и какие команды убрать её. Удаляет владелец или сессия по его слову.
    b="agent/$name"; git -C "$MAIN" fetch -q origin
    git -C "$MAIN" rev-parse -q --verify "$b" >/dev/null || git -C "$MAIN" rev-parse -q --verify "origin/$b" >/dev/null || { echo "нет ветки $b"; exit 2; }
    ref=$(git -C "$MAIN" rev-parse -q --verify "$b" >/dev/null && echo "$b" || echo "origin/$b")
    # Пробное слияние в памяти: если влитие ветки в main не меняет дерево main — всё её содержимое уже там
    # (и после cherry-pick, и когда файлы в main потом правили).
    tree=$(git -C "$MAIN" merge-tree --write-tree origin/main "$ref" 2>/dev/null | head -1) || tree=
    if [ "$tree" != "$(git -C "$MAIN" rev-parse "origin/main^{tree}")" ]; then
      echo "GONE $b: НЕ влита — слияние в main что-то изменило бы (или конфликт):"
      [ -n "$tree" ] && git -C "$MAIN" diff --stat origin/main "$tree" | tail -n 8; exit 1
    fi
    # Worktree ищем по ветке, а не по имени папки (папку могли назвать иначе).
    wt=$(git -C "$MAIN" worktree list --porcelain | awk -v b="refs/heads/$b" '/^worktree /{w=substr($0,10)} $0=="branch "b{print w}')
    [ -n "$wt" ] && [ -n "$(git -C "$wt" status --porcelain)" ] && { echo "GONE $b: коммиты в main, но в $wt есть незакоммиченное — сначала разобрать"; exit 1; }
    # worktree remove стирает и игнорируемые файлы (07.10 — карточки .cards/ Геймдизайна); кэши сборки не в счёт.
    ign=$([ -n "$wt" ] && git -C "$wt" status --porcelain --ignored=matching | sed -n 's/^!! //p' |
      grep -Ev '(^|/)(build|node_modules|dist|\.gradle|\.kotlin|\.godot|\.pio|\.cxx)/$|(^|/)(\.DS_Store|local\.properties)$' | head -3)
    [ -n "$ign" ] && { echo "GONE $b: коммиты в main, но в $wt есть игнорируемые файлы ($(echo $ign)) — remove их сотрёт, сначала перенести"; exit 1; }
    echo "GONE $b: влита целиком. Убрать:"
    [ -n "$wt" ] && echo "  git worktree remove $wt"
    git -C "$MAIN" rev-parse -q --verify "$b" >/dev/null && echo "  git branch -D $b"
    git -C "$MAIN" rev-parse -q --verify "origin/$b" >/dev/null && echo "  git push origin --delete $b"
    exit 0;;
  ls) git -C "$MAIN" worktree list;;
  *) sed -n 2,10p "$0"; exit 2;;
esac

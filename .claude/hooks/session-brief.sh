#!/bin/bash
# SessionStart-хук: короткая сводка в контекст новой сессии (≤ ~800 символов) — то, что CLAUDE.md велит собрать первым
# делом тремя-четырьмя командами (git log, git status, открытые PR, свои worktree). Экономит ходы на старте каждой сессии.
# Ничего не меняет; сеть (gh) — с пределом, без неё сводка просто короче. Вывод stdout уходит в контекст сессии.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
MAIN=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); MAIN=${MAIN%/.git}
echo "Сводка на старт (хук session-brief):"
echo "- main: $(git -C "$MAIN" log -1 --format='%h %s' main 2>/dev/null | cut -c1-90)"
br=$(git branch --show-current 2>/dev/null)
echo "- эта копия: ${PWD/#$HOME/~} на ${br:-detached}$([ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && echo ', есть незакоммиченное')"
[ "$br" = main ] && [ "$PWD" = "$MAIN" ] && echo "  (основная папка общая — не править здесь: scripts/agent-worktree.sh new <имя>)"
wts=$(git -C "$MAIN" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/agent/##p' | tr '\n' ' ')
[ -n "$wts" ] && echo "- worktree agent/*: $wts"
# gh без зависания: фоновый запуск и предел 4 с (на Mac нет GNU timeout).
tmp=$(mktemp); ( gh pr list --state open --json number,title,labels \
  -q '.[] | "  #\(.number) \(.title[0:60]) [\([.labels[].name | sub("зона: "; "")] | join(","))]"' > "$tmp" 2>/dev/null & p=$!
  for _ in 1 2 3 4 5 6 7 8; do kill -0 $p 2>/dev/null || break; sleep 0.5; done; kill $p 2>/dev/null ) 2>/dev/null
if [ -s "$tmp" ]; then echo "- открытые PR:"; head -8 "$tmp"; else echo "- открытых PR нет (или GitHub недоступен)"; fi
rm -f "$tmp"
echo "Готово к слиянию → SendMessage Pipeline: «готово к слиянию: PR N — что, пара/порядок»."
exit 0

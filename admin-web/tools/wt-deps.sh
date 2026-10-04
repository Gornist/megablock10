#!/usr/bin/env bash
# Зависимости в свежем git-worktree: scripts/agent-worktree.sh кладёт симлинки на node_modules основной копии, но у ветки могут быть
# другие версии (так было с ws и better-sqlite3 13). Симлинк заменяется настоящей установкой `npm ci`; основной копии это не касается.
#   admin-web/tools/wt-deps.sh [server|client|all]
. "$(dirname "$0")/_lib.sh"
part=${1:-all}
for p in server client; do
  [ "$part" != all ] && [ "$part" != "$p" ] && continue
  d="$ADMIN/$p"
  if [ -L "$d/node_modules" ]; then rm "$d/node_modules"; else [ -d "$d/node_modules" ] && { echo "$p: node_modules уже настоящий — пропускаю"; continue; }; fi
  (cd "$d" && PATH="$(node_dir "$p"):$PATH" npm ci --silent >"$LOGS/wt-deps-$p.log" 2>&1) && echo "$p: npm ci ок" || { echo "$p: npm ci ПРОВАЛ — $LOGS/wt-deps-$p.log"; tail -n 8 "$LOGS/wt-deps-$p.log"; }
done

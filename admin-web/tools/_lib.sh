#!/usr/bin/env bash
# Общее для admin-web/tools/*.sh: корень, каталог логов, выбор Node. Подключается через `. "$(dirname "$0")/_lib.sh"`.
set -u
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN="$(cd "$TOOLS_DIR/.." && pwd)"
REPO="$(git -C "$ADMIN" rev-parse --show-toplevel)"
LOGS=/tmp/mb10-tools
mkdir -p "$LOGS"

# Node: NODE_BIN из окружения важнее всего (как у scripts/check.sh); иначе 22 (как в CI), иначе 26 из /opt/homebrew/bin.
# Нужен >= 22: better-sqlite3 13 на Node 20 падает SIGSEGV, vitest 5 на 20 не стартует. Node 20 не использовать.
node_dir() {
  local d
  for d in "${NODE_BIN:-}" /opt/homebrew/opt/node@22/bin /opt/homebrew/bin; do [ -n "$d" ] && [ -x "$d/node" ] && { echo "$d"; return; }; done
  dirname "$(command -v node)"
}

# Секунды -> «4м12с».
dur() { local s=$1; [ "$s" -ge 60 ] && echo "$((s/60))м$((s%60))с" || echo "${s}с"; }

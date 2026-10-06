#!/bin/bash
# Не вышла ли ветка за зону своей сессии (CLAUDE.md, «Зоны сессий»): файлы, изменённые от origin/main (коммиты + рабочее дерево + новые),
# которых нет в зоне. Раньше сессии проверяли это руками (git diff --name-only … | grep -v …), а пересечение зон уже ломало CI.
#   scripts/zone-check.sh android|collector|nodes|godot|blender|gamedesign|pipeline
# Код 0 — всё в зоне, 1 — есть файлы вне зоны (список; правку в чужой зоне — описать соседу, а не коммитить), 2 — неизвестная зона.
# Зоны — копия таблицы из CLAUDE.md: правите таблицу — правьте и здесь. Общие для всех: свой раздел docs/progress.md.
cd "$(dirname "$0")/.." || exit 2
NODES='^firmware/|^admin-web/server/src/(displays/|audio/|routes/audio\.ts|scripts/display[^/]*\.ts|display[^/]*\.test\.ts|audio\.test\.ts|firmwareHost\.test\.ts)|^\.github/workflows/firmware\.yml|^docs/(displays|firmware-plan|sound-nodes)\.md'
BLENDER='^netrun/assets/|^netrun/client/(avatar_view|hand_view|avatar_body|head_[^/]*)\.gd|^netrun/tests/assets_[^/]*'
case $1 in
  android)   IN='^(app|kit|rules|scripts/e2e)/|^docs/(android-handoff|architecture|refactor-plan|device-testing|db-migrations)\.md|^docs/ux/|^scripts/phone\.sh$'; OUT='';;
  collector) IN='^admin-web/'; OUT="$NODES";;
  nodes)     IN="$NODES"; OUT='';;
  godot)     IN='^netrun/|^netrun-bridge/|^docs/netrun[^/]*'; OUT="$BLENDER";;
  blender)   IN="$BLENDER"; OUT='';;
  gamedesign) IN='^docs/gamedesign/'; OUT='';;
  pipeline)  IN='^CLAUDE\.md|^AGENTS\.md|^\.claude/|^\.githooks/|^scripts/[^/]*$'; OUT='';;
  *) echo "использование: zone-check.sh android|collector|nodes|godot|blender|gamedesign|pipeline"; exit 2;;
esac
git fetch -q origin main 2>/dev/null || true
CH=$( { git diff --name-only origin/main...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
BAD=$(grep -v '^docs/progress\.md$' <<<"$CH" | grep -Ev "$IN" ; [ -n "$OUT" ] && grep -E "$OUT" <<<"$CH")
BAD=$(grep -v '^$' <<<"$BAD" | sort -u)
if [ -z "$BAD" ]; then echo "ZONE $1: ок — $(grep -c . <<<"$CH") файл(ов), все в зоне"; exit 0; fi
echo "ZONE $1: вне зоны $(grep -c . <<<"$BAD") файл(ов) — описать владельцу зоны, не коммитить:"; sed 's/^/  /' <<<"$BAD" | head -20
exit 1

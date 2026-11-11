---
name: blender-session-zone
description: "Зона и правила сессии Blender (вид Сети) от Pipeline manager, 5 окт 2026 — что можно писать, что нельзя, как проверять"
metadata:
  node_type: memory
  type: project
  originSessionId: 714a5d95-4ee3-44c4-b1be-8bd46d0e3b79
  modified: 2026-10-05T07:15:39.475Z
---

Сессия Blender отвечает за вид Сети. Таблица зон — PR #14 (CLAUDE.md, «Зоны сессий»).

**Пишет:** `netrun/assets/` (модели, `src/*.py`, шейдеры, превью-сцены, ARCHITECTURE.md, STYLE.md) и отрисовку тела/рук в `netrun/client/` (`*_view.gd`, `avatar_body.gd`, `head_*.gd`).
**Не трогает:** `netrun/shared/`, `netrun/server/`, `netrun-bridge/` (зона Godot — новое поле позы предлагать Godot-сессии сообщением: файл, поле, зачем); `app/`, `admin-web/`, `firmware/`, `CLAUDE.md`, `.claude/`, общие `scripts/`.

**Правила:** своя worktree (`scripts/agent-worktree.sh new <имя>`), файлы в git — явными путями; цикл по skill `netrun-loop` (`dev.sh test`, `shot` одной сеткой, `test --all` в фоне раз на коммит); кадры по чек-листу — агент `visual-reviewer` (sonnet), ориентацию/пропорции/±90° — числом в тесте или владельцу; перед PR `scripts/verify.sh --full`, CI через `scripts/ci-wait.sh` в фоне; в main вливает только владелец; Godot и пакетный Blender — на devbox; `HeadLowPolygon.stl` в репозиторий не класть.

**Why:** владелец попросил Pipeline manager раздать зоны, чтобы параллельные сессии не пересекались.
**How to apply:** перед правкой файла вне своей зоны — не править, а написать владельцу/нужной сессии. См. [[pipeline-manager-session]], [[pico-headset-testing-etiquette]].

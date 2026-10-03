---
paths:
  - "netrun/**"
---

# Godot-часть (`netrun/`)

- Править и проверять — через агента `godot-dev` (`.claude/agents/godot-dev.md`): он работает на devbox в `~/wt-godot`
  (ветка `agent/godot`) с живым редактором Godot AI. Godot на Mac не запускать.
- Тесты — gdUnit4: `netrun/tools/gdunit.sh [res://tests/…]` на devbox (то же, что CI `netrun.yml`). `test_run` плагина не использовать.
- Плагин Godot AI в репозиторий не коммитить (`netrun/addons/godot_ai/` в `.gitignore`); строки плагина в `project.godot`
  (`godot_ai`, `_mcp_game_helper`, `main_run_args`) перед коммитом снять — `scripts/devbox-godot-ai.sh stop`.
- Новое поведение — сначала падающий тест в `netrun/tests/`.

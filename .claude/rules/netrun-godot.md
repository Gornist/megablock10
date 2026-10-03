---
paths:
  - "netrun/**"
---

# Godot-часть (`netrun/`)

- Править и проверять — через агента `godot-dev` (`.claude/agents/godot-dev.md`): он работает на devbox в `~/wt-godot`
  (ветка `agent/godot`) с живым редактором Godot AI. Godot на Mac не запускать.
- Тесты — gdUnit4: `netrun/tools/gdunit.sh [res://tests/…]` на devbox (то же, что CI `netrun.yml`). `test_run` плагина не использовать.
- Плагин Godot AI в репозиторий не коммитить (`netrun/addons/godot_ai/` в `.gitignore`).
  Строки плагина в `project.godot` из коммита убирает хук `pre-commit` на devbox (`scripts/devbox-godot-ai.sh hook`).
- Новое поведение — сначала падающий тест в `netrun/tests/`.

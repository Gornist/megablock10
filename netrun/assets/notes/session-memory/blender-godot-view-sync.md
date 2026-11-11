---
name: blender-godot-view-sync
description: "[Blender, Godot] 07.10.2026: владелец жалуется, что кадры preview Blender и клиент в очках расходятся; согласованный с Godot процесс приёмки вида Сети"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 76802b4d-7652-435f-8353-de5f05a76536
  modified: 2026-10-07T11:11:05.569Z
---

Владелец (07.10.2026): картинки и ассеты у Blender-сессии и Godot «слишком разные», билд в очках сильно отличается от моего preview; нужен процесс синхронизации.

**Why:** мой preview (`~/assets-gd`, `preview_capture.gd`) — отдельная сцена: пол 8×8, колонны по ±4, свои камеры/фон, десктопный mobile-renderer; клиент — `NodeView` с реальной раскладкой, пол 16, Pico (Android). Из-за этого я «принимал» `floor_v3`, которого клиент не рисует.

**How to apply (договорено с Godot 07.10):**
- Приёмка вида окружения — только кадр `dev.sh shot res://tests/foyer_preview.tscn` (NodeView по раскладке foyer, пол 16, реальные материалы) по общим пресетам `netrun/shared/eye_presets.gd` (EyePresets уже в main с PR #95: entry/north/south/vault_w/top*; глаза СИДЯ 1,2 м, fov 90°, не 1,6 м). Мой `~/assets-gd` — только «изолированно, не приёмка», так и подписывать кадры.
- Окончательная приёмка — кадр с очков по тем же пресетам (`pico.sh`), десктоп↔Pico рендер расходится, это можно проверить только на устройстве.
- Парные PR: ассет (Blender) + интеграция (Godot) со ссылкой друг на друга; готово = кадр foyer_preview после слияния обоих.
- Параметры материалов — только в `AssetMaterials` (мой файл), `node_view` их не ставит. Godot добавит gdUnit-тест «NodeView.MODULES/VARIANTS = файлы в assets/models».
- Перед правкой ассета проверять по `node_view.gd`, какой именно файл клиент рисует (пол `floor_slab_16`, колонна `pillar`/`cover`), а не по эксперименту.

См. [[blender-netrun-env-state]], [[blender-session-zone]].

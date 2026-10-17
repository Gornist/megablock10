# Плоская Windows-сборка для тестеров (SOLO)

Раздел «статус» ведёт сессия Godot; разбор и решения владельца — `docs/gamedesign/flat-playtest.md`.

## Статус

- **Экспорт (К6, 17.10):** `netrun/tools/export_flat_win.sh [--smoke]` собирает один exe (`build/netrun-solo.exe`, x86_64, pck внутри, метки `flat,solo`) по пресету «Flat Windows (solo)» из `netrun/export_presets.cfg`. На devbox: ~40 с, 107 МБ. `rcedit` выключен (нужен wine), exe не подписан.
- **Рендерер:** в репозитории `mobile` (Pico), для Windows скрипт собирает из временной копии проекта и подменяет на `gl_compatibility` + включает сжатие S3TC/BPTC; исходный `project.godot` не меняется.
- **Номер сборки:** `BuildInfo.BUILD` (`netrun/shared/build_info.gd`) в репозитории «dev»; скрипт подставляет `<ммдд>-<sha>` в копии и пишет `build/netrun-solo.txt`. Номер пока нигде не показывается игроку — вывести в интерфейсе должна карточка клиента (`solo_stub.gd`/HUD), не К6.
- **CI:** job `solo-export` в `.github/workflows/netrun.yml`: exe собрался (код возврата, размер > 20 МБ, нет ошибок экспорта) + дымовой прогон проекта той же копии (`godot --headless -- --solo --exit-after=8`, строка `[netrun-solo]`, нет ошибок скриптов; `timeout` 124 допустим — выход по `--exit-after` в SOLO пока не реализован). Сам exe в CI не запускается (нет Wine).
- **Не проверено:** запуск exe на Windows (возможности нет): рендер в Compatibility, шейдеры, звук, окно, брандмауэр.

# Карточка EYE — «Пресеты камеры глаз игрока + приёмочный кадр Фойе + тест ассетов»

Рабочая копия/ветка: **`~/Developer/megablock10-wt/gd-eye-presets`**, `agent/gd-eye-presets` (от main). Правила — `rules-godot.md`. Sonnet; один коммит на шаг; зелёные тесты.
Зона записи: `netrun/shared/`, `netrun/tests/`, `docs/netrun-tick-mode.md` не нужен. НЕ трогать `netrun/assets/` (Blender: их ARCHITECTURE.md §18 ссылается на `shared/eye_presets.gd` и `tests/foyer_preview.tscn`, имена не менять).

Зачем: Blender снимает кадры окружения своим отдельным проектом (пол 8, свои камеры) и принимал то, чего нет в клиенте. Теперь приёмка = `netrun/tools/dev.sh shot res://tests/foyer_preview.tscn` по общим пресетам камеры.

## Шаг E1 — `netrun/shared/eye_presets.gd`
`class_name EyePresets`, чистые данные, без сцены. Поза глаз Pico: высота `EYE_HEIGHT = 1.6` (проверь, какая высота головы у клиента — `client/xr_rig.gd`/`rig_test_scene.gd`, возьми оттуда константу, а не выдумывай), `FOV_DEG` (у камеры теста ставилось 50; для Pico вертикальный fov ≈ 90–100 — возьми значение из `xr_rig`/комментариев или оставь 50 только для вида «top»), список пресетов `PRESETS: Dictionary` имя → `{pos: Vector3, look: Vector3, fov: float}`: `entry` (глаза на входе S Фойе, как кадр `eye` сейчас), `north` (смотрит на северные хранилища), `south`, `vault_w` (у западного хранилища лицом к нему, с площадки), плюс обзорные `top`, `top_north`, `top_south` (то, что сейчас захардкожено в foyer_preview.gd). Позиции — через `NodeGrid.center(cell)` и `NodeLayout`, не магические числа, где возможно. Функция `static func get_preset(name) -> Dictionary` и `static func names() -> Array`. Тест `tests/eye_presets_test.gd`: все пресеты имеют pos/look/fov, высота глаз пресетов-«глаз» = EYE_HEIGHT, точки лежат внутри комнаты (`NodeLayout.in_room` или ROOM_MIN/MAX).

## Шаг E2 — `tests/foyer_preview.gd` по пресетам
Заменить захардкоженные камеры на `EyePresets` (кадры: entry, north, south, vault_w, top, top_north, top_south), сохранив поведение (Страж, рамка прицела, out-каталог `--out=`). `dev.sh shot res://tests/foyer_preview.tscn` должен давать одну сетку ≤ 1024 px (проверь запуском; кадр целиком в контекст не лить — только убедись, что сетка получилась и нет ошибок в журнале). Подпись кадра в сетке — имя пресета (если dev.sh это умеет; иначе пропусти).

## Шаг E3 — тест «клиент рисует именно эти ассеты»
`tests/node_assets_files_test.gd`: каждый модуль и вариант из `NodeView.MODULES`/`NodeView.VARIANTS` (`client/node_view.gd:40–48`) → файл `res://assets/models/env/<имя>.glb` существует (путь бери через `NodeAssets.env_path`, как делает клиент; проверь `ResourceLoader.exists`/`FileAccess.file_exists`); плюс «пол в клиенте = floor_slab_16» (VARIANTS.floor == ["floor_slab_16"]) как явная проверка, чтобы подмена не проходила молча. Правило «материалы — только в AssetMaterials»: тест-grep по `client/node_view.gd` на `set_shader_parameter`/`StandardMaterial3D.new` — должен быть пуст; если не пуст — НЕ чини, опиши в отчёте (что и где).

## Сдача
`dev.sh test eye_presets_test node_assets_files_test` + набор по `node_view` (grep имя в tests/) → зелёные; `scripts/zone-check.sh godot`; отчёт ≤ 12 строк (`rules-godot.md`).

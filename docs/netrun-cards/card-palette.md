# Карточка PALETTE — «Клиентские слои берут цвета только из AssetMaterials» (решение владельца 07.10)

Рабочая копия/ветка: **`~/Developer/megablock10-wt/gd-palette`**, `agent/gd-palette` — стоит на ветке PR #135 Blender (`agent/ui-palette`) + влитый свежий main. Правила — `rules-godot.md`. Sonnet, коммит на шаг, зелёные тесты. Зона: `netrun/client/`, `netrun/shared/`, `netrun/tests/`. НЕ править `netrun/assets/` (Blender: AssetMaterials, STYLE.md). Если слоя не хватает — в отчёт, не заводи свой цвет.

## Зачем
Владелец: «внешний вид у Blender и Godot сильно отличается»: клиентские слои красились моими цветами мимо палитры (коричневые клетки, зелёная рамка, оранжевые стрелки). Теперь **цвет и материал любого видимого элемента задаёт Blender**: `AssetMaterials.layer("имя", alpha := -1.0) -> Color`, константы `PAL_CYAN/ICE/THREAT/THREAT_HOT/DIM`, словарь `LAYERS` (см. `netrun/assets/asset_materials.gd`, STYLE.md «Палитра клиентских слоёв»). Янтарь/жёлтый/оранжевый/зелёный/коричневый запрещены (в ветке есть тест палитры).

## Соответствие (от Blender; сверь с реальными именами в asset_materials.gd)
- `client/occupied_floor.gd` COLOR → `cell_occupied_fill` (+ контур клетки `cell_occupied_edge`: если нужен контур, добавь вторым MultiMesh/рамкой, как позволяет геометрия; иначе только заливка).
- `client/ui/teleport_aim.gd` OK/WARN/NO/WAIT/DENIED → `aim_ok/aim_warn/aim_no/aim_wait/aim_denied`.
- `client/ice_view.gd` ALERT_COLOR/EYE_COLOR и `client/tick_floor.gd` STATE_COLORS → `ice_calm/ice_suspect/ice_alert/ice_hunt` (стадии 0..3), `ice_lost`; tick_floor: свет зрения `cell_vision`, FUTURE_TINT → `cell_future`, красная стрелка предзахвата/мигание → `ice_precapture`, след шагов `trail_step` / `trail_dim`, стрелки `arrow`.
- `client/ui/tick_ring.gd` TRACK/FILL/WARN → `tick_track/tick_fill/tick_warn`.
- `client/ui/hud_logic.gd` (зелёный/жёлтый/оранжевый/красный/серый) → `hud_ok/hud_notice/hud_warn/hud_bad/hud_off`; `client/ui/end_screen.gd` → `end_win/end_lose`; Label3D (`client/ui/label3d_sharp.gd` и места создания: teleport_aim, ice_view, offscreen_alert, trace_indicator, tick_floor, rig_test_scene) → `label` / `label_dim`.
- Деки/панели (`client/ui/deck_theme.gd`, mb_*) — отдельная система 2D-интерфейса (DeckTheme), её НЕ трогай, если в карточке нет слоя; опиши в отчёте, что осталось вне палитры.

## Шаги
1. **P1 — аудит:** `grep -rn "Color(" netrun/client netrun/shared` → таблица «файл:строка → слой». Что не покрывается слоем — список в отчёт (не придумывай цвет).
2. **P2 — перевод по файлам** (один коммит на 2–3 файла): константы цветов в клиенте заменить на `AssetMaterials.layer("…")` (читать при создании материала, не каждый кадр; прозрачность — вторым аргументом, если слой её не задаёт). Логику/геометрию не менять. Тесты, которые сверяли старые цвета, — поправь на новые слои (сравнивать с `AssetMaterials.layer(...)`, не с литералом).
3. **P3 — коричневые клетки:** Blender видит `OccupiedFloor` коричневым, хотя код голубой. Найди причину (материал: unshaded/alpha/цветовое пространство; наложение на `TickFloor`/свет зрения; `modulate` вторым слоем; Environment/тональная коррекция) — минимальный тест/наблюдение через `dev.sh shot res://tests/foyer_preview.tscn` (1 кадр, `DEV_CROP` на клетки; картинку в контекст не лить — оцени средний цвет пикселей в области клетки через Pillow на devbox и напиши числом RGB), исправь причину в клиенте, если она в моём коде; если в материале Blender — в отчёт.
4. Проверки: `dev.sh test` по затронутым (occupied_floor_test, teleport_aim*, tick_floor_test, tick_ring*, hud_logic_test, end_screen_test, node_scene_test, палитра Blender) и `dev.sh test --all` в фоне; `scripts/zone-check.sh godot`. Отчёт ≤ 12 строк: что переведено, что осталось вне палитры (нет слоя), причина коричневого.

# План рефактора Сети: умолчания, мёртвый код, облако (черновик на утверждение)

Составлен по итогам замеров на Pico 4 08–12.10.2026 (main 8853470). Это **план, не код**: порядок PR, зоны и приёмка.
Автор свода — сессия Godot; разделы про `netrun/assets/` и `AssetMaterials` согласуются с Blender (отметки «Blender»).
Цифры замеров — в памяти `netrun-msaa-pico-findings-1008` и `docs/netrun-bench.md`; bench = `[render] bench="entry"`, 3×10 с, GPU мс.

## 0. Что решено и измерено (опора плана)

| Факт | Источник |
|---|---|
| База: **MSAA 2× + 90 Гц**, foveation 0, fringe off, scale 1,0 (решение владельца 12.10) | msaa 4 не влезает: V10 msaa 4 = 73 fps / GPU 12,99 мс; msaa 2 = 90 fps / 9,72 мс (бюджет 11,1 мс) |
| MSAA > 0 вместе с фовеацией > 0 → пустой экран на Adreno 650 | замер П6 |
| Облако `cloud=1` по всей сцене: +3,4…3,9 мс при любой плотности (цена a2c — в площади материала) | C1/C2 |
| Облако только на реквизите (C3a, `cloud_lite`) на msaa 2: **+0,26 мс** (89,7 fps); msaa 4 — шумно, ≈ +2 мс | C3a |
| Цена частиц ∝ числу (≈0,07 мс/1000 квадов), размер px не влияет; a2c фиксированно +0,6…0,8 мс; точки хуже квадов | probe sweep |
| Не измерено: `cloud_two_sided=1` (задние грани), VolumeCloud на очках | ждёт очков |

## 1. Инвентарь ручек и режимов

### 1.1 Принято → становится умолчанием в коде (раздел 2)

`[render]`: msaa 2, foveation 0, fringe off, aa none, scale 1,0.
`[assets]` (набор V10, подтверждён владельцем на очках): `rim_top_only=true`, `rim_far_min=0`, `rim_far_start=6`, `rim_far_end=10`,
`rim_min_px=4`, `skirt_top_fade=0.12`, `edge_round=1`, `edge_glow=1.0`, `flat_light=true`, `drift_static=true`, `mist_alpha=0`,
`point_keep=0`, `streak_keep=0`, `tile_glow=3`, `tile_glow_h=1`, `floor_grid=0.35` (уже умолчание).

### 1.2 Тупик → удалить

| Что | Почему | Зона |
|---|---|---|
| `[render] scale`, `aa=fxaa`, `foveation_dynamic` | `scale` 1,25 не держит 90 Гц и лесенку не лечит; FXAA снимает фовеацию | Godot |
| `[render] fringe` и вся цепочка fringe: `fringe.gdshader`, `FRINGE_LAYERS`, `fringe_on/alpha/px`, `--nofringe` в `preview_capture.gd`, next_pass у pillar/exit/vault | 3 аддитивных слоя; при MSAA — «бензопила»; off принят | Godot (ключ, `apply_fringe`) + Blender (материалы) |
| Штрихи окружения: `streaks.gdshader` для tier≠"", `streak_*`, `halo`, `halo_width`, `halo_far`, `min_px_streaks`, генерация штрихов в `src/*.py` | `streak_keep=0` принят: не рисуются | Blender |
| Точки окружения: `point_keep`, `min_px_points`; генерация точек среды | `point_keep=0` принят; точки существ/аватаров остаются | Blender |
| Дымка/край комнаты: `*_mist`, `haze.gdshader`, `mist_alpha` | `mist_alpha=0`: меши скрыты, но грузятся | Blender |
| `edge_soft` (+ `edge_soft.gdshaderinc`), `vertex_clip`, `albedo_clip` | пробовали (V7–V9a), не приняты | Blender |
| `plate_flat` (единственный `discard` в solid_dark), `edge_uneven`, `edge_drift`, `flat_light`, `drift_static` | приняты значения «ровно и статично» → константы, шум и `TIME` из шейдера убираем | Blender |
| Эксперименты `*_glass`, `beacon_halo`, `dust_streaks`-параметры в `ROLE_PARAMS`, если не используются в Фойе/Сети | проверить grep по `res://assets/models` и сценам; неиспользуемое — удалить | Blender |
| msaa 4 как «база» в доках/стенде; варианты стенда V6–V13, P6*, A/B/K, base/top/flat/far/skirt/all/soft/wide | история остаётся в памяти и коммитах | Godot |

### 1.3 Остаётся инструментом (по умолчанию выкл., в документации «стенд»)

`[render] perf` (on|diag), `bench`, `probe` (+`sweep`), `volumetric`; `XrDiag`, `BenchRun`, `LoadProbe`, `ProbeSweep`.

### 1.4 Эксперимент, ждёт решения владельца (НЕ удалять до решения)

`cloud`, `cloud_lite`, `cloud_far/floor/ceiling`, `cloud_two_sided`, `cloud_edge_mix`, `dust`, `dust_cell`, `dust_density` — вид облака
на очках; `layers` on|behind (bench шёл на `on`; `behind` — руки поверх панели); `tile_glow` (клин у края комнаты не разобран).

## 2. Умолчания в коде вместо конфигов стенда

Цель: **чистый main без `netrun.cfg` даёт принятый вид** (кадр клиента == кадр Blender; раньше «две разные игры» из-за стенд-конфигов).

| Где | Что меняется |
|---|---|
| `RenderConfig` (Godot) | `MSAA_DEFAULT=2`, `FOVEATION_DEFAULT=0`, fringe — константа off (ключ удаляем); **защита**: msaa>0 и foveation>0 → foveation принудительно 0 + `warnings` (иначе пустой экран); удалить `scale`, `aa`, `foveation_dynamic`; устаревшие ключи в старых cfg на очках → строка в `warnings`, не ошибка |
| `AssetMaterials.KNOBS` (Blender) | значения 1.1 как умолчания; удалённые ручки (1.2) убираются; `tune_from_config` по-прежнему игнорирует неизвестные (только `push_warning`), поэтому старые `[assets]` в cfg очков безопасны |
| Контракт Godot↔Blender | `RenderConfig.apply_fringe` → переименовать в `apply_assets()`: вызывает `AssetMaterials.tune_from_config(cf)` (имя метода — зона Blender, контракт не меняется) |
| Тесты | `render_config_test`, `assets_*`: ожидаемые умолчания обновляются в том же PR, что и значения |
| Provision (`tools/pico.sh provision`) | не пишет `[render]`/`[assets]` кроме адреса и токена |

## 3. Мёртвый код и шейдерные ветки (цель — фрагмент дешевле, бюджет 11,1 мс)

1. **solid_dark** (127 строк): убрать `edge_soft`/`vertex_clip`/`albedo_clip`, `vnoise`+`TIME` (после `flat_light`/`drift_static`
   рёбра ровные — константа), `discard` (plate_flat). Без `discard` у шейдера появляется шанс на early-Z/LRZ на Adreno —
   **гипотеза, проверить bench**. Оставить то, что режет перерисовку: `rim_far_*`, `rim_min_px`, `rim_top_only`, `edge_round`.
2. **cloud_dark / cloud_dark_2s**: если облако принимается — `lite` становится единственным путём (хэш без sin, 2D-пятна), ветка 3D-шума
   и `if (lite)` уходят; два файла остаются (cull нельзя переключить uniform'ом) и делят `cloud_dark.gdshaderinc`.
3. **volume_dust.gdshaderinc**: одна функция узора на `solid_dark(dust)`, `cloud_dark`; если `cloud` принят — `dust` в solid_dark
   удаляется (остаётся один путь).
4. Шейдеры: `streaks`, `haze`, `fringe`, `edge_soft.gdshaderinc` — удалить целиком после снятия ссылок; `points` оставить только для
   существ/аватаров; `skirt` (вуаль + завеса `tile_glow`) оставить.
5. glb: убрать меши `*_mist`, штрихи и точки окружения из экспорта (`src/*.py`, `validate.py`, `glbinfo.py`) — размер APK и время загрузки.

Ожидание по мс **не обещаю**: приёмка — «не хуже базы V10 msaa 2 (9,72 мс)»; выигрыш — запас под `cloud_two_sided` (≈ +0,5 мс) и VolumeCloud.

## 4. Структура для перехода на облако

| Слой | Где живёт | Чей | Для чего |
|---|---|---|---|
| (А) Поверхностное облако | `assets/shaders/cloud_dark*.gdshader[inc]` + `volume_dust.gdshaderinc`, ручки в `AssetMaterials` | Blender | статичное окружение (реквизит; пол/потолок/дальние — solid_dark, `cloud_far/floor/ceiling=0`) |
| (Б) Объём частицами | `client/volume_cloud.gd`, `client/volume_registry.gd` (MultiMesh, LOD по расстоянию), `particles_body.gdshaderinc` | Godot (код), Blender (шейдер) | объекты Сети: хранилища, выход, порталы, шард, ICE-голограмма; бюджет ≤ 12k blend-квадов на вид, `volume_budget_ms` |
| Данные | `*.points` рядом с моделью (`VolumeRegistry.points_path`), формат 7 float32 | Blender (запекание), Godot (загрузка) | один формат, одна запись на модель |

Правила без дублирования: **цвет и яркость облака только из `AssetMaterials`** (VolumeCloud берёт цвет оттуда); узор поверхностного облака
— одна функция в `volume_dust.gdshaderinc`; режим точек (PRIMITIVE_POINTS) не использовать (замер: хуже квадов); `LoadProbe`/`ProbeSweep`
остаются единственной синтетикой. Импостор дальних пластов (кубмапа SubViewport) — отдельный шаг после R6, не в этом рефакторе.

## 5. stand_cfg.sh и стенд

Сейчас `~/pico-cfg/stand_cfg.sh` (180 строк, ≈30 вариантов) живёт на devbox вне git. План: положить в репозиторий как
`netrun/tools/pico_stand.sh` (зона Godot), оставить **5 пресетов**: `base` (пустой [assets] — чистые умолчания),
`bench` (msaa 2, bench=entry), `cloud-props` (C3a), `cloud-props-2s` (C3a + two_sided), `probe-sweep`; плюс аргументы
`msaa layers perf bench probe`. Варианты V6–V13/P6*/C1/C2 и т.п. — удалить (история в памяти). Запуск игры/сервера
(`watch_awake.sh`, `srv_p2.sh`, `build.sh`) — в `docs/netrun-devbox.md` одним разделом, этикет очков без изменений.

## 6. Порядок PR (маленькие шаги, у каждого приёмка)

| # | PR | Зона | Приёмка |
|---|---|---|---|
| R0 | этот документ | Godot | утверждение владельца |
| R1 | `RenderConfig`: msaa 2, foveation 0, защита msaa+foveation, удаление `scale/aa/foveation_dynamic/fringe`, `apply_assets()` | Godot | `dev.sh test --all`; на очках **без cfg** bench ≈ 90 fps / GPU ≈ 9,7 мс |
| R2 | `AssetMaterials.KNOBS`: умолчания V10, пересъёмка `foyer_preview`, обновление `ARCHITECTURE.md`/`STYLE.md` | Blender | `assets_*` зелёные; кадр клиента без cfg == кадр V10 по cfg (попиксельная разница ≈ 0, `visual-reviewer`) |
| R3a | убрать fringe-цепочку, halo, edge_soft, vertex/albedo_clip | Blender | тесты; кадр не изменился; bench msaa 2 не хуже |
| R3b | убрать штрихи/точки/дымку окружения (шейдеры, `src/*.py`, glb) | Blender | тесты; кадр; размер APK ↓ |
| R3c | solid_dark: шум/`TIME`/`discard` → константы | Blender | кадр; **bench msaa 2 ≤ 9,72 мс** (очки, владелец) |
| R4 | `netrun/tools/pico_stand.sh` + `docs/netrun-devbox.md`, удаление старых вариантов | Godot | прогон пресета `bench` на очках |
| R5 | решение по облаку: `cloud=1` (C3a) по умолчанию или откат; замер two_sided на msaa 2; при дороговизне — прототип «объём в коробке» | Blender (+замер Godot) | очки, bench msaa 2 ≤ +1 мс к базе; вид принят владельцем |
| R6 | П4 VolumeCloud: хранилище, выход, порталы, шард; `volume_budget_ms` | Godot (+Blender шейдер/.points) | тесты; кадр; очки: bench + probe |

Порядок: R1 ∥ R2 (разные файлы) → R3a → R3b → R3c → R4; R5 после решения владельца по виду (может идти параллельно R3); R6 — после R5.
Каждый PR — один слой, парные (R1+R2) сливаются подряд; сосед предупреждается сообщением (контракт `apply_assets`/`tune_from_config`).

## 7. Риски и откат

| Риск | Как проявится | Откат / защита |
|---|---|---|
| Новые умолчания (R1/R2) меняют вид «чистого» main у тех, кто без cfg | другой кадр на плоском клиенте/превью | `[assets]`/`[render]` в cfg перекрывают умолчания; revert одного PR |
| Старые cfg на очках содержат удалённые ключи | предупреждения в журнале | неизвестный ключ — warning, не падение (проверено: `RenderConfig`, `tune_from_config`) |
| Удаление шума/`discard` меняет рёбра или цену кадра | кадр отличается / bench хуже | попиксельная сверка до/после; если хуже — revert R3c (шейдер самостоятельный) |
| `src/*.py`/`validate.py`/`assets_*` ссылаются на удаляемые шейдеры | красные `assets_*` | шейдер и ссылки удаляются в одном PR (зона Blender целиком) |
| Удалили то, что владелец ещё хочет (cloud/dust, `tile_glow`) | потеря вида | раздел 1.4 не трогаем до решения; кандидаты на удаление держим в `git` (тег/ветка) |
| MSAA 2 даёт «лесенку» (владелец: заметна, терпима) | жалобы на вид | ручка `msaa=4` остаётся для сравнения; потолок 90 Гц обсуждается отдельно |
| Параллельные PR Godot/Blender в одном файле | конфликты | зоны разведены: `render_config.gd`/`proto_client.gd` — Godot; `asset_materials.gd`/`shaders/`/`src/` — Blender; общих файлов нет |

## 8. Вопросы владельцу

1. `layers`: по умолчанию `on` (как в bench) или `behind` (руки и луч поверх панели)?
2. `tile_glow=3`: оставить или `0` (клин у края комнаты не разобран)?
3. Облако: принимаем C3a (реквизит) как вид? `cloud_two_sided=1` — мерить сразу (цена ≈ +0,5 мс)?
4. Ключ `scale` удалить совсем или оставить как инструмент (рекомендую удалить)?

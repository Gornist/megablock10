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
`[assets]` (набор V10, подтверждён владельцем на очках): `rim_top_only=true`, `rim_far_min=0`, `rim_far_start=6` (замерялось в V10 именно 6,0; Blender в сообщении назвал 8 — сверить), `rim_far_end=10`,
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
| `dust` (пыль на solid_dark; вытеснена `cloud_dark`), `uv_rim`, ветки `uv_rim`/`cell_*` в `glass.gdshader` | `dust_cell`/`dust_density` остаются как ручки облака | Blender |
| Экспериментальные модели: `floor_v1…v4_8/16`, `floor_glass_8/16`, `floor_clear`, `floor_slab_8`, `room_edge_8`, `room_moat_8/16` (15 из 79 .glb), `src/floor_variants.py`, `room_moat.py`, ключи `--floorv` в `preview_capture.gd` | клиент их не грузит; одним PR после grep по клиенту | Blender |
| msaa 4 как «база» в доках/стенде; варианты стенда V6–V13, P6*, A/B/K, base/top/flat/far/skirt/all/soft/wide | история остаётся в памяти и коммитах | Godot |

### 1.3 Остаётся инструментом (по умолчанию выкл., в документации «стенд»)

`[render] perf` (on|diag), `bench`, `probe` (+`sweep`), `volumetric`; `XrDiag`, `BenchRun`, `LoadProbe`, `ProbeSweep`.

### 1.4 Эксперимент, ждёт решения владельца (НЕ удалять до решения)

`cloud`, `cloud_far/floor/ceiling`, `cloud_two_sided`, `cloud_edge_mix`, `dust_cell`, `dust_density` (`cloud_lite` — сразу константа, `dust` — удаляется) — вид облака
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

1. **solid_dark** (127 → ≈50 строк; оценка Blender, мс не измерены): убрать `uv_rim` (нужен только floor_v2/v4), `dust`+include, varyings `v_nw/v_uv/v_hs`,  `edge_soft`/`vertex_clip`/`albedo_clip`, `vnoise`+`TIME` (после `flat_light`/`drift_static`
   рёбра ровные — константа), `discard` (plate_flat). Без `discard` у шейдера появляется шанс на early-Z/LRZ на Adreno —
   **гипотеза, проверить bench**. Оставить то, что режет перерисовку: `rim_far_*`, `rim_min_px`, `rim_top_only`, `edge_round`.
2. **cloud_dark / cloud_dark_2s**: если облако принимается — `lite` становится единственным путём (хэш без sin, 2D-пятна), ветка 3D-шума
   и `if (lite)` уходят; два файла остаются (cull нельзя переключить uniform'ом) и делят `cloud_dark.gdshaderinc`.
3. **volume_dust.gdshaderinc → volume_cloud.gdshaderinc**: без `volume_dust_color`, один путь (`lite`); `dust` в solid_dark удаляется в любом случае.
   Честно (Blender): цена cloud сидит в площади a2c, а не в ALU — ждём читаемость и меньше вариантов, не мс.
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

**Генератор `.points` (`src/points.py`) пока не писать** (Blender): C3a закрывает реквизит гранями-облаком; цена частиц ∝ числу, а a2c фиксированна — отдельное облако на малый объект её только добавит. Писать, если владелец одобрит вид (Б) для конкретных объектов (хранилище ≈1,5k, выход ≈1k, портал ≈0,8k, шард ≈0,3k): площадное сэмплирование + вес ребра, seed фиксирован, `validate`: размер кратен записи, число ≤ бюджета, AABB в габарите, без NaN, строка в MANIFEST. `VolumeCloud` до этого остаётся в main без потребителей.

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
| G1 | `RenderConfig`: msaa 2, foveation 0, защита msaa+foveation, удаление `scale/aa/foveation_dynamic/fringe`, `apply_fringe` → `apply_assets()` | Godot | `dev.sh test --all`; на очках **без cfg** bench ≈ 90 fps / GPU ≈ 9,7 мс; превью/`dev.sh shot` выставляют msaa 2 явно |
| B1 | ручки + шейдеры без пересборки моделей: умолчания V10 в `KNOBS`, удаление fringe/halo/edge_soft/clip/noise/plate_flat/dust/uv_rim, solid_dark ≈50 строк | Blender | `assets_*` зелёные; `foyer_preview` до/после — тот же кадр (`visual-reviewer`); **очки: bench msaa 2 ≤ 9,72 мс** |
| B2 | удаление объектов окружения (штрихи, точки, `*_mist`) и 15 экспериментальных .glb, пересборка на devbox (бинарные .glb конфликтны — в поезд одним) | Blender | тесты; кадр; bench до/после (число draw calls); размер APK ↓ |
| G2 | `netrun/tools/pico_stand.sh` + `docs/netrun-devbox.md`, удаление старых вариантов | Godot | прогон пресета `bench` на очках |
| B3 | чистка cloud после решения владельца по C3a: `lite` — константа, `volume_dust` → `volume_cloud.gdshaderinc`, замер `two_sided` на msaa 2; при дороговизне — прототип «объём в коробке» | Blender (+замер Godot) | очки, bench msaa 2 ≤ +1 мс к базе; вид принят владельцем |
| B4 | документы: `ARCHITECTURE.md` §20, §12 → «Антипаттерны», §21 → «Вид Сети v1», бюджеты §9; `STYLE.md` п.7–8 | Blender | ревью |
| G3 | П4 VolumeCloud для хранилища/выхода/портала/шарда, `volume_budget_ms` — **только если владелец одобрит вид (Б)**; тогда Blender пишет `src/points.py` | Godot (+Blender) | тесты; кадр; очки: bench + probe |

Порядок: G1 ∥ B1 (разные файлы; B1 не требует пересборки моделей, но APK пересобирается — ручки вшиты) → B2 → G2 → B3 (после
решения по облаку, может идти параллельно B2) → B4; G3 — после B3 и только по решению. Каждый PR — один слой; G1 и B1 сливаются
подряд, сосед предупреждается сообщением (контракт `apply_assets` ↔ `tune_from_config`, «читающая сторона первой»).

## 7. Риски и откат

| Риск | Как проявится | Откат / защита |
|---|---|---|
| Новые умолчания (R1/R2) меняют вид «чистого» main у тех, кто без cfg | другой кадр на плоском клиенте/превью | `[assets]`/`[render]` в cfg перекрывают умолчания; revert одного PR |
| Старые cfg на очках содержат удалённые ключи | предупреждения в журнале | неизвестный ключ — warning, не падение (проверено: `RenderConfig`, `tune_from_config`) |
| Удаление шума/`discard` меняет рёбра или цену кадра | кадр отличается / bench хуже | попиксельная сверка до/после; если хуже — revert R3c (шейдер самостоятельный) |
| `src/*.py`/`validate.py`/`assets_*` ссылаются на удаляемые шейдеры | красные `assets_*` | шейдер и ссылки удаляются в одном PR (зона Blender целиком) |
| Удалили то, что владелец ещё хочет (cloud/dust, `tile_glow`) | потеря вида | раздел 1.4 не трогаем до решения; кандидаты на удаление держим в `git` (тег/ветка) |
| MSAA 2 даёт «лесенку» (владелец: заметна, терпима) | жалобы на вид | ручка `msaa=4` остаётся для сравнения; потолок 90 Гц обсуждается отдельно |
| Клиент без MSAA (редактор, `msaa=0`) получает лесенку без fringe | кадр хуже на превью | `msaa=0` остаётся допустимым значением как инструмент, но вид принимаем только на msaa 2; превью и `dev.sh shot` ставят msaa 2 явно |
| Удаление штрихов из .glb меняет число draw calls | bench иначе | bench msaa 2 до и после B2 |
| Ключи в `stand_cfg.sh`/cfg очков (`fringe_px`, `streak_*`…) | предупреждения | ключи удалённых ручек игнорируются; ключи оставшихся (`dust_cell`, `cloud*`…) не переименовываем |
| Параллельные PR Godot/Blender в одном файле | конфликты | зоны разведены: `render_config.gd`/`proto_client.gd` — Godot; `asset_materials.gd`/`shaders/`/`src/` — Blender; общих файлов нет |

## 8. Вопросы владельцу

1. `layers`: по умолчанию `on` (как в bench) или `behind` (руки и луч поверх панели)?
2. `tile_glow=3`: оставить или `0` (клин у края комнаты не разобран)?
3. Облако: принимаем C3a (реквизит) как вид? `cloud_two_sided=1` — мерить сразу (цена ≈ +0,5 мс)?
4. Ключ `scale` удалить совсем или оставить как инструмент (рекомендую удалить)?
5. Генератор `.points` и облако (Б) для хранилища/выхода/портала/шарда — писать или остаёмся на гранях-облаке (А) для реквизита?

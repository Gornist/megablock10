# Ревью области «Вид Сети» (netrun/assets, AssetMaterials, шейдеры, тесты assets_*), аудит 17.10.2026

## Сводка области

- Размер: `asset_materials.gd` 612 строк, `preview_capture.gd` 522, 16 файлов `src/*.py` (≈3,3 тыс. строк, самые крупные `lib.py` 464, `points.py` 448, `props.py` 438), 16 шейдеров/include (≈913 строк), 13 `preview_*.gd` (1478 строк), тесты `assets_*` — 1710 строк, из них `assets_models_test.gd` 1297 (167 числовых утверждений).
- Архитектура ясная: Blender-пайплайн (`src/*.py`) пишет `.glb` с материалами-ролями, `AssetMaterials.apply()` подменяет их шейдерами по имени роли и меша, клиент берёт цвета из `LAYERS`. Недавние чистки (B1–B3, `fringe`, `halo`, `edge_soft`, `volume_dust`, 15 экспериментальных моделей) сделаны добросовестно: удалённые ручки и файлы закреплены тестом-надгробием.
- Главная остаточная проблема: B2/B3 убрали объекты окружения, но не убрали механизм под них. Ручки `streak_*`/`point_keep`, их ветки в `streaks`/`points`, `set_corruption` и т. п. работают на единственном потребителе (`exit_frame`) или вообще без читателя в игре.
- `AssetMaterials` — God-объект (палитра, ручки, `apply()` на 102 строки со строковой диспетчеризацией по имени меша, тревога, дыхание облака, луч, ожог) и держит три статических изменяемых реестра.
- Шейдеры без общего include: `recolor()` байт-в-байт скопирован в 6 файлах, блок «corruption» — в 3.
- Тесты: ловят структуру (файлы импортируются, uniform'ы на месте, ручка доходит до материала), но не вид; зависят от числовых габаритов закоммиченных `.glb`; много тестов-надгробий. Python-генератор без юнит-тестов (нужен `bpy`), защита — `validate.py` в CI (`netrun.yml:39`).
- Расхождение «preview ↔ клиент» (класс сбоя 5) остаётся по двум видимым линиям: цвет фона и способ склейки MultiMesh (находки 1 и 8).

## Находки

### 1. Фон спокойного узла в клиенте не равен `VOID_BG`, о котором говорят STYLE/ARCHITECTURE и на котором принимали вид
- Где: `netrun/client/rig_test_scene.gd:119` (`CALM_BG := Color(0.02, 0.024, 0.03)`) и `:134`; `netrun/assets/asset_materials.gd:298` (`VOID_BG = (0, 0.10, 0.13)`); `netrun/assets/ARCHITECTURE.md:527` («клиент ставит `Environment.background_color = AssetMaterials.VOID_BG`»), `STYLE.md:62` (п. 11).
- Что: `VOID_BG` в клиенте не читает никто (grep `VOID_BG` по `client|shared` — 0 совпадений); клиент красит спокойный фон почти чёрным `CALM_BG` и прибавляет к нему лишь разницу `alarm_background(level) − alarm_background(0)`. Все 11 Blender-превью (`preview_*.gd`) стоят на `VOID_BG`/`alarm_background(0)`, то есть показывают бирюзовую дымку, которой в игре нет.
- Почему мешает: ровно тот класс «приёмка по своему стенду» из досье §5 п. 5 (07.10 «две разные игры»). Решение владельца 07.10 «пустота — тёмная бирюза» в клиенте не исполнено, а превью это скрывает. Тест `alarm_view_client_test.gd` закрепляет `CALM_BG` (`assert alarm_bg(4).g < 0.024`).
- Выгода: высокая, если расхождение случайное: возвращает единый вид; если намеренное (слои `behind`), нужно снять противоречие в документах.
- Риск (дверь/радиус): ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА (какой фон правильный), затем 2 файла клиента (Godot-зона) + `alarm_view_client_test`, цвет — константа Blender. Инварианты денег не затронуты. Смена фона влияет на яркость кадра на Pico.
- Размер: S
- Проверить чем: `netrun/tools/dev.sh shot res://tests/foyer_preview.tscn` против кадра с очков; `dev.sh test alarm_view_client_test`.

### 2. Ручки и ветки шейдеров окружения, которым остался один потребитель — скрытая рамка `exit_frame`
- Где: `asset_materials.gd:162-167` (`streak_far_*`, `streak_keep`, `streak_len`, `streak_px_fade`, `point_keep`), применение `:429-444` и `:422-424`; шейдерные uniform'ы `streaks.gdshader:59-61` (`keep_frac`, `len_scale`, `px_fade`), `:44-46` (`far_dim_*`), `points.gdshader` (`keep_frac`); `src/exit_frame.py:51,62`.
- Что: после B2 единственная env-модель с `streaks`/`points` — `exit_frame` (по `models/MANIFEST.md:32`: 18 точек, 29 штрихов; все остальные env — 0/0). При умолчаниях `streak_keep=0`/`point_keep=0` они не рисуются: столбы-занавесы и точки порога спрятаны ручкой, а docstring `exit_frame.py:41` описывает их как видимые. Семь ручек, три ветки вершинного шейдера и два теста (`assets_models_test.gd:686-730`) обслуживают объекты, которых игрок не видит.
- Почему мешает: мёртвая стоимость на каждом вершинном шейдере штрихов существ (ветки по `keep_frac`/`px_fade` исполняются у всех штрихов, пусть и по uniform), путаница «что рисуется», лишние тесты. Пересказ «ручка владельца» скрывает, что убирать надо сами меши.
- Выгода: средняя (меньше кода и тестов, чуть дешевле штрихи существ).
- Риск (дверь/радиус): ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА по виду рамки выхода (оставить столбы/точки видимыми или убрать из модели); пересборка `exit_frame.glb` на devbox (бинарные `.glb` конфликтуют при слиянии, см. refactor-plan B2), затрагивает `exit_frame.py`, `asset_materials.gd`, 2 шейдера, 2 теста.
- Размер: M
- Проверить чем: `dev.sh test assets_models_test`; кадр `exit_view` стенда `preview_capture`.

### 3. `AssetMaterials.set_corruption`/`set_distance_fade` и «corruption» в трёх шейдерах без читателя в игре
- Где: `asset_materials.gd:481-504` (обе функции); вызовы только в `preview_capture.gd:513,515,520`; шейдеры `shell_soft.gdshader:25-44`, `points.gdshader:38-57`, `streaks.gdshader:67-86` (`corrupt_k`, `cell_hash`, `corrupt_mask`, `corrupt_hole`, uniform'ы `corrupt_pos|radius|color`).
- Что: в `client|shared|server` слов `corrupt`/`set_corruption`/`set_distance_fade` нет (проверено grep); тестов на них 0. Живёт один кадр стенда `red_probe` (`preview_capture.gd:117`) и ноль-значения во всех остальных `"corrupt": [Vector3.ZERO, 0.0]`. «Красный шрам» заменён `set_alarm`/`set_alarm_focus`.
- Почему мешает: ≈60 строк GLSL, продублированных трижды, `sin`-хеш в каждом фрагменте точек и штрихов существ (при `corrupt_radius=0` ветка дёшева, но код и uniform'ы остаются), два публичных метода без контракта.
- Выгода: средняя.
- Риск (дверь/радиус): низкий; зона одна (Blender): 3 шейдера, `asset_materials.gd`, `preview_capture.gd`. Нужно подтвердить, что `set_distance_fade` не нужен очкам (fade_start/end по умолчанию 60/90 заданы и в шейдерах).
- Размер: S
- Проверить чем: `dev.sh test assets_models_test`, `grep -rn "corrupt" netrun` = 0, кадры `preview_capture` без `red_probe`.

### 4. `apply()` — 102 строки со строковой диспетчеризацией по имени меша, плюс God-объект `AssetMaterials`
- Где: `asset_materials.gd:379-480` (`apply`), строковые условия на `:391,:396,:413,:445,:450,:452,:456,:460`; в файле же палитра (`:44-132`), ручки (`:139-177`), тревога (`:285-361`), дыхание/касание облака (`:543-600`), луч (`:520`), ожог (`:112`).
- Что: одна функция знает имена мешей из Python (`*_skirt`, `pillar_block`, `pillar_base`, `exit_bar*`, `*_fan`, `*_beam*`, `beacon_halo`, `beacon_beam`, `*_mid`, `*_hang`, `floor_slab_under`, `slab`) и по ним выбирает шейдер, параметры и облако. Контракт «имя меша» нигде не описан таблицей, тест на каждое имя свой.
- Почему мешает: любой новый вид (П6-6 (в) логово, #424 облако) дописывает ещё `if` в эту функцию: регрессия «ручка не дошла до материала» (`tile_glow` в `assets_models_test.gd:935`, `floor_density`) лечится отдельным тестом на каждую; конфликты слияний в одном файле между сессиями Blender.
- Выгода: средняя.
- Риск (дверь/радиус): 20+ читающих файлов клиента (`set_alarm`, `layer`, `set_beam`, …), публичный API должен остаться; риск рассинхрона вида с Pico, поэтому каждый шаг по кадру клиента.
- Размер: M (таблица «имя меша → правило» `MESH_RULES`, затем вынос тревоги/облака в `AlarmView`/`CloudAnimation`; `class_name AssetMaterials` оставить фасадом)
- Проверить чем: `dev.sh test assets_models_test`, `dev.sh test --all`, сравнение кадров `foyer_preview` до/после.

### 5. Копипаста в шейдерах: `recolor()` в 6 файлах, `dist_fade`/corruption в 3
- Где: `recolor`: `beacon_halo.gdshader:36`, `skirt.gdshader:35`, `solid_dark.gdshader:36`, `shell_soft.gdshader:39`, `points.gdshader:52`, `streaks.gdshader:81` (md5 тела совпадает у всех шести); `dist_fade`: `shell_soft:44`, `points:57`, `streaks:86`; блок `corrupt_k..corrupt_hole`: `shell_soft:25`, `points:38`, `streaks:67` (md5 совпадает); `grid_tex` с `grid_alpha`: `solid_dark.gdshader:18-20,70-73` и `cloud_dark.gdshaderinc:9-11,29-31`.
- Что: общие функции перекраски тиром, затухания по дистанции и сетки скопированы в каждый шейдер; `.gdshaderinc` уже есть и применяется (`alarm_focus`, `breath_touch`, `volume_cloud`).
- Почему мешает: правка перекраски (тир HARD/NIGHTMARE) требует шести одинаковых правок; уже случился расход «одна функция в 3 местах» при добавлении `lattice`/`min_px`.
- Выгода: средняя.
- Риск (дверь/радиус): низкий по логике, но Godot компилирует include на лету; нужен кадр «тир ≠ BASE» на очках (перекраска). Затрагивает 6 шейдеров + новый `tint_common.gdshaderinc`.
- Размер: S
- Проверить чем: `dev.sh test assets_models_test` (`test_tier_is_a_material_tint`), кадр `preview_capture` по тирам.

### 6. Около 44 uniform'ов шейдеров не имеют ни одного setter'а в .gd
- Где: `streaks.gdshader:6-8,10,14-15,17-19` (`bead_freq`, `bead_speed`, `edge_sharp`, `halo_sharp`, `pulse_speed`, `pulse_scale`, `sway_speed`, `shimmer`, `shimmer_speed`), `points.gdshader:10-14` (`twinkle`, `twinkle_speed`, `wave`, `size_wave`, `wave_speed`, `wave_scale`), `volume_cloud.gdshaderinc:19-26` (`dust_fps`, `dust_far_*`, `dust_patch*`, `dust_cover_avg`, `dust_edge_gain`), `particles_body.gdshaderinc` (`wave_*`, `spark_*`, `glitch_*`), `beam.gdshader` (`on_wide`, `off_level`, `on_boost`), `shell_soft`, `skirt`, `corrupt_color` ×3, `grid_origin` ×2.
- Что: найдено скриптом: `grep -w` имя uniform в `client|shared|assets|tests|tools` на `set_shader_parameter`/строковое имя — 0. Это константы под видом uniform'ов (часть «ручек на будущее», заявленных на 08–12.10).
- Почему мешает: на мобильном GPU (Pico) uniform'ы берут место в UBO и не складываются компилятором; читать шейдер труднее, а ручки, которых нет в `KNOBS`, никто не может крутить. Часть из них явно пережила тупики (`halo_sharp`, `grid_origin`).
- Выгода: низкая–средняя (аккуратность и немного GPU).
- Риск (дверь/радиус): низкий; `grid_origin` и `corrupt_*` могут использоваться снаружи через `AssetMaterials.set_param` (из `avatar_view.gd`, `preview_*`), проверять по каждому. 6–8 шейдерных файлов.
- Размер: S
- Проверить чем: `dev.sh test assets_models_test assets_cloud_breath_test`; кадры `preview_capture`.

### 7. Дублированные цвета и правила вне `AssetMaterials` и без сверки с Python-палитрой
- Где: `client/obstacle_body.gd:15-16` (`CYAN := Color("18e6ff")`, `VOID := Color("02050a")`); `asset_materials.gd:285-289` (`TIER_TINT` повторяет литералы `PAL_CYAN` и т. д. вместо ссылки); `client/hand_view.gd:29-30` (`COLOR_HAND`, `COLOR_SPARK`, свой голубой (0.18,0.72,0.85), которого нет в палитре), `client/head_cloud.gd:14`; `src/lib.py:34-43` (`HEX` — отдельная копия палитры Blender).
- Что: правило проекта (CLAUDE.md, зона Blender): палитра и материалы всех видимых элементов — константы `AssetMaterials`. На деле: `lib.py:HEX`, `asset_materials.gd:PAL_*`/`TIER_TINT`, `obstacle_body.gd:CYAN/VOID` — три независимые копии `#18e6ff`/`#02050a`; сверочного теста нет (grep `HEX` в `netrun/tests` — только комментарий).
- Почему мешает: смена оттенка требует трёх правок; «кадр клиента ≠ превью Blender» (класс 5) уже был из-за цветов. `obstacle_body.light()` повторяет `lit()` из `env.py` (это зеркало защищено `assets_obstacle_body_test.gd`, а цвета — нет).
- Выгода: средняя.
- Риск (дверь/радиус): ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА лишь для `COLOR_HAND` (это принятый вид рук); остальное механика. Файлы: `obstacle_body.gd` (граница с Godot-зоной, там делает Blender по `STYLE.md`), `asset_materials.gd`, новый тест сверки `lib.HEX` ↔ `PAL_*` (парсинг `lib.py` из GDScript-теста).
- Размер: S
- Проверить чем: `dev.sh test assets_obstacle_body_test assets_models_test`.

### 8. Два механизма склейки MultiMesh: `AssetBatch` (стенд) и `node_view._add_multi` (клиент)
- Где: `netrun/assets/asset_batch.gd` (69 строк; единственный читатель `preview_capture.gd:292,303`), `netrun/client/node_view.gd:449` (`_add_multi`), `netrun/client/node_assets.gd:92` (`mesh_parts`).
- Что: стенд замеряет число draw call через свою склейку, клиент склеивает другой кодом. ARCHITECTURE §9 (`:340`) ссылается на замеры стенда как на бюджет.
- Почему мешает: класс сбоя 5 («приёмка по своему стенду»): бюджет вызовов отрисовки из `preview_capture` не обязан совпадать с очками; правки `mesh_parts` не отражаются на стенде.
- Выгода: средняя.
- Риск (дверь/радиус): `node_view.gd` — зона Godot/Blender (окружение — Godot); сменить стенд на вызов `NodeAssets.mesh_parts` — правка только `preview_capture.gd`; удалить `AssetBatch`.
- Размер: S
- Проверить чем: `dev.sh test`, сравнение числа вызовов (`tools/framestats.py`) стенда и клиента на одной сцене.

### 9. Раздувание кода и мёртвые вычисления в Python-генераторе окружения
- Где: `src/env.py:254,291` (`streaks += _slab_streaks(...)` считается ради датчика `rng`, результат нигде не используется; комментарий на `:258`), `src/floor_slab.py:63` (то же, «вывод не нужен»), `env.py:154-189` (`_slab_streaks` 35 строк), `src/props.py:13` (`from env import curtain, _slab_streaks` — приватная функция между модулями); комментарии о `fringe.gdshader` в `env.py:357`, `exit_frame.py:53`, `props.py:182`; функции длиннее 80 строк: `icegear.py:231 build_guard_booth` (162), `ice.py:152 build_black_ice` (≈99), `ice.py:251 build_black_lair` (94), `props.py:160 build_vault_volume` (86).
- Что: после B2 штрихи плит не экспортируются, но цикл их считает, чтобы раскладка плит (одобренная на очках) не поменялась; это закреплено словами, а не тестом. `smooth=True` у `pillar_block`/`exit_bar`/`vault_body` оправдан только снятой обводкой `fringe`.
- Почему мешает: читатель видит «штрихи» и тратит время; рефактор раскладки плит ломает вид, и нет теста, что она неизменна (кроме сравнения с закоммиченным `.glb` в `validate.py`/числовых утверждениях).
- Выгода: низкая–средняя.
- Риск (дверь/радиус): правки только Python; пересборка `.glb` недопустима без решения (бинарный diff, очки). Сначала заменить дорогой цикл на явный `rng.random()`-пропуск ровно того же числа вызовов и проверить побайтное равенство `.glb`.
- Размер: M
- Проверить чем: пересборка на devbox `netrun/assets/tools/pipeline.sh` и `git diff --stat netrun/assets/models` = 0; `python3 netrun/assets/src/validate.py --root netrun/assets`.

### 10. Дублирование геометрии колонны: `env.py:build_pillar` и `client/obstacle_body.gd`
- Где: `src/env.py:370` (`build_pillar`, `lit()` и пояс/рамка), `client/obstacle_body.gd:8-45` (`HEIGHT/INSET/BAND/RISE/FRAME_Y`, `light()`), сверка `tests/assets_obstacle_body_test.gd:73` с `pillar.glb`.
- Что: корпус цельного препятствия генерируется дважды, в Blender и во время выполнения в GDScript, с одними константами (`COVER_H = 2.2`, `BAND`, `RISE`); согласованность держит один тест на сравнение ключей вершин.
- Почему мешает: любая правка колонны (толщина полосы света, высота) требует двух синхронных правок и пересборки; тест падает, но не подсказывает, в какой из двух файлов идти.
- Выгода: низкая (защита уже есть, `ff128551`).
- Риск (дверь/радиус): две зоны (Blender и Godot-клиент); оставить как есть и только описать в ARCHITECTURE (одна строка «зеркало, тест …»). Кандидат на удаление только если `pillar.glb` перестанет использоваться для одиночной колонны.
- Размер: S
- Проверить чем: `dev.sh test assets_obstacle_body_test`.

### 11. Покадровый обход материалов в клиенте и статические реестры
- Где: `asset_materials.gd:543-575` (`_cloud_materials`, строит словарь и массив на каждый вызов), `:579-600` (`set_cloud_breath`/`set_cloud_touch` вызывают его по разу), `:335-350` (`set_alarm_focus`), вызовы каждый кадр: `client/rig_test_scene.gd:874-875,881`; статические `_surface_cloud_mats`/`_focus_mats` (`:184-186`), `_tuned` (`:178`).
- Что: по коду за кадр дважды обходится группа `surface_clouds` + группа `volume_clouds` с выделением памяти, а `set_alarm_focus` на уровнях 0–1 всё равно проходит по всем материалам и пишет 4 параметра (функция «выключает сама» только по значению радиуса, не по раннему выходу). Реестры слабых ссылок не сбрасываются между тестами и растут до первого `set_alarm_focus`/`_cloud_materials`.
- Почему мешает: CPU-кадр Pico (бюджет 11,1 мс, досье §7.2) платит за обход, который можно кэшировать при `apply()`; глобальное состояние даёт межтестовые зависимости.
- Выгода: низкая–средняя (замера нет, только по коду).
- Риск (дверь/радиус): низкий, один файл `asset_materials.gd` и 1–2 теста; обязателен кадр и замер на очках, а не только `dev.sh test`.
- Размер: S
- Проверить чем: `dev.sh test assets_cloud_breath_test assets_alarm_focus_test`, замер CPU-кадра на Pico (владельцем).

### 12. Облачный шейдер: вычисления до раннего выхода и без выхода по `far_k = 0`
- Где: `shaders/volume_cloud.gdshaderinc:55-74` (хэши `h`, `h2` и шум `patch_n` считаются до проверки `sharp < 0.02`, где `h`, `h2` не нужны), `:66-68`; отсутствие `discard`/раннего возврата при `dist ≥ dust_far_end` (`far_k = 0`, альфа 0); `cloud_dark.gdshaderinc:34-42` после `volume_cloud` ещё `breath_lift`, `touch_k`, `focus_light`.
- Что: по коду, без замеров: фрагмент дальнего пласта (за 40 м) всё равно исполняет ≈6 хэшей, 4 из них в шуме, при альфе 0; на «всё из частиц» (#424) цена пола и дальних пластов на очках не измерена (`asset_materials.gd:162-163` комментарий).
- Почему мешает: это ровно статья бюджета Pico (+3,4 мс по прежнему замеру `cloud_far`, `docs/netrun-refactor-plan.md` §0).
- Выгода: средняя, если замер подтвердит; в любом случае бесплатная проверка.
- Риск (дверь/радиус): шейдер общий для реквизита и пола; поведение (вид) не меняется, если ранний выход точно повторяет `a = 0`. Менять только вместе с серией кадров/замером на очках, по правилу «показ только по слову владельца».
- Размер: S
- Проверить чем: `dev.sh shot` до/после (пиксельное равенство), `bench` на Pico по слову владельца.

### 13. Тесты: тесты-надгробия и импорт-тесты вместо проверки вида; один файл на 1297 строк
- Где: `tests/assets_models_test.gd:83-107` (`load != null`), `:241-249`, `:654-665` (списки удалённых файлов/ручек/uniform'ов), `:567-596`; весь файл — 1297 строк, 60+ функций, один `GdUnitTestSuite`.
- Что: значительная часть проверяет, что что-то отсутствует (удалённые ручки и файлы), либо загрузку; 167 числовых порогов по габаритам и числу треугольников привязаны к закоммиченным `.glb` (пересборка Blender меняет их). Вид (цвет, яркость кадра) не проверяется: только uniform'ы на месте.
- Почему мешает: пересборка модели (бинарный конфликт слияний) ломает пороги без регрессии вида; надгробия копятся с каждой чисткой (B1–B3, #424), а отсутствие файла и так ловит `validate.py`.
- Выгода: средняя (скорость прогона и диагностика).
- Риск (дверь/радиус): низкий; нельзя терять охранные тесты на контракты (имена мешей, `LAYERS`, `pillar`). 1 файл → 4–5 по областям (env/ice/props/knobs/palette).
- Размер: M
- Проверить чем: `dev.sh test assets_models_test` до/после, число тестов и время.

### 14. Стенд: 13 `preview_*.gd` с одинаковой обвязкой и разными цветами фона
- Где: `assets/preview_decrypt.gd:11-30`, `preview_charge.gd`, `preview_breach.gd:19`, `preview_deck.gd:19` (фон `Color(0.03, 0.04, 0.06)` ×4), `preview_avatars.gd:34`, `preview_hands.gd:31`, `preview_node.gd:22` (`(0.008, 0.012, 0.02)`), `preview_capture.gd:156` (`VOID_BG`); общий разбор `OS.get_cmdline_user_args()` и `Environment`/`Camera3D`/`save_png` в 13 файлах.
- Что: каждая сцена повторяет 15–25 строк обвязки (аргументы `--out/--only`, окружение, камера, сохранение кадра), а фон выбирает сама: четыре разных цвета в одном стенде (не `AssetMaterials`).
- Почему мешает: кадры разных сцен нельзя сравнивать по яркости; та же причина, что в находке 1; новая сцена копирует предыдущую вместе с чужим фоном.
- Выгода: низкая–средняя.
- Риск (дверь/радиус): только стенд (`netrun/assets/preview_*`), на игру не влияет; `dev.sh shot` использует имена сцен.
- Размер: M
- Проверить чем: `dev.sh shot` по каждой сцене (кадры без диффа), `dev.sh test`.

### 15. Устаревшие упоминания удалённого (`fringe`, `edge_soft`, `mist`) в коде и комментариях
- Где: `client/obstacle_body.gd:23`, `client/proto_client.gd:80,192` (формат журнала `render msaa=… aa=… fringe=… scale=…`), `tests/foyer_preview.gd:20` (пример `--tune=edge_soft=0.8,fringe_on=false`), `src/env.py:357`, `src/exit_frame.py:53`, `src/props.py:182`, `assets/ARCHITECTURE.md:378,559-562,639-644` (разделы про снятое), `client/node_assets.gd:145` («mist_alpha=0»); `shared/breach/breach_rules.gd:2` (из досье §5 п. 10).
- Что: ссылки на уже удалённые шейдеры и ручки; команды-примеры `--tune=` вызывают предупреждение «неизвестная ручка».
- Почему мешает: новая сессия ищет `fringe.gdshader`, которого нет; ложный след при отладке вида.
- Выгода: низкая.
- Риск (дверь/радиус): нулевой (комментарии); `proto_client.gd` — Godot-зона, передать карточкой.
- Размер: S
- Проверить чем: `grep -rn fringe netrun --include=*.gd --include=*.py` после правки; `dev.sh test render_config_test`.

## Чего нет (что ожидал найти и не нашёл)

- Мёртвых ручек в `KNOBS` без читателей почти нет: у каждой есть `_k("…")` в `asset_materials.gd`; ручки `fringe/halo/edge_soft/dust/…` из плана B1 действительно удалены (тест `:654` это закрепляет), `cloud_lite`/`cloud_two_sided` и шейдеры `fringe/glass/haze` отсутствуют.
- Цветов, заданных клиентом мимо палитры, мало: из `client/` (кроме `deck_theme.gd`, у него осознанно свой набор по `asset_materials.gd:105`) нарушают только `obstacle_body.gd:15-16` и `hand_view.gd:29-30`; `tick_floor.gd`, `ice_view.gd` берут цвета из `layer()`.
- Экспериментальных `.glb` (`floor_v*`, `wall*`, `room_moat*`) в `models/` нет; варианты `_b/_c` у пола и потолка — три раскладки по сидам (`env.py:383-389`, `node_view.gd:44-46`), не мусор.
- Функций длиннее 100 строк в GDScript области нет (`apply` 102 — единственная, `_shots` 107 — таблица); крупнейшая функция в `node_view.gd` — 31 строка.
- Юнит-тестов Python-генератора нет, и это допустимо (нужен `bpy`); защита — `validate.py` в CI (`.github/workflows/netrun.yml:39`) и проверки габаритов в `assets_models_test.gd`.

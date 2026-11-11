# Ревью области «Сеть» (Godot + Мост), 17.10.2026

## Сводка области
- Размер: netrun/server 9,9 тыс. строк (30 gd), shared 5,3 тыс., client 16,7 тыс. (87 файлов), netrun-bridge main 5,6 тыс. Kotlin + test 7,1 тыс.
- Архитектура Godot: слои чистые (shared не знает server/client, клиент не знает GrayNode/NetServer — только в комментариях). Серверный центр — `GrayNode`
  (2622 строки, 172 функции, 101 поле/константа), вокруг него уже вынесены `VaultBreach`, `DecryptBreach`, `ChargeBreach`, `BarrierBreach`, `GiveService`,
  `GraphWorld`, `TickClock`; но вынос остановился на полпути.
- Мост (Kotlin): функции короткие (самая длинная — `doFinish`, 66 строк), `ValueOps.kt` (719) разбит на расширения `ValueOpsBreach/Give/Decrypt`. Деньги и предметы
  покрыты хорошо (ValueOpsTest 38, ValueOpsGiveTest 30, BreachOpsTest 44 теста, прогоны отказов `faultSweepFinish*`).
- Тесты: 167 файлов gdUnit (30,6 тыс. строк, вдвое больше кода сервера). GrayNode затронут 29 файлами, TickIce — 8, NetServer — 35; пробелов в «рискованной» логике
  по числу файлов нет. Слабое место — не покрытие, а то, что тесты ходят через фальш-Мост, повторяющий правила настоящего.
- Контракт правил взлома Kotlin ↔ GDScript защищён хорошо: `breach_golden.json` читают и `BreachGoldenTest.kt`, и `breach_golden_test.gd`; `breach.json` генерируется
  `BreachJsonTest`. Остальные копии правил (расшифровка, таблицы тиров, эдди) держатся комментариями.
- Общее впечатление: кодовая база дисциплинированная; главный долг — один God-объект на сервере, доживающий режим `realtime`, четыре копипаст-сервиса мини-игр и
  фальш-Мост на 651 строку с собственными правилами.

## Находки

### 1. GrayNode — God-объект: 9 ответственностей в одном классе
- Где: `netrun/server/node/gray_node.gd:1` (2622 строки); границы разделов: `:878` (добыча), `:971` (такты), `:2097` (граф узлов), `:2321` (тревога и локдаун), `:2490` (шарды), `:2582` (переход)
- Что: в одном классе — восстановление из Моста (`recover`, :485, 92 строки), колода и остывание (:773–:880), тактовый ICE (:971–:1260), датчики/барьеры/маяки (:1335–:1460), широковещание состояния (:1280, :1464, :1520), исходы и «ждём мастера» (:1918–:2095), хранилища и шарды (:2098–:2290, :2490–:2580), тревога/локдаун (:2321–:2489), порталы.
- Почему мешает: каждая правка шарда или тревоги читает и тестирует всё поле из 101 переменной; растущий класс — причина того, что 29 тестов собирают целый узел ради одной механики. Рост за последние поезда (#377, П9) идёт именно сюда.
- Выгода: высокая — меньше контекста на правку (агентам CLAUDE.md «читать точечно» нужно искать нужное `grep`-ом по 2600 строкам), изолированные тесты.
- Риск (дверь/радиус): средний. Контракт сообщений не меняется; задет `gray_node.gd` + `GraphWorld`/`NetServer` (публичные методы вызывают 29 тестов — оставить фасад). Не трогает инварианты денег, но `_finish_in_bridge`/`run.finish` (:2030) — граница с Мостом, переносить дословно.
- Размер: L (волна из 4–5 карточек S: Alarm (:2321–2489, ~170 строк, чистая логика), Shards/Refill (:2490–2581), Outcome/Finish (:1918–2095), StateBroadcast (:1280–1334, :1464–1534), Recovery (:476–613)). Начинать с Alarm — наименьшие связи.
- Проверить чем: `netrun/tools/dev.sh test` по затронутым (`gray_node_*`, `trace_alarm_test`, `reserve_*`, `barrier_*`), потом `test --all` в фоне; e2e `netrun-run.sh`.

### 2. Режим `realtime` у ICE доживает рядом с тактовым, хотя в плане «потом удаляется»
- Где: `netrun/server/node/node_graph.gd:34` (умолчание `"realtime"`), `docs/gamedesign/time-and-movement.md:217` («только пока идёт сравнение; потом удаляется»), `gray_node.gd:945–950` (ветка `_tick_mode`, всего 19 упоминаний), `netrun/server/ice/ice_brain.gd` (306), `ice_node.gd` (41)
- Что: во всех боевых графах (`data/graph.json:28`, `data/solo/graph.json:46`, стенды) `time_mode: "tick"`; `realtime` остался умолчанием в коде и держит вторую логику ICE (`IceBrain` + `IceNode`) и вторую ветку каждого широковещания. Док `netrun-tick-mode.md:15` называет realtime умолчанием в коде, `time-and-movement.md:215` — `tick` умолчанием по решению владельца: две правды.
- Почему мешает: удваивает пространство состояний GrayNode (19 условий `_tick_mode`) и тестов (`IceBrain` в 6 тестах, `IceNode` в 11); новая механика (датчики, барьеры, тревога на такт) каждый раз пишется с `if not _tick_mode`.
- Выгода: высокая — убирает целую ветку сервера, упрощает разбиение из п. 1.
- Риск (дверь/радиус): средний; затрагивает только Сеть; `TickBlackBrain extends IceBrain` (`tick_black_brain.gd:2`) — базовый класс нужен и после удаления realtime (оставить `IceBrain` как состояние/журнал). ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА: сравнение realtime/tick «на очках» закончено? Мы это из репозитория не видим.
- Размер: M
- Проверить чем: `dev.sh test` по `ice_*`, `black_ice_test`, `gray_node_*`; затем `test --all`.

### 3. Четыре копии одного каркаса мини-игры (Vault/Decrypt/Charge/Barrier)
- Где: `netrun/server/node/vault_breach.gd:75`, `decrypt_breach.gd:54`, `charge_breach.gd:44`, `barrier_breach.gd:51` (всего ≈1110 строк)
- Что: у каждого одни и те же `has_attempt`, `attempt_of`, `clear_session`, `check_start`, `request_start/tap/cancel`, `tick`, `end_early` и словарь `_by_session`; общего базового класса нет. Все четыре `clear_session` ни разу не вызываются (поиск по `netrun/` — только определения); очистка делается внутри `_finish` (`vault_breach.gd:356`).
- Почему мешает: правка правила (например, `avatar_removed`, таймаут, отказ) делается четырежды, расхождение молча; мёртвые `clear_session` вводят в заблуждение — похоже, что сессия чистится.
- Выгода: средняя/высокая — общий `SessionAttempt` базовый класс снимет ≈300 строк и закрепит единый порядок отказов.
- Риск (дверь/радиус): средний; 4 класса + `gray_node.gd` (их тики и `_on_avatar_removed`, :1580); формат сообщений не меняется. Правила взлома в Мосте/`rules/` не затронуты.
- Размер: M
- Проверить чем: `dev.sh test` по `breach_world_test`, `decrypt_world_test`, `charge_world_test`, `barrier_world_test`, `give_service_test`.

### 4. Фальш-Мост на 651 строку повторяет правила настоящего — ложно-зелёное и уже расхождение
- Где: `netrun/server/bridge/fake_bridge.gd:3–4` (шапка: «правил Моста тут нет»), `:34–36` (свои таблицы эдди, бонус MINER, остывание 1800 с), `:357` (`run_finish`, свой план перемещений), `:415–:540` (`run_breach`: своя проверка запроса, остывание, открытие хранилищ), `:241` / `:302` (give/decrypt)
- Что: шапка говорит «правил нет», но файл реализует `run.finish`, `run.breach`, `op.give_item`, `op.decrypt_item` с проверками, кулдауном и таблицами; настоящие числа/ошибки в Kotlin (`ValueOps.kt:390`, `ValueOpsBreach.kt`, `rules/BreachConstants.kt:9`). Сверка вручную есть в одном месте (`ValueOpsGiveTest.kt:303` ↔ `fake_bridge_test.gd`), для finish/breach — нет.
- Почему мешает: класс сбоя «копии правил и протоколов разъезжаются» (досье §5.10): зелёные тесты Godot подтверждают поведение фальши, а не Моста. Живой пример расхождения есть уже сейчас: `gray_node.gd:2021` читает `bridge.get("docs")` (позывной в карточке «ФЛЭТЛАЙН»), у `BridgeClient` поле называется `docs` (`bridge_client.gd:37`), у `FakeBridge` — `_docs` (`fake_bridge.gd:9`) → на фальши позывной молча заменяется ключом сессии, и тест текста карточки не может поймать ошибку.
- Выгода: высокая — общие векторы «запрос → ответ/код ошибки» (JSON, как `breach_golden.json`) прогонять и Kotlin-тестом, и GDScript-тестом по `run.finish`, `run.breach`, `op.take/leave`; тесты фальши перестанут быть единственной защитой.
- Риск (дверь/радиус): низкий — только тесты и фикстуры; задеты `netrun/tests/fixtures/`, `netrun-bridge/src/test`, `fake_bridge.gd`. Инварианты денег читать (а не менять): векторы фиксируют существующее поведение. Три другие копии Моста: `admin-web/server/src/net/fakeBridge.ts` (279), `netrun-bridge/.../FakeWorldServer.kt` (61), `scripts/e2e/netrun-bridge.mjs` (29) — только для коллектора, векторы им не нужны.
- Размер: M
- Проверить чем: `dev.sh test fake_bridge_test breach_bridge_test bridge_client_test`; `scripts/dbx.sh -- :netrun-bridge:test`.

### 5. Сообщение STATE — безымянные строковые ключи по обе стороны
- Где: `netrun/server/node/gray_node.gd:1280–1334` и `:1464–1520` (сборка: `"p"`, `"f"`, `"s"`, `"b"`, `"bp"`, `"bw"`, `"pg"`, `"c"`, `"kd"`, `"tk"`, `"bk"`, `"sn"`, `"br"`, `"bo"`, `"burn"`), `netrun/client/rig_test_scene.gd:246–287` (разбор), `netrun/shared/net/world_msg.gd:18` (только имя типа)
- Что: для типа STATE в `WorldMsg` нет ни констант полей, ни схемы; сервер и клиент договариваются устно по комментариям. Поля растут с каждой волной (волна 4: `bk`, `sn`, `br`, `bo`).
- Почему мешает: опечатка в ключе даёт не ошибку, а `state.get("bk", [])` → пустое значение, т. е. элемент не показывается; ловится только на очках/кадре.
- Выгода: средняя — константы полей в `WorldMsg` + один тест «каждое поле, что кладёт сервер, читает клиент и наоборот» снимет класс «тихо пропал элемент».
- Риск (дверь/радиус): низкий при условии «только имена»; формат на проводе не меняется. Затронуты `gray_node.gd`, `rig_test_scene.gd`, `world_msg.gd`, 2–3 теста.
- Размер: S
- Проверить чем: `dev.sh test node_scene_test trace_alarm_test` + новый тест схемы.

### 6. `rig_test_scene.gd` — не тестовая сцена, а главный оркестратор клиента (1327 строк, 79 функций)
- Где: `netrun/client/rig_test_scene.gd:1`, подключается в `netrun/client/proto_client.gd:85` (`preload(...).new()`); также `netrun/README.md:89`
- Что: имя «тест» осталось от прототипа; файл ведёт бочки, ICE, аватары, колоду, барьеры, маяки, датчики, тревогу, облако, панель взлома. Рядом `proto_client.gd:70` — `start()` на 123 строки, `_on_event` на 69.
- Почему мешает: агенты и ревьюеры пропускают файл как тестовый или, наоборот, боятся его; «правка рядом» ломает несвязанное (`_apply_barriers`, `_update_cloud`, `apply_breach_event` в одном классе). Часть слоя — зона Blender (`node_view`, `ice_view`), поэтому разрез по зонам тоже нужен.
- Выгода: средняя — переименование (S) убирает путаницу сразу, разрез по ответственностям (M) — следующий шаг.
- Риск (дверь/радиус): переименование: ≈10 файлов (`tests/node_scene_test.gd`, `booth_view_test.gd`, `solo_controls_test.gd`, `tick_demo_preview.gd`, `p8_frame_preview.gd`, `tools/p9_cost.gd`…), .tscn-ссылки через `preload`/`.uid`; делать с `scripts/dbx`-прогоном `dev.sh test --all`. Зона: Godot (Blender не затронут, пока `node_view`/`ice_view` сохраняют API).
- Размер: S (переименование) + M (разрез)
- Проверить чем: `grep -rn rig_test_scene netrun` = 0 после переименования; `dev.sh test --all` в фоне; кадр `dev.sh shot res://tests/foyer_preview.tscn`.

### 7. `layout_bots.gd` и `layout_check.gd` — инструменты проверки раскладок живут в боевом каталоге сервера
- Где: `netrun/server/layout_bots.gd:1` (1029 строк), `netrun/server/layout_check.gd:1` (518)
- Что: оба класса используют только тесты (`layout_bots_test`, `layout_check_test`, `layout_size_test`, `stand_p9_graph_test`, `black_lair_node_test`…) и документ `docs/netrun-tick-mode.md`; в сервере мира на них ссылок нет (`grep LayoutBots|LayoutCheck` в `server/node`, `world_server.gd` — пусто). При этом лежат в `server/` рядом с боевым кодом, а `layout_bots.gd` содержит длинные статические отчёты (`runner_report`, `thief_report`, `black_runner_report`, `check_*`) и DFS-решатель.
- Почему мешает: раздувают «серверный» объём (≈1,5 тыс. из 9,9 тыс. строк) и попадают в экспорт `--server`; агент, читая сервер, тратит контекст на проверку раскладок.
- Выгода: низкая/средняя — переезд в `netrun/tools/` или `netrun/tests/support/` не меняет логики.
- Риск (дверь/радиус): низкий; `class_name` делает ссылки прозрачными, пути `res://` в тестах не заданы; убедиться, что экспорт не ссылается. Только Godot-зона.
- Размер: S
- Проверить чем: `dev.sh test layout_bots_test layout_check_test layout_size_test`; сборка экспорта `tools/export_flat_win.sh` не должна терять классы.

### 8. Мёртвые публичные функции без единого вызова
- Где: `netrun/server/node/gray_node.gd:915` (`callsign_of` — обёртка над `_callsign_of`), `:974` (`is_tick_mode`), `:1203` (`wake_black_ice`); четыре `clear_session` (п. 3); `netrun/server/ice/tick_black.gd:124` (`burns_of`); `netrun/shared/net/server_clock.gd:15` (`has_data`); `netrun/shared/alarm_levels.gd:21`, `netrun/shared/run_mode.gd:23` (`name_of`); `netrun/client/rig_test_scene.gd:366` (`beacon_view_of`); `netrun/client/ui/deck_charge.gd:71`, `deck_pointer.gd:278`, `offscreen_alert.gd:52`; Kotlin: `netrun-bridge/.../MasterOps.kt:203` (`gateForRule`)
- Что: поиск по `server client shared tools tests` (GDScript) и `main test` (Kotlin) даёт 0 вызовов вне определения. `session_abort` в Godot (`bridge_api.gd:130`, `bridge_client.gd:246`, `fake_bridge.gd:132`) не вызывается нигде в боевом коде — op есть в протоколе, а вызова со стороны сервера мира нет.
- Почему мешает: ложные «ручки» — читая `wake_black_ice`/`gateForRule`, агент полагает, что правило мастера/Моста их вызывает. Для `gateForRule` комментарий «Версия для правил Моста (роль BRIDGE)» вводит в заблуждение: `RuleEngine` её не использует.
- Выгода: низкая — но почти бесплатно.
- Риск (дверь/радиус): минимальный; `wake_black_ice` может быть задуман под панель мастера (комментарий у :1209) — спросить Godot-сессию перед удалением; `session_abort` — часть контракта протокола (6.x) — не удалять, а пометить.
- Размер: S
- Проверить чем: `dev.sh test --all`; `scripts/dbx.sh -- :netrun-bridge:test`.

### 9. Копии стендов П6/П7/П9: почти одинаковые графы, фикстуры и скрипты
- Где: `netrun/tools/stand/p6_graph.json` ↔ `p7_graph.json` (121 строка, отличие 4 строки), `p6_bridge_fixture.json` ↔ `p7_bridge_fixture.json` (364 строки, отличие 50), `p9_graph_hard8.json` ↔ `p9_graph_hard10.json` (отличие 8); `netrun/tools/srv_p6.sh`, `srv_p7.sh`, `srv_p9.sh`; тесты `netrun/tests/stand_p6_graph_test.gd`, `stand_p9_graph_test.gd`
- Что: на каждый показ владельцу копируют граф и скрипт целиком (≈1590 строк JSON в `tools/stand`). Общее — `graph.json` с отличиями в нескольких узлах.
- Почему мешает: правка графа или фикстуры (новая механика, поле Моста) требует правки 5–6 копий; два стенда уже отстали бы от `data/graph.json` (145 строк отличий).
- Выгода: низкая/средняя — один шаблон + параметры (`srv_stand.sh p6|p7|p9`).
- Риск (дверь/радиус): низкий; нужен ответ: П6/П7 ещё показывают или уже архив (П8 разобран, П9 идёт по памяти сессии Godot). Задеты 2 теста.
- Размер: S
- Проверить чем: `dev.sh test stand_p6_graph_test stand_p9_graph_test`.

### 10. Таблицы тиров и правила расшифровки/эдди — копии на комментариях
- Где: `netrun/server/node/node_graph.gd:9–10`, `netrun/shared/breach/breach_data.gd:9`, `netrun/client/node_assets.gd:9`, `netrun/server/bridge/fake_bridge.gd:37` (список тиров ×4); `TIER_BLACK` дважды: `node_graph.gd:10`, `gray_node.gd:49`; `netrun/shared/breach/deck_decrypt.gd:4` ↔ `rules/.../DecryptRules.kt:11`; `fake_bridge.gd:34–35` ↔ `netrun/data/rules/breach.json` (диапазоны эдди и бонус MINER)
- Что: правило «лучший дешифратор — ближайший по тиру» в GDScript и Kotlin совпадает по смыслу, но золотого общего теста (как для взлома) нет; тир-таблицы и числа эдди фальши дублируют уже сгенерированный `breach.json`.
- Почему мешает: класс «копии правил разъезжаются» (досье §5.10); защищено только комментарием и тестами с ручными числами (`decrypt_client_test.gd:140`).
- Выгода: низкая/средняя.
- Риск (дверь/радиус): низкий; `DecryptRules` — правило Моста (деньги/предметы): Godot-копию не менять, только добавить сверку. ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА лишь если сверка выявит расхождение.
- Размер: S
- Проверить чем: `scripts/dbx.sh -- :rules:test` и `dev.sh test decrypt_client_test`; новый общий вектор `decrypt_golden.json`.

### 11. Устаревшие документы и комментарии вводят в заблуждение
- Где: `docs/netrun-refactor-plan.md:32–46` (список «тупик → удалить», отметок «сделано» нет), хотя код очищен (`netrun/shared/render_config.gd:34` `LEGACY_KEYS`, `netrun/tests/assets_models_test.gd:584`, `:843` проверяют отсутствие `fringe_on`, `cloud_two_sided`); `netrun/shared/breach/breach_rules.gd:2` («порт app/.../breach/BreachRules.kt» — файл переехал в `rules/src/main/kotlin/com/megablok10/rules/BreachRules.kt`); `docs/netrun-tick-mode.md:15` ↔ `docs/gamedesign/time-and-movement.md:215` (разное умолчание режима)
- Что: план рефакторинга от 13.10 не отмечен после исполнения (G1/B1/B2 по факту сделаны); путь порта в комментарии устарел.
- Почему мешает: следующий аудит или агент снова «найдёт» ручки к удалению (досье §3/§4 уже сделал такую ошибку для `fringe`); разные умолчания режима — выбор не в пользу кода.
- Выгода: низкая, но делается за час и снимает повторный анализ.
- Риск (дверь/радиус): нулевой (документы/комментарии). Документы `netrun*.md` — зона Godot; `time-and-movement.md` — Геймдизайн (карточкой).
- Размер: S
- Проверить чем: `grep -n "fringe_on" netrun --include='*.gd'` — только тесты отсутствия.

### 12. `ValueOps.kt` — самый крупный файл Моста (719 строк): много `internal`-хелперов для файлов-расширений
- Где: `netrun-bridge/src/main/kotlin/com/megablok10/netrun/bridge/ValueOps.kt:52` (класс), `:390` (`doFinish`, 66 строк), `:602–:687` (`execute`, `loadSession`, `currentNode`, `loadDeck`, `putDeckItems`… — `internal` для `ValueOpsBreach/Give/Decrypt`)
- Что: один класс: подача колоды, take/leave, выдача на телефон, finish, stock/unstock, абстракция документов. Расширения в трёх файлах пользуются `internal` помощниками; границы между «операции» и «доступ к документам» нет.
- Почему мешает: при добавлении очередной операции (`ValueOpsGive` была последней) приходится открывать ещё один `internal`; риск случайно обойти `exec` (`:620`) и потерять идемпотентность по `rid`.
- Выгода: низкая — код читаем, функции короткие, тесты сильные; разрез ради разреза не нужен.
- Риск (дверь/радиус): высокий для суммы работы — это деньги/предметы, `.claude/rules/app-invariants.md`. ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА перед любой правкой; рекомендация — не трогать, пока нет новой операции, которой тесно.
- Размер: M (если делать)
- Проверить чем: `scripts/dbx.sh -- :netrun-bridge:detekt :netrun-bridge:test`; e2e `netrun-run.sh` (реальный Мост).

## Чего нет
- Рендер-ручек `RenderConfig`/`AssetMaterials` без читателей почти нет: `fringe`, `scale`, `aa`, `foveation_dynamic` удалены и сведены к `LEGACY_KEYS` (`render_config.gd:34`), тесты проверяют их отсутствие. Остались `streak_keep`/`point_keep` = 0 по умолчанию (`asset_materials.gd:165,168`) — это зона Blender, читатели есть (шейдеры, тест).
- Смешения слоёв «клиент ↔ сервер ↔ shared» не нашёл: `res://client`/`res://server` из `shared` не берётся, `GrayNode`/`NetServer` в клиенте только в комментариях; единственная связь — `solo_stub.gd:16` встраивает сервер намеренно.
- Дубля правил взлома между `netrun/shared/breach` и `rules/` почти нет: есть золотой файл и генерируемый `breach.json`; расхождения «остывание» нет — остывание считает только Мост (`ValueOpsBreach.kt:195`), в Godot лишь фальш.
- Функций длиннее ~125 строк в Kotlin Моста нет (макс. 66); в GDScript сервере >90 строк — только `recover` (92) и `start` (≈90); крупнейшая в клиенте — `proto_client.start` (123).
- Отдельной проблемы с покрытием `tick_ice`/`gray_node` нет: тесты есть (`tick_ice_test` 643, `gray_node_tick_test` 392, `tick_*_test` ×10); слабое место — зависимость от фальш-Моста (п. 4), а не нехватка файлов.

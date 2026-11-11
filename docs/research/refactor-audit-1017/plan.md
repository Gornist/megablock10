# Аудит рефакторинга «Мегаблок №10» — план от 17.10.2026

Сессия «Аудит рефакторинга», только чтение. `main` на `47c6c157`. Материалы: `1017/dossier.md` (досье scout),
`1017/review-<область>.md` (семь отчётов ревьюеров: Sonnet по областям, Opus — контракты), карточки ревьюеров там же.
По 2–3 главным находкам каждой области строки `файл:строка` открыты и проверены вручную (отметка ✔ ниже).

Что уже сделано и не повторяется: Android — этапы A–E `docs/refactor-plan.md` (список «не делали» учтён);
Сеть — `docs/netrun-refactor-plan.md` (G1/B1/B2/G2/B3/G3 влиты 13–14.10). Инварианты денег (`.claude/rules/app-invariants.md`)
ни одним пунктом не меняются; где рефактор их касается — пометка «решение владельца».

## 1. Сводка по областям

| Область | Размер | Состояние | Главное |
|---|---|---|---|
| Android (`app/`, `kit/`, `rules/`) | app 17,8 тыс. строк main / 9,6 тыс. test; kit 1,7/1,7; rules 0,9/1,1 | Зрелая после этапов A–E. `AppGraph` — композиционный корень (333 строки, ~55 `val`), не God-объект экранов; большой рефакторинг не нужен | Дрейф контрактов без сверки: предобраз подписи денег дублируется в Мосте ✔, список причин записей в трёх копиях ✔, `WireVersion.REPORTED` неполный и тест сравнивает множества ✔; `CallManager` 355 строк без тестов ✔ |
| Коллектор (`admin-web/`) | сервер 21,8 тыс. (123 + 68 test), клиент 11,7 тыс. (110 + 30 test) | Зрелая: гигантов нет, миграции и типы в порядке. 13 находок, все S кроме тестов экранов мастера | Нет сверочного теста Kotlin↔TS по причинам и полям ✔; приём `/api/changes` (конфликт `seq`, флэтлайн, откат батча) без тестов; `requireMaster` вручную в 112 местах без теста «все маршруты закрыты» |
| Сеть (`netrun/`, `netrun-bridge/`) | server 9,9 тыс., shared 5,3, client 16,7 (без assets), Мост 5,6 + 7,1 test | Сервер мира держится на одном файле. `gray_node.gd` 2622 строки, 172 функции ✔ | `fake_bridge.gd` (651 строка) сам реализует правила Моста, живое расхождение `docs`/`_docs` ✔; режим ICE `realtime` остался умолчанием; четыре копии каркаса мини-игры; `rig_test_scene.gd` 1327 строк — главный оркестратор клиента |
| Вид Сети (`netrun/assets`) | asset_materials.gd 612, preview_capture 522, src/*.py 3,3 тыс., 16 шейдеров | После B1–B4 остались хвосты | Фон клиента `CALM_BG` ≠ `VOID_BG` превью ✔ (класс сбоя «приёмка по своему стенду»); ручки `streak_*`/`point_keep` обслуживают только скрытую рамку выхода ✔; `recolor()` скопирован в 6 шейдеров побайтно ✔; ~44 uniform'а без setter'ов; `assets_models_test.gd` 1297 строк |
| Прошивка (`firmware/`, `displays/`) | 8,1 тыс. строк C++; сервер displays/audio ≈ 2,5 тыс. TS | Протокол MB10D закреплён общими векторами — хорошо. Звук — нет | Пределы звука литералами в C++ и TS, векторов звука 0 ✔; тест «сервер ↔ настоящая прошивка» молча пропускается без бинарника ✔; mock-дисплей — третья реализация звука; `firmware.yml` гоняется дважды на PR из `agent/**` ✔ |
| Конвейер (`scripts/`, хуки, workflows) | 19 скриптов + `box/ctl.sh` 1119, e2e 19 сценариев, 7 workflows | `lint-pipeline.sh` зелёный. Главная утечка — CI и расхождение локальных проверок с CI | `netrun.yml`/`firmware.yml` дважды на пуш ✔; `dbx.sh --full` не гоняет `:netrun-bridge`, CI гоняет ✔; `verify.sh` на правку конвейера отвечает «нечего проверять» ✔; таблица зон в 4 копиях; хук обходится `git -C … push` |
| Контракты между зонами | см. §2 | см. §2 | см. §2 |

Общая картина: крупных God-объектов два (`gray_node.gd`, `box/ctl.sh`), остальное — зрелый код. Главный класс долга не «большие файлы»,
а **копии контрактов без сверочных тестов**: один и тот же список/формула живёт в Kotlin, TS и GDScript и расходится молча.
Второй класс — **ложно-зелёные тесты**: фальш-Мост в Godot, mock-дисплей в TS, пропускаемый тест прошивки, тест версий по множествам.
Третий — **расход CI и локальные проверки не равны CI**.

## 2. Контракты между зонами (отчёт Opus, `1017/review-contracts.md`)

| Контракт | Объявляет | Проверяет | Стережёт | Дыра |
|---|---|---|---|---|
| `/api/capabilities` | `admin-web/server/src/routes/capabilities.ts:9-14` (`world_records: 2`, `world_events: 1`) | Мост: `WorldCollectorTransport.kt:118`, `WorldEventSender.kt:175` — **точное равенство** ✔ | `WorldSyncTest.kt:144` требует «новее — тоже не шлём»; `worldRecords.test.ts:48` | `docs/netrun-world-records.md:265` обещает «≥ 2», `:325` — «равен» ✔. Любой подъём версии = пара PR одним поездом |
| Записи мира и `/api/changes` | `kit/.../sync/ChangeRecord.kt:29` (байты подписи) ↔ `admin-web/.../lib/changeRecord.ts:90` | `lib/changeIngest.ts:110` отвергает неизвестную причину | тестовые копии `testUtil.ts:32`, `FakeCollector.kt:239` — 4 копии формулы без общего вектора ✔ | Список причин: `ChangeFields.kt:27-44` ↔ `WorldRecordDeriver.kt:43-49` ↔ `changeRecord.ts:22-47` — сверочного теста нет ✔ |
| Сообщения Моста `/netrun/v1` | `BridgeConfig.kt:4`, `bridge_client.gd:7`, `fakeBridge.ts:119` (литерал) | `BridgeServer.kt:182,205` | `BridgeOpsTest`, `net.test.ts` | Три реализации семантики (Kotlin Мост, `fake_bridge.gd`, `fakeBridge.ts`) без общего набора сценариев; `docs/…protocol.md` без `inbox_timeout` |
| QR `MB10:…` | `Mb10Qr.kt:164-345`; зеркало `mb10QrCodec.ts` | `Mb10Qr.kt:215,246,260,266,277` — CONTAINER/SHARD/RAM/GRANT/SECALERT **без проверки версии** ✔ | побайтные тесты SHARD в TS и Kotlin | `MB10:GRANT` — читатель `Mb10Qr.kt:177` выдаёт лут, писателя и документа нет ✔ |
| Приложение ↔ коллектор | `WireVersion.kt:35` (`REPORTED`) → `CollectorSync.kt:46-52` | `changeIngest.ts:271-282`, `presence.ts:29` | `WireVersionTest.kt:21` сравнивает множества ✔ | `REPORTED` без ENTER/VOICE; тест отправки `wireVersions` отсутствует |

Общий корень: **e2e не запускается на PR коллектора** — в `.github/workflows/e2e.yml:14-20` нет `admin-web/**` ✔. Это единственная
межъязыковая проверка всех пяти контрактов, то есть ровно класс сбоя 05.10 (`world_records: 2` объявили раньше приёма).

## 3. Топ-10 по выгоде/риску

| # | Что | Зона | Размер | Дверь/радиус | Выгода |
|---|---|---|---|---|---|
| 1 | `e2e.yml`: добавить `admin-web/**` в `paths` (`e2e.yml:14-20`) | Pipeline manager (`main.yml`/`e2e.yml` — через него) | S, 1 строка | нулевой; +17 мин CI на PR коллектора | закрывает класс 05.10 целиком |
| 2 | Двойной прогон `netrun.yml`/`firmware.yml` (push без `branches` + `pull_request`): push только `main`, PR — всё (`netrun.yml:3-7`, `firmware.yml:6-12`) | Godot (`netrun.yml`), Физические узлы (`firmware.yml`) | S | низкий; не оставить дыру «push в main без прогона» | вдвое меньше самых дорогих прогонов и квоты Wokwi |
| 3 | Общие векторы контрактов в JSON (`rules/src/test/resources/contracts/`): подпись записи (`ChangeRecord.kt:29`↔`changeRecord.ts:90`), предобраз `TX2|`/`ITEM2|` (`Mb10Qr.kt:322,335`↔`PhoneWire.kt:108,112`), списки причин/полей (3 копии), QR SHARD, лут-крипто; тесты app/kit/Моста/TS читают один файл (образец — `firmware/display/test/vectors/protocol-v1.json`) | файл и тесты Kotlin app/kit — Android App; тест TS — Коллектор; тест Моста — Godot | M (3 карточки S) | только тесты, 0 строк прод-кода; файл создаётся первым, читатели потом | закрывает «молча разъедется» для денег |
| 4 | Локальные проверки = CI: `dbx.sh --auto/--full` гоняет `:netrun-bridge:*` при правке `rules/`/`kit/` (`dbx.sh:40-41`); `verify.sh` на `scripts/`, хуки, workflows зовёт `lint-pipeline.sh` (`verify.sh:23`) | Pipeline manager | S | низкий; скрипты | правка `rules/` перестаёт краснить CI мимо Mac |
| 5 | Фальш-Мост (`fake_bridge.gd`, 651 строка) и Kotlin-Мост на общих JSON-векторах «запрос → ответ/код ошибки» (как `breach_golden.json`); починить `docs`/`_docs` (`gray_node.gd:2021` ↔ `fake_bridge.gd:9`) ✔ | Godot | M | только тесты и фикстуры; `ValueOps` не трогать | убирает ложно-зелёные тесты сервера мира |
| 6 | `gray_node.gd` (2622 строки, 172 функции) — волна разбиения по ответственностям: тревога `:2321-2489` → шарды `:2490-2581` → исход `:1918-2095` → граф `:2097+`; перед ней — удалить режим ICE `realtime` (`node_graph.gd:34`, 19 упоминаний `_tick_mode`) по решению владельца | Godot | L (4–5 карточек S) | средний; формат сообщений не меняется; между стендами, не во время показа | меньше контекста на каждую правку сервера |
| 7 | Звук в общие векторы `protocol-v1.json`: пределы 4096/36/16 КиБ литералами в `protocol.cpp:97-113` и `protocol.ts:432-446` ✔; mock-дисплей (`mockDisplay.ts:311-430`) в набор конформанса; `firmwareHost.test.ts:21-22` — fail, не skip, в `firmware.yml` бинарник обязателен ✔ | Физические узлы | M (2 карточки) | версия протокола не меняется, векторы только добавляются | единственный контракт зоны без сверки байт |
| 8 | Тесты приёма `/api/changes`: конфликт `seq` (`changeIngest.ts:203`), побочный `NET_FLATLINE` (`:225`), откат батча; тест «каждый маршрут требует мастера или секрет» (`requireMaster` ×112) | Коллектор | S | только тесты | страхует самую рискованную функцию и auth |
| 9 | Хвосты после B1–B4: `recolor()` в 6 шейдерах → `.gdshaderinc` ✔; `streak_*`/`point_keep` (`asset_materials.gd:162-167`) и `set_corruption`/`set_distance_fade` (`:481-504`) без читателей в игре ✔; ~44 uniform'а без setter'ов; фон клиента `CALM_BG` (`rig_test_scene.gd:119`) ≠ `VOID_BG` превью ✔ — решение владельца | Blender (шейдеры, ручки), Godot (фон клиента) | S–M | кадр `foyer_preview` до/после через `visual-reviewer`, вид принимать по клиенту | меньше мёртвых веток, превью = клиент |
| 10 | Читающая сторона в одиночку: декодер QR проверяет версию (`Mb10Qr.kt:215,246,260,266,277`); `WireVersion.REPORTED` + ENTER/VOICE (`WireVersion.kt:35`, коллектор уже принимает) и тест на равенство ключей, не множеств (`WireVersionTest.kt:21`); `world_server.gd:100-110` — без `--bridge=` или с опечаткой падать, не брать фикстуру | Android App (QR, версии), Godot (`world_server.gd`) | S | читающая сторона, формат не меняется | убирает молчаливые подмены |

Следом (не в десятке, но дёшево): `docs/backlog.md merge=union` в `.gitattributes` (9 конфликтов из 300 коммитов) — Pipeline, S;
таблица зон в четырёх копиях (`CLAUDE.md`, `zone-check.sh:8-25`, `labeler.yml`, `session-brief.sh:14-24`) → `docs/zones.tsv` — Pipeline, M;
`rig_test_scene.gd` переименовать в оркестратор клиента (≈10 ссылок) — Godot, S; четыре копии каркаса мини-игры (`vault/decrypt/charge/barrier_breach.gd`, ≈1110 строк) → базовый класс — Godot, M;
`CallManager` 355 строк без тестов: чистая машина состояний — Android, M; `AssetMaterials.apply()` 102 строки → таблица `MESH_RULES` — Blender, M;
ssh/devbox-обвязка в 12 местах → `scripts/lib/devbox.sh` — Devbox, M; `box/ctl.sh` 1119 строк — L, **отложить** (работающее железо, очки у владельца).

Не делать (подтверждаем решения прошлых планов): разбиение `AppGraph` (композиционный корень, порядок инициализации); разрез `ValueOps.kt` (деньги, тесты сильные, код читаем);
`kit` отдельной библиотекой; подписи/реестр ключей.

## 4. Волны

Правило порядка: читающая сторона первой; пары — одним поездом; e2e на коллекторе (п. 1) — раньше всех остальных PR коллектора.

**Волна 0 — проверки и CI, без смены форматов (параллельно, все независимы):**
Pipeline: п. 1 (`e2e.yml`), п. 4 (`dbx.sh`/`verify.sh`), `merge=union` для бэклога, `timeout-minutes` у 6 job'ов.
Godot: `netrun.yml` триггеры (п. 2). Физические узлы: `firmware.yml` триггеры (п. 2), `firmwareHost.test.ts` fail вместо skip (п. 7а).
Коллектор: тесты приёма и auth (п. 8). Android: `WireVersionTest` на ключи, сценарий `UNKNOWN` для предметов (`ItemScenariosTest.kt:37-56`).

**Волна 1 — стражи контрактов (файл векторов первым, читатели следом, по одному PR на зону):**
1. Android App: `rules/src/test/resources/contracts/*.json` (подпись записи, `TX2|`/`ITEM2|`, причины/поля, QR SHARD, лут-крипто) + тесты app/kit (п. 3).
2. Затем параллельно: Коллектор — TS-тесты на те же файлы; Godot — тест Моста (`netrun-bridge`) и общие векторы Kotlin-Мост ↔ `fake_bridge.gd` (п. 5); Физические узлы — векторы звука (п. 7б).
3. Android: версии в декодере QR; Godot: `world_server.gd` без фикстуры (п. 10) — читающая сторона, без пар.

**Волна 2 — после решений владельца (§6):**
`capabilities` «==» → «≥» — один PR Моста (Godot), коллектор не трогается; если «{min,max}» — сначала Мост понимает оба вида, потом коллектор объявляет объект, одним поездом.
ICE `realtime` удалить → разбиение `gray_node.gd` карточками (п. 6, Godot, между стендами). Фон `VOID_BG`/`CALM_BG` (Godot клиент + Blender превью). `MB10:GRANT` — удалить (app) или кодер в Мастерской (коллектор). `CallManager` (Android).

**Волна 3 — дедупликация (только после стражей волны 1, байты не меняются):**
Blender: `recolor` → include, ручки `streak_*`/corruption, `MESH_RULES`. Коллектор: таблица `reason → {label, gainsBalance, reward}` вместо 6 списков; `proto` константой в `net/`.
Godot: мини-игры → базовый класс; переименование `rig_test_scene.gd`; `layout_bots.gd`/`layout_check.gd` в `tools/`. Pipeline: `docs/zones.tsv`; единый список Gradle-задач.
Devbox: `scripts/lib/devbox.sh`. Android ↔ Godot поездом: `PhoneWire` в `:rules` (app + netrun-bridge в одной сборке) — только по решению владельца.

Отложено: `box/ctl.sh` (L, железо), AppGraph, ValueOps.

## 5. Строки для `docs/backlog.md` (вносит Pipeline)

Волна 0:
- [ ] [pipeline] `e2e.yml`: добавить `admin-web/**` в `paths` — e2e единственная межъязыковая проверка capabilities/записей/подписи, PR коллектора идут без неё (класс сбоя 05.10) / аудит 17.10, `review-contracts.md` №1
- [ ] [pipeline] `dbx.sh --auto/--full` гонять `:netrun-bridge:detekt :netrun-bridge:test` при правке `rules/` и `kit/`; `verify.sh` на `scripts/`, `.claude/hooks/`, `.github/workflows/` → `lint-pipeline.sh` — правка rules/ красит CI мимо Mac; на конвейер verify отвечает «нечего проверять» / аудит 17.10, `review-pipeline.md` №2
- [ ] [pipeline] `.gitattributes`: `docs/backlog.md merge=union`; `timeout-minutes` у 6 job'ов (`main.yml:22,119`, `firmware.yml:16,78`, `netrun.yml:24,58,145`) — 9 конфликтов бэклога из 300 коммитов; прогон netrun 05.10 висел 50 мин / аудит 17.10, `review-pipeline.md` №11–12
- [ ] [godot] `netrun.yml`: push только `main`, PR — всё (сейчас push без `branches` + `pull_request` = два прогона на каждый пуш) / аудит 17.10, `review-pipeline.md` №1
- [ ] [nodes] `firmware.yml`: убрать `agent/**` из push (двойной прогон и двойная квота Wokwi); `firmwareHost.test.ts:21` — fail вместо skip, бинарник хоста в CI обязателен / аудит 17.10, `review-firmware.md` №2, №4
- [ ] [collector] тесты приёма `/api/changes`: конфликт `seq` (`changeIngest.ts:203`), побочный `NET_FLATLINE` (`:225`), откат батча; тест «каждый маршрут требует мастера или секрет» (`requireMaster` ×112) — самая рискованная функция без страховки / аудит 17.10, `review-collector.md` №4–5
- [ ] [android] `WireVersionTest.kt:21` сравнивать ключи, не множества; сценарий `SendOutcome.UNKNOWN` для предметов (`ItemScenariosTest.kt:37-56`, как `PaymentScenariosTest.kt:62`) / аудит 17.10, `review-android.md` №4, №9

Волна 1 (файл векторов первым, читатели следом):
- [ ] [android] общие JSON-векторы контрактов в `rules/src/test/resources/contracts/`: байты подписи записи (`ChangeRecord.kt:29`), предобраз `TX2|`/`ITEM2|` (`Mb10Qr.kt:322,335`), списки причин и полей (`ChangeFields.kt`), QR SHARD, лут-крипто; тесты app/kit читают их — формулы живут в 2–4 копиях без сверки, расхождение молча теряет денежные записи / аудит 17.10, `review-contracts.md` №3–4, `review-android.md` №1–2
- [ ] [collector] TS-тесты на общие векторы из `rules/src/test/resources/contracts/` (подпись записи, причины/поля, QR SHARD, лут-крипто) вместо копий декодера в `mb10QrCodec.test.ts:5-15` и `lootCrypto.test.ts:7-11` — после карточки Android с файлом / аудит 17.10, `review-android.md` №3
- [ ] [godot] тест Моста на общие векторы (`PhoneWire.kt:108,112`, `FakeCollector.kt:239`); `fake_bridge.gd` ↔ Kotlin-Мост на одних JSON-векторах «запрос → ответ/код»; `gray_node.gd:2021` читает `bridge.get("docs")`, у фальши поле `_docs` — позывной в карточке «ФЛЭТЛАЙН» молча подменяется ключом / аудит 17.10, `review-netrun.md` №4, `review-contracts.md` №10
- [ ] [nodes] звук в общие векторы `protocol-v1.json`: пределы 4096/36/16 КиБ литералами в `protocol.cpp:97-113` и `protocol.ts:432-446`; mock-дисплей (`mockDisplay.ts:311-430`) в набор конформанса C21+ / аудит 17.10, `review-firmware.md` №1, №3
- [ ] [android] декодер QR проверяет версию: `Mb10Qr.kt:215,246,260,266,277` (CONTAINER/SHARD/RAM/GRANT/SECALERT) — читающая сторона, формат не меняется / аудит 17.10, `review-contracts.md` №5
- [ ] [godot] `world_server.gd:100-110`: без `--bridge=` или с опечаткой — выход с ошибкой, не фикстура (на игре опечатка даёт мир на тестовых данных, ценности не доходят до Моста); проверить явный `--bridge=` в `netrun/tools/*.sh` и `scripts/e2e/up.sh` / аудит 17.10, `review-contracts.md` №6

Волна 2 (после решений владельца, см. §6):
- [ ] [godot] `capabilities`: Мост принимает `world_records`/`world_events` только при `==` (`WorldCollectorTransport.kt:118`, `WorldEventSender.kt:175`), документ обещает `≥` (`netrun-world-records.md:265`) — по решению владельца один PR Моста; до него любой подъём версии — пара PR одним поездом / аудит 17.10, `review-contracts.md` №2
- [ ] [godot] удалить режим ICE `realtime` (`node_graph.gd:34`, 19 упоминаний `_tick_mode` в `gray_node.gd`, `time-and-movement.md:217` «потом удаляется») → разбить `gray_node.gd` (2622 строки) карточками: тревога `:2321-2489`, шарды `:2490-2581`, исход `:1918-2095`, граф `:2097+`; между стендами / аудит 17.10, `review-netrun.md` №1–2
- [ ] [blender] фон спокойного узла: клиент `CALM_BG` (`rig_test_scene.gd:119`) ≠ `VOID_BG` всех превью (`asset_materials.gd:298`, `ARCHITECTURE.md`) — по решению владельца выровнять превью под клиент (Blender) или клиент под STYLE (карточка Godot) / аудит 17.10, `review-assets.md` №1
- [ ] [android] `MB10:GRANT`: читатель `Mb10Qr.kt:177` начисляет лут, писателя и документа нет — по решению владельца удалить вид (app) или кодер в Мастерской (карточка Коллектору) / аудит 17.10, `review-contracts.md` №7
- [ ] [android] `CallManager` (355 строк, без тестов): выделить чистую машину состояний (фаза, таймер, решение о рестарте ICE) и тесты — звонок самый часто чинимый узел / аудит 17.10, `review-android.md` №6

Волна 3 (дедупликация после стражей):
- [ ] [blender] `recolor()` в 6 шейдерах → `.gdshaderinc`; ручки `streak_*`/`point_keep` (`asset_materials.gd:162-167`) и `set_corruption`/`set_distance_fade` (`:481-504`) без читателей в игре; ~44 uniform'а без setter'ов; `apply()` 102 строки → таблица `MESH_RULES`; кадр до/после через `visual-reviewer` / аудит 17.10, `review-assets.md` №2–6
- [ ] [collector] одна таблица `reason → {label, gainsBalance, reward, transfer}` вместо шести списков (`integrity.ts:13`, `anomalies.ts:136`, `pulse.ts:68`, `humanize.ts:37`); `proto` константой в `net/` (`bridgeClient.ts:100`, `fakeBridge.ts:119`) / аудит 17.10, `review-collector.md` №1, №9
- [ ] [godot] четыре копии каркаса мини-игры (`vault/decrypt/charge/barrier_breach.gd`, ≈1110 строк) → базовый класс; `rig_test_scene.gd` (1327 строк — оркестратор клиента, не тест) переименовать; `layout_bots.gd`/`layout_check.gd` в `tools/` / аудит 17.10, `review-netrun.md` №3, №6–7
- [ ] [pipeline] таблица зон в 4 копиях (`CLAUDE.md`, `zone-check.sh:8-25`, `labeler.yml`, `session-brief.sh:14-24`) → `docs/zones.tsv`, остальные читают/сверяются в `lint-pipeline.sh`; единый список Gradle-задач для `check.sh`/`dbx.sh`/`main.yml` / аудит 17.10, `review-pipeline.md` №5–6
- [ ] [devbox] ssh-обвязка devbox в 12 местах с 5 наборами опций (`dbx.sh:59`, `phone.sh:19`, `check.sh:56`, `sweep.sh:21`, `box.sh:32`, `dev.sh:19`) → `scripts/lib/devbox.sh` (`dssh`, `onbox`, `unreachable`); `box/ctl.sh` 1119 строк — отложить до окна без очков / аудит 17.10, `review-pipeline.md` №7, №14

## 6. Вопросы владельцу (с рекомендацией)

1. **`capabilities`: «==» или «≥»?** Код Моста требует точного равенства, документ обещает «≥». Рекомендация: Мост шлёт при `reported ≥ SUPPORTED`,
   коллектор письменно обязуется принимать все старые версии записей; один PR Моста, коллектор не трогается. Тогда подъём версии перестаёт требовать поезда.
2. **ICE `realtime` — удалять?** Все боевые графы на тактах, документ геймдизайна помечает режим «потом удаляется». Рекомендация: да, если сравнение
   на очках закончено (П6–П9 все на tick); это открывает разбиение `gray_node.gd`.
3. **Фон узла: `VOID_BG` (превью, STYLE) или `CALM_BG` (клиент)?** Вид принимался по кадру клиента, значит клиент прав де-факто. Рекомендация: показать
   два кадра клиента и принять один; до решения превью Blender перевести на фон клиента (стенд = клиент).
4. **`MB10:GRANT` — удалить или довести?** Никто не пишет, документа нет, начисляет лут. Рекомендация: удалить (мастер выдаёт через коллектор, модель угроз дружеская).
5. **Где жить общим векторам контрактов?** Рекомендация: `rules/src/test/resources/contracts/` (зона Android, уже читается `:rules`; TS и gdUnit читают по пути,
   как сервер читает `firmware/display/test/vectors`). Альтернатива — новый каталог `contracts/` со своей зоной, но это новая строка в таблице зон.
6. **`gray_node.gd` — разбивать сейчас или после П9?** Рекомендация: после решения 2, карточками по одной ответственности, только между стендами.
7. **`PhoneWire` в `:rules` (app + Мост одной сборкой)?** Снимает дубль денежного предобраза совсем, но пара PR поездом и общая сборка. Рекомендация: отложить до
   волны 3, когда векторы волны 1 уже стерегут байты; само по себе не срочно.

## 7. Решения владельца (17.10, «все по твоим рекомендациям»)

1. `capabilities`: Мост принимает `world_records`/`world_events` при `reported ≥ SUPPORTED`; коллектор обязуется принимать старые версии записей (записать в `docs/netrun-world-records.md`). Один PR Моста (Godot), коллектор не трогается.
2. Режим ICE `realtime` — удалить (сравнение на очках закончено). Затем разбиение `gray_node.gd` карточками.
3. Фон узла — принимать по двум кадрам клиента; до решения превью Blender переводятся на фон клиента `CALM_BG` (стенд = клиент).
4. `MB10:GRANT` — удалить (app, один PR Android).
5. Общие векторы контрактов — `rules/src/test/resources/contracts/`, зона Android; TS и gdUnit читают по пути.
6. `gray_node.gd` — после п. 2, по одной ответственности на карточку, только между стендами.
7. `PhoneWire` в `:rules` — отложить до волны 3.

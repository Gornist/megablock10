# Ревью: контракты между зонами (Opus, main 47c6c157, только чтение)

## Сводка области
- Пять контрактов связывают 5 зон и 4 языка (Kotlin app/kit/rules, Kotlin netrun-bridge, TS admin-web, GDScript netrun). Общего реестра версий нет: каждая сторона объявляет константы сама, связь — комментарий «= WireVersion.CHAT приложения» или «Зеркало …».
- Межъязыковые общие векторы есть только у прошивки (`protocol-v1.json`) и у LootCrypto (литерал, списанный в оба теста). Подпись записей, `/api/changes`, карточки телефона, payload предметов, списки причин сверяются только e2e — а e2e не запускается на PR коллектора.
- Внутри Kotlin одинаковые кодеки живут дважды (app ↔ netrun-bridge), хотя оба модуля уже зависят от `:kit` и `:rules`.
- Семантика `capabilities` в коде (`==`) расходится с документом (`≥`): каждый будущий подъём версии превращается в обязательную пару PR.
- Тесты каждой стороны хорошие (WorldSyncTest, RackQrTest, BreachOpsTest, netStock.test), но проверяют сторону против своей копии контракта, а не против соседа.
- Общее впечатление: контракты аккуратно задокументированы и версионированы, слабое место — нет ни одного механизма, который ловит расхождение до ночного e2e.

## Контракты: где объявлено, где проверено, что стережёт

### 1. `/api/capabilities`
| сторона | версия | проверка | тест |
|---|---|---|---|
| Коллектор (объявляет) | `admin-web/server/src/routes/capabilities.ts:11` (`world_records: 2`), `:13` (`world_events: 1`) | — | `admin-web/server/src/worldRecords.test.ts:48` |
| Мост, записи мира | `netrun-bridge/.../collector/WorldCollectorTransport.kt:135` | `:112`, `:118` (`reported != SUPPORTED` → не шлём) | `WorldSyncTest.kt:135-151` |
| Мост, быстрые события | `.../collector/WorldEventSender.kt:251` | `:175` (`==`) | `WorldEventSenderTest.kt:108-116` |
| Приложение | не читает (полагается на `rejected` в ответе `/api/changes`) | — | — |
| Документ | `docs/netrun-world-records.md:265` («≥ 2») и `:325` («равен 2») — противоречат друг другу | | |

### 2. Записи мира (Мост → `/api/changes`)
| сторона | список полей/причин | проверка | тест |
|---|---|---|---|
| Мост (пишет) | `.../collector/WorldRecordDeriver.kt:39-49` (`object WorldRecords`) | — | `WorldRecordsTest.kt` |
| Коллектор (читает) | `admin-web/server/src/lib/changeRecord.ts:14-18`, `:41-46` | `isField`/`isReason` `:106`, `:123`; подпись `lib/changeIngest.ts:118` | `worldRecords.test.ts:136-158` |
| Подпись | kit `kit/.../sync/ChangeRecord.kt:29`; TS `lib/changeRecord.ts:90`; тестовые копии `admin-web/server/src/testUtil.ts:32`, `netrun-bridge/src/test/.../FakeCollector.kt:239` | | общего вектора нет |
| Быстрые события | `.../collector/WorldFastEvents.kt:29-38`; `admin-web/server/src/lib/worldEvents.ts:12`; `admin-web/server/src/types/worldEvents.ts:4` | | `worldEvents.test.ts` |
| Поля документа (`taken_at`) | `netrun-bridge/.../ValueOps.kt:235`, `:257`; `netrun/server/bridge/fake_bridge.gd:180`, `:212`; читатель `netrun/server/node/gray_node.gd:625` | | `BreachOpsTest.kt:452`, `netrun/tests/daemon_vault_test.gd:188` |
| Сквозной | `scripts/e2e/scenarios/netrun-run.sh:214-230` (NET_ENTER и др.) | | NET_BREACH в e2e не проверяется |

### 3. Сообщения Моста `/netrun/v1`
| сторона | версия | проверка | тест |
|---|---|---|---|
| Мост (Kotlin) | `BridgeConfig.kt:4` `NETRUN_PROTO = 1`; путь `BridgeServer.kt:297` | `BridgeServer.kt:182` (`v`), `:205` (`proto`) | `BridgeServerTest.kt` |
| Сервер мира (GD) | `netrun/server/bridge/bridge_client.gd:7` | отправка `:102`, `:159` | `netrun/tests/bridge_client_test.gd` |
| Фейк GD | `netrun/server/bridge/fake_bridge.gd` (651 строка, по умолчанию в `world_server.gd:100-110`, в solo-сборке тестеров) | — | `fake_bridge_test.gd` |
| Коллектор (TS) | литералы `admin-web/server/src/net/bridgeClient.ts:100` (`proto: 1`), `:130` (`v: 1`) | — | `net.test.ts` |
| Фейк TS | `admin-web/server/src/net/fakeBridge.ts:119` (`proto !== 1`), `:122` | | `net.test.ts` |
| Документ | `docs/netrun-bridge-protocol.md:51-75` (коды), §6 (операции) | | |

### 4. QR `MB10:…`
| вид | писатель | читатель (версия проверяется?) | тест |
|---|---|---|---|
| CONTAINER, SHARD, RAM, PROV | `admin-web/server/src/lib/mb10QrCodec.ts:19-44` | `app/.../qr/Mb10Qr.kt:214` (нет), `:245` (нет), `:259` (нет), `:291` (да) | `mb10QrCodec.test.ts` (декодер, списанный с Kotlin), `Mb10QrCodecTest.kt` |
| TX, ITEM, RCPT | app `Mb10Qr.kt:305`, `:325`, `:338`; Мост `phone/PhoneWire.kt` | `Mb10Qr.kt:308`, `:328` (да) | `ItemCardGoldenTest.kt:58` |
| SECALERT | app `Mb10Qr.kt:271`; Мост `PhoneWire.kt:89` | `Mb10Qr.kt:276` (нет) | `SecAlertRuleTest.kt:87` |
| RACK | только e2e (`scripts/e2e/scenarios/netrun-run.sh:148`, `netrun-breach.sh:144`) | `app/.../qr/RackQrCodec.kt` (да) | `RackQrTest.kt` |
| GRANT | никто | `Mb10Qr.kt:177`, `:265` (нет) → `breach/DaemonRewards.kt:96` | `ScanObjectTest.kt:14` |

### 5. Приложение ↔ коллектор
| сторона | версия/схема | проверка | тест |
|---|---|---|---|
| Приложение | `app/.../net/WireVersion.kt:35` (`REPORTED`), поля/причины `app/.../collector/ChangeFields.kt:7-45`; кодек `/api/changes` `CollectorClient.kt:63-107` (org.json) | — | `WireVersionTest.kt:20-30`; тестов `CollectorClient`/`wireVersions` нет |
| Мост (второй клиент того же API) | кодек `WorldCollectorTransport.kt:144-190` (kotlinx) | — | `FakeCollector.kt` (третья копия сервера) |
| Коллектор | `routes/changes.ts:51`, `lib/changeIngest.ts:271-282`, `lib/presence.ts:29` | ручная проверка без схем (zod не используется) | `clientVersions.test.ts`, `changeIngest.test.ts` |

## Находки

### 1. e2e не запускается на PR коллектора — единственная межъязыковая проверка контрактов 1, 2, 5
- Где: `.github/workflows/e2e.yml:14-20` (в `paths` нет `admin-web/**`)
- Что: стенд поднимает коллектор и проверяет приём записей мира (`netrun-run.sh:214-230`), но PR, меняющий `capabilities.ts`, `changeRecord.ts`, `changeIngest.ts` или подпись, его не запускает.
- Почему мешает: ровно класс сбоя §5.3 (05.10: коллектор объявил `world_records: 2` раньше Моста) — расхождение видно только ночью и краснит чужой PR.
- Выгода: высокая — одна строка закрывает весь класс.
- Риск: нет; +17 мин CI на PR коллектора (можно сузить до `admin-web/server/src/{routes,lib,net}/**`). Зона — Android (e2e.yml) по согласованию с Pipeline.
- Размер: S
- Проверить чем: `scripts/lint-pipeline.sh`; тестовый PR, трогающий `capabilities.ts`, — job E2E появляется.

### 2. `capabilities`: код требует точного равенства, документ — «≥»
- Где: `WorldCollectorTransport.kt:118`, `WorldEventSender.kt:175`; `docs/netrun-world-records.md:265` против `:325`; тест закрепляет `==` — `WorldSyncTest.kt:144`
- Что: Мост шлёт, только если коллектор объявил ровно его версию. Коллектор, умеющий v2 и v3 и объявивший 3, остановит Мост v2.
- Почему мешает: любой подъём версии — обязательная пара PR в одном поезде; между слияниями записи мира и быстрые события на точки стоят (очередь целая, но тревоги на дисплеях не идут; кэш «да» 5 мин — `WorldCollectorTransport.kt:138`). Нарушает правило CLAUDE.md «читающая сторона сначала принимает обе версии».
- Выгода: высокая — снимает принудительную пару навсегда.
- Риск: контракт. Варианты: (а) Мост `reported >= SUPPORTED` при обещании коллектора принимать все прежние версии; (б) коллектор объявляет `{min,max}`. ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА (политика совместимости), затем 1 PR Моста + правка документа.
- Размер: S
- Проверить чем: `scripts/dbx.sh --auto` (WorldSyncTest, WorldEventSenderTest).

### 3. Байты подписи записи — четыре копии без общего вектора
- Где: `kit/.../sync/ChangeRecord.kt:29`; `admin-web/server/src/lib/changeRecord.ts:90`; копии в тестах `admin-web/server/src/testUtil.ts:32`, `netrun-bridge/src/test/.../FakeCollector.kt:239`
- Что: формат «поля через |» реализован дважды в проде и дважды в тестах; тесты каждой стороны подписывают своей копией, сверочного вектора (как у LootCrypto `lootCrypto.test.ts:76`) нет.
- Почему мешает: расхождение → `invalid signature` (`changeIngest.ts:118`) → `rejected` → kit удаляет запись: тихая потеря денежных записей. Ловит только e2e (см. находку 1).
- Выгода: высокая.
- Риск: только тесты; формат не меняется. Затрагивает инварианты денег лишь как страж.
- Размер: S — файл векторов `{record, payload_hex}` + тест kit + тест TS (по образцу `firmware/display/test/vectors/protocol-v1.json`).
- Проверить чем: `admin-web/tools/test.sh server`, `scripts/dbx.sh --auto`.

### 4. Списки полей, причин и видов событий — 3 копии без сверочного теста
- Где: `app/.../collector/ChangeFields.kt:7-45`; `netrun-bridge/.../collector/WorldRecordDeriver.kt:39-49`; `admin-web/server/src/lib/changeRecord.ts:1-47`; быстрые события — `WorldFastEvents.kt:29-38`, `lib/worldEvents.ts:12`, `types/worldEvents.ts:4`
- Что: связь только комментарием «ровно те, что принимает коллектор». Незнакомая причина отвергается и удаляется у отправителя.
- Почему мешает: класс §5.10 «копии разъезжаются».
- Выгода: средняя-высокая.
- Риск: нет (тесты). Прецедент — `rules/src/test/.../BreachJsonTest.kt:67` читает файл другой зоны; аналогичный JVM-тест в `app/src/test/.../collector/` (разрешённая Android-зоне часть) и в Мосте читает `changeRecord.ts`/`worldEvents.ts` и сравнивает множества. В TS `types/worldEvents.ts:4` вывести из `WORLD_EVENT_KINDS`.
- Размер: S
- Проверить чем: `scripts/dbx.sh --auto`, `admin-web/tools/test.sh server`.

### 5. QR CONTAINER/SHARD/RAM/GRANT/SECALERT/CONTACT разбираются без проверки версии
- Где: `app/.../qr/Mb10Qr.kt:215`, `:246`, `:260`, `:266`, `:277` (против проверяющих `:292`, `:308`, `:328`)
- Что: декодер проверяет только число частей; `MB10:SHARD:v2:…` старый телефон разберёт как v1. Тир по умолчанию `toIntOrNull() ?: 1` маскирует сдвиг полей.
- Почему мешает: Мастерская не может поднять версию CONTAINER/SHARD безопасно — читающая сторона не умеет сказать «не понимаю»; SHARD несёт `moneyAmount`.
- Выгода: высокая при низкой цене.
- Риск: читающая сторона, все писатели сейчас пишут `v1` (`mb10QrCodec.ts:21,34,38`; `PhoneWire.kt:90`) — безопасно в одиночку. Затрагивает разбор лута (инварианты — только как отказ, не как начисление).
- Размер: S
- Проверить чем: `Mb10QrCodecTest`, `RackQrTest` через `scripts/dbx.sh --auto`; e2e (сканы контейнеров).

### 6. Сервер мира молча работает на фикстуре без `--bridge` или с опечаткой
- Где: `netrun/server/world_server.gd:100-110`
- Что: нет `--bridge=` → FakeBridge; неверная строка → `push_error` и всё равно FakeBridge.
- Почему мешает: на игре опечатка в запуске даёт мир на тестовых данных: взятые предметы и эдди не доходят до Моста и коллектора, никто не видит ошибки.
- Выгода: средняя.
- Риск: Godot-зона; проверить вызовы в `netrun/tools/*.sh` и `scripts/e2e/up.sh`, что везде `--bridge=` явный. Неверная строка → выход с кодом ≠ 0.
- Размер: S
- Проверить чем: `netrun/tools/dev.sh test`; `bridge_client_test.gd:89`.

### 7. `MB10:GRANT` — читатель без писателя и без документа, выдаёт ценности
- Где: `app/.../qr/Mb10Qr.kt:177`, `:265`; `app/.../breach/DaemonRewards.kt:96`; кодера нет ни в `admin-web/server/src/lib/mb10QrCodec.ts`, ни где-либо (`git grep GRANT`), в `*.md` не упоминается
- Что: «ручная выдача мастером» шарда/демона по QR, шифрованному игровым ключом или запасным ключом `LootCrypto.kt:19`.
- Почему мешает: путь начисления ценностей, которым никто не пользуется и который никто не стережёт; версия не проверяется (находка 5).
- Выгода: средняя.
- Риск: ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА (инвариант: путь, начисляющий лут): либо кодер в Мастерской + документ, либо удалить вид. Удаление — только app.
- Размер: S
- Проверить чем: `ScanObjectTest`, `scripts/dbx.sh --auto`.

### 8. QR стойки: нет производителя для игры, «подпись» двусмысленна
- Где: `docs/netrun-bridge-protocol.md:825-826` («печатается мастером»); кодер только в app `RackQrCodec.kt:16` (в проде не вызывается) и вручную в e2e `netrun-run.sh:148`, `netrun-breach.sh:144`
- Что: в Мастерской и в Мосте генератора `MB10:RACK:v1` нет; поле 7 в документе — «подпись», в коде — `label` (надпись), а в протоколе «подпись» везде — криптографическая.
- Почему мешает: к игре QR стоек собирать руками; две e2e-копии строки разъедутся с кодеком; GLOSSARY «одно слово — одно значение».
- Выгода: средняя (готовность к игре).
- Риск: новый писатель в Мастерской; читатель уже есть — коллектор в одиночку. Документ — Godot-зона.
- Размер: S
- Проверить чем: `admin-web/tools/test.sh server` (тест «кодер TS → строка из RackQrTest.kt:20»).

### 9. Payload предметов Сети: TS ↔ Kotlin без общего вектора, два формата с одним префиксом
- Где: `rules/.../ItemPayloadCodec.kt:26-29`, `:42-43` ↔ `admin-web/server/src/lib/netPayload.ts:6` (ссылка «на ветке agent/netrun» устарела); эффекты демонов `admin-web/server/src/lib/itemInput.ts:12` ↔ `rules/.../DaemonEffect.kt:8-24`; второй формат `app/.../breach/LootCodec.kt:14-19` с теми же `SHARD|`/`DAEMON|`
- Что: `netStock.test.ts:25` собирает ожидаемое своей логикой; золотая строка `RulesGoldenTest.kt:16` в TS-тест не перенесена. Список эффектов совпадает сейчас (8 = 8), но ничем не связан.
- Почему мешает: наполнение узла из Мастерской с неверным payload Мост отвергнет или выдаст битую карточку на телефон.
- Выгода: средняя.
- Риск: только тесты; переименование одного из префиксов — контракт, не трогать.
- Размер: S
- Проверить чем: `admin-web/tools/test.sh server`.

### 10. Три реализации семантики Моста без общего набора сценариев
- Где: `netrun-bridge/.../ValueOps.kt:228-257` ↔ `netrun/server/bridge/fake_bridge.gd:172-213` ↔ `admin-web/server/src/net/fakeBridge.ts:112-180`
- Что: FakeBridge (GD) повторяет take/leave/`claimed`/`protected_item`/`taken_at` и используется по умолчанию и в сборке тестеров; gdUnit проверяет сервер мира против фейка, Мост — свои тесты. Согласованность — только e2e/`netrun/tools/live_run.sh`.
- Почему мешает: правка правила в Мосте (новый код ошибки, поле документа) не ломает ни одного теста Godot — класс §5.10.
- Выгода: средняя.
- Риск: тесты; общий JSON «запрос → ожидаемый ответ» для 6.2/6.3/6.5, исполняемый gdUnit против FakeBridge и Gradle против Моста. Две зоны (Godot), одна сессия.
- Размер: M
- Проверить чем: `netrun/tools/dev.sh test`, `scripts/dbx.sh --auto`.

### 11. Кодеки линии телефона дублированы в Мосте (Kotlin ↔ Kotlin)
- Где: `netrun-bridge/.../phone/PhoneWire.kt:47-53` (версии вручную, «= WireVersion.CHAT приложения» `:48`) ↔ `app/.../net/WireVersion.kt:15-30`, `app/.../qr/Mb10Qr.kt:271-338`, `app/.../netrun/NetrunWire.kt`; золотые строки дублированы — `app/src/test/.../netrun/NetrunWireTest.kt:33` и `netrun-bridge/src/test/.../phone/PhoneWireEnterTest.kt:15`
- Что: CHAT, ITEM/TX/RCPT, ENTER/ENTERED, SECALERT собираются в двух модулях, оба зависят от `:kit` и `:rules` (`netrun-bridge/build.gradle.kts:29,31`).
- Почему мешает: денежные карточки TX/ITEM подписываются в двух местах; подъём версии чата в app не ломает Мост на сборке.
- Выгода: высокая по долгу, но дорого.
- Риск: в `docs/refactor-plan.md:214` «перенос Mb10Qr в :rules — не делали (общий с netrun)»; с тех пор Мост стал вторым потребителем — ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА (пересмотр, инварианты денег). Дешёвый первый шаг без решения: общий файл золотых строк, читаемый обоими наборами тестов.
- Размер: L (кодеки) / S (общие векторы)
- Проверить чем: `scripts/dbx.sh --full`, e2e.

### 12. Кодек `/api/changes` — два клиента на Kotlin и третий сервер в тестах
- Где: `app/.../collector/CollectorClient.kt:63-107` (org.json) ↔ `netrun-bridge/.../collector/WorldCollectorTransport.kt:144-190` (kotlinx) ↔ `netrun-bridge/src/test/.../collector/FakeCollector.kt`
- Что: kit владеет `SyncRequest`/`SyncResponse`, но не их проводным видом; каждый потребитель пишет свой.
- Почему мешает: новое поле ответа (`knownSeq`, `pending`) нужно добавить дважды; FakeCollector может разойтись с настоящим `routes/changes.ts`.
- Выгода: средняя.
- Риск: «CollectorWire — не делали» (`docs/refactor-plan.md:215`); путь синхронизации денег — ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА. У kit нет kotlinx-serialization (`kit/build.gradle.kts:42`) — правка сборки.
- Размер: M
- Проверить чем: `scripts/dbx.sh --full`, e2e `offline-sync.sh`.

### 13. Коды ошибок и литералы протокола Моста вне таблицы
- Где: `netrun-bridge/.../phone/PhoneInbox.kt:168` (`inbox_timeout` нет в `docs/netrun-bridge-protocol.md:51-75`); локальный `unavailable` — `netrun/server/bridge/bridge_client.gd:177`, `fake_bridge.gd:245`; `proto`/`v` литералами — `admin-web/server/src/net/bridgeClient.ts:100`, `:130`, `fakeBridge.ts:119`, `:122`
- Что: документ неполон; клиентский код не отличает «Мост ответил» от «Моста нет».
- Почему мешает: мелкие расхождения при подъёме `NETRUN_PROTO` (4 литерала в TS).
- Выгода: низкая.
- Риск: нет; документ — Godot, TS — Коллектор.
- Размер: S
- Проверить чем: `admin-web/tools/test.sh server`.

### 14. `wireVersions` не сообщает ENTER и VOICE, отправка не тестирована
- Где: `app/.../net/WireVersion.kt:35`; приём `admin-web/server/src/lib/presence.ts:29`; сравнение `admin-web/server/src/lib/attentionRules/fleetRules.ts:28`
- Что: телефон со старым `MB10ENTER` дашборд не пометит «Другая версия протоколов»; в `app/src/test` нет теста, что `CollectorSync` кладёт `REPORTED` в presence.
- Почему мешает: при подъёме ENTER мастер не увидит отставших телефонов.
- Выгода: низкая.
- Риск: добавление ключа безопасно (приём берёт до 8 ключей, `presence.ts:33`).
- Размер: S
- Проверить чем: `WireVersionTest`, `clientVersions.test.ts`.

## Порядок изменений
1. **Сначала стражи (любой порядок, без пар):** находка 1 (e2e на PR коллектора) — до всего остального, иначе следующие PR коллектора снова идут вслепую; затем векторы и сверки 3, 4, 9, общие золотые строки из 11 — только тесты, формат не меняют.
2. **Читающая сторона в одиночку:** 5 (версии в декодере QR — app); 6 (fallback сервера мира — Godot, вместе с проверкой скриптов запуска в том же PR); 14 (app добавляет ключи — коллектор уже принимает).
3. **`capabilities` (2):** после решения владельца. Если «Мост ≥»: один PR Моста, коллектор не трогается (объявляет 2). Если «{min,max}»: сначала Мост понимает и число, и объект, потом коллектор объявляет объект — два PR одним поездом в этом порядке. До этого **любой** подъём `world_records`/`world_events` — пара коллектор + Мост в одном поезде, иначе записи стоят.
4. **Новые писатели после читателей:** 8 (генератор RACK в Мастерской — app уже читает); 7 (GRANT — по решению: кодер в Мастерской одним PR коллектора или удаление одним PR app).
5. **Дедупликация последней (после стражей 3/4/11):** 11 и 12 — сначала общий код в `:rules`/`:kit` с тестами (Android-зона), затем переключение app, затем Моста (Godot-зона); байты не меняются, поэтому PR независимы, но каждый — с зелёным e2e. 10 — внутри Godot-зоны, когда сценарии 6.x стабильны.
6. Пары, обязанные идти поездом: подъём версии любого контракта при текущем `==` (2); перенос PhoneWire в `:rules`, если делать одним шагом (app + netrun-bridge в одном Gradle-сборке).

## Чего нет
- Единого источника версий контрактов (как `protocol-v1.json` у прошивки) для подписи записей, карточек телефона, payload предметов, `/api/changes`.
- PR-проверки «настоящий Мост ↔ BridgeClient.gd» и «настоящий Мост ↔ bridgeClient.ts»: только ночной e2e и ручной `live_run.sh`.
- Сквозной проверки `NET_BREACH`/`net.breach` в e2e (`git grep NET_BREACH scripts/e2e` пусто) — версия 2 контракта 1 сквозь стенд не проверена.
- Поправки к досье §2.3: таблица кодов документа не полна (`inbox_timeout`); `run.summary` — событие журнала клиента (`netrun/client/solo_stub.gd:273`), не сообщение Моста.

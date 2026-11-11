# Ревью области Android (app/, kit/, rules/) — аудит рефакторинга 17.10.2026

## Сводка области

- Размер: app main 208 kt / 17,8 тыс. строк, kit 23 файла / 1 840, rules 20 файлов / 0,9 тыс.; тестов около 160 + 19 + 9 файлов. Самый большой Kotlin-файл — ChatScreen.kt, 531 строка; файлов больше 600 строк нет. Функций больше 80 строк в main две: `AppRoot()` (MainActivity.kt:106, 148 строк) и ничего другого — следующая 74 строки (VoiceUi.kt:197).
- Архитектура после этапов A–E чистая: экраны получают данные через ViewModel (ChatScreen.kt без сетевых вызовов, только три `LaunchedEffect` на UI-события), сборка ViewModel — расширения `AppGraph.xxxViewModel()` (di/ViewModels.kt, 88 строк), `LocalAppGraph` читают только `ViewModels.kt`-фабрика (ui/LocalAppGraph.kt:22) и 2 класса вне UI. Деньги идут через `PaymentLedger`/`ItemLedger` + общий `kit Handover`; `SendOutcome.UNKNOWN` проверен тестом на платеже (PaymentScenariosTest.kt:62-72) и в kit (PeerTableTest.kt:186, HandoverRulesTest.kt:28).
- Карточка неточна: `PeerDirectory`/`PeerTable` в kit покрыты (PeerDirectoryTest, PeerTableTest 262 строки). Без JVM-тестов остались `ChatServer` (в app, не в kit), `MeshSession`, `PresenceService`, `CallManager`, `CollectorSync`, `HeadsetRuntime`, `DenoisedClipRecorder`.
- Реальный остаток долга — не размер файлов, а **границы между зонами и языками**: суммы, подписи и причины записей объявлены в 2–3 местах (app, Мост, TS) без общего источника и без сверочных тестов; плюс несколько нетестируемых «нервных узлов» (звонок, взлом в composable, порядок запуска сессии).
- Тестовая гигиена хорошая: `Thread.sleep` только в 2 тестах (VoiceAutoplayRoomTest, HeadsetHandshakeTimeoutTest), `runTest` 271 раз против `runBlocking` 83, `ManualClock` введён (коммиты 975c6d0f, 40172088).
- Общее впечатление: крупный рефакторинг Android не нужен; нужны 5–6 точечных карточек на контракты и тестируемость. Прошлые «Не делали» (разбиение AppGraph, CallRules, перенос Mb10Qr) ниже предложены только там, где есть новая причина.

## Находки

### 1. Предобраз подписи денег и предметов (`TX2|`, `ITEM2|`) и разбор карточек — в двух Kotlin-модулях без общего эталона
- Где: `app/src/main/java/com/megablok10/app/qr/Mb10Qr.kt:322` (`TX2|`) и `:335` (`ITEM2|`) ↔ `netrun-bridge/src/main/kotlin/com/megablok10/netrun/bridge/phone/PhoneWire.kt:112` и `:108`; эталонные строки только на стороне app: `app/src/test/java/com/megablok10/app/items/ItemCardGoldenTest.kt:43,47`.
- Что: Мост (собирает и подписывает карточки в телефон) и приложение (проверяет) хранят одни и те же форматы и байты подписи копиями; в тестах Моста строк `TX2|`/`ITEM2|` нет вообще (grep по `netrun-bridge/src/test` пуст). Третья копия — TS `mb10QrCodec.ts`.
- Почему мешает: расхождение даёт «карточка не принимается / подпись не сходится» у игроков — класс 3 и 10 из досье (копии протоколов разъезжаются). Мост и app уже зависят от общих `:kit`/`:rules` (netrun-bridge/build.gradle.kts:29,31; app/build.gradle.kts:194,196), так что общий источник возможен.
- Выгода: высокая — закрывает дрейф в денежном контракте.
- Риск: вариант «только эталонные векторы» (файл строк в `rules/src/test/resources/`, читают тесты app и Моста) — риск нулевой, 0 строк прод-кода. Вариант «перенос `Mb10Qr`/подписи в `:rules`» (пункт «не делали» refactor-plan E) трогает формат денег — **ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА** и согласования с зонами Godot/Коллектор. Новая причина вернуться: три копии вместо двух, и Мост уже зависит от `:rules`.
- Размер: S для эталонов; L для переноса.
- Проверить чем: `scripts/dbx.sh -- :app:testDebugUnitTest --tests '*ItemCardGoldenTest*' :netrun-bridge:test`.

### 2. Закрытый список причин записей (`ChangeReason`) — три копии, сверки нет, сервер отвергает неизвестное
- Где: `app/.../collector/ChangeFields.kt:26-44` (18 причин) ↔ `netrun-bridge/.../collector/WorldRecordDeriver.kt:43-49` (NET_*) ↔ `admin-web/server/src/lib/changeRecord.ts:22-47` (24 строки); отказ на приёме — `admin-web/server/src/lib/changeIngest.ts:110` (`unknown reason`). То же для `ChangeField` (`ChangeFields.kt:7-23`).
- Что: добавление причины в Kotlin без правки TS молча даёт постоянный отказ записи у мастера. Тест `meta.test.ts:9` сверяет только TS с подписями на русском, но не с Kotlin.
- Почему мешает: класс 3 (версия/значение объявлено раньше приёма); запись мастера теряется, а не падает громко.
- Выгода: высокая для денег/ленты мастера; дёшево.
- Риск: низкий — только тест/JSON-файл-контракт; обе стороны читают, ничего не пишут в прод. Чужая зона (Коллектор): карточкой.
- Размер: S.
- Проверить чем: `scripts/check.sh --fast` (kit/сервер) + `admin-web/tools/test.sh server` + `dbx.sh` для app.

### 3. Лут-крипто и QR-кодек: «эталон» в TS-тесте — это ещё одна копия декодера, шифртекст сверялся вручную
- Где: `admin-web/server/src/mb10QrCodec.test.ts:5-15` (комментарий: декодер «скопирован сюда как эталон»); `admin-web/server/src/lootCrypto.test.ts:7-11` («кросс-проверка с javax.crypto была сделана вручную»); общий вектор есть только для ключа: `app/src/test/.../breach/LootCryptoTest.kt:99-103` (hex `232aab80…`).
- Что: формат AES-GCM (iv‖ct‖tag) и разбор QR контейнера/шарда не имеют общего известного ответа (known-answer) для обеих сторон.
- Почему мешает: класс 10; сломанный лут/QR найдут на площадке, а не в CI.
- Выгода: средняя — дёшево закрывает «молча разъедется».
- Риск: низкий (тесты). Тест трогает зону Коллектора (TS) — карточкой соседу.
- Размер: S.
- Проверить чем: `LootCryptoTest` + `admin-web/tools/test.sh server`.

### 4. `WireVersion.REPORTED` не содержит voice/enter; сверочный тест слабый
- Где: `app/src/main/java/com/megablok10/app/net/WireVersion.kt:35` (REPORTED: chat, call, claim, read, to) против `:38` (SUPPORTED: ещё VOICE, VOICE_LISTENED, ENTER, ENTERED); тест `app/src/test/.../net/WireVersionTest.kt:21` сравнивает только **множества значений** (`values.toSet()`), поэтому добавленный протокол с версией 1 его не заденет. Мост хранит версии вручную: `PhoneWire.kt:48,52,53` (`// = WireVersion.CHAT приложения`).
- Что: дашборд мастера не видит версии голосовых и входа в Сеть (две последние волны протоколов), а тест, который должен это ловить, это пропускает.
- Почему мешает: класс 3; узнать, у кого старое приложение с несовместимым голосом, нельзя.
- Выгода: средняя.
- Риск: **поле `wireVersions` — контракт с Коллектором** (`changeIngest.ts:271-282`, `presence.ts:29`): сервер сначала должен принимать новые ключи; тест `clientVersions.test.ts` проверить. Читающая сторона уже принимает «разумные значения» — вероятно безопасно, но проверить.
- Размер: S.
- Проверить чем: `WireVersionTest`, `admin-web/tools/test.sh server`.

### 5. Ход взлома живёт в composable: таймер, исход, отладочный автосолвер
- Где: `app/src/main/java/com/megablok10/app/breach/BreachScreen.kt:279` (`run` в `remember`), `:307-331` (`LaunchedEffect(seed)` с `delay(1000)`-тиком и `resolveOnce`), `:284,315` (`DebugConfig.autoSolve` в релизном коде); `BreachViewModel.kt` — 65 строк, ведёт только доступ и завершение. Логика самой попытки чистая и в `:rules` (`BreachRun`), тестируется (BreachRunTest).
- Что: результат (`onResult` → `FinishBreach` → лут/эдди/СБ) зависит от корутины в композиции; состояние попытки и seed не переживают пересоздание активности (в manifest нет `configChanges`, `rememberSaveable` в breach/ нет; ориентация зафиксирована portrait, но смена масштаба шрифта/темы пересоздаёт Activity).
- Почему мешает: ни тик, ни «исход ровно один раз» не покрыты JVM-тестом; потеря незавершённой попытки при пересоздании — гипотеза, проверить на устройстве.
- Выгода: средняя (тестируемость денежного пути + устойчивость).
- Риск: средний — путь `FinishBreach` меняет баланс/лут (инварианты денег: запись в одной транзакции); перенос тика во ViewModel не должен менять момент вызова `onResult`. **ТРЕБУЕТ РЕШЕНИЯ ВЛАДЕЛЬЦА** только если меняется поведение при пересоздании.
- Размер: M.
- Проверить чем: `BreachRunTest`, `BreachViewModelTest`, `scripts/dbx.sh --auto`, e2e-сценарий взлома.

### 6. `CallManager` (355 строк) без собственных тестов; звонок — самый часто чинимый узел
- Где: `app/src/main/java/com/megablok10/app/call/CallManager.kt:64` (конструктор), `:131-175` (`onIceState`/`startRecoveryWatch`/`restartIce`), `:284` (`scheduleRingTimeout`); в тестах есть только фейк `FakeCallControls` (`app/src/test/.../testing/Fakes.kt:306`).
- Что: за 09–10.2026 в `call/` 20 коммитов, часть — перезапуск ICE и «висит СОЕДИНЯЕТСЯ» (2e17d581, 8189614a); состояние звонка проверяется только e2e и руками.
- Почему мешает: каждая правка звонка уходит на 17-минутный e2e или на телефоны; ещё и WebRTC 150 (cadfc5ca) обновили без юнит-покрытия.
- Выгода: средняя; пункт `CallRules`/`CallMediaPort` в «Не делали» — причина была «нет тестов, риск», новая причина: частота правок и обновление WebRTC.
- Риск: средний — выделение чистой машины состояний (фаза, таймер звонка, решение «рестартовать ICE») без изменения сигналов; `CallSignal` и `WireVersion.CALL=2` не трогать.
- Размер: M.
- Проверить чем: новый `CallRulesTest` в `:app` + e2e звонка.

### 7. Порядок запуска сессии (`srv.start` → `wifi.start`) защищён только комментарием и e2e
- Где: `app/src/main/java/com/megablok10/app/chat/MeshSession.kt:104` (`srv.start`), `:111` (`wifi.start`), `:112` (`presence.start`); конструктор принимает конкретные классы (`MeshSession.kt:39-60`: `PresenceService`, `WifiBinder`, `CallManager`); аналогично `PresenceService.kt:39` (Android `NsdManager`, 304 строки, 6 `catch Exception` с `@Suppress`).
- Что: инвариант из `.claude/rules/app-invariants.md` («сервер строк открывается до привязки к Wi-Fi», сбой e2e run 36209401543) не имеет юнит-теста; `MeshSession`/`PresenceService`/`CollectorSync`/`MainActivity` — 0 тестовых файлов.
- Почему мешает: класс 6/8 (сбои стенда e2e), регрессию увидят через 17 минут и не по причине.
- Выгода: средняя.
- Риск: низкий–средний: нужны узкие интерфейсы (`PresencePort`, `WifiPort`) и тест порядка вызовов на фейках; поведение не меняется. Пункт про `CollectorWire`/`CollectorSync` в «Не делали» не затрагивается.
- Размер: M.
- Проверить чем: новый `MeshSessionOrderTest` + `SessionGuardTest` (уже есть).

### 8. Новый протокол — правки в трёх местах (ChatServer, MeshSession, WireVersion)
- Где: `app/src/main/java/com/megablok10/app/chat/ChatServer.kt:37-61` (10 параметров-колбэков, 7 `LineRoute`), `chat/MeshSession.kt:82-99` (те же колбэки), `net/WireVersion.kt:35-38`.
- Что: за две недели добавлены `voice`, `voice_listened`, `entered` — каждый раз 3 файла и конструктор с дефолтными `{}`; забыть зарегистрировать маршрут (дефолт `{}`) молча «проглатывает» строку после `ACK`.
- Почему мешает: класс 3 (потеря входящего без ошибки). Это не God-объект, а «шов регистрации».
- Выгода: низкая–средняя.
- Риск: средний — инвариант «обработчик возвращается после сохранения» (`app-invariants.md`) должен сохраниться; список маршрутов вместо параметров = переписать `ChatServer` и `AppGraph`.
- Размер: S–M. Делать только вместе с находкой 7.
- Проверить чем: `ChatServer`-тест на фейках + `LineServerTest`.

### 9. Контракт «UNKNOWN = могло дойти» для предметов не проверен на уровне сценария
- Где: `app/src/test/java/com/megablok10/app/items/ItemScenariosTest.kt:37-56` (только offline/missing/accept), в отличие от `wallet/PaymentScenariosTest.kt:62-72`; код — `app/.../items/ItemTransferStore.kt:86` (`deliverOutgoing` → `handover.deliver`).
- Что: правило проверено в kit (HandoverRulesTest.kt:28) и на деньгах, но связка `SendItem` → `ItemLedger` → откат/не откат для предметов в сценарии не гоняется.
- Почему мешает: дубль предмета у обоих игроков — тот же класс потерь, что и у денег.
- Выгода: средняя; дёшево.
- Риск: нулевой (тест).
- Размер: S.
- Проверить чем: `dbx.sh -- :app:testDebugUnitTest --tests '*ItemScenariosTest*'`.

### 10. `Thread.sleep` и реальные часы в `VoiceAutoplayRoomTest`
- Где: `app/src/test/java/com/megablok10/app/voice/VoiceAutoplayRoomTest.kt:62-67` (`waitFor` по `System.currentTimeMillis()` + `Thread.sleep(20)`, предел 5 с), `:96` и `:106` (`Thread.sleep(200)` как «ждём, что ничего не произойдёт»).
- Что: отрицательные утверждения «следующий клип не пошёл» держатся на 200 мс реального времени; на загруженном devbox они дают ложный зелёный или краснеют по таймауту.
- Почему мешает: единственный заметный источник флака в Android-тестах (других `Thread.sleep` в app кроме HeadsetHandshakeTimeoutTest нет). В последних 300 коммитах слов «flaky» нет — риск гипотетический.
- Выгода: низкая.
- Риск: нулевой.
- Размер: S.
- Проверить чем: `*VoiceAutoplayRoomTest*` 10 раз подряд на devbox.

### 11. Прослойка совместимости `BreachAliases` и «Mock» в боевом коде
- Где: `app/src/main/java/com/megablok10/app/breach/BreachAliases.kt:1-26` (20 typealias «чтобы не менять импорты»), `breach/Tier.kt`, `breach/DaemonEffect.kt`; `breach/MockBreach.kt:11-22` используется в проде: `items/ItemTransferStore.kt:150`, `breach/DaemonStore.kt:34`, `breach/BreachScreen.kt:215`.
- Что: переходный слой после выноса логики в `:rules` (bdccd69c) остался навсегда; `MockBreach.daemons` — стартовый демон игрока, а имя говорит «заглушка».
- Почему мешает: путает читателя (два одноимённых `Tier.kt` в `:app` и `:rules` — досье §3) и скрывает, что `BreachParams` и др. живут в `:rules`.
- Выгода: низкая.
- Риск: низкий, но шумный — механическая правка импортов в ~30 файлах app и тестах; остальные 9 файлов уже импортируют `com.megablok10.rules` напрямую. Можно делать скриптом, `scout`.
- Размер: S.
- Проверить чем: `scripts/dbx.sh --auto` (компиляция + detekt).

### 12. `AppGraph` — композиционный корень на 333 строки / ~55 публичных `val`, а не God-объект экранов
- Где: `app/src/main/java/com/megablok10/app/di/AppGraph.kt:116` (класс), читают целиком: `di/ViewModels.kt` (расширения), `MainActivity.kt`, `Mb10App.kt:3` обращений, `call/CallActionReceiver.kt:3`.
- Что: граф растёт с каждой фичей (сейчас 78 членов), но экраны от него изолированы. Читателей с нулём у публичных `val` не найдено (проверено грепом по всем членам).
- Почему мешает: только ростом конструктора; разбиение уже в «Не делали», новой причины нет.
- Выгода: низкая.
- Риск: высокий для порядка инициализации (`lines` ссылается на `presence` до его объявления, `AppGraph.kt:125`).
- Размер: L — **не рекомендую**; максимум сделать `private`/`internal` те поля, которые читает только `ViewModels.kt` (S).
- Проверить чем: `dbx.sh --auto`.

### 13. Осиротевший KDoc в денежном коде
- Где: `app/src/main/java/com/megablok10/app/wallet/TransactionStore.kt:120-124` — блок «Фиксирует платёж по чеку получателя…» стоит над `deliveredUnconfirmed` (`:125`), а описывает `verifyAndConfirmReceipt` (`:128`).
- Что: комментарий не к той функции, оригинальная `verifyAndConfirmReceipt` без документации.
- Почему мешает: читающий деньги агент понимает инвариант «после чека отмена невозможна» неверно.
- Выгода: низкая.
- Риск: нулевой (комментарий).
- Размер: S (одна строка).
- Проверить чем: `scripts/check.sh --fast`.

## Чего нет

- Больших файлов и функций: ничего больше 531 строки, нет функций больше 150 строк (кроме `AppRoot`).
- Мёртвых ручек: `BuildConfig.DEFAULT_COLLECTOR_URL` (2 читателя), `ALLOW_MANUAL_SETUP` (2), `DebugConfig` (читается в 3 файлах), `BreachSfx.isEnabled` — у всех есть читатели; публичные `val` `AppGraph` без читателей не найдены.
- Сетевых вызовов в `LaunchedEffect` экранов (ChatScreen.kt: 3 эффекта, все на состояние UI) и baseline detekt (`app/detekt-baseline.xml` без записей).
- Дубля между app и kit: общий код (PeerTable, LineServer, Handover, ChangeRecorder) уже в kit; app содержит только typealias-шимы (находка 11).
- Флака по истории: слов «flaky/падал» в последних 300 коммитах нет; `Thread.sleep` только в двух тестах.
- Не проверялось (вне бюджета): `HeadsetMirror`/`HeadsetRuntime` (2 тестовых файла на 1282 строки кода headset), `DenoisedClipRecorder` (273 строки, 0 тестов, JNI-RNNoise).

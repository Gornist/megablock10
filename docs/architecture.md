# Архитектура Android-приложения

Документ для тех, кто будет менять приложение или собирать на его основе другое. Как это работает для игрока — в
[README](../README.md), протоколы сети — в [network-spec.md](network-spec.md), база — в [db-migrations.md](db-migrations.md).

## Модули

| Модуль | Что это | Зависит от |
|---|---|---|
| `:kit` | Ядро без Android и без игры: журнал, подписи и шифрование, строки по TCP, пиры и очередь исходящих, передача ценностей, синхронизация с мастерским сервером. [kit/README.md](../kit/README.md). | Kotlin, корутины |
| `:rules` | Правила игры без Android, общие для приложения и Моста «Сети»: тиры, демоны, движок и параметры взлома, кодек предмета в карточке, решение о сигнале СБ; в тестовых ресурсах — общие векторы контрактов. [rules/README.md](../rules/README.md). | `:kit` |
| `:app` | Приложение: хранилища (Room, SharedPreferences), Android-обвязка (NSD, Wi-Fi, сервисы, WebRTC), экраны на Compose. | `:kit`, `:rules` |
| `:netrun-bridge` | Мост «Сети» (Kotlin/JVM, сессия Godot); с приложением связан форматами сообщений, не кодом. | `:kit`, `:rules` |
| `admin-web/` | Дашборд-коллектор (Node); с приложением связан только форматами записей и HTTP. | — |

Границу `:kit` проверяет сборка: ни Android, ни классов приложения, Animal Sniffer не пускает API новее Android 8.0 (так же в `:rules`).
В приложении то же сторожит Android Lint (`:app:lintDebug`, `NewApi` в том числе; старые находки — `app/lint-baseline.xml`).

Сборка: minSdk 26, compileSdk 37, **targetSdk 35** (решение владельца; 36 — отдельной правкой с проверкой экранов). Из-за него интерфейс
всегда под системными панелями: `MainActivity.enableEdgeToEdge`, отступы ставят `MbAppShell` (`statusBars`, `imePadding`, у нижнего меню
`navigationBars`) и экраны вне оболочки (`safeDrawing`: `SetupScreen`, `ProfileScreen`), `CallOverlay` — `statusBars`, `AppSnackHost` —
`navigationBars`; «Назад» во вложенных потоках — `BackHandler`.

## Слои внутри приложения

```
 Компоненты интерфейса     ui/theme/Mb*, MbAppShell; ui/nav (AppTab, ShellBadges)   данные приходят параметрами
      │
 Compose-экраны            ui/screens/*Screen.kt, MainActivity (AppRoot)        рисуют состояние, зовут действия ViewModel
      │ appViewModel { … }
 ViewModel                 ui/SessionViewModel, ShellViewModel, ui/screens/*ViewModel, breach/BreachViewModel
      │                    состояние экрана (StateFlow); долгие действия — в processScope
 Сценарии (use cases)      wallet/SendPayment, AcceptPayment, items/SendItem, AcceptItem,
      │                    identity/CreateCharacter, breach/CheckBreachAccess, FinishBreach
      │                    поток из нескольких шагов, одинаковый для интерфейса и стенда e2e
 Хранилища и сервисы       *Store, ContactDirectory, CallManager, MeshSession, PresenceService …
      │                    свои данные и инварианты (баланс не уходит в минус, предмет не у двоих)
 kit + Android + Room      ChangeRecorder, SyncEngine, Handover, LineServer, Outbox, PeerDirectory …
```

Зависимости идут только сверху вниз. Хранилище не ходит в сеть: карточку перевода доставляет сценарий, а не `TransactionStore`.

Пакеты `app/` — по фичам: `chat/`, `voice/`, `call/`, `wallet/`, `items/`, `shards/`, `breach/`, `identity/`, `qr/`, `collector/`, `announce/`,
`presence/`, `session/`, `netrun/` + `headset/` («Сеть»: вход через Мост, очки Pico), `data/` (Room), `net/` (`WireVersion`), `di/`, `ui/`.
`netrun/` и `headset/` ведёт сессия Godot ([netrun.md](netrun.md), [netrun-phone-link.md](netrun-phone-link.md)), `collector/` — Коллектора
([admin-web/README.md](../admin-web/README.md)); Android правит там только тесты (контракт с сервером).

### Корень композиции — `di/AppGraph`

Все долгоживущие объекты создаются в `di/AppGraph.kt` (его создаёт `Mb10App.onCreate`, он один на процесс); внедрение ручное, без
фреймворка, зависимости — через конструктор. Android-компоненты берут граф через `context.appGraph`. Экраны — `val vm = appViewModel {
walletViewModel() }` (фабрики в `di/ViewModels.kt`, хелпер в `ui/LocalAppGraph.kt`); экземпляров несколько — ключ: `appViewModel(key =
"thread:$me:$peer") { … }`. Компоненты дизайн-системы и всё, что рисуют скриншот-тесты, граф не трогают.

### Интерфейс: `ui/theme` и `ui/nav`

`ui/theme` — дизайн-система по [ux/ui-style-guide.md](ux/ui-style-guide.md): компоненты `Mb*` (`MbButton`, `MbField`, `MbBubble`, `MbListItem`,
`MbTabs`, `MbDialog`, `MbTile`, `MbTag` и др.), токены (`MbColors`, `MbDimens`, `MbTypography`, `MbChamfer` — скошенные углы, `MbIcons`,
`MbFormat`), оболочка `MbAppShell`, `MbBreach` и `AppSnack` (реализация порта `PlayerNotices`). Компонент берёт данные параметрами —
поэтому его снимают скриншот-тесты (`KitCatalogTest`); прямоугольные рамки запрещает `NoRectangularBordersTest`. `ui/nav` — `AppTab` и
`ShellBadges` (счётчики на иконках; локальная отметка «видел», не сетевое «прочитано»).

### ViewModel

- Состояние — `StateFlow`; потоки из базы — `stateIn(viewModelScope, WhileSubscribed(5 с))`, экран собирает `collectAsStateWithLifecycle()`.
- ViewModel живёт, пока жива Activity, поэтому всё, что привязано к персонажу, реагирует на смену личности: ключ из `IdentityStore.state`
  (`ChatViewModel`) или ключ ViewModel с ключом личности (`BreachViewModel`, треды).
- **Долгие действия — в `processScope`, не в `viewModelScope` и не в корутине экрана.** Перевод, приём, передача предмета, итог взлома,
  выдачу и сброс персонажа нельзя бросать на полпути: ушёл игрок с экрана — деньги дописываются, чек уходит. Скоуп приходит параметром
  `work`; результат экрану — `StateFlow` или колбэк на главном потоке. Короткие сообщения игроку — порт `PlayerNotices`.

### Сценарии (use cases)

Класс-глагол с одним `suspend operator fun invoke`; нужен, когда действие запускают из разных мест (экран, стенд e2e через `DebugQrReceiver`,
уведомление): e2e проверяет тот же код, что нажимает игрок. Зависимости — порты: `wallet/PaymentLedger` (`TransactionStore`),
`items/ItemLedger` (`ItemTransferStore`; ещё `NetrunEntry`), `chat/DirectMessenger` (`ChatStore`), `call/CallControls` (`CallManager`),
`PlayerNotices` (`AppSnack`). Группа связанных операций — интерфейс; одна операция — функция (`cooldowns::remainingCooldownMs` в
`CheckBreachAccess`, `FinishBreach`).

### Хранилища

`*Store` владеют данными (Room, SharedPreferences) и инвариантами. Проверка и запись — одной транзакцией (`recordOutgoingPending` проверяет
баланс и списывает внутри неё). Изменения для мастера пишутся тем же вызовом через `ChangeRecorder` внутри той же транзакции: данные и
запись фиксируются одним коммитом, seq выдаётся там же (таблица `sequences`). Транзакции — через `AppGraph.transactor` (kit `Transactor`,
`data/RoomTransactor`), не `db.withTransaction`: вложенные вызовы присоединяются к внешней, синхронизация просыпается после коммита. Всё,
после чего уходит подтверждение (серверу, другому телефону), пишется синхронно — транзакцией или `commit()`, не `apply()`. Личность пока в
SharedPreferences (`identity_prefs`, реактивна: `IdentityStore.state`), остальное — в Room (схема 17), поэтому операции через оба хранилища
(выдача по QR, RAM-апгрейд) доделываются после падения процесса при запуске (`AppGraph.resumeInterruptedWork` → `resumeInterrupted`);
убрать окно можно только переносом личности в Room (C1 в [refactor-plan.md](refactor-plan.md)).

### Сетевая сессия — `chat/MeshSession`

Пока на телефоне есть персонаж, работают сервер строк (`ChatServer` поверх kit `LineServer`, порт `CHAT_PORT` 47100: адрес игрока — его IP,
перезапуск его не меняет), NSD, привязка к Wi-Fi площадки, foreground-сервис, очередь исходящих и фоновые задачи (отложенные сигналы СБ,
связь с очками, снимки состояния). Что запущено, решает `session/SessionController`; события — старт процесса, личность (подписка в
`processScope` с запуска, не из экрана: иначе после перезапуска процесса системой без Activity приём не работал бы), открытие экрана,
сброс (`SessionReset`). Сеть — один раз на ключ (правки мастера её не перезапускают), синк — один раз на процесс, foreground-сервис —
вместе с сетью (из фона система может не пустить — поднимет экран). Таблица правил — `SessionControllerTest`, «никто другой не запускает»
— `SessionGuardTest` (читает текст `AppGraph`, граф поэтому не дробят).

`ChatServer` разбирает строки по `LineRoute` (chat, call, claim, read, voice, voice_listened, entered — ответ Моста). Конверт `LineEnvelope`
проверяет адресата до обработки; получатель отвечает `ok <ключ>` / `wrong <ключ>`: `ok` — доставлено, `wrong` — там другой игрок (следующий
адрес), закрыто без ответа — старая версия, нет ответа после записи — `UNKNOWN`. Чек из сети сразу подтверждает перевод или передачу
(`ReceiptConfirmer`), где бы ни был игрок.

- `presence/` — NSD и Wi-Fi: чистая логика (`NsdSlot` — регистрация и поиск по одной операции, `NsdResolveQueue` — разрешение по одному, до
  Android 14 параллельные падают `FAILURE_ALREADY_ACTIVE`, `NsdRefreshGate`) и тонкие вызовы Android. `WifiBinder` привязывает процесс к
  Wi-Fi площадки (сервер строк открывается до привязки: сокет, открытый после неё, умирает вместе с сетью), `MeshLink` — гейт взлома.
  `MeshForegroundService`: Android 14+ `specialUse` (у `dataSync` на 15 лимит 6 ч/сутки), на 10–13 `dataSync`; служба звонка — `microphone`.
- Адресация — kit `PeerDirectory`: `online` (игрок один раз, без адреса), `send(ключ, строка)`, `sendToAll`; `PeerInfo` с host/port не выходит
  за `presence/` и `collector/`. `PeerTable` держит адреса по ключу игрока: свежее событие первым, `NOT_REACHED` — в конец, адрес из
  входящих (`heard`) переносится к ответившему.
- `chat/`: `MessageStatus` (в `data/ChatMessageEntity.kt`) только вверх — не ушло, ушло, доставлено, прочитано; `ReadReceipts`; `OutboxPolicy` —
  что можно ставить в очередь (деньги и предметы — нет). `voice/`: голосовые `MB10VOICE`, «прослушано» `MB10LISTEN`, запись с шумодавом.

## Потоки данных

- **Деньги и предметы (Handover).** Сценарий → хранилище списывает и ставит PENDING одной транзакцией → подписанная карточка (`TX v2`,
  `ITEM v2`) уходит `DirectMessenger.deliverCard` по kit `Handover`: DELIVERED ставится до отправки, откат только при `NOT_REACHED`;
  `UNKNOWN` («могло дойти») остаётся DELIVERED, отмена невозможна (так же для предметов). Получатель проверяет подпись и адресата, шлёт
  подписанный чек `RCPT v1`; `ReceiptConfirmer` фиксирует перевод.
- **Звонки.** `CallManager` исполняет, `CallRules` решает (исход по фазе, OFFER/ANSWER, тайм-аут вызова, `CallUiState` — чистые функции без
  WebRTC); `IceRecoveryPolicy` — перезапуск ICE и исход LOST. Сигналы `MB10CALL` идут через `PeerDirectory`, медиа — WebRTC (`CallMedia`).
- **QR и выдача персонажа.** Все QR разбирает `Mb10QrCodec` в `Mb10Qr`: CONTACT, CONTAINER, SHARD, RAM, SECALERT, RCPT — только `v1`, иная версия
  → null; PROV — v1, TX и ITEM — v2 (v1 денег и предметов не принимается). `MB10:PROV` → `ProvisionStore.apply`. Без камеры: код `ABC-DEF`
  (`qr/ProvisionCode`) → `CollectorClient.redeemProvisionCode` (`POST /api/provisions/redeem`) → тот же QR → тот же `apply`; код в журнал не
  пишется. Контракт — [provisioning-qr.md](provisioning-qr.md).
- **Коллектор.** `ChangeRecorder` (подпись ключом игрока, очередь в Room) → `SyncEngine` шлёт пачки `POST /api/changes`, получает правки
  мастера (`MasterChangeHooks` применяет без эха) и подтверждает их; в heartbeat уходят `wireVersions`. Тиражный лут арбитрирует сервер
  (`SlotClaimStore`).
- **«Сеть».** Стойка (QR `Rack`) даёт ключ мира и адрес Моста (статический пир). `NetrunEntry` отдаёт Мосту карточки демонов обычными
  передачами предметов, затем подписанный `MB10ENTER`, ждёт подписанный `MB10ENTERED`; добычу от ключа мира принимает `WorldAutoAccept`.
  Очки Pico: телефон — WebSocket-клиент (`headset/HeadsetRuntime`, пока идёт сессия), отдаёт им звуки и голос звонка.

## Протоколы и контракты

Первая строка сообщения — `МАГИЯ:vN:…`; декодер принимает ТОЛЬКО свою версию, несовпадение при известной магии сообщается игроку.
Версии — `net/WireVersion` (все 1, кроме `CALL` 2 и `ENTER` 2: запрос, записанный до обновления, уходит как v1, Мост принимает обе). Дашборду уходит
`REPORTED` (chat, call, claim, read, to, voice, enter — 7 ключей, предел коллектора 8); `MB10LISTEN` и `MB10ENTERED` не сообщаются
сознательно (`WireVersionTest`).

Подпись записи, строки карточек и крипто лута живут в нескольких копиях (приложение, Мост, коллектор), поэтому у них общие известные ответы,
посчитанные независимо от Kotlin: `rules/src/test/resources/contracts/*.json` (`change-record`, `cards`, `qr`, `loot-crypto`, `provision-code`,
`bridge-ops`; кто что читает — README в той папке). Приложение читает их тестами `app/src/test/.../contracts/`, коллектор и Мост — своими. Файл
правится только вместе с форматом, по правилу «Контракт между зонами» из [CLAUDE.md](../CLAUDE.md): сначала читающая сторона. Числа взлома
(`netrun/data/rules/breach.json`) общие с Godot, их сверяют тесты `:rules`.

## Куда класть новое

| Хочу… | Куда |
|---|---|
| правило игры без ввода-вывода | чистая функция или `object` рядом с фичей (`BalanceRules`, `CallRules`), тест без фейков; нужно Мосту — `:rules` |
| новые данные на телефоне | Entity + DAO в `data/`, миграция ([db-migrations.md](db-migrations.md)), `*Store` в пакете фичи |
| действие из нескольких шагов | сценарий в пакете фичи, зависимости — порты, тест с фейками из `app/src/test/.../testing/Fakes.kt` |
| новый экран | `XxxScreen` + `XxxViewModel` в `ui/screens/`, фабрика в `di/ViewModels.kt`, данные ниже экрана — параметрами |
| элемент интерфейса для нескольких экранов | `Mb*` в `ui/theme/` на токенах, без графа; сначала [прототип](ux/prototype/mb10-ui-kit.html), потом Compose и снимок в `KitCatalogTest` |
| вкладка, счётчик нижнего меню | `ui/nav` (`AppTab`, `ShellBadges`) |
| то, что работает «пока есть персонаж» | событие в `session/SessionController`, не вызов из экрана или `Application` (`SessionGuardTest`) |
| NSD или Wi-Fi | чистая логика без Android (как `NsdSlot`) и тест; `PresenceService`/`WifiBinder` — только вызовы Android |
| протокол между телефонами | формат и версия в пакете фичи и в `WireVersion` (+ `WireVersionTest`), маршрут `LineRoute` в `ChatServer` |
| новый вид QR | вариант `Mb10Qr`, ветка `Mb10QrCodec.decode`, вектор в `contracts/qr.json` |
| поле для мастера | константа в `collector/ChangeFields.kt` (строка общая с сервером), запись через `ChangeRecorder`, вектор в `change-record.json` |
| новый объект на процесс; пригодится другому приложению | строка в `AppGraph`; в `:kit` — если нет ни Android, ни игры |

## Что нельзя менять без согласования

По этому работают телефоны игроков с данными, сервер и стенд e2e:

- имена файлов настроек (`identity_prefs`, `collector_prefs`, `announcements`, `netrun_prefs`, `chat_prefs`) и схема Room (только миграциями);
- форматы строк в сети, QR и записях для сервера: меняете — поднимаете версию (`WireVersion`) и общий вектор;
- теги и имена событий журнала (`Mb10Log`, `LogFormat`): контракт — `scripts/e2e/log-contract.tsv` + `LogContractTest`;
- строки `MB10DBG` в `DebugQrReceiver` (`port=`, `pay id=`, `give id=`, `recv -> …`, `set applied: Identity(…)`): их разбирает `scripts/e2e/lib.sh`.

## Тесты

Порядка 665 тестов в `app`, 148 в `kit`, 39 в `rules`. Kit — JUnit, виртуальное время, настоящие сокеты (`LineAckTest`). Правила и контракты —
чистые функции, golden-наборы, `contracts/`, `WireVersionTest`, `CallRulesTest`. Сценарии (`PaymentScenariosTest`, `ItemScenariosTest`,
`BreachScenariosTest`) — фейки портов (`testing/Fakes.kt`) поверх настоящего `Handover` и подписей. Хранилища и база — наследники `testing/RoomTest`
(Room в памяти под Robolectric: откаты, сбой посреди операции `failOnSign`, `restart()`), `MigrationDataTest`, `MigrationGuardTest`. Сессия и сеть —
`SessionControllerTest`, `SessionGuardTest`, `Nsd*Test` (`ManualNsdScheduler`, `ManualClock`, `testPeerDirectory`). Интерфейс — `screenshots/*` в
отдельной JVM Paparazzi (эталоны `app/src/test/snapshots`). Целиком — `scripts/e2e`: `DebugQrReceiver` ходит через те же сценарии, что экран.

Без JVM-тестов `ChatServer`, `MeshSession`, `PresenceService`, `CallManager`, `CallMedia` (их проверяют e2e и телефоны; чистые решения вынесены
в `CallRules`, `NsdSlot` и др.). JVM-тесты не должны звать реализацию Android API: в CI там заглушки `android.jar`, и они бросают исключение;
интерфейсы можно (фейк `SharedPreferences` — `MemoryPrefs`). Значения для сервера собираются без `org.json` (`counterValue`).

## Переиспользование в другом приложении

Подключите `:kit` ([kit/README.md](../kit/README.md)), реализуйте его порты своим хранилищем (`ChangeQueue`, `OutboxQueue`, `OutgoingJournal`,
`CollectorTransport`; образцы для Room — `RoomChangeQueue`, `RoomOutboxQueue`, `TransactionJournal`), слои приложения берите за образец.

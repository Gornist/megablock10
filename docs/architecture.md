# Архитектура Android-приложения

Документ для тех, кто будет менять приложение или собирать на его основе другое. Как это работает для игрока — в
[README](../README.md), протоколы сети — в [network-spec.md](network-spec.md), база — в [db-migrations.md](db-migrations.md).

## Модули

| Модуль | Что это | Зависит от |
|---|---|---|
| `:kit` | Переиспользуемое ядро без Android и без игры: журнал, подписи и шифрование, строки по TCP, пиры и очередь исходящих, протокол передачи ценностей, синхронизация с мастерским сервером. Подробно — [kit/README.md](../kit/README.md). | только Kotlin и корутины |
| `:app` | Приложение «Мегаблок №10»: игровые правила, хранилища на Room и SharedPreferences, Android-обвязка (NSD, Wi-Fi, сервисы, уведомления, WebRTC), экраны на Compose. | `:kit`, AndroidX |
| `admin-web/` | Мастерский дашборд-коллектор (Node), с приложением связан только форматами записей и HTTP. | — |

Граница `:kit` проверяется сборкой: kit не видит ни Android, ни классы приложения, а Animal Sniffer не пускает API новее
Android 8.0. В приложении то же сторожит Android Lint (`:app:lintDebug`, полный набор проверок — уровень API (`NewApi`) в
том числе, старые находки в `app/lint-baseline.xml`, как у detekt).

## Слои внутри приложения

```
 Compose-экраны            ui/screens/*Screen.kt, MainActivity (AppRoot)        рисуют состояние, зовут действия ViewModel
      │ appViewModel { … }
 ViewModel                 ui/SessionViewModel, ui/screens/*ViewModel, breach/BreachViewModel
      │                    состояние экрана (StateFlow), действия; долгие действия — в processScope
 Сценарии (use cases)      wallet/SendPayment, AcceptPayment, items/SendItem, AcceptItem,
      │                    identity/CreateCharacter, breach/CheckBreachAccess, FinishBreach
      │                    поток из нескольких шагов, одинаковый для интерфейса и стенда e2e
 Хранилища и сервисы       *Store, ContactDirectory, CallManager, MeshSession, PresenceService …
      │                    свои данные и свои инварианты (баланс не уходит в минус, предмет не у двоих)
 kit + Android + Room      ChangeRecorder, SyncEngine, Handover, LineServer, Outbox, PeerTable …
```

Зависимости идут только сверху вниз. Экран не знает, из чего собрана его ViewModel. Сценарий не знает про экраны.
Хранилище не ходит в сеть: карточку перевода доставляет сценарий, а не `TransactionStore`.

### Корень композиции — `di/AppGraph`

Все долгоживущие объекты создаются в одном месте, `di/AppGraph.kt`. Его создаёт `Mb10App.onCreate`, и он один на процесс.
Остальной код получает зависимости через конструктор. Внедрение ручное, без фреймворка: граф небольшой, читается сверху
вниз и одинаково работает в тестах.

- Android-компоненты (приёмники, сервисы) берут граф через `context.appGraph`.
- Экраны берут свои ViewModel: `val vm = appViewModel { walletViewModel() }`. Фабрики лежат в `di/ViewModels.kt`, хелпер
  `appViewModel` — в `ui/LocalAppGraph.kt`. Если экземпляров нужно несколько, передаётся ключ, например тред на каждую пару
  ключей: `appViewModel(key = "thread:$me:$peer") { … }`.
- Компоненты дизайн-системы и всё, что рисуют скриншот-тесты, граф не трогают: данные приходят параметрами.

### ViewModel

- Состояние — `StateFlow`. Потоки из базы подключаются через `stateIn(viewModelScope, WhileSubscribed(5 с))`, экран
  собирает их через `collectAsStateWithLifecycle()`: подписка живёт, пока экран виден, и переживает поворот.
- ViewModel живёт, пока жива Activity: она переживает поворот и переключение вкладок. Значит, всё, что привязано к
  персонажу, должно реагировать на смену личности (сброс сессии без перезапуска). Для этого есть два способа: брать ключ
  персонажа из `IdentityStore.state` (как `ChatViewModel`) или использовать ключ ViewModel с ключом личности (как
  `BreachViewModel` и треды).
- **Долгие действия — в `processScope`, а не в `viewModelScope` и не в корутине экрана.** Перевод, приём, передача
  предмета, итог взлома, выдача и сброс персонажа нельзя бросать на полпути. Если игрок ушёл с экрана, деньги должны
  дописаться и чек должен уйти. ViewModel получает этот скоуп параметром `work`. Если результат нужен экрану, он
  приходит через `StateFlow` или колбэк на главном потоке.
- Короткие сообщения игроку идут через порт `PlayerNotices` (реализация — `AppSnack`), а не прямо из доменного кода.

### Сценарии (use cases)

Сценарий — класс-глагол с одним `suspend operator fun invoke`. Он собирает поток из нескольких хранилищ и сети. Сценарий
нужен, когда одно и то же действие запускается из разных мест: из экрана, из стенда e2e (`DebugQrReceiver` в debug-сборке
ходит через те же сценарии) или из уведомления. Так e2e проверяет тот же код, что нажимает игрок.

Зависимости сценария — порты, а не конкретные классы:

| Порт | Реализация | Кто пользуется |
|---|---|---|
| `wallet/PaymentLedger` | `TransactionStore` | `SendPayment`, `AcceptPayment`, `ReceiptConfirmer`, `WalletViewModel` |
| `items/ItemLedger` | `ItemTransferStore` | `SendItem`, `AcceptItem`, `ReceiptConfirmer` |
| `chat/DirectMessenger` | `ChatStore` | сценарии передачи, `DirectThreadViewModel` |
| `call/CallControls` | `CallManager` | `CallsViewModel` |
| `PlayerNotices` | `AppSnack` | ViewModel, `MasterChangeHooks` |
| одна операция — функция | метод хранилища (`cooldowns::remainingCooldownMs`) | `CheckBreachAccess`, `FinishBreach` |

Правило: если нужна группа связанных операций, порт делается интерфейсом; если одна операция — функцией.

### Хранилища

`*Store` владеют своими данными (Room, SharedPreferences) и инвариантами. Проверка и запись идут одной транзакцией
(`recordOutgoingPending` проверяет баланс и списывает внутри транзакции). Изменения, о которых должен узнать мастер,
хранилище записывает тем же вызовом через `ChangeRecorder` из kit — внутри той же транзакции: данные и запись о них
фиксируются одним коммитом, номер записи (seq) выдаётся там же (таблица `sequences`). Все транзакции открываются через
`AppGraph.transactor` (kit `Transactor`), а не `db.withTransaction` напрямую: вложенные вызовы присоединяются к внешней
транзакции, а синхронизация просыпается только после её коммита. Всё, после чего уходит подтверждение (серверу, другому
телефону), пишется синхронно — транзакцией Room или `commit()`, не `apply()`. Операции, которые охватывают и Room, и
SharedPreferences (выдача по QR, RAM-апгрейд), доделываются после падения процесса при запуске (`AppGraph.resumeInterruptedWork`). `IdentityStore` реактивен (`state`): правки мастера,
создание и сброс персонажа видны экранам сразу.

### Сетевая сессия — `chat/MeshSession`

Пока на телефоне есть персонаж, работают сервер строк (`ChatServer` поверх kit `LineServer`), NSD (`PresenceService`),
привязка к Wi-Fi площадки, foreground-сервис, досылка очереди исходящих и фоновые задачи сессии (отложенные сигналы СБ,
снимки состояния в журнал). Что запущено, решает `session/SessionController` (B3): события — старт процесса
(`AppGraph.startSession` из `Mb10App.onCreate`), личность (подписка в `processScope` с момента запуска, не из экрана: иначе после
перезапуска процесса системой без Activity приём не работал бы), открытие экрана и сброс сессии (`SessionReset`). Сеть — один раз
на ключ, правки мастера её не перезапускают; синк — один раз на процесс; foreground-сервис — вместе с сетью, из фона система может
не пустить — тогда его поднимет экран. Таблица правил — `SessionControllerTest`, «никто другой не запускает» — `SessionGuardTest`.
Приём чека, пришедшего по сети, сразу подтверждает
перевод или передачу (`ReceiptConfirmer`), где бы ни был игрок в интерфейсе.

## Куда класть новое

| Хочу… | Куда |
|---|---|
| новое правило игры без ввода-вывода (формула, проверка) | чистая функция или `object` рядом с фичей (`BalanceRules`, `DecryptRules`), тест без фейков |
| новые данные на телефоне | Entity + DAO в `data/`, миграция ([db-migrations.md](db-migrations.md)), хранилище `*Store` в пакете фичи |
| действие из нескольких шагов | сценарий в пакете фичи, зависимости — порты, тест с фейками из `app/src/test/.../testing/Fakes.kt` |
| новый экран | `XxxScreen` + `XxxViewModel` в `ui/screens/`, фабрика в `di/ViewModels.kt`, данные ниже экрана — параметрами |
| новый протокол между телефонами | формат и версия в пакете фичи (как `ChatProtocol`, `WireVersion`), маршрут в `ChatServer` (`LineRoute`) |
| новое поле для мастера | константа в `collector/ChangeFields.kt` (строка общая с сервером), запись через `ChangeRecorder` |
| что-то, что пригодится другому приложению | в `:kit`, если в этом нет ни Android, ни игры; иначе — в приложение, а в kit — только механику |
| новый объект на процесс | одна строка в `AppGraph` в правильной секции; зависимости — через конструктор |

## Что нельзя менять без согласования

По этим вещам работают телефоны игроков с данными, сервер и стенд e2e:

- имена файлов настроек и ключей (`identity_prefs`, `collector_prefs`, `announcements`) и схема Room (только миграциями);
- форматы строк в сети, QR и записях для сервера; меняете формат — поднимаете версию (`net/WireVersion.kt`);
- теги и имена событий журнала (`Mb10Log`, `LogFormat`): по ним разбирают журналы живых проверок;
- строки `MB10DBG` в `DebugQrReceiver` (`port=`, `pay id=`, `give id=`, `recv -> …`, `set applied: Identity(…)` и др.):
  их разбирает `scripts/e2e/lib.sh`.

## Тесты

| Уровень | Где | Чем |
|---|---|---|
| kit | `kit/src/test` | JUnit, виртуальное время корутин, настоящие сокеты, фиксированные векторы форматов |
| правила игры | `app/src/test/.../<фича>` | чистые функции |
| сценарии | `…/wallet/PaymentScenariosTest`, `items/ItemScenariosTest`, `breach/BreachScenariosTest` и др. | фейки портов (`testing/Fakes.kt`) поверх настоящего kit `Handover` и настоящих подписей: проверяются реальные переходы статусов |
| ViewModel | `…/ui/*ViewModelTest` | `MainDispatcherRule` (главный поток на тестовом диспетчере), `work` — скоуп теста |
| база | `data/MigrationDataTest`, `MigrationGuardTest` | миграции на настоящем SQLite |
| хранилища | наследники `testing/RoomTest` (`ChangeRecordTransactionsTest`, `InterruptedIssueTest` и др.) | настоящая Room в памяти под Robolectric: транзакции, откаты, сбой посреди операции (`failOnSign`), перезапуск (`restart()`) |
| интерфейс | `screenshots/ScreenshotTest` | Paparazzi |
| целиком | `scripts/e2e` | два эмулятора и сервер; `DebugQrReceiver` ходит через те же сценарии, что интерфейс |

JVM-тесты не должны звать реализацию Android API: в CI на их месте заглушки `android.jar`, и они бросают исключение.
Можно пользоваться интерфейсами (фейк `SharedPreferences` — `MemoryPrefs`). Значения для сервера собираются без
`org.json` (`counterValue`), чтобы сценарии проверялись обычными тестами.

## Переиспользование в другом приложении

Для другой игры или приложения со схожей логикой (офлайн-сеть на площадке, личность на ключах, передача ценностей
между участниками, мастерский сервер):

1. Подключите `:kit` ([kit/README.md](../kit/README.md), раздел «Как подключить»). Вся механика там: сеть без сервера,
   протокол передачи с чеками, журнал изменений с синхронизацией, пиры и очередь исходящих.
2. Реализуйте порты kit своим хранилищем (`ChangeQueue`, `OutboxQueue`, `OutgoingJournal`, `CollectorTransport`).
   Образцы для Room — `RoomChangeQueue`, `RoomOutboxQueue`, `TransactionJournal`.
3. Возьмите за образец слои приложения: корень композиции (`AppGraph`), сценарии поверх портов, ViewModel с долгими
   действиями в скоупе процесса. Сценарии перевода (`SendPayment` / `AcceptPayment`) переносятся почти без изменений:
   достаточно заменить формат карточки.

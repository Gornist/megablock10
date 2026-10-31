# Передача: Android-приложение

Для сессии «Android App» и всех, кто продолжит работу над приложением: что устроено и почему, на какие решения владельца опирается
дизайн, что проверено и что нет, грабли, долги. Как устроен код — [architecture.md](architecture.md), ядро без Android — [kit/README.md](../kit/README.md),
правила для агентов — [CLAUDE.md](../CLAUDE.md) (корень) и `.claude/rules/` (`app-invariants.md` — деньги и транзакции: читать до правки `app/`, `kit/`).
Текущее состояние работ — [progress.md](progress.md), очередь — [backlog.md](backlog.md).

## Коротко

- Три модуля: `:app` (Android), `:kit` (ядро без Android и без игры: сеть на площадке, подписи ECDSA P-256, HKDF, AES-GCM, передача
  ценностей, движок синхронизации с коллектором), `:rules` (чистая логика игры: взлом, лут, сигнал СБ, формат предметов).
- Слои приложения: корень композиции `di/AppGraph` → хранилища и сервисы → сценарии (use cases) → ViewModel → Compose-экраны.
  Глобальных объектов с `Context` нет; долгие действия (перевод, взлом, выдача) идут в скоупе процесса, а не экрана.
- Форматы в сети, QR и на сервере, имена файлов настроек, теги и события журнала, строки `MB10DBG` для стенда e2e — контракт: меняются
  только по правилу «Контракт между зонами» из CLAUDE.md.
- Минимальный Android — 8 (API 26). В `kit` нельзя вызывать то, чего нет в API 26 (например, `PrintWriter` с `Charset` — только с API 33,
  из-за этого отправка падала на Android 8–12): границу сторожат Animal Sniffer (`:kit:animalsnifferMain`) и Android Lint `NewApi`.
- Модель угроз — **дружеская игра** (решение владельца 25.09, README, «Доверие к балансу»): подписи мастера на QR, реестр ключей игроков,
  подписи сообщений чата, звонков, сигналов СБ и presence не делаем. Если модель угроз поменяется — это первое, что делать.

## Сборка и платформа

- compileSdk 37, minSdk 26, **targetSdk 35** (владелец 19.10 выбрал 35, не 36: APK ставится в обход Play, требования магазина к targetSdk
  не касаются; 36 — отдельной правкой с проверкой экранов). Kotlin 2.4, AGP 9.2.1, Gradle 9.4.1, Compose BOM 2026.09 (Compose 1.12),
  lifecycle 2.11, Paparazzi 2.0.0-alpha05.1, Robolectric 4.17, WebRTC `io.github.webrtc-sdk:android` 150.7871.01 (`org.webrtc:google-webrtc` мёртв).
  Kotlin встроен в AGP: плагин `kotlin.android` не подключается, версию KGP задают `kotlin.plugin.compose` и `kotlin.jvm` в корневом
  `build.gradle.kts`. С AGP 9 юнит-тесты есть только у Debug (`testReleaseUnitTest` нет).
- **targetSdk 35 = edge-to-edge всегда:** `MainActivity.enableEdgeToEdge`; `MbAppShell` — `statusBars` сверху, `imePadding`, `navigationBars` у нижнего меню;
  вне оболочки `SetupScreen` и `ProfileScreen` — `safeDrawing`; плашка звонка (`CallOverlay`) — `statusBars`; `AppSnackHost` — `navigationBars`.
  «Назад»: `BackHandler` во вложенных потоках (профиль, чат, кибердека). Новый экран обязан сам учитывать отступы.
- `MeshForegroundService` (живёт всю сессию персонажа — иначе фоновый процесс замораживается и чат/звонки встают): на Android 14+ тип
  `specialUse` (у `dataSync` на 15 лимит 6 ч/сутки), на Android 10–13 `dataSync`; в манифесте оба типа и оба разрешения. `CallForegroundService` — `microphone`.
  Процесс без экрана (перезапуск системой, broadcast) на Android 12+ не может запустить foreground-сервис — исключение ловит
  `MeshForegroundService.start`: сеть работает без сервиса, открытие приложения поднимает его.
- **APK для телефонов** — `.github/workflows/apk.yml`: на каждый push в `main` (артефакт 30 дней) и по тегу `v*` (ещё GitHub Release), имя
  с коротким хешем коммита. Подпись постоянная — из секретов Actions `ANDROID_KEYSTORE_BASE64/_PASSWORD`, `ANDROID_KEY_ALIAS/_PASSWORD`
  (все четыре или ни одного; без них — случайный debug-ключ раннера, в сводке job об этом сказано, поверх установленного такой APK не встанет).
  Первый переход на постоянный ключ требует один раз удалить приложение с телефона. Сборка остаётся debuggable. `main.yml` тоже кладёт
  debug-APK, но подпись у него случайная.
- Android Lint — полный набор; то, что прямо противоречит решениям проекта (`ApplySharedPref`, `InsecureBaseConfiguration`,
  `LockedOrientationActivity`/`DiscouragedApi`, `ExportedReceiver` у debug-only `DebugQrReceiver`, `GradleDependency`), отключено с комментарием
  в `app/build.gradle.kts`; старые находки — в `app/lint-baseline.xml` (обновить: `:app:updateLintBaseline`), у detekt — `app/detekt-baseline.xml`.

## Сеть без догадок

Решения владельца 25.09: эмуляторы — свидетель логики приложения, а не mDNS; адрес игрока не должен меняться; проверка «ключ + IP»;
отметки «доставлено / прочитано» с переключателем, как в мессенджерах. Этапы B и D — [refactor-plan.md](refactor-plan.md).

- **Адресация — одно место:** kit `PeerDirectory` держит все адреса игрока (история NSD, подсказка сервера — запасной адрес), рабочий — первым.
  Личные сообщения, карточки, рассылка фракции, переотправка, очередь исходящих и звонки (`CallManager`) пробуют адреса по очереди и идут дальше
  только после `NOT_REACHED` (строка точно не ушла). Причина: запись NSD после перезапуска чужого приложения хранила порт прошлого процесса
  (`ECONNREFUSED`), хотя рабочий адрес был известен, — отсюда плавающие e2e `item-transfer` и `sec-alert`.
- **Постоянный порт 47100/TCP** — перезапуск приложения не меняет адрес игрока; порт в сети площадки должен быть открыт.
- **Порядок `ServerSocket` ↔ `bindProcessToNetwork`** (урок ночи 25→26.09): сервер строк открывается **до** привязки к Wi-Fi, сокет, открытый после,
  помечен сетью и умирает вместе с ней (не принимал через `emu redir`); порядок в `MeshSession.start` задан явно; страховка — сбой `accept` переоткрывает тот же порт.
- **Конверт `MB10TO:v1` «кому/от кого» и ответ `MB10ACK`:** «доставлено» = сохранено у того самого игрока; адрес берётся из входящих. Строки старых
  телефонов новые принимают как раньше; новые → старые: ответа нет, исход «могло дойти» (личные сообщения ждут в очереди, деньги — чек).
  На игре у всех одна сборка.
- **Статусы своих личных сообщений:** «…» / «✓» / «✓✓» / «✓✓» цветом («прочитано» — отчёт из открытого треда; переключатель «Отчёты о прочтении» в Настройках).
- **NSD:** не пересоздаётся без смены сети/IP (лишние перезапуски теряли регистрацию); операции по одной (`NsdSlot`), найденные разрешаются по одному
  (`NsdResolveQueue`, Android до 14).
- **Кто что запускает в фоне — `session/SessionController`** (сеть, обмен с коллектором, foreground-сервис). События ему шлют процесс
  (`onProcessStarted`), личность (`onIdentity`), экран (`onUiStarted`) и сброс сессии (`onSessionReset`); без экрана записи для мастера уходят, правки приходят.
  Тесты `SessionControllerTest`, `SessionGuardTest`.

## Данные и надёжность (аудит 25.09)

Внешний аудит (P0/P1/P2) проверен по коду: факты в основном подтвердились, часть приоритетов завышена под модель «игроки взламывают приложение»
(см. «Коротко»). Исправлены сбои, гонки и потери данных. Как теперь писать код, трогающий данные (подробнее — [architecture.md](architecture.md), «Хранилища»):

- Все транзакции — через `AppGraph.transactor` (kit `Transactor`, `tx.inTransaction { … }`), не `db.withTransaction` напрямую. Запись для мастера
  (`changes.record`) делается внутри той же транзакции, что и изменение; seq записей живёт в таблице `sequences`, а не в SharedPreferences.
- Всё, после чего уходит подтверждение (серверу, другому телефону), пишется синхронно: Room-транзакция или `commit()`, не `apply()`.
  Приём и отмена передачи предмета атомарны; old/new баланса читается внутри транзакции.
- Правка мастера подтверждается только после применения; отказ уходит серверу с причиной (`MasterApply`, `MasterOverride.parse`), после 5 отказов сервер
  перестаёт слать («Правка не применилась на телефоне»). Подтверждение несёт `appliedAtSeq` — старая офлайн-запись, пришедшая позже, правку не откатывает.
- Слот лута заявляется только после расшифровки и проверки содержимого; выдача по QR и RAM-апгрейд доделываются после падения процесса
  (`resumeInterruptedWork` при старте).
- Журнал подтверждённых записей (`accepted_change_records`, 6 часов): после восстановления сервера из копии телефон по `knownSeq` досылает потерянное.
  Правки мастера и объявления после момента резервной копии досылать некому — их повторяет мастер (admin-web/README, «Резервные копии»).
- `CardResender`: карточка перевода/предмета в DELIVERED без чека через минуту уходит адресату снова, тем же сообщением (у получателя повтор — дубль).
- «Требует внимания»: один шард отсканировали несколько игроков — копия QR.
- **Новая схема Room:** `app/schemas/<версия>.json` собирает Room при сборке (сейчас 17); в облачной сессии без Android SDK хэш считается вручную по алгоритму Room,
  `ExportedSchemaIdentityTest` подтверждает верность. Миграции — [db-migrations.md](db-migrations.md).
- Тесты на настоящей Room — наследники `testing/RoomTest` (Robolectric); сбой посреди операции моделирует `failOnSign`, перезапуск процесса — `restart()`.

## Выдача персонажа и QR

- Контракт выдачи — [provisioning-qr.md](provisioning-qr.md) и [character-reissue.md](character-reissue.md) (зона Коллектора; здесь только читатель).
  Пакет `collector/` в приложении — граница с Коллектором, правки только по контракту.
- **Ввод кода без камеры:** на экране первого запуска под сканером «Нет камеры? Ввести код» (все сборки). `qr/ProvisionCode.kt` — 6 знаков из 31-знакового
  алфавита (A–Z без I, L, O и цифры 2–9), вид `ABC-DEF`, нормализация (регистр, пробелы, «-»); `CollectorClient.redeemProvisionCode` —
  `POST {baseUrl}/api/provisions/redeem {"code"}` → `{"qr":"MB10:PROV:v1:…"}`, дальше обычный `ProvisionStore.apply`; `SessionViewModel.redeemCode`.
  Адрес сервера — из настроек, иначе поле «Адрес сервера»; 404 без тела или иной код = «сервер не поддерживает ввод кода»; 429 = лимит;
  сам код в журнал не пишется. Сервер объявляет `provisionCode: 1` в `/api/capabilities`.
- **Декодер `qr/Mb10Qr.kt`:** CONTACT/CONTAINER/SHARD/RAM/SECALERT/RCPT/PROV читаются только как `v1`, TX и ITEM — только `v2` (v1 денег и предметов не принимается);
  иная версия → null. **`MB10:GRANT` удалён** (читатель начислял лут без писателя и документа); `CollectedKind` = `{ Shard }`.
- **Общие JSON-векторы контрактов:** `rules/src/test/resources/contracts/*.json` (README в папке): запись изменений (байты подписи), карточки TX/ITEM/RCPT,
  QR (с разделом `rejected`), крипто лута, короткий код, `bridge-ops.json` (Мост; приложение его не читает). Приложение читает их тестами
  `app/src/test/.../contracts/`, Коллектор — в TS-тестах, Мост — в своих; значения посчитаны независимо от Kotlin. Файлы правятся только вместе с форматом.
- **`WireVersion.REPORTED`** (уходит коллектору в `wireVersions`): chat, call, claim, read, to, voice, enter; `MB10LISTEN` и `MB10ENTERED` — явный «известный пропуск»;
  `WireVersionTest` сверяет версии по ключам. `ItemScenariosTest` покрывает `SendOutcome.UNKNOWN` (UNKNOWN = «мог дойти» → остаётся DELIVERED, отмена невозможна), как у денег.
- Живая выдача на телефон — `scripts/phone.sh prov|provlive|qr|install|shot|ui|taptext|tap|log` (шапка скрипта); стенд на двух телефонах — [live-test-plan.md](live-test-plan.md).

## Звонки, голос, очки

- `call/CallRules.kt` — чистые решения звонка (исход по фазе, OFFER/ANSWER, таймаут вызова, переходы `CallUiState`) без WebRTC, `CallManager` только исполняет
  (`CallRulesTest`); `IceRecoveryPolicy` — перезапуск ICE, исход LOST. Экран гаснет у уха (`CallProximityGuard`), «Завершить» со второго нажатия (`EndCallConfirmation`).
- **Шумодав RNNoise** — [app/docs/call-denoise.md](../app/docs/call-denoise.md): в звонках по умолчанию; в записи голосовых — `DenoisedClipRecorder` (AudioRecord 48 кГц →
  RNNoise → 16 кГц → MediaCodec AAC), запасной `MediaRecorder` (`voice.record_fallback`).
- **Голосовые сообщения** — [app/docs/voice-messages.md](../app/docs/voice-messages.md): протокол `MB10VOICE v1`, запись и проигрыватель по образцу Telegram, предел 60 с,
  отчёт «прослушано» (`MB10LISTEN`), синие ✓✓. Расшифровка в текст отложена (решение владельца 07.10): позже через Whisper на Коллекторе, Vosk на телефоне — запасной.
- **VPN на телефонах ломает голос в звонках** (ICE CHECKING) — проверять без VPN.
- Очки Pico: связь телефона с очками (`headset/`) и голос звонка в очках — [netrun-phone-link.md](netrun-phone-link.md) (зона Godot). Вход в Сеть из приложения — `netrun/`.
- Взлом: параметры тира (таймеры, замок хранилища, запас буфера, приманки) — `rules/` (`BreachConstants`); числа лежат в `netrun/data/rules/breach.json` (общий файл с Godot)
  и сверяются тестами `:rules`; перегенерировать — `UPDATE_NETRUN_JSON=1` через `dbx.sh --env`.

## UI на дизайн-системе

Экраны игрока на системе [ui-style-guide.md](ux/ui-style-guide.md) (прототип [mb10-ui-kit.html](ux/prototype/mb10-ui-kit.html), процесс — [ui-migration-plan.md](ux/ui-migration-plan.md));
старая дизайн-система удалена целиком, возвращать её имена (`AppButton`, `MB10Colors`, `chamferShape`, `ChamferedSurface`, `Jura`, …) не нужно. Открыто на усмотрение
владельца: яркость на улице и самый маленький из игровых телефонов.

- Компоненты `Mb*` в `ui/theme/` на токенах и типографике гайдлайна; шрифты Fira Sans Condensed + IBM Plex Mono (статичные TTF в `res/font`, лицензии — `docs/ux/font-licenses/`).
  Оболочка — `MbAppShell`; `ui/nav` — `AppTab` и `ShellBadges`.
- Скриншот-тесты — `screenshots/*`: каталог компонентов `KitCatalogTest`, масштаб шрифта 1,3× `FontScaleTest`, взлом на самом маленьком экране `SmallScreenBreachTest`;
  `NoRectangularBordersTest` не пускает прямоугольные рамки. UI собирается из готовых компонентов, не из одноразовых.

## Проверки

- **Что есть:** тестов по `@Test` — app ≈660, kit ≈150, rules ≈40. CI (`main.yml`): detekt, Android Lint, Animal Sniffer, unit-тесты, Paparazzi, сборка APK, admin-web; строка
  «тестов N, прошло N» в журнале. Тяжёлое — на devbox (`scripts/dbx.sh --auto|--full`, skill `devbox`), не на Mac с 8 ГБ.
- **e2e на двух эмуляторах** (`e2e.yml`, ≈17–19 мин; на PR в `main` с правкой `app/`, `kit/`, `rules/`, `netrun*/`, `scripts/e2e/`, `admin-web/server/**` без `*.test.ts`; ночью; вручную):
  `scripts/e2e/up.sh && scripts/e2e/run-all.sh` (устройство стенда — [scripts/e2e/README.md](../scripts/e2e/README.md)). Сценарии — `scripts/e2e/scenarios/` (в том числе `message-status`,
  `voice`, `rnnoise`, `netrun-breach`, `wifi-bind`) и `scenarios-anomaly/`. Ждать результат (`eq_wait`, `await` в `lib.sh`), не `sleep`. Стенд одноразовый: после `zz-provisioning`
  следующий `run-all.sh` — только после `./down.sh && ./up.sh`. `up.sh` держит общий замок очереди devbox до `down.sh`; перед каждым сценарием проверяется связь эмуляторов
  с сервером. `netrun-breach`: остывание читается по слоту хранилища (`node_07_pk0`). Падение — сначала журналы, skill `debug-journals`.
- **Devbox** переустановлен начисто 25.10: `dbx.sh` работает через клон `~/megablock10`; Gradle-кэши и `~/wt-dbx-*` пусты (первый прогон — десятки минут). Образы эмуляторов
  e2e (system-images) и AVD **не ставились** — доставить через `sdkmanager` (`~/android-sdk/cmdline-tools/latest/bin`); стенд на 5554/5556 и коллектор :2517 поднимать заново;
  `~/live-collector` (живой коллектор :2527) не сохранён. Брони устройств — `scripts/box.sh lease|release|leases`, подробности — [devbox.md](devbox.md).
- **Телефоны:** XCover7 (Android 16, adb через devbox) и Xiaomi; RCPad — отдельный проект владельца, в Мегаблок не входит. На XCover7 19.10 проверено: targetSdk 35,
  служба specialUse, экраны без наездов, чат с клавиатурой. План живой проверки — [device-testing.md](device-testing.md).
- **Не проверено на живых телефонах:** входящий звонок и диалог объявления под edge-to-edge; Android 14 и 10–13; живая запись голосовых с RNNoise; NSD между 5+ устройствами,
  роуминг Wi-Fi, правка мастера телефону без связи, обновление поверх старой версии (миграции Room), нагрузка на 100 устройств (стенд — два эмулятора). Эмулятор не покажет
  NSD между устройствами, звонок целиком и роуминг.

## Известные ограничения и долги

- ViewModel живут, пока жива Activity; экземпляры с ключом (тред на пару ключей, взлом на персонажа) копятся до её закрытия — памяти почти не занимают.
- Не сделано по решению владельца (дружеская игра): см. «Коротко». Не сделано из P2 аудита: ключ игрока в Android Keystore; запасной ключ лута без `GAME_SECRET`
  в боевой сборке; признак «стартовый демон» в сущности вместо сравнения с `MockBreach` (`ItemTransferStore.isTransferable`); лимиты длины полей в протоколах чата
  и звонков; `PeerTable` по ключу игрока, а не по имени NSD-сервиса.
- Аудит рефакторинга 17.10 (план вне git): сделаны общие векторы, версия в декодере QR, удаление GRANT, `CallRules`, `wireVersions`, тесты UNKNOWN. **Не делали:** перенос
  `Mb10Qr` и подписи в `:rules`, `PhoneWire` в `:rules` (волна 3, Godot), `CallMediaPort`.
- Мелкое: иконки приложения нет вовсе (`MissingApplicationIcon` в lint-baseline — нужен арт); 7 находок `ModifierParameter` в baseline (трогает публичные сигнатуры дизайн-системы);
  в detekt-baseline осталась старая находка `DecryptRules`; `DebugQrBus` (только debug) теряет строку, если экран её не слушает — стенд e2e это учитывает.
- **kit как библиотека:** когда появится второе приложение, публиковать kit отдельным артефактом (composite build или Maven), а не копией каталога; до тех пор — правило из
  kit/README: ни Android, ни игры, форматы закреплены тестами.
- **Paparazzi и Robolectric:** Paparazzi ставит Java-агент ByteBuddy; подключение на лету на macOS под нагрузкой ненадёжно, поэтому агент грузится при старте тестовой JVM
  (`-javaagent`, конфигурация `byteBuddyAgent` в `app/build.gradle.kts`; стережёт `AgentPreloadTest`). Нативные библиотеки Paparazzi (layoutlib, своя Skia) и Robolectric
  (нативный SQLite) в одной JVM конфликтуют (SIGSEGV на macOS), поэтому `testDebugUnitTest` гоняет только `screenshots/`, остальное — `testDebugUnitTestNoScreenshots`, от которой она зависит.
  **Не запускай `cleanTest*`** у app: Paparazzi регистрирует `app/src/test/snapshots` как выход тестовой задачи, и clean удаляет закоммиченные эталоны («нет файла» при сверке).
  Прогнать заново без кэша — `./gradlew verifyPaparazziDebug --rerun-tasks` (без скриншотов — `:app:testDebugUnitTestNoScreenshots --rerun`); удалённые эталоны — `git restore app/src/test/snapshots`.
- **detekt 2.0.0-alpha.6** (плагин `dev.detekt`, стабильной 2.0 ещё нет): собран с Kotlin 2.4, пин компилятора убран — не возвращайте. Ключи `config/detekt/detekt.yml`
  переименованы по [руководству миграции](https://detekt.dev/docs/introduction/migration); задача идёт в режиме `light` (без classpath) — правила, которым нужны типы, не работают.
  Baseline 1.x не подходит 2.x (формат ID): при пересоздании — только `detektBaseline`.

## Что ждёт владельца

- Звуки приложения из Cyberpunk 2077: 81 кандидат (`~/Developer/cp77-sound-candidates/android/listen.html`), выбор номерами; в `app/src/main/res/raw/` кладём только одобренное.
- Живая проверка по списку «Не проверено» выше.

## Как проверить у себя

```bash
./gradlew :app:detekt :kit:detekt :rules:detekt :kit:animalsnifferMain :app:lintDebug   # статический анализ и уровень API
./gradlew verifyPaparazziDebug :kit:test                                                # все тесты приложения со сверкой скриншотов + kit
scripts/check.sh --all                                                                  # всё сразу (по изменённому — scripts/verify.sh)
scripts/e2e/up.sh && scripts/e2e/run-all.sh                                             # два эмулятора и все сценарии
```

Gradle на Mac не гонять — `scripts/dbx.sh --auto|--full` (CLAUDE.md, «Где что запускать»).

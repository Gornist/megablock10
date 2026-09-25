# Правила для агентов (Claude Code и др.)

Проект: Android-приложение для LARP «Мегаблок №10» (`app/`), переиспользуемое ядро без Android (`kit/`), сервер и дашборд
мастера (`admin-web/`), стенд e2e на двух эмуляторах (`scripts/e2e/`). Всё здесь выверено на реальных сбоях — не обходите.

Прочитать перед работой: [docs/android-handoff.md](docs/android-handoff.md) (состояние и план),
[docs/architecture.md](docs/architecture.md) (слои, правила), [docs/refactor-plan.md](docs/refactor-plan.md) (что в работе),
[scripts/e2e/README.md](scripts/e2e/README.md) (стенд).

## Git и процесс

- Коммиты, комментарии и документация — на русском. Сообщение коммита: что и **почему** (какой сбой, какой журнал).
- В `main` — только по явной команде владельца, перемоткой (fast-forward) с зелёными CI и e2e. Историю `main` не переписывать.
- Одна ветка — один исполнитель. Параллельная работа — `scripts/agent-worktree.sh new <имя>` (своя копия и ветка `agent/<имя>`).
- Не коммитить незавершённое «на потом»: после каждого шага ветка собирается и тесты зелёные.

## Проверки

| Что | Команда | Где |
|---|---|---|
| Всё локально | `scripts/check.sh --all` | pre-push хук (`scripts/setup-hooks.sh`) — быстрая версия |
| Тесты приложения + скриншоты | `./gradlew verifyPaparazziDebug` (сам гоняет **все** unit-тесты app: скриншоты и остальное — в разных JVM) | без скриншотов — `testDebugUnitTestNoScreenshots`; один тест — `--tests` у неё |
| kit | `./gradlew :kit:test` | чистый JVM |
| Статика | `./gradlew :app:detekt :kit:detekt :kit:animalsnifferMain :app:lintDebug` | новые находки ломают CI |
| CI | `.github/workflows/main.yml` (push/PR в `main`, вручную) | ≈4 мин |
| e2e | `scripts/e2e/up.sh && scripts/e2e/run-all.sh`; CI — `e2e.yml` (PR в `main` с правкой `app/`, `kit/`, `scripts/e2e/`; ночью; вручную) | ≈17 мин |

- **Облачная сессия без Android SDK** не соберёт `:app` (и даже `:kit` — Gradle конфигурирует весь проект). Проверка —
  только CI: запустить `main.yml`/`e2e.yml` на своей ветке и читать журнал job. Не утверждать «проверено», не дождавшись CI.
- **Никогда `./gradlew cleanTest*` / `:app:cleanTestDebugUnitTest`**: Paparazzi считает `app/src/test/snapshots/` выходом
  тестовой задачи, clean **удаляет закоммиченные эталоны**. Заново без кэша — `--rerun-tasks`. Стёрлись — `git restore app/src/test/snapshots`.
- Намеренно поменяли интерфейс — `./gradlew recordPaparazziDebug` и коммит новых PNG вместе с правкой.
- Тестовая JVM в `app/build.gradle.kts` настроена под macOS (M1, JDK под Rosetta): агент ByteBuddy — через `-javaagent`,
  SQLite Robolectric — `LEGACY` (нативная ломала layoutlib Paparazzi, SIGSEGV). Не убирать без замены (см. refactor-plan, A1);
  стерегут `AgentPreloadTest` и `SqliteModeTest`.

## Как писать проверки e2e (`scripts/e2e/`)

- **Запрещено «действие; `sleep N`; одно чтение».** Результат асинхронный: `eq_wait <с> "описание" ожидаемое <команда>`,
  `check "…" wait_until <с> …`; значение из logcat — `await <с> <команда>`.
- «Не изменилось / не появилось» ожиданием не доказать: сначала дождаться свидетельства, что действие отработало (строка
  `MB10DBG`, число попыток), потом `eq`. Значение, которое по пути проходит через ожидаемое (баланс в серии переводов), — так же.
- Перед чтением id из logcat — `adb_ $S logcat -c`, иначе `tail -1` вернёт прошлое значение.
- **Стенд одноразовый**: `zz-provisioning` стирает Alice. Второй `run-all.sh` — только после `./down.sh && ./up.sh`.
- Стенд опирается на тексты журнала и строки `MB10DBG` (`sync.unreachable`, `chat.recv`, `pay id=`, `привязано к Wi-Fi`…).
  Переименовали событие или строку — поправьте `scripts/e2e/` в том же коммите (`grep -rn '<старое>' scripts/`). Всё, что стенд
  ищет в выводе приложения, перечислено в `scripts/e2e/log-contract.tsv` и сверяется с кодом unit-тестом `LogContractTest`;
  новая проверка по logcat/журналу — сначала строка в контракт.
- Эмулятор, привязанный к виртуальному Wi-Fi, иногда не достукивается до хоста 10.0.2.2 — это лечит `heal_host_reach`
  (перед каждым сценарием). Не путать с багом приложения.

## Отладка: сначала журналы, потом гипотезы

- Журнал приложения — события `Mb10Log` (`name key=value`), на устройстве `Android/data/com.megablok10.app/files/logs/`,
  на стенде `journal_cat <serial>`; красные сценарии кладут его в `$E2E_DIR/journals/`, CI печатает прямо в лог job
  (шаг «Журналы красных сценариев»). Прежде чем чинить — найти в журнале строку, которая объясняет сбой.
- Разовый красный — не «флейк»: сравнить с прогоном на `main` (запустить `e2e.yml` на `main`), найти причину.
- Ключевые события: `chat.send_direct … outcome=`, `send.not_reached`, `sync.ok|sync.unreachable`, `peer.found|peer.static|peer.server_hints`,
  `chat.start|chat.stop`, `=== ЗАПУСК ПРОЦЕССА ===`, `Snapshot` (раз в 30 с: Wi-Fi, очередь).

## Инварианты приложения (нарушение = потеря денег/данных у игроков)

- Транзакции — только `AppGraph.transactor` (`tx.inTransaction { … }`), запись для мастера (`changes.record`) — внутри той же
  транзакции. Всё, после чего уходит подтверждение, — синхронно (Room или `commit()`, не `apply()`).
- Нельзя менять без согласования: имена prefs, схему Room (только миграцией, `docs/db-migrations.md`), форматы сети/QR/записей
  (меняете — поднимайте версию, `net/WireVersion.kt`), теги и события журнала, строки `MB10DBG`.
- Деньги и предметы: `SendOutcome.UNKNOWN` = «могло дойти» — **не повторять** по другому адресу и не откатывать в PENDING.
- Адрес игрока — не «первый в списке»: у одного ключа бывает несколько записей пиров (NSD, статическая, подсказка сервера),
  NSD может хранить порт прошлого процесса. Отправлять через `kit.mesh.addressesOf` + `sendToFirstReachable`
  (звонки пока нет — refactor-plan, B1).
- Фоновая работа стартует от процесса (`Mb10App.onCreate`), не от экрана: сеть (`startMeshWhenIdentityAppears`) и синк
  (`startCollectorSync`). С Android 12 `startForegroundService` из фона бросает исключение — ловить (см. `MeshForegroundService.start`).
- Личность — в SharedPreferences, игровые данные — в Room: личность появляется раньше коммита данных. Не читать «персонаж
  есть ⇒ стартовый баланс есть» (refactor-plan, C1).
- Модель угроз — дружеская игра: подписи QR мастера, реестр ключей, подписи чата не делаем (решение владельца).

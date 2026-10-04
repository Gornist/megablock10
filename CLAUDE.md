# Правила для агентов (Claude Code и др.)

Проект: Android-приложение для LARP «Мегаблок №10» (`app/`), переиспользуемое ядро без Android (`kit/`), сервер и дашборд
мастера (`admin-web/`), прошивка точек на площадке — QR-дисплей и звук на ESP32 (`firmware/display/`), стенд e2e на двух
эмуляторах (`scripts/e2e/`). Всё здесь выверено на реальных сбоях — не обходите.

Прочитать перед работой: [docs/progress.md](docs/progress.md) (где мы сейчас, коротко), [docs/android-handoff.md](docs/android-handoff.md) (состояние и план),
[docs/architecture.md](docs/architecture.md) (слои, правила), [docs/refactor-plan.md](docs/refactor-plan.md) (что в работе),
[scripts/e2e/README.md](scripts/e2e/README.md) (стенд).

## Git и процесс

- Коммиты, комментарии и документация — на русском. Сообщение коммита: что и **почему** (какой сбой, какой журнал).
- В `main` — только по явной команде владельца, перемоткой (fast-forward) с зелёными CI и e2e. Историю `main` не переписывать.
- Одна ветка — один исполнитель. Параллельная работа — `scripts/agent-worktree.sh new <имя>` (своя копия и ветка `agent/<имя>`).
- Не коммитить незавершённое «на потом»: после каждого шага ветка собирается и тесты зелёные.

## Окружение агентов

- Плагины Claude Code для проекта — `.claude/settings.json` (code-review, KotlinSense). Облачная сессия по нему их не ставит —
  ставит `scripts/cloud-setup.sh` (`claude plugin install`, до старта сессии). LSP-инструмент Claude Code (через него
  KotlinSense даёт диагностику) включается переменной `ENABLE_LSP_TOOL=1` — она в `env` того же `settings.json`.
  Decibel Superpowers публичного git-источника не имеет — включается в аккаунте claude.ai.
- Godot-часть (`netrun/`) ведёт проектный агент `godot-dev` (`.claude/agents/godot-dev.md`): он работает с живым редактором Godot
  на devbox через MCP-сервер `godot-ai` из `.mcp.json` (ssh + `uvx godot-ai attach`; при первом запуске Claude Code просит одобрить
  проектный MCP). Редактор: `scripts/devbox-godot-ai.sh start|stop|status` на devbox, рабочая копия — `~/wt-godot` (`agent/godot`).
- Облачное окружение настраивает `scripts/cloud-setup.sh` (копия вставлена в Setup script окружения): SDK 36, зеркало Maven
  для Gradle и Robolectric, `LANG=C.UTF-8`, kotlin-language-server (для KotlinSense), PlatformIO с платформой ESP32 и `wokwi-cli`
  (прошивка QR-дисплея, `firmware/display`). Правите скрипт — обновите и его копию в настройках. Для прошивки в Network access
  окружения нужны `api.registry.platformio.org`, `dl.registry.platformio.org`, `wokwi.com`; токен Wokwi — переменная окружения
  `WOKWI_CLI_TOKEN` в настройках окружения и секрет с тем же именем в GitHub Actions, не в репозитории и не в чате.

## Проверки

| Что | Команда | Где |
|---|---|---|
| Всё локально | `scripts/check.sh --all` | pre-push хук (`scripts/setup-hooks.sh`) — `check.sh --fast` (≤ 1 мин): detekt, lint, kit, сервер; без Robolectric/Paparazzi |
| Тесты приложения + скриншоты | `./gradlew verifyPaparazziDebug` (сам гоняет **все** unit-тесты app: скриншоты и остальное — в разных JVM) | без скриншотов — `testDebugUnitTestNoScreenshots`; один тест — `--tests` у неё |
| kit | `./gradlew :kit:test` | чистый JVM |
| Статика | `./gradlew :app:detekt :kit:detekt :kit:animalsnifferMain :app:lintDebug` | новые находки ломают CI |
| CI | `.github/workflows/main.yml` (push/PR в `main`, вручную) | ≈4 мин |
| e2e | `scripts/e2e/up.sh && scripts/e2e/run-all.sh`; CI — `e2e.yml` (PR в `main` с правкой `app/`, `kit/`, `scripts/e2e/`; ночью; вручную) | ≈17 мин |
| Коллектор | `admin-web/server`: `npm test`; `admin-web/client`: `npm test`, `npm run lint`, `npm run build` | в CI — `main.yml`, job admin-web |
| Godot (netrun) | `ssh devbox 'cd ~/wt-godot && netrun/tools/gdunit.sh'`; правки и запуск игры — агент `godot-dev` (живой редактор + MCP, `.claude/agents/godot-dev.md`) | devbox; CI — `netrun.yml` (правка `netrun/`); подробности — `docs/netrun-devbox.md`, «Godot AI» |
| Прошивка | `cmake -S firmware/display -B firmware/display/build && cmake --build … && ctest --test-dir …`; плата — `pio run -e crowpanel579`; Wokwi — `firmware/display/tools/wokwi_selftest.sh` (квота CI-минут; в CI — только при правке кода платы); esp-emulator без квоты (без SD/I²S) — `firmware/display/tools/espemu_selftest.sh` | CI — `firmware.yml` (правка `firmware/`, `admin-web/server/src/displays/`, звука на сервере — `audio/`, `routes/audio.ts`); ≈5 мин |

- **Облачная сессия без Android SDK** не соберёт `:app` (и даже `:kit` — Gradle конфигурирует весь проект). Проверка —
  только CI: запустить `main.yml`/`e2e.yml` на своей ветке и читать журнал job. Не утверждать «проверено», не дождавшись CI.
- **Никогда `./gradlew cleanTest*` / `:app:cleanTestDebugUnitTest`**: Paparazzi считает `app/src/test/snapshots/` выходом
  тестовой задачи, clean **удаляет закоммиченные эталоны**. Заново без кэша — `--rerun-tasks`. Стёрлись — `git restore app/src/test/snapshots`.
- Намеренно поменяли интерфейс — `./gradlew recordPaparazziDebug` и коммит новых PNG вместе с правкой.
- Скриншот-тесты (Paparazzi) и остальные unit-тесты (Robolectric) — в разных JVM (`app/build.gradle.kts`, refactor-plan A1):
  раньше нативный SQLite Robolectric в общей JVM ломал layoutlib Paparazzi на macOS (SIGSEGV), разделение это сняло —
  подтверждено 5 прогонами на Mac (M1), `robolectric.sqliteMode=LEGACY` больше нет. Агент ByteBuddy — через `-javaagent`
  (нужен Paparazzi в любой JVM, не убирать); стережёт `AgentPreloadTest`.

## Где что запускать

- **Mac (8 ГБ):** правка, git, `scripts/check.sh --fast`. Gradle, Paparazzi, e2e, Godot, Мост — **на devbox** (`ssh devbox`),
  долгое через `devjob` — skill `devbox`. Параллельных Gradle и стендов e2e нет: одна задача на машину.
- **Gradle на devbox — `scripts/dbx.sh --auto|--full`** (очередь, один итог; skill `orchestrate`). Большая задача из 3+ шагов — по skill `orchestrate`
  (разведка одним агентом с досье, исполнители sonnet, ожидание одним фоновым вызовом, `scripts/ci-wait.sh`).
- Цикл задачи: правка → `check.sh --fast` (Mac) → тяжёлая проверка на devbox → коммит → `/clear`. Новое окно начинать с
  `docs/android-handoff.md`, `git log -10`, `git diff`.
- e2e: правила написания проверок — `.claude/rules/e2e.md` (подгружаются при правке `scripts/e2e/`).
- Сбой: сначала журналы — skill `debug-journals`, потом гипотезы.
- Инварианты приложения (деньги, транзакции, сеть) — `.claude/rules/app-invariants.md`, подгружаются при правке `app/` и `kit/`.
  Нарушение = потеря денег/данных у игроков; читать **до** правки.

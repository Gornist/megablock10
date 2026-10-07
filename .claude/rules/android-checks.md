---
paths:
  - "app/**"
  - "kit/**"
  - "rules/**"
  - "netrun-bridge/**"
  - "gradle/**"
  - "*.gradle.kts"
---

# Проверки Android и Gradle (перенесено из CLAUDE.md 07.10 — грузится только при работе с этими путями)

Gradle — только на devbox: `scripts/dbx.sh --auto|--full` (очередь, один итог; skill `devbox`). На Mac Gradle не запускать.

| Что | Команда | Заметки |
|---|---|---|
| Тесты приложения + скриншоты | `./gradlew verifyPaparazziDebug` (сам гоняет **все** unit-тесты app: скриншоты и остальное — в разных JVM) | без скриншотов — `testDebugUnitTestNoScreenshots`; один тест — `--tests` у неё |
| kit | `./gradlew :kit:test` | чистый JVM |
| Статика | `./gradlew :app:detekt :kit:detekt :kit:animalsnifferMain :app:lintDebug` | новые находки ломают CI |

- **Облачная сессия без Android SDK** не соберёт `:app` (и даже `:kit` — Gradle конфигурирует весь проект). Проверка —
  только CI: запустить `main.yml`/`e2e.yml` на своей ветке и читать журнал job. Не утверждать «проверено», не дождавшись CI.
- **Никогда `./gradlew cleanTest*` / `:app:cleanTestDebugUnitTest`** (хук отклоняет): Paparazzi считает `app/src/test/snapshots/`
  выходом тестовой задачи, clean **удаляет закоммиченные эталоны**. Заново без кэша — `--rerun-tasks`. Стёрлись — `git restore app/src/test/snapshots`.
- Намеренно поменяли интерфейс — `./gradlew recordPaparazziDebug` и коммит новых PNG вместе с правкой.
- Скриншот-тесты (Paparazzi) и остальные unit-тесты (Robolectric) — в разных JVM (`app/build.gradle.kts`, refactor-plan A1):
  раньше нативный SQLite Robolectric в общей JVM ломал layoutlib Paparazzi на macOS (SIGSEGV), разделение это сняло —
  подтверждено 5 прогонами на Mac (M1), `robolectric.sqliteMode=LEGACY` больше нет. Агент ByteBuddy — через `-javaagent`
  (нужен Paparazzi в любой JVM, не убирать); стережёт `AgentPreloadTest`.
- Плагины Claude Code: KotlinSense даёт диагностику через LSP-инструмент (`ENABLE_LSP_TOOL=1` в `env` `.claude/settings.json`);
  облачной сессии его ставит `scripts/cloud-setup.sh`.

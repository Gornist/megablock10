---
name: devbox
description: Запуск тяжёлого (Gradle, Paparazzi, стенд e2e, Godot, Мост) на машине разработки devbox по SSH — реквизиты, devjob, пуш ветки, диагностика. Использовать перед любой сборкой, тестом приложения или e2e.
---

# devbox — где выполняется всё тяжёлое

Mac (8 ГБ) — только правка, git и `scripts/check.sh --fast`. Gradle, `verifyPaparazziDebug`, e2e, Godot, Мост — на devbox
(i7-9700T, 16 ГБ, Ubuntu 24.04, KVM). Машина общая для всех веток.

## Доступ
- `ssh devbox` (Tailscale SSH, 100.80.115.46, пользователь `nick`; имя хоста с Mac резолвится неверно — только IP).
- Репозиторий `~/megablock10`; на Mac git-remote `devbox`. Пуш ветки: `git push devbox <ветка> --no-verify`
  (локальный pre-push хук запускает Gradle на Mac — на devbox он не нужен).
- Окружение: `~/netrun-env.sh` (Android SDK в `~/android-sdk`, Godot в `~/.local/bin`). **Ловушка JDK:** `devjob` сам делает
  `. ~/netrun-env.sh`, а там JAVA_HOME=temurin-17 (нужен ветке `agent/netrun`, она от `main` до Kotlin 2.4). Для `main` и веток
  от свежего `main` в команде `devjob` явно: `export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin:$PATH`.
  Проверки `java -version` мало: версия подставляется тихо.
- **Каталог.** `devjob` делает `cd ~/megablock10`, а там постоянно checkout `agent/netrun` (`receive.denyCurrentBranch=updateInstead`
  для пушей Cyberspace). Чужие ветки в `~/megablock10` **не** переключать: `git -C ~/megablock10 worktree add ~/wt-<имя> <ветка>`,
  `cp local.properties`, ссылки на `admin-web/*/node_modules`, в команде `devjob` — `cd ~/wt-<имя> && …`. Для `main` уже есть `~/mb-main`.

## Долгие задачи — только отвязанно
`devjob start <имя> '<команда>'`, затем `devjob status|log|stop <имя>` (логи — `~/jobs/`). Обрыв SSH не убивает задачу;
результат читать короткими вызовами, не держать живую сессию. Пример: `devjob start paparazzi 'cd ~/mb-main && export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin:$PATH && ./gradlew verifyPaparazziDebug; echo rc=$?'`.

Ловушки `devjob`:
- команду не заканчивать на `exit $r`: код не запишется, `status` покажет «нет такой задачи»; писать `…; echo rc=$?`;
- не искать процессы `pgrep -f '<строка>'`/`pkill -f`, если строка есть в самой команде ssh: совпадёт сам с собой (ожидание
  висит, ssh убивается). Проверять через `devjob status`;
- `./gradlew --stop` из задач не вызывать: демон общий для всех worktree, убьёт чужие прогоны.

## Правила
- Одновременно одна задача Gradle и один стенд e2e: порты эмуляторов и сервера фиксированы (`scripts/e2e/up.sh` откажет,
  если стенд занят другой копией). Свободна ли машина — `devjob status` и `ps`.
- Стенд одноразовый: второй `run-all.sh` — после `down.sh && up.sh`.
- Godot на Mac не запускать вообще (краш-репорты macOS) — только devbox.
- Эмулятор завис: `scripts/e2e/down.sh; pkill -f emulator; scripts/e2e/up.sh`.
- Порты: стенд e2e — 5554/5556, коллектор 2517 (`scripts/e2e`); Мост в `live_run.sh` — 7410/7411, сервер мира 7777. Параллельный
  `live_run` конфликтует: задачи брали 7510/7511/7877.
- **Лечение стенда пока только в `agent/netrun`** (коммиты E1: `LC_ALL` в `lib.sh`, `captive_portal_mode 0` в `up.sh`). В `main`
  их нет: стенд на devbox от `main` даёт 5 красных (announcement, sec-alert, slot-race, wifi-bind, zz-provisioning) — это не баг
  приложения. Описанное ниже верно после слияния.
- Красные сценарии, не связанные с приложением: локаль без UTF-8 (lib.sh ставит `LC_ALL=C.UTF-8`) и отключённый Android
  виртуальный Wi-Fi без интернета (`up.sh` выставляет `captive_portal_mode 0`). Подробности и первичная настройка —
  `docs/netrun-devbox.md`, `scripts/devbox-setup.sh` (идемпотентный).
- Нужен файл с devbox (журнал, скриншот) — `scp devbox:<путь> .` или `ssh devbox 'tail -n 200 …'`, не пересказывать по памяти.

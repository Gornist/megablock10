---
name: devbox
description: Запуск тяжёлого (Gradle, Paparazzi, стенд e2e, Godot, Мост) на машине разработки devbox по SSH — реквизиты, devjob, пуш ветки, диагностика. Использовать перед любой сборкой, тестом приложения или e2e.
---

# devbox — где выполняется всё тяжёлое

Mac (8 ГБ) — только правка, git и `scripts/check.sh --fast`. Gradle, `verifyPaparazziDebug`, e2e, Godot, Мост — на devbox
(i7-9700T, 16 ГБ, GTX 1650, Ubuntu 26.04.1, KVM; переустановлена с нуля 25.10 — `scripts/devbox-bootstrap.sh`). Машина общая
для всех веток. Чего нет в git, после переустановки нет и на машине: стенды и рабочие копии каждая сессия поднимает себе сама.

## Доступ
- `ssh devbox` (LAN 192.168.1.141, пользователь `nick`; алиас в `~/.ssh/config` на Mac). VPN и Tailscale нет. После переустановки
  отпечаток хоста новый: `ssh-keygen -R 192.168.1.141`. GitHub с devbox качает медленно (20–30 КБ/с) — большое качать на Mac и `scp`.
- Состояние машины и устройств — `scripts/box.sh status` (одна строка); adb — user-служба `box-adb`, `adb kill-server` не нужен.
  Машиной управляет сессия **Devbox** (ТЗ — `docs/devbox.md`): очередь, брони устройств и портов — через неё.
- Репозиторий `~/megablock10`; на Mac git-remote `devbox`. Пуш ветки: `git push devbox <ветка> --no-verify`
  (локальный pre-push хук запускает Gradle на Mac — на devbox он не нужен).
- Окружение: `~/netrun-env.sh` (Android SDK в `~/android-sdk`, Godot в `~/.local/bin`). **Ловушка JDK:** `devjob` сам делает
  `. ~/netrun-env.sh`, а там JAVA_HOME=temurin-17, тогда как Gradle `main` нужен 21 (Paparazzi 2). В команде `devjob` явно:
  `export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin:$PATH` (`dbx.sh` делает это сам).
  Проверки `java -version` мало: версия подставляется тихо.
- **Каталог.** `devjob` делает `cd ~/megablock10` (checkout `main`, общий). Ветки в нём **не** переключать:
  `git -C ~/megablock10 worktree add ~/wt-<имя> <ветка>`, `cp local.properties`, ссылки на `admin-web/*/node_modules`, в команде
  `devjob` — `cd ~/wt-<имя> && …`. Для `main` есть `~/mb-main`; `dbx.sh` работает в своих `~/wt-dbx-*` и берёт оттуда `local.properties`.

- **Godot AI (`~/wt-godot`).** Живой редактор Godot с плагином Godot AI (MCP) и рабочая копия `~/wt-godot` (ветка `agent/godot`) —
  `bash ~/wt-godot/scripts/devbox-godot-ai.sh setup|start|stop|status` (порты 8000/9500; поднимается сам после перезагрузки).
  Работает на дисплее GNOME (автовход nick, Wayland). Тесты Godot — `netrun/tools/gdunit.sh` (сам подтягивает
  `~/netrun-env.sh`: неинтерактивный ssh не знает путь к `godot`). Правит и проверяет агент `godot-dev` (`.claude/agents/godot-dev.md`);
  подробности и ловушки — `docs/netrun-devbox.md`, «Godot AI».

## Долгие задачи — только отвязанно
**Gradle — через `scripts/dbx.sh --auto|--full`** (git-синхронизация, очередь `flock`, один итог; skill `orchestrate`): им пользуйся вместо ручных `devjob`+rsync. Ниже — общий случай (не Gradle).
`devjob start <имя> '<команда>'`, затем `devjob status|log|stop <имя>` (логи — `~/jobs/`). Обрыв SSH не убивает задачу;
результат читать короткими вызовами, не держать живую сессию. Пример: `devjob start paparazzi 'cd ~/mb-main && export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 PATH=/usr/lib/jvm/temurin-21-jdk-amd64/bin:$PATH && ./gradlew verifyPaparazziDebug; echo rc=$?'`.

Ловушки `devjob`:
- команду не заканчивать на `exit $r`: код не запишется, `status` покажет «нет такой задачи»; писать `…; echo rc=$?`;
- не искать процессы `pgrep -f '<строка>'`/`pkill -f`/`ps | grep '<строка>'`, если строка есть в самой команде ssh: совпадёт сам
  с собой (ожидание висит, ssh убивается). Проверять через `devjob status`, процесс редактора Godot — по pid-файлу скрипта;
- `./gradlew --stop` из задач не вызывать: демон общий для всех worktree, убьёт чужие прогоны.

## Правила
- Одновременно одна задача Gradle и один стенд e2e: порты эмуляторов и сервера фиксированы (`scripts/e2e/up.sh` откажет,
  если стенд занят другой копией). Свободна ли машина — `devjob status` и `ps`.
- Стенд одноразовый: второй `run-all.sh` — после `down.sh && up.sh`.
- Godot на Mac не запускать вообще (краш-репорты macOS) — только devbox.
- Эмулятор завис: `scripts/e2e/down.sh; pkill -f emulator; scripts/e2e/up.sh`.
- Порты: стенд e2e — 5554/5556, коллектор 2517 (`scripts/e2e`); Мост в `live_run.sh` — 7410/7411, сервер мира 7777. Параллельный
  `live_run` конфликтует: задачи брали 7510/7511/7877.
- Красные сценарии, не связанные с приложением: локаль без UTF-8 (lib.sh ставит `LC_ALL=C.UTF-8`) и отключённый Android
  виртуальный Wi-Fi без интернета (`up.sh` выставляет `captive_portal_mode 0`). Подробности и первичная настройка —
  `docs/netrun-devbox.md`, `scripts/devbox-setup.sh` (идемпотентный).
- Нужен файл с devbox (журнал, скриншот) — `scp devbox:<путь> .` или `ssh devbox 'tail -n 200 …'`, не пересказывать по памяти.

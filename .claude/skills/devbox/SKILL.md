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
- Окружение: `source ~/netrun-env.sh` (JDK, Android SDK в `~/android-sdk`, Godot в `~/.local/bin`). Сверить `java -version`
  с тем, что требует `scripts/` (по умолчанию temurin-21).

## Долгие задачи — только отвязанно
`devjob start <имя> '<команда>'`, затем `devjob status|log|stop <имя>` (логи — `~/jobs/`). Обрыв SSH не убивает задачу;
результат читать короткими вызовами, не держать живую сессию. Пример: `devjob start paparazzi 'cd ~/megablock10 && ./gradlew verifyPaparazziDebug'`.

## Правила
- Одновременно одна задача Gradle и один стенд e2e: порты эмуляторов и сервера фиксированы (`scripts/e2e/up.sh` откажет,
  если стенд занят другой копией). Свободна ли машина — `devjob status` и `ps`.
- Стенд одноразовый: второй `run-all.sh` — после `down.sh && up.sh`.
- Godot на Mac не запускать вообще (краш-репорты macOS) — только devbox.
- Эмулятор завис: `scripts/e2e/down.sh; pkill -f emulator; scripts/e2e/up.sh`.
- Красные сценарии, не связанные с приложением: локаль без UTF-8 (lib.sh ставит `LC_ALL=C.UTF-8`) и отключённый Android
  виртуальный Wi-Fi без интернета (`up.sh` выставляет `captive_portal_mode 0`). Подробности и первичная настройка —
  `docs/netrun-devbox.md`, `scripts/devbox-setup.sh` (идемпотентный).
- Нужен файл с devbox (журнал, скриншот) — `scp devbox:<путь> .` или `ssh devbox 'tail -n 200 …'`, не пересказывать по памяти.

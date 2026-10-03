# Текущее состояние (для нового окна контекста)

Короткая страница: где мы и что дальше. Подробности — в [android-handoff.md](android-handoff.md) (история, долги),
[refactor-plan.md](refactor-plan.md), [architecture.md](architecture.md). Обновляйте при завершении этапа; дату — в строке ниже.

Обновлено: 02.10.2026, `main` на `b333a9d`.

## Сейчас

- `main`: Android (kit + app на архитектурном слое), Kotlin 2.4 / AGP 8.13 / Gradle 8.14 / compileSdk 36 (миграция M1–M6 слита),
  дашборд мастера и «Устройства», прошивка QR-дисплея. CI зелёный.
- Параллельные потоки (у каждого своя сессия и ветка; в `main` — только по команде владельца):
  - **Cyberspace («Сеть», VR-клиент нетраннера)** — `agent/netrun` и ~45 веток-задач `agent/netrun-*`, каталог `netrun/`,
    `netrun-bridge/`, `docs/netrun*.md`. План по карточкам: `docs/netrun-tasks.md`.
    Статус: Мост B0–B4, обмен карточками с телефоном (M2), P5; приложение — M1 (`:rules`), M3 (вход по QR стойки); Godot — серый
    узел, 10 клиентов, Black ICE на ревью; сквозной e2e `netrun-run` на devbox зелёный. Каталог `netrun/` и документы уже в `main`;
    ветки-задачи `agent/netrun-*` вливаются по команде владельца.
    Godot-часть ведёт агент `godot-dev` (`.claude/agents/godot-dev.md`): живой редактор Godot с плагином Godot AI (MCP) на devbox,
    тесты — gdUnit4 (`netrun/tools/gdunit.sh`, 223 теста); подробности — `docs/netrun-devbox.md`, «Godot AI».
  - **3D-ассеты «Сети»** (Blender → `.glb` → Godot) — ТЗ `docs/netrun-assets-brief.md`; моделлер работает в своей ветке (`scripts/agent-worktree.sh new assets`).
  - **Дашборд мастера** — только `admin-web/`.
  - **UI на новой дизайн-системе** — `agent/ui-kit`.
- Тяжёлое (Gradle, Paparazzi, e2e, Godot) — на devbox, см. `.claude/skills/devbox/`.

## Дальше

1. Живая проверка на 2–3 телефонах (`device-testing.md`): переводы, передача предметов, статусы ✓✓, Android 8–12.
2. Слить в `main` скрипт и документ devbox (`scripts/devbox-setup.sh`, `docs/netrun-devbox.md`) отдельно от VR-работы.
3. Мелкое: иконка приложения (нужен арт), 7 находок `ModifierParameter` в дизайн-системе.

## Известные ограничения

- AGP 9 пока не берём: нужны стабильные Paparazzi и detekt (подробности — android-handoff, «Известные ограничения»).
  targetSdk 34: 35+ включает edge-to-edge, поднимать отдельной правкой со сверкой всех экранов.
- Не сделано по решению владельца (дружеская игра): подписи QR мастера, реестр ключей, подписи чата.
- Нагрузка на 100 устройств не проверялась: стенд — два эмулятора.

## Как восстановить контекст

`git log -10`, `git status`, этот файл, затем нужный раздел из ссылок выше. Проверки — `scripts/check.sh --fast` (Mac),
остальное на devbox.

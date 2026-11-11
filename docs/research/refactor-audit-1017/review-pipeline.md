# Ревью области «Конвейер» (17.10.2026, main 47c6c157)

## Сводка области

- Размер: 19 скриптов `scripts/*.sh` + `session-stats.py` (≈2 000 строк без `box/`), `scripts/box/ctl.sh` 1119 строк / 80 КБ, `scripts/e2e/lib.sh` 412 строк, 19 сценариев e2e, 7 workflows (≈840 строк), хук `guard-bash.sh` (52 строки) с таблицей из 70 случаев, 8 skills (61 КБ вместе с rules), `CLAUDE.md` 21,7 КБ.
- Архитектура: «вердикт одной строкой + код выхода» выдержана почти везде (`verify`, `dbx`, `land`, `ci-wait`, `zone-check`, `lint-pipeline`); циклы ограничены (`ci-wait` 240×30 с, `dbx` 360×15 с, `sweep` 576 проходов); `scripts/lint-pipeline.sh` на Mac работает и даёт `LINT OK` (shellcheck и actionlint установлены).
- Покрытие тестами: проверяется только хук (`test-hook.cases`) и статика (shellcheck/actionlint). Тестов нет у `land.sh` (слияние в `main`, регулярка SAFE), `train.sh`, `ci-wait.sh`, `dbx.sh --auto` (выбор задач по путям), `box/ctl.sh` (управление очками).
- Общее впечатление: инструменты зрелые, дыры сидят на стыках. Одна и та же истина живёт в нескольких копиях (таблица зон — 4 копии, «что проверять по изменённым путям» — 4, выбор Node — 3, ssh на devbox — 12 мест), и копии уже разошлись. Две дыры в проверках дают красный CI на чужом PR: `netrun-bridge` не входит в локальные `dbx`/`check` и `verify` не смотрит на `scripts/`, workflows и хук.
- Lint включает только 16 файлов из ≈90 shell-скриптов репозитория (`lint-pipeline.sh:17-24`), хотя непокрытые чище, чем можно было ждать: `ctl.sh` 0 замечаний, e2e — ≈19.

## Находки

### 1. Workflows дважды запускаются на каждый пуш в ветку с PR (netrun.yml, firmware.yml) — в том числе Wokwi-квота
- Где: `.github/workflows/netrun.yml:3-13` (push без `branches` + pull_request; группа `netrun-${{ pull_request.number || run_id }}`), `.github/workflows/firmware.yml:6-12`, `:125-128` (для PR `BEFORE` = base sha).
- Что: пуш в `agent/*` с открытым PR порождает два прогона (push и pull_request). Для push группа concurrency — `run_id`, отмена старых не работает; в firmware Wokwi-шаг видит «изменение платы» в обоих событиях, а для PR сравнивает с базой всего PR, а не с предыдущим коммитом, и поэтому гоняется на каждый пуш PR.
- Почему мешает: платные минуты Wokwi (месячная квота, `firmware.yml:117,154`) и ≈2×(test + Android-экспорт + Windows-экспорт) на каждую правку Godot; очередь Actions длиннее, `ci-wait` ждёт лишнее.
- Выгода: высокая — вдвое меньше самых дорогих прогонов.
- Риск (дверь/радиус): низкий; триггеры двух файлов; обязательные проверки `main` (`build`, `admin-web`) не затронуты. Нельзя оставить дыру «push в `main` без прогона»: оставить `push: branches: [main]` + PR.
- Размер: S
- Проверить чем: `actionlint`, затем два пуша в тестовую ветку с PR и `gh run list --branch` (по одному прогону на workflow).

### 2. `scripts/dbx.sh --auto/--full` и `check.sh` не гоняют `:netrun-bridge`, а CI гоняет; `verify.sh` не смотрит на конвейер
- Где: `scripts/dbx.sh:40-41` (RULES/FULL без `:netrun-bridge:*`), `scripts/verify.sh:23` (мост — только если изменён `netrun-bridge/`), `scripts/check.sh:50-56`, CI: `.github/workflows/main.yml:37,56`; `netrun-bridge/build.gradle.kts:29,31` зависит от `:kit` и `:rules`. Для `scripts/`, `.claude/hooks/`, `.github/workflows/` в `verify.sh` нет ни одной ветки (выводит «нечего проверять»).
- Что: правка `rules/` или `kit/` (контракт приложение↔мост, коды, кодеки) локально зелёная, а `:netrun-bridge:test`/`detekt` краснеют только в CI. Правка скрипта/workflow/хука проходит `verify.sh` как «нечего проверять».
- Почему мешает: класс сбоев «версия/контракт объявлены раньше приёма» (досье §5.3) и «красный CI не из-за своей правки»; лишний круг «пуш → ждать 4 мин → чинить».
- Выгода: высокая — закрывает известную дыру дешёвой правкой.
- Риск (дверь/радиус): низкий; в `dbx.sh` добавить `:netrun-bridge:detekt :netrun-bridge:test` при изменениях `rules/` и `kit/`, в `verify.sh` — ветка `^(scripts/|\.claude/hooks/|\.github/workflows/)` → `scripts/lint-pipeline.sh`. `dbx.sh` — зона Devbox (согласовать).
- Размер: S
- Проверить чем: `DBX_DRY=1 scripts/dbx.sh --auto` после правки `rules/…`, `scripts/verify.sh --dry` после правки скрипта.

### 3. Хук `guard-bash.sh`: обход `git -C … push origin main`, пробелы в списке запретов, ложные срабатывания на тексте
- Где: `.claude/hooks/guard-bash.sh:15` (ищет `git[[:space:]]+push` подряд), `:12-13` (только `-A|--all|.`), `:33` (`cleanTest` в любом месте команды); таблица `scripts/test-hook.cases` случаев на эти варианты не содержит.
- Что: проверено прогоном хука (файл-пробник в scratchpad). Разрешено: `git -C /x push origin main`, `git add -u`, `git add app/`, `git add *`, `git commit -a`, `git rebase`, `git branch -D`, `git worktree remove`, `git push origin --delete agent/x`, `git push origin :agent/x`, `git reset --hard`. Ложно отклоняется: `git commit -m "… git add -A …"` (сработало и на мой собственный вызов при ревью), `cat docs/cleanTest.md`.
- Почему мешает: CLAUDE.md («Не автоматизировать») заявляет запрет rebase/удаления веток и worktree, хук их не держит; `-C` обходит главный запрет (push в `main`), страхует только серверный ruleset, у владельца-admin он обходится (`docs/ci.md`, «Защита main»). Ложные отказы стоят хода (4 таких случая 05–06.10).
- Выгода: средняя — главный запрет без дыры, меньше ложных отказов.
- Риск (дверь/радиус): средний — слишком жёсткие правила снова будут отклонять легитимное; поэтому каждое правило — со случаем в `test-hook.cases`. Файлы: хук + таблица (зона Pipeline).
- Размер: S
- Проверить чем: `scripts/test-hook.sh`, `scripts/lint-pipeline.sh`.

### 4. Pre-push с Mac может висеть до ≈90 минут при занятом devbox, хотя заявлен «≤ 1 мин»
- Где: `.githooks/pre-push:2` и `scripts/check.sh:56` (только `ssh … devbox true` перед `dbx.sh --auto`), `scripts/dbx.sh:71` (`flock -w 2700`), `:88` (до 360×15 с).
- Что: проверка доступности devbox не смотрит на очередь; при чужой долгой задаче (`--full`, e2e) пуш ждёт очереди до 45 мин + сборку.
- Почему мешает: класс «очередь devbox» (досье §5.7); сессии обходят хук `--no-verify` (запрещён хуком только вне devbox — но давление на обход возникает именно здесь).
- Выгода: средняя.
- Риск (дверь/радиус): низкий; ограничить ожидание хука (`DBX_QUEUE_WAIT`, по умолчанию в хуке ≈60 с → «devbox занят — проверит CI») в `dbx.sh` и `check.sh`; файлы Devbox/Pipeline.
- Размер: S
- Проверить чем: вручную занять `~/.dbx.lock`, `scripts/check.sh --fast` на изменённом `app/` — вердикт за ≈минуту.

### 5. «Что проверять по изменённым путям» размножено в четырёх местах; список Gradle-задач — в шести
- Где: `scripts/check.sh:50-56`, `scripts/dbx.sh:36-47`, `scripts/verify.sh:19-37`, `.github/workflows/main.yml:36-110`; документация: `.claude/rules/android-checks.md:15-19`, `.claude/skills/orchestrate/SKILL.md:41-43`, `CLAUDE.md` (раздел «Проверки»).
- Что: каждый вариант выбирает набор по-своему (в находке 2 уже разошлись), текст про `verifyPaparazziDebug` и `NoScreenshots` повторяется с разной формулировкой (`check.sh:51-53` vs `main.yml:57-58`).
- Почему мешает: при смене Gradle-задач (AGP 9, detekt 2.0 в недавних PR) правятся 3–6 мест, одно забывается; агент читает противоречащие описания.
- Выгода: средняя.
- Риск (дверь/радиус): средний — единый источник (`scripts/lib/gradle-tasks.sh` или таблица в `dbx.sh --print-tasks`, CI зовёт `dbx.sh --print-tasks full`), затрагивает CI.
- Размер: M
- Проверить чем: `scripts/lint-pipeline.sh`, `DBX_DRY=1 scripts/dbx.sh --full`, пробный PR в `main`.

### 6. Таблица зон — четыре копии, уже разошлись
- Где: `CLAUDE.md` («Зоны сессий»), `scripts/zone-check.sh:8-25`, `.github/labeler.yml`, `.claude/hooks/session-brief.sh:14-24` (имя сессии → зона).
- Что: `apk.yml` — в зоне android по `zone-check.sh` (последняя строка `android)`), но не в `labeler.yml` и не в `CLAUDE.md`; `zone-check pipeline` принимает все `scripts/[^/]*`, а метка «конвейер» перечисляет 11 скриптов, и `sweep.sh`, `cloud-setup.sh`, `setup-hooks.sh`, `phone.sh` остаются без метки; документы зон (`docs/android-handoff.md`, `docs/netrun*.md`, `docs/displays.md`) и `.githooks/`, `docs/ci.md` в метках отсутствуют.
- Почему мешает: класс «параллельные сессии, зоны» (досье §5.4) — очередь слияний на `labeler` смотрит неполно; правка таблицы требует четырёх синхронных изменений («правите — правьте все три» в `labeler.yml:2`, а копий уже четыре).
- Выгода: средняя.
- Риск (дверь/радиус): низкий-средний; `docs/zones.tsv` (зона; regexp входа; regexp запрета) → `zone-check.sh` читает файл; `lint-pipeline.sh` сверяет `labeler.yml`/`session-brief.sh` с ним. CLAUDE.md сокращается до одной строки на зону.
- Размер: M
- Проверить чем: `scripts/zone-check.sh <зона>` на PR-ветке до и после (одинаковый вердикт), `lint-pipeline.sh`.

### 7. Работа с devbox по ssh размножена: 12 мест, 5 наборов опций, только `box.sh` умеет «я уже на devbox» и диагностику недоступности
- Где: `scripts/dbx.sh:59` (ConnectTimeout=15), `scripts/phone.sh:19,52` (10), `scripts/check.sh:56` (5), `scripts/sweep.sh:21` (10, без BatchMode), `scripts/box.sh:32-44` (8; `onbox`, `unreachable`), `netrun/tools/dev.sh:19` (`DEV_HOST`); `scripts/dbx.sh:63` перезаписывает `~/.local/bin/dbx-run` на каждом вызове прямо на месте.
- Что: у `dbx.sh` и `phone.sh` нет ветки «запущено на devbox» (на нём 13.10 ssh к себе падал на known_hosts — это уже чинили в `box.sh`) и нет внятной причины «Tailscale лежит / машина выключена»; хост `devbox` зашит строкой. Перезапись `dbx-run` в процессе чужого ожидания в `flock` меняет файл, который bash дочитывает по смещению (при смене содержимого скрипта).
- Почему мешает: класс «очередь devbox / железо» (досье §5.7-8): каждый новый скрипт копирует ssh-строку со своими опциями.
- Выгода: средняя.
- Риск (дверь/радиус): средний — зона Devbox + Android + Godot (`dev.sh`); общий `scripts/lib/devbox.sh` (функции `dssh`, `onbox`, `unreachable`), версия `dbx-run` с хэшем в имени.
- Размер: M
- Проверить чем: `scripts/lint-pipeline.sh`, `DBX_DRY=1 scripts/dbx.sh --auto`, `scripts/box.sh status` и `scripts/phone.sh devices` на живом devbox.

### 8. Выбор Node/JDK в трёх местах с разной политикой; e2e откатывается на Node 20
- Где: `scripts/e2e/lib.sh:19-21` (запасной `node@20`, проверка только каталога, не бинарника), `scripts/check.sh:23-29` (Node ≥ 22, проверка версии), `admin-web/tools/_lib.sh:10-16`; JDK — `scripts/check.sh:13-19` и `scripts/e2e/lib.sh:22`.
- Что: `better-sqlite3` 13 на Node 20 падает SIGSEGV (`admin-web/README.md:10`, `check.sh:23-24`), а e2e-стенд при отсутствии `node@22` на Mac тихо возьмёт `node@20` и сервер стенда упадёт не по своей вине.
- Почему мешает: класс «нативные библиотеки и версии рантайма» (досье §5.9); при повторе — красный стенд, не имеющий отношения к правке.
- Выгода: низкая-средняя (на CI не воспроизводится, на Mac и новом devbox — да).
- Риск (дверь/радиус): низкий; общая функция `pick_node` (одна версия ≥ 22) в `scripts/lib/`, три потребителя; e2e — зона Android.
- Размер: S
- Проверить чем: `scripts/check.sh --fast` и `scripts/e2e/up.sh --status` при `NODE_BIN=` пустом и без `node@22`.

### 9. Сценарии `netrun-breach.sh` и `netrun-run.sh` повторяют ≈85 строк подъёма стенда; цикл `bash -c "source lib.sh; …"` — 43 раза
- Где: `scripts/e2e/scenarios/netrun-breach.sh:41,95-142` и `scripts/e2e/scenarios/netrun-run.sh:41,104-146` (seed.json через python-heredoc, правка графа, сборка Моста, `--import`, `emu redir`, запуск Моста и сервера мира); `scripts/e2e/lib.sh:65-70` (`wait_until` не видит функций, поэтому в ассерты вставляют `bash -c "source '$ROOT/scripts/e2e/lib.sh'; …"`).
- Что: два сценария по 238 и 275 строк копируют подготовку; shellcheck: SC2046/SC2206 в `netrun-breach.sh:163,164,221,222` (`$(bot_args)` и `PIDS+=($BOT)` без кавычек).
- Почему мешает: деньги/взлом/контракт мост↔сервер мира проверяются именно здесь; правка подготовки обязана попасть в оба файла; шумные копии `source lib.sh` ломаются от смены пути.
- Выгода: средняя.
- Риск (дверь/радиус): средний — сценарии идут в e2e 17 мин, любая ошибка в общей части красит оба; поэтому выносить по одному шагу, `netrun-lib.sh` (подъём Моста, сид, импорт) и `export -f` для часто зовущихся функций.
- Размер: M
- Проверить чем: `shellcheck -S warning scripts/e2e/**/*.sh`, `e2e.yml` вручную на ветке (сценарии в порядке до/после).

### 10. Lint конвейера покрывает 16 файлов из ≈90; JSON настроек хука не проверяется
- Где: `scripts/lint-pipeline.sh:17-24` (список), `.github/workflows/pipeline.yml:7,10` (paths не включают `.claude/settings.json`, `.githooks/**`, `netrun/tools`).
- Что: вне lint остаются `scripts/e2e/*.sh` и сценарии (≈19 предупреждений shellcheck, находка 9), `netrun/tools/*.sh` и `admin-web/tools/*.sh` (16 предупреждений), `scripts/sweep.sh`, `phone.sh`, `cloud-setup.sh`, `devbox-setup.sh` (SC2034 `NO_KVM` — флаг `--android-only` ничего не делает, `devbox-setup.sh:44`), `devbox-runner.sh`, `box/ctl.sh`, `.githooks/pre-push`. Невалидный `.claude/settings.json` молча отключает хук — проверки на JSON нет.
- Почему мешает: найденное сегодня — ошибки, которые lint поймал бы при добавлении; хук-защита (класс 13 досье) не имеет страховки на собственный конфиг.
- Выгода: средняя.
- Риск (дверь/радиус): низкий — заменить явный список на `git ls-files '*.sh'`, предупреждения вычистить заранее (≈35 шт.), добавить `jq empty .claude/settings.json`; затрагивает чужие зоны только правкой их скриптов (e2e, netrun/tools, admin-web/tools — карточками владельцам).
- Размер: S (сам lint) + мелкие карточки на предупреждения
- Проверить чем: `scripts/lint-pipeline.sh`, CI `pipeline.yml`.

### 11. Гигиена workflows: нет `timeout-minutes` у 6 job'ов, скачивание actionlint с `main`, нет кэша npm, установка JDK/Node/Godot копируется
- Где: без таймаута — `.github/workflows/main.yml:22-23,119-120`, `firmware.yml:16-18,78-80`, `netrun.yml:24-25,58-60,145-146` (в `:45` есть своя заметка: «05.10 один прогон встал на 50 минут»); `.github/workflows/pipeline.yml:22` (`curl … rhysd/actionlint/main/… | bash`); `actions/setup-node` без `cache: npm` в `main.yml:124`, `firmware.yml:22`; Godot ставится двумя способами: `chickensoft-games/setup-godot` в `netrun.yml:31,70,151` и `curl` в `e2e.yml:93-99` (версия 4.7.2 зашита в обоих: `netrun.yml:16`, `e2e.yml:65`).
- Что: по умолчанию job живёт до 6 часов; ссылка на скрипт без пина — риск для supply chain и источник нерепродуцируемой ошибки.
- Почему мешает: зависший прогон держит `ci-wait` до его 2-часового лимита и блокирует очередь поезда.
- Выгода: средняя.
- Риск (дверь/радиус): низкий; `main.yml` — обязательные проверки: добавление таймаута не меняет имена job'ов. Внутри `main.yml` (Pipeline), `netrun.yml` (Godot), `firmware.yml` (Узлы) — карточки соседям.
- Размер: S
- Проверить чем: `actionlint`, один прогон `workflow_dispatch`.

### 12. Конфликты `docs/backlog.md` повторяются: файл правят все зоны, в 44 из последних 300 коммитов
- Где: `docs/backlog.md` (26 строк), парсер `.claude/hooks/session-brief.sh:45-47`; нет `.gitattributes`; конфликтные слияния: «Слияние origin/main в gd-backlog-clean», «…gd-lock-hint», «…gd-p7-tail» и др. (5 из 300).
- Что: общий файл в одно место, правится построчно из 9 зон и Pipeline.
- Почему мешает: класс 1 из досье §5; каждое слияние «поезда» с затронутым бэклогом рискует остановиться.
- Выгода: средняя.
- Риск (дверь/радиус): низкий; вариант А — `docs/backlog.md merge=union` в `.gitattributes` (риск: «закрыл строку» + «правка строки» дают дубль), вариант Б — `docs/backlog/<зона>.md`, `session-brief` читает свою зону (чище, правит парсер и `zone-check`, ссылки в CLAUDE.md).
- Размер: S
- Проверить чем: два параллельных PR с разных зон с правкой «своей» строки → слияние без конфликта; `scripts/zone-check.sh`.

### 13. Мёртвое и устаревшее: `devbox-runner.sh` и раздел «Раннер на devbox» в `docs/ci.md`; README указывает на APK со случайной подписью
- Где: `scripts/devbox-runner.sh` (109 строк, вызовов нет, кроме `docs/ci.md:63-116`, где раннер назван «снят 06.10»); `README.md:44` (ссылка на артефакт `megablok10-debug-apk` из `main.yml:113`), тогда как `.github/workflows/apk.yml:4-7` объясняет, что такой APK не встанет поверх прежнего (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); `apk.yml` в README и docs не упомянут.
- Что: мёртвый скрипт и ≈55 строк документации для снятого раннера; инструкция установки ведёт игрока/мастера на неподписанную сборку.
- Почему мешает: сессия читает 55 строк «как ставить, если понадобится»; мастер на площадке ставит неподходящую сборку.
- Выгода: низкая (скрипт) / средняя (README).
- Риск (дверь/радиус): низкий; README — общий файл (по правилам — карточка Android/Pipeline), `main.yml:113-117` «Upload APK» можно убрать после правки README.
- Размер: S
- Проверить чем: `git grep devbox-runner`, `actionlint`.

### 14. `scripts/box/ctl.sh` — 1119 строк, пять подсистем в одном bash-файле, без тестов
- Где: `scripts/box/ctl.sh:46-224` (брони, очередь, `cmd_run`), `:225-889` (очки: `pico_*`, `pico_run` 583-658, `pico_show` 709-761, `cmd_pico` 782-889 — 107 строк), `:890-1004` (экземпляры `up/down/inst`), `:1005-1065` (adb-rescue), `:1066-1104` (`usb-watch`).
- Что: очки (≈660 строк) вместе с очередью и экземплярами; shellcheck чист (0 предупреждений), но `lint-pipeline.sh` его не включает, из тестов — только `netrun/tools/box_guard_selftest.sh` для соседнего `box_guard.sh`.
- Почему мешает: любая правка очков (много сбоев с 13.10: страж USB, ожидание трекинга, парковка карточки) идёт через файл на 80 КБ; боевой код управления железом без самопроверки. Важно: правка может выключить очки на владельце.
- Выгода: средняя.
- Риск (дверь/радиус): высокий — работающее железо, «очки в руках» (память `pico-headset-testing-etiquette`); делить на `box/{lease,pico,inst}.sh` с `source`, тесты на чистые функции (`pico_state`, разбор `dumpsys`) по заранее записанным выводам.
- Размер: L
- Проверить чем: `scripts/lint-pipeline.sh` (добавить файл), `scripts/box.sh status` и `box.sh pico status` на живой машине вне брони.

### 15. Контекст каждого хода: `CLAUDE.md` 21,7 КБ; повторы между CLAUDE.md, skills и rules
- Где: `CLAUDE.md` (таблица зон ≈3,5 КБ с абзацем «Единый вид Сети» внутри строки Blender; раздел «Работа агента»), `.claude/skills/orchestrate/SKILL.md` (18 КБ, таблица команд `:37-48` повторяет «Проверки» из CLAUDE.md), `.claude/rules/android-checks.md:15-19`.
- Что: CLAUDE.md сам утверждает, что «каждый прочитанный байт оплачивается на каждом ходу», но грузится целиком в каждую сессию; Blender-абзац и подробности Pipeline-строки нужны одной сессии каждому.
- Почему мешает: ≈6 тыс. токенов на каждый ход всех сессий; повторы расходятся (находка 5).
- Выгода: низкая-средняя.
- Риск (дверь/радиус): низкий; общий файл всех зон — менять по решению владельца (Pipeline владеет правилами); сокращение зон до одной строки возможно после находки 6.
- Размер: S
- Проверить чем: `wc -c CLAUDE.md`, `scripts/session-stats.py` до/после.

## Чего нет (ожидал найти и не нашёл)

- Циклов без предела: `while`/`for` в `ci-wait`, `dbx`, `sweep`, `ctl.sh:680` (дедлайн), `lib.sh` (`wait_until` по `SECONDS`) все ограничены; опроса CI руками и автоповтора «до зелёного» нет.
- Скриптов без вердикта и кода выхода среди «сквозных» (`verify`, `dbx`, `check`, `land`, `train`, `ci-wait`, `lint-pipeline`, `zone-check`, `sweep`) — все печатают итог и возвращают код; исключение — `run-all.sh` (нет таймаута на сценарий, `scripts/e2e/run-all.sh:15-17`: зависший `adb` держит до лимита job 60 минут).
- Дублей между правилами `permissions.allow` и хуком: `settings.json` только разрешает (нет `deny`), хук только запрещает; пересечений нет. Настоящая слабость там — нет второго рубежа (`deny` на `git push --force*`), находка 3.
- Найденных замечаний shellcheck в скриптах из списка lint: `LINT OK`, 0 замечаний.
- Явной ошибки в `land.sh`: проверка SAFE/UNSAFE и ff логичны; тестов нет (риск без находки, т.к. скрипт короткий и защищён хуком).

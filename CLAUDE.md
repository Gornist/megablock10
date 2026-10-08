# Правила для агентов (Claude Code и др.)

Проект: Android-приложение для LARP «Мегаблок №10» (`app/`), переиспользуемое ядро без Android (`kit/`), сервер и дашборд
мастера (`admin-web/`), прошивка точек на площадке — QR-дисплей и звук на ESP32 (`firmware/display/`), стенд e2e на двух
эмуляторах (`scripts/e2e/`). Всё здесь выверено на реальных сбоях — не обходите.

Прочитать перед работой — всем: [docs/progress.md](docs/progress.md) (где мы сейчас, коротко); `main`, своя копия, worktree и открытые PR —
уже в сводке хука `session-brief` в начале контекста (повторять `git log`/`gh pr list` не нужно). Дальше — только свою
область и только нужные разделы (`grep -n` по заголовкам, потом Read с `offset/limit`):

| Область | Документы |
|---|---|
| Android (`app/`, `kit/`, `rules/`) | [docs/android-handoff.md](docs/android-handoff.md), [docs/architecture.md](docs/architecture.md), [docs/refactor-plan.md](docs/refactor-plan.md) |
| e2e (`scripts/e2e/`) | [scripts/e2e/README.md](scripts/e2e/README.md), `.claude/rules/e2e.md` |
| Коллектор (`admin-web/`) | [admin-web/docs/agent-pipeline.md](admin-web/docs/agent-pipeline.md); `admin-web/README.md` (55 КБ) — только по разделам |
| Сеть (`netrun/`, `netrun-bridge/`) | [docs/netrun.md](docs/netrun.md), [docs/netrun-devbox.md](docs/netrun-devbox.md), skill `netrun-loop`; протокол — [docs/netrun-bridge-protocol.md](docs/netrun-bridge-protocol.md) (58 КБ) по разделам |
| Прошивка (`firmware/`) | [docs/displays.md](docs/displays.md), [docs/firmware-plan.md](docs/firmware-plan.md), [docs/sound-nodes.md](docs/sound-nodes.md) |

## Зоны сессий

Параллельно работают несколько сессий, у каждой своя зона записи. Чужую зону **читать можно, править нельзя**: нужна правка у соседа —
описать её ему (SendMessage: файл, что и почему) или владельцу. Пересечение зон уже ломало CI (`git add -A` унёс чужую незаконченную работу).

| Сессия | Пишет | Не трогает (чьё) |
|---|---|---|
| **Android App** | `app/`, `kit/`, `rules/`, `scripts/e2e/`, Android-документы | пакет `collector/` в приложении — только тесты (контракт с Коллектором) |
| **Коллектор** | `admin-web/` — сервер и дашборд мастера, приём изменений, БД и миграции, auth, связь с Мостом со стороны коллектора | `admin-web/server/src/displays/`, `audio/`, `routes/audio.ts`, `scripts/display*.ts` и их тесты (Физические узлы) |
| **Физические узлы** | `firmware/` (QR-дисплей, звук), в `admin-web/server/src/`: `displays/`, `audio/`, `routes/audio.ts`, `scripts/display*.ts` и их тесты; `.github/workflows/firmware.yml`; `docs/displays.md`, `firmware-plan.md`, `sound-nodes.md` | остальной `admin-web/` (Коллектор) |
| **Godot** | `netrun/` — сервер мира, игра, дека, сеть и формат сообщений (`netrun/server/`, `netrun/shared/`), `netrun-bridge/`, `docs/netrun*.md` | ассеты и вид аватара (Blender); цвета и материалы своих видимых элементов (маркеры пола, прицел, след ICE, HUD, метки) не задаёт — берёт константы `AssetMaterials` |
| **Blender** | вид Сети: `netrun/assets/` (модели, `src/*.py`, шейдеры, превью, `ARCHITECTURE.md`, `STYLE.md`) и отрисовка тела и рук в `netrun/client/` (`avatar_view.gd`, `hand_view.gd`, `avatar_body.gd`, `head_*.gd`; окружение `node_view.gd`, `ice_view.gd` — Godot), тесты ассетов `netrun/tests/assets_*`; **палитра и материалы всех видимых элементов клиента** — константы в `AssetMaterials` по `STYLE.md` | формат сообщений и сеть (`netrun/shared/`, `netrun/server/` — Godot): новые поля позы — предложить Godot-сессии |

Единый вид Сети (07.10: превью Blender и клиент разошлись настолько, что «две разные игры» — коричневые клетки и зелёный прицел мимо палитры,
приёмка по своему стенду): вид принимают только по кадру клиента (`netrun/tools/dev.sh shot res://tests/foyer_preview.tscn`, пресеты
`EyePresets`) и кадру с очков; стенд Blender — для замеров. Новый видимый элемент клиента: Godot — логика и геометрия, Blender — цвет и материал.
| **Геймдизайн** | `docs/gamedesign/` — документы проекта и модель (`docs/gamedesign/model/`) | код всех зон: изменения — карточками сессиям зон, код пишут они (решение владельца 06.10) |
| **LARP** | `docs/story/` — сюжет и мир ларпа: библия мира, фракции, вводные, линии «сюжет × приложение» | код всех зон: изменения — карточками сессиям зон; связь с Сетью — через Геймдизайн (решение владельца 08.10) |
| **Pipeline manager** | общие правила и инструменты: `CLAUDE.md`, `.claude/` (хук, настройки, общие skills), общие `scripts/` (`check`, `verify`, `dbx`, `ci-wait`, `agent-worktree`, `zone-check`, `train`, `land`, `session-stats`, `test-hook`, `lint-pipeline`, `devbox-runner`), `.github/dependabot.yml`, `labeler.yml`, workflows `main`/`pipeline`/`labeler`, `docs/ci.md`; `scripts/phone.sh` дополняет и Android App; **очередь слияний в `main` за все сессии** (Git и процесс) | код областей |

Общее для всех: `docs/progress.md` — каждая сессия правит только свой раздел; `.github/workflows/` своей области — можно, `main.yml` — через
Pipeline manager. Работать в своей worktree (`scripts/agent-worktree.sh new <имя>`), добавлять файлы явными путями, в `main` — только владелец.
Перед коммитом и PR — `scripts/zone-check.sh <android|collector|nodes|godot|blender|gamedesign|story|pipeline>`: печатает файлы вне зоны (таблица продублирована в скрипте —
правите таблицу, правьте и его).

## Работа агента: время и токены

Каждый прочитанный байт и каждая картинка остаются в контексте и оплачиваются на **каждом** следующем ходу — это главная статья расхода
(замеры трёх сессий 03–04.10: целые документы — 6,9 млн символов, 241 кадр PNG, ≈40 пустых ходов ожидания, 233 правки через python-heredoc).

- **Читать точечно:** `grep -n` → Read с `offset/limit`; файл > 300 строк целиком не читать. Длинный вывод команды — в файл, в контекст — `tail`/grep по итогу.
- **Править только Edit/Write**, не `python3 - <<EOF`/`sed -i` по многострочному тексту (файл дважды идёт через контекст).
- **Картинки — последнее средство:** текст страницы — `get_page_text`/`read_page`; кадры — одной сеткой ≤ 1024 px (`netrun/tools/dev.sh shot`, `DEV_CROP`),
  серия кадров с чек-листом — агент `visual-reviewer`; скриншот браузера — `scale: 0.5`.
- **Проверять по изменённому — `scripts/verify.sh`:** сам выбирает проверки затронутых областей (Android — `dbx.sh --auto`, Godot — `dev.sh test`,
  коллектор — `admin-web/tools/test.sh <часть>`, мост — Gradle на devbox) и печатает одну строку `VERIFY`; `--dry` — показать набор.
  Полный прогон — `scripts/verify.sh --full`, один раз перед PR и в фоне.
- **Ждать одним фоновым вызовом с одним итогом** (Bash `run_in_background`: `scripts/ci-wait.sh pr N` — на красном сам кладёт журнал упавших шагов в файл и печатает путь, `dbx.sh`, `dev.sh test --all`). Никаких `sleep`,
  Monitor с выводом на каждую итерацию и опроса CI руками. Любой цикл — с пределом итераций. Пока ждёшь — следующая независимая работа.
- **Скрипты печатают вердикт** (1–5 строк, код выхода 0/1, путь к полному журналу). Новый инструмент делать так же; длинные цепочки ssh/rsync/adb,
  повторённые дважды, — в скрипт (`scripts/phone.sh`, `dbx.sh`, `dev.sh`).
- **Делегировать** — skill `orchestrate`: Haiku 5.5 (агент `scout`) — поиск «где X» и механика по точному списку; Sonnet — код по карточке, кадры, разбор падений;
  Opus — контракты, деньги/записи/auth, ревью рискованного диффа. Меньше трёх вызовов — делать самому. Отчётам агентов не верить на слово:
  один раз прогнать проверку самому и посмотреть `git diff --stat`.
- **Не автоматизировать:** push в `main`, rebase/force, `--no-verify`, удаление веток и worktree, автоповтор CI «до зелёного», перезапись эталонов.
  Часть запретов проверяет хук `.claude/hooks/guard-bash.sh` (`git add -A`, push в `main` и `--force`, `--no-verify` вне devbox, `cleanTest*`,
  правка через python-heredoc, `sleep` > 30 с, rsync `netrun` без `--delete`, gdunit мимо `dev.sh`); скрипты-вердикты разрешены без запроса
  (`permissions.allow` в `.claude/settings.json`).

## Git и процесс

- Коммиты, комментарии и документация — на русском. Сообщение коммита: что и **почему** (какой сбой, какой журнал).
- В `main` — только по явной команде владельца, перемоткой (fast-forward) с зелёными CI и e2e. Историю `main` не переписывать.
- **Слияния ведёт Pipeline manager** (решение владельца 06.10: он не должен ходить по сессиям и собирать, что готово):
  1. Сессия доводит ветку: `verify.sh --full`, `zone-check.sh`, пуш, PR, зелёный CI (`scripts/ci-wait.sh pr N` в фоне).
  2. Пишет Pipeline manager (SendMessage, не владельцу): «готово к слиянию: PR N — что внутри; порядок/пара с PR M; ждёт ли решения владельца».
  3. Pipeline manager собирает готовые PR поездом (`scripts/train.sh`, один CI на свежем `main`), владелец вливает одной командой
     `scripts/land.sh N`. Агентам перемотка `main` запрещена хуком. Механика очереди, поездов, пар и уборки — `docs/ci.md`.
  4. Чужую ветку Pipeline manager меняет только вливанием `origin/main` и предупреждает её сессию.
- **После «влит» — новая задача в новой worktree** (`agent-worktree.sh new`): `land.sh` сам убирает ветки `agent/*` влитых PR и их
  чистые worktree (с незакоммиченным или игнорируемыми файлами — оставляет и называет), GitHub удаляет ветку PR. Своё нужное
  вне git (карточки, журналы) держать вне worktree. Ветки без PR и невлитые — `agent-worktree.sh gone <имя>`, удаляет владелец.
- Одна ветка — один исполнитель. Параллельная работа — `scripts/agent-worktree.sh new <имя>` (своя копия и ветка `agent/<имя>`).
- Не коммитить незавершённое «на потом»: после каждого шага ветка собирается и тесты зелёные.
- **Контракт между зонами** (версии в `/api/capabilities`, формат записей мира, сообщений Моста, QR, приложение↔коллектор) меняется так, чтобы
  `main` был зелёным после **каждого** слияния: сначала читающая сторона принимает и старую, и новую версию, потом пишущая поднимает версию;
  парные PR — в одном порядке, сосед предупреждён сообщением. Так было не всегда: 05.10 коллектор объявил `world_records: 2` раньше, чем Мост
  стал его принимать (Мост ждал ровно 1) — между двумя слияниями e2e на чужом PR краснел не из-за его правок.

## Окружение агентов

- Правила области подгружаются сами при работе с её файлами (`.claude/rules/*.md`, поле `paths`): Android и Gradle — `android-checks.md`,
  инварианты денег и транзакций — `app-invariants.md`, e2e — `e2e.md`, Godot — `netrun-godot.md`, прошивка и Wokwi — `firmware.md`.
  Здесь — только общее для всех.
- Облачное окружение настраивает `scripts/cloud-setup.sh` (копия вставлена в Setup script окружения; правите скрипт — обновите копию):
  SDK, зеркало Maven, плагины Claude Code (code-review, KotlinSense), PlatformIO.

## Проверки

| Что | Команда | Где |
|---|---|---|
| Всё локально | `scripts/check.sh --all`; по изменённому — `scripts/verify.sh` | pre-push хук (`scripts/setup-hooks.sh`) — `check.sh --fast` (≤ 1 мин): detekt, lint, kit, сервер; без Robolectric/Paparazzi |
| Android, kit, Мост (Gradle) | `scripts/dbx.sh --auto\|--full` на devbox; команды Gradle и грабли Paparazzi — `.claude/rules/android-checks.md` | никогда `cleanTest*` (стирает эталоны) |
| CI | `.github/workflows/main.yml` (push/PR в `main`, вручную) | ≈4 мин |
| e2e | `scripts/e2e/up.sh && scripts/e2e/run-all.sh`; CI — `e2e.yml` (PR в `main` с правкой `app/`, `kit/`, `scripts/e2e/`; ночью; вручную) | ≈17 мин |
| Коллектор | `admin-web/tools/test.sh server\|client\|lint\|build\|all` (сам берёт Node ≥ 22, вердикт строкой; свежий worktree — сначала `admin-web/tools/wt-deps.sh`) | в CI — `main.yml`, job admin-web |
| Godot (netrun) | `netrun/tools/dev.sh test` / `test --all` (в фоне) / `shot`, агент `godot-dev` — `.claude/rules/netrun-godot.md` | devbox; CI — `netrun.yml` |
| Прошивка | cmake/ctest, `pio`, Wokwi (квота!) — `.claude/rules/firmware.md` | CI — `firmware.yml`; ≈5 мин |
| Конвейер (скрипты, хук, workflows) | `scripts/lint-pipeline.sh` (shellcheck, actionlint, таблица хука `scripts/test-hook.cases`); правите хук — добавьте случай в таблицу | CI — `pipeline.yml` (правка `scripts/`, `.claude/hooks/`, `.github/workflows/`); ≈1 мин; метки зон на PR — `labeler.yml`; раннер devbox — `docs/ci.md` |

- Не утверждать «проверено», не дождавшись проверки (облачная сессия без SDK проверяет только через CI).

## Где что запускать

- **Mac (8 ГБ):** правка, git, `scripts/check.sh --fast`. Gradle, Paparazzi, e2e, Godot, Мост — **на devbox** (`ssh devbox`),
  долгое через `devjob` — skill `devbox`. Параллельных Gradle и стендов e2e нет: одна задача на машину.
  На Mac нет `timeout` (GNU), Pillow и ImageMagick, bash — 3.2: сетки кадров, обработку картинок и всё с пределом времени — на devbox.
- **Gradle на devbox — `scripts/dbx.sh --auto|--full`** (очередь, один итог; skill `orchestrate`). Большая задача из 3+ шагов — по skill `orchestrate`
  (разведка одним агентом с досье, исполнители sonnet, ожидание одним фоновым вызовом, `scripts/ci-wait.sh`).
- Цикл задачи: правка → `check.sh --fast` (Mac) → тяжёлая проверка на devbox → коммит → `/clear`. Новое окно начинать с
  `docs/progress.md` и документов своей области (таблица вверху); состояние git и PR — в сводке хука на старте.
- Середина длинной задачи, контекст тяжёлый — не `/clear`, а `/compact` с подсказкой (набирает владелец): «оставь карточку,
  решения, что сделано и не проверено, следующий шаг». Перед этим сессия сама кратко пишет эти пункты — сжатие опирается на них.
- **Своя worktree на сессию** (`scripts/agent-worktree.sh new <имя>`): основной checkout общий для всех сессий — в нём не править и не коммитить.
- Сбой: сначала журналы — skill `debug-journals`, потом гипотезы.
- Инварианты приложения (деньги, транзакции, сеть) — `.claude/rules/app-invariants.md`: нарушение = потеря денег/данных у игроков, читать **до** правки `app/`, `kit/`.

# Инструкция для агента: миграция интерфейса на новый стиль

**Миграция завершена** (M0–M5 в `main`, см. [ui-migration-plan.md](ui-migration-plan.md)); отдельную сессию «ui-kit» запускать не нужно.
Документ остался как инструкция исполнителю для любой правки интерфейса приложения игрока: что можно трогать, как переносить
компонент, чем проверять. Правила репозитория ([CLAUDE.md](../../CLAUDE.md), зона **Android App**) важнее этой инструкции.

## Прочитать до начала

1. [ui-style-guide.md](ui-style-guide.md) — токены, шрифты, фаски, размеры, компоненты, «нельзя».
2. [ui-migration-plan.md](ui-migration-plan.md) — что где лежит в `ui/theme/`, что не меняется, решения владельца, что осталось.
3. [prototype/mb10-ui-kit.html](prototype/mb10-ui-kit.html) — живой эталон (вкладка «Компоненты» — каталог, «Экраны» — 19 экранов); точные
   цвета и отступы — в его CSS. Если прототип и гайдлайн расходятся — прав прототип (гайдлайн поправить).
4. [docs/architecture.md](../architecture.md), [android-handoff.md](../android-handoff.md) — устройство приложения; `.claude/rules/app-invariants.md` — до правки `app/`.

## Границы

**Можно менять:** `ui/theme/**`, `ui/nav/**`, `ui/screens/*Screen.kt`, `CallOverlay.kt`, `AnnouncementDialogHost.kt`, `ItemTransferUi.kt`,
`SetupScreen` (в `MainActivity.kt`), `breach/BreachScreen.kt`, `res/font/**`, скриншот-тесты и эталоны `app/src/test/snapshots/`,
координатные скрипты `scripts/e2e/audit-screens.sh` и `demo.sh`, документы `docs/ux/**`, раздел UI в `docs/architecture.md`.

**Только отдельным шагом с тестом:** ViewModel (счётчики, баланс в шапке, состояние синка).

**Нельзя:**
- `admin-web/` — зона Коллектора;
- сеть, синк, хранилища, Room-схема, журнал и события `Mb10Log`, строки `MB10DBG`, `scripts/e2e/log-contract.tsv`;
- инварианты денег и транзакций (`SendOutcome.UNKNOWN`, адреса пиров, фоновый старт);
- тексты, по которым стенд нажимает элементы («Взломать контейнер», «Принять», «Принято», «Отправить», «Настройки», «Демоны», «Шарды»,
  «Сообщение от мастера», имена демонов мок-взлома) — только вместе с правкой `scripts/e2e` в том же коммите.

## Порядок работы

1. Своя worktree: `scripts/agent-worktree.sh new <имя>`; в `main` — только по правилам слияния из CLAUDE.md.
2. Маленькими шагами. После каждого: сборка и тесты зелёные, намеренно изменившиеся скриншоты перезаписаны (`recordPaparazziDebug`) и
   закоммичены вместе с правкой, коммит на русском (что и почему), в индекс — свои файлы по путям (не `git add -A`).
3. Экран за экраном: следующий — когда предыдущий зелёный, включая e2e на CI (`e2e.yml` запускается на PR с правкой `app/`).
4. Удаляя компонент — сначала `grep`, что он нигде не используется.

## Проверки

| Что | Команда |
|---|---|
| Быстро (≤ 1 мин, Mac) | `scripts/check.sh --fast` |
| Gradle, скриншоты, тесты (devbox) | `scripts/dbx.sh --auto` / `--full`; внутри — `verifyPaparazziDebug` (без скриншотов — `testDebugUnitTestNoScreenshots`) |
| Перезаписать эталоны | `recordPaparazziDebug` (через `dbx.sh`) |
| Статика | detekt и lint — в `scripts/check.sh --fast` (перед пушем это же делает pre-push хук) |
| e2e | `scripts/e2e/up.sh && scripts/e2e/run-all.sh` на devbox; на CI — `e2e.yml` ([README стенда](../../scripts/e2e/README.md)) |

- **Никогда `cleanTest*`** — Paparazzi считает `app/src/test/snapshots/` выходом задачи и сотрёт эталоны (стёрлись — `git restore app/src/test/snapshots`); команды и грабли — `.claude/rules/android-checks.md`.
- Gradle на Mac не запускать. Не писать «проверено», не дождавшись результата; после пуша досмотреть CI до конца.
- Красный e2e — сначала журнал (skill `debug-journals`), потом гипотезы. Разовый красный — не «флейк».

## Как переносить компонент

- Имена — из гайдлайна (`MbButton`, `MbListItem`, `MbDialog`…), файлы — в `ui/theme/` (плоский список `Mb*.kt`).
- Цвета — только токены `MbColors` из `LocalMbColors` (темы Default / Breach / Success). Ни одного `Color(0x…)` на экранах.
- Рамка — только `MbChamfer`/`Modifier.mbFrame` одной из трёх форм (Std / Tab / Dlg). Ни `Modifier.border` без формы, ни `RoundedCornerShape` (`NoRectangularBordersTest`).
- Нажимаемое — `Modifier.minimumInteractiveComponentSize()` (48 dp) при любом размере рисунка.
- Иконка без текста — `contentDescription`; декоративная — `null`.
- Состояния: нажато / выключено / фокус — у кнопок, строк, вкладок.
- Текст — `sp`, не мельче 11 sp; масштаб шрифта 1,3× (`FontScaleTest`).
- Системные отступы (targetSdk 35, edge-to-edge): внутри `MbAppShell` — делает оболочка; экран вне оболочки или оверлей ставит `windowInsetsPadding(WindowInsets.safeDrawing)` / `statusBars` / `navigationBars` сам (гайдлайн, раздел 4).
- Шрифты — `res/font`, не Downloadable Fonts: на площадке нет интернета.
- Каждый компонент — в Paparazzi-каталоге `KitCatalogTest`, каждый экран — свой снимок с фейковым состоянием.

## Когда остановиться и спросить владельца

- Нужно поменять что-то вне границ (сеть, данные, тексты для стенда без правки стенда, `admin-web`).
- Прототип и гайдлайн противоречат друг другу, или экрана/состояния нет в прототипе.
- Экран взлома не помещается на 360 × 640 dp даже после ужатия.
- e2e красный, и журнал не объясняет почему.

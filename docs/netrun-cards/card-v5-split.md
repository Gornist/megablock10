# Дополнение к карточке В5 (разбивка на два исполнителя)

Основная карточка (читать целиком, там досье и правила): `/Users/peachbite/Developer/megablock10-wt/gamedesign/.cards/w1-v5-godot.md`. Чужую worktree `gamedesign` не править. Общие правила исполнителя: `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md`.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/gd-w1-port`, ветка `agent/gd-w1-port` (создана от `origin/agent/gd-w1-breach`; новые `netrun/data/rules/breach.json` и `netrun/tests/fixtures/breach_golden.json` уже в ней — НЕ править, их выгружает Kotlin-тест). Копия на devbox — `~/wt-gd-w1-port`. Не пушить, не открывать PR.

**Расширение зоны записи** (к зоне основной карточки): `netrun/tests/charge_world_test.gd` (один из красных тестов — чинит В5).
Если карточка противоречит коду или красный тест не объясняется правилом §2 `docs/gamedesign/breach.md` — не угадывай, опиши в отчёте и остановись на этом шаге.

## Часть 1 (исполнитель В5-1): шаги 1–4 основной карточки
Данные тира → сетка с замком и приманками → засчитывание и исход → `BreachRun.for_storage` и `vault_breach.gd` (сообщение старта взлома клиенту пока НЕ меняй — это шаг 5). После шагов зелёными должны стать `breach_data_test`, `breach_run_test`, `breach_grid_test`, `breach_attempt_test`, `charge_world_test`; `breach_golden_test` и зеркало/панель — во второй части (golden требует знания замка автосолвером — шаг 6). Проверка после каждого шага — `netrun/tools/dev.sh test <имена>`; в отчёте — какие тесты ещё красные и почему (ожидаемо: golden, mirror, panel).
Заряд и расшифровка (`for_charge`, `for_decrypt`) берут `cipher_timer_sec` (45/60/75), не `timer_sec`, замок = 0 там не меняет поведение.
Отчёт ≤15 строк: коммиты, тесты по именам (зелёные/красные), новые публичные имена (поля данных, функции, признак `lock_opened`), отклонения.

## Часть 2 (исполнитель В5-2): шаги 5–8 основной карточки
Зеркало и сообщение старта, golden с замком и автосолвер, щуп `breach_probe_test.gd` (отдельный набор), документы (`docs/netrun-bridge-protocol.md` раздел клиент↔сервер, `docs/netrun-deck-design.md` §10), полный прогон `dev.sh test --all` одним фоновым вызовом. Читай коммиты части 1 (`git log` ветки) и отчёт оркестратора в начале промпта. В отчёте — доли щупа числами, время щупа, итог `--all`.

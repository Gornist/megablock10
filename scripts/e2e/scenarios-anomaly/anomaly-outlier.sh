#!/bin/bash
# Игрок-выброс: 6 игроков по 3 взлома, у одного 40 → player_outlier (нужно ≥5 активных, взломов ≥10). Пока у всех по 3 — тревоги нет.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-outlier"
anom_up
# Запись о взломе — тот же JSON, что шлёт приложение (FinishBreach): сервер принимает в counters.* только JSON-объект.
BREACH='{"tier":"BASE","outcome":"success"}'
for i in 1 2 3 4 5 6; do fake register O$i --balance 100 >/dev/null; fake send O$i --field counters.breach --new "$BREACH" --reason BREACH_ATTEMPT --repeat 3 >/dev/null; done
expect_no_kind player_outlier "у всех по 3 взлома — выбросов нет"
fake send O1 --field counters.breach --new "$BREACH" --reason BREACH_ATTEMPT --repeat 37 >/dev/null
expect_kind player_outlier 10
check "выброс — игрок O1" bash -c "source '$ROOT/scripts/e2e/anom-lib.sh'; item_field player_outlier detail | grep -q 'O1'"
anom_finish

#!/bin/bash
# Неверный код игры: сервер с GAME_SECRET; запросы без заголовка → 401 → secret_denied (от 3 отказов). С верным кодом всё принимается.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-secret"
anom_up GAME_SECRET=anom-secret-12345
export GAME_SECRET=anom-secret-12345
eq "с верным кодом запись принята" 3 "$(fake register Good --balance 100 | python3 -c 'import sys,json;print(json.load(sys.stdin)["accepted"])')"
expect_no_kind secret_denied
OUT=$(fake --secret none beat Good --repeat 5)
check "без кода все запросы получили 401" bash -c "echo '$OUT' | grep -q '\"401\":5'"
expect_kind secret_denied 15
anom_finish

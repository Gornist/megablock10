#!/bin/bash
# Сброс сессии на телефоне: позывной и фракция остаются в снимке игрока на дашборде (персонаж — набор данных), выставляется sessionResetAt,
# сброшенное устройство не считается в «Обзоре».
source "$(dirname "$0")/../anom-lib.sh"
echo "== session-reset"
anom_up
fake register Zed --faction Rats --balance 250 --ram 9 >/dev/null
eq "до сброса игрок считается" 1 "$(api GET /api/overview | jq_ 'd["players"]["total"]')"
eq "до сброса sessionResetAt пуст" None "$(player_field Zed sessionResetAt)"
fake reset Zed >/dev/null
eq "позывной остался в снимке" 1 "$(players_named Zed)"
eq "фракция осталась в снимке" Rats "$(player_field Zed faction)"
eq "баланс остался в снимке" 250 "$(player_field Zed balance)"
check "выставлен sessionResetAt" bash -c "source '$ROOT/scripts/e2e/anom-lib.sh'; [ \"\$(player_field Zed sessionResetAt)\" != None ]"
eq "сброшенное устройство не считается в обзоре" 0 "$(api GET /api/overview | jq_ 'd["players"]["total"]')"
anom_finish

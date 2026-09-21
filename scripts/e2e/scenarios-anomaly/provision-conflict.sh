#!/bin/bash
# Копия применённого QR персонажа: второй телефон с тем же номером выдачи получает отказ, игрока-копии на дашборде нет, тревога provision_conflict.
# Честное применение кода тревоги не даёт.
source "$(dirname "$0")/../anom-lib.sh"
echo "== provision-conflict"
anom_up
ID=$(provision_new Ghost Neon 100 8)
eq "первый телефон применил код (4 записи приняты)" 4 "$(fake register Ghost --faction Neon --balance 100 --ram 8 --provision "$ID" | jq_ 'd["accepted"]')"
expect_no_kind provision_conflict "честное применение кода — тревоги нет"
OUT=$(fake register Copy --faction Neon --balance 100 --provision "$ID")
check "копия получила отказ «уже применён на другом телефоне»" bash -c "echo '$OUT' | grep -q 'provision code already applied on another device'"
eq "игрок-копия на дашборде не появился" 0 "$(players_named Copy)"
eq "исходный игрок на месте" 1 "$(players_named Ghost)"
expect_kind provision_conflict 10
anom_finish

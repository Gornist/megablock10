#!/bin/bash
# Погашенный код: после повторной выдачи прежний, ещё не применённый код отклоняется с текстом «выдан заново»; новый применяется.
source "$(dirname "$0")/../anom-lib.sh"
echo "== provision-void-code"
anom_up
ID=$(provision_new Ghost Neon 100 8)
fake register Ghost --faction Neon --balance 100 --ram 8 --provision "$ID" >/dev/null
KEY=$(fake key Ghost)
ID2=$(reissue "$KEY")      # первый код выдачи «заново» — ещё не применён
ID3=$(reissue "$KEY")      # второй гасит первый
OUT=$(fake register Late --faction Neon --balance 100 --provision "$ID2")
check "погашенный код отклонён с текстом «выдан заново»" bash -c "echo '$OUT' | grep -q 'provision code is no longer valid (issued again)'"
eq "игрок с погашенным кодом не появился" 0 "$(players_named Late)"
eq "актуальный код применяется" 4 "$(fake register Fresh --faction Neon --balance 100 --ram 8 --provision "$ID3" | jq_ 'd["accepted"]')"
anom_finish

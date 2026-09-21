#!/bin/bash
# «Выдать заново»: новый код по параметрам из снимка; когда новый телефон применил его, у старого ключа replacedBy, у нового replaces,
# остаток старого ключа не входит в «Экономику» и в число игроков обзора.
source "$(dirname "$0")/../anom-lib.sh"
echo "== provision-reissue"
anom_up
ID=$(provision_new Ghost Neon 300 8)
fake register Ghost --faction Neon --balance 300 --ram 8 --provision "$ID" >/dev/null
OLDKEY=$(fake key Ghost)
ID2=$(reissue "$OLDKEY")
[ -n "$ID2" ] || die "«Выдать заново» не создал код"
eq "новый код подставил сохранённый баланс 300" 300 "$(api GET /api/provisions | jq_ "next(i['balance'] for i in d['items'] if i['id']=='$ID2')")"
eq "новый код связан со старым ключом" "$OLDKEY" "$(api GET /api/provisions | jq_ "next(i['replacesKey'] for i in d['items'] if i['id']=='$ID2')")"
eq "новый телефон применил код" 4 "$(fake register Ghost2 --faction Neon --balance 300 --ram 8 --provision "$ID2" | jq_ 'd["accepted"]')"
NEWKEY=$(fake key Ghost2)
eq "у старого ключа replacedBy = новый" "$NEWKEY" "$(player_field Ghost replacedBy)"
eq "у нового ключа replaces = старый" "$OLDKEY" "$(player_field Ghost2 replaces)"
eq "в «Экономике» остаток старого ключа не считается (300, а не 600)" 300 "$(api GET /api/economy | jq_ 'd["totalSupply"]')"
eq "в обзоре один игрок, а не два" 1 "$(api GET /api/overview | jq_ 'd["players"]["total"]')"
anom_finish

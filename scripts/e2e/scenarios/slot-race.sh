#!/bin/bash
# Гонка за последний экземпляр: контейнер с одним слотом, оба игрока ломают его одновременно.
# Ожидание: сервер отдаёт слот ровно одному; у второго «КЭШ ОЧИЩЕН»; на дашборде copiesClaimed = 1.
source "$(dirname "$0")/../lib.sh"
echo "== slot-race"
ID=race-$RANDOM
QR=$(container $ID "Гонка" BASE Ghosts 1) || die "не создал контейнер"
autosolve $A true; autosolve $B true
breach $A "$QR" & breach $B "$QR" & wait
sleep 5
shards_total() { echo $(( $(q $A "select count(*) from shards where id like '%$ID%'") + $(q $B "select count(*) from shards where id like '%$ID%'") )); }
eq_wait 20 "ровно один шард на двоих" 1 shards_total
claimed() { api GET /api/slots | jq_ "sum(s['copiesClaimed'] for s in d if s['containerId']=='$ID')"; }
eq_wait 90 "на дашборде тираж выбран" 1 claimed   # до сервера — через синк
finish

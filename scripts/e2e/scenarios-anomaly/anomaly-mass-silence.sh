#!/bin/bash
# Массовое молчание: 6 устройств на связи 15 с, затем замолкают на 30 с. Пока все на связи — тревоги нет; после — mass_silence (срочная).
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-mass-silence"
anom_up
fake_swarm 6 S --balance 100
end=$((SECONDS+16)); while [ $SECONDS -lt $end ]; do for i in 1 2 3 4 5 6; do fake beat S$i >/dev/null; done; sleep 1.5; done
eq "все шестеро на связи" 6 "$(api GET /api/overview | jq_ 'd["players"]["online"]')"
expect_no_kind mass_silence "пока все на связи, массового молчания нет"
sleep 30
expect_kind mass_silence 25
eq "тревога срочная" crit "$(item_field mass_silence severity)"
anom_finish

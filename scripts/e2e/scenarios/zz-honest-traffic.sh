#!/bin/bash
# Ложные срабатывания: после всех обычных сценариев (честный трафик двух эмуляторов, в имени zz — идёт последним) на основном сервере не должно быть
# тревог о подделке. Сюда не входят game-secret и сценарии-провокаторы (у них отдельный сервер, см. anomaly-all.sh).
source "$(dirname "$0")/../lib.sh"
echo "== honest-traffic"
ALL=$(api GET /api/attention | jq_ '", ".join(sorted(set(i["kind"] for i in d["items"]))) or "(нет)"')
echo "  (тревоги сейчас: $ALL)"
for k in duplicate_receive transfer_amount_mismatch balance_unexplained clock_skew reject_spike; do
  eq "честный трафик не даёт тревоги $k" 0 "$(api GET /api/attention | jq_ "sum(1 for i in d['items'] if i['kind']=='$k')")"
done
finish

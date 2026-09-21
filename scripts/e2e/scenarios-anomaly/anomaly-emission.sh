#!/bin/bash
# Скачок эмиссии: ≈55 с спокойной игры (база для сравнения — не меньше 20 сэмплов), затем 3 награды по 500 → emission_spike. До всплеска тревоги нет.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-emission"
anom_up
for i in 1 2 3; do fake register E$i --balance 100 >/dev/null; done
sleep 55
expect_no_kind emission_spike "спокойная игра — скачка эмиссии нет"
fake send E1 --field balance --delta 500 --reason BREACH_EDDIES --repeat 3 >/dev/null
expect_kind emission_spike 20
anom_finish

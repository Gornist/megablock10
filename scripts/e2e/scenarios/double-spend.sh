#!/bin/bash
# Гонка «двойной тап»: несколько одновременных переводов при недостаточном балансе — баланс не должен уйти в минус.
source "$(dirname "$0")/../lib.sh"
echo "== double-spend"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
dbg $A DEBUG_SET --es balance 100; sleep 2
BEFORE=$(q $A 'select count(*) from transactions where amount = -30')
# 8 одновременных переводов по 30 при балансе 100: пройти могут только три (90), остальные должны быть отклонены.
dbg $A DEBUG_SET --es pay "$PKB:30:offline" --ei burst 8; sleep 5
eq "баланс не ушёл в минус (100 − 3×30)" 10 "$(q $A 'select coalesce(sum(amount),0) from transactions')"
eq "принято ровно три перевода" 3 "$(( $(q $A 'select count(*) from transactions where amount = -30') - BEFORE ))"
finish

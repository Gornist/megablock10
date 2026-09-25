#!/bin/bash
# Гонка «двойной тап»: несколько одновременных переводов при недостаточном балансе — баланс не должен уйти в минус.
source "$(dirname "$0")/../lib.sh"
echo "== double-spend"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
dbg $A DEBUG_SET --es balance 100
eq_wait 15 "стартовый баланс" 100 bal_of $A
BEFORE=$(q $A 'select count(*) from transactions where amount = -30')
# 8 одновременных переводов по 30 при балансе 100: пройти могут только три (90), остальные должны быть отклонены.
# Ждать нужного баланса здесь нельзя: по пути к минусу он прошёл бы и через 10. Сначала — что все 8 попыток отработали (каждая пишет
# «pay id=…» или «pay rejected»), потом разовое чтение.
adb_ $A logcat -c
dbg $A DEBUG_SET --es pay "$PKB:30:offline" --ei burst 8
attempts() { adb_ $A logcat -d -s MB10DBG | grep -cE "pay id=|pay rejected"; }
eq_wait 30 "все 8 попыток перевода отработали" 8 attempts
eq "баланс не ушёл в минус (100 − 3×30)" 10 "$(bal_of $A)"
eq "принято ровно три перевода" 3 "$(( $(q $A 'select count(*) from transactions where amount = -30') - BEFORE ))"
finish

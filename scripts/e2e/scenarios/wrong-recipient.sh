#!/bin/bash
# Карточка платежа адресована конкретному получателю (он в подписи): чужую копию принять нельзя, деньги из воздуха не создаются.
source "$(dirname "$0")/../lib.sh"
echo "== wrong-recipient"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
bal() { q $B "select coalesce(sum(amount),0) from transactions"; }
dbg $B DEBUG_SET --es balance 50
eq_wait 15 "стартовый баланс B" 50 bal

# Подложная карточка: подписана A, но адресована не B → B её не принимает
adb_ $A logcat -c
card_of() { adb_ $A logcat -d -s MB10DBG | grep -o 'card=.*' | tail -1 | cut -d= -f2- | tr -d '\r'; }
dbg $A DEBUG_SET --es forgecard "someone-else:500"
FORGED=$(await 15 card_of)
[ -n "$FORGED" ] || die "подложная карточка не создана"
adb_ $B logcat -c
dbg $B DEBUG_SET --es recv "$FORGED"
check "карточка не для B отклонена" wait_until 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep -q 'recv -> false'"
eq "баланс B не изменился" 50 "$(bal)"

# Карточка, адресованная именно B, принимается — и ровно один раз
adb_ $A logcat -c
dbg $A DEBUG_SET --es forgecard "$PKB:25"
OK=$(await 15 card_of)
[ -n "$OK" ] || die "карточка для B не создана"
adb_ $B logcat -c
dbg $B DEBUG_SET --es recv "$OK"
eq_wait 15 "адресованная B принята" 75 bal
adb_ $B logcat -c
dbg $B DEBUG_SET --es recv "$OK"
wait_until 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep -q 'recv -> false'" || log "$B: повтор карточки не отработал за 15 с"   # сначала — что повтор обработан
eq "повтор той же карточки не зачисляется" 75 "$(bal)"
finish

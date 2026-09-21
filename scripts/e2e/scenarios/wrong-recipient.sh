#!/bin/bash
# Карточка платежа адресована конкретному получателю (он в подписи): чужую копию принять нельзя, деньги из воздуха не создаются.
source "$(dirname "$0")/../lib.sh"
echo "== wrong-recipient"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
bal() { q $B "select coalesce(sum(amount),0) from transactions"; }
dbg $B DEBUG_SET --es balance 50; sleep 2
eq "стартовый баланс B" 50 "$(bal)"

# Подложная карточка: подписана A, но адресована не B → B её не принимает
adb_ $A logcat -c
dbg $A DEBUG_SET --es forgecard "someone-else:500"; sleep 2
FORGED=$(adb_ $A logcat -d -s MB10DBG | grep -o 'card=.*' | tail -1 | cut -d= -f2- | tr -d '\r')
[ -n "$FORGED" ] || die "подложная карточка не создана"
adb_ $B logcat -c
dbg $B DEBUG_SET --es recv "$FORGED"; sleep 2
check "карточка не для B отклонена" bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep -q 'recv -> false'"
eq "баланс B не изменился" 50 "$(bal)"

# Карточка, адресованная именно B, принимается — и ровно один раз
dbg $A DEBUG_SET --es forgecard "$PKB:25"; sleep 2
OK=$(adb_ $A logcat -d -s MB10DBG | grep -o 'card=.*' | tail -1 | cut -d= -f2- | tr -d '\r')
adb_ $B logcat -c
dbg $B DEBUG_SET --es recv "$OK"; sleep 2
eq "адресованная B принята" 75 "$(bal)"
dbg $B DEBUG_SET --es recv "$OK"; sleep 2
eq "повтор той же карточки не зачисляется" 75 "$(bal)"
finish

#!/bin/bash
# Кошелёк: недоставленный перевод можно отменить (баланс возвращается, дашборд «отменён»), доставленный — нельзя.
source "$(dirname "$0")/../lib.sh"
echo "== transfer-cancel"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
dbg $A DEBUG_SET --es balance 100; sleep 2
bal() { q $A "select coalesce(sum(amount),0) from transactions"; }
eq "стартовый баланс" 100 "$(bal)"

# 1. получатель «не в сети» → карточка не уходит → PENDING
adb_ $A logcat -c
dbg $A DEBUG_SET --es pay "$PKB:10:offline"; sleep 3
TX=$(tx_of $A); [ -n "$TX" ] || die "перевод не создан"
eq "PENDING, баланс уменьшен" "PENDING|90" "$(q $A "select status from transactions where id='$TX'")|$(bal)"
dbg $A DEBUG_SET --es cancel "$TX"; sleep 3
eq "после отмены баланс вернулся" 100 "$(bal)"
check "дашборд: перевод отменён отправителем" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/transfers | jq_ 'any(t[\"txId\"]==\"$TX\" and t[\"cancelledAt\"] for t in d)' | grep -q True"

# 2. получатель в сети → карточка доставлена → отмена запрещена
adb_ $A logcat -c
dbg $A DEBUG_SET --es pay "$PKB:7:online"; sleep 5
TX2=$(tx_of $A); [ -n "$TX2" ] || die "второй перевод не создан"
eq "DELIVERED или CONFIRMED" 1 "$(q $A "select count(*) from transactions where id='$TX2' and status in ('DELIVERED','CONFIRMED')")"
dbg $A DEBUG_SET --es cancel "$TX2"; sleep 2
check "отмена доставленного отклонена" bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $A logcat -d -s MB10DBG | grep -q \"cancel $TX2 -> false\""
eq "баланс не вернулся" 93 "$(bal)"
finish

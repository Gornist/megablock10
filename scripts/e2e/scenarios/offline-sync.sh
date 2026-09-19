#!/bin/bash
# Офлайн-синк: коллектор недоступен → записи копятся в очереди на телефоне → сервер вернулся → очередь дошла и опустела.
source "$(dirname "$0")/../lib.sh"
echo "== offline-sync"
PKB=$(cat "$E2E_DIR/pk_$B.txt")
dbg $A DEBUG_SET --es balance 200; sleep 2
server_stop
adb_ $A logcat -c
dbg $A DEBUG_SET --es pay "$PKB:3:offline"; sleep 4
TX=$(tx_of $A); [ -n "$TX" ] || die "перевод не создан"
check "очередь на телефоне не пуста, пока сервера нет" bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from pending_change_records')\" -gt 0 ]"
server_start || die "сервер не поднялся"
check "запись дошла до дашборда" wait_until 120 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET /api/transfers | jq_ 'any(t[\"txId\"]==\"$TX\" for t in d)' | grep -q True"
check "очередь на телефоне опустела" wait_until 60 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from pending_change_records')\" -eq 0 ]"
finish

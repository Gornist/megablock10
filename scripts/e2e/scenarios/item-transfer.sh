#!/bin/bash
# Передача предметов тем же протоколом, что и деньги: демон Bob → Alice (принятие в чате), отмена недоставленного возвращает предмет,
# доставленную отменить нельзя, предмет никогда не бывает у двоих сразу.
source "$(dirname "$0")/../lib.sh"
echo "== item-transfer"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
has() { q "$1" "select count(*) from daemons where id='$2'"; }

dbg $B DEBUG_SET --es daemon "Тень Ghost:1C,7A:2:BLACKOUT"; sleep 2
ID="debug-Тень Ghost"
eq "у Bob есть демон" 1 "$(has $B "$ID")"

# 1. недоставленная передача (получатель «не в сети») — отмена возвращает демона
adb_ $B logcat -c
dbg $B DEBUG_SET --es give "daemon:$ID:$PKA:offline"; sleep 3
T1=$(item_of $B); [ -n "$T1" ] || die "передача не создана"
eq "PENDING: у Bob демона уже нет" 0 "$(has $B "$ID")"
dbg $B DEBUG_SET --es cancelitem "$T1"; sleep 3
eq "после отмены демон вернулся к Bob" 1 "$(has $B "$ID")"
eq "у Alice его нет" 0 "$(has $A "$ID")"

# 2. доставленная передача: Alice принимает в чате
adb_ $B logcat -c
dbg $B DEBUG_SET --es give "daemon:$ID:$PKA"; sleep 4
T2=$(item_of $B); [ -n "$T2" ] || die "вторая передача не создана"
eq "DELIVERED у отправителя" DELIVERED "$(q $B "select status from item_transfers where id='$T2'")"
eq "у Alice демона ещё нет, пока не приняла" 0 "$(has $A "$ID")"
dbg $B DEBUG_SET --es cancelitem "$T2"; sleep 2
check "отмена доставленного отклонена" bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep -q \"cancelitem $T2 -> false\""

open_chat $A Bob
tap_text $A "Принять" >/dev/null; sleep 3
eq "Alice приняла: демон у неё" 1 "$(has $A "$ID")"
eq "у Bob его больше нет" 0 "$(has $B "$ID")"
check "чек подтвердил передачу у Bob" wait_until 30 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $B \"select status from item_transfers where id='$T2'\")\" = CONFIRMED ]"
check "дашборд видит демона у Alice" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; api GET \"/api/players/\$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=\"\"))' '$PKA')\" | grep -q 'Тень Ghost'"

# 3. повторное «Принять» на старой карточке не размножает предмет
dbg $A DEBUG_SET --es give "daemon:$ID:$PKB"; sleep 4   # Alice передаёт демона обратно
open_chat $B Alice; tap_text $B "Принять" >/dev/null; sleep 3
eq "демон вернулся к Bob" 1 "$(has $B "$ID")"
open_chat $A Bob; tap_text $A "Принять" >/dev/null; sleep 3   # старая карточка Bob → Alice
eq "повторное «Принять» демона не размножило" 0 "$(has $A "$ID")"
finish

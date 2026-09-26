#!/bin/bash
# Отметки личных сообщений (docs/refactor-plan.md, D2–D4): «доставлено» — по ответу получателя (MB10ACK ok после сохранения),
# «прочитано» — по отчёту, когда получатель открыл тред; с выключенным переключателем «Отчёты о прочтении» отчёт не уходит.
source "$(dirname "$0")/../lib.sh"
echo "== message-status"
PKA=$(cat "$E2E_DIR/pk_$A.txt")
PKB=$(cat "$E2E_DIR/pk_$B.txt")
status_of() { q $A "select status from chat_messages where body = '$1'"; }
readthread() { adb_ $B logcat -c; dbg $B DEBUG_SET --es readthread "$PKA"; await 15 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $B logcat -d -s MB10DBG | grep 'readthread ->' | tail -1 | sed 's/.*-> //'"; }

T1="e2e-status-$RANDOM"
dbg $A DEBUG_SET --es say "$PKB|$T1"
eq_wait 30 "у отправителя «доставлено» — получатель подтвердил сохранение" 3 status_of "$T1"
eq_wait 15 "у получателя сообщение есть" 1 q $B "select count(*) from chat_messages where body = '$T1'"

dbg $B DEBUG_SET --es readreceipts on
eq "получатель открыл тред — отчёт ушёл" "SENT" "$(readthread)"
eq_wait 30 "у отправителя «прочитано»" 4 status_of "$T1"

# Выключенный переключатель: сначала свидетельство, что открытие треда отработало (строка MB10DBG), потом «статус не изменился».
T2="e2e-status-off-$RANDOM"
dbg $A DEBUG_SET --es say "$PKB|$T2"
eq_wait 30 "второе — «доставлено»" 3 status_of "$T2"
dbg $B DEBUG_SET --es readreceipts off
eq "с выключенными отчётами открытие треда ничего не шлёт" "OFF" "$(readthread)"
eq "у отправителя по-прежнему «доставлено»" 3 "$(status_of "$T2")"
dbg $B DEBUG_SET --es readreceipts on
finish

#!/bin/bash
# Обрыв Wi-Fi у получателя (как пауза при роуминге, docs/network-spec.md §7): сообщение уходит в очередь и доходит само, когда сеть вернулась;
# при этом ни одного дубля. Деньги в очередь не попадают — их карточку можно отменить, пока она не доставлена.
source "$(dirname "$0")/../lib.sh"
echo "== network-drop"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
TEXT="e2e-drop-$RANDOM"
# Обрыв: проброс порта Боба на хосте снимаем (отправитель получает «connection refused», как при недоступной точке), Wi-Fi гасим тоже —
# для проверки перерегистрации NSD/привязки; один только svc wifi disable проброс эмулятора не рвёт.
drop() { adb_ $B emu redir del tcp:24817 >/dev/null 2>&1; adb_ $B shell svc wifi disable; }
# Восстановление: Wi-Fi включаем и связываем эмуляторы заново тем же link.sh, что и при старте стенда — иначе следующие сценарии могут остаться
# без проброса порта Боба.
restore() { adb_ $B shell svc wifi enable; sleep 6; "$ROOT/scripts/e2e/link.sh" >/dev/null 2>&1; }
cnt() { q $B "select count(*) from chat_messages where body = '$TEXT'"; }

drop; sleep 4
dbg $A DEBUG_SET --es say "$PKB|$TEXT"; sleep 4
check "сообщение встало в очередь у отправителя" bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from outbox')\" -ge 1 ]"
eq "пока Wi-Fi у получателя выключен, сообщения у него нет" 0 "$(cnt)"

restore
check "после возврата сети сообщение дошло само" wait_until 120 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $B \"select count(*) from chat_messages where body = '$TEXT'\")\" -ge 1 ]"
check "очередь у отправителя опустела" wait_until 60 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select count(*) from outbox')\" -eq 0 ]"
sleep 3; eq "ровно одно сообщение, без дублей" 1 "$(cnt)"

# Деньги офлайн: карточка не уходит и в очередь не ставится — платёж остаётся PENDING и отменяем.
dbg $A DEBUG_SET --es balance 50; sleep 2
drop; sleep 4
dbg $A DEBUG_SET --es pay "$PKB:20:online"; sleep 4
eq "карточка платежа не попала в очередь (очередь пуста)" 0 "$(q $A 'select count(*) from outbox')"
restore; sleep 5
finish

#!/bin/bash
# Привязка трафика приложения к Wi-Fi (docs/network-spec.md §7): после запуска в logcat есть «привязано к Wi-Fi», обе стороны видят друг друга.
source "$(dirname "$0")/../lib.sh"
echo "== wifi-bind"
for s in $A $B; do adb_ $s shell svc wifi enable; done; sleep 5   # сценарий проверяет привязку к Wi-Fi: он должен быть включён (heal_host_reach мог его выключить)
for s in $A $B; do
  adb_ $s logcat -c; restart_app $s
done
sleep 6
for s in $A $B; do
  check "$s: приложение привязано к Wi-Fi" wait_until 30 bash -c "source '$ROOT/scripts/e2e/lib.sh'; adb_ $s logcat -d -s WifiBinder | grep -q 'привязано к Wi-Fi'"
done
"$ROOT/scripts/e2e/link.sh" >/dev/null 2>&1
PKB=$(cat "$E2E_DIR/pk_$B.txt"); TEXT="e2e-bind-$RANDOM"
dbg $A DEBUG_SET --es say "$PKB|$TEXT"
check "сообщение доходит при привязке к Wi-Fi" wait_until 30 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $B \"select count(*) from chat_messages where body = '$TEXT'\")\" -ge 1 ]"
heal_host_reach 2   # вернуть эмуляторам связь с сервером для следующих сценариев
finish

#!/bin/bash
# Связывает два эмулятора как пиров (mDNS между эмуляторами не ходит): redir портов + DEBUG_PEER.
# Порты приложения меняются при каждом запуске — скрипт можно (и нужно) запускать заново после перезапуска приложения.
source "$(dirname "$0")/lib.sh"
wait_until 60 bash -c "source '$(dirname "$0")/lib.sh'; [ -n \"\$(port_of $A)\" ] && [ -n \"\$(port_of $B)\" ]"
PA=$(port_of $A); PB=$(port_of $B)
[ -n "$PA" ] && [ -n "$PB" ] || die "не нашёл порты приложений (приложения запущены?)"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); PKB=$(cat "$E2E_DIR/pk_$B.txt")
adb_ $A emu redir del tcp:21277 >/dev/null 2>&1; adb_ $B emu redir del tcp:24817 >/dev/null 2>&1
adb_ $A emu redir add tcp:21277:$PA >/dev/null; adb_ $B emu redir add tcp:24817:$PB >/dev/null
dbg $B DEBUG_PEER --es pk "$PKA" --es cs Alice --es fac Neon --es host 10.0.2.2 --ei port 21277
dbg $A DEBUG_PEER --es pk "$PKB" --es cs Bob   --es fac Rats --es host 10.0.2.2 --ei port 24817
log "пиры связаны (A:$PA ↔ B:$PB)"

#!/bin/bash
# Останавливает сервер и (если не --keep-emulators) оба эмулятора.
source "$(dirname "$0")/lib.sh"
server_stop
if [ "$1" != "--keep-emulators" ]; then
  for s in $A $B; do "$ADB" -s $s emu kill >/dev/null 2>&1; done
fi
exit 0

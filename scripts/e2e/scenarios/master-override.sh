#!/bin/bash
# Правка мастера с дашборда: ёмкость буфера RAM и баланс доезжают до устройства.
source "$(dirname "$0")/../lib.sh"
echo "== master-override"
PKA=$(cat "$E2E_DIR/pk_$A.txt"); ENC=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$PKA")
api POST "/api/players/$ENC/override" '{"field":"ramCapacity","newValue":"9","reason":"e2e"}' >/dev/null || die "override ram"
check "RAM=9 применился на устройстве" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(ram_of $A)\" = 9 ]"
api POST "/api/players/$ENC/override" '{"field":"balance","newValue":"777","reason":"e2e"}' >/dev/null || die "override balance"
check "баланс 777 применился" wait_until 90 bash -c "source '$ROOT/scripts/e2e/lib.sh'; [ \"\$(q $A 'select coalesce(sum(amount),0) from transactions')\" = 777 ]"
finish

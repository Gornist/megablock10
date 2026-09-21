#!/bin/bash
# Всплеск отклонений: 15 записей с чужой подписью подряд → reject_spike, срочная, причина «подпись».
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-reject-spike"
anom_up
fake register Mallory --balance 100 >/dev/null
expect_no_kind reject_spike
fake send Mallory --field balance --delta 10 --reason BREACH_EDDIES --repeat 15 --bad-signature >/dev/null
expect_kind reject_spike 15
eq "тревога срочная (подпись)" crit "$(item_field reject_spike severity)"
check "в описании причина «подпись»" bash -c "source '$ROOT/scripts/e2e/anom-lib.sh'; item_field reject_spike detail | grep -q 'подпись'"
anom_finish

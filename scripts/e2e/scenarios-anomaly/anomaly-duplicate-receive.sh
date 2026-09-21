#!/bin/bash
# Один перевод получили двое: TRANSFER_IN с одним sourceRef у двух игроков → duplicate_receive (срочная). Честная пара тревоги не даёт.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-duplicate-receive"
anom_up
for n in DA DB DC; do fake register $n --balance 100 >/dev/null; done
fake send DA --field balance --new 0 --reason TRANSFER_OUT --ref tx-dup-1 >/dev/null
fake send DB --field balance --delta 100 --reason TRANSFER_IN --ref tx-dup-1 --actor DA >/dev/null
expect_no_kind duplicate_receive "честная пара (отправил и получил один) — дубля нет"
fake send DC --field balance --delta 100 --reason TRANSFER_IN --ref tx-dup-1 --actor DA >/dev/null
expect_kind duplicate_receive 10
eq "тревога срочная" crit "$(item_field duplicate_receive severity)"
anom_finish

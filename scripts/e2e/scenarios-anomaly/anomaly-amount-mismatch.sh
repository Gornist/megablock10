#!/bin/bash
# Сумма перевода не сходится: списано 100, получено 300 с одним sourceRef → transfer_amount_mismatch (срочная). Честная пара 50/50 тревоги не даёт.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-amount-mismatch"
anom_up
fake register MA --balance 500 >/dev/null; fake register MB --balance 0 >/dev/null
fake send MA --field balance --new 450 --reason TRANSFER_OUT --ref tx-ok-1 >/dev/null
fake send MB --field balance --delta 50 --reason TRANSFER_IN --ref tx-ok-1 --actor MA >/dev/null
expect_no_kind transfer_amount_mismatch "честный перевод 50/50 — расхождения нет"
fake send MA --field balance --new 350 --reason TRANSFER_OUT --ref tx-mm-1 >/dev/null
fake send MB --field balance --delta 300 --reason TRANSFER_IN --ref tx-mm-1 --actor MA >/dev/null
expect_kind transfer_amount_mismatch 10
eq "ровно одна тревога (только у нечестной пары)" 1 "$(item_count transfer_amount_mismatch)"
eq "тревога срочная" crit "$(item_field transfer_amount_mismatch severity)"
anom_finish

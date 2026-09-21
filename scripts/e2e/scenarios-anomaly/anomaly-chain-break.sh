#!/bin/bash
# Разрыв цепочки баланса: oldValue не равен предыдущему newValue → balance_chain_break. Честная цепочка тревоги не даёт.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-chain-break"
anom_up
fake register CB --balance 100 >/dev/null
fake send CB --field balance --delta 50 --reason BREACH_EDDIES >/dev/null
expect_no_kind balance_chain_break "честная цепочка 100 → 150 — разрыва нет"
fake send CB --field balance --old 999 --new 1049 --reason BREACH_EDDIES >/dev/null
expect_kind balance_chain_break 10
anom_finish

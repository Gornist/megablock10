#!/bin/bash
# Зависший перевод: TRANSFER_OUT без пары и без отмены → transfer_stuck (порог на стенде 6 с). Перевод с отменой тревоги не даёт.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-stuck-transfer"
anom_up
fake register TA --balance 500 >/dev/null; fake register TB --balance 0 >/dev/null
fake send TA --field balance --new 400 --reason TRANSFER_OUT --ref tx-stuck-1 >/dev/null
fake send TA --field balance --new 300 --reason TRANSFER_OUT --ref tx-cancel-1 >/dev/null
fake send TA --field balance --new 400 --reason TRANSFER_CANCELLED --ref tx-cancel-1 >/dev/null
expect_no_kind transfer_stuck "порог 6 с ещё не прошёл — тревоги нет"
expect_kind transfer_stuck 20
eq "ровно один зависший (отменённый не считается)" 1 "$(item_count transfer_stuck)"
check "в описании сумма 100 €$" bash -c "source '$ROOT/scripts/e2e/anom-lib.sh'; item_field transfer_stuck detail | grep -q '100'"
anom_finish

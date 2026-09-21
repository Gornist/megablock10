#!/bin/bash
# Часы устройства спешат: запись, датированная на 30 минут вперёд → clock_skew. Запись «сейчас» тревоги не даёт.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-clock"
anom_up
fake register CK --balance 100 >/dev/null
fake send CK --field balance --delta 1 --reason BREACH_EDDIES >/dev/null
expect_no_kind clock_skew "запись с честным временем"
fake send CK --field balance --delta 1 --reason BREACH_EDDIES --happened-at +1800000 >/dev/null
expect_kind clock_skew 10
anom_finish

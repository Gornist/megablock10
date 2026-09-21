#!/bin/bash
# Баланс вырос без причины: +5000 по RAM_UPGRADE → balance_unexplained (срочная). Тот же рост по BREACH_EDDIES этой тревоги не даёт (только «крупное поступление»).
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-unexplained-jump"
anom_up
fake register UJ --balance 100 >/dev/null
fake send UJ --field balance --delta 5000 --reason BREACH_EDDIES >/dev/null
expect_no_kind balance_unexplained "рост за взлом — причина законная"
fake send UJ --field balance --delta 5000 --reason RAM_UPGRADE >/dev/null
expect_kind balance_unexplained 10
eq "тревога срочная" crit "$(item_field balance_unexplained severity)"
anom_finish

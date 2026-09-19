#!/bin/bash
# Гоняет все сценарии по очереди на уже поднятом стенде (./up.sh). Код возврата 1, если хоть один красный.
cd "$(dirname "$0")"
RC=0
for f in scenarios/*.sh; do "./$f" || RC=1; done
[ $RC -eq 0 ] && echo "ВСЕ ЗЕЛЁНЫЕ" || echo "ЕСТЬ КРАСНЫЕ"
exit $RC

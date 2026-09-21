#!/bin/bash
# Лимит запросов: 100 heartbeat с одного адреса при лимите 60/мин → часть получает 429, тревога rate_limited.
source "$(dirname "$0")/../anom-lib.sh"
echo "== anomaly-rate-limit"
anom_up
fake register Loop --balance 100 >/dev/null
expect_no_kind rate_limited
OUT=$(fake beat Loop --repeat 100)
check "часть запросов получила 429" bash -c "echo '$OUT' | grep -q '\"429\"'"
expect_kind rate_limited 15
anom_finish

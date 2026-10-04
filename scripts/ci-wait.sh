#!/bin/bash
# Ждёт GitHub Actions и печатает ОДИН итог (ход оркестратора тратит токены на каждое событие — не опрашивать по кругу).
#   scripts/ci-wait.sh pr <номер>      — все проверки PR
#   scripts/ci-wait.sh sha <sha>       — все прогоны на коммите (после пуша в ветку/main)
# Запускать в фоне: Bash с run_in_background — придёт одно уведомление. Ошибки API (504) переживает; ≈2 ч максимум. Код 0 — всё зелёное, 1 — красное, 2 — API недоступен.
set -u
KIND=${1:-}; ARG=${2:-}; ERR=0
[ -n "$KIND" ] && [ -n "$ARG" ] || { sed -n 2,5p "$0"; exit 2; }
for i in $(seq 1 240); do
  if [ "$KIND" = pr ]; then OUT=$(gh pr checks "$ARG" 2>&1); RC=$?
  else OUT=$(gh run list --commit "$ARG" --json workflowName,status,conclusion --jq '.[] | "\(.workflowName)\t\(if .status=="completed" then .conclusion else "pending" end)"' 2>&1); RC=$?; fi
  if [ $RC -ne 0 ] && ! echo "$OUT" | grep -qE 'pending|pass|fail'; then ERR=$((ERR+1)); [ $ERR -ge 8 ] && { echo "CI: API недоступен ($OUT)"; exit 2; }; sleep 30; continue; fi
  ERR=0
  if [ -n "$OUT" ] && ! echo "$OUT" | grep -qiE 'pending|queued|in_progress'; then
    echo "CI: $(echo "$OUT" | awk -F'\t' '{printf "%s %s; ", $1, $2}')"
    echo "$OUT" | grep -qiE 'fail|cancel|error|timed_out|startup_failure' && exit 1 || exit 0
  fi
  sleep 30
done
echo "CI: не дождался за 2 ч"; exit 2

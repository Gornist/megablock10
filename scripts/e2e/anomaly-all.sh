#!/bin/bash
# Гоняет сценарии-провокаторы (scenarios-anomaly/) на отдельном сервере (порт 2518, свои БД и ускоренные окна) — основной стенд и эмуляторы не нужны.
# anomaly-silent-phone.sh нужен основной стенд с эмуляторами и берётся только с --phones. Артефакты (вывод /api/anomalies/replay каждого
# прогона, для подбора порогов ANOM_*) — в $ANOM_ARTIFACTS (по умолчанию /tmp/mb10-e2e-anom-artifacts). Код возврата 1, если что-то красное.
#   ./anomaly-all.sh [--phones] [имя-сценария ...]
cd "$(dirname "$0")" || exit 1
PHONES=0; ONLY=()
for a in "$@"; do case $a in --phones) PHONES=1;; *) ONLY+=("$a");; esac; done
rm -rf "${ANOM_ARTIFACTS:-/tmp/mb10-e2e-anom-artifacts}"
RC=0; declare -a TIMES
for f in scenarios-anomaly/*.sh; do
  n=$(basename "$f" .sh)
  [ ${#ONLY[@]} -gt 0 ] && [[ ! " ${ONLY[*]} " =~ " $n " ]] && continue
  [ $PHONES -eq 0 ] && [ "$n" = anomaly-silent-phone ] && [ ${#ONLY[@]} -eq 0 ] && continue
  t0=$(date +%s); "./$f" < /dev/null || RC=1; TIMES+=("$n: $(( $(date +%s) - t0 )) с")
done
echo "── время сценариев:"; printf '  %s\n' "${TIMES[@]}"
echo "── артефакты replay: ${ANOM_ARTIFACTS:-/tmp/mb10-e2e-anom-artifacts}"
[ $RC -eq 0 ] && echo "ВСЕ ЗЕЛЁНЫЕ" || echo "ЕСТЬ КРАСНЫЕ"
exit $RC

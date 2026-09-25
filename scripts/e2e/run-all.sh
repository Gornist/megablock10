#!/bin/bash
# Гоняет все сценарии по очереди на уже поднятом стенде (./up.sh). Код возврата 1, если хоть один красный.
cd "$(dirname "$0")"
RC=0
# После zz-provisioning (стирает Alice: новый ключ, порт, пиры) стенд одноразовый — второй прогон на нём краснеет «сам»: карточки
# не доходят (NOT_REACHED), на дашборде лишние игроки. Два прогона подряд — только с ./down.sh && ./up.sh между ними.
[ -e "${E2E_DIR:-/tmp/mb10-e2e}/stand_used" ] && { echo "Стенд уже прогнан (zz-provisioning стёр Alice). Сначала: ./down.sh && ./up.sh"; exit 2; }
# Время каждого сценария печатается в конце — так видно, на что уходят минуты прогона.
declare -a TIMES
for f in scenarios/*.sh; do
  ( source ./lib.sh; reset_ui; heal_host_reach 2 >/dev/null || true )   # чистый экран и связь с сервером перед сценарием
  t0=$(date +%s); "./$f" || RC=1; TIMES+=("$(basename "$f" .sh): $(( $(date +%s) - t0 )) с")
done
echo "── время сценариев:"; printf '  %s\n' "${TIMES[@]}"
[ $RC -eq 0 ] && echo "ВСЕ ЗЕЛЁНЫЕ" || echo "ЕСТЬ КРАСНЫЕ"
exit $RC

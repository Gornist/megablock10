# Общая обвязка ssh к devbox. Подключается через `. "$ROOT/scripts/lib/devbox.sh"` (сама ничего не запускает).
#   dssh <команда…>   — выполнить на devbox; stdin сохраняется. На самом devbox (из клона ~/box/repo, из ssh-сеанса сессии) идёт
#                       локально: ssh к себе там не выходит («Host key verification failed», 13.10).
#   unreachable       — ssh не прошёл (код 255): отличить «Tailscale лежит» от «машина выключена»; печатает вердикт и подсказку.
#   onbox             — то же, что dssh на самом devbox (bash -c "$*").
# Настройка до вызова: DEVBOX_TMO — ConnectTimeout, с (по умолчанию 10; dbx.sh берёт 15, box.sh 8), DEVBOX_HOST (devbox).
DEVBOX_HOST=${DEVBOX_HOST:-devbox}
DEVBOX_TS_IP=${DEVBOX_TS_IP:-100.80.115.46}
DEVBOX_LAN_IP=${DEVBOX_LAN_IP:-192.168.1.141}

onbox() { bash -c "$*"; }

dssh() {
  if [ "$(hostname -s 2>/dev/null)" = "$DEVBOX_HOST" ]; then
    onbox "$@"
  else
    ssh -o ConnectTimeout="${DEVBOX_TMO:-10}" -o BatchMode=yes "$DEVBOX_HOST" "$@"
  fi
}

unreachable() {
  local ts=нет lan=нет
  ping -c1 -t2 "$DEVBOX_TS_IP" >/dev/null 2>&1 && ts=есть
  ping -c1 -t2 "$DEVBOX_LAN_IP" >/dev/null 2>&1 && lan=есть
  echo "devbox: НЕДОСТУПЕН — ssh не отвечает (ping Tailscale $DEVBOX_TS_IP: $ts, LAN $DEVBOX_LAN_IP: $lan)"
  if [ "$lan" = есть ] && [ "$ts" = нет ]; then
    echo "  ! машина включена, Tailscale лежит: владельцу на devbox — sudo systemctl restart tailscaled; если не Running — sudo tailscale up"
  elif [ "$lan" = нет ] && [ "$ts" = нет ]; then
    echo "  ! машина выключена или не в сети (LAN и Tailscale молчат) — владельцу"
  fi
}

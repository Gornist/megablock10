# Общая обвязка ssh к devbox. Подключается через `. "$ROOT/scripts/lib/devbox.sh"` (сама ничего не запускает).
#   dssh <команда…>   — выполнить на devbox; stdin сохраняется. На самом devbox (из клона ~/box/repo, из ssh-сеанса сессии) идёт
#                       локально: ssh к себе там не выходит («Host key verification failed», 13.10).
#   unreachable       — ssh не прошёл (код 255): печатает вердикт «машина выключена или не в сети»; devbox ходит только по LAN.
#   onbox             — то же, что dssh на самом devbox (bash -c "$*").
# Настройка до вызова: DEVBOX_TMO — ConnectTimeout, с (по умолчанию 10; dbx.sh берёт 15, box.sh 8), DEVBOX_HOST (devbox),
# DEVBOX_LAN_IP (192.168.1.141; Tailscale и VPN на devbox убраны 25.10.2026, 100.80.115.46 больше не существует).
DEVBOX_HOST=${DEVBOX_HOST:-devbox}
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
  local lan=нет
  ping -c1 -t2 "$DEVBOX_LAN_IP" >/dev/null 2>&1 && lan=есть
  echo "devbox: НЕДОСТУПЕН — ssh не отвечает (ping LAN $DEVBOX_LAN_IP: $lan)"
  if [ "$lan" = есть ]; then
    echo "  ! машина отвечает на ping, но ssh нет: служба ssh или ключ (ssh -v $DEVBOX_HOST); после переустановки — ssh-keygen -R $DEVBOX_LAN_IP"
  else
    echo "  ! машина выключена или не в сети (кабель, питание, роутер) — владельцу"
  fi
}

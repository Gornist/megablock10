#!/usr/bin/env bash
# Старт сеанса devbox: incy (VPN) → Tailscale → Blender (blender-mcp на 9876).
# Запускается автозапуском GNOME после входа nick (~/.config/autostart/devbox-session.desktop), нужен графический сеанс:
# incy — GUI, Blender открывается окном на Wayland.
# Требует (один раз, руками владельца):
#   1) incy: Настройки → «Автоподключение» (autoConnect) — иначе VPN сам не поднимется;
#   2) sudo-правило без пароля на запуск tailscaled (/etc/sudoers.d/devbox-tailscale, см. docs/netrun-devbox.md).
# Журнал: ~/.local/state/devbox-session.log. Каждый этап ждёт предыдущий, но по таймауту идёт дальше — чтобы
# Blender поднимался даже без VPN, а сбой этапа был виден в журнале, а не молчал.
set -u

LOG="$HOME/.local/state/devbox-session.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1

VPN_TIMEOUT=${VPN_TIMEOUT:-180}
TS_TIMEOUT=${TS_TIMEOUT:-90}
BLENDER_TIMEOUT=${BLENDER_TIMEOUT:-60}
INCY=/opt/incy/bin/incy
BLENDER="$HOME/.local/bin/blender"

log() { echo "[$(date '+%F %T')] $*"; }
wait_for() {  # wait_for <что> <секунд> <команда…>
  local what=$1 t=$2 i; shift 2
  for ((i = 0; i < t; i++)); do
    if "$@" >/dev/null 2>&1; then log "ok: $what (${i} с)"; return 0; fi
    sleep 1
  done
  log "ТАЙМАУТ: $what (${t} с)"; return 1
}

vpn_up() { ip -4 -br addr show tun_incy 2>/dev/null | grep -q '198\.18\.' && pgrep -x xray >/dev/null; }
ts_running() { tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; }
mcp_up() { ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:9876'; }

log "=== старт сеанса ==="

# 1. incy → VPN
if ! pgrep -f "$INCY" >/dev/null; then
  log "запускаю incy"
  setsid nohup "$INCY" >/dev/null 2>&1 &
else
  log "incy уже запущен"
fi
wait_for "VPN (tun_incy + xray)" "$VPN_TIMEOUT" vpn_up \
  || log "VPN не поднялся: включён ли autoConnect в incy? Иду дальше без него"

# 2. Tailscale — после VPN (restart запустит и остановленный сервис, и перезапустит работающий уже через VPN)
if sudo -n /usr/bin/systemctl restart tailscaled; then
  wait_for "Tailscale (BackendState=Running)" "$TS_TIMEOUT" ts_running \
    || log "Tailscale не в Running: tailscale status (возможно, нужен tailscale up)"
else
  log "ОШИБКА: sudo без пароля на tailscaled не настроен — Tailscale не перезапущен"
fi

# 3. Blender
if pgrep -x blender >/dev/null; then
  log "Blender уже запущен"
else
  log "запускаю Blender"
  setsid nohup "$BLENDER" >/dev/null 2>&1 &
fi
wait_for "blender-mcp на 127.0.0.1:9876" "$BLENDER_TIMEOUT" mcp_up \
  || log "порт 9876 не слушает: включён ли аддон blender-mcp?"

log "=== готово ==="

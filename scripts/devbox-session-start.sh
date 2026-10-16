#!/usr/bin/env bash
# Старт сеанса devbox: incy (VPN) → Tailscale → adb → Blender (blender-mcp на 9876) → редактор Godot → самопроверка.
# Запускается автозапуском GNOME после входа nick (~/.config/autostart/devbox-session.desktop), нужен графический сеанс.
# Автозапуск указывает на клон репозитория ~/box/repo (scripts/box.sh sync) — не на ручную копию: правка здесь доезжает до
# devbox одной командой, а расхождение видно в `scripts/box.sh status`. Запустить вручную (идемпотентно, ничего не убивает):
#   scripts/box.sh boot-check
# Требует (один раз, руками владельца):
#   1) incy: Настройки → «Автоподключение» (autoConnect) — иначе VPN сам не поднимется;
#   2) sudo-правило без пароля на перезапуск tailscaled (/etc/sudoers.d/devbox-tailscale, см. docs/netrun-devbox.md).
# Итог: журнал ~/.local/state/devbox-session.log (подробно), ~/box/boot.report (вердикт — его читает `box.sh status`),
# ~/box/journal.jsonl (строка на запуск). Каждый этап ждёт предыдущий, но по таймауту идёт дальше — чтобы сбой этапа был виден,
# а не молчал и не тянул за собой остальное. Чужое не убиваем: Blender без 9876 не перезапускаем (там может быть работа).
set -u

BOX=${BOX:-$HOME/box}
LOG=${LOG:-$HOME/.local/state/devbox-session.log}
mkdir -p "$BOX" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
exec 9>"$BOX/boot.lock"
flock -n 9 || { echo "[$(date '+%F %T')] проверка уже идёт — выхожу"; exit 0; }

HERE=$(cd "$(dirname "$0")" && pwd)
VPN_TIMEOUT=${VPN_TIMEOUT:-180}
TS_TIMEOUT=${TS_TIMEOUT:-90}
GFX_TIMEOUT=${GFX_TIMEOUT:-120}
BLENDER_TIMEOUT=${BLENDER_TIMEOUT:-60}
BLENDER_TRIES=${BLENDER_TRIES:-3}
GODOT_TIMEOUT=${GODOT_TIMEOUT:-90}
INCY=/opt/incy/bin/incy
BLENDER=${BLENDER:-$HOME/.local/bin/blender}
BLENDER_COMM=${BLENDER_COMM:-blender}
MCP_PORT=${MCP_PORT:-9876}
ADB="$HOME/android-sdk/platform-tools/adb"

# Окружение графического сеанса: из автозапуска оно есть, из ssh (ручной прогон) — нет.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
export DISPLAY=${DISPLAY:-:0}

PROBLEMS=()
log() { echo "[$(date '+%F %T')] $*"; }
bad() { PROBLEMS+=("$*"); log "ПРОБЛЕМА: $*"; }
wait_for() {  # wait_for <что> <секунд> <команда…>
  local what=$1 t=$2 i; shift 2
  for ((i = 0; i < t; i++)); do
    if "$@" >/dev/null 2>&1; then log "ok: $what (${i} с)"; return 0; fi
    sleep 1
  done
  log "ТАЙМАУТ: $what (${t} с)"; return 1
}

vpn_up() { ip -4 -br addr show tun_incy 2>/dev/null | grep -q '198\.18\.' && pgrep -x xray >/dev/null; }
ts_state() { tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState","?"))' 2>/dev/null; }
ts_running() { [ "$(ts_state)" = "Running" ]; }
gfx_up() { [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && pgrep -x gnome-shell >/dev/null && timeout 8 nvidia-smi -L >/dev/null 2>&1; }
mcp_up() { ss -H -ltn "sport = :$MCP_PORT" 2>/dev/null | grep -q .; }
godot_up() { ss -H -ltn 'sport = :8000' 2>/dev/null | grep -q .; }
adb_up() { ss -H -ltn 'sport = :5037' 2>/dev/null | grep -q .; }
# GUI-Blender: процессы `blender -b` (сборка ассетов, кадры) — не он, их сервер blender-mcp не нужен
blender_gui() { pgrep -a -x "$BLENDER_COMM" 2>/dev/null | grep -v -E ' (-b|--background)( |$)' | grep -q .; }

log "=== старт сеанса (скрипты: $(git -C "$HERE/.." rev-parse --short HEAD 2>/dev/null || echo 'не из git')) ==="

# 1. incy → VPN
if ! pgrep -f "$INCY" >/dev/null; then
  log "запускаю incy"
  setsid nohup "$INCY" >/dev/null 2>&1 9>&- &
else
  log "incy уже запущен"
fi
wait_for "VPN (tun_incy + xray)" "$VPN_TIMEOUT" vpn_up \
  || bad "VPN не поднялся (autoConnect в incy включён? Иду дальше без него)"

# 2. Tailscale. Демон стартует при загрузке раньше VPN и ходит к control plane через прокси xray — пока прокси нет, не Running.
#    Уже Running — не трогаем (раньше перезапускали всегда и на секунды роняли ssh). Иначе (14.10: при старте раньше прокси демон
#    остаётся «logged out» — fetch control key: connection refused на 127.0.0.1:10809) — то, что владелец делал руками:
#    `tailscale up` БЕЗ sudo (оператор демона — nick), потом перезапуск tailscaled, потом ещё раз `tailscale up`.
#    Флаги — те же, что в настройках узла (--ssh, --operator=nick): `tailscale up` без них отказывается менять настройки.
ts_up() { timeout 40 tailscale up --ssh --operator=nick --accept-risk=lose-ssh >/dev/null 2>&1; }
if wait_for "Tailscale (BackendState=Running)" 15 ts_running; then
  :
else
  log "Tailscale: $(ts_state) при поднятом VPN — tailscale up"
  ts_up
  if wait_for "Tailscale после tailscale up" 30 ts_running; then
    :
  elif sudo -n /usr/bin/systemctl restart tailscaled; then
    ts_up
    wait_for "Tailscale после перезапуска tailscaled" "$TS_TIMEOUT" ts_running \
      || bad "Tailscale: $(ts_state) после tailscale up и перезапуска — владельцу: вход, если NeedsLogin (tailscale up, откроет ссылку)"
  else
    bad "Tailscale: $(ts_state), tailscale up не помог, а sudo без пароля на tailscaled не настроен (/etc/sudoers.d/devbox-tailscale)"
  fi
fi

# 3. adb. Сервер — user-служба box-adb (поднимается сама при входе); здесь только проверка. Чужой сервер не убиваем.
if adb_up; then
  if systemctl --user is-active --quiet box-adb 2>/dev/null; then
    log "ok: adb — служба box-adb"
  else
    log "adb-сервер есть, но не под службой box-adb — перевести: scripts/box.sh adb adopt (сам не трогаю: рвёт reverse/forward)"
  fi
elif systemctl --user cat box-adb >/dev/null 2>&1; then
  systemctl --user start box-adb 2>/dev/null
  wait_for "adb-сервер (служба box-adb)" 15 adb_up || bad "adb-сервер не поднялся (systemctl --user status box-adb)"
else
  bad "служба box-adb не установлена (scripts/box.sh sync)"
fi
DEVICES=$(timeout 10 "$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}' | paste -sd, -)
log "adb: устройства: ${DEVICES:-нет}"

# 4. Blender. Сервер blender-mcp аддон сам не поднимает (автостарт — свойство сцены), поэтому включаем его таймером после
#    загрузки интерфейса. 13.10 Blender падал в libdecor-gtk (Wayland, создание окна) — гонка с графическим сеансом: ждём
#    графику и повторяем, последняя попытка без плагина рамок (LIBDECOR_PLUGIN_DIR). Крэш-отчёт сохраняем в ~/box.
START_MCP='import bpy
def _start_mcp():
    try:
        bpy.ops.blendermcp.start_server()
    except Exception as e:
        print("blender-mcp: сервер не запущен:", e)
    return None
bpy.app.timers.register(_start_mcp, first_interval=3.0)'
if mcp_up; then
  log "ok: blender-mcp уже на 9876"
elif blender_gui; then
  bad "Blender запущен без blender-mcp (9876): сервер снаружи не включить — перезапуск Blender за его сессией; не убиваю"
else
  wait_for "графический сеанс (wayland + gnome-shell + GPU)" "$GFX_TIMEOUT" gfx_up || log "графика не подтвердилась — пробую Blender всё равно"
  sleep 5
  for ((try = 1; try <= BLENDER_TRIES; try++)); do
    rm -f /tmp/blender.crash.txt
    env_extra=()
    [ "$try" -eq "$BLENDER_TRIES" ] && [ "$try" -gt 1 ] && env_extra=(LIBDECOR_PLUGIN_DIR=/nonexistent)
    log "запускаю Blender (попытка $try из $BLENDER_TRIES${env_extra[*]:+, ${env_extra[*]}})"
    env "${env_extra[@]}" setsid nohup "$BLENDER" --python-expr "$START_MCP" >>"$BOX/blender-boot.log" 2>&1 9>&- &
    sleep 3  # цепочка env → setsid → nohup → blender ещё не стала процессом `blender`: без паузы цикл принял бы её за падение
    for ((i = 0; i < BLENDER_TIMEOUT; i++)); do
      mcp_up && break
      blender_gui || break
      sleep 1
    done
    if mcp_up; then log "ok: blender-mcp на $MCP_PORT (попытка $try)"; break; fi
    if blender_gui; then
      bad "Blender жив, но 9876 не слушает за ${BLENDER_TIMEOUT} с (аддон blender-mcp включён?)"; break
    fi
    crash="$BOX/blender-crash-$(date +%m%d-%H%M%S).txt"
    [ -f /tmp/blender.crash.txt ] && cp /tmp/blender.crash.txt "$crash"
    log "Blender упал на попытке $try (крэш-отчёт: $([ -f "$crash" ] && echo "$crash" || echo нет)): $(grep -m1 -E 'lib[a-z]+.*\.so' "$crash" 2>/dev/null | cut -c1-120)"
    [ "$try" -eq "$BLENDER_TRIES" ] && bad "Blender падает при старте $BLENDER_TRIES раза подряд (крэш-отчёты ~/box/blender-crash-*.txt)"
    sleep 10
  done
fi

# 5. Редактор Godot AI поднимает отдельный godot-ai.desktop (через 20 с после входа) — только ждём и сообщаем.
wait_for "редактор Godot AI на 8000" "$GODOT_TIMEOUT" godot_up \
  || bad "редактор Godot не слушает 8000 (godot-ai.desktop: scripts/devbox-godot-ai.sh start в ~/wt-godot)"

# 6. Самопроверка тем же скриптом, что и `box.sh status`, и отчёт: вердикт читает status, строка — в журнал действий.
#    Сначала отчёт по этапам (проба читает его же), потом проба: то, что она видит сверх этапов (adb не под службой, пропавший
#    порт), тоже делает вердикт «problems» — этапы могли отработать «ок» там, где итоговое состояние плохое.
write_report() { # write_report <verdict> <проблемы через «;»>
  {
    echo "time=$(date +%s)"
    echo "boot=$(awk '/^btime/{print $2}' /proc/stat)"
    echo "verdict=$1"
    echo "problems=$2"
    echo "devices=${DEVICES:-}"
  } >"$BOX/boot.report.tmp" && mv "$BOX/boot.report.tmp" "$BOX/boot.report"
}
VERDICT=ok; [ "${#PROBLEMS[@]}" -gt 0 ] && VERDICT=problems
PROB_TXT=$(IFS=';'; echo "${PROBLEMS[*]:-}")
write_report "$VERDICT" "$PROB_TXT"
PROBE="$HERE/box/probe.sh"
if [ -f "$PROBE" ]; then
  PROBE_OUT=$(bash "$PROBE" --brief 2>&1)
  while IFS= read -r l; do log "probe: $l"; done <<<"$PROBE_OUT"
  PROBE_BAD=$(grep '^  ! ' <<<"$PROBE_OUT" | sed 's/^  ! //' | grep -v '^нет ~/box/boot.report' | paste -sd';' -)
  if [ -n "$PROBE_BAD" ] && [ "$VERDICT" = ok ]; then
    VERDICT=problems; PROB_TXT=$PROBE_BAD
  fi
fi
write_report "$VERDICT" "${PROB_TXT:-}"
j=${PROB_TXT//\\/\/}; j=${j//\"/\'}
printf '{"t":"%s","event":"boot-check","verdict":"%s","problems":"%s","devices":"%s"}\n' \
  "$(date -Is)" "$VERDICT" "$j" "${DEVICES:-}" >>"$BOX/journal.jsonl"
log "=== готово: $VERDICT${PROB_TXT:+ — $PROB_TXT} ==="
[ "$VERDICT" = ok ]

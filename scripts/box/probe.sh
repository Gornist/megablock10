#!/usr/bin/env bash
# Проба состояния devbox — выполняется НА devbox. С Mac её запускает `scripts/box.sh status`
# (`ssh devbox bash -s < probe.sh`: копии на машине нет, устаревать нечему); автозапуск после загрузки зовёт её из клона ~/box/repo.
#   probe.sh            — вердикт, замечания, сводка (машина, сеть, adb, устройства, порты, занято)
#   probe.sh --brief    — только вердикт и замечания
# Только чтение: ничего не запускает, не перезапускает и не нажимает на устройствах. Код выхода: 0 — замечаний нет, 1 — есть.
# Что считается замечанием (!): Tailscale не Running, нет adb-сервера на 5037, GPU/диск, устройство offline/unauthorized,
# нет blender-mcp (9876) или редактора Godot (8000/9500), автозапуск не отчитался после загрузки. Остальное — справка.
set -u
ADB=${ADB:-$HOME/android-sdk/platform-tools/adb}
BOX=$HOME/box
BRIEF=0; [ "${1:-}" = "--brief" ] && BRIEF=1
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}

PROBLEMS=()
INFO=()
problem() { PROBLEMS+=("$*"); }
info() { INFO+=("$*"); }
listen_tcp() { ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .; }
listen_udp() { ss -H -lun "sport = :$1" 2>/dev/null | grep -q .; }
dur() { # секунды → «3 д 4 ч» / «5 ч 12 мин» / «23 мин»
  local s=$1
  if [ "$s" -ge 86400 ]; then echo "$((s / 86400)) д $((s % 86400 / 3600)) ч"
  elif [ "$s" -ge 3600 ]; then echo "$((s / 3600)) ч $((s % 3600 / 60)) мин"
  else echo "$((s / 60)) мин"; fi
}
NOW=$(date +%s)

# --- машина -----------------------------------------------------------------------------------------------------------
UP=$(awk '{print int($1)}' /proc/uptime)
read -r L1 L5 _ </proc/loadavg
CORES=$(nproc)
GPU=""
if gpu_raw=$(timeout 6 nvidia-smi --query-gpu=driver_version,memory.used,memory.total,utilization.gpu,temperature.gpu \
    --format=csv,noheader,nounits 2>/dev/null) && [ -n "$gpu_raw" ]; then
  IFS=',' read -r gdrv gused gtot gutil gtemp <<<"$gpu_raw"
  gdrv=${gdrv// /}; gused=${gused// /}; gtot=${gtot// /}; gutil=${gutil// /}; gtemp=${gtemp// /}
  GPU="GPU $gdrv ${gused}/${gtot} МБ ${gutil}% ${gtemp}°"
  [ "$gtemp" -ge 85 ] 2>/dev/null && problem "GPU ${gtemp}° — перегрев"
else
  GPU="GPU: nvidia-smi не отвечает"
  problem "GPU: nvidia-smi не отвечает (драйвер?)"
fi
read -r DFSIZE DFPCT <<<"$(df -P / | awk 'NR==2{gsub("%","",$5); printf "%d %d", $4/1048576, $5}')"
[ "$DFPCT" -ge 92 ] && problem "диск / заполнен на ${DFPCT}% (свободно ${DFSIZE} ГБ)"
info "машина: up $(dur "$UP") · load $L1/$L5 из $CORES · $GPU · диск свободно ${DFSIZE} ГБ (${DFPCT}%)"

# --- сеть -------------------------------------------------------------------------------------------------------------
TS_STATE="нет tailscale"; TS_IP=""; TS_HEALTH=""
if command -v tailscale >/dev/null; then
  ts_json=$(timeout 6 tailscale status --json 2>/dev/null)
  if [ -n "$ts_json" ]; then
    # shellcheck disable=SC2016  # программа python — не для оболочки
    read -r TS_STATE TS_IP _ <<<"$(python3 -c '
import json, sys
d = json.load(sys.stdin)
s = d.get("Self") or {}
print(d.get("BackendState", "?"), (s.get("TailscaleIPs") or ["-"])[0], s.get("Online"))' <<<"$ts_json" 2>/dev/null)"
    TS_HEALTH=$(python3 -c '
import json, sys
print("; ".join((json.load(sys.stdin).get("Health") or [])[:2]))' <<<"$ts_json" 2>/dev/null)
  else
    TS_STATE="демон не отвечает"
  fi
fi
if [ "$TS_STATE" != "Running" ]; then
  problem "Tailscale: $TS_STATE${TS_HEALTH:+ ($TS_HEALTH)} — ssh снаружи пропадёт; sudo systemctl restart tailscaled, если не помогло — tailscale up"
fi
VPN="VPN нет"
if ip -4 -br addr show tun_incy 2>/dev/null | grep -q '198\.18\.' && pgrep -x xray >/dev/null; then VPN="VPN tun_incy+xray"; fi
LAN=$(ip -4 -br addr show eno1 2>/dev/null | awk '{sub("/.*","",$3); print $3}')
info "сеть: tailscale $TS_STATE ${TS_IP} · ${VPN} · LAN ${LAN:-—}"

# --- adb и устройства -------------------------------------------------------------------------------------------------
ADB_NOTE=""
ADB_SVC=$(systemctl --user is-active box-adb 2>/dev/null)
ADB_SVC_PID=$(systemctl --user show -p MainPID --value box-adb 2>/dev/null)
SRV_PID=$(ss -H -ltnp 'sport = :5037' 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
declare -a SERIALS=()
if ! listen_tcp 5037; then
  ADB_NOTE="adb: сервер не слушает 5037"
  problem "adb-сервера нет на 5037 (служба box-adb: ${ADB_SVC:-нет})"
else
  if [ "$ADB_SVC" = "active" ] && [ "$SRV_PID" = "$ADB_SVC_PID" ]; then
    ADB_NOTE="adb: служба box-adb (pid $SRV_PID)"
  else
    ADB_NOTE="adb: сервер pid ${SRV_PID:-?} — поднят не службой (box-adb: ${ADB_SVC:-не установлена})"
    problem "adb-сервер не под службой: пропадёт вместе с чьим-то ssh-сеансом (scripts/box.sh adb adopt)"
  fi
  while read -r serial state rest; do
    [ -z "$serial" ] && continue
    SERIALS+=("$serial")
    case $state in
      device) ;;
      *) problem "устройство $serial: $state${rest:+ ($rest)}" ;;
    esac
  done < <(timeout 8 "$ADB" devices -l 2>/dev/null | sed '1d')
fi
info "$ADB_NOTE · устройств: ${#SERIALS[@]}"
# ЛИШНИЙ adb-сервер (не 5037) держит USB-устройства и прячет их от основного: 14.10 очки пропали из adb после перезагрузки —
# `adb -L tcp:5099` (поднят переменной ANDROID_ADB_SERVER_PORT=5099 у Godot) держал интерфейс Pico. Любой такой сервер — замечание.
STRAY=$(ps -eo pid=,etimes=,args= 2>/dev/null | awk '/adb .*(fork-server|server nodaemon|-L tcp)/ && !/-L tcp:(localhost:)?5037/ && !/awk/ {printf "pid %s (%d ч): %s; ", $1, $2/3600, substr($0, index($0,$3), 60)}')
[ -n "$STRAY" ] && problem "лишний adb-сервер вне 5037 держит USB-устройства и прячет их от основного: $STRAY — остановить: ANDROID_ADB_SERVER_PORT=<порт> adb kill-server"
# Кто убивает общий сервер: adb сам пишет в журнал службы цепочку процессов kill-server. Свежее убийство (30 мин) — замечание:
# каждое рвёт устройства и reverse/forward у всех сессий.
KILLS=$(journalctl --user -u box-adb --since '24 hours ago' --no-pager -o short-iso 2>/dev/null | grep -c 'killed by remote request')
if [ "${KILLS:-0}" -gt 0 ]; then
  LASTK=$(journalctl --user -u box-adb --since '24 hours ago' --no-pager -o short-iso 2>/dev/null | grep 'killed by remote request' | tail -1 | cut -c1-16 | tr 'T' ' ')
  WHO=$(journalctl --user -u box-adb --since '24 hours ago' --no-pager 2>/dev/null | grep -A2 'adb kill-server' | grep 'cmdline:' | grep -v 'adb kill-server' \
    | sed -E 's/.*cmdline://' | cut -c1-60 | sort | uniq -c | sort -rn | head -2 | sed -E 's/^ *([0-9]+) /\1× /' | paste -sd';' -)
  info "adb: kill-server за сутки $KILLS (последний $LASTK; кто: ${WHO:-?})"
  if [ "$(date -d "$LASTK" +%s 2>/dev/null || echo 0)" -gt $((NOW - 1800)) ]; then
    problem "adb-сервер убивали за последние 30 мин ($KILLS за сутки; кто: ${WHO:-?}) — рвёт устройства и forward/reverse у всех"
  fi
fi

DEVSCRIPT='
echo "model=$(getprop ro.product.model)"
echo "rel=$(getprop ro.build.version.release)"
echo "now=$(date +%s)"
echo "bat=$(dumpsys battery 2>/dev/null | grep -m1 "level:")"
echo "wlan=$(ip -o -4 addr show wlan0 2>/dev/null | head -1)"
echo "vpn=$(ip -o addr show 2>/dev/null | grep -E " (tun|ppp|wg|tap)[0-9]+ " | head -1)"
echo "focus=$(dumpsys window 2>/dev/null | grep -m1 mCurrentFocus)"
exit
'
dev_line() { # dev_line <serial> — одна строка про устройство; пустое/ошибки не роняют статус
  local s=$1 raw model rel now bat wlan vpn focus ip skew usb tm fg fwd rev
  raw=$(printf '%s\n' "$DEVSCRIPT" | timeout 12 "$ADB" -s "$s" shell 2>/dev/null | tr -d '\r')
  if [ -z "$raw" ]; then echo "  $s: не отвечает на adb shell (занято? экран заблокирован?)"; return; fi
  model=$(sed -n 's/^model=//p' <<<"$raw")
  rel=$(sed -n 's/^rel=//p' <<<"$raw")
  now=$(sed -n 's/^now=//p' <<<"$raw")
  bat=$(sed -n 's/^bat=level: *//p' <<<"$raw")
  wlan=$(sed -n 's/^wlan=//p' <<<"$raw")
  vpn=$(sed -n 's/^vpn=//p' <<<"$raw")
  focus=$(sed -n 's/^focus=//p' <<<"$raw")
  ip=$(sed -E -n 's/.* inet ([0-9.]+).*/\1/p' <<<"$wlan")
  fg=$(sed -E -n 's/.* ([A-Za-z0-9_.]+)\/.*/\1/p' <<<"$focus")
  usb=$("$ADB" devices -l 2>/dev/null | grep -F "$s" | sed -E -n 's/.*usb:([0-9.-]+).*/\1/p' | head -1)
  vpnt="VPN нет"
  [ -n "$vpn" ] && vpnt="VPN $(sed -E -n 's/^[0-9]+: ([A-Za-z0-9_]+).*/\1/p' <<<"$vpn")"
  tm="время ок"
  if [ -n "$now" ]; then
    skew=$((now - NOW)); [ "$skew" -lt 0 ] && skew=$((-skew))
    [ "$skew" -gt 120 ] && tm="время расходится на $(dur "$skew") ($(date -d "@$now" '+%F %H:%M' 2>/dev/null))"
  else
    tm="время ?"
  fi
  fwd=$("$ADB" forward --list 2>/dev/null | awk -v s="$s" '$1==s{printf "%s→%s ", $2, $3}')
  rev=$(timeout 6 "$ADB" -s "$s" reverse --list 2>/dev/null | awk 'NF>=3{printf "%s←%s ", $3, $2}')
  echo "  $s ${model:-?} (Android ${rel:-?}) usb ${usb:-?} · Wi-Fi ${ip:-нет} · ${tm} · ${vpnt} · фокус ${fg:-—}${bat:+ · бат ${bat}%}${fwd:+ · forward ${fwd}}${rev:+ · reverse ${rev}}"
}
if [ "$BRIEF" = 0 ] && [ "${#SERIALS[@]}" -gt 0 ]; then
  TMP=$(mktemp -d)
  i=0
  for s in "${SERIALS[@]}"; do
    # устройства опрашиваем параллельно: каждый adb shell — до 12 с
    (dev_line "$s" >"$TMP/$i") &
    i=$((i + 1))
  done
  wait
  DEVLINES=$(cat "$TMP"/* 2>/dev/null | sort)
  rm -rf "$TMP"
fi

# --- порты ------------------------------------------------------------------------------------------------------------
UPS=(); DOWNS=()
chk() { # chk tcp|udp <порт> <имя>
  if "listen_$1" "$2"; then UPS+=("$2 $3"); else DOWNS+=("$2 $3"); fi
}
chk tcp 9876 blender-mcp; chk tcp 8000 godot-ai; chk tcp 9500 godot-ai-ws; chk udp 7777 стенд-сети
chk tcp 2517 коллектор-e2e; chk tcp 2527 live-коллектор; chk tcp 4174 uavmap; chk tcp 8765 surf-decals
case " ${DOWNS[*]} " in *"9876 blender-mcp"*) problem "blender-mcp не слушает 9876 (Blender не запущен или без сервера; загрузочная проверка: ~/box/boot.report)";; esac
case " ${DOWNS[*]} " in *"8000 godot-ai"*) problem "редактор Godot AI не слушает 8000 (godot-ai.desktop стартует через 20 с после входа)";; esac
info "порты: слушают ${UPS[*]:-—} | нет ${DOWNS[*]:-—}"

# --- чем занята машина ------------------------------------------------------------------------------------------------
BUSY=()
while read -r _ rss args; do
  case $args in
    *GradleDaemon*) BUSY+=("gradle-демон $((rss / 1024)) МБ");;
    *GradleWrapperMain*|*gradle-launcher*) BUSY+=("gradle-клиент идёт");;
    */godot*--editor*|godot\ --editor*) BUSY+=("godot-редактор $((rss / 1024)) МБ");;
    */godot*GdUnit*|godot\ *GdUnit*) BUSY+=("godot gdUnit");;
    */godot*--headless*|godot\ --headless*) BUSY+=("godot-headless");;
    *qemu-system*|*/emulator/emulator*) BUSY+=("эмулятор");;
    */blender\ -b*|*/blender\ --background*) BUSY+=("blender-фон");;
    */.local/bin/blender*|/usr/bin/blender*) BUSY+=("blender-GUI $((rss / 1024)) МБ");;
  esac
done < <(ps -eo pid=,rss=,args= 2>/dev/null | grep -E 'Gradle|godot|qemu-system|emulator|blender' | grep -v -E 'grep|ps -eo|probe\.sh')
info "занято: ${BUSY[*]:-ничем из известного}"

# --- очереди и брони (scripts/box/ctl.sh из клона; нет клона — пропускаем) -------------------------------------------------
CTL=$BOX/repo/scripts/box/ctl.sh
if [ -f "$CTL" ]; then
  QRAW=$(bash "$CTL" queue </dev/null 2>/dev/null)
  if grep -q -E 'занято|ждут|^ +[0-9]+\.' <<<"$QRAW"; then
    info "очередь:"$'\n'"$(sed 's/^/  /' <<<"$QRAW")"
  else
    info "очередь: gradle и gpu свободны, замки gdUnit/display не заняты"
  fi
  LLINES=$(bash "$CTL" leases </dev/null 2>/dev/null | sed 's/^/  /')
  [ -n "$LLINES" ] && info "брони:"$'\n'"$LLINES"
  # Очки Pico: датчик приближения заклеен, сами не гаснут — Awake без брони = замечание (риск выгорания матриц).
  # Запаркованная карточка границы вне прогона — замечание: в очках человека будет пусто (инцидент 14.10 ~10:00): `box.sh pico unpark`.
  if [ -n "$(find "$BOX/pico-parked.stack" -mmin +20 2>/dev/null)" ]; then
    problem "карточка границы запаркована на другой дисплей (стек/boot: $(cat "$BOX/pico-parked.stack")) — человек в очках не увидит игру: scripts/box.sh pico unpark"
  fi
  PICO_ST=$(bash "$CTL" pico status </dev/null 2>&1); PICO_RC=$?
  if [ "$PICO_RC" -ne 0 ] && grep -q 'БЕЗ БРОНИ' <<<"$PICO_ST"; then
    problem "$PICO_ST"
  elif [ "$PICO_RC" -ne 0 ]; then
    info "$PICO_ST"
  else
    info "$PICO_ST"
  fi
fi

# --- после загрузки и скрипты -----------------------------------------------------------------------------------------
BTIME=$(awk '/^btime/{print $2}' /proc/stat)
REPORT=$BOX/boot.report
if [ -f "$REPORT" ]; then
  RT=$(stat -c %Y "$REPORT")
  RV=$(sed -n 's/^verdict=//p' "$REPORT")
  if [ "$RT" -lt "$BTIME" ]; then
    problem "автозапуск не отчитался после последней загрузки (отчёт старше загрузки на $(dur $((BTIME - RT))))"
  elif [ "$RV" != "ok" ]; then
    problem "после загрузки: $(sed -n 's/^problems=//p' "$REPORT") (подробно: ~/box/boot.report)"
  fi
  info "после загрузки: ${RV:-?}, отчёт $(dur $((NOW - RT))) назад"
else
  problem "нет ~/box/boot.report: автозапуск из репозитория не установлен (scripts/box.sh sync)"
fi
if [ -d "$BOX/repo/.git" ]; then
  HERE=$(git -C "$BOX/repo" rev-parse --short HEAD 2>/dev/null)
  TIP=$(timeout 8 git -C "$BOX/repo" ls-remote origin main 2>/dev/null | cut -c1-7)
  DESK=$(sed -n 's/^Exec=//p' "$HOME/.config/autostart/devbox-session.desktop" 2>/dev/null)
  if [ "$DESK" != "$BOX/repo/scripts/devbox-session-start.sh" ]; then
    problem "автозапуск идёт не из репозитория: Exec=${DESK:-?} (scripts/box.sh sync)"
  fi
  REF=$(cat "$BOX/repo.ref" 2>/dev/null || echo "?")
  if [ -n "$TIP" ] && [ "$TIP" = "$HERE" ]; then
    info "скрипты: клон ~/box/repo на $HERE = origin/main"
  elif [ "$REF" = "main" ] && [ -n "$TIP" ]; then
    info "скрипты: клон ~/box/repo на $HERE, origin/main уже $TIP — отстают (scripts/box.sh sync)"
  else
    info "скрипты: клон ~/box/repo на $HERE (${REF}), origin/main${TIP:+ $TIP}"
  fi
else
  problem "нет клона ~/box/repo: скрипты devbox — ручная копия (scripts/box.sh sync)"
fi

# --- вывод ------------------------------------------------------------------------------------------------------------
N=${#PROBLEMS[@]}
if [ "$N" -eq 0 ]; then echo "devbox: ОК"; else echo "devbox: ВНИМАНИЕ — замечаний $N"; fi
for p in "${PROBLEMS[@]}"; do echo "  ! $p"; done
if [ "$BRIEF" = 0 ]; then
  for l in "${INFO[@]}"; do echo "$l"; done
  [ -n "${DEVLINES:-}" ] && { echo "устройства:"; echo "$DEVLINES"; }
fi
[ "$N" -eq 0 ]

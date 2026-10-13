#!/bin/bash
# Менеджер devbox с Mac (зона «Devbox», docs/devbox.md): состояние машины одной командой и установка своих скриптов на неё.
#   scripts/box.sh status [--brief]   — вердикт, замечания, сводка: машина, сеть, adb, устройства, порты, чем занята. Код 0/1.
#                                       Пробу (scripts/box/probe.sh) гоним по ssh со стандартного ввода — копии на devbox нет.
#   scripts/box.sh sync [ветка|sha]   — клон репозитория ~/box/repo на devbox (только scripts/) → указанная ревизия (по умолчанию
#                                       main); user-служба box-adb и автозапуск сеанса берутся оттуда. Ветка должна быть на origin.
#   scripts/box.sh adb [status|adopt [--force]] — adb-сервер: чей он; adopt переводит чужой сервер под службу box-adb (рвёт
#                                       reverse/forward — поэтому проверяет, что их нет и что нет идущих команд adb, Gradle, эмуляторов)
#   scripts/box.sh lease <ресурс> <владелец> <мин> [заметка] | release <ресурс> <владелец> [--force] | leases | check <ресурс> <владелец>
#                                     — брони устройств/портов/стенда (1–480 мин, истекают сами; серийник = rcpad|xcover7|pico)
#   scripts/box.sh run <gradle|gpu|light> <владелец> [--wait сек] [--name имя] -- команда…  — выполнить НА devbox в очереди класса
#   scripts/box.sh queue [класс]      — кто держит и кто ждёт (в т. ч. замки dbx.sh, gdUnit, display); подробности — scripts/box/ctl.sh
#   scripts/box.sh pico status | wake <владелец> <мин> [заметка] | sleep <владелец> [--force]  — очки Pico: будить только под бронь
#                                       `pico`, гасить сразу после (датчик заклеен). guard on|off|status — таймер-страж: гасит Awake без брони > 3 мин
#   scripts/box.sh boot-check         — прогнать проверку после загрузки вручную (идемпотентно: ничего не убивает и не перезапускает,
#                                       что уже работает); итог — ~/box/boot.report и строка в статусе
#   scripts/box.sh journal [N]        — последние N (20) строк журнала действий ~/box/journal.jsonl
# Перезагрузка devbox, драйверы, пакеты, пароли — только владелец (docs/devbox.md, «Нельзя»).
set -u
HOST=devbox
TS_IP=100.80.115.46
LAN_IP=192.168.1.141
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(hostname -s 2>/dev/null)" = "$HOST" ]; then
  # Запущен на самом devbox (из клона ~/box/repo, из ssh-сеанса сессии): ходить по ssh к себе незачем, да и не выйдет —
  # нет known_hosts («Host key verification failed», 13.10). Те же команды, локально; stdin сохраняется.
  onbox() { bash -c "$*"; }
  SSH=(onbox)
else
  SSH=(ssh -o ConnectTimeout=8 -o BatchMode=yes "$HOST")
fi

unreachable() { # ssh не прошёл: отличить «Tailscale лежит» от «машина выключена»
  local ts=нет lan=нет
  ping -c1 -t2 "$TS_IP" >/dev/null 2>&1 && ts=есть
  ping -c1 -t2 "$LAN_IP" >/dev/null 2>&1 && lan=есть
  echo "devbox: НЕДОСТУПЕН — ssh не отвечает (ping Tailscale $TS_IP: $ts, LAN $LAN_IP: $lan)"
  if [ "$lan" = есть ] && [ "$ts" = нет ]; then
    echo "  ! машина включена, Tailscale лежит: владельцу на devbox — sudo systemctl restart tailscaled; если не Running — sudo tailscale up"
  elif [ "$lan" = нет ] && [ "$ts" = нет ]; then
    echo "  ! машина выключена или не в сети (LAN и Tailscale молчат) — владельцу"
  fi
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  status)
    out=$("${SSH[@]}" bash -s -- "$@" <"$ROOT/scripts/box/probe.sh" 2>&1); rc=$?
    if [ "$rc" -eq 255 ]; then unreachable; exit 1; fi
    printf '%s\n' "$out"
    exit "$rc" ;;

  sync)
    REF=${1:-main}
    if [ "${SSH[0]}" = onbox ] && [ "$ROOT" = "$HOME/box/repo" ]; then
      echo "sync: из самого клона нельзя — он переписал бы скрипт на ходу; с Mac: scripts/box.sh sync [ветка]"; exit 1
    fi
    URL=$(git -C "$ROOT" remote get-url origin 2>/dev/null) || { echo "sync: у этой копии нет origin"; exit 1; }
    "${SSH[@]}" bash -s -- "$URL" "$REF" <<'REMOTE'
set -u
URL=$1; REF=$2
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
BOX=$HOME/box; REPO=$BOX/repo
mkdir -p "$BOX" "$HOME/.config/systemd/user" "$HOME/.config/autostart"
if [ ! -d "$REPO/.git" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse "$URL" "$REPO" || { echo "sync: git clone не удался"; exit 1; }
  git -C "$REPO" sparse-checkout set scripts || exit 1
fi
git -C "$REPO" fetch -q --depth 1 origin "$REF" || { echo "sync: на origin нет '$REF' (ветку запушили?)"; exit 1; }
git -C "$REPO" checkout -q --detach FETCH_HEAD || exit 1
SHA=$(git -C "$REPO" log -1 --format='%h %s' | cut -c1-90)
echo "$REF" >"$BOX/repo.ref"
# user-служба adb: копия юнита (не ссылка — юнит не должен меняться под ногами при смене ревизии клона)
UNIT=$HOME/.config/systemd/user/box-adb.service
cp -f "$REPO/scripts/box/box-adb.service" "$UNIT"
systemctl --user daemon-reload
systemctl --user enable box-adb >/dev/null 2>&1
if systemctl --user is-active --quiet box-adb; then
  ADB="служба box-adb: active (юнит обновлён, сервер не перезапускался)"
elif ss -H -ltn 'sport = :5037' | grep -q .; then
  ADB="сервер на 5037 уже есть — под службу: scripts/box.sh adb adopt"
else
  systemctl --user start box-adb; sleep 2; ADB="служба box-adb: $(systemctl --user is-active box-adb)"
fi
# автозапуск сеанса: Exec из клона (прежний файл — один раз в .orig)
D=$HOME/.config/autostart/devbox-session.desktop
[ -f "$D" ] && [ ! -f "$D.orig" ] && cp "$D" "$D.orig"
cat >"$D" <<EOF
[Desktop Entry]
Type=Application
Name=devbox-session
Comment=incy (VPN) -> Tailscale -> adb -> Blender (из репозитория: scripts/box.sh sync)
Exec=$REPO/scripts/devbox-session-start.sh
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
Terminal=false
EOF
printf '{"t":"%s","event":"sync","ref":"%s","commit":"%s"}\n' "$(date -Is)" "$REF" "${SHA%% *}" >>"$BOX/journal.jsonl"
echo "sync: ~/box/repo → $SHA"
echo "  adb: $ADB"
echo "  автозапуск: Exec=$REPO/scripts/devbox-session-start.sh"
REMOTE
    rc=$?
    [ "$rc" -eq 255 ] && { unreachable; exit 1; }
    exit "$rc" ;;

  adb)
    sub=${1:-status}
    [ $# -gt 0 ] && shift
    case $sub in
      status|adopt) ;;
      *) echo "использование: box.sh adb status | adopt [--force]"; exit 2;;
    esac
    "${SSH[@]}" bash -s -- "$sub" "${1:-_}" <<'REMOTE'
set -u
SUB=$1; FORCE=$2
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
A=$HOME/android-sdk/platform-tools/adb
listen_pid() { ss -H -ltnp 'sport = :5037' 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2; }
SVC=$(systemctl --user is-active box-adb 2>/dev/null); SVC_PID=$(systemctl --user show -p MainPID --value box-adb 2>/dev/null)
SRV=$(listen_pid)
if [ "$SUB" = status ]; then
  if [ -z "$SRV" ]; then echo "adb: сервера на 5037 нет (служба box-adb: ${SVC:-не установлена})"; exit 1; fi
  if [ "$SVC" = active ] && [ "$SRV" = "$SVC_PID" ]; then echo "adb: служба box-adb, pid $SRV"; exit 0; fi
  echo "adb: сервер pid $SRV не под службой (box-adb: ${SVC:-не установлена}) — scripts/box.sh adb adopt"; exit 1
fi
# adopt
systemctl --user cat box-adb >/dev/null 2>&1 || { echo "adb adopt: служба не установлена — scripts/box.sh sync"; exit 1; }
if [ -n "$SRV" ] && [ "$SVC" = active ] && [ "$SRV" = "$SVC_PID" ]; then echo "adb: уже под службой box-adb (pid $SRV)"; exit 0; fi
if [ -n "$SRV" ] && [ "$FORCE" != "--force" ]; then
  BLOCK=""
  CLIENTS=$(pgrep -a -x adb | grep -v -E 'fork-server|server nodaemon')
  [ -n "$CLIENTS" ] && BLOCK="$BLOCK\n  идут команды adb: $(echo "$CLIENTS" | cut -c1-100 | head -3 | paste -sd';' -)"
  FWD=$("$A" forward --list 2>/dev/null)
  [ -n "$FWD" ] && BLOCK="$BLOCK\n  есть adb forward: $(echo "$FWD" | head -3 | paste -sd';' -)"
  for s in $("$A" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}'); do
    case $s in emulator-*) BLOCK="$BLOCK\n  онлайн эмулятор $s (стенд e2e идёт?)";; esac
    REV=$(timeout 6 "$A" -s "$s" reverse --list 2>/dev/null | grep .)
    [ -n "$REV" ] && BLOCK="$BLOCK\n  у $s есть adb reverse: $(echo "$REV" | head -2 | paste -sd';' -)"
  done
  pgrep -f 'GradleWrapperMain' >/dev/null && BLOCK="$BLOCK\n  идёт клиент Gradle (installDebug?)"
  if [ -n "$BLOCK" ]; then
    echo "adb adopt: ОТКАЗ — перезапуск сервера порвёт чужое:"; printf '%b\n' "$BLOCK"
    echo "  дождаться или предупредить хозяев; осознанно — scripts/box.sh adb adopt --force"
    exit 1
  fi
fi
[ -n "$SRV" ] && "$A" kill-server
for _ in 1 2 3 4 5; do ss -H -ltn 'sport = :5037' | grep -q . || break; sleep 1; done
systemctl --user restart box-adb
for _ in 1 2 3 4 5 6 7 8 9 10; do ss -H -ltn 'sport = :5037' | grep -q . && break; sleep 1; done
sleep 3
SVC_PID=$(systemctl --user show -p MainPID --value box-adb); SRV=$(listen_pid)
if [ -n "$SRV" ] && [ "$SRV" = "$SVC_PID" ]; then
  printf '{"t":"%s","event":"adb-adopt","pid":"%s"}\n' "$(date -Is)" "$SRV" >>"$HOME/box/journal.jsonl"
  echo "adb: служба box-adb, pid $SRV; устройства: $("$A" devices 2>/dev/null | awk 'NR>1 && $2!=""{printf "%s(%s) ", $1, $2}')"
else
  echo "adb adopt: служба не взяла порт (сервер: ${SRV:-нет}, служба: $(systemctl --user is-active box-adb)) — journalctl --user -u box-adb"; exit 1
fi
REMOTE
    rc=$?
    [ "$rc" -eq 255 ] && { unreachable; exit 1; }
    exit "$rc" ;;

  boot-check)
    "${SSH[@]}" 'timeout 900 bash "$HOME/box/repo/scripts/devbox-session-start.sh"; rc=$?; sed -n "s/^verdict=/после загрузки: /p;s/^problems=/  проблемы: /p;s/^devices=/  устройства: /p" "$HOME/box/boot.report"; exit $rc'
    rc=$?
    [ "$rc" -eq 255 ] && { unreachable; exit 1; }
    exit "$rc" ;;

  lease|release|leases|check|run|queue|pico)
    # Логика — scripts/box/ctl.sh из клона ~/box/repo: одна версия на всех, а не та, что у вызвавшего в worktree.
    args=$cmd
    for a in "$@"; do args="$args $(printf '%q' "$a")"; done
    "${SSH[@]}" "[ -f \"\$HOME/box/repo/scripts/box/ctl.sh\" ] || { echo 'нет клона ~/box/repo: scripts/box.sh sync' >&2; exit 4; }; bash \"\$HOME/box/repo/scripts/box/ctl.sh\" $args"
    rc=$?
    [ "$rc" -eq 255 ] && { unreachable; exit 1; }
    exit "$rc" ;;

  guard)
    # Страж очков (раз в минуту гасит Awake без брони дольше 3 мин): ставится и снимается только этой командой.
    sub=${1:-status}
    case $sub in on|off|status) ;; *) echo "использование: box.sh guard on|off|status"; exit 2;; esac
    "${SSH[@]}" bash -s -- "$sub" <<'REMOTE'
set -u
SUB=$1
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
R=$HOME/box/repo/scripts/box; U=$HOME/.config/systemd/user
case $SUB in
  on)
    [ -f "$R/box-pico-guard.timer" ] || { echo "guard: нет юнитов в ~/box/repo (scripts/box.sh sync <ветка с юнитами>)"; exit 1; }
    cp -f "$R/box-pico-guard.service" "$R/box-pico-guard.timer" "$U/"
    systemctl --user daemon-reload && systemctl --user enable --now box-pico-guard.timer >/dev/null 2>&1
    printf '{"t":"%s","event":"pico-guard-on"}\n' "$(date -Is)" >>"$HOME/box/journal.jsonl" ;;
  off)
    systemctl --user disable --now box-pico-guard.timer >/dev/null 2>&1
    printf '{"t":"%s","event":"pico-guard-off"}\n' "$(date -Is)" >>"$HOME/box/journal.jsonl" ;;
esac
echo "guard: таймер $(systemctl --user is-enabled box-pico-guard.timer 2>/dev/null || echo не-установлен) / $(systemctl --user is-active box-pico-guard.timer 2>/dev/null || echo неактивен)"
REMOTE
    rc=$?
    [ "$rc" -eq 255 ] && { unreachable; exit 1; }
    exit "$rc" ;;

  journal)
    n=${1:-20}
    case $n in ''|*[!0-9]*) echo "использование: box.sh journal [N]"; exit 2;; esac
    "${SSH[@]}" "tail -n $n \"\$HOME/box/journal.jsonl\" 2>&1" ;;

  *)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    [ -z "$cmd" ] && exit 2
    exit 2 ;;
esac

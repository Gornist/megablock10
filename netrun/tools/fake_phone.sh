#!/usr/bin/env bash
# «Фальшивый телефон» для живой проверки связи очков с телефоном без приложения Android (tools/fake_phone.gd).
#   netrun/tools/fake_phone.sh <хост_очков> [токен] [сценарий: idle|chat|call|all]
# Порт — FAKE_PHONE_PORT (7420), позывной — FAKE_PHONE_CALLSIGN (Призрак), пауза на ответы очков после сценария — FAKE_PHONE_HOLD (30 с).
# На Mac сначала синхронизирует netrun/ на devbox (dev.sh sync) и идёт `ssh devbox`; на самом devbox (Linux) запускает Godot тут же из текущей копии.
# Вывод: `<- {json}` кадры от очков, `-> {json}` отправленные; в конце вердикт `FAKE_PHONE ok` или `FAKE_PHONE closed code=… reason=…` (код выхода 0 / 1).
# Очки в это время должны слушать (RemotePhoneLink.start на том же порту и токене); ключ токена — обычные латиница/цифры/-/_.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $# -ge 1 ]] || { echo "usage: fake_phone.sh <хост_очков> [токен] [idle|chat|call|all]" >&2; exit 2; }
HOST_GLASSES=$1
TOKEN=${2:-}
SCENARIO=${3:-all}
PORT=${FAKE_PHONE_PORT:-7420}
CALLSIGN=${FAKE_PHONE_CALLSIGN:-Призрак}
HOLD=${FAKE_PHONE_HOLD:-30}
[[ "$SCENARIO" =~ ^(idle|chat|call|all)$ ]] || { echo "fake_phone.sh: сценарий idle|chat|call|all, а не '$SCENARIO'" >&2; exit 2; }
[[ "$TOKEN" =~ ^[A-Za-z0-9_-]*$ ]] || { echo "fake_phone.sh: токен — латиница, цифры, - и _" >&2; exit 2; }
[[ "$HOST_GLASSES" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "fake_phone.sh: странный адрес очков '$HOST_GLASSES'" >&2; exit 2; }
URL="ws://$HOST_GLASSES:$PORT/"
[[ -n "$TOKEN" ]] && URL="$URL?token=$TOKEN"
LIMIT=$((HOLD + 90))
LOG=$(mktemp "${TMPDIR:-/tmp}/fake-phone.XXXXXX")
trap 'rm -f "$LOG"' EXIT

# Команда Godot (на devbox): неинтерактивный ssh не читает профиль, путь к godot задаёт ~/netrun-env.sh.
godot_cmd() {
  cat <<CMD_EOF
command -v godot >/dev/null 2>&1 || [[ ! -f "\$HOME/netrun-env.sh" ]] || . "\$HOME/netrun-env.sh"
cd "\$1/netrun" || exit 3
export LC_ALL=C.UTF-8 LANG=C.UTF-8
timeout $LIMIT godot --headless --path . -s res://tools/fake_phone.gd -- --url='$URL' --scenario=$SCENARIO --callsign='$CALLSIGN' --hold=$HOLD
CMD_EOF
}

if [[ "$(uname -s)" == "Linux" ]]; then
  bash -c "$(godot_cmd)" _ "$ROOT" 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[0]}
else
  BRANCH=$(git -C "$ROOT" branch --show-current)
  SLUG=${BRANCH#agent/}
  SLUG=${SLUG//\//-}
  REMOTE=${DEV_REMOTE:-wt-$SLUG}
  "$ROOT/netrun/tools/dev.sh" sync >&2 || { echo "FAKE_PHONE closed code=0 reason=sync failed"; exit 1; }
  godot_cmd | ssh "${DEV_HOST:-devbox}" bash -s -- "\$HOME/$REMOTE" 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[1]}
fi

if grep -aq '^\[fake-phone\] ok' "$LOG" && [[ $rc -eq 0 ]]; then
  echo "FAKE_PHONE ok"
  exit 0
fi
closed=$(grep -a '^closed code=' "$LOG" | tail -1)
echo "FAKE_PHONE ${closed:-closed code=0 reason=нет итога (rc=$rc)}"
exit 1

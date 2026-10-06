#!/usr/bin/env bash
# GitHub Actions self-hosted runner на devbox (тяжёлый e2e). Запускать С MAC: scripts/devbox-runner.sh install|status|remove
#   install — токен РЕГИСТРАЦИИ со stdin (не аргументом, не в журнал):
#             gh api -X POST repos/Gornist/megablock10/actions/runners/registration-token -q .token | scripts/devbox-runner.sh install
#   remove  — токен УДАЛЕНИЯ со stdin: gh api -X POST repos/Gornist/megablock10/actions/runners/remove-token -q .token | scripts/devbox-runner.sh remove
#   status  — одна строка: RUNNER online|offline|не установлен
# Код выхода: 0 — готово/online, 1 — ошибка или offline, 2 — неверное использование.
# Раннер: ~/actions-runner на devbox, systemd --user сервис actions-runner, метка devbox, НЕ под root.
# Очередь с dbx.sh: шаги workflow обязаны идти через `flock -w 2700 ~/.dbx.lock <команда>` (docs/ci.md).
set -euo pipefail

REPO="${RUNNER_REPO:-Gornist/megablock10}"
HOST="${RUNNER_HOST:-devbox}"
DIR='$HOME/actions-runner'
UNIT=actions-runner

die() { echo "RUNNER $*" >&2; exit 1; }
usage() { echo "usage: $0 install|status|remove (токен — со stdin)" >&2; exit 2; }

read_token() {
  [[ -t 0 ]] && { echo "RUNNER токен нужен со stdin (см. шапку скрипта)" >&2; exit 2; }
  local t
  IFS= read -r t || true
  [[ -n "$t" ]] || { echo "RUNNER пустой токен на stdin" >&2; exit 2; }
  printf '%s' "$t"
}

cmd_status() {
  local inst gh_state
  inst=$(ssh -o ConnectTimeout=8 "$HOST" "[ -x $DIR/run.sh ] && systemctl --user is-active $UNIT 2>/dev/null || echo none" || echo ssh-fail)
  if [[ "$inst" == ssh-fail ]]; then echo "RUNNER devbox недоступен по ssh"; exit 1; fi
  gh_state=$(gh api "repos/$REPO/actions/runners" --jq '[.runners[]|select(.name=="devbox")][0] | if .==null then "none" else "\(.status)\(if .busy then "+busy" else "" end)" end' 2>/dev/null || echo "gh-fail")
  if [[ "$inst" == none && "$gh_state" == none ]]; then echo "RUNNER не установлен"; exit 1; fi
  echo "RUNNER ${gh_state/#none/нет в GitHub} (сервис: $inst)"
  case "$gh_state" in online*) exit 0 ;; *) exit 1 ;; esac
}

cmd_install() {
  local token ver sha
  token=$(read_token)
  ver=$(gh api repos/actions/runner/releases/latest --jq .tag_name | sed 's/^v//')
  sha=$(gh api repos/actions/runner/releases/latest --jq .body \
    | grep -o 'actions-runner-linux-x64-[0-9.]*\.tar\.gz[^<]*<!-- hash: *[0-9a-f]*' | head -1 | sed 's/.*hash: *//' || true)
  if [[ -z "$sha" ]]; then
    sha=$(gh api repos/actions/runner/releases/latest --jq .body \
      | sed -n 's/.*BEGIN SHA linux-x64 -->\([0-9a-f]\{64\}\)<!-- END SHA linux-x64.*/\1/p' | head -1)
  fi
  [[ "$ver" =~ ^[0-9.]+$ && "$sha" =~ ^[0-9a-f]{64}$ ]] || die "не удалось взять версию/sha256 релиза (ver='$ver')"
  # Токен идёт по stdin ssh, на devbox читается `read` — в argv и журнал не попадает.
  local remote
  remote=$(cat <<'EOF'
set -euo pipefail
read -r TOKEN
[ "$(id -u)" != 0 ] || { echo "RUNNER нельзя под root"; exit 1; }
D="$HOME/actions-runner"; mkdir -p "$D"; cd "$D"
if [ ! -x ./run.sh ]; then
  curl -fsSL -o r.tgz "https://github.com/actions/runner/releases/download/v$VER/actions-runner-linux-x64-$VER.tar.gz"
  echo "$SHA  r.tgz" | sha256sum -c - >/dev/null || { echo "RUNNER sha256 не совпал"; rm -f r.tgz; exit 1; }
  tar xzf r.tgz && rm -f r.tgz
fi
./config.sh --unattended --url "https://github.com/$REPO" --token "$TOKEN" --labels devbox --name devbox --replace >/dev/null
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/$UNIT.service" <<UNITEOF
[Unit]
Description=GitHub Actions runner (devbox)
After=network-online.target
[Service]
WorkingDirectory=$D
ExecStart=$D/run.sh
Restart=always
RestartSec=10
KillMode=process
[Install]
WantedBy=default.target
UNITEOF
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT" >/dev/null
if [ "$(loginctl show-user "$USER" -p Linger --value)" != yes ]; then
  echo "RUNNER linger выключен: после выхода из сессии сервис остановится. Владельцу на devbox: sudo loginctl enable-linger $USER"
fi
echo "RUNNER установлен v$VER, сервис $UNIT запущен"
EOF
)
  printf '%s\n' "$token" | ssh "$HOST" "VER=$ver SHA=$sha REPO=$REPO UNIT=$UNIT bash -c $(printf '%q' "$remote")" || die "установка не удалась"
  cmd_status || true
}

cmd_remove() {
  local token remote
  token=$(read_token)
  remote=$(cat <<'EOF'
set -euo pipefail
read -r TOKEN
D="$HOME/actions-runner"
systemctl --user disable --now "$UNIT" 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/$UNIT.service"; systemctl --user daemon-reload
[ -x "$D/config.sh" ] && (cd "$D" && ./config.sh remove --token "$TOKEN" >/dev/null) || true
echo "RUNNER снят (каталог $D оставлен; удалить: rm -rf $D)"
EOF
)
  printf '%s\n' "$token" | ssh "$HOST" "UNIT=$UNIT bash -c $(printf '%q' "$remote")" || die "снятие не удалось"
}

case "${1:-}" in
  install) cmd_install ;;
  status) cmd_status ;;
  remove) cmd_remove ;;
  *) usage ;;
esac

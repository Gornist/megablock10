#!/usr/bin/env bash
# Итерация эталона V11: кадры сцены на devbox + сверка с CP2077 (числа и сетка «эталон | CP2077» на Mac).
#   netrun/assets/look_v11/run.sh [--set=row=0.04,...] [--only=wide]
#   LOOK_RM=mobile — тем же рендером, что клиент (по умолчанию forward_plus: эталон на ПК; Mobile квантует почти-чёрное в 10 бит).
#   LOOK_PAIRS=кадр:реф,...  LOOK_RES=1280x720  LOOK_OUT=/tmp/look_cmp.png
# Кадры CP2077 ждутся на devbox в ~/look-v11/ref (r376, r470, r520 — ffmpeg -ss <с> из video.mkv, 1280×720).
# Свой запуск вместо dev.sh shot: dev.sh не передаёт --rendering-method. Очередь gpu и замок дисплея — те же.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
SLUG=$(git -C "$ROOT" branch --show-current); SLUG=${SLUG#agent/}; SLUG=${SLUG//\//-}
REMOTE=wt-$SLUG
DIR=/tmp/dev-shots/$REMOTE
OUT=${LOOK_OUT:-/tmp/look_cmp.png}
"$ROOT/netrun/tools/dev.sh" sync > /dev/null || { echo "run.sh: sync упал"; exit 1; }
# shellcheck disable=SC2029
ssh devbox "set -u; cd ~/$REMOTE || exit 3
export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-0
rm -rf $DIR && mkdir -p $DIR
timeout 300 ~/.local/bin/godot --headless --path netrun --import > /dev/null 2>&1 </dev/null || true
CTL=\$HOME/box/repo/scripts/box/ctl.sh
gpu() { if [ -f \"\$CTL\" ]; then bash \"\$CTL\" run gpu Look --name look --wait 900 -- \"\$@\"; else \"\$@\"; fi; }
gpu bash -c 'timeout 240 flock /tmp/display.lock ~/.local/bin/godot --rendering-method ${LOOK_RM:-forward_plus} --display-driver wayland --path netrun --resolution ${LOOK_RES:-1280x720} res://assets/look_v11/look_v11.tscn -- --out=$DIR $* > $DIR/run.log 2>&1 </dev/null'
grep -a 'LOOK\|ERROR\|SCRIPT' $DIR/run.log | head -5
python3 -W ignore ~/$REMOTE/netrun/assets/look_v11/compare.py $DIR ~/look-v11/ref /tmp/look_cmp.png ${LOOK_PAIRS:-wide:r376,pillar:r470,floor:r520}"
scp -q devbox:/tmp/look_cmp.png "$OUT" && echo "run.sh: сетка на Mac: $OUT"

#!/usr/bin/env bash
# Брони и очередь devbox для скриптов Сети (D4, docs/devbox.md «Что уже работает»): подключается `. box_guard.sh` из pico_stand.sh и pico_series.sh
# (они идут НА devbox). Кооперативно: чужая бронь — отказ «кто и до когда»; машина без ~/box/repo (не devbox) — ничего не проверяется.
#   box_check <ресурс>            0 — свободно или бронь наша; 1 — чужая (строка «занято: …» уже напечатана). Ресурсы: pico, port:7777
#   box_ctl <подкоманда> [арги…]  ctl.sh с владельцем BOX_OWNER (по умолчанию Godot): box_ctl pico ready, box_ctl pico sleep
# Окружение: BOX_OWNER (имя сессии в бронях), BOX_CTL (путь к ctl.sh, по умолчанию ~/box/repo/scripts/box/ctl.sh).

BOX_OWNER="${BOX_OWNER:-Godot}"
BOX_CTL="${BOX_CTL:-$HOME/box/repo/scripts/box/ctl.sh}"

box_has() { [ -f "$BOX_CTL" ]; }

box_check() {
  box_has || return 0
  local out
  out=$(bash "$BOX_CTL" check "$1" "$BOX_OWNER" </dev/null 2>&1) && return 0
  echo "$out" >&2
  return 1
}

## box_ctl pico ready → `ctl.sh pico ready Godot`; подкоманды, где владелец идёт последним аргументом (ready, sleep).
box_ctl() {
  box_has || { echo "box_guard: нет $BOX_CTL (не devbox)" >&2; return 1; }
  bash "$BOX_CTL" "$@" "$BOX_OWNER" </dev/null
}

#!/usr/bin/env bash
# Серия замеров на очках подряд: на каждый вариант — конфиг (pico_stand.sh) → перезапуск игры → ожидание `[bench] ИТОГ` / `[probe] ИТОГ` →
# строки итога и PNG кадра вида (perf=diag, XrDiag) в каталог результатов. Запускать на devbox; одну серию на очки.
#
#   pico_series.sh "<имя>=<пресет> [ключ=значение ...]" ...
#   пример: pico_series.sh "w1=bench veil_scale=0 bench=wedge" "w2=bench tile_glow=0 bench=wedge" "ctrl=bench bench=wedge"
#
# ОДИН ПУТЬ К ОЧКАМ (Д5, решение владельца 13.10 после 17:27): на devbox серия сама идёт внутри `ctl.sh pico run Godot <мин> -- …` —
# бронь, пробуждение, ready по состоянию системы (свет, граница, трекинг), снимки до/после, logcat, погасить, снять бронь, один вердикт.
# Здесь НЕТ своих wake/sleep/stayon/KEYCODE и нажатий в системных окнах. Не готово (ready) — серия не стартует, код run 20, «нужен человек».
# Между вариантами: `pico ready` (идемпотентный) → `pico start` (игра на переднем плане, «kept for the user» = НЕ ГОТОВО). Исходный
# netrun.cfg сохраняется на входе и возвращается по выходу (trap), игра останавливается.
#
# Окружение: PICO_SERIAL (устройство; run ставит сам), OUT (каталог результатов; по умолчанию PICO_RUN_DIR прогона, иначе ~/pico-series/<время>),
# WAIT_SEC (ожидание итога на вариант, 150), PICO_RUN_MIN (бронь и предел серии, мин; по умолчанию 20 — серия из 4 вариантов ≈ 12–15),
# PICO_RUN_TIMEOUT (сек, предел команды в run), PICO_SERVER_CMD (команда сервера мира; запускается на серию; на devbox run берёт `--port`
# PICO_PORT, по умолчанию 7777), BOX_OWNER (имя сессии в бронях, Godot). Не на devbox (нет ~/box/repo): серия без брони и run —
# `am start` напрямую, PICO_READY_CMD (например pico_ready.sh) — подготовка очков по желанию.
set -u

PACKAGE="com.megablok10.netrun"
COMPONENT="$PACKAGE/com.godot.game.GodotAppLauncher"
CFG_PATH="/sdcard/Android/data/$PACKAGE/files/netrun.cfg"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HOME/netrun-env.sh" ] && . "$HOME/netrun-env.sh"
. "$HERE/box_guard.sh"

[ "$#" -gt 0 ] || { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2; }

# Внешний слой: на devbox серия идёт внутри `pico run` (он берёт и снимает брони pico и порта, будит и гасит очки).
if [ -z "${PICO_RUN_INNER:-}" ] && box_has; then
  opts=()
  [ -z "${PICO_SERVER_CMD:-}" ] || opts+=(--port "${PICO_PORT:-7777}")
  [ -z "${PICO_RUN_TIMEOUT:-}" ] || opts+=(--timeout "$PICO_RUN_TIMEOUT")
  exec bash "$BOX_CTL" pico run "$BOX_OWNER" "${PICO_RUN_MIN:-20}" ${opts[@]+"${opts[@]}"} -- env PICO_RUN_INNER=1 bash "$0" "$@"
fi

WAIT_SEC="${WAIT_SEC:-150}"
OUT="${OUT:-${PICO_RUN_DIR:-$HOME/pico-series/$(date +%m%d-%H%M)}}"
mkdir -p "$OUT"

serial="${PICO_SERIAL:-}"
if [ -z "$serial" ]; then
  serial=$(adb devices | awk '$2=="device"{print $1}')
  [ "$(echo "$serial" | grep -c .)" = 1 ] || { echo "pico_series: нужно ровно одно устройство или PICO_SERIAL" >&2; exit 1; }
fi
export PICO_SERIAL="$serial"

# ready / start: на devbox — штатные ctl.sh pico ready|start (по состоянию системы, без нажатий отсюда); иначе запасной путь.
pico_ready() {
  if box_has; then
    bash "$BOX_CTL" pico ready "$BOX_OWNER" </dev/null 2>&1
    return $?
  elif [ -n "${PICO_READY_CMD:-}" ]; then
    $PICO_READY_CMD 2>&1
    return $?
  fi
  return 0
}
pico_start() {
  if box_has; then
    bash "$BOX_CTL" pico start "$BOX_OWNER" "$COMPONENT" </dev/null 2>&1
    return $?
  fi
  local started
  started=$(adb -s "$serial" shell am start -n "$COMPONENT" </dev/null 2>&1)
  if echo "$started" | grep -q "kept for the user"; then
    echo "игра не стартует — поверх висит системный диалог Pico («kept for the user»)"
    return 1
  fi
  return 0
}
pico_fg() { box_has && bash "$BOX_CTL" pico fg "$BOX_OWNER" </dev/null 2>&1 | tail -1; }

# Исходный netrun.cfg на входе → обратно по выходу: серия правит cfg между вариантами, после неё очки должны остаться как были.
cfg_orig="$OUT/netrun.cfg.orig"
cfg_had=0
adb -s "$serial" pull "$CFG_PATH" "$cfg_orig" >/dev/null 2>&1 </dev/null && cfg_had=1
server_pid=""
cleanup() {
  trap - EXIT INT TERM HUP
  adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null >/dev/null 2>&1
  if [ "$cfg_had" = 1 ]; then
    adb -s "$serial" push "$cfg_orig" "$CFG_PATH" >/dev/null 2>&1 </dev/null
  else
    adb -s "$serial" shell rm -f "$CFG_PATH" </dev/null >/dev/null 2>&1
  fi
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

if [ -n "${PICO_SERVER_CMD:-}" ]; then
  nohup bash -c "exec $PICO_SERVER_CMD" > "$OUT/server.log" 2>&1 </dev/null &
  server_pid=$!
  sleep 6
fi

fail=0
for spec in "$@"; do
  name="${spec%%=*}"; rest="${spec#*=}"
  echo "== $name: $rest"
  # shellcheck disable=SC2086
  "$HERE/pico_stand.sh" $rest || { echo "   пресет не записан — вариант пропущен"; fail=1; continue; }
  adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null
  sleep 1
  adb -s "$serial" logcat -c </dev/null
  ready=$(pico_ready) || { echo "   СТОП: очки не готовы — $ready"; fail=2; break; }
  started=$(pico_start) || {
    echo "   СТОП: игра не вышла на передний план — $started"
    fg=$(pico_fg); [ -z "$fg" ] || echo "   состояние: $fg"
    adb -s "$serial" exec-out screencap -p </dev/null > "$OUT/$name-blocked.png" 2>/dev/null || true
    fail=2; break
  }
  waited=0
  while [ "$waited" -lt "$WAIT_SEC" ]; do
    sleep 3; waited=$((waited + 3))
    adb -s "$serial" logcat -d -s godot </dev/null | grep -aq "\] ИТОГ" && break
  done
  echo "   питание: $(adb -s "$serial" shell dumpsys power </dev/null | grep -a -m1 mWakefulness | tr -d '\r ') ожидание ${waited} с"
  adb -s "$serial" logcat -d -s godot </dev/null | grep -a "\[bench\] ИТОГ\|\[probe\]\|\[perf\]\|\[xr-diag\]" | sed -E 's/^.*I godot   : //' | tail -24 | tee "$OUT/$name.txt" | sed 's/^/   /'
  [ "$(wc -l < "$OUT/$name.txt")" -gt 0 ] || { echo "   нет строк итога (кадры не рисуются: очки спят или игра на паузе)"; fail=1; }
  adb -s "$serial" exec-out run-as "$PACKAGE" cat files/xr_diag_view.png </dev/null > "$OUT/$name.png" 2>/dev/null || true
  [ -s "$OUT/$name.png" ] && head -c 4 "$OUT/$name.png" | grep -q PNG || adb -s "$serial" pull "/sdcard/Android/data/$PACKAGE/files/xr_diag_view.png" "$OUT/$name.png" >/dev/null 2>&1 </dev/null || true
  [ -s "$OUT/$name.png" ] && echo "   кадр: $OUT/$name.png" || { rm -f "$OUT/$name.png"; echo "   кадра нет (perf=diag не задан или PNG ещё не сохранён)"; }
done

echo "pico_series: готово, результаты — $OUT (код $fail)"
exit "$fail"

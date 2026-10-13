#!/usr/bin/env bash
# Серия замеров на очках подряд: на каждый вариант — конфиг (pico_stand.sh) → перезапуск игры → ожидание `[bench] ИТОГ` / `[probe] ИТОГ` →
# строки итога и PNG кадра вида (perf=diag, XrDiag) в каталог результатов. Запускать на devbox (adb), одну серию на очки.
#
#   pico_series.sh "<имя>=<пресет> [ключ=значение ...]" ...
#   пример: pico_series.sh "w1=bench veil_scale=0 bench=wedge" "w2=bench tile_glow=0 bench=wedge" "ctrl=bench bench=wedge"
#
# Окружение: PICO_SERIAL (устройство), OUT (каталог результатов, по умолчанию ~/pico-series/<время>), WAIT_SEC (ожидание итога на вариант, 150),
# PICO_SERVER_CMD (команда сервера мира для стенда; запускается один раз на серию и останавливается по её концу), PICO_READY_CMD (команда подготовки
# очков перед каждым вариантом: `pico_ready.sh` снимает известные системные окна кнопками, не меняющими настройки; код ≠ 0 — серия останавливается).
# Условия: очки на столе остаются бодрыми только пока их не гасит датчик — иначе игра стартует «на паузе» (итога не будет); если поверх всего
# висит системный диалог Pico (например «Слишком темно» — камеры не видят комнату), `am start` отвечает «kept for the user»:
# серия прерывается с сообщением, диалог закрывает человек. Этикет очков (CLAUDE.md, память pico-headset-testing-etiquette): серию запускать
# только когда на голове никого нет или по слову владельца «надеваю».
set -u

PACKAGE="com.megablok10.netrun"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HOME/netrun-env.sh" ] && . "$HOME/netrun-env.sh"
WAIT_SEC="${WAIT_SEC:-150}"
OUT="${OUT:-$HOME/pico-series/$(date +%m%d-%H%M)}"
mkdir -p "$OUT"

serial="${PICO_SERIAL:-}"
if [ -z "$serial" ]; then
  serial=$(adb devices | awk '$2=="device"{print $1}')
  [ "$(echo "$serial" | grep -c .)" = 1 ] || { echo "pico_series: нужно ровно одно устройство или PICO_SERIAL" >&2; exit 1; }
fi
export PICO_SERIAL="$serial"

[ "$#" -gt 0 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

server_pid=""
if [ -n "${PICO_SERVER_CMD:-}" ]; then
  nohup bash -c "exec $PICO_SERVER_CMD" > "$OUT/server.log" 2>&1 </dev/null &
  server_pid=$!
  sleep 6
fi
adb -s "$serial" shell svc power stayon true </dev/null

fail=0
for spec in "$@"; do
  name="${spec%%=*}"; rest="${spec#*=}"
  echo "== $name: $rest"
  # shellcheck disable=SC2086
  "$HERE/pico_stand.sh" $rest || { echo "   пресет не записан — вариант пропущен"; fail=1; continue; }
  adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null
  sleep 1
  adb -s "$serial" logcat -c </dev/null
  adb -s "$serial" shell input keyevent KEYCODE_WAKEUP </dev/null
  if [ -n "${PICO_READY_CMD:-}" ]; then   # снять известные системные окна безопасными кнопками (pico_ready.sh); незнакомое — стоп
    ready=$($PICO_READY_CMD 2>&1) || { echo "   СТОП: $ready"; fail=2; break; }
  fi
  started=$(adb -s "$serial" shell am start -n "$PACKAGE/com.godot.game.GodotAppLauncher" </dev/null 2>&1)
  if [ -n "${PICO_READY_CMD:-}" ] && echo "$started" | grep -q "kept for the user"; then   # окно появилось при запуске: снять и стартовать ещё раз
    ready=$($PICO_READY_CMD 2>&1) || { echo "   СТОП: $ready"; fail=2; break; }
    started=$(adb -s "$serial" shell am start -n "$PACKAGE/com.godot.game.GodotAppLauncher" </dev/null 2>&1)
  fi
  if echo "$started" | grep -q "kept for the user"; then
    echo "   СТОП: игра не стартует — поверх висит системный диалог Pico («Слишком темно» и т. п.); закройте его на очках и повторите"
    adb -s "$serial" exec-out screencap -p </dev/null > "$OUT/$name-blocked.png" 2>/dev/null || true
    fail=2; break
  fi
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

adb -s "$serial" shell am force-stop "$PACKAGE" </dev/null
[ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
echo "pico_series: готово, результаты — $OUT (код $fail)"
exit "$fail"

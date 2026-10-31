#!/usr/bin/env bash
# Стенд очков: пресет рендера в netrun.cfg на устройстве без переустановки APK (секции [render] и [assets]; остальные секции файла не трогаются).
# Умолчания приняты и живут в коде (RenderConfig, AssetMaterials.KNOBS): пресет «base» — чистый вид без единой строки, остальное — различия от него.
#
#   pico_stand.sh <пресет> [ключ=значение ...]    записать пресет; ключи после него перекрывают
#   pico_stand.sh --show                          показать netrun.cfg с очков
#   pico_stand.sh --reset                         убрать [render] и [assets] (чистые умолчания)
#
# Пресеты (замеры bench — в docs/netrun-bench.md, итоги 08–12.10 — в docs/netrun-refactor-plan.md):
#   base            чистые умолчания: msaa 2, foveation 0, layers behind, вид V10, облако (Б) на всех модулях (с 14.10 — умолчание кода;
#                   `volumetric=off` — сплошные модели, для сравнения)
#   bench           perf=on, bench=entry: 5 с прогрева + 3 окна по 10 с, строка `[bench] ИТОГ`
#   cloud-props     bench + cloud=1: облако на колоннах/хранилище/выходе (C3a; пол, потолок и дальние остаются solid_dark).
#                   После B3 `cloud=1` — умолчание AssetMaterials, так что пресет ≡ bench (оставлен алиасом для старых команд)
#   cloud-vol       bench + volumetric=vault,portal: хранилище и порталы облаком частиц (VolumeRegistry, точки с поверхности модели)
#   cloud-vol-budget cloud-vol + volume_budget_ms=10.5: регулятор плотности облаков по GPU-времени кадра (VolumeBudget)
#   cloud-all       bench + volumetric=vault,portal,shard,exit,ice: все объёмные модули (рамка выхода, голограмма ICE, шарды)
#   cloud-all-imp   cloud-all + volume_impostor_m=8: дальше 8 м облака — запечённые билборды (VolumeImpostor)
#   probe-sweep     perf=on, probe=sweep: серия синтетической нагрузки (база + 14 вариантов, ≈3,5 мин) → таблица `[probe] ИТОГ`
#   probe-pts       perf=on, probe=sweep_pts: V11, способы рисовать облако точек (discard/a2c/points/points_a2c/gpup × 100к/300к/1М, px=4;
#                   база + 15 вариантов, ≈3,5 мин) → `[probe] ИТОГ`
#   probe-pts-one   perf=on bench=entry + свой вариант: pico_stand.sh probe-pts-one probe=quads=300000,px=4,mode=points → строка `[bench] ИТОГ`
#
# Ключи: имена из RenderConfig.KEYS (msaa layers foveation perf volumetric bench probe volume_budget_ms volume_impostor_m warmup) пишутся в [render], остальные — в [assets]
# (AssetMaterials.KNOBS; неизвестная ручка игра пропускает с предупреждением). Пример:
#   pico_stand.sh cloud-props msaa=4 dust_density=0.55 perf=diag bench=wedge
# Читается при СТАРТЕ игры: после смены — перезапуск (pico_series.sh делает это сам). Устройство — PICO_SERIAL или единственное подключённое.
set -e

PACKAGE="com.megablok10.netrun"
CFG_PATH="/sdcard/Android/data/$PACKAGE/files/netrun.cfg"
RENDER_KEYS=" msaa layers far_cull_m foveation perf volumetric bench probe volume_budget_ms volume_impostor_m warmup "

[ -f "$HOME/netrun-env.sh" ] && . "$HOME/netrun-env.sh"
. "$(cd "$(dirname "$0")" && pwd)/box_guard.sh"

serial="${PICO_SERIAL:-}"
if [ -z "$serial" ]; then
  serial=$(adb devices | awk '$2=="device"{print $1}')
  if [ "$(echo "$serial" | grep -c .)" != 1 ]; then
    echo "pico_stand: нужно ровно одно устройство или PICO_SERIAL (сейчас: $(echo "$serial" | tr '\n' ' '))" >&2
    exit 1
  fi
fi

tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.new"' EXIT
adb -s "$serial" pull "$CFG_PATH" "$tmp" >/dev/null 2>&1 </dev/null || : > "$tmp"

case "${1:-}" in
  --show) cat "$tmp"; exit 0 ;;
  "")     sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

# Запись конфига — действие над очками: чужая бронь pico (devbox) — отказ «кто и до когда», чужой прогон не трогаем.
box_check pico || exit 1

# Без секций [render] и [assets]; остальное (адрес, токен, [net]) остаётся как было.
awk '/^\[render\]/{skip=1;next} /^\[assets\]/{skip=1;next} /^\[/{skip=0} !skip' "$tmp" > "$tmp.new"

if [ "$1" != "--reset" ]; then
  preset="$1"; shift
  case "$preset" in
    base)           set -- "$@" ;;
    bench)          set -- perf=on bench=entry "$@" ;;
    cloud-props)    set -- perf=on bench=entry cloud=1 "$@" ;;
    cloud-vol)      set -- perf=on bench=entry volumetric=vault,portal "$@" ;;
    cloud-vol-budget) set -- perf=on bench=entry volumetric=vault,portal volume_budget_ms=10.5 "$@" ;;
    cloud-all)      set -- perf=on bench=entry volumetric=vault,portal,shard,exit,ice "$@" ;;
    cloud-all-imp)  set -- perf=on bench=entry volumetric=vault,portal,shard,exit,ice volume_impostor_m=8 "$@" ;;
    probe-sweep)    set -- perf=on probe=sweep "$@" ;;
    probe-pts)      set -- perf=on probe=sweep_pts "$@" ;;
    probe-pts-one)  set -- perf=on bench=entry "$@" ;;
    *) echo "pico_stand: неизвестный пресет «$preset» (есть: base bench cloud-props cloud-vol cloud-vol-budget cloud-all cloud-all-imp probe-sweep probe-pts probe-pts-one)" >&2; exit 2 ;;
  esac
  # Последнее значение ключа выигрывает: пресет, затем ключи с командной строки.
  render=""; assets=""
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$kv" in *=*) ;; *) echo "pico_stand: «$kv» — нужен вид ключ=значение" >&2; exit 2 ;; esac
    case "$RENDER_KEYS" in
      *" $k "*) render=$(printf '%s\n' "$render" | grep -v "^$k = " || true); render="$render"$'\n'"$k = \"$v\"" ;;
      *)        assets=$(printf '%s\n' "$assets" | grep -v "^$k = " || true); assets="$assets"$'\n'"$k = $v" ;;
    esac
  done
  # Числа в [render] пишем без кавычек (msaa, foveation), строки — в кавычках.
  render=$(printf '%s\n' "$render" | sed -E 's/^(msaa|foveation) = "([0-9]+)"$/\1 = \2/' | grep . || true)
  assets=$(printf '%s\n' "$assets" | grep . || true)
  [ -n "$render" ] && printf '\n[render]\n%s\n' "$render" >> "$tmp.new"
  [ -n "$assets" ] && printf '\n[assets]\n%s\n' "$assets" >> "$tmp.new"
  echo "pico_stand: пресет $preset → [render]: $(printf '%s' "$render" | tr '\n' ';') [assets]: $(printf '%s' "$assets" | tr '\n' ';')"
else
  echo "pico_stand: [render] и [assets] убраны — чистые умолчания"
fi

adb -s "$serial" push "$tmp.new" "$CFG_PATH" >/dev/null </dev/null
echo "pico_stand: netrun.cfg записан на $serial (читается при старте игры)"

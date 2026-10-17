#!/usr/bin/env bash
# Сборка ОДНОГО exe для Windows (x86_64, pck внутри, режим SOLO) — плоская одиночная игра для тестеров (docs/netrun-flat-windows.md).
#   netrun/tools/export_flat_win.sh            собрать build/netrun-solo.exe и build/netrun-solo.txt (номер сборки)
#   netrun/tools/export_flat_win.sh --smoke    то же + дымовой прогон ПРОЕКТА (не exe: Windows-exe на Linux без Wine не запустить)
# Запускать на devbox из синхронизированной копии (netrun/tools/dev.sh sync) или в CI (godot и шаблоны экспорта уже стоят).
# Печатает вердикт: `EXPORT ok размер=… сборка=… путь=…`, код выхода 0/1; полный журнал — $BUILD_LOG (по умолчанию в каталоге сборки).
#
# Почему из ВРЕМЕННОЙ копии: для Windows нужен рендерер gl_compatibility (в репозитории — mobile, для Pico), а подмена строки в самом
# project.godot сломала бы очки. Копия получает: рендерер, сжатие текстур S3TC/BPTC (без него экспорт отказывает для настольных платформ),
# номер сборки в shared/build_info.gd. Исходный каталог не меняется.
# Переменные: GODOT, BUILD_NUMBER (иначе <ммдд>-<короткий sha>), SOLO_WORK (каталог копии, по умолчанию во временном).
set -uo pipefail

NETRUN=$(cd "$(dirname "$0")/.." && pwd)
SMOKE=0
[[ "${1:-}" == "--smoke" ]] && SMOKE=1
PRESET="Flat Windows (solo)"
MIN_SIZE=$((20 * 1024 * 1024))

# Неинтерактивный ssh не читает профиль: godot лежит в ~/.local/bin, путь задаёт ~/netrun-env.sh (docs/netrun-devbox.md).
command -v "${GODOT:-godot}" >/dev/null 2>&1 || [[ ! -f "$HOME/netrun-env.sh" ]] || . "$HOME/netrun-env.sh"
GODOT="${GODOT:-godot}"

fail() { echo "EXPORT fail: $*"; exit 1; }
command -v "$GODOT" >/dev/null 2>&1 || fail "нет godot в PATH (GODOT=...)"

# Номер сборки: дата + короткий sha. На devbox каталог — копия без .git: sha кладёт туда dev.sh (.dev-sha рядом с netrun/).
if [[ -z "${BUILD_NUMBER:-}" ]]; then
	sha=$(git -C "$NETRUN" rev-parse --short HEAD 2>/dev/null || cat "$NETRUN/../.dev-sha" 2>/dev/null || echo nosha)
	BUILD_NUMBER="$(date +%m%d)-$sha"
fi
[[ "$BUILD_NUMBER" =~ ^[a-z0-9-]+$ ]] || fail "странный номер сборки «$BUILD_NUMBER» (нужно ^[a-z0-9-]+$)"

WORK=${SOLO_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/netrun-solo-src.XXXXXX")}
mkdir -p "$WORK" || fail "каталог копии $WORK"
LOG=${BUILD_LOG:-$WORK/export.log}
: > "$LOG"

# Копия проекта: без сборок, кэша импорта, отчётов и плагина редактора Godot AI.
rsync -a --delete --exclude build --exclude .godot --exclude reports --exclude addons/godot_ai "$NETRUN/" "$WORK/" || fail "rsync в $WORK"

# Подмена в копии (через временный файл: sed -i у GNU и BSD разный).
grep -q '^renderer/rendering_method="mobile"$' "$WORK/project.godot" || fail "в project.godot нет renderer/rendering_method=\"mobile\" — скрипт устарел"
grep -q '^const BUILD := "dev"$' "$WORK/shared/build_info.gd" || fail "в shared/build_info.gd нет const BUILD := \"dev\" — скрипт устарел"
sed -e 's|^renderer/rendering_method="mobile"$|renderer/rendering_method="gl_compatibility"|' \
	-e 's|^textures/vram_compression/import_etc2_astc=true$|&\ntextures/vram_compression/import_s3tc_bptc=true|' \
	"$WORK/project.godot" > "$WORK/project.godot.new" && mv "$WORK/project.godot.new" "$WORK/project.godot" || fail "подмена project.godot"
sed -e "s|^const BUILD := \"dev\"\$|const BUILD := \"$BUILD_NUMBER\"|" \
	"$WORK/shared/build_info.gd" > "$WORK/shared/build_info.gd.new" && mv "$WORK/shared/build_info.gd.new" "$WORK/shared/build_info.gd" || fail "подмена build_info.gd"
grep -q "\"$BUILD_NUMBER\"" "$WORK/shared/build_info.gd" || fail "номер сборки не попал в build_info.gd"

mkdir -p "$WORK/build"
"$GODOT" --headless --path "$WORK" --import >> "$LOG" 2>&1 || true
"$GODOT" --headless --path "$WORK" --export-release "$PRESET" build/netrun-solo.exe >> "$LOG" 2>&1
rc=$?
EXE="$WORK/build/netrun-solo.exe"
[[ -s "$EXE" ]] || fail "exe не создан (код $rc), журнал: $LOG"
SIZE=$(wc -c < "$EXE" | tr -d ' ')
[[ "$SIZE" -ge "$MIN_SIZE" ]] || fail "exe слишком мал ($SIZE байт), журнал: $LOG"
# Ошибки экспорта Godot печатает, но код возврата не всегда ненулевой.
if grep -aq "^ERROR:.*export\|ERROR: Failed to export\|Cannot export project" "$LOG"; then fail "godot сообщил об ошибке экспорта, журнал: $LOG"; fi

mkdir -p "$NETRUN/build" || fail "mkdir $NETRUN/build"
cp "$EXE" "$NETRUN/build/netrun-solo.exe" || fail "копирование exe"
echo "$BUILD_NUMBER" > "$NETRUN/build/netrun-solo.txt"

if [[ "$SMOKE" == 1 ]]; then
	# Дымовой прогон проекта-копии (тот же код и данные, что внутри exe): сервер и клиент поднялись в одном процессе. Выход по --exit-after= в SOLO
	# есть (SoloStub), поэтому ждём чистый код 0; 124 (дожил до предела timeout) — сбой: процесс завис или таймер не сработал.
	SMOKE_LOG="$WORK/smoke.log"
	timeout 30 "$GODOT" --headless --path "$WORK" -- --solo --exit-after=8 > "$SMOKE_LOG" 2>&1
	src=$?
	grep -aq '\[netrun-solo\]' "$SMOKE_LOG" || fail "дымовой прогон: нет строки [netrun-solo], журнал: $SMOKE_LOG"
	if [[ "$src" != 0 ]]; then fail "дымовой прогон: код выхода $src, журнал: $SMOKE_LOG"; fi
	if grep -aq "SCRIPT ERROR\|Parse Error" "$SMOKE_LOG"; then fail "дымовой прогон: ошибки скриптов, журнал: $SMOKE_LOG"; fi
	echo "SMOKE ok код=$src строка=[netrun-solo]"
fi

echo "EXPORT ok размер=$(( SIZE / 1024 / 1024 )) МБ сборка=$BUILD_NUMBER путь=$NETRUN/build/netrun-solo.exe"

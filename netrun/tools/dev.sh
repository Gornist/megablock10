#!/usr/bin/env bash
# Цикл «правка → синхронизация → тесты → кадры» для Godot-части (netrun/) одной командой с Mac. Печатает КОМПАКТНЫЙ итог, полные журналы остаются на devbox.
#
#   netrun/tools/dev.sh sync                      залить netrun/ на devbox (rsync --delete, без reports/.godot)
#   netrun/tools/dev.sh test [файл_test ...]      sync + тесты; по умолчанию — затронутые изменёнными файлами (git diff от origin/main, включая неотправленное)
#   netrun/tools/dev.sh test --all                весь набор (5–10 мин: запускать в фоне, Bash run_in_background)
#   netrun/tools/dev.sh shot res://assets/X.tscn [арги сцены]   sync + превью-сцена на дисплее devbox; кадры склеиваются в ОДНУ сетку, на Mac приходит только она
#   netrun/tools/dev.sh all [res://сцена ...]     sync + тесты по изменённым [+ shot]
#
# Правила (сбои, на которых это выверено):
#  - Рабочий каталог на devbox выводится из ВЕТКИ (wt-<ветка без agent/>), а не из имени папки; в нём файл .dev-branch со своей веткой — чужую не затираем.
#    Явно другой каталог — DEV_REMOTE=wt-имя (метка обновится). Каталоги — копии без .git: состояние — только то, что залил sync.
#  - rsync всегда с --delete: оставшийся от другой ветки *_test.gd без нужного кода вешает gdUnit в отладчике (Parser Error → Debugger Break).
#  - Один gdUnit и один дисплей на devbox: flock /tmp/gdunit.lock и /tmp/display.lock, timeout на каждый запуск.
#  - Картинки в контекст агента не лить: shot отдаёт одну сетку ≤ 1024 px шириной (Pillow на devbox). Деталь мелкая — DEV_CROP=левый,верх,ширина,высота
#    (доли кадра, например DEV_CROP=0.3,0.15,0.4,0.7) режет каждый кадр перед сборкой сетки.
set -uo pipefail

HOST=${DEV_HOST:-devbox}
ROOT=$(git rev-parse --show-toplevel)
BRANCH=$(git -C "$ROOT" branch --show-current)
SLUG=${BRANCH#agent/}
SLUG=${SLUG//\//-}
REMOTE=${DEV_REMOTE:-wt-$SLUG}
TEST_TIMEOUT=${DEV_TEST_TIMEOUT:-900}
SHOT_DIR=/tmp/dev-shots/$REMOTE

die() { echo "dev.sh: $*" >&2; exit 2; }
[[ -n "$BRANCH" ]] || die "нет ветки (detached HEAD)"
[[ "$SLUG" =~ ^[A-Za-z0-9._-]+$ ]] || die "странное имя ветки: $BRANCH"
[[ "$REMOTE" =~ ^[A-Za-z0-9._-]+$ ]] || die "странное имя каталога: $REMOTE"

cmd_sync() {
  echo "dev.sh: $ROOT@$BRANCH -> $HOST:$REMOTE"
  local mark
  mark=$(ssh "$HOST" "cat ~/$REMOTE/.dev-branch 2>/dev/null || true")
  if [[ -n "$mark" && "$mark" != "$BRANCH" && -z "${DEV_REMOTE:-}" ]]; then
    die "в $REMOTE лежит ветка '$mark', а у вас '$BRANCH'; задайте DEV_REMOTE=... явно, если так и надо"
  fi
  ssh "$HOST" "mkdir -p ~/$REMOTE/netrun" || die "ssh"
  rsync -a --delete --exclude reports --exclude .godot "$ROOT/netrun/" "$HOST:$REMOTE/netrun/" || die "rsync"
  ssh "$HOST" "echo '$BRANCH' > ~/$REMOTE/.dev-branch; echo '$(git -C "$ROOT" rev-parse --short HEAD)' > ~/$REMOTE/.dev-sha"
  echo "dev.sh: sync ok ($(git -C "$ROOT" rev-parse --short HEAD) + рабочие правки)"
}

# Файлы тестов, затронутые изменениями: сам изменённый *_test.gd; для кода — tests/<имя>_test.gd и любой тест, упоминающий class_name или путь файла.
# (Совместимо с bash 3.2 на Mac: без mapfile и ассоциативных массивов.)
changed_tests() {
  local base files f cn t out=""
  base=$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)
  files=$( { git -C "$ROOT" diff --name-only "$base"; git -C "$ROOT" ls-files --others --exclude-standard; } | grep '^netrun/.*\.gd$' | sort -u)
  for f in $files; do
    [[ -f "$ROOT/$f" ]] || continue
    if [[ "$f" == netrun/tests/*_test.gd ]]; then out="$out$(basename "$f" .gd)"$'\n'; continue; fi
    t=netrun/tests/$(basename "$f" .gd)_test.gd
    [[ -f "$ROOT/$t" ]] && out="$out$(basename "$t" .gd)"$'\n'
    cn=$(grep -m1 '^class_name ' "$ROOT/$f" | awk '{print $2}')
    if [[ -n "$cn" ]]; then
      for t in $(grep -lw "$cn" "$ROOT"/netrun/tests/*_test.gd 2>/dev/null); do out="$out$(basename "$t" .gd)"$'\n'; done
    fi
    for t in $(grep -l "res://${f#netrun/}" "$ROOT"/netrun/tests/*_test.gd 2>/dev/null); do out="$out$(basename "$t" .gd)"$'\n'; done
  done
  printf '%s' "$out" | sed '/^$/d' | sort -u
}

# Удалённая часть: каждый набор под замком и таймаутом, вывод сворачивается в одну строку + причины падения. Код выхода 0 — зелёно.
remote_test_script() {
  cat <<REMOTE_EOF
set -u
cd ~/$REMOTE || exit 3
mkdir -p ~/dev-logs
ts=\$(date +%H%M%S)
rc_all=0
for t in "\$@"; do
  target="res://tests/\$t.gd"; [[ "\$t" == "__ALL__" ]] && target="res://tests"
  log=~/dev-logs/$REMOTE-\$t-\$ts.log
  timeout $TEST_TIMEOUT flock /tmp/gdunit.lock netrun/tools/gdunit.sh "\$target" > "\$log" 2>&1
  rc=\$?
  plain=\$(sed "s/\x1b\[[0-9;]*m//g" "\$log")
  sumline=\$(grep -a "Overall Summary" <<<"\$plain" | tail -1 | sed "s/Overall Summary: *//")
  if [[ \$rc -eq 124 ]]; then echo "\$t: TIMEOUT ($TEST_TIMEOUT с) log=\$log"; rc_all=1; continue; fi
  if grep -aq "Debugger Break\|Parser Error" <<<"\$plain"; then
    echo "\$t: ERROR (ошибка разбора скрипта или отладчик) log=\$log"; grep -a -m3 "Parser Error\|Debugger Break" <<<"\$plain" | sed "s/^/    /"; rc_all=1; continue
  fi
  if [[ -z "\$sumline" ]]; then
    echo "\$t: НЕТ ИТОГА (rc=\$rc) log=\$log"; tail -3 <<<"\$plain" | sed "s/^/    /"
    grep -aq "No test cases found" <<<"\$plain" && echo "    набора \$t нет в netrun/tests (имя — без .gd, например daemon_vault_test)"
    rc_all=1; continue
  fi
  fails=\$(grep -a " FAILED" <<<"\$plain" | sed -E "s/.*tests\/([a-z_0-9]+)\.gd *> *([A-Za-z_0-9]+).*/\1::\2/" | sort -u)
  if [[ \$rc -eq 0 && -z "\$fails" ]]; then echo "\$t: ok  \$sumline"; else
    echo "\$t: FAIL \$sumline log=\$log"; rc_all=1
    for f in \$fails; do
      echo "    \$f"
      n=\${f##*::}
      grep -a -A14 "\$n.*FAILED" <<<"\$plain" | sed -n "/Expecting\|Parser\|Invalid\|SCRIPT ERROR/,+4p" | head -5 | sed "s/^ */      /"
    done
  fi
done
exit \$rc_all
REMOTE_EOF
}

cmd_test() {
  local names=("$@")
  if [[ ${#names[@]} -eq 0 ]]; then
    names=()
    local line
    while IFS= read -r line; do [[ -n "$line" ]] && names+=("$line"); done < <(changed_tests)
    if [[ ${#names[@]} -eq 0 ]]; then echo "dev.sh: изменённый код не затрагивает тестов (проверьте вручную: dev.sh test имя_test)"; return 0; fi
    if [[ ${#names[@]} -gt 12 ]]; then echo "dev.sh: затронуто ${#names[@]} наборов — используйте dev.sh test --all в фоне"; return 0; fi
    echo "dev.sh: тесты по изменённым файлам: ${names[*]}"
  elif [[ "${names[0]}" == "--all" ]]; then
    names=("__ALL__")
  else
    # имя можно дать путём или с суффиксом .gd (daemon_vault_test.gd, netrun/tests/x_test.gd): без этого gdUnit молча находил 0 тестов
    local i n
    for i in "${!names[@]}"; do n=${names[$i]}; n=${n##*/}; names[$i]=${n%.gd}; done
  fi
  remote_test_script | ssh "$HOST" bash -s -- "${names[@]}"
}

remote_shot_script() {
  local scene=$1; shift
  cat <<REMOTE_EOF
set -u
cd ~/$REMOTE || exit 3
export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-0
rm -rf $SHOT_DIR && mkdir -p $SHOT_DIR
# rsync --delete стирает *.import, которых нет в git (у новых .glb их не бывает до первого открытия редактора), и без импорта сцена не находит модели:
# «No loader found for resource» и пустой кадр. Импорт — как в gdunit.sh; кэш .godot жив, поэтому повторный проход короткий.
# Скрипт приходит на stdin (`ssh bash -s`): godot читает stdin и съедает остаток скрипта (после него молча нет сетки) — гасим его </dev/null.
timeout 300 ~/.local/bin/godot --headless --path netrun --import > /dev/null 2>&1 </dev/null || true
timeout 180 flock /tmp/display.lock ~/.local/bin/godot --display-driver wayland --path netrun --resolution 1280x720 $scene -- --out=$SHOT_DIR $* > $SHOT_DIR/run.log 2>&1 </dev/null
grep -aE "ERROR|SCRIPT|Parse" $SHOT_DIR/run.log | head -5
python3 - <<'PY'
import glob, os
from PIL import Image
files = [f for f in sorted(glob.glob("$SHOT_DIR/*.png")) if not f.endswith("sheet.png")]
if not files:
    print("кадров нет, см. $SHOT_DIR/run.log")
    raise SystemExit
cell = 512
crop = [float(x) for x in "${DEV_CROP:-}".split(",") if x.strip()]
tiles = []
for f in files:
    im = Image.open(f).convert("RGB")
    if len(crop) == 4:
        l, t, w, h = crop
        im = im.crop((int(l * im.width), int(t * im.height), int((l + w) * im.width), int((t + h) * im.height)))
    tiles.append(im.resize((cell, max(1, round(im.height * cell / im.width)))))
cols = 2 if len(tiles) > 1 else 1
rows = (len(tiles) + cols - 1) // cols
th = max(t.height for t in tiles)
sheet = Image.new("RGB", (cols * cell, rows * th), (0, 0, 0))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * cell, (i // cols) * th))
sheet.save("$SHOT_DIR/sheet.png")
print("сетка %dx%d px, кадров %d (слева направо, сверху вниз):" % (sheet.width, sheet.height, len(tiles)))
print("  " + ", ".join(os.path.basename(f)[:-4] for f in files))
PY
REMOTE_EOF
}

cmd_shot() {
  local scene=${1:-}
  [[ "$scene" == res://* ]] || die "shot: нужна сцена res://… (например res://assets/preview_avatars.tscn)"
  shift
  remote_shot_script "$scene" "$@" | ssh "$HOST" bash -s
  mkdir -p "$SHOT_DIR"
  if scp -q "$HOST:$SHOT_DIR/sheet.png" "$SHOT_DIR/sheet.png" 2>/dev/null; then
    echo "dev.sh: сетка на Mac: $SHOT_DIR/sheet.png (отдельные кадры — на devbox: $SHOT_DIR)"
  fi
}

case "${1:-}" in
  sync) cmd_sync ;;
  test) shift; cmd_sync && cmd_test "$@" ;;
  shot) shift; cmd_sync && cmd_shot "$@" ;;
  all) shift; cmd_sync && cmd_test; rc=$?; if [[ $# -gt 0 ]]; then cmd_shot "$@"; fi; exit $rc ;;
  *) sed -n 2,12p "$0"; exit 1 ;;
esac

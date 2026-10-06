#!/usr/bin/env bash
# Конвейер ассетов «Сети»: Mac → devbox (Blender → .glb → Godot) → Mac. Запускать с Mac из любого каталога.
#   pipeline.sh build            — собрать ВСЕ ассеты из src/*.py на devbox (PYTHONHASHSEED=0), проверить, забрать .glb и отчёты, пересобрать MANIFEST.md;
#       в конце src/head_points.py: без HeadLowPolygon.stl печатает «пропуск» (код 0), HEAD_STL=путь — перегенерирует netrun/client/head_points.gd
#   pipeline.sh shots [каталог] [флаги сцены] [--grid] — снять кадры комнаты из Godot (по умолчанию /tmp/assets-shots); флаги: --only=a,b --lattice=0.05 --field --crowd --walls (вернуть стены комнаты, по умолчанию их нет) --portal (вернуть портал у западной стены, по умолчанию нет) --noedge (убрать кромку комнаты env/room_edge_8, по умолчанию она есть) --nomoat (убрать ров env/room_moat_8 вокруг плиты-пола, по умолчанию он есть) --floor1 (ЭКСПЕРИМЕНТ: пол комнаты одной плитой env/floor_slab_8 вместо 16 модулей) --floor1glass (ЭКСПЕРИМЕНТ: то же, но плита стеклянная, полупрозрачная env/floor_glass_8) --floorv=N (ЭКСПЕРИМЕНТ: один из четырёх вариантов пола env/floor_v<N>_8, N=1…4: пыль, террасы, решётка, полосы; не сочетается с --floor1*)
#       --grid — самому pipeline.sh (в сцену не уходит): после съёмки склеить кадры на devbox в ОДНУ сетку ≤ 1024 px по ширине с подписями
#                имён кадров и забрать на Mac один PNG: <каталог>/grid.png (отдельные кадры лежат там же)
#   pipeline.sh movie [файл.mp4] [флаги сцены] — записать видео комнаты (7 с) и сконвертировать (нужен ffmpeg на Mac); флаги: --walk --static --cam=…
#   pipeline.sh demo [файл.mp4] — длинный проход по комнате (34 с, 1920×1080): вход → хранилище → портал → ICE → вверх
#   pipeline.sh fps              — замер времени кадра GPU/CPU и числа вызовов отрисовки на трёх ракурсах
#   pipeline.sh stats <кадр|каталог> ... [--ref <референс.png>] — числовые метрики кадров (яркость, доли чёрного/бирюзы/синего/красного, горизонт, потолок/пол)
#       таблицей на devbox (tools/framestats.py): сравнение с референсом цифрами, без картинок в контексте
# Требует: devbox доступен (Tailscale), на нём Blender (~/.local/bin/blender) и Godot (~/.local/bin/godot), графический сеанс nick.
# Стенд просмотра — минимальный проект Godot ~/assets-gd на devbox (создаётся сам); это не проект netrun/.
# Блокировки на devbox. build/shots/movie/demo/fps берут /tmp/assets-pipeline.lock на ВСЁ время команды (две параллельные сборки ломали
# ~/assets-work и ~/assets-gd): вторая ждёт (до 30 мин) и печатает «pipeline.sh: жду другую сборку…». Блокировку держит отдельный
# ssh-сеанс, он умирает вместе с этим скриптом (даже по Ctrl-C) и никаким фоновым процессом не наследуется. Запуск Godot с дисплеем
# дополнительно берёт /tmp/display.lock — тот же, что netrun/tools/dev.sh (кадры dev.sh и pipeline.sh не пересекаются на экране).
# build НЕ трогает отслеживаемые файлы вне пересобранных ассетов: *.glb.import (их делает Godot, на devbox их нет) rsync не удаляет;
# Python запускается с PYTHONHASHSEED=0, поэтому повторная сборка даёт те же .glb побайтно. Тяжёлого параллельно не запускать (skill devbox).
set -euo pipefail
cd "$(dirname "$0")/.."   # netrun/assets
HOST=${DEVBOX:-nick@100.80.115.46}   # имя devbox с Mac резолвится неверно — только IP
GD_ENV='U=$(id -u); export XDG_RUNTIME_DIR=/run/user/$U WAYLAND_DISPLAY=wayland-0'
LOCK_FILE=/tmp/assets-pipeline.lock
DISPLAY_LOCK='flock -w 900 /tmp/display.lock'

LOCKDIR=""; LOCKPID=""
release_lock() {
  exec 7>&- 2>/dev/null || true
  [ -n "$LOCKPID" ] && kill "$LOCKPID" 2>/dev/null || true
  [ -n "$LOCKDIR" ] && rm -rf "$LOCKDIR"
}

acquire_lock() {  # держит flock на devbox, пока жив отдельный ssh-сеанс (cat читает его stdin; закрыли fifo или убили ssh — блокировка снята)
  LOCKDIR=$(mktemp -d); mkfifo "$LOCKDIR/in"
  trap release_lock EXIT; trap 'exit 130' INT TERM
  exec 7<>"$LOCKDIR/in"
  ssh "$HOST" "exec 9>$LOCK_FILE
flock -n 9 || { echo WAITING; flock -w 1800 9 || { echo TIMEOUT; exit 3; }; }
echo LOCKED; cat >/dev/null" <"$LOCKDIR/in" >"$LOCKDIR/out" 2>/dev/null 7>&- &
  LOCKPID=$!
  local i waited=0
  for i in $(seq 1 4000); do   # 0,5 с × 4000 ≈ 33 мин: чуть больше 1800 с ожидания на devbox
    if grep -q LOCKED "$LOCKDIR/out" 2>/dev/null; then return 0; fi
    if [ $waited -eq 0 ] && grep -q WAITING "$LOCKDIR/out" 2>/dev/null; then echo "pipeline.sh: жду другую сборку…"; waited=1; fi
    if grep -q TIMEOUT "$LOCKDIR/out" 2>/dev/null || ! kill -0 "$LOCKPID" 2>/dev/null; then break; fi
    sleep 0.5
  done
  echo "pipeline.sh: не получил блокировку $LOCK_FILE на devbox (занято дольше 30 мин или нет связи)"; exit 3
}

ensure_project() {  # минимальный проект просмотра + импорт ассетов в Godot
  ssh "$HOST" 'mkdir -p ~/assets-gd/assets ~/assets-work'
  rsync -a --delete --exclude 'models/MANIFEST.md' --exclude 'tools' --exclude 'src' ./ "$HOST:~/assets-gd/assets/"
  ssh "$HOST" 'cd ~/assets-gd
[ -f project.godot ] || printf "config_version=5\n\n[application]\nconfig/name=\"assets-preview\"\nrun/main_scene=\"res://preview.tscn\"\n\n[rendering]\nrenderer/rendering_method=\"mobile\"\n" > project.godot
[ -f preview.tscn ] || printf "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"res://assets/preview_capture.gd\" id=\"1\"]\n\n[node name=\"Preview\" type=\"Node3D\"]\nscript = ExtResource(\"1\")\n" > preview.tscn
~/.local/bin/godot --headless --path . --import 2>&1 | grep -iE "error" || true'
}

make_grid() {  # на devbox: все кадры каталога $1 → grid.png ≤ 1024 px по ширине, имя кадра в каждой ячейке
  ssh "$HOST" python3 - "$1" <<'PY'
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont
d = sys.argv[1]
files = [f for f in sorted(glob.glob(d + "/*.png")) if not f.endswith("grid.png")]
if not files:
    print("кадров нет, сетку не собрал")
    raise SystemExit
cols = 1 if len(files) == 1 else (2 if len(files) <= 6 else 3)
cell = 1024 // cols
try:
    font = ImageFont.load_default(size=14)
except TypeError:
    font = ImageFont.load_default()
tiles = []
for f in files:
    im = Image.open(f).convert("RGB")
    im = im.resize((cell, max(1, round(im.height * cell / im.width))))
    dr = ImageDraw.Draw(im)
    name = os.path.basename(f)[:-4]
    w = dr.textlength(name, font=font)
    dr.rectangle((0, 0, w + 8, 20), fill=(0, 0, 0))
    dr.text((4, 3), name, fill=(255, 255, 255), font=font)
    tiles.append(im)
rows = (len(tiles) + cols - 1) // cols
th = max(t.height for t in tiles)
sheet = Image.new("RGB", (cols * cell, rows * th), (0, 0, 0))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * cell, (i // cols) * th))
sheet.save(d + "/grid.png")
print("сетка %dx%d px, кадров %d (слева направо, сверху вниз): %s" % (sheet.width, sheet.height, len(tiles), ", ".join(os.path.basename(f)[:-4] for f in files)))
PY
}

cmd=${1:-help}
case "$cmd" in build|shots|movie|demo|fps) acquire_lock ;; esac

case "$cmd" in
  build)
    ssh "$HOST" 'mkdir -p ~/assets-work'
    rsync -a --delete src/ "$HOST:~/assets-work/src/"
    # head_points.py — не ассет Blender (читает внешний STL и пишет client/head_points.gd): из цикла исключён, запускается ниже на Mac.
    # Раньше его гнали под Blender, и в argv[1] попадал флаг «-b» → «FileNotFoundError: '-b'».
    ssh "$HOST" 'cd ~/assets-work && rm -rf out
export PYTHONHASHSEED=0
for s in $(ls src/*.py | grep -vE "lib.py|glbinfo.py|validate.py|_smoke.py|head_points.py"); do
  ~/.local/bin/blender -b --factory-startup -noaudio --python "$s" -- --out ~/assets-work/out 2>&1 | grep -E "EXPORT|Error|Traceback|File \"" || true
done
python3 src/validate.py --root out'
    # *.glb.import делает Godot, на devbox их нет: не удаляем (--exclude защищает и от --delete)
    rsync -a --delete --exclude MANIFEST.md --exclude '*.glb.import' "$HOST:~/assets-work/out/models/" models/
    rsync -a --delete "$HOST:~/assets-work/out/reports/" reports/
    python3 src/validate.py --manifest | tail -2
    # облако точек головы: без STL (его в репозитории нет) — одна строка и код 0; HEAD_STL=путь перегенерирует netrun/client/head_points.gd
    python3 src/head_points.py "${HEAD_STL:-HeadLowPolygon.stl}" ;;
  shots)
    shift; out=/tmp/assets-shots; extra=""; grid=0; first=1
    for a in "$@"; do
      case "$a" in
        --grid) grid=1 ;;
        --*) extra="$extra $a" ;;
        *) if [ $first -eq 1 ]; then out=$a; first=0; else extra="$extra $a"; fi ;;
      esac
    done
    ensure_project; rm -rf "$out"
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && rm -rf shots && timeout 150 $DISPLAY_LOCK ~/.local/bin/godot --display-driver wayland --path . --resolution 1280x720 -- --out=/home/nick/assets-gd/shots $extra 2>&1 | grep -E 'ERROR|SCRIPT|Parse|SHADER' || true"
    if [ $grid -eq 1 ]; then make_grid /home/nick/assets-gd/shots; fi
    scp -rq "$HOST:~/assets-gd/shots" "$out"
    if [ $grid -eq 1 ]; then echo "сетка: $out/grid.png (отдельные кадры — рядом)"; else echo "кадры: $out"; fi ;;
  movie)
    mp4=${2:-/tmp/assets-room.mp4}; extra=${*:3}; ensure_project
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && rm -f room.avi && timeout 240 $DISPLAY_LOCK ~/.local/bin/godot --display-driver wayland --path . --resolution 1280x720 --write-movie /home/nick/assets-gd/room.avi --fixed-fps 24 --quit-after 168 -- --movie $extra 2>&1 | grep -E 'ERROR|SCRIPT|Parse' || true"
    scp -q "$HOST:~/assets-gd/room.avi" /tmp/assets-room.avi
    ffmpeg -v error -y -i /tmp/assets-room.avi -c:v libx264 -pix_fmt yuv420p -crf 20 -an "$mp4"; echo "видео: $mp4" ;;
  demo)
    mp4=${2:-/tmp/assets-demo.mp4}; extra=${*:3}; ensure_project
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && rm -f demo.avi && timeout 420 $DISPLAY_LOCK ~/.local/bin/godot --display-driver wayland --path . --resolution 1920x1080 --write-movie /home/nick/assets-gd/demo.avi --fixed-fps 24 --quit-after 816 -- --demo $extra 2>&1 | grep -E 'ERROR|SCRIPT|Parse' | grep -v 'leaked\|still in use' || true"
    scp -q "$HOST:~/assets-gd/demo.avi" /tmp/assets-demo.avi
    ffmpeg -v error -y -i /tmp/assets-demo.avi -c:v libx264 -pix_fmt yuv420p -crf 20 -an "$mp4"; echo "демо: $mp4 (34 с, 24 к/с, 1920×1080)" ;;
  fps)
    ensure_project
    for cam in "-1.0,1.25,8.6,0.0,1.0,-2.5" "11.0,10.5,11.0,0.0,0.4,-0.5" "0.3,1.6,1.6,0.0,0.0,-0.4"; do
      echo "== камера $cam"
      ssh "$HOST" "$GD_ENV; cd ~/assets-gd && timeout 60 $DISPLAY_LOCK ~/.local/bin/godot --display-driver wayland --path . --resolution 1920x1080 -- --movie --static --fps ${FPS_EXTRA:-} --cam=$cam 2>&1 | grep -E 'GPU мс|вызовов' || true"
    done
    echo "== толпа: 9 аватаров в комнате (--crowd)"
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && timeout 60 $DISPLAY_LOCK ~/.local/bin/godot --display-driver wayland --path . --resolution 1920x1080 -- --movie --static --fps ${FPS_EXTRA:-} --crowd --cam=-1.0,1.25,8.6,0.0,1.0,-2.5 2>&1 | grep -E 'GPU мс|вызовов' || true"
    echo "ЭТО НЕ Pico 4: настольная видеокарта devbox, окно с вертикальной синхронизацией." ;;
  stats)  # числовые метрики кадров на devbox (там Pillow); без GPU, блокировка не нужна
    shift; [ $# -gt 0 ] || { echo "pipeline.sh stats <кадр.png|каталог> ... [--ref <референс.png>]" >&2; exit 2; }
    tmp=/tmp/assets-stats-$$; ssh "$HOST" "rm -rf $tmp; mkdir -p $tmp/in $tmp/ref"
    scp -q tools/framestats.py "$HOST:$tmp/framestats.py"
    n=0; refargs=""; inargs=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --ref) n=$((n + 1)); scp -q "$2" "$HOST:$tmp/ref/r$n-$(basename "$2")"; refargs="$refargs --ref $tmp/ref/r$n-$(basename "$2")"; shift 2 ;;
        *) if [ -d "$1" ]; then for f in "$1"/*.png; do case "$f" in */grid.png) ;; *) n=$((n + 1)); scp -q "$f" "$HOST:$tmp/in/$(printf '%02d' $n)-$(basename "$f")"; ;; esac; done
           else n=$((n + 1)); scp -q "$1" "$HOST:$tmp/in/$(printf '%02d' $n)-$(basename "$1")"; fi; shift ;;  # номер впереди: одинаковые имена из разных каталогов не затирают друг друга
      esac
    done
    ssh "$HOST" "python3 $tmp/framestats.py $refargs $tmp/in; rm -rf $tmp" ;;
  *) sed -n 2,8p "$0"; exit 2 ;;
esac

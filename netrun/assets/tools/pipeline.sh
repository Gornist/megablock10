#!/usr/bin/env bash
# Конвейер ассетов «Сети»: Mac → devbox (Blender → .glb → Godot) → Mac. Запускать с Mac из любого каталога.
#   pipeline.sh build            — собрать ВСЕ ассеты из src/*.py на devbox, проверить, забрать .glb и отчёты, пересобрать MANIFEST.md
#   pipeline.sh shots [каталог] [флаги сцены] — снять кадры комнаты из Godot (по умолчанию /tmp/assets-shots); флаги: --only=a,b --lattice=0.05 --field --crowd
#   pipeline.sh movie [файл.mp4] [флаги сцены] — записать видео комнаты (7 с) и сконвертировать (нужен ffmpeg на Mac); флаги: --walk --static --cam=…
#   pipeline.sh fps              — замер времени кадра GPU/CPU и числа вызовов отрисовки на трёх ракурсах
# Требует: devbox доступен (Tailscale), на нём Blender (~/.local/bin/blender) и Godot (~/.local/bin/godot), графический сеанс nick.
# Стенд просмотра — минимальный проект Godot ~/assets-gd на devbox (создаётся сам); это не проект netrun/. Тяжёлого параллельно
# не запускать: одна задача на машину (skill devbox).
set -euo pipefail
cd "$(dirname "$0")/.."   # netrun/assets
HOST=${DEVBOX:-nick@100.80.115.46}   # имя devbox с Mac резолвится неверно — только IP
GD_ENV='U=$(id -u); export XDG_RUNTIME_DIR=/run/user/$U WAYLAND_DISPLAY=wayland-0'

ensure_project() {  # минимальный проект просмотра + импорт ассетов в Godot
  ssh "$HOST" 'mkdir -p ~/assets-gd/assets ~/assets-work'
  rsync -a --delete --exclude 'models/MANIFEST.md' --exclude 'tools' --exclude 'src' ./ "$HOST:~/assets-gd/assets/"
  ssh "$HOST" 'cd ~/assets-gd
[ -f project.godot ] || printf "config_version=5\n\n[application]\nconfig/name=\"assets-preview\"\nrun/main_scene=\"res://preview.tscn\"\n\n[rendering]\nrenderer/rendering_method=\"mobile\"\n" > project.godot
[ -f preview.tscn ] || printf "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"res://assets/preview_capture.gd\" id=\"1\"]\n\n[node name=\"Preview\" type=\"Node3D\"]\nscript = ExtResource(\"1\")\n" > preview.tscn
~/.local/bin/godot --headless --path . --import 2>&1 | grep -iE "error" || true'
}

case "${1:-help}" in
  build)
    ssh "$HOST" 'mkdir -p ~/assets-work'
    rsync -a --delete src/ "$HOST:~/assets-work/src/"
    ssh "$HOST" 'cd ~/assets-work && rm -rf out
for s in $(ls src/*.py | grep -vE "lib.py|glbinfo.py|validate.py|_smoke.py"); do
  ~/.local/bin/blender -b --factory-startup -noaudio --python "$s" -- --out ~/assets-work/out 2>&1 | grep -E "EXPORT|Error|Traceback|File \"" || true
done
python3 src/validate.py --root out'
    rsync -a --delete --exclude MANIFEST.md "$HOST:~/assets-work/out/models/" models/
    rsync -a --delete "$HOST:~/assets-work/out/reports/" reports/
    python3 src/validate.py --manifest | tail -2 ;;
  shots)
    out=${2:-/tmp/assets-shots}; extra=${*:3}; ensure_project; rm -rf "$out"
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && rm -rf shots && timeout 150 ~/.local/bin/godot --display-driver wayland --path . --resolution 1280x720 -- --out=/home/nick/assets-gd/shots $extra 2>&1 | grep -E 'ERROR|SCRIPT|Parse|SHADER' || true"
    scp -rq "$HOST:~/assets-gd/shots" "$out"; echo "кадры: $out" ;;
  movie)
    mp4=${2:-/tmp/assets-room.mp4}; extra=${*:3}; ensure_project
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && rm -f room.avi && timeout 240 ~/.local/bin/godot --display-driver wayland --path . --resolution 1280x720 --write-movie /home/nick/assets-gd/room.avi --fixed-fps 24 --quit-after 168 -- --movie $extra 2>&1 | grep -E 'ERROR|SCRIPT|Parse' || true"
    scp -q "$HOST:~/assets-gd/room.avi" /tmp/assets-room.avi
    ffmpeg -v error -y -i /tmp/assets-room.avi -c:v libx264 -pix_fmt yuv420p -crf 20 -an "$mp4"; echo "видео: $mp4" ;;
  fps)
    ensure_project
    for cam in "-1.0,1.25,8.6,0.0,1.0,-2.5" "11.0,10.5,11.0,0.0,0.4,-0.5" "0.3,1.6,1.6,0.0,0.0,-0.4"; do
      echo "== камера $cam"
      ssh "$HOST" "$GD_ENV; cd ~/assets-gd && timeout 60 ~/.local/bin/godot --display-driver wayland --path . --resolution 1920x1080 -- --movie --static --fps ${FPS_EXTRA:-} --cam=$cam 2>&1 | grep -E 'GPU мс|вызовов' || true"
    done
    echo "== толпа: 9 аватаров в комнате (--crowd)"
    ssh "$HOST" "$GD_ENV; cd ~/assets-gd && timeout 60 ~/.local/bin/godot --display-driver wayland --path . --resolution 1920x1080 -- --movie --static --fps ${FPS_EXTRA:-} --crowd --cam=-1.0,1.25,8.6,0.0,1.0,-2.5 2>&1 | grep -E 'GPU мс|вызовов' || true"
    echo "ЭТО НЕ Pico 4: настольная видеокарта devbox, окно с вертикальной синхронизацией." ;;
  *) sed -n 2,10p "$0"; exit 2 ;;
esac

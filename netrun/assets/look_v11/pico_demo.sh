#!/usr/bin/env bash
# VR-демо эталона V11 на Pico 4 — отдельное приложение com.megablok10.lookv11 (игру com.megablok10.netrun не трогает).
#   netrun/assets/look_v11/pico_demo.sh build     с Mac: sync + на devbox копия проекта, запекание точек, экспорт APK (очередь gpu)
#   netrun/assets/look_v11/pico_demo.sh install   поставить APK на подключённые к devbox очки (не запускает)
#   netrun/assets/look_v11/pico_demo.sh launch    запустить — только когда владелец сказал, что готов (очки на голове или в руках)
#   netrun/assets/look_v11/pico_demo.sh log       строки LOOKVR из журнала (fps, вид)
#   netrun/assets/look_v11/pico_demo.sh stop
# Копия проекта на devbox (~/look-v11/apk/netrun): главная сцена — look_vr.tscn, пакет и имя — свои; файлы репозитория не меняются.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
SLUG=$(git -C "$ROOT" branch --show-current); SLUG=${SLUG#agent/}; SLUG=${SLUG//\//-}
PKG=com.megablok10.lookv11
APK=look-v11/apk/lookv11.apk
cmd=${1:-}

remote_build() {
  cat <<EOF
set -e
. ~/netrun-env.sh
export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-0
W=~/look-v11/apk
mkdir -p \$W/netrun
rsync -a --delete --exclude .godot --exclude android --exclude build --exclude reports --exclude addons/godot_ai ~/wt-$SLUG/netrun/ \$W/netrun/
cd \$W/netrun
if [ ! -d android/build ]; then
  mkdir -p android/build
  unzip -q ~/.local/share/godot/export_templates/4.7.2.stable/android_source.zip -d android/build
  echo -n "4.7.2.stable" > android/.build_version
  touch android/build/.gdignore
fi
grep -q '^run/main_scene="res://main.tscn"\$' project.godot || { echo "pico_demo: в project.godot нет main_scene=main.tscn — скрипт устарел"; exit 1; }
grep -q '^package/unique_name="com.megablok10.netrun"\$' export_presets.cfg || { echo "pico_demo: в export_presets.cfg нет пакета netrun — скрипт устарел"; exit 1; }
sed -e 's|^run/main_scene="res://main.tscn"\$|run/main_scene="res://assets/look_v11/look_vr.tscn"|' project.godot > project.godot.new && mv project.godot.new project.godot
sed -e 's|^package/unique_name="com.megablok10.netrun"\$|package/unique_name="$PKG"|' -e 's|^package/name="Мегаблок 10: Сеть"\$|package/name="Сеть V11 эталон"|' export_presets.cfg > export_presets.cfg.new && mv export_presets.cfg.new export_presets.cfg
godot --headless --path . --import > \$W/import.log 2>&1 || true
# Запекание — с дисплеем: у headless-рендера пустой буфер MultiMesh.
rm -rf assets/look_v11/baked
timeout 180 flock /tmp/display.lock godot --display-driver wayland --rendering-method mobile --path . --resolution 1280x720 res://assets/look_v11/look_v11.tscn -- --bake > \$W/bake.log 2>&1 </dev/null || true
grep -a "LOOK bake\|ERROR\|SCRIPT" \$W/bake.log | head -5
ls assets/look_v11/baked/World.res > /dev/null || { echo "pico_demo: запекание не удалось, см. \$W/bake.log"; exit 1; }
godot --headless --path . --import > /dev/null 2>&1 || true
mkdir -p build && rm -f build/netrun-client.apk
godot --headless --path . --export-debug "Client Pico 4 (Android)" build/netrun-client.apk > \$W/export.log 2>&1 || { tail -20 \$W/export.log; exit 1; }
cp build/netrun-client.apk ~/$APK
echo "pico_demo: APK \$(du -h ~/$APK | cut -f1) — ~/$APK"
EOF
}

case "$cmd" in
  build)
    "$ROOT/netrun/tools/dev.sh" sync > /dev/null || { echo "pico_demo: sync упал"; exit 1; }
    remote_build | ssh devbox 'mkdir -p ~/look-v11 && cat > ~/look-v11/apk_build.sh' || exit 1
    ssh devbox 'bash ~/box/repo/scripts/box/ctl.sh run gpu Look --name lookv11-apk --wait 900 -- bash ~/look-v11/apk_build.sh' ;;
  install) ssh devbox ". ~/netrun-env.sh; adb install -r ~/$APK 2>&1 | tail -1" ;;
  launch) ssh devbox ". ~/netrun-env.sh; adb logcat -c; adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 > /dev/null && echo 'pico_demo: запущено'" ;;
  stop) ssh devbox ". ~/netrun-env.sh; adb shell am force-stop $PKG && echo 'pico_demo: остановлено'" ;;
  log) ssh devbox ". ~/netrun-env.sh; adb logcat -d -s godot | grep -a 'LOOKVR\|ERROR\|SCRIPT' | tail -${2:-15}" ;;
  *) sed -n 2,8p "$0"; exit 2 ;;
esac

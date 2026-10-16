#!/usr/bin/env bash
# APK очков для П6 из этой копии netrun (без вшитого адреса и токена: их кладёт pico.sh provision) в ~/pico-p6/ — отдельно от ~/pico-cfg,
# чтобы не затирать чужой экспорт. Запускать в очереди gpu: scripts/box.sh run gpu Godot --name p6-build -- bash netrun/tools/p6_build.sh
set -e
# shellcheck disable=SC1090
. ~/netrun-env.sh
SRC="$(cd "$(dirname "$0")/.." && pwd)"
W=${P6_DIR:-$HOME/pico-p6}
mkdir -p "$W/netrun"
rsync -a --delete --exclude .godot --exclude android --exclude build --exclude reports "$SRC/" "$W/netrun/"
cd "$W/netrun"
if [ ! -d android/build ]; then
  mkdir -p android/build
  unzip -q ~/.local/share/godot/export_templates/4.7.2.stable/android_source.zip -d android/build
  echo -n "4.7.2.stable" > android/.build_version
  touch android/build/.gdignore
fi
godot --headless --path . --import > "$W/import.log" 2>&1 || true
mkdir -p build
rm -f build/netrun-client.apk
godot --headless --path . --export-debug "Client Pico 4 (Android)" > "$W/export.log" 2>&1 || { tail -20 "$W/export.log"; exit 1; }
cp build/netrun-client.apk "$W/netrun-client-p6.apk"
ls -la "$W/netrun-client-p6.apk"

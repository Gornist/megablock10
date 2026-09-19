#!/bin/bash
# Скриншоты обоих устройств рядом: ./shot.sh [имя] → $E2E_DIR/shots/<имя>.png (нужен ImageMagick `magick`, иначе два отдельных файла).
source "$(dirname "$0")/lib.sh"
n=${1:-shot_$(date +%H%M%S)}; mkdir -p "$E2E_DIR/shots"
adb_ $A exec-out screencap -p > "$E2E_DIR/shots/${n}_A.png"
adb_ $B exec-out screencap -p > "$E2E_DIR/shots/${n}_B.png"
if command -v magick >/dev/null; then magick "$E2E_DIR/shots/${n}_A.png" "$E2E_DIR/shots/${n}_B.png" +append "$E2E_DIR/shots/$n.png" && echo "$E2E_DIR/shots/$n.png"
else echo "$E2E_DIR/shots/${n}_A.png $E2E_DIR/shots/${n}_B.png"; fi

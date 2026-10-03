#!/bin/bash
# Полная пересборка env и props на devbox: модели, превью, проверка бюджета, MANIFEST.md. Blender на Mac не запускать.
#   scp -r netrun/assets devbox:/tmp/a1/ && ssh devbox 'bash /tmp/a1/assets/src/build_all.sh'
set -e
cd "$(dirname "$0")"
BLENDER=${BLENDER:-$HOME/.local/bin/blender}
$BLENDER -b -P build_env.py | grep -E "^\[ASSET\]|rror|Traceback" || true
$BLENDER -b -P build_props.py | grep -E "^\[ASSET\]|rror|Traceback" || true
$BLENDER -b -P preview.py -- env | grep -E "rror|Traceback" || true
$BLENDER -b -P preview.py -- props | grep -E "rror|Traceback" || true
$BLENDER -b -P preview.py -- assembly | grep -E "rror|Traceback" || true
python3 check_budget.py
python3 manifest.py

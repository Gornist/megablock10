#!/bin/bash
# Полная пересборка всех ассетов на devbox: модели, превью, проверка бюджета, MANIFEST.md. Blender на Mac не запускать.
#   scp -r netrun/assets devbox:/tmp/a1/ && ssh devbox 'bash /tmp/a1/assets/src/build_all.sh'
# Импорт Godot (.glb.import) и снимок сцены — отдельно, см. MANIFEST.md («Как пересобрать»).
# Только часть групп: ASSET_GROUPS="ice avatar deck" bash build_all.sh. Пересборка env/props даёт другие байты при той же геометрии
# (порядок рёбер в наборе меняется от запуска к запуску) — не коммитьте такие .glb, если модель не правили.
set -e
cd "$(dirname "$0")"
BLENDER=${BLENDER:-$HOME/.local/bin/blender}
ASSET_GROUPS=${ASSET_GROUPS:-"env props ice avatar deck"}
for g in $ASSET_GROUPS; do
  case $g in
    env) b=build_env;; props) b=build_props;; ice) b=build_ice;; avatar) b=build_avatar;; deck) b=build_deck;;
  esac
  $BLENDER -b -P $b.py | grep -E "^\[ASSET\]|rror|Traceback" || true
  $BLENDER -b -P preview.py -- $g | grep -E "rror|Traceback" || true
done
[ "$ASSET_GROUPS" = "env props ice avatar deck" ] && { $BLENDER -b -P preview.py -- assembly | grep -E "rror|Traceback" || true; }
python3 check_budget.py
python3 make_preview_scene.py
python3 manifest.py

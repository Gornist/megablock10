#!/usr/bin/env python3
"""Облегчает настройки импорта Godot у .glb.import набора (после первого `godot --headless --path netrun --import`).

    python3 netrun/assets/src/patch_imports.py [каталог_models]

Для автономных очков (Mobile, Pico 4) в наших ассетах не нужны: тангенты (нет карт нормалей), LOD (меши до нескольких тысяч
треугольников), теневые меши (динамических теней нет). Остальные параметры и uid не трогаем. Идемпотентно.
Правки в .import вступают в силу при следующем импорте — тогда Godot пересоберёт ассеты.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(os.path.dirname(HERE), "models")
WANT = {
    "meshes/ensure_tangents": "false",
    "meshes/generate_lods": "false",
    "meshes/create_shadow_meshes": "false",
}


def patch(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    changed = False
    seen = set()
    for i, ln in enumerate(lines):
        key = ln.split("=", 1)[0]
        if key in WANT:
            seen.add(key)
            if ln != "%s=%s" % (key, WANT[key]):
                lines[i] = "%s=%s" % (key, WANT[key])
                changed = True
    missing = set(WANT) - seen
    if missing:
        raise SystemExit("%s: нет параметров %s — версия Godot другая? Сначала выполните импорт." % (path, sorted(missing)))
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    return changed


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    n = c = 0
    for d, _dirs, files in os.walk(root):
        for fn in files:
            if fn.endswith(".glb.import"):
                n += 1
                c += patch(os.path.join(d, fn))
    print("файлов .glb.import: %d, изменено: %d" % (n, c))


if __name__ == "__main__":
    main()

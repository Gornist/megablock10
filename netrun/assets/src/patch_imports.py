#!/usr/bin/env python3
"""Облегчает настройки импорта Godot у .glb.import набора (после первого `godot --headless --path netrun --import`).

    python3 netrun/assets/src/patch_imports.py [каталог_models]

Для автономных очков (Mobile, Pico 4) в наших ассетах не нужны: тангенты (нет карт нормалей), LOD (меши до нескольких тысяч
треугольников), теневые меши (динамических теней нет). Клипы существ (ice) зацикливаются здесь: glTF не хранит петлю, поэтому у
каждой анимации .glb в `_subresources` ставится `settings/loop_mode = 1` (линейная петля Godot). Остальные параметры и uid не
трогаем. Идемпотентно. Правки в .import вступают в силу при следующем импорте — тогда Godot пересоберёт ассеты.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(os.path.dirname(HERE), "models")
WANT = {
    "meshes/ensure_tangents": "false",
    "meshes/generate_lods": "false",
    "meshes/create_shadow_meshes": "false",
}


def loop_subresources(glb_path):
    """Текст значения `_subresources` для .glb: пусто, если анимаций нет; иначе loop_mode=1 у каждой (имена по алфавиту, как пишет Godot)."""
    sys.path.insert(0, HERE)
    import check_budget as cb
    names = sorted({a.get("name", "?") for a in cb.load_glb(glb_path)[0].get("animations", [])})
    if not names:
        return "{}"
    body = ",\n".join('"%s": {\n"settings/loop_mode": 1\n}' % n for n in names)
    return '{\n"animations": {\n%s\n}\n}' % body


def patch_subresources(lines, glb_path):
    """Заменить блок `_subresources=...` (до следующего ключа `ключ=значение` верхнего уровня) на нужный."""
    start = next(i for i, ln in enumerate(lines) if ln.startswith("_subresources="))
    end = start + 1
    while end < len(lines) and not lines[end][:1].isalpha():   # строки блока начинаются с кавычки или скобки
        end += 1
    want = ("_subresources=" + loop_subresources(glb_path)).split("\n")
    if lines[start:end] == want:
        return False
    try:   # Godot при реимпорте раскрывает блок до всех своих ключей — смотрим по смыслу, чтобы не воевать с ним
        have = json.loads("\n".join(lines[start:end])[len("_subresources="):])
        if {k: v.get("settings/loop_mode") for k, v in have.get("animations", {}).items()} == \
                {k: 1 for k in json.loads(loop_subresources(glb_path)).get("animations", {})}:
            return False
    except (ValueError, AttributeError):
        pass
    lines[start:end] = want
    return True


def patch(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    changed = patch_subresources(lines, path[: -len(".import")])
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

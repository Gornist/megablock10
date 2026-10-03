#!/usr/bin/env python3
"""Проверка бюджета ассетов «Сети» по готовым .glb (чистый Python, без Blender и Godot).

    python3 netrun/assets/src/check_budget.py [каталог_models]    # код 1, если что-то вне бюджета

Проверяет для каждого .glb: число треугольников (по всем узлам-экземплярам), не больше двух материалов, нет текстур/картинок,
нет прозрачности (BLEND/MASK), в env и props нет анимаций, скелет не больше 20 костей, у трёх тиров env одинаковые меши.
Бюджеты — из docs/netrun-assets-brief.md; где ТЗ числа не задаёт, взят потолок «предметы ≤ 2000» (помечено в таблице).
"""
import json
import math
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MODELS = os.path.join(os.path.dirname(HERE), "models")

# (группа, регулярное выражение по имени файла без .glb) -> (бюджет, из ТЗ ли число)
BUDGETS = [
    ("env", r".*", 300, True),
    ("props", r"vault.*", 2000, True),
    ("props", r"portal.*", 2000, True),
    ("props", r"shard.*", 300, True),
    ("props", r"dead_deck.*", 2000, True),
    ("props", r"(sensor|seat).*", 2000, False),
    ("ice", r"soft_ice.*", 3000, True),
    ("ice", r"black_ice.*", 6000, True),
    ("avatar", r".*", 2000, True),
    ("deck", r"wrist_deck.*", 2000, True),
    ("deck", r"daemon_.*", 500, False),
]
DEFAULT_BUDGET = (2000, False)
TIER_SUFFIX = re.compile(r"_(hard|nightmare)$")
MAX_MATERIALS = 2
MAX_BONES = 20


def budget_for(group, name):
    for g, pat, limit, from_brief in BUDGETS:
        if g == group and re.fullmatch(pat, name):
            return limit, from_brief
    return DEFAULT_BUDGET


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise ValueError("не glTF 2.0 .glb")
    off, doc = 12, None
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        if ctype == 0x4E4F534A:  # JSON
            doc = json.loads(data[off + 8: off + 8 + clen].decode("utf-8"))
        off += 8 + clen
    if doc is None:
        raise ValueError("нет JSON-чанка")
    return doc


def _mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def _node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    q = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    x, y, z, w = q
    r = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def analyse(doc):
    """Треугольники, материалы, габариты (мировые AABB по узлам), анимации, кости."""
    acc = doc.get("accessors", [])
    meshes = doc.get("meshes", [])
    nodes = doc.get("nodes", [])
    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]

    def mesh_tris(mi):
        total = 0
        for prim in meshes[mi]["primitives"]:
            if prim.get("mode", 4) != 4:
                raise ValueError("не треугольники (mode %s)" % prim.get("mode"))
            total += (acc[prim["indices"]]["count"] if "indices" in prim else acc[prim["attributes"]["POSITION"]]["count"]) // 3
        return total

    tris, lo, hi, used_mats = 0, [1e30] * 3, [-1e30] * 3, set()
    mesh_nodes = []

    def walk(ni, parent):
        node = nodes[ni]
        m = _mat_mul(parent, _node_matrix(node))
        if "mesh" in node:
            mesh_nodes.append((ni, node["mesh"], m))
        for c in node.get("children", []):
            walk(c, m)

    roots = doc["scenes"][doc.get("scene", 0)]["nodes"] if doc.get("scenes") else range(len(nodes))
    for r in roots:
        walk(r, ident)
    for _ni, mi, m in mesh_nodes:
        tris += mesh_tris(mi)
        for prim in meshes[mi]["primitives"]:
            if "material" in prim:
                used_mats.add(prim["material"])
            a = acc[prim["attributes"]["POSITION"]]
            for cx in (0, 1):
                for cy in (0, 1):
                    for cz in (0, 1):
                        p = [a["max"][0] if cx else a["min"][0], a["max"][1] if cy else a["min"][1], a["max"][2] if cz else a["min"][2]]
                        for i in range(3):
                            w = m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3]
                            lo[i], hi[i] = min(lo[i], w), max(hi[i], w)
    bones = max([len(s.get("joints", [])) for s in doc.get("skins", [])] or [0])
    mats = doc.get("materials", [])
    return {
        "tris": tris,
        "materials": [mats[i].get("name", "?") for i in sorted(used_mats)],
        "mat_docs": [mats[i] for i in sorted(used_mats)],
        "size": [round(hi[i] - lo[i], 3) for i in range(3)] if mesh_nodes else [0, 0, 0],
        "min": [round(v, 3) for v in lo] if mesh_nodes else [0, 0, 0],
        "max": [round(v, 3) for v in hi] if mesh_nodes else [0, 0, 0],
        "animations": [a.get("name", "?") for a in doc.get("animations", [])],
        "bones": bones,
        "images": len(doc.get("images", [])) + len(doc.get("textures", [])),
        "nodes": [n.get("name", "?") for n in nodes],
    }


def scan(models):
    out = []
    for group in sorted(os.listdir(models)):
        gdir = os.path.join(models, group)
        if not os.path.isdir(gdir):
            continue
        for fn in sorted(os.listdir(gdir)):
            if fn.endswith(".glb"):
                path = os.path.join(gdir, fn)
                info = analyse(load_glb(path))
                info.update(group=group, name=fn[:-4], path=path)
                out.append(info)
    return out


def violations(info):
    errs = []
    limit, _ = budget_for(info["group"], info["name"])
    if info["tris"] > limit:
        errs.append("треугольников %d > бюджет %d" % (info["tris"], limit))
    if len(info["materials"]) > MAX_MATERIALS:
        errs.append("материалов %d > %d" % (len(info["materials"]), MAX_MATERIALS))
    if info["images"]:
        errs.append("есть текстуры/картинки (%d): текстур в наборе нет" % info["images"])
    for m in info["mat_docs"]:
        if m.get("alphaMode", "OPAQUE") != "OPAQUE":
            errs.append("прозрачность у материала %s (%s)" % (m.get("name"), m.get("alphaMode")))
    if info["group"] in ("env", "props") and info["animations"]:
        errs.append("анимации в %s не нужны: %s" % (info["group"], info["animations"]))
    if info["bones"] > MAX_BONES:
        errs.append("костей %d > %d" % (info["bones"], MAX_BONES))
    return errs


def main(argv):
    models = argv[1] if len(argv) > 1 else DEFAULT_MODELS
    infos = scan(models)
    bad = 0
    tiers = {}
    print("%-34s %6s %7s  %s" % ("файл", "треуг.", "бюджет", "размер X*Y*Z, м"))
    for i in infos:
        limit, from_brief = budget_for(i["group"], i["name"])
        errs = violations(i)
        mark = "" if from_brief else " *"
        print("%-34s %6d %7s  %s %s" % ("%s/%s" % (i["group"], i["name"]), i["tris"], str(limit) + mark,
                                       "x".join("%.2f" % v for v in i["size"]), "  <-- " + "; ".join(errs) if errs else ""))
        bad += bool(errs)
        if i["group"] == "env":
            tiers.setdefault(TIER_SUFFIX.sub("", i["name"]), set()).add(i["tris"])
    for base, counts in tiers.items():
        if len(counts) > 1:
            bad += 1
            print("env/%s: у тиров разное число треугольников %s" % (base, sorted(counts)))
    print("* — число бюджета не задано ТЗ, принят потолок")
    if not infos:
        print("нет ни одного .glb в", models)
        return 1
    print("ИТОГО: %d файлов, нарушений: %d" % (len(infos), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

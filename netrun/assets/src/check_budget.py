#!/usr/bin/env python3
"""Проверка бюджета ассетов «Сети» по готовым .glb (чистый Python, без Blender и Godot).

    python3 netrun/assets/src/check_budget.py [каталог_models]    # код 1, если что-то вне бюджета

Проверяет для каждого .glb: число треугольников (по всем узлам-экземплярам), не больше двух материалов, нет текстур/картинок
(плоскость под экран деки — исключение: у неё есть UV, но нет картинок), нет прозрачности (BLEND/MASK), анимации только у ICE
(имена из ТЗ, короткие, зацикленные: последний ключ равен первому), скелет не больше 20 костей и только у ICE и аватара, у трёх
тиров env одинаковые меши, есть все файлы набора из ТЗ.
Бюджеты — из docs/netrun-assets-brief.md; где ТЗ числа не задаёт, взят потолок «предметы ≤ 2000» (жетоны демонов — 500).
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
DAEMON_EFFECTS = ["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]
# клипы ICE: имена и допустимая длина — ТЗ («короткие зацикленные клипы с именами из списка»)
ICE_CLIPS = {"soft_ice": {"idle", "patrol"}, "black_ice": {"idle", "hunt", "catch"}}
MAX_CLIP_SECONDS = 4.0
# файлы набора (ТЗ): без них приёмка красная; тиры env проверяются отдельно
REQUIRED = (
    ["env/" + n for n in ("floor", "wall", "corner", "pillar", "doorway", "platform", "lockdown_gate", "cable_straight", "cable_curve", "tunnel_ring")]
    + ["props/" + n for n in ("vault_closed", "vault_open", "shard", "shard_encrypted", "dead_deck", "portal", "portal_locked", "sensor", "seat")]
    + ["ice/soft_ice", "ice/black_ice", "avatar/runner", "deck/wrist_deck"]
    + ["deck/daemon_" + e for e in DAEMON_EFFECTS]
)
SKINNED = ("ice", "avatar")
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
    off, doc, blob = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        if ctype == 0x4E4F534A:  # JSON
            doc = json.loads(data[off + 8: off + 8 + clen].decode("utf-8"))
        elif ctype == 0x004E4942:  # BIN
            blob = data[off + 8: off + 8 + clen]
        off += 8 + clen
    if doc is None:
        raise ValueError("нет JSON-чанка")
    return doc, blob


def read_floats(doc, blob, idx):
    """Значения FLOAT-акцессора как список кортежей (для выходов анимаций: VEC3 / VEC4)."""
    a = doc["accessors"][idx]
    if a["componentType"] != 5126:
        raise ValueError("ожидался FLOAT-акцессор")
    n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
    bv = doc["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride") or n * 4
    return [struct.unpack_from("<%df" % n, blob, off + i * stride) for i in range(a["count"])]


def clip_report(doc, blob):
    """[(имя, секунд, зациклен ли)] по анимациям: зациклен, если у каждого канала последнее значение совпадает с первым."""
    out = []
    for anim in doc.get("animations", []):
        length, looped = 0.0, True
        for ch in anim["channels"]:
            sm = anim["samplers"][ch["sampler"]]
            times = read_floats(doc, blob, sm["input"])
            length = max(length, times[-1][0])
            vals = read_floats(doc, blob, sm["output"])
            first, last = vals[0], vals[-1]
            if len(first) == 4:   # кватернион: q и -q — один и тот же поворот
                same = abs(sum(x * y for x, y in zip(first, last))) > 1 - 1e-5
            else:
                same = all(abs(x - y) < 1e-4 for x, y in zip(first, last))
            looped = looped and same
        out.append((anim.get("name", "?"), round(length, 3), looped))
    return out


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


def analyse(doc, blob=b""):
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
        "clips": clip_report(doc, blob),
        "skins": len(doc.get("skins", [])),
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
                info = analyse(*load_glb(path))
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
    group, name = info["group"], info["name"]
    if group != "ice" and info["animations"]:
        errs.append("анимации в %s не нужны: %s" % (group, info["animations"]))
    if group == "ice":
        want = ICE_CLIPS.get(name, set())
        if set(info["animations"]) != want:
            errs.append("клипы %s, по ТЗ нужны %s" % (sorted(info["animations"]), sorted(want)))
        for clip, seconds, looped in info["clips"]:
            if not 0 < seconds <= MAX_CLIP_SECONDS:
                errs.append("клип %s: длина %.2f с, нужно короткий (до %.0f с)" % (clip, seconds, MAX_CLIP_SECONDS))
            if not looped:
                errs.append("клип %s не зациклен: последний ключ не равен первому" % clip)
    if group in SKINNED and not info["skins"]:
        errs.append("у существа нет скелета")
    if group not in SKINNED and info["skins"]:
        errs.append("скелет в %s не нужен" % group)
    if info["bones"] > MAX_BONES:
        errs.append("костей %d > %d" % (info["bones"], MAX_BONES))
    return errs


def main(argv):
    models = argv[1] if len(argv) > 1 else DEFAULT_MODELS
    infos = scan(models)
    bad = 0
    tiers = {}
    print("%-34s %6s %7s  %s" % ("файл", "треуг.", "бюджет", "размер X*Y*Z, м"))   # кости/клипы — в конце строки
    for i in infos:
        limit, from_brief = budget_for(i["group"], i["name"])
        errs = violations(i)
        mark = "" if from_brief else " *"
        extra = ""
        if i["bones"]:
            extra = "  костей %d" % i["bones"] + "".join(", %s %.1f с" % (c, sec) for c, sec, _ in i["clips"])
        print("%-34s %6d %7s  %s%s%s" % ("%s/%s" % (i["group"], i["name"]), i["tris"], str(limit) + mark,
                                        "x".join("%.2f" % v for v in i["size"]), extra, "  <-- " + "; ".join(errs) if errs else ""))
        bad += bool(errs)
        if i["group"] == "env":
            tiers.setdefault(TIER_SUFFIX.sub("", i["name"]), set()).add(i["tris"])
    have = {"%s/%s" % (i["group"], i["name"]) for i in infos}
    for need in REQUIRED:
        if need not in have:
            bad += 1
            print("нет файла из набора ТЗ:", need + ".glb")
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

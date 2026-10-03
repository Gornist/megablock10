"""Чтение .glb без Blender: числа для бюджета и проверок. Единственный источник «что в файле».

Работает на чистом Python 3 (Mac, devbox, CI): `python3 glbinfo.py файл.glb`.
Узлы сцены считаются нулевыми по трансформации (сборка применяет все трансформации), отклонения попадают в `moved_nodes`.
"""
import json
import struct
import sys


def parse(path):
    data = open(path, "rb").read()
    magic, _version, _length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        raise ValueError(f"{path}: не glb")
    chunk_len, _ctype = struct.unpack("<II", data[12:20])
    doc = json.loads(data[20:20 + chunk_len])
    acc = doc["accessors"]
    mats = doc.get("materials", [])
    prims = []
    for mesh in doc.get("meshes", []):
        for p in mesh["primitives"]:
            pos = acc[p["attributes"]["POSITION"]]
            tris = acc[p["indices"]]["count"] // 3 if "indices" in p else pos["count"] // 3
            prims.append({
                "mesh": mesh.get("name"),
                "material": mats[p["material"]]["name"] if "material" in p else None,
                "tris": tris,
                "verts": pos["count"],
                "attrs": sorted(p["attributes"]),
                "min": pos["min"],
                "max": pos["max"],
            })
    moved = sum(
        1 for n in doc.get("nodes", [])
        if any(k in n for k in ("translation", "rotation", "scale", "matrix")) and "skin" not in n and "mesh" in n
    )
    lo = [min(p["min"][i] for p in prims) for i in range(3)] if prims else [0, 0, 0]
    hi = [max(p["max"][i] for p in prims) for i in range(3)] if prims else [0, 0, 0]
    return {
        "prims": prims,
        "materials": [m["name"] for m in mats],
        "animations": [a.get("name") for a in doc.get("animations", [])],
        "bbox_min": lo,
        "bbox_max": hi,
        "size": [round(hi[i] - lo[i], 4) for i in range(3)],
        "moved_nodes": moved,
    }


def summary(info):
    """Сводка по ролям материалов: треугольники, точки и штрихи (квадрат точки или штриха = 4 вершины, 2 треугольника)."""
    tris = sum(p["tris"] for p in info["prims"] if p["material"] not in ("points", "streaks"))
    points = sum(p["verts"] // 4 for p in info["prims"] if p["material"] == "points")
    streaks = sum(p["verts"] // 4 for p in info["prims"] if p["material"] == "streaks")
    layers = sum(1 for p in info["prims"] if p["material"] == "shell_soft")
    return {"tris": tris, "points": points, "streaks": streaks, "layers": layers}


if __name__ == "__main__":
    for f in sys.argv[1:]:
        i = parse(f)
        print(f, json.dumps({**summary(i), "size": i["size"], "materials": i["materials"], "animations": i["animations"],
                              "attrs": sorted({a for p in i["prims"] for a in p["attrs"]})}, ensure_ascii=False))

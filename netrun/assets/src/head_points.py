#!/usr/bin/env python3
"""Облако точек головы чужого нетраннера из 3D-модели головы (STL, миллиметры, Z вверх, лицо смотрит в -Y).

Запуск: python3 netrun/assets/src/head_points.py путь/к/HeadLowPolygon.stl  ->  netrun/client/head_points.gd
Чистый Python, без numpy. Что делает:
  1. читает бинарный STL, склеивает совпавшие вершины, считает нормали граней и углы между соседними гранями;
  2. берёт «линии»: рёбра с резким изломом (нос, глазницы, губы, челюсть, уши) — точки через ~4,5 мм вдоль ребра, бюджет LINE_BUDGET;
  3. добавляет точки по поверхности, площадь × вес (лицо в 4 раза гуще затылка), бюджет SURFACE_BUDGET;
  4. переводит в систему головы клиента: начало между глаз, +Y вверх, -Z вперёд, метры; шея ниже подбородка обрезана.
Результат — константа Array[float] (по 6 чисел на точку: x, y, z, размер, яркость, фаза) в client/head_points.gd.
Модель в репозиторий не кладётся (лицензия — на владельце); сгенерированные точки — да. Зерно фиксировано: результат повторяется.
"""
import math
import os
import random
import struct
import sys

SCALE = 0.001            # мм -> м
LINE_BUDGET = 380
SURFACE_BUDGET = 250
LINE_SPACING = 4.5       # мм вдоль ребра
CREASE_DEG = 24.0
NECK_CUT_Z = 14.0        # мм: ниже подбородка (≈ 22 мм) оставляем немного шеи, дальше — обрезаем
SEED = 5

# Положение «между глаз» в системе модели, мм. Подобрано по виду сбоку/спереди (глаза на высоте 125 мм, нос выступает до y = 0).
EYE_Y = 50.0
EYE_Z = 125.0


def read_stl(path):
    data = open(path, "rb").read()
    n = struct.unpack("<I", data[80:84])[0]
    if 84 + 50 * n != len(data):
        raise SystemExit("ожидается бинарный STL")
    verts, index, tris = [], {}, []
    for i in range(n):
        v = struct.unpack("<12f", data[84 + 50 * i:84 + 50 * i + 48])
        ids = []
        for k in range(3):
            p = (v[3 + 3 * k], v[4 + 3 * k], v[5 + 3 * k])
            key = tuple(round(c, 3) for c in p)
            if key not in index:
                index[key] = len(verts)
                verts.append(p)
            ids.append(index[key])
        if len(set(ids)) == 3:
            tris.append(tuple(ids))
    return verts, tris


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def length(a): return math.sqrt(dot(a, a))


def unit(a):
    l = length(a)
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-9 else (0.0, 0.0, 0.0)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if not os.path.isfile(sys.argv[1]):
        # STL в репозитории нет (решение владельца), это не ошибка. Раньше конвейер гнал этот скрипт под Blender, и argv[1] был его флагом «-b»
        print("head_points: нет HeadLowPolygon.stl — пропуск")
        return
    verts, tris = read_stl(sys.argv[1])
    rng = random.Random(SEED)
    cx = (min(v[0] for v in verts) + max(v[0] for v in verts)) / 2.0

    normals, areas, cents = [], [], []
    for a, b, c in tris:
        nrm = cross(sub(verts[b], verts[a]), sub(verts[c], verts[a]))
        areas.append(length(nrm) / 2.0)
        normals.append(unit(nrm))
        cents.append(tuple((verts[a][k] + verts[b][k] + verts[c][k]) / 3.0 for k in range(3)))

    edges = {}
    for t, (a, b, c) in enumerate(tris):
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault((min(u, v), max(u, v)), []).append(t)

    creases = []
    for (u, v), ts in edges.items():
        if len(ts) != 2:
            continue
        ang = math.degrees(math.acos(max(-1.0, min(1.0, dot(normals[ts[0]], normals[ts[1]])))))
        mid_z = (verts[u][2] + verts[v][2]) / 2.0
        if ang >= CREASE_DEG and mid_z >= NECK_CUT_Z:
            creases.append((ang, u, v))
    creases.sort(reverse=True)

    pts = {}  # ключ округлённой позиции -> (x, y, z, вид, угол)

    def add(p, kind, ang=0.0):
        key = tuple(round(c / 1.5) for c in p)
        if key not in pts or (kind == "line" and pts[key][3] != "line"):
            pts[key] = (p[0], p[1], p[2], kind, ang)

    for ang, u, v in creases:
        if sum(1 for q in pts.values() if q[3] == "line") >= LINE_BUDGET:
            break
        a, b = verts[u], verts[v]
        n = max(1, int(round(length(sub(b, a)) / LINE_SPACING)))
        for i in range(n + 1):
            t = i / n
            add(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)), "line", ang)

    # поверхность: площадь × вес (лицо спереди гуще)
    weights = []
    for t, c in enumerate(cents):
        w = areas[t] if c[2] >= NECK_CUT_Z else 0.0
        if c[1] < 75.0 and c[2] > 30.0 and abs(c[0] - cx) < 62.0:
            w *= 4.0
        weights.append(w)
    total = sum(weights)
    cum, s = [], 0.0
    for w in weights:
        s += w
        cum.append(s)
    placed = 0
    guard = 0
    while placed < SURFACE_BUDGET and guard < 20000:
        guard += 1
        r = rng.random() * total
        lo, hi = 0, len(cum) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if cum[mid] < r:
                lo = mid + 1
            else:
                hi = mid
        a, b, c = (verts[i] for i in tris[lo])
        u, v = rng.random(), rng.random()
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        p = tuple(a[k] + (b[k] - a[k]) * u + (c[k] - a[k]) * v for k in range(3))
        before = len(pts)
        add(p, "surface")
        if len(pts) > before:
            placed += 1

    zmin = min(q[2] for q in pts.values())
    zmax = max(q[2] for q in pts.values())
    rows = []
    for x, y, z, kind, ang in pts.values():
        gx = (x - cx) * SCALE
        gy = (z - EYE_Z) * SCALE
        gz = (y - EYE_Y) * SCALE
        front = 1.0 if y < 75.0 and z > 30.0 and abs(x - cx) < 62.0 else 0.0
        ear = abs(x - cx) > 68.0
        neck = z < 30.0
        if kind == "line":
            w = 0.7 + 0.3 * min(ang / 90.0, 1.0)
            size = 0.0028 + 0.0008 * front
        else:
            w = 0.5 if front else 0.32
            size = 0.0022
        if ear:
            w *= 0.7
        if neck:
            w *= 0.5
        phase = (z - zmin) / (zmax - zmin)
        rows.append((gx, gy, gz, size, min(w + 0.15 * front, 1.0), phase))
    rows.sort(key=lambda r: (-r[4], r[1]))

    ys = [r[1] for r in rows]
    zs = [r[2] for r in rows]
    xs = [r[0] for r in rows]
    center = ((max(xs) + min(xs)) / 2.0, (max(ys) + min(ys)) / 2.0 + 0.0, (max(zs) + min(zs)) / 2.0)
    out = ["# Сгенерировано netrun/assets/src/head_points.py из модели головы (STL). Не править руками: перегенерировать скриптом.",
           "class_name HeadPoints",
           "extends RefCounted",
           "## Облако точек головы в системе головы клиента: начало между глаз, +Y вверх, -Z вперёд, метры. По 6 чисел на точку: x, y, z, размер, яркость, фаза (0 шея … 1 макушка).",
           "## Линии — рёбра с резким изломом (нос, глазницы, губы, челюсть, уши), остальное — точки по поверхности, на лице гуще.",
           "",
           "const STRIDE := 6",
           "const COUNT := %d" % len(rows),
           "const CENTER := Vector3(%.4f, %.4f, %.4f)" % center,
           "const HALF := Vector3(%.4f, %.4f, %.4f)" % ((max(xs) - min(xs)) / 2.0, (max(ys) - min(ys)) / 2.0, (max(zs) - min(zs)) / 2.0),
           "const DATA: Array[float] = [",
           ]
    for r in rows:
        out.append("\t%.4f, %.4f, %.4f, %.4f, %.2f, %.2f," % r)
    out.append("]")
    path = __file__.rsplit("/netrun/", 1)[0] + "/netrun/client/head_points.gd"
    open(path, "w").write("\n".join(out) + "\n")
    lines = sum(1 for q in pts.values() if q[3] == "line")
    print("точек %d (линий %d, поверхность %d), центр %s, размеры %s -> %s" % (len(rows), lines, len(rows) - lines, tuple(round(c, 3) for c in center), (round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)), path))


if __name__ == "__main__":
    main()

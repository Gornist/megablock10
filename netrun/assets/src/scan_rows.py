"""Строки скана (вид V11, решение владельца 31.10): поверхности Сети — точки, выложенные горизонтальными строками с ровным шагом
по высоте, как скан лидара. Чистый Python 3 без Blender и numpy; пишет `.points` в формате `VolumeCloud` (client/volume_cloud.gd):
little-endian float32, 7 чисел на точку [x, y, z, полуразмер_м, фаза 0…1, вид (0 точка / 1 искра), вес 0…1], порядок перемешан
(префикс массива — равномерная выборка, это и есть ЛОД).

Правила строки (STYLE.md «Строки скана»):
  - шаг между строками РОВНЫЙ (он читается как масштаб поверхности), строки горизонтальны; у пола — вдоль X при постоянном Z;
  - внутри строки шаг с разбросом ±JITTER и пропусками ~12 % (одиночные и по 2–3 подряд) — «вариативность вместо линейки»;
  - край растворяется: к силуэту и стыку с другой поверхностью точки редеют, а вес (яркость) падает; резкого обрыва нет;
  - размер точки — мировой (HALF_K × меньший из шагов), на экране его держит шейдер.

Запуск (тестовая комната для замера способов рисования, карточка Pipeline 31.10):
    python3 scan_rows.py --n 300000 --out /путь/scan_room_300k.points      # точек ровно N (после перемешивания — усечение)
    python3 scan_rows.py --check /путь/scan_room_300k.points               # размер кратен 28, габарит, веса
Рядом пишется `<имя>.json`: число точек по поверхностям, шаги, габарит, прямоугольники оснований колонн (для `set_cloud_occluders`).
Детерминировано: seed = SEED_BASE + N.
"""
import argparse
import array
import json
import math
import os
import random
import struct
import sys

POINT_FLOATS = 7
POINT_BYTES = POINT_FLOATS * 4
SEED_BASE = 20261031
JITTER = 0.35        # разброс шага внутри строки, доля шага
GAP_START = 0.06     # вероятность начать пропуск на точке; средняя длина пропуска 2 → ≈ 12 % выпавших
SPARK = 0.015        # доля «искр» (вид 1): чуть ярче и крупнее
HALF_K = 0.42        # полуразмер точки = HALF_K × меньший шаг
DEPTH_JITTER = 0.003 # разброс по нормали, м (поверхность не идеально плоская)
FADE_W = 0.5         # ширина растворения края, м
MIN_WEIGHT = 0.18    # вес у самого края (не нулевой: край тускнеет, но не исчезает целиком)

# Комната-фойе (NodeLayout): x −8…8, z −14…2; колонны по 1,9×1,9 м (корпус из 2×2 м с щелью 5 см), высота 2,2 м.
ROOM_MIN = (-8.0, -14.0)
ROOM_MAX = (8.0, 2.0)
PILLARS = [(-3.0, -5.0), (3.0, -5.0), (-3.0, -11.0), (1.0, -11.0)]
PILLAR_SIZE = 1.9
PILLAR_H = 2.2


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


class Rows:
    """Накопитель точек: плоский array('f') по 7 чисел."""

    def __init__(self):
        self.data = array.array("f")
        self.by_surface = {}

    def add(self, surface, x, y, z, half, weight, rng):
        spark = 1.0 if rng.random() < SPARK else 0.0
        self.data.extend((x, y, z, half * (1.35 if spark else 1.0), rng.random(), spark, weight))
        self.by_surface[surface] = self.by_surface.get(surface, 0) + 1

    def count(self):
        return len(self.data) // POINT_FLOATS


def _row_points(rng, length, pitch):
    """Положения вдоль строки 0…length: шаг с разбросом, пропуски одиночные и по 2–3 подряд."""
    out = []
    t = rng.random() * pitch
    gap = 0
    while t < length:
        if gap > 0:
            gap -= 1
        elif rng.random() < GAP_START:
            gap = rng.choice((1, 1, 2, 3))   # этот и следующие gap−1… точек выпадают
        else:
            out.append(t)
        t += pitch * (1.0 + (rng.random() * 2.0 - 1.0) * JITTER)
    return out


def quad_rows(acc, surface, rng, origin, ax_u, ax_v, w, h, row_pitch, pt_pitch, edge_dist, normal, skip=None):
    """Строки на прямоугольнике: origin + u·ax_u + v·ax_v, u 0…w (вдоль строки), v 0…h (ряды, ровный шаг row_pitch).
    edge_dist(u, v) → расстояние до края, который растворяется (м; большое — края нет). skip(x, y, z) → True: точку не ставить.
    Возвращает число добавленных точек."""
    half = HALF_K * min(row_pitch, pt_pitch)
    n0 = acc.count()
    rows = max(int(round(h / row_pitch)), 1)
    step_v = h / rows
    for r in range(rows + 1):
        v = r * step_v
        for u in _row_points(rng, w, pt_pitch):
            d = edge_dist(u, v)
            f = smoothstep(0.0, FADE_W, d)
            if rng.random() > 0.25 + 0.75 * f:     # у края строки редеют
                continue
            x = origin[0] + ax_u[0] * u + ax_v[0] * v
            y = origin[1] + ax_u[1] * u + ax_v[1] * v
            z = origin[2] + ax_u[2] * u + ax_v[2] * v
            dj = (rng.random() * 2.0 - 1.0) * DEPTH_JITTER
            x, y, z = x + normal[0] * dj, y + normal[1] * dj, z + normal[2] * dj
            if skip is not None and skip(x, y, z):
                continue
            acc.add(surface, x, y, z, half, MIN_WEIGHT + (1.0 - MIN_WEIGHT) * f, rng)
    return acc.count() - n0


def build(row_pitch, pt_pitch, seed):
    """Вся комната: пол, четыре боковых грани и верх каждой колонны. Возвращает (Rows, правила)."""
    rng = random.Random(seed)
    acc = Rows()
    x0, z0 = ROOM_MIN
    x1, z1 = ROOM_MAX
    hs = PILLAR_SIZE / 2.0
    rects = [(px - hs, pz - hs, px + hs, pz + hs) for px, pz in PILLARS]

    def dist_rects(x, z):   # расстояние от точки до ближайшего основания колонны (внутри — 0)
        best = 1e9
        for ax, az, bx, bz in rects:
            dx = max(ax - x, 0.0, x - bx)
            dz = max(az - z, 0.0, z - bz)
            best = min(best, math.hypot(dx, dz))
        return best

    def floor_edge(u, v):   # u — вдоль X, v — вдоль Z
        x, z = x0 + u, z0 + v
        d_room = min(x - x0, x1 - x, z - z0, z1 - z)
        return min(d_room, dist_rects(x, z))

    quad_rows(acc, "floor", rng, (x0, 0.0, z0), (1, 0, 0), (0, 0, 1), x1 - x0, z1 - z0, row_pitch, pt_pitch,
              floor_edge, (0, 1, 0), skip=lambda x, y, z: dist_rects(x, z) <= 0.0)
    for k, (ax, az, bx, bz) in enumerate(rects):
        w = bx - ax
        # грани: юг (z=bz), север (z=az), запад (x=ax), восток (x=bx); u вдоль грани, v вверх; край — основание, верх и вертикальные рёбра
        faces = (
            ((ax, 0.0, bz), (1, 0, 0), (0, 0, 1)),
            ((bx, 0.0, az), (-1, 0, 0), (0, 0, -1)),
            ((ax, 0.0, az), (0, 0, 1), (-1, 0, 0)),
            ((bx, 0.0, bz), (0, 0, -1), (1, 0, 0)),
        )
        for fi, (org, au, nrm) in enumerate(faces):
            def side_edge(u, v, w=w):
                return min(u, w - u, v, PILLAR_H - v)
            quad_rows(acc, "pillar%d_side" % k, rng, org, au, (0, 1, 0), w, PILLAR_H, row_pitch, pt_pitch, side_edge, nrm)
        def top_edge(u, v, w=w):
            return min(u, w - u, v, w - v)
        quad_rows(acc, "pillar%d_top" % k, rng, (ax, PILLAR_H, az), (1, 0, 0), (0, 0, 1), w, w, row_pitch, pt_pitch, top_edge, (0, 1, 0))
    return acc, rects


def make(n, seed=None):
    """Комната ровно на n точек: шаг подбирается итерациями, лишнее после перемешивания отбрасывается."""
    seed = SEED_BASE + n if seed is None else seed
    area = (ROOM_MAX[0] - ROOM_MIN[0]) * (ROOM_MAX[1] - ROOM_MIN[1]) + len(PILLARS) * (4 * PILLAR_SIZE * PILLAR_H + PILLAR_SIZE ** 2) \
        - len(PILLARS) * PILLAR_SIZE ** 2
    pitch = math.sqrt(0.62 * area / n)      # 0,62 — доля, что остаётся после пропусков и растворения краёв
    for _ in range(6):
        acc, rects = build(pitch, pitch, seed)
        got = acc.count()
        if got >= n and got <= n * 1.06:
            break
        pitch *= math.sqrt(got / n) if got < n else math.sqrt(got / n) * 0.995
    pts = acc.data
    order = list(range(got))
    random.Random(seed ^ 0x5CA1AB1E).shuffle(order)
    keep = order[:n]
    out = array.array("f")
    for i in keep:
        out.extend(pts[i * POINT_FLOATS:(i + 1) * POINT_FLOATS])
    meta = {
        "points": len(out) // POINT_FLOATS, "requested": n, "pitch_m": round(pitch, 5), "row_pitch_m": round(pitch, 5),
        "seed": seed, "room": {"min": ROOM_MIN, "max": ROOM_MAX}, "pillar_rects_xz": [list(r) for r in rects],
        "pillar_height_m": PILLAR_H, "by_surface_before_trim": acc.by_surface,
        "format": "float32 LE x7: x y z half phase kind weight (client/volume_cloud.gd)",
    }
    return out, meta


def check(path):
    size = os.path.getsize(path)
    if size % POINT_BYTES:
        print("FAIL: размер %d не кратен %d" % (size, POINT_BYTES)); return 1
    a = array.array("f"); a.fromfile(open(path, "rb"), size // 4)
    n = len(a) // POINT_FLOATS
    xs = a[0::7]; ys = a[1::7]; zs = a[2::7]; hs = a[3::7]; ws = a[6::7]
    bad = [i for i in range(n) if not (0.0 <= ws[i] <= 1.0) or not (0.0 < hs[i] <= 0.05)]
    print("%s: %d точек; x %.2f…%.2f y %.2f…%.2f z %.2f…%.2f; полуразмер %.4f…%.4f; вес %.2f…%.2f" % (
        os.path.basename(path), n, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), min(hs), max(hs), min(ws), max(ws)))
    if bad:
        print("FAIL: %d точек с весом/размером вне допуска" % len(bad)); return 1
    print("ok"); return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, help="число точек")
    ap.add_argument("--out", help="файл .points")
    ap.add_argument("--check", help="проверить готовый .points")
    a = ap.parse_args()
    if a.check:
        sys.exit(check(a.check))
    if not a.n or not a.out:
        ap.error("нужны --n и --out (или --check)")
    pts, meta = make(a.n)
    with open(a.out, "wb") as f:
        pts.tofile(f)
    with open(os.path.splitext(a.out)[0] + ".json", "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("ok: %d точек, шаг %.4f м -> %s" % (meta["points"], meta["pitch_m"], a.out))


if __name__ == "__main__":
    main()

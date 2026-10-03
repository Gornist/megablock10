"""Окружение «Сети»: модульный набор на сетке 2x2 м, по три тира (BASE, HARD, NIGHTMARE) — те же меши, разные материалы.

Запуск: blender -b -P netrun/assets/src/build_env.py   (на devbox; результат — netrun/assets/models/env/*.glb)

Соглашения набора (подробнее — models/MANIFEST.md):
- ячейка 2x2 м, origin на полу в центре ячейки, ось Y вверх;
- лицо модуля (внутренняя сторона стены) смотрит в +Z; стена стоит на крае ячейки z=-1 и входит внутрь на 0,2 м;
  на другие края — поворотом на 90 градусов вокруг Y;
- BASE — файл <имя>.glb, HARD — <имя>_hard.glb, NIGHTMARE — <имя>_nightmare.glb.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as bc  # noqa: E402
import palette  # noqa: E402
from bl_common import MODELS, Part, X, Y, Z  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

B, N = 0, 1  # индексы материалов: тело, неон
WALL_H = 3.2
DOOR_W, DOOR_H = 1.4, 2.4


# --- детали стены (локальные координаты: лицо +Z, стена на z in [-1.0, -0.8]) ----------------------------------------
def plinth(p, x0, x1):
    p.box(((x0 + x1) / 2, 0.15, -0.88), (x1 - x0, 0.30, 0.24), B, 0.035, "top")


def panel(p, x0, x1, y0, y1):
    p.box(((x0 + x1) / 2, (y0 + y1) / 2, -0.91), (x1 - x0, y1 - y0, 0.18), B, 0.03, "vert")


def cap(p, x0, x1):
    p.box(((x0 + x1) / 2, 3.1, -0.89), (x1 - x0, 0.2, 0.22), B, 0.035, "top")


def wall_neon(p, x0, x1):
    """Две вертикальные полосы, горизонтальная у верха и полоса на цоколе."""
    mid = (x0 + x1) / 2
    for dx in (-0.62, 0.62):
        x = mid + dx
        if x0 + 0.1 < x < x1 - 0.1:
            p.strip((x, 1.65, -0.82), 2.1, 0.06, Y, Z, N)
    p.strip((mid, 2.78, -0.82), min(1.1, (x1 - x0) - 0.4), 0.05, X, Z, N)
    p.strip((mid, 0.15, -0.76), min(1.6, (x1 - x0) - 0.3), 0.04, X, Z, N)


def wall_run(p, x0, x1):
    plinth(p, x0, x1)
    panel(p, x0, x1, 0.3, 3.0)
    cap(p, x0, x1)
    wall_neon(p, x0, x1)


# --- модули ---------------------------------------------------------------------------------------------------------
def floor(m):
    p = Part("Mesh", m)
    p.box((0, -0.06, 0), (2, 0.12, 2), B, 0.03, "top")
    p.ring((0, 0, 0), 0.78, 0.89, 8, Y, N, rot=math.radians(22.5))
    p.disc((0, 0, 0), 0.14, 8, Y, N, rot=math.radians(22.5))
    return [p.build()]


def wall(m):
    p = Part("Mesh", m)
    wall_run(p, -1.0, 1.0)
    return [p.build()]


def corner(m):
    """Внутренний угол: стена по краю -Z и стена по краю -X (получается поворотом первой) со столбом в вершине."""
    p = Part("Mesh", m)
    wall_run(p, -1.0, 1.0)
    with p.frame(Matrix.Rotation(math.radians(90), 4, "Y")):
        # в мировых осях эта стена занимает x in [-1, -0.8], z in [-0.8, 1.0]
        wall_run(p, -1.0, 0.8)
    p.box((-0.86, 1.625, -0.86), (0.28, 3.25, 0.28), B, 0.04, "all")
    p.strip((-0.72, 1.65, -0.86), 2.0, 0.05, Y, X, N)
    p.strip((-0.86, 1.65, -0.72), 2.0, 0.05, Y, Z, N)
    return [p.build()]


def pillar(m):
    p = Part("Mesh", m)
    rot = math.radians(22.5)
    r = 0.30 / math.cos(math.radians(22.5))  # 0.30 — расстояние до грани
    p.frustum(0, 0, 0, 0.3, 0.46, 0.34, 8, B, rot, caps="bot")
    p.frustum(0, 0, 0.3, 2.9, r, r, 8, B, rot, caps="none")
    p.frustum(0, 0, 2.9, 3.2, 0.34, 0.46, 8, B, rot, caps="both")
    for y in (0.7, 2.5):  # неоновые пояса
        p.frustum(0, 0, y, y + 0.05, r + 0.012, r + 0.012, 8, N, rot, caps="none")
    for k in range(4):  # вертикальные полосы на четырёх гранях
        a = math.radians(90 * k)
        nrm = Vector((math.cos(a), 0, math.sin(a)))
        c = nrm * 0.30 + Vector((0, 1.6, 0))
        p.strip(c, 1.5, 0.06, Y, nrm, N)
    return [p.build()]


def doorway_frame(p, neon):
    wl, wr = -DOOR_W / 2, DOOR_W / 2
    for x0, x1 in ((-1.0, wl), (wr, 1.0)):
        plinth(p, x0, x1)
        panel(p, x0, x1, 0.3, 3.0)
    panel(p, wl, wr, DOOR_H, 3.0)
    cap(p, -1.0, 1.0)
    if neon:
        for x in (-0.85, 0.85):
            p.strip((x, 1.4, -0.82), 1.7, 0.05, Y, Z, N)
        p.strip((0, 2.7, -0.82), 1.0, 0.05, X, Z, N)
        p.strip((wl, 1.2, -0.9), 2.2, 0.05, Y, X, N)    # откосы проёма
        p.strip((wr, 1.2, -0.9), 2.2, 0.05, Y, -X, N)
        p.strip((0, DOOR_H, -0.9), DOOR_W - 0.1, 0.05, X, -Y, N)


def doorway(m):
    p = Part("Mesh", m)
    doorway_frame(p, True)
    return [p.build()]


def platform(m):
    p = Part("Mesh", m)
    p.box((0, 0.07, 0), (2, 0.14, 2), B, 0.03, "top+vert")
    p.box((0, 0.17, 0), (1.76, 0.06, 1.76), B, 0.03, "top")
    rot = math.radians(22.5)
    p.ring((0, 0.2, 0), 0.72, 0.82, 8, Y, N, rot=rot)
    p.ring((0, 0.2, 0), 0.38, 0.46, 8, Y, N, rot=rot)
    p.disc((0, 0.2, 0), 0.09, 8, Y, N, rot=rot)
    for nrm in (Z, -Z, X, -X):  # светящиеся полосы по бокам основания
        p.strip(nrm * 1.0 + Vector((0, 0.07, 0)), 1.2, 0.04, Y.cross(nrm), nrm, N)
    return [p.build()]


def lockdown_gate(m):
    """Решётка запертого выхода. Frame — всегда; Bars_Closed — видна, пока выход заперт (в открытом состоянии скрыта).
    Размер проёма и рамка те же, что у doorway, — ворота встают вместо него. Неон здесь всегда красный (bad)."""
    frame = Part("Frame", m)
    doorway_frame(frame, False)
    frame.box((0, 2.64, -0.78), (1.7, 0.28, 0.12), B, 0.025, "top")  # короб шторы над проёмом
    bars = Part("Bars_Closed", m)
    for k in range(-3, 4):
        bars.box((k * 0.2, DOOR_H / 2, -0.9), (0.05, DOOR_H, 0.05), N)
    for y in (0.8, 1.6):
        bars.box((0, y, -0.9), (DOOR_W + 0.1, 0.08, 0.07), B)
    bars.strip((0, 2.64, -0.71), 1.3, 0.06, X, Z, N)
    return [frame.build(), bars.build()]


def _bundle(p, pts, sides, seg_mat_top):
    """Пучок из трёх кабелей вдоль пути: две нижних жилы и верхняя (неоновая через одну секцию)."""
    r = 0.05
    offs = [(0.05, -0.055, B), (0.05, 0.055, B), (0.145, 0.0, "top")]
    for dy, dz, kind in offs:
        rings = []
        for c, side in pts:
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides + math.pi / 6
                ring.append(c + side * (dz + r * math.cos(a)) + Y * (dy + r * math.sin(a)))
            rings.append(ring)
        if kind == "top":
            p.loft(rings, lambda i: seg_mat_top(i), caps=True)
        else:
            p.loft(rings, B, caps=True)


def cable_straight(m):
    p = Part("Mesh", m)
    segs = 6
    pts = [(Vector((-1 + 2 * i / segs, 0, 0)), Z) for i in range(segs + 1)]
    _bundle(p, pts, 6, lambda i: N if i % 2 == 0 else B)
    p.box((0, 0.1, 0), (0.12, 0.2, 0.26), B, 0.012, "top+vert")  # колодка-хомут
    return [p.build()]


def cable_curve(m):
    """Поворот на 90 градусов: из середины края -X в середину края +Z, радиус 1 м вокруг угла (-1, +1)."""
    p = Part("Mesh", m)
    segs = 5
    pts = []
    for i in range(segs + 1):
        t = math.radians(90 * i / segs)
        c = Vector((-1 + math.sin(t), 0, 1 - math.cos(t)))
        side = Vector((-math.sin(t), 0, math.cos(t)))
        pts.append((c, side))
    _bundle(p, pts, 6, lambda i: N if i % 2 == 0 else B)
    t = math.radians(45)
    cc = Vector((-1 + math.sin(t), 0.1, 1 - math.cos(t)))
    with p.frame(Matrix.Translation(cc) @ Matrix.Rotation(-t, 4, "Y")):
        p.box((0, 0, 0), (0.12, 0.2, 0.26), B, 0.012, "top+vert")
    return [p.build()]


def tunnel_ring(m):
    """Сегмент цифрового тоннеля длиной 2 м вдоль Z (тайлится по Z). 12-угольник: внутри 2,0 м до граней, пол плоский на y=0."""
    p = Part("Mesh", m)
    cy = 2.0
    rot = math.radians(15)
    k = 1 / math.cos(math.radians(15))
    p.annulus_prism(cy, 2.0 * k, 2.25 * k, 12, -1.0, 1.0, B, rot)
    # неоновые пояса на внутренней стене у обоих торцов
    for z in (-0.9, 0.9):
        ang = [rot + 2 * math.pi * i / 12 for i in range(12)]
        r = 1.985 * k
        ring0 = [Vector((r * math.cos(a), cy + r * math.sin(a), z - 0.05)) for a in ang]
        ring1 = [Vector((r * math.cos(a), cy + r * math.sin(a), z + 0.05)) for a in ang]
        for i in range(12):
            i2 = (i + 1) % 12
            quad = [ring0[i], ring0[i2], ring1[i2], ring1[i]]
            mid = Vector((0, cy, z))
            c = sum(quad, Vector((0, 0, 0))) / 4
            p._face(p._next_gid(), quad, N, mid - c)
    # дорожки данных: полосы по длине на каждой второй грани (включая пол)
    for i in range(1, 12, 2):
        a = math.radians(30 * i)
        nrm = Vector((-math.cos(a), -math.sin(a), 0))  # внутрь, к оси
        pos = Vector((math.cos(a) * 2.0, cy + math.sin(a) * 2.0, 0))
        p.strip(pos, 1.5, 0.12, Z, nrm, N)
    return [p.build()]


ENV = [
    ("floor", floor),
    ("wall", wall),
    ("corner", corner),
    ("pillar", pillar),
    ("doorway", doorway),
    ("platform", platform),
    ("lockdown_gate", lockdown_gate),
    ("cable_straight", cable_straight),
    ("cable_curve", cable_curve),
    ("tunnel_ring", tunnel_ring),
]


def main():
    totals = {}
    for tier, spec in palette.TIERS.items():
        for name, fn in ENV:
            bc.reset_scene()
            body = bc.body_material("env_body_" + tier, spec["body"])
            neon_hex = palette.BAD if name == "lockdown_gate" else spec["neon"]
            neon = bc.neon_material("env_neon_" + ("BAD" if name == "lockdown_gate" else tier), neon_hex,
                                    palette.neon_strength(neon_hex, palette.NEON_ENV))
            objs = fn([body, neon])
            path = os.path.join(MODELS, "env", name + spec["suffix"] + ".glb")
            t = bc.export_glb(path, objs)
            if totals.setdefault(name, t) != t:
                raise RuntimeError("%s: число треугольников различается между тирами" % name)


if __name__ == "__main__":
    main()

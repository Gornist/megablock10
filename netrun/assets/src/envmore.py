"""Группа env, дополнительные модули: ворота блокировки, кольцо тоннеля, кабели, угол, платформа.
Запуск: blender -b --python envmore.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from env import WALL_H, curtain  # noqa: E402


def _corner_dots(size=2.0, z=0.006):
    """Четыре едва заметные точки по углам модуля: габарит симметричен, модули стыкуются по центру (origin «пол»)."""
    h = size / 2 - 0.03
    return [Vector((sx * h, sy * h, z)) for sx in (-1, 1) for sy in (-1, 1)]


GATE_X = (-0.40, -0.20, 0.0, 0.20, 0.40)  # прутья решётки по ширине проёма 1,04 м (как у exit_frame: косяки на ±0,52 м)
GATE_BAR = 0.09    # сечение прута, м: 9 см — читается с 6–8 м (штрих 1 см был бы меньше пикселя)
GATE_EDGE = 0.025  # светящаяся кромка по вертикальным рёбрам прута
GATE_H = 2.0       # высота закрытой решётки: как проём exit_frame
GATE_H_OPEN = 0.12  # втянутая решётка: пеньки у порога


def build_lockdown_gate(out, name="lockdown_gate", opened=False, seed=51):
    """Ворота блокировки (LOCKDOWN), ставятся на место проёма exit_frame (косяки и перемычку даёт он): пять непрозрачных прутьев 9 см (solid_dark) с яркой
    кромкой по вертикальным рёбрам — видимое тело вместо прежних красных штрихов, которые на очках не рисуются (streak_keep=0). Закрытые: высота 2 м,
    красная кромка (угроза: LOCKDOWN — единственное место, где красное в окружении разрешено). Открытые: те же прутья втянуты в пеньки 12 см,
    кромка бирюзовая, проход свободен. Origin на полу в центре, проход вдоль оси Z Godot. seed не используется (оставлен ради прежней сигнатуры)."""
    lib.reset()
    glow = lib.lin("cyan") if opened else lib.lin("threat")
    void = lib.lin("void")
    h = GATE_H_OPEN if opened else GATE_H
    half = GATE_BAR / 2
    bms = []
    for x in GATE_X:
        bm = lib.box_bm((GATE_BAR, GATE_BAR, h), center=(x, 0.0, h / 2))
        for ax in (0, 1):  # плоскости у вертикальных рёбер: полоска кромки GATE_EDGE по каждой из четырёх боковых граней
            for sgn in (-1, 1):
                co = [0.0, 0.0, 0.0]
                co[ax] = (x if ax == 0 else 0.0) + sgn * (half - GATE_EDGE)
                no = [0.0, 0.0, 0.0]
                no[ax] = 1.0
                bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=co, plane_no=no)
        lib.canon_faces(bm)
        bms.append(bm)

    def rgb(co):
        for x in GATE_X:
            if abs(co[0] - x) <= half + 1e-4:
                return glow if (abs(co[0] - x) > half - 1e-3 and abs(co[1]) > half - 1e-3) else void  # вертикальное ребро прута
        return void

    objs = [lib.obj_from_bm("gate_bars", lib.merge_bm(*bms), "solid_dark", glow, rgb_fn=rgb)]
    return lib.export(name, "env", objs, out, budget_tris=320, budget_points=0, budget_streaks=0, origin="floor",
                      notes=("закрыт: красные прутья 2 м" if not opened else "открыт: пеньки 12 см, бирюзовая кромка"))


def build_tunnel_ring(out, name="tunnel_ring", seed=61):
    """Сегмент цифрового тоннеля (переход CONNECT между узлами), 2 м вдоль оси Y Blender (Z Godot) и диаметром 3 м, тайлится встык по длине.
    Стенка — цилиндрический занавес вертикальных штрихов по окружности (высота штриха по хорде, поэтому по краям короче), два кольца из точек на
    торцах и россыпь точек по стенке. Пол тоннеля касается плоскости пола (центр на высоте 1,5 м). Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    R, cz = 1.5, 1.5
    st = []
    for i in range(100):
        a = math.tau * (i + rng.uniform(0.2, 0.8)) / 100
        if rng.random() < 0.08:
            continue
        x, z = R * math.cos(a), cz + R * math.sin(a)
        hh = rng.uniform(0.25, 0.7) * (0.35 + 0.65 * abs(math.cos(a)))  # у верха и низа окружности штрих короче
        hh = min(hh, z, 2 * cz - z)
        if hh < 0.05:
            continue
        st.append((Vector((x, rng.uniform(-0.95, 0.95), z)), rng.uniform(0.008, 0.016), hh / 2, rng.uniform(0.25, 0.8), ice if rng.random() < 0.06 else cy))
    objs = [lib.streak_set("tunnel_streaks", st, cy)]
    pts = []
    for y in (-0.98, 0.98):
        pts += [Vector((R * math.cos(a), y, cz + R * math.sin(a))) for a in (math.tau * k / 64 for k in range(64))]
    pts += [Vector((R * math.cos(a), rng.uniform(-0.9, 0.9), cz + R * math.sin(a))) for a in (rng.uniform(0, math.tau) for _ in range(60))]
    pts = [Vector((p.x, p.y, max(p.z, 0.01))) for p in pts]
    objs.append(lib.point_cloud("tunnel_pts", pts, cy, half_size=0.013, seed=seed, a_min=0.3, a_max=0.9))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=320, budget_streaks=120, origin="floor",
                      notes="сегмент 2 м вдоль оси Z Godot, диаметр 3 м; кладётся встык")


def build_cable(out, name="cable_straight", curved=False, seed=71):
    """Пучок кабелей (поток данных) лежит на полу модуля 2×2 м: пять прядей из цепочек точек вдоль пути, слегка расходятся и прижимаются (высота 3–25 см),
    по прядям бежит волна яркости (шейдер points). Линия — плотность точек, не рейка. cable_straight идёт вдоль Y через середины двух граней; cable_curve —
    четверть окружности радиусом 1 м между серединой южной и восточной граней. Углы модуля помечены едва видимыми точками (габарит симметричен)."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    pts = []
    for s in range(5):
        off = (s - 2) * 0.06
        n = 70
        for i in range(n):
            t = (i + rng.uniform(0.0, 1.0)) / n
            if curved:
                a = math.pi - t * math.pi / 2  # центр дуги в (1, −1): от (0, −1) к (1, 0)
                r = 1.0 + off
                x, y = 1.0 + r * math.cos(a), -1.0 + r * math.sin(a)
            else:
                x, y = off + 0.02 * math.sin(t * 9 + s), -1.0 + 2.0 * t
            z = 0.03 + 0.1 * (0.5 + 0.5 * math.sin(t * 5 + s * 1.3)) * rng.uniform(0.5, 1.0) + (0.1 if s in (1, 3) else 0.0) * rng.random()
            pts.append(Vector((x, y, z)))
    objs = [lib.point_cloud("cable_pts", pts, cy, half_size=0.012, seed=seed, a_min=0.4, a_max=1.0)]
    objs.append(lib.point_cloud("cable_corners", _corner_dots(), cy, half_size=0.006, seed=1, a_min=0.1, a_max=0.2, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=420, budget_streaks=0, origin="floor",
                      notes=("четверть окружности R 1 м" if curved else "вдоль Y через середины граней"))


def build_corner(out, name="corner", seed=81):
    """Угол стен 2×2 м: два занавеса штрихов вдоль южной и восточной граней модуля (как у wall), в углу пучок высоких штрихов с двумя белыми — колонна.
    Origin на полу в центре модуля. Стены смотрят внутрь комнаты: занавесы у граней −Y (Blender, юг) и +X (восток)."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    a = [(Vector((c.x, -1.0 + c.y * 0.3 + 0.1, c.z)), w, h, al) for c, w, h, al in curtain(rng, -0.97, 0.97, 100, WALL_H)]
    b = [(Vector((1.0 + c.y * 0.3 - 0.1, c.x, c.z)), w, h, al) for c, w, h, al in curtain(rng, -0.97, 0.97, 100, WALL_H)]
    objs = [lib.streak_set("corner_curtain", a + b, cy)]
    core = [(Vector((1.0 + rng.uniform(-0.05, 0.05), -1.0 + rng.uniform(-0.05, 0.05), hh / 2)), rng.uniform(0.01, 0.018), hh / 2, rng.uniform(0.5, 0.95), ice if i < 2 else cy)
            for i in range(9) for hh in [rng.uniform(1.8, 3.0)]]
    objs.append(lib.streak_set("corner_core", core, cy))
    objs.append(lib.point_cloud("corner_corners", _corner_dots(), cy, half_size=0.006, seed=1, a_min=0.1, a_max=0.2, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=40, budget_streaks=240, origin="floor",
                      notes="стены у южной (−Y Blender) и восточной (+X) граней, колонна в углу (+X, −Y)")


def build_platform(out, name="platform", seed=91):
    """Платформа 2×2 м высотой 0,3 м (возвышение в комнате, например под кресло или хранилище): чёрный блок 1,9×1,9 с подсвеченным верхним контуром,
    на верхней грани редкая сетка точек (шаг 0,4 м, ~20% пропусков), по бокам тихий занавес из 12 коротких штрихов на сторону, уходящих вниз к полу.
    Origin на полу в центре. В отличие от тайлов пола, платформа выступает в комнату намеренно (0,3 м)."""
    lib.reset()
    rng = random.Random(seed)
    cy, void = lib.lin("cyan"), lib.lin("void")
    blk = lib.box_bm((1.9, 1.9, 0.3), center=(0, 0, 0.15))
    glow = lib.lit_part(blk, 0.3, 0.014)
    objs = [lib.obj_from_bm("platform_block", blk, "solid_dark", cy, rgb_fn=lib.combine_rgb([glow], cy, void))]
    dots = [Vector((-0.8 + 0.4 * i, -0.8 + 0.4 * j, 0.306)) for i in range(5) for j in range(5) if rng.random() > 0.2]
    dots += _corner_dots(1.9, 0.017)
    objs.append(lib.point_cloud("platform_pts", dots, cy, half_size=0.016, seed=seed, a_min=0.4, a_max=0.9))
    st = []
    for side in range(4):
        for q in range(12):
            if rng.random() < 0.2:
                continue
            t = -0.9 + 1.8 * (q + 0.5) / 12
            x, y = [(t, -0.95), (0.95, t), (t, 0.95), (-0.95, t)][side]
            hh = rng.uniform(0.08, 0.26)
            st.append((Vector((x, y, 0.3 - hh / 2)), rng.uniform(0.006, 0.011), hh / 2, rng.uniform(0.12, 0.4)))
    objs.append(lib.streak_set("platform_streaks_hang", st, cy))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=40, budget_streaks=60, origin="floor",
                      notes="высота 0,3 м, выступает в комнату намеренно")


if __name__ == "__main__":
    o = lib.args()
    build_lockdown_gate(o, "lockdown_gate", False)
    build_lockdown_gate(o, "lockdown_gate_open", True)
    build_tunnel_ring(o)
    build_cable(o, "cable_straight", False)
    build_cable(o, "cable_curve", True)
    build_corner(o)
    build_platform(o)

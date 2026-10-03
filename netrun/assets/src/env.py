"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>

Стиль по референсам Blackwall (STYLE.md): свет живёт в вертикальных штрихах, поверхности чёрные и непрозрачные, пол — ряды точек.
Стена — занавес из штрихов (яркость плывёт вдоль стены) плюс несколько чёрных плит-перекрытий с каймой; сплошных реек и стеклянных
плиток нет. Граница модуля — яркие штрихи у краёв, остальное рваное."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def _env(x, phase=0.0):
    """Плавная огибающая яркости вдоль стены 0..1 (кластеры ярче, провалы темнее)."""
    return 0.5 + 0.5 * math.sin(x * 3.1 + 1.3 + phase) * math.sin(x * 7.7 + 0.4 + phase)


def curtain(rng, x0, x1, n, hmax, depth=0.12, w_range=(0.008, 0.02)):
    """Занавес штрихов от пола: рост высоты и яркости следуют огибающей. Возвращает [(центр, w, h, a)]."""
    out = []
    for i in range(n):
        x = x0 + (x1 - x0) * (i + rng.random() * 0.8) / n
        e = _env(x)
        full = hmax * rng.uniform(0.82, 1.0) * (0.8 + 0.2 * e)  # высота почти ровная (занавес), яркость плывёт по огибающей
        out.append((Vector((x, rng.uniform(-depth, depth), full / 2)), rng.uniform(*w_range), full / 2, 0.2 + 0.8 * e * rng.uniform(0.45, 1.0)))
    return out


def slabs(objs, rng, specs, rgb):
    """Чёрные непрозрачные плиты-перекрытия (solid_dark): закрывают штрихи за собой, кайма цветом rgb. specs [(w, h, x, глубина, z)]."""
    parts = [lib.box_bm((w, 0.04, h), center=(x, d, z)) for w, h, x, d, z in specs]
    objs.append(lib.obj_from_bm("slabs", lib.merge_bm(*parts), "solid_dark", rgb, alpha=0.9))


def build_wall(out):
    """Стена 2×2 м: занавес ~64 штрихов с плывущей яркостью, 6 ярких белых (две опоры по краям модуля), 3 чёрные плиты-перекрытия.
    Origin на полу в центре."""
    lib.reset()
    rng = random.Random(21)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = [lib.streak_set("wall_curtain", curtain(rng, -0.97, 0.97, 100, 2.0), cy)]
    accents = [(Vector((-0.99, 0, 1.0)), 0.012, 1.0, 1.0), (Vector((0.99, 0, 1.0)), 0.012, 1.0, 1.0)]
    for x in (-0.5, -0.1, 0.35, 0.72):
        hh = rng.uniform(0.7, 1.0)
        accents.append((Vector((x, rng.uniform(-0.08, 0.08), hh)), 0.011, hh, 0.95))
    objs.append(lib.streak_set("wall_accents", accents, ice))
    slabs(objs, rng, [(0.55, 0.8, -0.35, 0.10, 0.9), (0.4, 0.55, 0.45, -0.08, 1.2), (0.6, 0.4, 0.05, 0.06, 0.3)], cy)
    fill = lib.sample_box((0, 0, 1.0), (2.0, 0.4, 2.0), 50, seed=5, min_z=0.01)
    objs.append(lib.point_cloud("wall_pts", fill, cy, half_size=0.007, seed=11, a_min=0.15, a_max=0.5, on_floor=True))
    return lib.export("wall", "env", objs, out, budget_tris=300, budget_points=80, budget_streaks=120, origin="floor")


def build_doorway(out):
    """Проём 2×2 м (вход/выход): два занавеса по бокам, яркие белые штрихи — косяки, короткая бахрома сверху, ряды точек порога.
    Ширина прохода 1,1 м. Origin на полу в центре. Проход вдоль оси Z Godot."""
    lib.reset()
    rng = random.Random(8)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    side = curtain(rng, -0.98, -0.66, 18, 2.0) + curtain(rng, 0.66, 0.98, 18, 2.0)
    objs = [lib.streak_set("door_curtain", side, cy)]
    jambs = [(Vector((sx * d, 0, 1.0)), 0.016, 1.0, 1.0) for sx in (-1, 1) for d in (0.52, 0.57, 0.62)]
    fringe = [(Vector((-0.55 + i * 0.1, rng.uniform(-0.03, 0.03), 2.0 - hh)), 0.008, hh, 0.7) for i in range(12) for hh in [rng.uniform(0.2, 0.55)]]
    objs.append(lib.streak_set("door_jambs", jambs + fringe, ice))
    th = [Vector((x, y, 0.0)) for x in [-0.5 + i * 0.125 for i in range(9)] for y in (-0.06, 0.06)]
    objs.append(lib.point_cloud("door_threshold", th, ice, half_size=0.018, seed=7, a_min=0.8, a_max=1.0, on_floor=True))
    return lib.export("doorway", "env", objs, out, budget_tris=300, budget_points=40, budget_streaks=80, origin="floor")


def build_floor(out):
    """Плитка пола 2×2 м: ряды точек в решётке (как пол в референсе Blackwall), без плоскости и без рамок. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(2)
    cy = lib.lin("cyan")
    pts = [Vector((-0.875 + i * 0.25 + rng.uniform(-0.01, 0.01), -0.875 + j * 0.25 + rng.uniform(-0.01, 0.01), 0.0)) for i in range(8) for j in range(8)]
    objs = [lib.point_cloud("floor_dots", pts, cy, half_size=0.016, seed=2, a_min=0.4, a_max=0.9, on_floor=True)]
    return lib.export("floor", "env", objs, out, budget_tris=300, budget_points=70, origin="floor")


def build_pillar(out):
    """Колонна на углу: пучок высоких штрихов (два белых) и несколько точек у основания. Высота до 2,4 м. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(6)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    st = []
    for _ in range(9):
        hh = rng.uniform(0.7, 1.2)
        st.append((Vector((rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07), hh)), rng.uniform(0.01, 0.018), hh, rng.uniform(0.4, 0.9)))
    objs = [lib.streak_set("pillar_streaks", st, cy)]
    objs.append(lib.streak_set("pillar_core", [(Vector((0, 0, 1.1)), 0.012, 1.1, 1.0), (Vector((0.03, 0.02, 0.9)), 0.01, 0.9, 0.9)], ice))
    return lib.export("pillar", "env", objs, out, budget_tris=300, budget_streaks=16, origin="floor")


if __name__ == "__main__":
    o = lib.args()
    for f in (build_wall, build_doorway, build_floor, build_pillar):
        f(o)

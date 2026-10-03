"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>

Стиль по референсам Blackwall (STYLE.md): свет живёт в вертикальных штрихах, поверхности чёрные и непрозрачные, пол — ряды точек.
Стена — только занавес из штрихов (яркость плывёт вдоль стены); чёрные тайлы лежат на ПОЛУ, не на стенах; сплошных реек и
стеклянных плиток нет. Граница модуля — яркие штрихи у краёв, остальное рваное."""
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
    """Плитка пола 2×2 м: поле чёрных непрозрачных тайлов-блоков разной высоты (как в референсе cyan space), из их рёбер поднимаются
    короткие штрихи, в щелях редкие точки. Чёрные тайлы — только на полу. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(2)
    cy = lib.lin("cyan")
    tiles, streaks, edge = [], [], []
    for i in range(4):
        for j in range(4):
            cx, cyy = -0.75 + i * 0.5, -0.75 + j * 0.5
            hh = rng.uniform(0.02, 0.12)
            tiles.append(lib.box_bm((0.42, 0.42, hh), center=(cx, cyy, hh / 2)))
            for a, b in (((cx - 0.21, cyy - 0.21, hh), (cx + 0.21, cyy - 0.21, hh)), ((cx - 0.21, cyy - 0.21, hh), (cx - 0.21, cyy + 0.21, hh))):
                edge += lib.sample_line(a, b, 22, spread=0.004, seed=len(edge) + 1)  # две видимые грани тайла — цепочка частиц
            for _ in range(6):  # штрихи строго на рёбрах тайла
                if rng.random() < 0.5:
                    ex, ey = cx + rng.choice((-0.21, 0.21)), cyy + rng.uniform(-0.21, 0.21)
                else:
                    ex, ey = cx + rng.uniform(-0.21, 0.21), cyy + rng.choice((-0.21, 0.21))
                top = rng.uniform(0.12, 0.42)
                streaks.append((Vector((ex, ey, hh + top / 2)), rng.uniform(0.006, 0.012), top / 2, rng.uniform(0.3, 0.85)))
    objs = [lib.obj_from_bm("floor_tiles", lib.merge_bm(*tiles), "solid_dark", lib.lin("void"), alpha=1.0)]  # верх чёрный: кайма не нужна
    objs.append(lib.point_cloud("floor_edges", edge, cy, half_size=0.011, seed=4, a_min=0.5, a_max=1.0))
    objs.append(lib.streak_set("floor_streaks", streaks, cy))
    dots = [Vector((-0.75 + i * 0.5 + 0.25 + rng.uniform(-0.02, 0.02), -0.75 + j * 0.5 + 0.25 + rng.uniform(-0.02, 0.02), 0.0)) for i in range(3) for j in range(3)]
    objs.append(lib.point_cloud("floor_dots", dots, cy, half_size=0.016, seed=2, a_min=0.5, a_max=0.9, on_floor=True))
    return lib.export("floor", "env", objs, out, budget_tris=300, budget_points=340, budget_streaks=110, origin="floor")


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

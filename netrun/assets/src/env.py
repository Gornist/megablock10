"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>

Принципы: (1) граница модуля всегда обозначена, чтобы из модулей собиралась читаемая комната; (2) грани и линии — только
плотностью частиц (цепочки точек с разбросом), сплошных реек, стержней и рамок нет; (3) «рваность» внутри: фрагменты разной
глубины, пропуски, тусклые линии; яркие узлы — компактные кластеры точек."""
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def _clamp(points, hx=1.0, hy=0.25):
    """Точки не выходят за габарит модуля (иначе центр сдвигается и модули не стыкуются): |x| ≤ hx, |y| ≤ hy."""
    for p in points:
        p.x = max(-hx, min(hx, p.x))
        p.y = max(-hy, min(hy, p.y))
    return points


def _fragments(objs, name, P, rgb, layers=2):
    """Фрагменты-плитки P = [(w, h, x, глубина, z, плотность)] склеены по слоям: layers прозрачных оболочек на весь ассет."""
    panel = lambda p: lib.box_bm((p[0], 0.03, p[1]), center=(p[2], p[3], p[4]))

    def layer(k):
        parts = []
        for p in P:
            bm = panel(p)
            for v in bm.verts:
                v.co = v.co * (1.0 + k * 0.02)
            parts.append(bm)
        return lib.merge_bm(*parts)

    def dens(k):
        return lambda co: min(P, key=lambda p: (co.x - p[2]) ** 2 + (co.z - p[4]) ** 2)[5] * (1.0 - 0.7 * k)

    for k in range(layers):
        objs.append(lib.obj_from_bm(f"{name}_shell{k}", layer(k), "shell_soft", rgb, alpha_fn=dens(k), smooth=True))
    return panel


def _node(c, n=14, seed=1):
    """Яркий узел — компактный кластер точек."""
    return lib.sample_box(c, (0.05, 0.05, 0.05), n, seed=seed)


def build_wall(out):
    """Стена 2×2 м. Границы: низ, верх и боковые опоры — плотные цепочки частиц на всю длину. Внутри до 7 фрагментов
    разной глубины, 3 тусклые линии и 3 узла. Сплошных реек нет. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(21)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = []
    cell = 2.0 / 3.0
    P = []
    for ix in range(3):
        for iz in range(3):
            if rng.random() < 0.22 or len(P) >= 7:
                continue
            w, h = cell * rng.uniform(0.72, 0.97), cell * rng.uniform(0.72, 0.97)
            P.append((w, h, -1.0 + cell * (ix + 0.5) + rng.uniform(-0.04, 0.04), rng.uniform(-0.14, 0.14),
                      max(cell * (iz + 0.5) + rng.uniform(-0.04, 0.04), h / 2 + 0.04), rng.uniform(0.14, 0.34)))
    panel = _fragments(objs, "wall", P, cy)
    border = [((-1, 0, 0.0), (1, 0, 0.0)), ((-1, 0, 2.0), (1, 0, 2.0)), ((-0.99, 0, 0.0), (-0.99, 0, 2.0)), ((0.99, 0, 0.0), (0.99, 0, 2.0))]
    inner = [((x, rng.uniform(-0.08, 0.08), 0.03), (x, 0, 0.03 + hh)) for x, hh in ((-0.45, 1.2), (0.12, 0.8), (0.58, 1.55))]
    edge = lib.sample_lines(border, 40, spread=0.009, seed=3, min_z=0.005) + lib.sample_lines(inner, 22, spread=0.008, seed=9, min_z=0.005)
    edge += _node((-0.45, 0, 1.22), seed=1) + _node((0.58, 0.04, 1.57), seed=2) + _node((0.12, 0, 0.82), seed=3)
    objs.append(lib.point_cloud("wall_edge", _clamp(edge), cy, half_size=0.012, seed=3, a_min=0.6, a_max=1.0, on_floor=True))
    fill = []
    for p in P:
        fill += lib.sample_surface(panel(p), 20, seed=rng.randint(1, 999), push=0.16, min_z=0.01)
    fill += lib.sample_box((0, 0, 1.0), (2.0, 0.4, 2.0), 40, seed=5, min_z=0.01)
    objs.append(lib.point_cloud("wall_fill", _clamp(fill), cy, half_size=0.007, seed=11, a_min=0.12, a_max=0.5, on_floor=True))
    return lib.export("wall", "env", objs, out, budget_tris=300, budget_points=700, origin="floor")


def build_doorway(out):
    """Проём 2×2 м (вход/выход): косяки и перемычка — плотные линии частиц, крылья из фрагментов, яркий порог на полу.
    Ширина прохода 1,1 м. Origin на полу в центре. Проход вдоль оси Z Godot."""
    lib.reset()
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = []
    P = [(0.34, 0.9, -0.80, 0.05, 0.65, 0.26), (0.30, 0.5, -0.80, -0.08, 1.55, 0.18), (0.26, 0.4, -0.81, 0.10, 0.25, 0.14),
         (0.36, 0.7, 0.80, -0.06, 0.55, 0.22), (0.30, 0.8, 0.80, 0.07, 1.50, 0.28), (0.20, 0.3, 0.82, 0.0, 1.10, 0.12)]
    panel = _fragments(objs, "door", P, cy)
    frame = [((-0.55, 0, 0.0), (-0.55, 0, 2.0)), ((0.55, 0, 0.0), (0.55, 0, 2.0)), ((-0.6, 0, 1.97), (0.6, 0, 1.97)),
             ((-1.0, 0, 0.0), (-0.55, 0, 0.0)), ((0.55, 0, 0.0), (1.0, 0, 0.0)), ((-0.99, 0, 0.0), (-0.99, 0, 2.0)), ((0.99, 0, 0.0), (0.99, 0, 2.0))]
    objs.append(lib.point_cloud("door_edge", _clamp(lib.sample_lines(frame, 28, spread=0.009, seed=5, min_z=0.005)), ice, half_size=0.017, seed=5, a_min=0.7, a_max=1.0, on_floor=True))
    objs.append(lib.point_cloud("door_threshold", _clamp(lib.sample_line((-0.5, 0, 0.012), (0.5, 0, 0.012), 80, spread=0.008, seed=7, min_z=0.005)), ice, half_size=0.016, seed=7, a_min=0.85, a_max=1.0, on_floor=True))
    fill = []
    for p in P:
        fill += lib.sample_surface(panel(p), 16, seed=int(p[4] * 100), push=0.14, min_z=0.01)
    fill += lib.sample_box((0, 0, 1.0), (1.1, 0.3, 2.0), 30, seed=4, min_z=0.01)
    objs.append(lib.point_cloud("door_fill", _clamp(fill), cy, half_size=0.007, seed=3, a_min=0.12, a_max=0.5, on_floor=True))
    return lib.export("doorway", "env", objs, out, budget_tris=300, budget_points=520, origin="floor")


def build_floor(out):
    """Плитка пола 2×2 м: почти невидимая плоскость, границы плитки — цепочки частиц, на плоскости редкие точки.
    Сетка плиток даёт масштаб и направление. Origin на полу в центре."""
    lib.reset()
    cy = lib.lin("cyan")
    objs = lib.shell_stack(lambda: lib.box_bm((1.97, 1.97, 0.012), center=(0, 0, 0.006)), "floor", cy, layers=1, a_inner=0.06, a_outer=0.06, pivot=(0, 0, 0))
    h = 0.985
    border = [((-h, -h, 0.012), (h, -h, 0.012)), ((-h, h, 0.012), (h, h, 0.012)), ((-h, -h, 0.012), (-h, h, 0.012)), ((h, -h, 0.012), (h, h, 0.012))]
    objs.append(lib.point_cloud("floor_edge", lib.sample_lines(border, 26, spread=0.008, seed=2, min_z=0.012), cy, half_size=0.011, seed=2, a_min=0.45, a_max=0.9, on_floor=True))
    objs.append(lib.point_cloud("floor_fill", lib.sample_box((0, 0, 0.012), (1.9, 1.9, 0.0), 50, seed=3, min_z=0.012), cy, half_size=0.006, seed=3, a_min=0.1, a_max=0.4, on_floor=True))
    return lib.export("floor", "env", objs, out, budget_tris=300, budget_points=320, origin="floor")


def build_pillar(out):
    """Колонна на углу комнаты: мягкий объём (оболочки), яркая вертикаль и узел наверху — из частиц. Высота 2,2 м. Origin на полу в центре."""
    lib.reset()
    cy = lib.lin("cyan")
    objs = lib.shell_stack(lambda: lib.box_bm((0.3, 0.3, 2.2), bevel=0.04, center=(0, 0, 1.1)), "pillar", cy, layers=2, grow=0.05, a_inner=0.14, a_outer=0.04, pivot=(0, 0, 0))
    line = lib.sample_line((0, 0, 0.0), (0, 0, 2.2), 70, spread=0.012, seed=6, min_z=0.005) + _node((0, 0, 2.27), n=24, seed=4)
    objs.append(lib.point_cloud("pillar_edge", line, cy, half_size=0.012, seed=6, a_min=0.6, a_max=1.0, on_floor=True))
    objs.append(lib.point_cloud("pillar_fill", lib.sample_box((0, 0, 1.1), (0.4, 0.4, 2.2), 40, seed=7, min_z=0.01), cy, half_size=0.006, seed=7, a_min=0.1, a_max=0.4, on_floor=True))
    return lib.export("pillar", "env", objs, out, budget_tris=300, budget_points=260, origin="floor")


def build_dust(out):
    """Облако «цифровой пыли» и коротких штрихов из точек для глубины между камерой и модулями. Origin в центре."""
    lib.reset()
    rng = random.Random(33)
    cy = lib.lin("cyan")
    dashes = []
    for i in range(16):
        c = Vector((rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4)))
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized() * rng.uniform(0.05, 0.18)
        dashes += lib.sample_line(c - d, c + d, 70, spread=0.004, seed=100 + i)
    objs = [lib.point_cloud("dust_dashes", dashes, cy, half_size=0.0055, seed=1, a_min=0.2, a_max=0.7)]
    objs.append(lib.point_cloud("dust_pts", lib.sample_box((0, 0, 0), (3.0, 3.0, 3.0), 400, seed=9), cy, half_size=0.006, seed=9, a_min=0.1, a_max=0.6))
    return lib.export("dust", "env", objs, out, budget_tris=300, budget_points=700, origin="center")


if __name__ == "__main__":
    o = lib.args()
    for f in (build_wall, build_doorway, build_floor, build_pillar, build_dust):
        f(o)

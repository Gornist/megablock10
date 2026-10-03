"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>

Принцип читаемости пространства: каждый модуль держит свою границу сплошными рейками и опорами (пол и потолок видны всегда),
а «рваность» — только внутри: фрагменты разной глубины, пропуски, тусклые колонны. Тогда из модулей собирается понятная комната,
а не россыпь декоративных обломков."""
import os
import random
import sys

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


def build_wall(out):
    """Стена 2×2 м. Границы модуля — сплошные: нижняя и верхняя рейки на всю ширину, опоры по краям. Внутри: до 7 фрагментов
    разной глубины, 3 тусклые колонны и 3 ярких узла; ~75% формы почти не светится. Origin на полу в центре."""
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
    bars = [lib.box_bm((2.0, 0.025, 0.025), center=(0, 0, 0.0125)), lib.box_bm((2.0, 0.025, 0.025), center=(0, 0, 1.9875)),
            lib.box_bm((0.035, 0.035, 2.0), center=(-0.9825, 0, 1.0)), lib.box_bm((0.035, 0.035, 2.0), center=(0.9825, 0, 1.0))]
    for x, hh in ((-0.45, 1.2), (0.12, 0.8), (0.58, 1.55)):
        bars.append(lib.box_bm((0.02, 0.02, hh), center=(x, rng.uniform(-0.08, 0.08), hh / 2 + 0.03)))
    objs.append(lib.obj_from_bm("wall_lines", lib.merge_bm(*bars), "glow_edge", cy, alpha_fn=lambda co: 0.22 + 0.4 * min(max(co.z, 0) / 2.0, 1.0)))
    nodes = [lib.box_bm((0.06, 0.06, 0.06), center=c) for c in ((-0.45, 0.0, 1.22), (0.58, 0.04, 1.57), (0.12, 0.0, 0.82))]
    objs.append(lib.obj_from_bm("wall_nodes", lib.merge_bm(*nodes), "glow_edge", ice, alpha=0.95))
    pts = []
    for p in P:
        pts += lib.sample_surface(panel(p), 36, seed=rng.randint(1, 999), push=0.16, min_z=0.01)
    pts += lib.sample_box((0, 0, 1.0), (2.0, 0.4, 2.0), 50, seed=5, min_z=0.01)
    objs.append(lib.point_cloud("wall_pts", _clamp(pts[:400]), cy, half_size=0.007, seed=11, a_min=0.2, a_max=0.9))
    return lib.export("wall", "env", objs, out, budget_tris=300, budget_points=400, origin="floor")


def build_doorway(out):
    """Проём 2×2 м (вход/выход): два косяка, перемычка, крылья из фрагментов по бокам, яркая «пороговая» планка на полу.
    Ширина прохода 1,1 м. Origin на полу в центре. Проход направлен вдоль оси Z Godot."""
    lib.reset()
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = []
    P = [(0.34, 0.9, -0.80, 0.05, 0.65, 0.26), (0.30, 0.5, -0.80, -0.08, 1.55, 0.18), (0.26, 0.4, -0.81, 0.10, 0.25, 0.14),
         (0.36, 0.7, 0.80, -0.06, 0.55, 0.22), (0.30, 0.8, 0.80, 0.07, 1.50, 0.28), (0.20, 0.3, 0.82, 0.0, 1.10, 0.12)]
    panel = _fragments(objs, "door", P, cy)
    frame = [lib.box_bm((0.12, 0.12, 2.0), center=(-0.55, 0, 1.0)), lib.box_bm((0.12, 0.12, 2.0), center=(0.55, 0, 1.0)),
             lib.box_bm((1.22, 0.12, 0.08), center=(0, 0, 1.96)),
             lib.box_bm((0.45, 0.025, 0.025), center=(-0.78, 0, 0.0125)), lib.box_bm((0.45, 0.025, 0.025), center=(0.78, 0, 0.0125))]
    objs.append(lib.obj_from_bm("door_frame", lib.merge_bm(*frame), "glow_edge", cy, alpha_fn=lambda co: 0.35 + 0.35 * min(max(co.z, 0) / 2.0, 1.0)))
    objs.append(lib.obj_from_bm("door_threshold", lib.box_bm((1.0, 0.05, 0.012), center=(0, 0, 0.006)), "glow_edge", ice, alpha=0.9))
    pts = []
    for p in P:
        pts += lib.sample_surface(panel(p), 20, seed=int(p[4] * 100), push=0.14, min_z=0.01)
    pts += lib.sample_box((0, 0, 1.0), (1.1, 0.3, 2.0), 40, seed=4, min_z=0.01)
    objs.append(lib.point_cloud("door_pts", _clamp(pts[:240]), cy, half_size=0.007, seed=3, a_min=0.2, a_max=0.9))
    return lib.export("doorway", "env", objs, out, budget_tris=300, budget_points=240, origin="floor")


def build_floor(out):
    """Плитка пола 2×2 м: почти невидимая плоскость, рамка по краям и россыпь точек. Сетка плиток даёт масштаб и направление.
    Origin на полу в центре."""
    lib.reset()
    cy = lib.lin("cyan")
    objs = lib.shell_stack(lambda: lib.box_bm((1.97, 1.97, 0.012), center=(0, 0, 0.006)), "floor", cy, layers=1, a_inner=0.07, a_outer=0.07, pivot=(0, 0, 0))
    edge = [lib.box_bm((1.97, 0.02, 0.012), center=(0, -0.985, 0.006)), lib.box_bm((1.97, 0.02, 0.012), center=(0, 0.985, 0.006)),
            lib.box_bm((0.02, 1.97, 0.012), center=(-0.985, 0, 0.006)), lib.box_bm((0.02, 1.97, 0.012), center=(0.985, 0, 0.006))]
    objs.append(lib.obj_from_bm("floor_frame", lib.merge_bm(*edge), "glow_edge", cy, alpha=0.3))
    objs.append(lib.point_cloud("floor_pts", lib.sample_box((0, 0, 0.012), (1.9, 1.9, 0.0), 90, seed=2, min_z=0.012), cy, half_size=0.006, seed=2, a_min=0.15, a_max=0.6))
    return lib.export("floor", "env", objs, out, budget_tris=300, budget_points=120, origin="floor")


def build_pillar(out):
    """Колонна на углу комнаты: тонкий яркий стержень, мягкий объём вокруг и узел наверху. Высота 2,2 м. Origin на полу в центре."""
    lib.reset()
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = lib.shell_stack(lambda: lib.box_bm((0.3, 0.3, 2.2), bevel=0.04, center=(0, 0, 1.1)), "pillar", cy, layers=2, grow=0.05, a_inner=0.16, a_outer=0.05, pivot=(0, 0, 0))
    objs.append(lib.obj_from_bm("pillar_core", lib.box_bm((0.05, 0.05, 2.2), center=(0, 0, 1.1)), "glow_edge", cy, alpha_fn=lambda co: 0.3 + 0.5 * min(max(co.z, 0) / 2.2, 1.0)))
    objs.append(lib.obj_from_bm("pillar_node", lib.box_bm((0.14, 0.14, 0.14), center=(0, 0, 2.27)), "glow_edge", ice, alpha=0.95))
    objs.append(lib.point_cloud("pillar_pts", lib.sample_box((0, 0, 1.1), (0.4, 0.4, 2.2), 70, seed=6, min_z=0.01), cy, half_size=0.006, seed=6, a_min=0.2, a_max=0.8))
    return lib.export("pillar", "env", objs, out, budget_tris=300, budget_points=120, origin="floor")


def build_dust(out):
    """Облако «цифровой пыли» и осколков для глубины между камерой и модулями: тусклые точки и редкие тонкие пластины. Origin в центре."""
    lib.reset()
    rng = random.Random(33)
    cy = lib.lin("cyan")
    slivers = []
    for _ in range(16):
        w, h = rng.uniform(0.06, 0.35), rng.uniform(0.006, 0.02)
        bm = lib.box_bm((w, 0.004, h))
        lib.xform_bm(bm, rot=(rng.uniform(0, 90), rng.uniform(-30, 30), rng.uniform(0, 360)), offset=(rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4)))
        slivers.append(bm)
    objs = [lib.obj_from_bm("dust_slivers", lib.merge_bm(*slivers), "glow_edge", cy, alpha=0.14)]
    objs.append(lib.point_cloud("dust_pts", lib.sample_box((0, 0, 0), (3.0, 3.0, 3.0), 600, seed=9), cy, half_size=0.006, seed=9, a_min=0.1, a_max=0.6))
    return lib.export("dust", "env", objs, out, budget_tris=300, budget_points=600, origin="center")


if __name__ == "__main__":
    o = lib.args()
    for f in (build_wall, build_doorway, build_floor, build_pillar, build_dust):
        f(o)

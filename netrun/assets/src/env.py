"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_wall(out):
    """Стена 2×2 м как «массив данных»: не плита и не забор, а плавающие фрагменты разной глубины и плотности, незавершённые
    линии и несколько ярких узлов. ~75% формы почти не светится. Origin на полу в центре: нижняя рейка на всю ширину держит модуль."""
    lib.reset()
    rng = random.Random(21)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = []
    # фрагменты: сетка 3×3, часть выпала, глубина и размер разные; яркость у каждого своя. Склеены по слоям (2 слоя на весь ассет).
    cell = 2.0 / 3.0
    P = []  # (w, h, x, глубина, z, плотность)
    for ix in range(3):
        for iz in range(3):
            if rng.random() < 0.34:
                continue
            w = cell * rng.uniform(0.62, 0.95)
            h = cell * rng.uniform(0.62, 0.95)
            x = -1.0 + cell * (ix + 0.5) + rng.uniform(-0.05, 0.05)
            z = max(cell * (iz + 0.5) + rng.uniform(-0.05, 0.05), h / 2 + 0.03)
            P.append((w, h, x, rng.uniform(-0.16, 0.16), z, rng.uniform(0.12, 0.34)))
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

    for k in range(2):
        objs.append(lib.obj_from_bm(f"wall_shell{k}", layer(k), "shell_soft", cy, alpha_fn=dens(k), smooth=True))
    # линии: нижняя рейка целиком (тусклая), верхняя обрывается, колонны разной высоты, не симметрично
    bars = [lib.box_bm((2.0, 0.025, 0.025), center=(0, 0, 0.0125)), lib.box_bm((1.1, 0.025, 0.025), center=(-0.45, 0, 1.97))]
    for x, hh in ((-0.78, 1.3), (-0.12, 0.7), (0.5, 1.65), (0.93, 0.95)):
        bars.append(lib.box_bm((0.025, 0.025, hh), center=(x, rng.uniform(-0.1, 0.1), hh / 2 + 0.03)))
    objs.append(lib.obj_from_bm("wall_lines", lib.merge_bm(*bars), "glow_edge", cy, alpha_fn=lambda co: 0.18 + 0.5 * min(max(co.z, 0) / 2.0, 1.0)))
    # узлы: несколько ярких точек-кубиков, всё остальное тусклое
    nodes = [lib.box_bm((0.06, 0.06, 0.06), center=c) for c in ((-0.78, 0.0, 1.35), (0.5, 0.04, 1.7), (-0.12, 0.0, 0.75), (0.93, -0.05, 1.0), (-0.45, 0.0, 1.97))]
    objs.append(lib.obj_from_bm("wall_nodes", lib.merge_bm(*nodes), "glow_edge", ice, alpha=0.95))
    # точки: гуще у фрагментов, шире разлёт, часть дрейфует в пустоте
    pts = []
    for p in P:
        pts += lib.sample_surface(panel(p), 38, seed=rng.randint(1, 999), push=0.18, min_z=0.01)
    pts += lib.sample_box((0, 0, 1.0), (2.0, 0.4, 2.0), 60, seed=5, min_z=0.01)
    objs.append(lib.point_cloud("wall_pts", pts[:400], cy, half_size=0.007, seed=11, a_min=0.2, a_max=0.9))
    return lib.export("wall", "env", objs, out, budget_tris=300, budget_points=400, origin="floor")


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
    out = lib.args()
    build_wall(out)
    build_dust(out)

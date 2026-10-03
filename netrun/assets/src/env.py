"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_wall(out):
    """Стена 2×2 м: не кирпич, а «массив данных» — мягкая плита, тонкие светящиеся колонны и рамка, россыпь точек. Origin на полу в центре."""
    lib.reset()
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    slab = lambda: lib.box_bm((2.0, 0.12, 2.0), bevel=0.04, center=(0, 0, 1.0))
    objs = lib.shell_stack(slab, "wall", cy, layers=3, grow=0.015, a_inner=0.5, a_outer=0.1)
    bars = [lib.box_bm((2.0, 0.03, 0.03), center=(0, 0, 0.015)), lib.box_bm((2.0, 0.03, 0.03), center=(0, 0, 1.985))]
    bars += [lib.box_bm((0.03, 0.03, 1.7), center=(-0.9 + i * 0.257, 0, 1.0)) for i in range(8)]
    objs.append(lib.obj_from_bm("wall_edges", lib.merge_bm(*bars), "glow_edge", ice, alpha_fn=lambda co: 0.35 + 0.65 * min(co.z / 2.0, 1.0)))
    objs.append(lib.point_cloud("wall_pts", lib.sample_surface(slab(), 380, seed=11, push=0.05, min_z=0.01), cy, half_size=0.008, seed=11))
    return lib.export("wall", "env", objs, out, budget_tris=300, budget_points=400, origin="floor")


if __name__ == "__main__":
    build_wall(lib.args())

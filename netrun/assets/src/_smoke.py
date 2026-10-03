"""Дымовой тест lib.py: оболочки + облако точек, экспорт, проверка чтения. Не ассет, в MANIFEST не попадает."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

out = lib.args()
lib.reset()
cy = lib.lin("cyan")
body = lambda: lib.box_bm((0.3, 0.3, 0.5), bevel=0.05, center=(0, 0, 0.25))
objs = lib.shell_stack(body, "smoke", cy, layers=3, pivot=(0, 0, 0))  # растёт от пола, ниже пола не уходит
objs.append(lib.point_cloud("smoke_pts", lib.sample_surface(body(), 200, seed=3, push=0.06, min_z=0.006), cy, half_size=0.006))
lib.export("_smoke", "env", objs, out, budget_tris=300, budget_points=400)

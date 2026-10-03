"""Группа ice: существа Сети. Запуск: blender -b --python ice.py -- --out <корень netrun/assets>"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_soft_ice(out):
    """Soft ICE: строгая симметрия, не человек. Парящее ядро, вертикальное кольцо, 4 шипа, красная кайма на полу и аура точек.
    Читается силуэтом: «крест из шипов вокруг кольца». Анимации idle/patrol — следующим этапом (скелет ≤ 20 костей)."""
    lib.reset()
    red, hot = lib.lin("threat"), lib.lin("threat_hot")
    core_z = 1.15
    core = lambda: lib.ico_bm(0.22, subdiv=1, scale=(1, 1, 1.25), center=(0, 0, core_z))
    objs = lib.shell_stack(core, "ice_core", red, layers=3, grow=0.14, a_inner=0.85, a_outer=0.2, pivot=(0, 0, core_z))
    objs.append(lib.obj_from_bm("ice_dark", lib.ico_bm(0.16, subdiv=1, scale=(1, 1, 1.25), center=(0, 0, core_z)), "solid_dark", red, alpha=0.6))
    ring = lib.xform_bm(lib.band_bm(0.46, 0.05, segments=16), rot=(90, 0, 0), offset=(0, 0, core_z))
    spikes = [
        lib.xform_bm(lib.cone_bm(0.07, 0.0, 0.42, segments=5), rot=(0, 90, a), offset=(0.62 * math.cos(math.radians(a)), 0.62 * math.sin(math.radians(a)), core_z))
        for a in (0, 90, 180, 270)
    ]
    floor_ring = lib.band_bm(0.38, 0.02, segments=16, center=(0, 0, 0.01))
    objs.append(lib.obj_from_bm("ice_edges", lib.merge_bm(ring, *spikes, floor_ring), "glow_edge", hot, alpha_fn=lambda co: 0.5 + 0.5 * min(co.z / 1.2, 1.0)))
    aura = lib.sample_surface(lib.ico_bm(0.5, subdiv=2, scale=(1, 1, 1.3), center=(0, 0, core_z)), 700, seed=5, push=0.2)
    objs.append(lib.point_cloud("ice_pts", aura, red, half_size=0.012, seed=5))
    return lib.export("soft_ice", "ice", objs, out, budget_tris=3000, budget_points=1500, origin="floor", notes="без анимаций (пилот)")


if __name__ == "__main__":
    build_soft_ice(lib.args())

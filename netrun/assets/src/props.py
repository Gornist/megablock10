"""Группа props: предметы узла. Запуск: blender -b --python props.py -- --out <корень netrun/assets>"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_shard(out):
    """Шард — лут: маленький вытянутый светящийся кристалл (8 см), origin в центре. Зашифрованный вариант — тот же меш, другой tint."""
    lib.reset()
    white = lib.lin("ice_white")
    crystal = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.055, 0.055, 0.11))
    objs = lib.shell_stack(crystal, "shard", white, layers=3, grow=0.18, a_inner=0.9, a_outer=0.25)
    objs.append(lib.point_cloud("shard_pts", lib.sample_surface(crystal(), 70, seed=7, push=0.05), lib.lin("cyan"), half_size=0.003, seed=7))
    return lib.export("shard", "props", objs, out, budget_tris=300, budget_points=120, origin="center")


if __name__ == "__main__":
    build_shard(lib.args())

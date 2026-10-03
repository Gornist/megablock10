"""Группа ice: существа Сети. Запуск: blender -b --python ice.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_soft_ice(out):
    """Soft ICE: облако красных штрихов (как «сущности» в референсе Blackwall): плотное основание, рваный верх, наклон,
    раскалённое ядро и несколько высоких игл. Без конусов и геометрии. Origin «у ног» на полу. Анимации — следующим этапом."""
    lib.reset()
    rng = random.Random(14)
    red, hot = lib.lin("threat"), lib.lin("threat_hot")
    body, core = [], []
    for _ in range(150):
        ang, r = rng.uniform(0, math.tau), 0.5 * math.sqrt(rng.random())
        hh = max(0.15, 2.0 * (1.0 - (r / 0.5) ** 1.4) * rng.uniform(0.45, 1.0))
        x, y = r * math.cos(ang) + 0.16 * hh, 0.7 * r * math.sin(ang)
        body.append((Vector((x, y, hh / 2)), rng.uniform(0.01, 0.022), hh / 2, rng.uniform(0.25, 0.8)))
    for _ in range(26):
        ang, r = rng.uniform(0, math.tau), 0.14 * math.sqrt(rng.random())
        hh = rng.uniform(1.0, 1.7)
        core.append((Vector((r * math.cos(ang) + 0.16 * hh, 0.7 * r * math.sin(ang), hh / 2)), rng.uniform(0.012, 0.02), hh / 2, rng.uniform(0.7, 1.0)))
    for dx, hh in ((0.28, 2.15), (0.05, 2.0), (0.4, 1.8)):  # иглы: высокие тонкие штрихи над облаком
        core.append((Vector((dx, rng.uniform(-0.05, 0.05), hh / 2)), 0.009, hh / 2, 0.9))
    objs = [lib.streak_set("ice_body", body, red), lib.streak_set("ice_core", core, hot)]
    haze = [Vector((0.55 * math.sqrt(rng.random()) * math.cos(a), 0.4 * math.sqrt(rng.random()) * math.sin(a), 0.0)) for a in [rng.uniform(0, math.tau) for _ in range(160)]]
    objs.append(lib.point_cloud("ice_haze", haze, red, half_size=0.075, seed=3, a_min=0.1, a_max=0.35, on_floor=True))
    return lib.export("soft_ice", "ice", objs, out, budget_tris=300, budget_points=200, budget_streaks=200, origin="feet", notes="без анимаций (пилот)")


if __name__ == "__main__":
    build_soft_ice(lib.args())

"""Группа env: свободная рамка выхода `exit_frame` (замена doorway без стен). Запуск: blender -b --python exit_frame.py -- --out <корень netrun/assets>"""
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from env import curtain  # noqa: E402

JAMB_X = (0.52, 0.57, 0.62)  # три белых косяка с каждой стороны: те же, что у doorway и lockdown_gate (проём между ними 1,04 м)
OPEN_H = 2.0                 # высота проёма: как у lockdown_gate (решётка и косяки 2 м)
POST_H = 2.4                 # высота занавесов-столбов по бокам


def build_exit_frame(out, name="exit_frame", seed=14):
    """Рамка выхода без стен (STYLE.md п. 1, 2): два столба-занавеса из штрихов по бокам (высота 2,4 м, по 0,32 м шириной, зазор между ними — ПУСТОЙ проём
    1,04 м, сквозь него видно дальше), три белых косяка с каждой стороны (ice_white, 2 м — тот же проём, что у `lockdown_gate`, клиент подставляет
    ворота на то же место при LOCKDOWN), перемычка — тонкая линия точек ice_white на 2 м, на полу порог: чёрная плита 1,24×0,15×0,03 м с яркой кромкой
    и два ряда белых точек. Боковых стен нет. Красного нет. Origin на полу в центре проёма, «перед» — Godot −Z (проход вдоль оси Z, рамка симметрична)."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    objs = []
    for side, (x0, x1) in (("l", (-0.98, -0.66)), ("r", (0.66, 0.98))):
        post = curtain(rng, x0, x1, 15, POST_H * 1.08, depth=0.12, w_range=(0.008, 0.016), p_gap=0.06)
        sx = -1 if side == "l" else 1
        jambs = [(Vector((sx * d, 0, OPEN_H / 2)), 0.016, OPEN_H / 2, 1.0, ice) for d in JAMB_X]  # пятый элемент — свой цвет штриха
        objs.append(lib.streak_set("exit_post_" + side, post + jambs, cy))
    lintel = [Vector((-0.62 + 1.24 * (i + 0.5) / 32, rng.uniform(-0.01, 0.01), OPEN_H + 0.01)) for i in range(32) if rng.random() > 0.06]
    objs.append(lib.point_cloud("exit_lintel", lintel, ice, half_size=0.018, seed=seed, a_min=0.8, a_max=1.0))
    T = 0.03
    plate = lib.box_bm((1.24, 0.15, T), center=(0, 0, T / 2))
    g = lib.lit_part(plate, T, 0.014)
    rim = tuple(c * 0.9 for c in ice)
    objs.append(lib.obj_from_bm("exit_sill", plate, "solid_dark", cy, rgb_fn=lambda co: rim if g(co) else void))
    sill_pts = [Vector((-0.55 + i * 0.1375, y, T + 0.004)) for i in range(9) for y in (-0.045, 0.045)]
    objs.append(lib.point_cloud("exit_threshold", sill_pts, ice, half_size=0.016, seed=seed + 1, a_min=0.85, a_max=1.0))
    return lib.export(name, "env", objs, out, budget_tris=120, budget_points=150, budget_streaks=140, origin="floor",
                      notes="проём 1,04×2 м как у lockdown_gate, столбы-занавесы 2,4 м, перемычка точками, порог 1,24×0,15 м; без стен; красного нет")


if __name__ == "__main__":
    build_exit_frame(lib.args())

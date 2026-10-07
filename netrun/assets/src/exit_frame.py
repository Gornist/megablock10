"""Группа env: свободная рамка выхода `exit_frame` (замена doorway без стен). Запуск: blender -b --python exit_frame.py -- --out <корень netrun/assets>"""
import os
import random
import sys

import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from env import curtain  # noqa: E402

OPEN_X = 0.52                # половина проёма: как у doorway и lockdown_gate (проём 1,04 м)
OPEN_H = 2.0                 # высота проёма: как у lockdown_gate (решётка и косяки 2 м)
POST_H = 2.4                 # высота занавесов-столбов по бокам
BAR = 0.14                   # сечение брусьев рамки: 14 см — на 8 м ≈ 5 px при 2160 px на глаз (штрих 3 см был бы 1–2 px)
EDGE = 0.03                  # ширина светящейся кромки бруса


def _lit_bar(center, size, glow, dark):
    """Непрозрачный брус с яркой кромкой по всем рёбрам (как укрытие `cover`): плоскости нарезаны в EDGE от граней, свет вершин только у рёбер. Возвращает (bmesh, rgb_fn)."""
    bm = lib.box_bm(size, center=center)
    for ax in range(3):
        for sgn in (-1, 1):
            co = [0.0, 0.0, 0.0]
            co[ax] = center[ax] + sgn * (size[ax] / 2 - EDGE)
            no = [0.0, 0.0, 0.0]
            no[ax] = 1.0
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=co, plane_no=no)
    lib.canon_faces(bm)

    def rgb(co):
        on = sum(abs(co[i] - center[i]) > size[i] / 2 - 1e-3 for i in range(3))
        return glow if on >= 2 else dark  # два крайних измерения = ребро

    return bm, rgb


def build_exit_frame(out, name="exit_frame", seed=14):
    """Рамка выхода без стен (STYLE.md п. 1, 2): два столба-занавеса из штрихов по бокам (высота 2,4 м, по 0,32 м шириной, зазор между ними — ПУСТОЙ проём
    1,04 м, сквозь него видно дальше), два косяка и перемычка — непрозрачные брусья 14 см с яркой кромкой ice_white (тот же проём, что у `lockdown_gate`, клиент подставляет
    ворота на то же место при LOCKDOWN; тонкие штрихи 3 см на 6–10 м были меньше пикселя), на полу порог: чёрная плита 1,24×0,15×0,03 м с яркой кромкой
    и два ряда белых точек. Боковых стен нет. Красного нет. Origin на полу в центре проёма, «перед» — Godot −Z (проход вдоль оси Z, рамка симметрична)."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    objs = []
    for side, (x0, x1) in (("l", (-0.98, -0.66)), ("r", (0.66, 0.98))):
        post = curtain(rng, x0, x1, 15, POST_H * 1.08, depth=0.12, w_range=(0.008, 0.016), p_gap=0.06)
        sx = -1 if side == "l" else 1
        objs.append(lib.streak_set("exit_post_" + side, post, cy))
        bar, rgb = _lit_bar((sx * (OPEN_X + BAR / 2), 0.0, (OPEN_H + BAR) / 2), (BAR, BAR, OPEN_H + BAR), ice, void)  # косяк: брус от пола до верха перемычки
        objs.append(lib.obj_from_bm("exit_bar_" + side, bar, "solid_dark", ice, rgb_fn=rgb, smooth=True))  # smooth: нормали для обводки силуэта (fringe.gdshader)
    top, rgb = _lit_bar((0.0, 0.0, OPEN_H + BAR / 2), (2 * OPEN_X + 2 * BAR, BAR, BAR), ice, void)  # перемычка поверх проёма (выше 2,0 м)
    objs.append(lib.obj_from_bm("exit_bar_top", top, "solid_dark", ice, rgb_fn=rgb, smooth=True))
    T = 0.03
    plate = lib.box_bm((1.24, 0.15, T), center=(0, 0, T / 2))
    g = lib.lit_part(plate, T, 0.014)
    rim = tuple(c * 0.9 for c in ice)
    objs.append(lib.obj_from_bm("exit_sill", plate, "solid_dark", cy, rgb_fn=lambda co: rim if g(co) else void))
    sill_pts = [Vector((-0.55 + i * 0.1375, y, T + 0.004)) for i in range(9) for y in (-0.045, 0.045)]
    objs.append(lib.point_cloud("exit_threshold", sill_pts, ice, half_size=0.016, seed=seed + 1, a_min=0.85, a_max=1.0))
    return lib.export(name, "env", objs, out, budget_tris=450, budget_points=60, budget_streaks=140, origin="floor",
                      notes="проём 1,04×2 м как у lockdown_gate, столбы-занавесы 2,4 м, три светящихся бруса 14 см (косяки и перемычка, читаются с 6–10 м), порог 1,24×0,15 м; без стен; красного нет")


if __name__ == "__main__":
    build_exit_frame(lib.args())

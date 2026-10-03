"""Группа ice: существа Сети. Запуск: blender -b --python ice.py -- --out <корень netrun/assets>"""
import math
import os
import sys

from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def _tendril(start, length, tilt, azimuth, r=0.035):
    """Тонкий конус остриём вниз от start, наклон tilt (°) в сторону azimuth (°): «кабель-щупальце»."""
    m = Euler([0, math.radians(tilt), math.radians(azimuth)]).to_matrix()
    d = m @ Vector((0, 0, -1))
    bm = lib.cone_bm(r, 0.0, length, segments=3)
    return lib.xform_bm(bm, rot=(180, tilt, azimuth), offset=Vector(start) + d * (length / 2)), Vector(start) + d * length


def build_soft_ice(out):
    """Soft ICE: ассиметричный охотник, не иконка. Тёмный наклонённый корпус (закрывает cyan за собой и режет силуэт),
    красная кайма, «корона» из неравных лезвий, шлейф кабелей-щупалец и поток точек. Без колец и шипов-иконок.
    Анимации idle/patrol — следующим этапом (скелет ≤ 20 костей)."""
    lib.reset()
    red, hot = lib.lin("threat"), lib.lin("threat_hot")
    lean = 14
    cz = 0.95  # центр корпуса по высоте
    body = lambda: lib.xform_bm(lib.cone_bm(0.22, 0.05, 1.2, segments=6), rot=(0, lean, 0), offset=(0.0, 0.0, cz))
    objs = [lib.obj_from_bm("ice_body", body(), "solid_dark", red, alpha=0.75, smooth=True)]
    aura = lambda: lib.xform_bm(lib.cone_bm(0.26, 0.1, 1.3, segments=6), rot=(0, lean, 0), offset=(0.0, 0.0, cz))
    objs += lib.shell_stack(aura, "ice_aura", red, layers=2, grow=0.1, a_inner=0.22, a_outer=0.06, pivot=(0, 0, cz))
    # корона и щупальца — линии частиц (сплошных конусов нет). Корона: три неравных лезвия вверх-назад.
    top = Vector((math.sin(math.radians(lean)) * 0.6, 0, cz + math.cos(math.radians(lean)) * 0.6))
    segs = []
    for length, tilt, az in ((0.45, 28, 200), (0.3, 55, 120), (0.55, 18, 300)):
        d = Euler([0, math.radians(tilt), math.radians(az)]).to_matrix() @ Vector((0, 0, 1))
        segs.append((top, top + d * length))
    # щупальца: неравные; кончик первого ровно на полу (origin «feet»), остальные выше. Начало: z = кончик + length·cos(tilt)
    for sx, sy, length, tilt, az, tip_z in ((0.14, 0.0, 0.9, 6, 20, 0.0), (0.0, 0.1, 0.7, 22, 150, 0.12), (-0.1, -0.1, 0.8, 30, 250, 0.25), (0.05, 0.0, 0.6, 40, 80, 0.4)):
        start = Vector((sx, sy, tip_z + length * math.cos(math.radians(tilt))))
        d = Euler([0, math.radians(tilt), math.radians(az)]).to_matrix() @ Vector((0, 0, -1))
        segs.append((start, start + d * length))
    lines = lib.sample_lines(segs, 70, spread=0.012, seed=21, min_z=0.004)
    objs.append(lib.point_cloud("ice_lines", lines, hot, half_size=0.009, seed=21, a_min=0.4, a_max=1.0))
    aura = lib.sample_surface(aura(), 700, seed=5, push=0.25)
    objs.append(lib.point_cloud("ice_pts", [p if p.z > 0.004 else Vector((p.x, p.y, 0.004)) for p in aura], red, half_size=0.011, seed=5, a_min=0.2, a_max=0.9))
    return lib.export("soft_ice", "ice", objs, out, budget_tris=3000, budget_points=1500, origin="feet", notes="без анимаций (пилот)")


if __name__ == "__main__":
    build_soft_ice(lib.args())

"""Аватар другого нетраннера: голова в VR-гарнитуре, торс, руки, без ног (внизу торс сужается в конус-«парение»).

Запуск: blender -b -P netrun/assets/src/build_avatar.py   (на devbox; результат — netrun/assets/models/avatar/runner.glb)

Масштаб — сидящий человек: глаза на 1,2 м (как EyeAnchor кресла), поэтому взгляд аватара совпадает по высоте с взглядом игрока.
Лицо смотрит в -Z, origin на полу в центре. До 9 аватаров одновременно: ~700 треугольников и один скининг-меш каждый.
Скелет 9 костей (Root, Torso, Head, UpperArm/Forearm/Hand L и R) — клиент позирует голову и кисти по трекингу; клипов нет.
Поверхность 0 — корпус, поверхность 1 — неон: клиент перекрашивает неон под игрока (material_override у поверхности).
Метка NameAnchor — статичная точка над головой для имени игрока.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as bc  # noqa: E402
import palette  # noqa: E402
from bl_common import MODELS, Part, Rig, Y, Z  # noqa: E402
from mathutils import Vector  # noqa: E402

B, N = 0, 1
R22 = math.radians(22.5)


def _arm_bones(sx, s):
    return [
        ("UpperArm" + s, "Torso", (sx * 0.24, 1.0, 0.0), (sx * 0.27, 0.78, -0.03)),
        ("Forearm" + s, "UpperArm" + s, (sx * 0.27, 0.78, -0.03), (sx * 0.26, 0.58, -0.16)),
        ("Hand" + s, "Forearm" + s, (sx * 0.26, 0.58, -0.16), (sx * 0.26, 0.48, -0.25)),
    ]


BONES = [
    ("Root", None, (0, 0, 0), (0, 0.3, 0)),
    ("Torso", "Root", (0, 0.86, 0), (0, 1.04, 0)),
    ("Head", "Torso", (0, 1.10, 0), (0, 1.32, 0)),
] + _arm_bones(-1, "L") + _arm_bones(1, "R")


def _arm(p, sx, s):
    sh, el, wr = Vector((sx * 0.24, 1.0, 0)), Vector((sx * 0.27, 0.78, -0.03)), Vector((sx * 0.26, 0.58, -0.16))
    with p.on_bone("UpperArm" + s):
        p.limb(sh, el, 0.05, 0.04, 6, B, 0.0)
        p.box((sx * 0.27, 1.04, 0), (0.12, 0.05, 0.15), B, 0.015, "all")                 # наплечник
        p.strip((sx * 0.27, 1.0665, 0), 0.08, 0.02, Z, Y, N, tip=0.008)
    with p.on_bone("Forearm" + s):
        p.limb(el, wr, 0.04, 0.035, 6, B, 0.0)
        a, b = el + (wr - el) * 0.3, el + (wr - el) * 0.42
        p.limb(a, b, 0.046, 0.046, 6, N, 0.0, caps="none")                                # неоновый браслет
    with p.on_bone("Hand" + s):
        p.box((sx * 0.26, 0.52, -0.2), (0.06, 0.07, 0.08), B, 0.015, "all")


def runner(mats):
    p = Part("Mesh", mats)
    with p.on_bone("Torso"):
        p.box((0, 0.97, 0), (0.40, 0.22, 0.24), B, 0.04, "all")                          # грудь
        p.box((0, 1.03, 0), (0.50, 0.10, 0.22), B, 0.03, "all")                          # плечевой пояс
        p.frustum(0, 0, 0.52, 0.87, 0.03, 0.16, 8, B, R22, caps="bot")                   # низ — конус, без ног
        p.frustum(0, 0, 0.775, 0.825, 0.136, 0.152, 8, N, R22, caps="none")              # неоновый пояс на конусе
        for sx in (-1, 1):                                                               # «V» на груди
            a = math.radians(-35 * sx)
            p.strip((sx * 0.09, 0.98, -0.12), 0.15, 0.028, Vector((math.cos(a), math.sin(a), 0)), -Z, N, tip=0.012)
        p.box((0, 0.98, 0.17), (0.24, 0.20, 0.10), B, 0.025, "all")                      # блок на спине
        p.strip((0, 0.98, 0.22), 0.16, 0.03, Y, Z, N, tip=0.012)
    with p.on_bone("Head"):
        p.frustum(0, 0, 1.06, 1.13, 0.05, 0.055, 8, B, R22, caps="none")                 # шея
        p.frustum(0, 0, 1.10, 1.34, 0.105, 0.115, 8, B, R22, caps="both")                # голова
        p.frustum(0, 0, 1.265, 1.305, 0.121, 0.121, 8, B, R22, caps="none")              # оголовье гарнитуры
        p.box((0, 1.20, -0.10), (0.23, 0.10, 0.07), B, 0.02, "all")                      # визор
        p.strip((0, 1.20, -0.135), 0.17, 0.05, Vector((1, 0, 0)), -Z, N, tip=0.02)         # линза
        for sx in (-1, 1):
            p.box((sx * 0.125, 1.20, 0.0), (0.04, 0.08, 0.10), B, 0.012, "all")          # наушники
        p.limb(Vector((0, 1.30, 0.10)), Vector((0, 1.44, 0.15)), 0.012, 0.0, 6, N, 0.0)  # антенна
    _arm(p, -1, "L")
    _arm(p, 1, "R")
    return p


def main():
    bc.reset_scene()
    body = bc.body_material("avatar_body", palette.PROP_BODY)
    neon = bc.neon_material("avatar_neon", palette.ACC, palette.NEON_PROP)
    rig = Rig("Skeleton", BONES)
    rig.build()
    mesh = runner([body, neon]).build()
    rig.attach(mesh)
    anchor = bc.empty("NameAnchor", (0, 1.62, 0))
    bc.export_glb(os.path.join(MODELS, "avatar", "runner.glb"), [rig.obj, mesh, anchor], skinned=True)


if __name__ == "__main__":
    main()

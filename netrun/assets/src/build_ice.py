"""ICE «Сети»: Soft ICE (патрульный) и Black ICE (охотник узлов NIGHTMARE). Скелет, жёсткий скининг, клипы.

Запуск: blender -b -P netrun/assets/src/build_ice.py   (на devbox; результат — netrun/assets/models/ice/*.glb)

Читаемость издалека — по силуэту, а не по цвету: Soft ICE — парящий шар с одним глазом, вращающимся кольцом-«нимбом» (1,3 м в поперечнике) и тремя
висящими клинками, ростом 1,6 м, оранжевый неон (warn); Black ICE — высокая узкая фигура 2,9 м с рогатым венцом, шипастыми наплечниками и
длинными руками до колен, красный неон (bad), тело почти чёрное. Оба смотрят вперёд, то есть в -Z; origin на полу в центре.
Клипы — короткие периодические (последний ключ равен первому): Soft ICE: idle, patrol; Black ICE: idle, hunt, catch.
Метка AlertAnchor — статичная точка над головой для значка «обнаружен / охота» и пространственного звука.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as bc  # noqa: E402
import palette  # noqa: E402
from bl_common import EPS, MODELS, Part, Rig, R_, T_, X, Y, Z  # noqa: E402
from mathutils import Vector  # noqa: E402

B, N = 0, 1
R22 = math.radians(22.5)
TAU = 2 * math.pi


def sin_(t, cycles=1.0, phase=0.0):
    return math.sin(TAU * (t * cycles + phase))


# =========================================================================================================================
# Soft ICE
# =========================================================================================================================
CY = 0.98   # центр шара-ядра по высоте
SOFT_BONES = [
    ("Root", None, (0, 0, 0), (0, 0.25, 0)),
    ("Body", "Root", (0, CY, 0), (0, CY + 0.2, 0)),
    ("Eye", "Body", (0, CY, -0.34), (0, CY, -0.54)),
    ("Ring", "Body", (0, CY, 0), (0, CY + 0.15, 0)),
    ("TentL", "Body", (-0.12, 0.64, 0.09), (-0.2, 0.3, 0.14)),
    ("TentR", "Body", (0.12, 0.64, 0.09), (0.2, 0.3, 0.14)),
    ("TentB", "Body", (0, 0.64, 0.14), (0, 0.3, 0.26)),
    ("Antenna", "Body", (0, CY + 0.33, 0), (0, CY + 0.66, 0)),
]
# профиль шара: (высота относительно центра, радиус) — восьмигранник, грани смотрят по осям
ORB = [(-0.34, 0.10), (-0.25, 0.25), (-0.11, 0.35), (0.0, 0.385), (0.11, 0.35), (0.25, 0.25), (0.34, 0.10)]


def _blade(p, angle_deg, tilt, length=0.46, mat_tip=True):
    """Висящий клинок под шаром: вертикальная пластина, наклонённая наружу; кончик неоновый."""
    a = math.radians(angle_deg)
    base = Vector((0.12 * math.cos(a), 0.64, 0.12 * math.sin(a)))
    with p.frame(T_(*base) @ R_(-angle_deg, "Y") @ R_(tilt, "Z")):
        p.extrude([(-0.06, 0.0), (0.06, 0.0), (0.04, -length * 0.5), (0.0, -length), (-0.04, -length * 0.5)], 0.035, B)
        p.extrude([(-0.026, -length * 0.55), (0.026, -length * 0.55), (0.0, -length * 1.02)], 0.045, N)


def soft_ice(mats):
    p = Part("Mesh", mats)
    with p.on_bone("Body"):
        for k in range(len(ORB) - 1):
            (y0, r0), (y1, r1) = ORB[k], ORB[k + 1]
            caps = "bot" if k == 0 else ("top" if k == len(ORB) - 2 else "none")
            p.frustum(0, 0, CY + y0, CY + y1, r0, r1, 8, B, R22, caps=caps)
        p.frustum(0, 0, CY - 0.045, CY + 0.045, 0.389, 0.389, 8, N, R22, caps="none")          # неоновый пояс по экватору
        for k in range(8):                                                                     # полосы на верхних гранях шара
            a = R22 * 2 * k
            d = Vector((math.cos(a), 0, math.sin(a)))
            c = d * (0.9239 * 0.30) + Vector((0, CY + 0.18, 0))
            nrm = (d * 0.866 + Y * 0.5).normalized()
            p.strip(c, 0.13, 0.026, (Y - d * 0.5).normalized(), nrm, N, tip=0.01)
    with p.on_bone("Eye"):
        p.box((0, CY, -0.40), (0.30, 0.28, 0.12), B, 0.03, "all")                              # корпус глаза
        p.box((0, CY + 0.17, -0.40), (0.36, 0.045, 0.16), B, 0.014, "all")                     # козырёк-бровь
        p.disc((0, CY, -0.46), 0.105, 8, -Z, N, rot=R22)                                       # радужка
        p.disc((0, CY, -0.468), 0.042, 8, -Z, B, rot=R22)                                      # зрачок
    with p.on_bone("Ring"):
        n_seg = 8
        for k in range(n_seg):
            a0, a1 = TAU * k / n_seg, TAU * (k + 0.72) / n_seg
            r_in, r_out = 0.50, 0.64
            seg = [(r_in * math.cos(a0), r_in * math.sin(a0)), (r_out * math.cos(a0), r_out * math.sin(a0)),
                   (r_out * math.cos((a0 + a1) / 2), r_out * math.sin((a0 + a1) / 2)),
                   (r_out * math.cos(a1), r_out * math.sin(a1)), (r_in * math.cos(a1), r_in * math.sin(a1)),
                   (r_in * math.cos((a0 + a1) / 2), r_in * math.sin((a0 + a1) / 2))]
            with p.frame(T_(0, CY, 0) @ R_(-90, "X")):    # плоскость XY -> горизонталь; локальный Y -> -Z мира
                p.extrude(seg, 0.05, N if k % 2 == 0 else B)
    for name, ang, tilt in (("TentL", 215, 12), ("TentR", 325, 12), ("TentB", 90, 10)):
        with p.on_bone(name):
            _blade(p, ang, tilt)
    with p.on_bone("Antenna"):
        p.frustum(0, 0, CY + 0.33, CY + 0.52, 0.035, 0.02, 6, B, 0.0, caps="bot")
        p.frustum(0, 0, CY + 0.52, CY + 0.66, 0.022, 0.0, 6, N, 0.0, caps="none")
    return p


def soft_clips(rig):
    def idle(b, t):
        s = sin_(t)
        if b == "Body":
            return {"loc": (0, 0.03 * s, 0), "rot": (1.5 * s, 0, 0)}
        if b == "Ring":
            return {"rot": (4 * sin_(t, 1, 0.2), 14 * sin_(t, 1, 0.3), 4 * sin_(t, 1, 0.45))}
        if b == "Eye":
            return {"rot": (0, 16 * sin_(t, 1, 0.1), 0)}
        if b in ("TentL", "TentR", "TentB"):
            ph = {"TentL": 0.0, "TentR": 0.33, "TentB": 0.66}[b]
            return {"rot": (5 * sin_(t, 1, ph), 0, 6 * sin_(t, 1, ph + 0.25))}
        if b == "Antenna":
            return {"rot": (5 * sin_(t, 1, -0.15), 0, 6 * sin_(t, 1, -0.35))}
        return None

    def patrol(b, t):
        s2 = sin_(t, 2)
        if b == "Body":
            return {"loc": (0, 0.035 * s2, 0), "rot": (-9 + 2 * s2, 0, 0)}
        if b == "Ring":
            return {"rot": (-3 + 3 * sin_(t, 2, 0.2), 360.0 * t, 5 * sin_(t, 2, 0.45))}
        if b == "Eye":
            return {"rot": (0, 32 * sin_(t), 0)}
        if b in ("TentL", "TentR", "TentB"):
            ph = {"TentL": 0.0, "TentR": 0.25, "TentB": 0.5}[b]
            return {"rot": (-14 + 8 * sin_(t, 2, ph), 0, 8 * sin_(t, 2, ph + 0.25))}
        if b == "Antenna":
            return {"rot": (9 + 6 * sin_(t, 2, -0.2), 0, 7 * sin_(t, 2, -0.35))}
        return None

    rig.clip("idle", 2.0, idle)
    rig.clip("patrol", 2.0, patrol)


# =========================================================================================================================
# Black ICE
# =========================================================================================================================
def _arm_bones(sx, side):
    s = side
    return [
        ("UpperArm" + s, "Chest", (sx * 0.58, 1.95, 0.0), (sx * 0.62, 1.42, -0.05)),
        ("Forearm" + s, "UpperArm" + s, (sx * 0.62, 1.42, -0.05), (sx * 0.62, 0.86, -0.12)),
        ("Hand" + s, "Forearm" + s, (sx * 0.62, 0.86, -0.12), (sx * 0.62, 0.55, -0.20)),
    ]


BLACK_BONES = [
    ("Root", None, (0, 0, 0), (0, 0.3, 0)),
    ("Hips", "Root", (0, 1.0, 0), (0, 1.3, 0)),
    ("Hem", "Hips", (0, 1.0, 0), (0, 0.5, 0)),
    ("Chest", "Hips", (0, 1.5, 0), (0, 1.95, 0)),
    ("Core", "Chest", (0, 1.75, -0.40), (0, 1.75, -0.56)),
    ("Head", "Chest", (0, 2.1, 0), (0, 2.5, 0)),
] + _arm_bones(-1, "L") + _arm_bones(1, "R")


def _hem(p):
    """Рваный низ плаща: кольцо 16 точек, чередуются длинные зубцы (низко, широко) и короткие (выше, уже)."""
    n = 16
    bottom, top = [], []
    for k in range(n):
        a = TAU * k / n
        long_ = k % 2 == 0
        y, r = (0.16, 0.66) if long_ else (0.52, 0.52)
        bottom.append(Vector((r * math.cos(a), y, r * math.sin(a))))
        rt = 0.50 if k % 2 else 0.50 * math.cos(R22)   # стык с восьмигранником талии: вершины — нечётные точки
        top.append(Vector((rt * math.cos(a), 1.0, rt * math.sin(a))))
    p.loft([bottom, top], B, caps=True)
    for k in range(0, n, 2):                                   # светящиеся кончики длинных зубцов
        a = TAU * k / n
        p.limb(Vector((0.66 * math.cos(a), 0.17, 0.66 * math.sin(a))), Vector((0.70 * math.cos(a), 0.02, 0.70 * math.sin(a))), 0.045, 0.0, 4, N, math.radians(45), caps="none")
    inner_b, inner_t = [], []                                   # второй, внутренний слой плаща: глубина силуэта
    for k in range(n):
        a = TAU * k / n + TAU / (2 * n)
        long_ = k % 2 == 0
        y, r = (0.30, 0.50) if long_ else (0.62, 0.42)
        inner_b.append(Vector((r * math.cos(a), y, r * math.sin(a))))
        inner_t.append(Vector((0.36 * math.cos(a), 1.0, 0.36 * math.sin(a))))
    p.loft([inner_b, inner_t], B, caps=True)


def _claws(p, sx, hand_y=0.78):
    cx, cz = sx * 0.62, -0.14
    palm_y = hand_y
    p.box((cx, palm_y, cz), (0.15, 0.09, 0.10), B, 0.02, "all")
    fingers = [(-0.055, 0.30, -0.32), (-0.019, 0.24, -0.38), (0.019, 0.24, -0.38), (0.055, 0.30, -0.32)]
    for dx, ty, tz in fingers:
        base = Vector((cx + dx, palm_y - 0.04, cz - 0.02))
        tip = Vector((cx + dx * 1.2, ty, tz))
        mid = base + (tip - base) * 0.55
        p.limb(base, mid, 0.024, 0.016, 4, B, math.radians(45), caps="bot")
        p.limb(mid, tip, 0.016, 0.0, 4, N, math.radians(45), caps="none")
    thumb_base = Vector((cx + sx * 0.075, palm_y - 0.02, cz))
    thumb_tip = Vector((cx + sx * 0.17, 0.52, cz - 0.20))
    mid = thumb_base + (thumb_tip - thumb_base) * 0.55
    p.limb(thumb_base, mid, 0.024, 0.016, 4, B, math.radians(45), caps="bot")
    p.limb(mid, thumb_tip, 0.016, 0.0, 4, N, math.radians(45), caps="none")


def _arm(p, sx, side):
    sh, el, wr = Vector((sx * 0.58, 1.95, 0.0)), Vector((sx * 0.62, 1.42, -0.05)), Vector((sx * 0.62, 0.86, -0.12))
    with p.on_bone("UpperArm" + side):
        p.limb(sh, el, 0.10, 0.075, 6, B, 0.0)
        p.limb(Vector((sx * 0.40, 1.93, 0)), Vector((sx * 0.80, 2.0, 0)), 0.15, 0.11, 6, B, 0.0)     # наплечник
        p.limb(Vector((sx * 0.60, 2.02, 0)), Vector((sx * 0.84, 2.46, -0.02)), 0.075, 0.0, 6, B, 0.0)   # шип вверх
        p.limb(Vector((sx * 0.72, 1.99, 0.06)), Vector((sx * 1.04, 2.22, 0.30)), 0.06, 0.0, 6, N, 0.0)   # шип назад (неон)
        p.limb(Vector((sx * 0.64, 1.46, 0.03)), Vector((sx * 0.72, 1.60, 0.36)), 0.045, 0.0, 6, B, 0.0)  # локтевой клинок
    with p.on_bone("Forearm" + side):
        p.limb(el, wr, 0.075, 0.055, 6, B, 0.0)
        p.strip(Vector((sx * 0.62 + sx * 0.062, 1.15, -0.085)), 0.30, 0.022, Y, X * sx, N, tip=0.008)     # неон на предплечье
        for t in (0.35, 0.65):                                                                              # клинки вдоль предплечья
            c = el + (wr - el) * t
            p.limb(c + Vector((sx * 0.05, 0, 0.03)), c + Vector((sx * 0.20, -0.05, 0.22)), 0.04, 0.0, 6, B, 0.0)
    with p.on_bone("Hand" + side):
        _claws(p, sx)


def black_ice(mats):
    p = Part("Mesh", mats)
    with p.on_bone("Hem"):
        _hem(p)
    with p.on_bone("Hips"):
        p.frustum(0, 0, 1.0, 1.5, 0.50, 0.36, 8, B, R22, caps="none")
        p.frustum(0, 0, 1.455, 1.5, 0.381, 0.368, 8, N, R22, caps="none")   # неоновый пояс у талии (чуть шире тела)
    with p.on_bone("Chest"):
        p.frustum(0, 0, 1.5, 2.0, 0.36, 0.50, 8, B, R22, caps="bot")         # торс: плечи шире талии
        p.frustum(0, 0, 2.0, 2.14, 0.50, 0.17, 8, B, R22, caps="both")       # воротник к шее
        p.box((0, 1.78, -0.30), (0.50, 0.52, 0.10), B, 0.035, "all")         # нагрудная пластина
        for sx in (-1, 1):
            p.strip((sx * 0.19, 1.78, -0.35), 0.40, 0.03, Y, -Z, N, tip=0.012)
        for k in range(5):                                                   # шипы вдоль спины
            y = 1.55 + 0.17 * k
            p.limb(Vector((0, y, 0.30)), Vector((0, y + 0.30, 0.72 - 0.05 * k)), 0.07 - 0.005 * k, 0.0, 6, B, 0.0)
        for sx in (-1, 1):                                                   # ключичные шипы вперёд-вверх
            p.limb(Vector((sx * 0.20, 2.04, -0.14)), Vector((sx * 0.30, 2.46, -0.30)), 0.055, 0.0, 6, B, 0.0)
    with p.on_bone("Core"):
        # кристалл-сердце: вытянутая двойная пирамида, торчит из груди
        p.frustum(0, -0.40, 1.75, 1.93, 0.085, 0.0, 8, N, R22, caps="none")
        p.frustum(0, -0.40, 1.75, 1.57, 0.085, 0.0, 8, N, R22, caps="none")
    with p.on_bone("Head"):
        p.frustum(0, 0, 2.04, 2.16, 0.09, 0.11, 8, B, R22, caps="none")      # шея
        p.frustum(0, 0, 2.14, 2.36, 0.17, 0.215, 8, B, R22, caps="bot")      # череп-шлем
        p.frustum(0, 0, 2.36, 2.52, 0.215, 0.12, 8, B, R22, caps="top")
        p.box((0, 2.27, -0.16), (0.34, 0.21, 0.10), B, 0.03, "all")          # маска
        for sx in (-1, 1):                                                   # злые глаза
            a = math.radians(-24 * sx)
            p.strip((sx * 0.078, 2.31, -0.21), 0.15, 0.046, Vector((math.cos(a), math.sin(a), 0)), -Z, N, tip=0.02)
        p.disc((0, 2.395, -0.21), 0.026, 4, -Z, N, rot=0.0)                # третий глаз
        for k in range(-2, 3):                                               # рот-шов
            p.strip((k * 0.045, 2.20, -0.21), 0.06, 0.012, Y, -Z, N, tip=0.004)
        for s in range(-3, 4):                                               # рогатый венец
            ax = math.radians(s * 22)
            base = Vector((math.sin(ax) * 0.15, 2.42 + math.cos(ax) * 0.09, 0.03))
            length = (0.52, 0.44, 0.35, 0.27)[abs(s)]
            d = Vector((math.sin(ax) * 0.75, math.cos(ax), 0.30)).normalized()
            p.limb(base, base + d * length, 0.045, 0.0, 6, B if abs(s) != 3 else N, 0.0)
        for sx in (-1, 1):                                                   # лезвия-«уши», назад
            p.limb(Vector((sx * 0.19, 2.32, 0.02)), Vector((sx * 0.36, 2.18, 0.62)), 0.045, 0.0, 6, B, 0.0)
    _arm(p, -1, "L")
    _arm(p, 1, "R")
    return p


def black_clips(rig):
    def idle(b, t):
        s = sin_(t)
        sp = sin_(t, 1, 0.5)
        if b == "Hips":
            return {"loc": (0, 0.04 * s, 0)}
        if b == "Chest":
            return {"rot": (1.5 * s, 2 * sin_(t, 1, 0.2), 0)}
        if b == "Head":
            return {"rot": (2 * sin_(t, 1, 0.3), 8 * sin_(t, 1, 0.1), 0)}
        if b == "Hem":
            return {"rot": (5 * sin_(t, 1, 0.4), 0, 4 * sin_(t, 1, 0.1))}
        if b == "Core":
            return {"scale": 1.0 + 0.07 * (0.5 + 0.5 * sin_(t, 2))}
        if b in ("UpperArmL", "UpperArmR"):
            ph = 0.0 if b.endswith("L") else 0.5
            return {"rot": (3 * sin_(t, 1, ph), 0, (2 if b.endswith("R") else -2) * s)}
        if b in ("ForearmL", "ForearmR"):
            return {"rot": (4 + 3 * sin_(t, 1, 0.25 if b.endswith("L") else 0.75), 0, 0)}
        if b in ("HandL", "HandR"):
            return {"rot": (5 * sin_(t, 1, 0.45 if b.endswith("L") else 0.95), 0, 0)}
        return None

    def hunt(b, t):
        s, s2 = sin_(t), sin_(t, 2)
        if b == "Hips":
            return {"loc": (0, 0.03 * s2, -0.05), "rot": (-13, 0, 0)}
        if b == "Chest":
            return {"rot": (-8 + 3 * s2, 4 * s, 0)}
        if b == "Head":
            return {"rot": (-12 + 3 * sin_(t, 2, 0.2), 0, 0)}
        if b == "Hem":
            return {"rot": (-22 + 8 * sin_(t, 2, 0.35), 0, 5 * s)}
        if b == "Core":
            return {"scale": 1.0 + 0.16 * (0.5 + 0.5 * sin_(t, 2))}
        if b in ("UpperArmL", "UpperArmR"):
            ph = 0.0 if b.endswith("L") else 0.5
            return {"rot": (20 + 28 * sin_(t, 1, ph), 0, 0)}
        if b in ("ForearmL", "ForearmR"):
            ph = 0.0 if b.endswith("L") else 0.5
            return {"rot": (28 + 18 * sin_(t, 1, ph + 0.2), 0, 0)}
        if b in ("HandL", "HandR"):
            return {"rot": (10 + 10 * sin_(t, 1, 0.4 if b.endswith("L") else 0.9), 0, 0)}
        return None

    def catch(b, t):
        s2 = sin_(t, 2)
        sq = 0.5 - 0.5 * math.cos(TAU * t)    # 0 = руки разведены, 1 = сведены
        if b == "Hips":
            return {"loc": (0, 0.02 * s2, -0.10), "rot": (-16, 0, 0)}
        if b == "Chest":
            return {"rot": (-14, 0, 0)}
        if b == "Head":
            return {"rot": (-22 + 2 * s2, 0, 0)}
        if b == "Hem":
            return {"rot": (-30 + 6 * sin_(t, 2, 0.3), 0, 0)}
        if b == "Core":
            return {"scale": 1.0 + 0.22 * (0.5 + 0.5 * sin_(t, 2))}
        if b in ("UpperArmL", "UpperArmR"):
            yaw = -18 * sq if b.endswith("L") else 18 * sq
            return {"rot": (72, yaw, 0)}
        if b in ("ForearmL", "ForearmR"):
            yaw = -14 * sq if b.endswith("L") else 14 * sq
            return {"rot": (22, yaw, 0)}
        if b in ("HandL", "HandR"):
            return {"rot": (12 + 14 * sq, 0, 0)}
        return None

    rig.clip("idle", 3.0, idle, step=3)
    rig.clip("hunt", 1.2, hunt)
    rig.clip("catch", 1.0, catch)


# =========================================================================================================================
def build(name, bones, make_part, make_clips, body_hex, neon_hex, anchor_y):
    bc.reset_scene()
    body = bc.body_material("ice_body_" + name, body_hex)
    neon = bc.neon_material("ice_neon_" + name, neon_hex, palette.NEON_ICE)
    rig = Rig("Skeleton", bones)
    rig.build()
    part = make_part([body, neon])
    mesh = part.build()
    rig.attach(mesh)
    make_clips(rig)
    anchor = bc.empty("AlertAnchor", (0, anchor_y, 0))
    bc.export_glb(os.path.join(MODELS, "ice", name + ".glb"), [rig.obj, mesh, anchor], skinned=True)


def main():
    build("soft_ice", SOFT_BONES, soft_ice, soft_clips, palette.SOFT_ICE_BODY, palette.WARN, 1.95)
    build("black_ice", BLACK_BONES, black_ice, black_clips, palette.BLACK_ICE_BODY, palette.BAD, 3.2)


if __name__ == "__main__":
    main()

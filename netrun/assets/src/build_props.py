"""Предметы «Сети»: хранилище, шард, мёртвая дека, портал, датчик, кресло. По одному телу (графит) и одному неону.

Запуск: blender -b -P netrun/assets/src/build_props.py   (на devbox; результат — netrun/assets/models/props/*.glb)

Соглашения: origin на полу в центре (шард и дека — в центре предмета); лицо предмета (дверца, линза, арка) смотрит в +Z —
так его видит игрок, смотрящий вдоль -Z. Кресло — наоборот: сидящий смотрит в -Z (вперёд в Godot), спинка сзади, у +Z.
Метки (Node3D в Godot): ShardSlot у хранилища, SeatAnchor и EyeAnchor у кресла.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as bc  # noqa: E402
import palette  # noqa: E402
from bl_common import MODELS, Part, X, Y, Z  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

B, N = 0, 1
R22 = math.radians(22.5)


def T_(x, y, z):
    return Matrix.Translation((x, y, z))


def R_(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)


# --- хранилище -------------------------------------------------------------------------------------------------------
def vault(m, opened):
    """Сейф данных 1,2 x 1,55 x 0,9 м. Нишу с постаментом закрывает решётчатая дверца (шард виден сквозь прутья, но не взять,
    пока не открыто); открытая — дверца отведена на 110 градусов влево. Метка ShardSlot — центр шарда над постаментом."""
    p = Part("Mesh", m)
    p.box((0, 0.06, 0), (1.2, 0.12, 0.9), B, 0.03, "top+vert")        # основание
    p.box((0, 0.41, 0), (1.1, 0.58, 0.8), B, 0.035, "vert+top")        # нижний блок
    p.box((0, 1.425, 0), (1.1, 0.25, 0.8), B, 0.035, "all")            # верхний блок
    for sx in (-1, 1):                                                  # стойки ниши
        p.box((sx * 0.45, 1.0, 0), (0.2, 0.6, 0.8), B, 0.03, "vert")
    p.box((0, 1.0, -0.35), (0.7, 0.6, 0.1), B)                          # задняя стенка ниши
    p.frustum(0, 0, 0.7, 0.82, 0.17, 0.13, 8, B, R22, caps="both")      # постамент
    p.ring((0, 0.82, 0), 0.07, 0.115, 8, Y, N, rot=R22)                 # гнездо шарда
    for sx in (-1, 1):                                                  # неон на лице
        p.strip((sx * 0.45, 1.0, 0.4), 0.5, 0.04, Y, Z, N)
    p.strip((0, 1.43, 0.4), 0.9, 0.05, X, Z, N)
    p.strip((0, 1.3, 0.1), 0.55, 0.05, X, -Y, N)                        # потолок ниши
    p.strip((0, 0.7, 0.2), 0.55, 0.05, X, Y, N)                         # пол ниши
    p.disc((0, 0.42, 0.4), 0.06, 8, Z, N, rot=R22)                      # лампа замка
    with p.frame(T_(-0.35, 0, 0.375) @ R_(-110 if opened else 0, "Y")):  # дверца на петле слева
        for cx, cy, sx, sy in ((0.35, 1.275, 0.7, 0.05), (0.35, 0.725, 0.7, 0.05), (0.025, 1.0, 0.05, 0.6), (0.675, 1.0, 0.05, 0.6)):
            p.box((cx, cy, 0), (sx, sy, 0.05), B)
        for k in range(1, 5):
            p.box((k * 0.14, 1.0, 0), (0.022, 0.5, 0.022), N)
    return [p.build(), bc.empty("ShardSlot", (0, 1.0, 0))]


# --- шард ------------------------------------------------------------------------------------------------------------
def shard(m):
    """Кристалл 0,16 x 0,30 м стоймя; поясок — отдельная поверхность. Индексы материалов: 0 — ядро, 1 — поясок.
    Обычный и зашифрованный — один меш, материалы инвертированы (ядро светится или поясок светится)."""
    p = Part("Mesh", m)
    for y0, y1, r0, r1 in ((0.07, 0.15, 0.055, 0.0), (0.0, 0.07, 0.07, 0.055), (-0.07, 0.0, 0.055, 0.07), (-0.07, -0.15, 0.055, 0.0)):
        p.frustum(0, 0, y0, y1, r0, r1, 8, 0, 0.0, caps="none")
    p.frustum(0, 0, -0.022, 0.0, 0.074, 0.086, 8, 1, 0.0, caps="bot")
    p.frustum(0, 0, 0.0, 0.022, 0.086, 0.074, 8, 1, 0.0, caps="top")
    return [p.build()]


# --- мёртвая дека ----------------------------------------------------------------------------------------------------
def dead_deck(m):
    """Выведенная из строя дека-браслет 0,36 x 0,07 x 0,16 м: трещина на экране, сломанный слот, оборванный ремень и кабель.
    Лежит на полу (origin в центре — поднять на 0,035 м)."""
    p = Part("Mesh", m)
    p.box((0, 0, 0), (0.24, 0.045, 0.15), B, 0.01, "all")
    p.box((0, 0.0275, -0.015), (0.16, 0.01, 0.09), B)                    # рамка экрана
    for cx, cz, deg in ((-0.04, -0.03, 20), (-0.01, -0.005, -35), (0.025, -0.02, 40), (0.045, 0.01, -15)):
        a = math.radians(deg)
        p.strip((cx, 0.0325, cz), 0.045, 0.008, Vector((math.cos(a), 0, math.sin(a))), Y, N, tip=0.004)   # трещина
    for k, x in enumerate((-0.075, -0.025, 0.025, 0.075)):              # слоты демонов, третий сорван
        with p.frame(T_(x, 0.0285, 0.05) @ (R_(25, "Y") if k == 2 else Matrix.Identity(4))):
            p.box((0, 0, 0), (0.032, 0.012 if k != 2 else 0.006, 0.032), B)
    p.box((-0.15, -0.002, 0), (0.07, 0.03, 0.12), B, 0.008, "top")      # ремень слева цел
    with p.frame(T_(0.165, -0.004, 0.01) @ R_(14, "Y")):                 # справа оборван
        p.box((0, 0, 0), (0.05, 0.026, 0.1), B, 0.008, "top")
    path = [Vector(v) for v in ((0.12, -0.012, 0.075), (0.16, -0.016, 0.1), (0.2, -0.018, 0.105), (0.235, -0.015, 0.09))]
    rings = []
    for i, c in enumerate(path):
        tan = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = tan.cross(Y).normalized()
        rings.append([c + side * 0.009 * math.cos(2 * math.pi * k / 6) + Y * 0.009 * math.sin(2 * math.pi * k / 6) for k in range(6)])
    p.loft(rings, lambda i: N if i == len(rings) - 2 else B)             # кабель, последний кусок искрит
    p.strip((0, 0.0, 0.0755), 0.2, 0.012, X, Z, N, tip=0.005)             # тусклая кромка спереди
    return [p.build()]


# --- портал ----------------------------------------------------------------------------------------------------------
def portal(m):
    """Арка 3,4 x 3,0 м с площадкой радиусом 1,5 м (радиус прохода из graph.json): игрок стоит на площадке, арка в плоскости XY,
    лицо +Z, проходить в -Z. Шевроны на площадке указывают к арке."""
    p = Part("Mesh", m)
    p.frustum(0, 0, 0, 0.06, 1.5, 1.44, 24, B, 0.0, caps="top")
    p.ring((0, 0.06, 0), 1.28, 1.38, 24, Y, N)
    p.ring((0, 0.06, 0), 0.55, 0.62, 24, Y, N)
    for z in (0.95, 1.2):
        for sx in (-1, 1):
            u = Vector((-sx * 0.28, 0, -0.2))
            p.strip((sx * 0.14, 0.06, z), 0.35, 0.07, u, Y, N)
    c = Vector((0, 1.3, 0))
    for r_in, r_out, hd, mat in ((1.5, 1.7, 0.12, B), (1.475, 1.5, 0.05, N)):
        rings = []
        for i in range(13):
            t = math.pi * i / 12
            d = Vector((math.cos(t), math.sin(t), 0))
            rings.append([c + d * r_in + Z * hd, c + d * r_out + Z * hd, c + d * r_out - Z * hd, c + d * r_in - Z * hd])
        p.loft(rings, mat, caps=True)
    for sx in (-1, 1):
        p.box((sx * 1.6, 0.1, 0), (0.36, 0.2, 0.4), B, 0.03, "top+vert")     # стопа
        p.box((sx * 1.6, 0.75, 0), (0.2, 1.1, 0.24), B, 0.02, "vert")         # стойка
        p.box((sx * 1.4875, 0.75, 0), (0.025, 1.1, 0.1), N)                   # неон внутри стойки
    p.disc((0, 2.9, 0.12), 0.06, 8, Z, N, rot=R22)                            # замковый камень
    return [p.build()]


# --- датчик ----------------------------------------------------------------------------------------------------------
def sensor(m):
    """Стационарный датчик узла 0,44 x 1,6 x 0,44 м: стойка и поворотная голова с красной линзой, смотрит в +Z."""
    p = Part("Mesh", m)
    p.box((0, 0.04, 0), (0.44, 0.08, 0.44), B, 0.025, "top+vert")
    p.frustum(0, 0, 0.08, 1.05, 0.085, 0.065, 8, B, R22, caps="none")
    p.frustum(0, 0, 1.05, 1.12, 0.11, 0.11, 8, B, R22, caps="both")
    p.box((0, 1.14, 0), (0.5, 0.05, 0.1), B)                                  # перемычка вилки
    for sx in (-1, 1):
        p.box((sx * 0.235, 1.28, 0), (0.05, 0.3, 0.12), B)
    with p.frame(T_(0, 1.3, 0) @ R_(90, "X")):                                 # голова: ось по Z
        p.frustum(0, 0, -0.14, 0.04, 0.17, 0.2, 8, B, R22, caps="both")
        p.frustum(0, 0, -0.045, -0.005, 0.206, 0.206, 8, N, R22, caps="none")  # неоновый пояс
        p.frustum(0, 0, 0.04, 0.08, 0.12, 0.09, 8, N, R22, caps="top")         # линза
    p.disc((0, 1.3, 0.08), 0.04, 8, Z, B, rot=R22)                             # зрачок
    return [p.build()]


# --- кресло ----------------------------------------------------------------------------------------------------------
def seat(m):
    """Кресло-капсула узла: платформа, сиденье (верх 0,5 м), наклонная спинка с подголовником, подлокотники. Сидящий смотрит в -Z.
    Метки: SeatAnchor — центр сиденья, EyeAnchor — глаза сидящего на высоте 1,2 м."""
    p = Part("Mesh", m)
    rot = math.radians(15)
    p.frustum(0, 0, 0, 0.12, 0.72, 0.66, 12, B, rot, caps="both")
    p.ring((0, 0.12, 0), 0.52, 0.6, 12, Y, N, rot=rot)
    p.frustum(0, 0, 0.12, 0.36, 0.2, 0.16, 8, B, R22, caps="none")
    p.box((0, 0.43, 0), (0.6, 0.14, 0.56), B, 0.04, "all")
    with p.frame(T_(0, 0.5, 0.28) @ R_(12, "X")):
        p.box((0, 0.4, 0), (0.6, 0.8, 0.12), B, 0.04, "all")
        p.box((0, 0.88, 0), (0.34, 0.16, 0.14), B, 0.03, "all")
        p.strip((0, 0.4, -0.06), 0.55, 0.06, Y, -Z, N)
        for sx in (-1, 1):
            p.strip((sx * 0.22, 0.4, -0.06), 0.4, 0.03, Y, -Z, N)
    for sx in (-1, 1):
        p.box((sx * 0.36, 0.7, 0.0), (0.1, 0.06, 0.46), B, 0.02, "top")
        p.box((sx * 0.36, 0.6, 0.12), (0.08, 0.2, 0.1), B)
        p.strip((sx * 0.36, 0.73, 0.0), 0.36, 0.03, Z, Y, N)
    return [p.build(), bc.empty("SeatAnchor", (0, 0.5, 0)), bc.empty("EyeAnchor", (0, 1.2, 0))]


def main():
    body_hex = palette.PROP_BODY
    jobs = [
        # имя файла, функция, неон (токен), сила свечения
        ("vault_closed", lambda m: vault(m, False), palette.WARN, palette.NEON_PROP),
        ("vault_open", lambda m: vault(m, True), palette.OK, palette.NEON_PROP),
        ("portal", portal, palette.ACC, palette.NEON_PROP),
        ("sensor", sensor, palette.BAD, palette.NEON_PROP),
        ("seat", seat, palette.ACC, palette.NEON_PROP),
        ("dead_deck", dead_deck, palette.CHROME, 1.0),
    ]
    for name, fn, neon_hex, strength in jobs:
        bc.reset_scene()
        body = bc.body_material("prop_body", body_hex)
        neon = bc.neon_material("prop_neon_" + name, neon_hex, strength)
        bc.export_glb(os.path.join(MODELS, "props", name + ".glb"), fn([body, neon]))
    # шард: материалы [ядро, поясок]
    for name, core, band in (("shard", ("neon", palette.MONEY), ("body", None)), ("shard_encrypted", ("body", None), ("neon", palette.WARN))):
        bc.reset_scene()
        mats = []
        for kind, hexv in (core, band):
            if kind == "neon":
                mats.append(bc.neon_material("shard_neon_" + name, hexv, palette.NEON_PROP))
            else:
                mats.append(bc.body_material("shard_body", "#1B1D21"))
        bc.export_glb(os.path.join(MODELS, "props", name + ".glb"), shard(mats))


if __name__ == "__main__":
    main()

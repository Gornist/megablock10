"""Кибердека на запястье и жетоны восьми демонов.

Запуск: blender -b -P netrun/assets/src/build_deck.py   (на devbox; результат — netrun/assets/models/deck/*.glb)

wrist_deck. Origin — точка крепления: ось запястья на границе кисти (z=0); предплечье идёт к локтю в +Z, верх запястья — +Y,
экран и слоты смотрят вверх (+Y), читаются с локтевой стороны (+Z, откуда смотрит игрок). Объекты: Mesh (корпус), Screen —
плоскость 0,15 x 0,10 м под SubViewport (UV (0,0) — левый верхний угол для зрителя; клиент задаёт material_override с
ViewportTexture; нормаль +Y, «верх» экрана — к кисти, -Z), метки Slot1..Slot5 — центры жетонов (слева направо с локтевой стороны,
то есть x от -0,068 до +0,068 шагом 0,034). Материалы только два: тёмный корпус и бирюзовый неон (acc, «интерактивное»).

daemon_<EFFECT>. Жетон 3 см: origin в центре, снизу штырь-вилка (у всех одинаковый, уходит в гнездо), лицо в +Z. Форма и цвет у
каждого свои (цвета — токены гайдлайна, смысл по возможности тот же, что в игре):
  EXTRACT_SHARD  кристалл-октаэдр с поясом, жёлтый (money) — как шард в узле
  EXTRACT_DAEMON микросхема со штырьками, бирюзовый (acc) — коды демонов в приложении бирюзовые
  GHOST          привидение с зубчатым подолом, белый (ink)
  TIMESKEW       песочные часы, розовый (label)
  BLACKOUT       тёмная шайба с символом «выключено», серый (ink2)
  JITTER         молния-зигзаг, красный (bad)
  DECRYPT        открытый замок, оранжевый (warn) — как зашифрованный шард, который он вскрывает
  MINER          кирка, зелёный (ok) — «входящие деньги»
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as bc  # noqa: E402
import palette  # noqa: E402
from bl_common import MODELS, Part, R_, T_, X, Y, Z  # noqa: E402
from mathutils import Vector  # noqa: E402

B, N = 0, 1
R22 = math.radians(22.5)
TAU = 2 * math.pi

# --- деки ------------------------------------------------------------------------------------------------------------
SLOT_X = [-0.068, -0.034, 0.0, 0.034, 0.068]
SLOT_Z = 0.065
PUCK_TOP = 0.080
SLOT_Y = PUCK_TOP - 0.004 + 0.018          # центр жетона: штырь на 4 мм в гнезде, низ штыря на 0,018 ниже центра
PLATE_TOP = 0.073
SCREEN = {"center": (0.0, 0.0765, 0.185), "w": 0.15, "h": 0.10}


def wrist_deck(mats):
    p = Part("Mesh", mats)
    p.eps = 0.0008
    for z0, z1 in ((0.045, 0.085), (0.205, 0.245)):                              # ремни: восьмигранные кольца вокруг запястья
        p.annulus_prism(0.0, 0.040, 0.052, 8, z0, z1, B, rot=R22)
    p.box((0, 0.0615, 0.145), (0.19, 0.023, 0.25), B, 0.01, "all")               # плита
    for x in SLOT_X:                                                              # гнёзда жетонов
        p.frustum(x, SLOT_Z, PLATE_TOP, PUCK_TOP, 0.0155, 0.0145, 8, B, R22, caps="top")
        p.ring((x, PUCK_TOP, SLOT_Z), 0.0075, 0.0115, 8, Y, N, rot=R22)
    p.strip((0, PLATE_TOP, 0.100), 0.15, 0.007, X, Y, N, tip=0.003)               # разделитель слотов и экрана
    cx, cy, cz = SCREEN["center"]
    for dz, sz in ((-0.05 - 0.006, 0.012), (0.05 + 0.006, 0.012)):               # рамка экрана: дальняя и ближняя планки
        p.box((0, 0.0775, cz + dz), (0.174, 0.009, sz), B)
        p.strip((0, 0.082, cz + dz), 0.15, 0.004, X, Y, N, tip=0.0015)
    for sx in (-1, 1):
        p.box((sx * 0.081, 0.0775, cz), (0.012, 0.009, 0.124), B)
        p.strip((sx * 0.081, 0.082, cz), 0.10, 0.004, Z, Y, N, tip=0.0015)
        p.strip((sx * 0.0885, PLATE_TOP, 0.145), 0.22, 0.005, Z, Y, N, tip=0.002)  # неон по кромкам плиты
    return p


def build_deck():
    bc.reset_scene()
    body = bc.body_material("prop_body", palette.PROP_BODY)
    neon = bc.neon_material("deck_neon", palette.ACC, palette.NEON_PROP)
    mesh = wrist_deck([body, neon]).build()
    s = Part("Screen", [body])
    s.screen(SCREEN["center"], SCREEN["w"], SCREEN["h"], X, Y, 0)
    screen = s.build()
    marks = [bc.empty("Slot%d" % (i + 1), (x, SLOT_Y, SLOT_Z)) for i, x in enumerate(SLOT_X)]
    bc.export_glb(os.path.join(MODELS, "deck", "wrist_deck.glb"), [mesh, screen] + marks, uv=True)


# --- жетоны ----------------------------------------------------------------------------------------------------------
def plug(p):
    p.frustum(0, 0, -0.018, -0.006, 0.0065, 0.0075, 8, B, R22, caps="bot")


def arc_ring(p, center, r_in, r_out, a0, a1, segs, mat):
    """Дуга-декаль в плоскости XY лицом в +Z: сектор кольца от угла a0 до a1 (градусы)."""
    cx, cy, cz = center
    for k in range(segs):
        t0 = math.radians(a0 + (a1 - a0) * k / segs)
        t1 = math.radians(a0 + (a1 - a0) * (k + 1) / segs)
        pts = [(cx + r_in * math.cos(t0), cy + r_in * math.sin(t0), cz), (cx + r_out * math.cos(t0), cy + r_out * math.sin(t0), cz),
               (cx + r_out * math.cos(t1), cy + r_out * math.sin(t1), cz), (cx + r_in * math.cos(t1), cy + r_in * math.sin(t1), cz)]
        p.poly(pts, Z, mat)


def tube_xy(p, path, half, mat):
    """Прямоугольная труба сечением 2*half вдоль ломаной в плоскости XY (толщина — вдоль Z)."""
    rings = []
    for i, c in enumerate(path):
        c = Vector(c)
        t = (Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(i - 1, 0)])).normalized()
        n = Vector((-t.y, t.x, 0))
        rings.append([c + n * half + Z * half, c - n * half + Z * half, c - n * half - Z * half, c + n * half - Z * half])
    p.loft(rings, mat, caps=True)


def t_extract_shard(p):
    plug(p)
    cy = 0.006
    p.frustum(0, 0, cy, cy + 0.022, 0.0135, 0.0, 8, N, R22, caps="none")
    p.frustum(0, 0, cy, cy - 0.012, 0.0135, 0.0, 8, N, R22, caps="none")
    p.frustum(0, 0, cy - 0.0035, cy + 0.0035, 0.0143, 0.0143, 8, B, R22, caps="none")


def t_extract_daemon(p):
    plug(p)
    p.box((0, 0.004, 0), (0.021, 0.021, 0.008), B, 0.002, "all")
    for k in (-1, 0, 1):
        for sx in (-1, 1):
            p.box((sx * 0.0127, 0.004 + k * 0.0065, 0), (0.0048, 0.0028, 0.0028), N)
        p.box((k * 0.0065, 0.0158, 0), (0.0028, 0.0048, 0.0028), N)
    p.poly([(-0.0055, -0.0015, 0.004), (0.0055, -0.0015, 0.004), (0.0055, 0.0095, 0.004), (-0.0055, 0.0095, 0.004)], Z, N)
    p.poly([(-0.0095, 0.0125, 0.004), (-0.0055, 0.0125, 0.004), (-0.0095, 0.0085, 0.004)], Z, N)


def t_ghost(p):
    plug(p)
    dy = 0.002
    dome = [(0.0125 * math.cos(math.radians(a)), 0.010 + 0.0125 * math.sin(math.radians(a)) + dy) for a in (150, 120, 90, 60, 30)]
    outline = [(-0.0125, -0.008 + dy), (-0.0125, 0.010 + dy)] + dome + [(0.0125, 0.010 + dy), (0.0125, -0.008 + dy),
               (0.0083, -0.002 + dy), (0.0042, -0.008 + dy), (0.0, -0.002 + dy), (-0.0042, -0.008 + dy), (-0.0083, -0.002 + dy)]
    p.extrude(outline, 0.010, N)
    for sx in (-1, 1):
        p.disc((sx * 0.0045, 0.0125 + dy, 0.005), 0.0025, 6, Z, B)
    p.disc((0, 0.0065 + dy, 0.005), 0.0017, 6, Z, B)


def t_timeskew(p):
    plug(p)
    p.frustum(0, 0, -0.006, -0.002, 0.0125, 0.0125, 8, B, R22, caps="both")
    p.frustum(0, 0, 0.0245, 0.0285, 0.0125, 0.0125, 8, B, R22, caps="both")
    p.frustum(0, 0, -0.002, 0.013, 0.0105, 0.0015, 8, N, R22, caps="none")
    p.frustum(0, 0, 0.013, 0.0245, 0.0015, 0.0105, 8, N, R22, caps="none")
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box((sx * 0.0085, 0.0125, sz * 0.0085), (0.0022, 0.0265, 0.0022), B)


def t_blackout(p):
    plug(p)
    cy = 0.009
    with p.frame(T_(0, cy, 0) @ R_(90, "X")):
        p.frustum(0, 0, -0.004, 0.004, 0.0155, 0.0155, 8, B, R22, caps="both")
    arc_ring(p, (0, cy, 0.004), 0.0066, 0.0094, 125, 125 + 290, 10, N)
    p.strip((0, cy + 0.0045, 0.004), 0.011, 0.0032, Y, Z, N, tip=0.0012)


def t_jitter(p):
    plug(p)
    raw = [(0.008, 0.026), (-0.008, 0.004), (-0.001, 0.004), (-0.007, -0.012), (0.009, 0.010), (0.002, 0.010)]
    k = 0.84
    p.extrude([(x * k, (y + 0.012) * k - 0.006) for x, y in raw], 0.008, N)


def t_decrypt(p):
    plug(p)
    p.box((0, 0.001, 0), (0.024, 0.017, 0.010), B, 0.002, "all")
    p.disc((0, 0.0035, 0.005), 0.0028, 8, Z, N, rot=R22)
    p.strip((0, -0.0015, 0.005), 0.006, 0.0026, Y, Z, N, tip=0.001)
    arch = [(0.0075 * math.cos(math.radians(a)), 0.0185 + 0.0075 * math.sin(math.radians(a))) for a in (180, 150, 120, 90, 60, 30, 0)]
    path = [(-0.0075, 0.0095)] + [(x, y) for x, y in arch] + [(0.0075, 0.0150)]
    tube_xy(p, [(x, y, 0) for x, y in path], 0.0016, N)


def t_miner(p):
    plug(p)
    p.box((0, 0.0085, 0), (0.0036, 0.0295, 0.0036), B)
    cy, ro, ri = 0.012, 0.0135, 0.0085
    outer = [(ro * math.cos(math.radians(a)), cy + ro * math.sin(math.radians(a))) for a in (160, 130, 100, 80, 50, 20)]
    inner = [(ri * math.cos(math.radians(a)), cy + ri * math.sin(math.radians(a))) for a in (25, 55, 85, 95, 125, 155)]
    p.extrude(outer + [(0.0158, 0.0100)] + inner + [(-0.0158, 0.0100)], 0.006, N)


# (имя эффекта, строитель, неон, тело)
TOKENS = [
    ("EXTRACT_SHARD", t_extract_shard, palette.MONEY, palette.TOKEN_BODY),
    ("EXTRACT_DAEMON", t_extract_daemon, palette.ACC, palette.TOKEN_BODY),
    ("GHOST", t_ghost, palette.INK, palette.TOKEN_BODY),
    ("TIMESKEW", t_timeskew, palette.LABEL, palette.TOKEN_BODY),
    ("BLACKOUT", t_blackout, palette.INK2, palette.TOKEN_BODY_DARK),
    ("JITTER", t_jitter, palette.BAD, palette.TOKEN_BODY),
    ("DECRYPT", t_decrypt, palette.WARN, palette.TOKEN_BODY),
    ("MINER", t_miner, palette.OK, palette.TOKEN_BODY),
]


def build_tokens():
    for effect, fn, neon_hex, body_hex in TOKENS:
        bc.reset_scene()
        body = bc.body_material("token_body", body_hex)
        neon = bc.neon_material("token_neon_" + effect, neon_hex, palette.NEON_TOKEN)
        p = Part("Mesh", [body, neon])
        p.eps = 0.0005
        fn(p)
        bc.export_glb(os.path.join(MODELS, "deck", "daemon_%s.glb" % effect), [p.build()])


def main():
    build_deck()
    build_tokens()


if __name__ == "__main__":
    main()

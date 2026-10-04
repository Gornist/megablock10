"""Группа props: предметы узла. Запуск: blender -b --python props.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from env import curtain  # noqa: E402


def build_shard(out, name="shard", color="ice_white"):
    """Шард — лут: маленький вытянутый светящийся кристалл (8 см), origin в центре. Зашифрованный вариант — тот же меш, другой tint."""
    lib.reset()
    white = lib.lin(color)
    crystal = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.055, 0.055, 0.11))
    objs = lib.shell_stack(crystal, "shard", white, layers=3, grow=0.18, a_inner=0.9, a_outer=0.25)
    objs.append(lib.point_cloud("shard_pts", lib.sample_surface(crystal(), 70, seed=7, push=0.05), lib.lin("cyan"), half_size=0.003, seed=7))
    return lib.export(name, "props", objs, out, budget_tris=300, budget_points=120, origin="center",
                      notes=("зашифрованный: тот же меш, фиолетовое свечение" if color != "ice_white" else ""))


def build_vault(out, name="vault_closed", opened=False, seed=12):
    """Хранилище узла (сейф данных): прозрачный объём 0,7×0,7 м, высота ~0,7 м (с дыханием штрихов до ~0,95 м, выше сидящей руки не уходит).
    Поверхность — как у стен: четыре занавеса штрихов (шаг постоянный, пропуски, разброс в глубину, дыхание шейдером), без ниши и без чёрных блоков.
    Грани — цепочки точек, верх — редкая сетка точек. Внутри в центре виден шард (якорь Anchor_Shard, z = 0,5 м).
    Закрытое: передняя грань плотнее, каждый пятый штрих белый и выше («замок»). Открытое: на передней грани проём без штрихов, из объёма вверх уходят
    лёгкие штрихи света. Лицом к Blender +Y (Godot −Z). Тиры красят как окружение. Origin на полу."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    t, hmax = 0.35, 0.7
    streaks = []
    for face in range(4):  # 0 перед (+Y), 1 зад, 2 и 3 боковые
        for c, w, h, a in curtain(rng, -t + 0.01, t - 0.01, 30, hmax, depth=0.03, w_range=(0.007, 0.014), p_gap=0.1 if face else (0.05 if not opened else 0.1)):
            if face == 0:
                if opened and abs(c.x) < 0.15:  # проём: штрихов нет
                    continue
                pos = Vector((c.x, t + c.y, c.z))
            elif face == 1:
                pos = Vector((c.x, -t + c.y, c.z))
            else:
                pos = Vector(((t if face == 2 else -t) + c.y, c.x, c.z))
            streaks.append((pos, w, h, min(a, 0.7)))
    if not opened:  # «замок»: белые высокие штрихи на лицевой грани
        for i in range(-3, 4, 2):
            streaks.append((Vector((i * 0.09, t + 0.02, 0.4)), 0.010, 0.4, 0.95, ice))
    else:  # свет вверх из объёма
        for _ in range(8):
            h = rng.uniform(0.15, 0.3)
            streaks.append((Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0.7 + h / 2)), rng.uniform(0.007, 0.012), h / 2, rng.uniform(0.25, 0.6)))
    objs = [lib.streak_set("vault_curtain", streaks, cy)]
    segs = [((sx * t, sy * t, 0.0), (sx * t, sy * t, 0.8)) for sx in (-1, 1) for sy in (-1, 1)]  # вертикальные рёбра
    segs += [((-t, sy * t, 0.7), (t, sy * t, 0.7)) for sy in (-1, 1)] + [((sx * t, -t, 0.7), (sx * t, t, 0.7)) for sx in (-1, 1)]  # рамка верха
    segs += [((-t, sy * t, 0.0), (t, sy * t, 0.0)) for sy in (-1, 1)] + [((sx * t, -t, 0.0), (sx * t, t, 0.0)) for sx in (-1, 1)]  # основание
    pts = lib.sample_lines(segs, 26, spread=0.006, seed=seed, min_z=0.006)
    pts += lib.sample_box((0, 0, 0.7), (0.66, 0.66, 0.02), 24, seed=seed + 1)  # верх: редкая сетка точек
    objs.append(lib.point_cloud("vault_pts", pts, cy, half_size=0.009, seed=seed, a_min=0.45, a_max=1.0, on_floor=True))
    objs.append(lib.anchor("Anchor_Shard", (0, 0, 0.5)))
    return lib.export(name, "props", objs, out, budget_tris=500, budget_points=420, budget_streaks=160, origin="floor",
                      notes="якорь Anchor_Shard в центре (z 0,5); лицом к Blender +Y (Godot −Z)")


def build_portal(out, name="portal_open", opened=True, seed=5):
    """Портал в соседний узел: диск радиуса 1,5 м (радиус прохода по ТЗ), вертикальный, центр на высоте 1,5 м. Открытый: мембрана из ~80 вертикальных
    штрихов, высота каждого по хорде круга (силуэт диска), прозрачнее к центру, глубина «рябит» плавной волной с шумом; обод — цепочка ярких точек.
    Закрытый (за нетраннером охотится Black ICE): мембрана осыпалась, остались редкие короткие штрихи у нижней дуги, обод тусклый с пропусками.
    Цвет ICE не запекается: охоту игра показывает шрамом (set_corruption). Имя меша мембраны *_mid: длина дышит от центра. Origin на полу."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    R, cz, pitch = 1.5, 1.5, 0.035
    ph = rng.uniform(0, 6.28)
    st = []
    for i in range(int(2 * R / pitch)):
        if rng.random() < 0.07:
            continue
        x = -R + pitch * (i + 0.5)
        chord = math.sqrt(max(R * R - x * x, 0.0))
        y = 0.05 * math.sin(x * 2.7 + ph) + rng.uniform(-0.03, 0.03)
        rim = (abs(x) / R) ** 2
        if opened:
            h = chord * rng.uniform(0.92, 1.0)
            st.append((Vector((x, y, cz)), rng.uniform(0.008, 0.016), h, 0.12 + 0.55 * rim * rng.uniform(0.7, 1.0)))
        elif rng.random() < 0.35:  # осыпалась: короткие штрихи от нижней дуги
            h = chord * rng.uniform(0.07, 0.22)
            st.append((Vector((x, y, cz - chord + h)), rng.uniform(0.008, 0.014), h, rng.uniform(0.1, 0.3)))
    objs = [lib.streak_set("portal_membrane_mid", st, cy)]
    n = int(2 * math.pi * R * (38 if opened else 30))
    rim_pts = [Vector((R * math.cos(a), rng.uniform(-0.03, 0.03), cz + R * math.sin(a))) for a in (math.tau * (k + rng.random()) / n for k in range(n))]
    if not opened:
        rim_pts = [p for p in rim_pts if rng.random() < 0.5]
        rim_pts += [Vector((rng.uniform(-0.06, 0.06), 0.0, 0.0)) for _ in range(6)]  # ножка обода всегда у пола (origin «на полу»)
    objs.append(lib.point_cloud("portal_rim", rim_pts, (ice if opened else cy), half_size=0.014, seed=seed, a_min=(0.6 if opened else 0.2), a_max=(1.0 if opened else 0.5), on_floor=True))
    return lib.export(name, "props", objs, out, budget_tris=2000, budget_points=(400 if opened else 260), budget_streaks=(100 if opened else 40), origin="floor",
                      notes="радиус прохода 1,5 м; закрыт, пока за нетраннером охотится Black ICE")


if __name__ == "__main__":
    o = lib.args()
    build_shard(o)
    build_shard(o, "shard_encrypted", "violet")
    build_vault(o, "vault_closed", False, 12)
    build_vault(o, "vault_open", True, 12)
    build_portal(o, "portal", True, 5)
    build_portal(o, "portal_locked", False, 5)

"""Группа props: предметы узла. Запуск: blender -b --python props.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

from mathutils import Vector

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


def build_vault(out, name="vault_closed", opened=False, seed=12):
    """Хранилище узла (сейф данных): полупрозрачный стеклянный блок 0,7×0,7×0,95 м (выше сидящей руки не уходит) с окном-нишей на лицевой стороне (Blender +Y = Godot −Z),
    в нише виден шард («без демона предмет видно, но не взять»). Закрытое: перед нишей занавес ярких штрихов («замок»); открытое: занавес
    ушёл на порог, из ниши льётся свет. Грани блока и ниши — цепочки частиц. Якорь Anchor_Shard в нише. Тиры красят как окружение. Origin на полу."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    # Корпус — не чёрный ящик, а стекло: две вложенные оболочки (аддитивный Френель, ярче у силуэта) и редкие штрихи-«колонны данных» внутри.
    # Нишу не вырезаем: сквозь стекло шард виден с любой стороны; перед нишей колонн нет.
    box = lambda: lib.box_bm((0.70, 0.70, 0.95), bevel=0.02, center=(0, 0, 0.475))
    objs = lib.shell_stack(box, "vault_glass", cy, layers=2, grow=0.025, a_inner=0.09, a_outer=0.04, pivot=(0, 0, 0))
    fill = []
    for ix in range(5):
        for iy in range(5):
            x, y = -0.28 + 0.14 * ix, -0.28 + 0.14 * iy
            if abs(x) < 0.21 and y > -0.05 or rng.random() < 0.3:  # перед нишей и на 30% мест пусто
                continue
            h = rng.uniform(0.08, 0.3)
            fill.append((Vector((x + rng.uniform(-0.02, 0.02), y + rng.uniform(-0.02, 0.02), 0.04 + rng.uniform(0, 0.8) + h / 2)), rng.uniform(0.006, 0.010), h / 2, rng.uniform(0.2, 0.5)))
    objs.append(lib.streak_set("vault_fill", fill, cy))
    t, f = 0.35, 0.17  # половина стороны блока и половина ширины ниши
    segs = [((sx * t, t, 0.0), (sx * t, t, 0.95)) for sx in (-1, 1)]                                   # передние вертикальные рёбра
    segs += [((-t, t, 0.95), (t, t, 0.95)), ((-t, t, 0.0), (t, t, 0.0))] + [((sx * t, -t, 0.95), (sx * t, t, 0.95)) for sx in (-1, 1)]
    segs += [((-f, t, 0.42), (f, t, 0.42)), ((-f, t, 0.80), (f, t, 0.80)), ((-f, t, 0.42), (-f, t, 0.80)), ((f, t, 0.42), (f, t, 0.80))]  # рамка ниши
    edge = lib.sample_lines(segs, 26, spread=0.006, seed=seed, min_z=0.006)
    edge += lib.sample_box((0, 0.12, 0.61), (0.26, 0.20, 0.30), 30, seed=seed + 1)  # свечение внутри ниши
    objs.append(lib.point_cloud("vault_pts", edge, cy, half_size=0.009, seed=seed, a_min=0.45, a_max=1.0, on_floor=True))
    if not opened:  # «замок»: занавес штрихов поперёк ниши (плоскость y = 0,33), каждый четвёртый белый
        gate = [(Vector((-0.155 + 0.0225 * i, 0.33 + rng.uniform(-0.008, 0.008), 0.61)), rng.uniform(0.007, 0.011), 0.19, rng.uniform(0.6, 1.0), (ice if i % 4 == 0 else cy)) for i in range(14)]
    else:  # открыт: занавес ушёл на порог, из ниши льётся свет
        gate = [(Vector((rng.uniform(-0.15, 0.15), 0.33, 0.42 + h / 2)), 0.008, h / 2, 0.3, cy) for h in [rng.uniform(0.03, 0.07) for _ in range(7)]]
        gate += [(Vector((rng.uniform(-0.14, 0.14), rng.uniform(0.34, 0.355), 0.42 + h / 2)), rng.uniform(0.008, 0.014), h / 2, rng.uniform(0.4, 0.9), (ice if rng.random() < 0.3 else cy))
                 for h in [rng.uniform(0.3, 0.7) for _ in range(12)]]
    objs.append(lib.streak_set("vault_gate", gate, cy))
    objs.append(lib.anchor("Anchor_Shard", (0, 0.12, 0.61)))
    return lib.export(name, "props", objs, out, budget_tris=2000, budget_points=260, budget_streaks=80, origin="floor",
                      notes="якорь Anchor_Shard в нише; лицом к Blender +Y (Godot −Z)")


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
    build_vault(o, "vault_closed", False, 12)
    build_vault(o, "vault_open", True, 12)
    build_portal(o, "portal_open", True, 5)
    build_portal(o, "portal_closed", False, 5)

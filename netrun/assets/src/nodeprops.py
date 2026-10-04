"""Группа props, предметы узла: кресло, датчик, мёртвая дека. Запуск: blender -b --python nodeprops.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_seat(out, name="seat", seed=3):
    """Кресло узла: низкая круглая платформа, на которой собирается аватар (игра только сидя). Чёрный диск R 0,6 м высотой 0,14 м с подсвеченным верхним
    контуром, по краю россыпь точек, сзади дуга из 11 тонких штрихов-«спинки» (до 1,05 м, дышат) — опора для взгляда и спины, но не стена.
    Якорь Anchor_Seat в центре платформы (место таза, высота 0,14 м). Origin на полу в центре. Лицом к Blender +Y (Godot −Z): спинка сзади."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    R, H = 0.6, 0.14
    disc = lib.cone_bm(R, R, H, segments=32, center=(0, 0, H / 2))
    glow = lib.lit_part(disc, H, 0.012, outer=lib.disc_glow(R))
    objs = [lib.obj_from_bm("seat_base", disc, "solid_dark", cy, rgb_fn=lib.combine_rgb([glow], cy, void))]
    back = []
    for i in range(11):
        a = math.radians(200 + 140 * i / 10)  # дуга сзади (−Y Blender), 140°
        hh = rng.uniform(0.55, 1.05)
        back.append((Vector((0.52 * math.cos(a), 0.52 * math.sin(a), H + hh / 2)), rng.uniform(0.008, 0.014), hh / 2, rng.uniform(0.3, 0.8), ice if i % 5 == 0 else cy))
    objs.append(lib.streak_set("seat_back", back, cy))
    pts = [Vector((0.5 * math.cos(a), 0.5 * math.sin(a), H + 0.006)) for a in (math.tau * (k + rng.uniform(0.2, 0.8)) / 26 for k in range(26)) if rng.random() > 0.15]
    objs.append(lib.point_cloud("seat_pts", pts, cy, half_size=0.012, seed=seed, a_min=0.4, a_max=0.9))
    objs.append(lib.anchor("Anchor_Seat", (0, 0, H)))
    return lib.export(name, "props", objs, out, budget_tris=300, budget_points=40, budget_streaks=16, origin="floor",
                      notes="якорь Anchor_Seat (место таза, 0,14 м); спинка сзади, лицом к Blender +Y (Godot −Z)")


def build_sensor(out, name="sensor", seed=9):
    """Стационарный датчик узла: чёрная колонна 0,14×0,14×1,0 м с подсвеченным верхним контуром, на ней «глаз» — ядро из белых оболочек (шар 7 см)
    и кольцо из 16 точек вокруг него на высоте 1,2 м. Два тонких штриха-антенны вверх. Цвет окружения (голубая гамма), красного нет: он только для угрозы.
    Тревога — не в ассете: игра красит и усиливает материал. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    col = lib.box_bm((0.14, 0.14, 1.0), center=(0, 0, 0.5))
    glow = lib.lit_part(col, 1.0, 0.012)
    objs = [lib.obj_from_bm("sensor_column", col, "solid_dark", cy, rgb_fn=lib.combine_rgb([glow], cy, void))]
    eye = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.07, 0.07, 0.07), center=(0, 0, 1.2))
    objs += lib.shell_stack(eye, "sensor_eye", ice, layers=3, grow=0.3, a_inner=0.9, a_outer=0.25, pivot=(0, 0, 1.2))
    ring = [Vector((0.16 * math.cos(a), 0.16 * math.sin(a), 1.2 + rng.uniform(-0.004, 0.004))) for a in (math.tau * k / 16 for k in range(16))]
    objs.append(lib.point_cloud("sensor_ring", ring, cy, half_size=0.011, seed=seed, a_min=0.6, a_max=1.0))
    ant = [(Vector((dx, 0.0, 1.0 + hh / 2)), 0.007, hh / 2, 0.8, ice) for dx, hh in ((-0.04, 0.45), (0.05, 0.3))]
    objs.append(lib.streak_set("sensor_antenna", ant, cy))
    return lib.export(name, "props", objs, out, budget_tris=500, budget_points=40, budget_streaks=8, origin="floor",
                      notes="тревога задаётся игрой (материал), красного в ассете нет")


def build_dead_deck(out, name="dead_deck", seed=17):
    """Мёртвая дека: выведенная из строя кибердека, которую можно подобрать. Небольшой чёрный блок 18×11×3,5 см, экран погашен, по верхнему контуру
    янтарная приглушённая подсветка, из-за которой читается «вещь», а не мусор; несколько «битых пикселей» янтарными точками и две короткие искры-штриха.
    Янтарь только у деки (красный зарезервирован за угрозой). Origin в центре."""
    lib.reset()
    rng = random.Random(seed)
    amber, void = lib.lin("amber"), lib.lin("void")
    blk = lib.box_bm((0.18, 0.11, 0.035), bevel=0.003, center=(0, 0, 0))
    glow = lib.lit_part(blk, 0.0175, 0.004)
    objs = [lib.obj_from_bm("dead_deck_body", blk, "solid_dark", amber, rgb_fn=lib.combine_rgb([glow], tuple(c * 0.8 for c in amber), void))]
    dead = [Vector((rng.uniform(-0.07, 0.07), rng.uniform(-0.04, 0.04), 0.0185)) for _ in range(9)]
    objs.append(lib.point_cloud("dead_deck_pixels", dead, amber, half_size=0.0035, seed=seed, a_min=0.15, a_max=0.5))
    sparks = [(Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.03, 0.03), 0.0175 + 0.015)), 0.002, 0.015, rng.uniform(0.25, 0.5), amber) for _ in range(2)]
    objs.append(lib.streak_set("dead_deck_sparks", sparks, amber))
    return lib.export(name, "props", objs, out, budget_tris=300, budget_points=20, budget_streaks=4, origin="center",
                      notes="тусклая янтарная подсветка контура, экран погашен")


if __name__ == "__main__":
    o = lib.args()
    build_seat(o)
    build_sensor(o)
    build_dead_deck(o)

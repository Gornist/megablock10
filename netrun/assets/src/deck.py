"""Группа deck: кибердека на запястье и токены восьми демонов. Запуск: blender -b --python deck.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_wrist_deck(out, name="wrist_deck", seed=23):
    """Кибердека на запястье (кустарная профессиональная вещь, не часы): ремень по запястью (кольцо из цепочек точек радиусом 3 см, шириной 4 см, две пряжки
    ярче), на нём асимметричный чёрный блок 9×6×2,2 см с подсвеченным янтарным верхним контуром; сверху плоскость экрана 7,5×4,4 см (меш `deck_screen`,
    тёмный: игра подставляет SubViewport) и под ней ряд из пяти гнёзд демонов (диски-кольца из точек 1,8 см; якоря Anchor_Slot0…Anchor_Slot4 — место токена).
    Сбоку «открытая электроника»: пара коротких янтарных штрихов-проводов, плата точками. Янтарь/оранжевый — цвет деки (красный за угрозой).
    Origin в точке крепления (центр запястья, ось руки вдоль X Blender). Размеры реальные."""
    lib.reset()
    rng = random.Random(seed)
    amber, ice, void = lib.lin("amber"), lib.lin("ice_white"), lib.lin("void")
    blk = lib.box_bm((0.09, 0.06, 0.022), bevel=0.003, center=(0.0, 0.0, 0.043))
    glow = lib.lit_part(blk, 0.054, 0.003)
    objs = [lib.obj_from_bm("deck_body", blk, "solid_dark", amber, rgb_fn=lib.combine_rgb([glow], tuple(c * 0.9 for c in amber), void))]
    scr = lib.box_bm((0.075, 0.044, 0.0006), center=(0.0, 0.004, 0.0546))
    objs.append(lib.obj_from_bm("deck_screen", scr, "solid_dark", amber, rgb_fn=lambda co: void))
    strap = []
    for x in (-0.018, -0.006, 0.006, 0.018):
        for k in range(40):
            a = math.tau * (k + rng.uniform(0.0, 1.0)) / 40
            if math.sin(a) > 0.55:  # верх закрыт блоком
                continue
            strap.append(Vector((x + rng.uniform(-0.002, 0.002), 0.03 * math.cos(a), 0.03 * math.sin(a) + 0.0)))
    buckle = [Vector((x, 0.03 * math.cos(a), 0.03 * math.sin(a))) for x in (-0.02, 0.02) for a in (math.radians(235), math.radians(245))]
    objs.append(lib.point_cloud("deck_strap", strap, lib.lin("cyan"), half_size=0.0016, seed=seed, a_min=0.3, a_max=0.7))
    objs.append(lib.point_cloud("deck_buckles", buckle, ice, half_size=0.0028, seed=seed + 1, a_min=0.8, a_max=1.0))
    slots = []
    for i in range(5):
        cx = -0.032 + 0.016 * i
        slots += [Vector((cx + 0.007 * math.cos(a), -0.021 + 0.007 * math.sin(a) * 0.9, 0.0555)) for a in (math.tau * k / 10 for k in range(10))]
        objs.append(lib.anchor(f"Anchor_Slot{i}", (cx, -0.021, 0.056)))
    objs.append(lib.point_cloud("deck_slots", slots, amber, half_size=0.0013, seed=seed + 2, a_min=0.6, a_max=1.0))
    board = [Vector((0.05 + rng.uniform(0, 0.012), rng.uniform(-0.022, 0.022), 0.04 + rng.uniform(-0.008, 0.008))) for _ in range(18)]
    wires = [(Vector((0.047, y, 0.052)), 0.0012, 0.008 * rng.uniform(0.6, 1.2), 0.8, amber) for y in (-0.016, 0.012)]
    objs.append(lib.point_cloud("deck_board", board, amber, half_size=0.0016, seed=seed + 3, a_min=0.4, a_max=0.9))
    objs.append(lib.streak_set("deck_wires", wires, amber))
    objs.append(lib.anchor("Anchor_Screen", (0.0, 0.004, 0.055)))
    return lib.export(name, "deck", objs, out, budget_tris=2000, budget_points=200, budget_streaks=8, origin="center",
                      notes="якоря Anchor_Slot0…4 (гнёзда) и Anchor_Screen; меш deck_screen — плоскость под SubViewport; ось руки вдоль X")


def _tok(name, parts, rgb_main, pts=None, rgb_pts=None, seed=1, extra_streaks=None):
    objs = []
    for k, (maker, layers, grow, ai, ao) in enumerate(parts):
        objs += lib.shell_stack(maker, f"{name}_{k}", rgb_main, layers=layers, grow=grow, a_inner=ai, a_outer=ao)
    if pts:
        objs.append(lib.point_cloud(f"{name}_pts", pts, rgb_pts or rgb_main, half_size=0.0016, seed=seed, a_min=0.5, a_max=1.0))
    if extra_streaks:
        objs.append(lib.streak_set(f"{name}_streaks", extra_streaks, rgb_main))
    return objs


def _ring(r, n, z=0.0, tilt=0.0, seed=1):
    rng = random.Random(seed)
    out = []
    for k in range(n):
        a = math.tau * k / n
        v = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        v = Vector((v.x, v.y * math.cos(tilt) - 0.0, v.y * math.sin(tilt))) + Vector((0, 0, z))
        out.append(v + Vector((rng.uniform(-0.0006, 0.0006),) * 3))
    return out


def build_daemons(out):
    """Токены демонов в слотах деки (4 см, origin в центре). Форма различима без подписи; красного нет (он за угрозой). Серия по смыслу:
    EXTRACT_SHARD — вытянутый кристалл (как шард), EXTRACT_DAEMON — две сцепленные клетки (кольцо и ядро), GHOST — размытое облако точек вокруг
    прозрачной сферы, TIMESKEW — песочные часы, BLACKOUT — чёрная сфера с кольцом света вокруг, JITTER — зигзаг точек, DECRYPT — открытый куб
    (три грани) с ядром внутри, MINER — пирамидка из ступеней."""
    ice, cy, bl, vi, am = lib.lin("ice_white"), lib.lin("cyan"), lib.lin("blue"), lib.lin("violet"), lib.lin("amber")
    void = lib.lin("void")
    sc = 0.5

    def run(name, builder, tris=300, pts=140, st=8):
        lib.reset()
        objs = builder()
        lib.export(name, "deck", objs, out, budget_tris=tris, budget_points=pts, budget_streaks=st, origin="center", notes="токен демона 4 см, форма читается без подписи")

    def shard():
        mk = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.012, 0.012, 0.03))
        return _tok("t_shard", [(mk, 3, 0.18, 0.9, 0.25)], ice, pts=lib.sample_surface(mk(), 20, seed=2, push=0.006), rgb_pts=cy, seed=2)

    def extract_daemon():
        core = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.012, 0.012, 0.012))
        return _tok("t_exd", [(core, 3, 0.2, 0.9, 0.3)], cy, pts=_ring(0.022, 28, 0.0, 0.0, 3) + _ring(0.022, 28, 0.0, math.pi / 2, 4), rgb_pts=ice, seed=3)

    def ghost():
        mk = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.016, 0.016, 0.02))
        rng = random.Random(4)
        cloud = [Vector((rng.gauss(0, 0.012), rng.gauss(0, 0.012), rng.gauss(0, 0.015))) for _ in range(46)]
        return _tok("t_ghost", [(mk, 2, 0.35, 0.35, 0.1)], vi, pts=cloud, rgb_pts=vi, seed=4)

    def timeskew():
        def mk():
            return lib.merge_bm(lib.cone_bm(0.016, 0.002, 0.018, 12, center=(0, 0, 0.011)), lib.cone_bm(0.002, 0.016, 0.018, 12, center=(0, 0, -0.011)))
        sand = [Vector((random.Random(k).uniform(-0.004, 0.004), random.Random(k + 9).uniform(-0.004, 0.004), -0.014 + 0.002 * (k % 5))) for k in range(14)]
        return _tok("t_ts", [(mk, 2, 0.12, 0.6, 0.2)], bl, pts=sand, rgb_pts=ice, seed=5)

    def blackout():
        sph = lib.ico_bm(0.018, subdiv=2)
        objs = [lib.obj_from_bm("t_bo_sphere", sph, "solid_dark", void, alpha=1.0)]
        objs.append(lib.point_cloud("t_bo_ring", _ring(0.027, 36, 0.0, 0.35, 6) + _ring(0.027, 36, 0.0, -0.35, 7), vi, half_size=0.0018, seed=6, a_min=0.6, a_max=1.0))
        return objs

    def jitter():
        rng = random.Random(7)
        zig = []
        for k in range(36):
            t = k / 35
            zig.append(Vector((-0.02 + 0.04 * t, 0.0, (0.009 if k % 6 < 3 else -0.009) + rng.uniform(-0.001, 0.001))))
        return [lib.point_cloud("t_jit_zig", zig, am, half_size=0.0018, seed=7, a_min=0.6, a_max=1.0)] + [lib.point_cloud("t_jit_echo", [p + Vector((0.0, 0.006, 0.0)) for p in zig[::2]], am, half_size=0.0012, seed=8, a_min=0.2, a_max=0.4)]

    def decrypt():
        faces = lambda: lib.box_bm((0.026, 0.026, 0.026), bevel=0.002)
        core = [Vector((random.Random(k).uniform(-0.005, 0.005), random.Random(k + 5).uniform(-0.005, 0.005), random.Random(k + 11).uniform(-0.005, 0.005))) for k in range(16)]
        edges = []
        for a in (-1, 1):
            for b in (-1, 1):
                for c in (-1, 1):
                    edges.append(Vector((a * 0.013, b * 0.013, c * 0.013)))
        return _tok("t_dec", [(faces, 2, 0.12, 0.35, 0.12)], cy, pts=core + edges, rgb_pts=ice, seed=9)

    def miner():
        steps = [lib.box_bm((0.034 - 0.009 * i, 0.034 - 0.009 * i, 0.009), center=(0, 0, -0.014 + 0.0095 * i)) for i in range(4)]
        body = lib.merge_bm(*steps)
        pts = [Vector((random.Random(k).uniform(-0.016, 0.016), random.Random(k + 5).uniform(-0.016, 0.016), -0.0185)) for k in range(14)]
        o = lib.obj_from_bm("t_min_body", body, "solid_dark", am, rgb_fn=lambda co: tuple(c * 0.8 for c in am) if (co.z > 0.0 and abs(co.z - round(co.z / 0.0095) * 0.0095) < 0.003) else void)
        return [o, lib.point_cloud("t_min_pts", pts, am, half_size=0.0016, seed=10, a_min=0.5, a_max=1.0)]

    for name, fn in (("daemon_EXTRACT_SHARD", shard), ("daemon_EXTRACT_DAEMON", extract_daemon), ("daemon_GHOST", ghost), ("daemon_TIMESKEW", timeskew),
                     ("daemon_BLACKOUT", blackout), ("daemon_JITTER", jitter), ("daemon_DECRYPT", decrypt), ("daemon_MINER", miner)):
        run(name, fn)


if __name__ == "__main__":
    o = lib.args()
    build_wrist_deck(o)
    build_daemons(o)

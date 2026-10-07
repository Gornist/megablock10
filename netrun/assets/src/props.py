"""Группа props: предметы узла. Запуск: blender -b --python props.py -- --out <корень netrun/assets>"""
import math
import os
import random
import struct
import sys

import bmesh
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from env import curtain, _slab_streaks  # noqa: E402


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


# ================================================================ «волюметрик»: предметы узла в стиле Сети (интерактивное читается с 1–3 м)
# Рецепт (решение владельца и Godot-сессии): жёсткое ядро — чёрный объём solid_dark с яркой тонкой кромкой — и поверх мягкая оболочка из штрихов,
# точек и слабой вуали (`*_skirt`). Красного нет. Отражения в полу делает клиент (scale.y = −1, 0,18).

def _f32(c):
    return struct.unpack("f", struct.pack("f", float(c)))[0]


def _key(co):
    """Ключ вершины в float32: меш хранит float32, а bmesh — float64, ключи иначе расходятся на границе округления."""
    return tuple(round(_f32(c), 5) for c in co)


def _xf_glow(bm, is_glow, rot=(0, 0, 0), offset=(0, 0, 0)):
    """Классифицировать вершины как «светятся» ДО поворота (в простых координатах), повернуть и сместить, вернуть множество ключей светящихся."""
    flags = [bool(is_glow(v.co)) for v in bm.verts]
    lib.xform_bm(bm, rot=rot, offset=offset)
    return {_key(v.co) for v, f in zip(bm.verts, flags) if f}


def _scaled(rgb, k):
    return tuple(c * k for c in rgb)


def _ring_pts(r, z, n, rng, cx=0.0, cy=0.0, jitter=0.0):
    return [Vector((cx + r * math.cos(a), cy + r * math.sin(a), z + (rng.uniform(-jitter, jitter) if jitter else 0.0)))
            for a in (math.tau * (k + 0.5) / n for k in range(n))]


def _rect_pts(hx, hy, z, per_m, rng):
    c = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    segs = [((c[i][0], c[i][1], z), (c[(i + 1) % 4][0], c[(i + 1) % 4][1], z)) for i in range(4)]
    return lib.sample_lines(segs, per_m, spread=0.002, seed=rng.randint(0, 9999))


def build_vault_volume(out, name="vault", seed=12):
    """Хранилище узла «волюметрик»: ОДИН файл на три состояния. Общий корпус (чёрный постамент 0,6×0,6×0,3 м и широкий тонкий лоток 0,78×0,74×0,03 м с яркой
    кромкой ice_white, цепочка точек по кромке, вуаль `vault_skirt` и свисающие штрихи `vault_streaks_hang` вокруг лотка) + узлы-группы
    State_closed (шард внутри: крышка и клетка из штрихов 0,78 м, ядро), State_open (створки подняты, столб света к ShardSlot, кольца), State_empty
    (низкий тусклый лоток с пунктирной меткой и «крестом»: шард вынесен), Tier_1..3 (кумулятивные засечки на лицевой грани постамента) и метка ShardSlot (центр
    шарда, 1,0 м над полом). Клиент включает нужное через visible. Лицом к Blender +Y (Godot −Z), origin на полу."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    HX, HY, ZB, ZT = 0.45, 0.45, 0.30, 0.33  # лоток 0,9×0,9 м по центру клетки хода 1×1 м, щель 5 см (как у укрытий); лицо — +Y по оси клетки
    base = lib.box_bm((0.60, 0.60, ZB), bevel=0.012, center=(0, 0, ZB / 2))
    g_base = lib.lit_part(base, ZB, 0.012)
    tray = lib.box_bm((2 * HX, 2 * HY, 0.03), center=(0, 0, ZT - 0.015))
    g_tray = lib.lit_part(tray, ZT, 0.014)
    body = lib.merge_bm(base, tray)
    rim_c, rim_i = _scaled(cy, 0.6), _scaled(ice, 0.85)
    objs = [lib.obj_from_bm("vault_body", body, "solid_dark", cy, rgb_fn=lambda co: rim_i if g_tray(co) else (rim_c if g_base(co) else void))]
    sk = [(Vector((ax, ay, ZB)), Vector((bx, by, ZB)), Vector((0, 0, -0.28)), 0.95, 0.95)
          for ax, ay, bx, by in ((-HX, -HY, HX, -HY), (HX, -HY, HX, HY), (HX, HY, -HX, HY), (-HX, HY, -HX, -HY))]
    objs.append(lib.skirt_set("vault_skirt", sk, cy))
    hang = _slab_streaks(rng, 0.0, 0.0, HX, HY, ZT, 1.0, 0.065, 0.2, ZB - 0.02, 0.009, 0.014, 0.5)
    objs.append(lib.streak_set("vault_streaks_hang", hang, cy))
    rim_pts = _rect_pts(HX, HY, ZT + 0.004, 26, rng)
    objs.append(lib.point_cloud("vault_rim_pts", rim_pts, ice, half_size=0.007, seed=seed, a_min=0.6, a_max=1.0))
    # ---- State_closed: крышка, клетка (замок), ядро шарда внутри
    lid = lib.box_bm((0.60, 0.58, 0.025), center=(0, 0, ZT + 0.0125))
    g_lid = lib.lit_part(lid, ZT + 0.025, 0.012)
    zl = ZT + 0.025
    closed = [lib.obj_from_bm("closed_lid", lid, "solid_dark", cy, rgb_fn=lambda co: rim_i if g_lid(co) else void)]
    posts = [(Vector((sx * 0.29, sy * 0.28, (zl + 0.78) / 2)), 0.011, (0.78 - zl) / 2, 0.95, ice) for sx in (-1, 1) for sy in (-1, 1)]
    cur = []
    for face in range(4):
        for i in range(10):
            if rng.random() < 0.12:
                continue
            t, h = (i + 0.5) / 10 - 0.5, rng.uniform(0.12, 0.38)
            pos = [Vector((t * 0.54, 0.28, zl + h / 2)), Vector((t * 0.54, -0.28, zl + h / 2)),
                   Vector((0.29, t * 0.52, zl + h / 2)), Vector((-0.29, t * 0.52, zl + h / 2))][face]
            cur.append((pos, rng.uniform(0.007, 0.011), h / 2, rng.uniform(0.3, 0.6)))
    closed.append(lib.streak_set("closed_cage", posts + cur, cy))
    closed.append(lib.point_cloud("closed_ring_top", _rect_pts(0.29, 0.28, 0.78, 30, rng), ice, half_size=0.007, seed=seed + 1, a_min=0.7, a_max=1.0))
    closed.append(lib.point_cloud("closed_ring_mid", _rect_pts(0.29, 0.28, 0.57, 16, rng), cy, half_size=0.006, seed=seed + 2, a_min=0.3, a_max=0.6))
    core = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.07, 0.07, 0.09), center=(0, 0, 0.56))
    closed.append(lib.obj_from_bm("closed_core", core(), "shell_soft", ice, alpha=0.6, smooth=True))
    closed.append(lib.point_cloud("closed_dust", lib.sample_box((0, 0, 0.56), (0.2, 0.2, 0.2), 18, seed=seed + 3), cy, half_size=0.006, seed=seed + 3, a_min=0.4, a_max=0.8))
    # ---- State_open: створки подняты, столб света, кольца
    wings, wglow = [], set()
    for sign in (1, -1):
        w = lib.box_bm((0.30, 0.50, 0.025), center=(sign * 0.15, 0, 0))
        w.normal_update()
        bmesh.ops.inset_individual(w, faces=[f for f in w.faces if abs(f.normal.z) > 0.9], thickness=0.014)
        outer = lambda co, sg=sign: abs(co.y) > 0.25 - 1e-4 or abs(co.x - sg * 0.15) > 0.15 - 1e-4
        wglow |= _xf_glow(w, outer, rot=(0, -sign * 62, 0), offset=(sign * 0.24, 0, ZT))
        wings.append(w)
    wbm = lib.merge_bm(*wings)
    rim_w = _scaled(ice, 0.8)
    open_ = [lib.obj_from_bm("open_wings", wbm, "solid_dark", cy, rgb_fn=lambda co: rim_w if _key(co) in wglow else void)]
    col = []
    for _ in range(14):
        h, r, a = rng.uniform(0.25, 0.45), rng.uniform(0.0, 0.15), rng.uniform(0, math.tau)
        col.append((Vector((r * math.cos(a), r * math.sin(a), ZT + h / 2)), rng.uniform(0.008, 0.013), h / 2, rng.uniform(0.4, 0.85), ice if rng.random() < 0.3 else cy))
    open_.append(lib.streak_set("open_column", col, cy))
    open_.append(lib.point_cloud("open_rings", _ring_pts(0.16, ZT + 0.014, 28, rng) + _ring_pts(0.13, 0.80, 20, rng), ice, half_size=0.007, seed=seed + 4, a_min=0.6, a_max=1.0))
    # ---- State_empty: низкий тусклый лоток, пунктирный контур, «крест», пунктир на месте шарда
    emp = _rect_pts(0.25, 0.25, ZT + 0.004, 14, rng)
    emp += lib.sample_lines([((-0.25, -0.25, ZT + 0.004), (0.25, 0.25, ZT + 0.004)), ((-0.25, 0.25, ZT + 0.004), (0.25, -0.25, ZT + 0.004))], 10, spread=0.002, seed=seed + 5)
    emp += _ring_pts(0.12, ZT + 0.004, 14, rng)  # пунктирный круг на месте, где лежал шард; низко: у пустого хранилища силуэт низкий
    empty = [lib.point_cloud("empty_marks", emp, cy, half_size=0.006, seed=seed + 6, a_min=0.25, a_max=0.5)]
    # ---- тиры: кумулятивные засечки на лицевой грани постамента (1, 2, 3 штриха рядом)
    tiers = []
    for k in range(3):
        tiers.append(lib.group(f"Tier_{k + 1}", [lib.streak_set(f"vault_tier_{k + 1}", [(Vector((-0.08 + 0.08 * k, 0.306, 0.15)), 0.011, 0.07, 0.95, ice)], cy)]))
    groups = [lib.group("State_closed", closed), lib.group("State_open", open_), lib.group("State_empty", empty)]
    slot = lib.anchor("ShardSlot", (0, 0, 1.0))
    all_objs = objs + closed + open_ + empty + [t for g in tiers for t in [g] + list(g.children)] + groups + [slot]
    return lib.export(name, "props", all_objs, out, budget_tris=900, budget_points=500, budget_streaks=220, budget_draws=20, origin="floor",
                      notes="State_closed/open/empty, Tier_1..3 (кумулятивно), ShardSlot (1,0 м); лицом к Blender +Y (Godot −Z)")


def _crystal_bm(rx, hz):
    """Гранёный кристалл: шестигранная бипирамида (12 граней), ось Z, вершины ±hz, пояс радиуса rx."""
    bm = bmesh.new()
    top, bot = bm.verts.new((0, 0, hz)), bm.verts.new((0, 0, -hz))
    ring = [bm.verts.new((rx * math.cos(a), rx * math.sin(a), 0)) for a in (math.tau * k / 6 + math.tau / 12 for k in range(6))]
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new([ring[i], ring[j], top])
        bm.faces.new([ring[j], ring[i], bot])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm, [Vector(v.co) for v in ring], Vector(top.co), Vector(bot.co)


def build_shard(out, name="shard", encrypted=False):
    """Шард 13 см, origin в центре. Расшифрованный: чистый гранёный кристалл (12 плоских граней, shell_soft) с мягким ядром (две сглаженные оболочки) и
    яркими точками по рёбрам. Зашифрованный: тот же кристалл, но тусклый, без ядра, внутри клетки (три квадратных каркаса из точек, четыре ребра-штриха) и
    с глитч-полосами (пунктирные горизонтальные полосы, смещённые вбок) — отличим формой. Tier_1..3: кумулятивные кольца точек вокруг (центральное, верхнее, нижнее)."""
    lib.reset()
    rng = random.Random(7)
    cy, ice, vio = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("violet")
    hz, rx = 0.065, 0.032
    bm, ring, top, bot = _crystal_bm(rx, hz)
    objs = [lib.obj_from_bm("shard_facets", bm, "shell_soft", vio if encrypted else cy, alpha=(0.3 if encrypted else 0.65))]
    if not encrypted:
        edges = [(top, r) for r in ring] + [(bot, r) for r in ring] + [(ring[i], ring[(i + 1) % 6]) for i in range(6)]
        pts = [a + (b - a) * t for a, b in edges for t in (0.2, 0.45, 0.7, 0.92)]
        objs.append(lib.point_cloud("shard_edge_pts", pts, ice, half_size=0.003, seed=7, a_min=0.7, a_max=1.0))
        core = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.034, 0.034, 0.044))
        objs += lib.shell_stack(core, "shard_core", ice, layers=2, grow=0.5, a_inner=0.9, a_outer=0.35)
    else:
        h = 0.042
        cage = []
        for z in (-hz, 0.0, hz):
            cage += _rect_pts(h, h, z, 80, rng)
        objs.append(lib.point_cloud("shard_cage_pts", cage, vio, half_size=0.003, seed=8, a_min=0.7, a_max=1.0))
        objs.append(lib.streak_set("shard_cage_bars", [(Vector((sx * h, sy * h, 0.0)), 0.003, hz * 0.8, 0.7, ice) for sx in (-1, 1) for sy in (-1, 1)], vio))
        gl = []
        for k, z in enumerate((0.022, -0.016, 0.048)):  # глитч-полосы: пунктир шире клетки, каждая сдвинута вбок
            shift = (-1) ** k * 0.02
            for side in (1, -1):
                gl += [Vector((shift + x, side * 0.05, z)) for x in (-0.075, -0.045, -0.015, 0.02, 0.05, 0.075) if rng.random() > 0.15]
        objs.append(lib.point_cloud("shard_glitch_pts", gl, vio, half_size=0.0035, seed=9, a_min=0.6, a_max=1.0))
    tiers = []
    for k, z in enumerate((0.0, 0.04, -0.04)):  # кумулятивно: Tier_1 центральное кольцо, Tier_2 добавляет верхнее, Tier_3 нижнее
        ring_pts = _ring_pts(0.068, z, 18, rng)
        tiers.append(lib.group(f"Tier_{k + 1}", [lib.point_cloud(f"shard_tier_{k + 1}", ring_pts, ice, half_size=0.003, seed=20 + k, a_min=0.8, a_max=1.0)]))
    all_objs = objs + [t for g in tiers for t in [g] + list(g.children)]
    return lib.export(name, "props", all_objs, out, budget_tris=(400 if encrypted else 300), budget_points=(220 if encrypted else 160),
                      budget_streaks=(8 if encrypted else 0), origin="center",
                      notes=("зашифрованный: клетка и глитч-полосы, ядро скрыто" if encrypted else "расшифрованный: гранёный кристалл с ядром") + "; Tier_1..3 — кумулятивные кольца")


def build_daemon_token(out, name="daemon_token", seed=31):
    """Токен демона (лут): плоская тонкая шестиугольная «карта» ~0,13 м, парит (origin в центре), плоскость XZ. Чёрная плита 1,2 см с яркой кромкой с обеих
    сторон, вокруг шестиугольное кольцо из точек с РАЗРЫВОМ (одна грань пропущена), внутри слабое малое кольцо и яркая сердцевина (две мягкие оболочки).
    Формой не похож на гранёный шард."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    R, t = 0.058, 0.012
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=R, radius2=R, depth=t)
    bm.normal_update()
    bmesh.ops.inset_individual(bm, faces=[f for f in bm.faces if abs(f.normal.z) > 0.9], thickness=0.007)
    glow = _xf_glow(bm, lambda co: math.hypot(co.x, co.y) > R - 0.003, rot=(90, 0, 0))
    rim = _scaled(ice, 0.9)
    objs = [lib.obj_from_bm("token_plate", bm, "solid_dark", cy, rgb_fn=lambda co: rim if _key(co) in glow else void)]

    def hex_edge(rr, skip=()):
        c = [(rr * math.cos(math.radians(60 * k)), rr * math.sin(math.radians(60 * k))) for k in range(6)]
        out_pts = []
        for i in range(6):
            if i in skip:
                continue
            (ax, az), (bx, bz) = c[i], c[(i + 1) % 6]
            out_pts += [Vector((ax + (bx - ax) * u, 0.0, az + (bz - az) * u)) for u in (0.06, 0.22, 0.39, 0.56, 0.72, 0.89)]
        return out_pts

    objs.append(lib.point_cloud("token_ring", hex_edge(0.066, skip=(1,)), ice, half_size=0.005, seed=seed, a_min=0.8, a_max=1.0))
    objs.append(lib.point_cloud("token_inner", hex_edge(0.040), cy, half_size=0.0035, seed=seed + 1, a_min=0.35, a_max=0.6))
    core = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.04, 0.012, 0.04))
    objs += lib.shell_stack(core, "token_core", ice, layers=2, grow=0.5, a_inner=0.95, a_outer=0.4)
    return lib.export(name, "props", objs, out, budget_tris=200, budget_points=80, origin="center",
                      notes="плоскость XZ (лицо к ±Y Blender), кольцо с разрывом, светится с обеих сторон")


def build_hack_panel(out, name="hack_panel"):
    """Панель взлома: рамка 0,5×0,4 м (чёрная плита 3 см, яркая кромка, цепочка точек), наклон 25° к игроку (верх отклонён назад, нормаль экрана на 25° вверх),
    центр экрана на высоте 1,1 м, на тонкой стойке с плоским основанием. Узел `Screen` — квад 0,44×0,30 м с UV 0..1 (u вправо, v вниз, как видит игрок),
    материал-заглушка тёмно-бирюзовый; узел `ScreenAnchor` — центр экрана, его +Z (Godot) направлен от экрана к игроку. Лицом к Blender +Y (Godot −Z); origin на полу."""
    lib.reset()
    rng = random.Random(41)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    TILT, CZ = 25.0, 1.1
    R = Euler([math.radians(TILT), 0, 0]).to_matrix()
    tp = lambda x, y, z: R @ Vector((x, y, z)) + Vector((0, 0, CZ))
    frame = lib.box_bm((0.5, 0.03, 0.4))
    frame.normal_update()
    bmesh.ops.inset_individual(frame, faces=[f for f in frame.faces if f.normal.y > 0.9], thickness=0.016)
    fglow = _xf_glow(frame, lambda co: co.y > 0.014 and (abs(co.x) > 0.249 or abs(co.z) > 0.199), rot=(TILT, 0, 0), offset=(0, 0, CZ))
    rim = _scaled(ice, 0.85)
    objs = [lib.obj_from_bm("panel_frame", frame, "solid_dark", cy, rgb_fn=lambda co: rim if _key(co) in fglow else void)]
    pole = lib.box_bm((0.03, 0.03, 1.07), center=(0, -0.014, 0.02 + 0.535))
    foot = lib.box_bm((0.34, 0.34, 0.02), center=(0, 0, 0.01))
    g_foot = lib.lit_part(foot, 0.02, 0.012)
    pbm = lib.merge_bm(pole, foot)
    dim, rim_f = _scaled(cy, 0.45), _scaled(ice, 0.8)
    objs.append(lib.obj_from_bm("panel_stand", pbm, "solid_dark", cy, rgb_fn=lambda co: rim_f if g_foot(co) else (dim if co.z > 0.021 else void)))
    sc = bmesh.new()
    uv = sc.loops.layers.uv.new("UV0")
    cs = [(0.22, -0.15, (0, 0)), (-0.22, -0.15, (1, 0)), (-0.22, 0.15, (1, 1)), (0.22, 0.15, (0, 1))]  # слева→справа глазами игрока: +x слева; v вверх (glTF перевернёт)
    f = sc.faces.new([sc.verts.new(tp(x, 0.018, z)) for x, z, _ in cs])
    for loop, (_, _, t) in zip(f.loops, cs):
        loop[uv].uv = t
    objs.append(lib.obj_from_bm("Screen", sc, "solid_dark", (0.0, 0.07, 0.09)))
    chain = []
    for a, b in (((-0.25, -0.2), (0.25, -0.2)), ((0.25, -0.2), (0.25, 0.2)), ((0.25, 0.2), (-0.25, 0.2)), ((-0.25, 0.2), (-0.25, -0.2))):
        chain += lib.sample_line(tp(a[0], 0.022, a[1]), tp(b[0], 0.022, b[1]), 28, spread=0.0015, seed=rng.randint(0, 99))
    objs.append(lib.point_cloud("panel_edge_pts", chain, ice, half_size=0.006, seed=5, a_min=0.7, a_max=1.0))
    zb = tp(0, 0, -0.2)
    hang = []
    for i in range(14):
        if rng.random() < 0.15:
            continue
        ln = rng.uniform(0.08, 0.25)
        x = -0.235 + 0.47 * (i + 0.5) / 14
        p = tp(x, 0.0, -0.2)
        hang.append((Vector((p.x, p.y, p.z - ln / 2)), rng.uniform(0.008, 0.012), ln / 2, rng.uniform(0.4, 0.9)))
    objs.append(lib.streak_set("panel_streaks_hang", hang, cy))
    # +Z узла в Godot = нормаль экрана к игроку; в Blender это локальная −Y (оси Godot: X→X, Z_blender→Y, −Y_blender→Z)
    ly = -(R @ Vector((0, 1, 0)))  # локальная −Y = нормаль экрана к игроку
    lz = R @ Vector((0, 0, 1))     # локальная Z = «вверх» по плоскости экрана (в Godot станет Y)
    lx = ly.cross(lz)
    m = Matrix((lx, ly, lz)).transposed()
    anc = lib.anchor("ScreenAnchor", tp(0, 0.018, 0), euler=m.to_euler())
    return lib.export(name, "props", objs + [anc], out, budget_tris=300, budget_points=120, budget_streaks=20, origin="floor",
                      notes="Screen (квад 0,44×0,30, UV 0..1), ScreenAnchor (+Z Godot к игроку); наклон 25°, центр экрана 1,1 м")


def build_hack_pad(out, name="hack_pad", seed=51):
    """Площадка взлома под ногами: тонкая плита 0,9×0,9×0,03 м с яркой кромкой, цепочка точек по краю, два контура-следа и шеврон в сторону хранилища
    (Blender −Y, Godot +Z), вуаль `pad_skirt` поднимается от кромки на 0,25 м и короткие штрихи вдоль кромки. Игрок встаёт в 0,85 м перед хранилищем;
    ориентация как у хранилища (тот же yaw). Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice, void = lib.lin("cyan"), lib.lin("ice_white"), lib.lin("void")
    H, T = 0.45, 0.03
    plate = lib.box_bm((2 * H, 2 * H, T), center=(0, 0, T / 2))
    g = lib.lit_part(plate, T, 0.014)
    rim = _scaled(ice, 0.85)
    objs = [lib.obj_from_bm("pad_plate", plate, "solid_dark", cy, rgb_fn=lambda co: rim if g(co) else void)]
    sk = [(Vector((ax, ay, T)), Vector((bx, by, T)), Vector((0, 0, 0.25)), 0.9, 0.9)
          for ax, ay, bx, by in ((-H, -H, H, -H), (H, -H, H, H), (H, H, -H, H), (-H, H, -H, -H))]
    objs.append(lib.skirt_set("pad_skirt", sk, cy))
    objs.append(lib.point_cloud("pad_rim_pts", _rect_pts(H - 0.01, H - 0.01, T + 0.004, 26, rng), ice, half_size=0.007, seed=seed, a_min=0.6, a_max=1.0))
    marks = _rect_pts(0.06, 0.14, T + 0.004, 22, rng)
    marks = [Vector((p.x - 0.14, p.y, p.z)) for p in marks] + [Vector((p.x + 0.14, p.y, p.z)) for p in marks]
    for sx in (-1, 1):
        marks += [Vector((sx * 0.15 * u, -0.36 + 0.16 * u, T + 0.004)) for u in (0.15, 0.4, 0.65, 0.9)]
    objs.append(lib.point_cloud("pad_marks", marks, cy, half_size=0.006, seed=seed + 1, a_min=0.4, a_max=0.7))
    st = []
    for side in range(4):
        for q in range(8):
            if rng.random() < 0.15:
                continue
            u = (q + 0.5) / 8 * 2 * (H - 0.02) - (H - 0.02)
            e = [(u, -H), (H, u), (u, H), (-H, u)][side]
            ln = rng.uniform(0.06, 0.2)
            st.append((Vector((e[0], e[1], T + ln / 2)), rng.uniform(0.009, 0.013), ln / 2, rng.uniform(0.4, 0.8)))
    objs.append(lib.streak_set("pad_streaks", st, cy))
    return lib.export(name, "props", objs, out, budget_tris=120, budget_points=160, budget_streaks=40, origin="floor",
                      notes="шеврон указывает в Blender −Y (Godot +Z): в сторону хранилища; тот же yaw, что у хранилища")


if __name__ == "__main__":
    o = lib.args()
    build_shard(o)
    build_shard(o, "shard_encrypted", True)
    build_daemon_token(o)
    build_vault_volume(o)
    build_hack_panel(o)
    build_hack_pad(o)
    build_vault(o, "vault_closed", False, 12)
    build_vault(o, "vault_open", True, 12)
    build_portal(o, "portal", True, 5)
    build_portal(o, "portal_locked", False, 5)

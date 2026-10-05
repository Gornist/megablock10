"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>

Стиль по референсам Blackwall (STYLE.md): свет живёт в вертикальных штрихах, поверхности чёрные и непрозрачные, пол — ряды точек.
Стена — только занавес из штрихов (яркость плывёт вдоль стены); чёрные тайлы лежат на ПОЛУ, не на стенах; сплошных реек и
стеклянных плиток нет. Граница модуля — яркие штрихи у краёв, остальное рваное."""
import math
import os
import random
import sys

import bmesh

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


WALL_H = 3.0  # базовая высота штрихов стены, м; дыхание (breathe 0.3) даёт до ×1.3 → максимум 3.9 м, не выше 4 м


def _env(x, phase=0.0):
    """Плавная огибающая яркости вдоль стены 0..1 (кластеры ярче, провалы темнее)."""
    return 0.5 + 0.5 * math.sin(x * 3.1 + 1.3 + phase) * math.sin(x * 7.7 + 0.4 + phase)


def curtain(rng, x0, x1, n, hmax, depth=0.3, w_range=(0.008, 0.02), p_gap=0.1):
    """Занавес штрихов от пола. Шаг по горизонтали постоянный; в глубину (ось Y Blender) разброс: плавная волна + групповые
    «выступы» (несколько соседних штрихов смещены вместе) + случайный шум; где-то штрих пропущен (одиночные и по 2–3 подряд).
    Возвращает [(центр, w, h, a)]."""
    ph = [rng.uniform(0, 6.28) for _ in range(2)]
    pitch = (x1 - x0) / n
    out, gap, push, hold = [], 0, 0.0, 0
    for i in range(n):
        if gap > 0:
            gap -= 1
            continue
        if rng.random() < p_gap:  # пропуск: 1–3 штриха подряд
            gap = rng.randint(0, 2)
            continue
        if hold <= 0:  # групповой выступ: следующие 4–9 штрихов смещены вместе
            push, hold = rng.uniform(-0.6, 0.6) * depth, rng.randint(4, 9)
        hold -= 1
        x = x0 + pitch * (i + 0.5)
        y = depth * (0.35 * math.sin(x * 2.3 + ph[0]) + 0.2 * math.sin(x * 5.9 + ph[1])) + push + rng.uniform(-0.08, 0.08)
        y = max(-depth, min(depth, y))
        e = _env(x)
        full = hmax * rng.uniform(0.6, 1.0) * (0.8 + 0.2 * e)  # занавес: высота в пределах 60–100% от базовой, яркость плывёт по огибающей
        out.append((Vector((x, y, full / 2)), rng.uniform(*w_range), full / 2, 0.2 + 0.8 * e * rng.uniform(0.45, 1.0)))
    mid = (min(c[0].y for c in out) + max(c[0].y for c in out)) / 2  # центр разброса по глубине в нуле: модули стыкуются ровно
    return [(Vector((c.x, c.y - mid, c.z)), w, h, a) for c, w, h, a in out]


def build_wall(out, name="wall", seed=21):
    """Стена 2×2 м: занавес ~64 штрихов с плывущей яркостью, 6 ярких белых (две опоры по краям модуля), 3 чёрные плиты-перекрытия.
    Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = [lib.streak_set("wall_curtain", curtain(rng, -0.97, 0.97, 100, WALL_H), cy)]
    accents = [(Vector((-0.99, rng.uniform(-0.12, 0.12), 1.4)), 0.012, 1.4, 1.0), (Vector((0.99, rng.uniform(-0.12, 0.12), 1.5)), 0.012, rng.uniform(1.3, 1.5), 1.0)]
    for x in sorted(rng.uniform(-0.8, 0.8) for _ in range(rng.randint(3, 5))):
        hh = rng.uniform(1.0, 1.5)
        accents.append((Vector((x, rng.uniform(-0.25, 0.25), hh)), 0.011, hh, 0.95))
    objs.append(lib.streak_set("wall_accents", accents, ice))
    fill = lib.sample_box((0, 0, WALL_H / 2), (2.0, 0.4, WALL_H), 50, seed=5, min_z=0.01)  # россыпь точек по всей высоте стены
    objs.append(lib.point_cloud("wall_pts", fill, cy, half_size=0.007, seed=11, a_min=0.15, a_max=0.5, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=80, budget_streaks=120, origin="floor")


def build_portal_wall(out, name="portal_wall", seed=33, R=1.5, cz=1.5, gap=0.12):
    """Стена 4×3 м (два модуля) с круглым вырезом под портал (props/portal_*, диск R=1,5 м, центр z=1,5 м). Штрихи не пересекают круг:
    внутри колонки |x|<R+зазор штрих разбит на нижний (от пола, короче зазора с запасом на дыхание ×1,3) и верхний (от дуги вверх, дышит вверх).
    Вокруг выреза зазор gap, чтобы мембрана и обод портала не тонули в стене. Origin на полу в центре. Портал ставится в начало координат этого ассета."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    Rh = R + gap
    out_st = []
    for c, w, h, a in curtain(rng, -1.97, 1.97, 200, WALL_H):
        top = 2 * h  # полная высота штриха из занавеса
        if abs(c.x) >= Rh:
            out_st.append((c, w, h, a))
            continue
        ch = math.sqrt(Rh * Rh - c.x * c.x)
        lo = cz - ch  # нижняя дуга выреза
        hi = cz + ch  # верхняя дуга выреза
        L = lo / 1.3 * 0.95  # с дыханием (до ×1,3) нижний штрих не доходит до дуги
        if L > 0.1:
            out_st.append((Vector((c.x, c.y, L / 2)), w, L / 2, a))
        if top - hi > 0.1:  # верхний: основание на дуге, растёт вверх
            out_st.append((Vector((c.x, c.y, (hi + top) / 2)), w, (top - hi) / 2, a))
    objs = [lib.streak_set("wall_curtain", out_st, cy)]
    accents = []
    for x in sorted(rng.uniform(-1.8, 1.8) for _ in range(6)):
        if abs(x) < Rh + 0.2:
            continue
        hh = rng.uniform(1.0, 1.5)
        accents.append((Vector((x, rng.uniform(-0.25, 0.25), hh)), 0.011, hh, 0.95))
    objs.append(lib.streak_set("wall_accents", accents, ice))
    fill = [p for p in lib.sample_box((0, 0, WALL_H / 2), (4.0, 0.4, WALL_H), 100, seed=5, min_z=0.01) if (p.x ** 2 + (p.z - cz) ** 2) > (Rh + 0.05) ** 2]
    objs.append(lib.point_cloud("wall_pts", fill, cy, half_size=0.007, seed=11, a_min=0.15, a_max=0.5, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=150, budget_streaks=300, origin="floor",
                      notes="вырез под портал R=1,5 м, центр z=1,5; портал ставить в начало координат ассета")


def build_far_field(out, name="far_field", seed=41, size=11.0):
    """Дальний план: участок 11×11 м «города данных» за пределами комнаты. Пучки вертикальных штрихов (11–14 на участок) разной высоты (башни до 3,6 м: с дыханием ×1,3 ≤ 4,7 м, под потолком 5 м),
    между ними россыпь точек у пола. Без плотных стен: на расстоянии читается как далёкие столбы света, не закрывает комнату.
    Кладётся кольцами вокруг комнаты (вариантами seed, поворотами, масштабом ×1…×2); цвет задаёт тир (в комнате дальний план — HARD, голубой темнее).
    Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    half = size / 2 - 0.8
    st = []
    for _ in range(rng.randint(11, 14)):
        cx, cy_ = rng.uniform(-half, half), rng.uniform(-half, half)
        top = rng.choice([rng.uniform(1.2, 2.0), rng.uniform(2.0, 3.0), rng.uniform(3.0, 3.6)])
        for _ in range(rng.randint(4, 8)):
            hh = top * rng.uniform(0.35, 1.0)
            st.append((Vector((cx + rng.uniform(-0.35, 0.35), cy_ + rng.uniform(-0.35, 0.35), hh / 2)), rng.uniform(0.02, 0.05), hh / 2, rng.uniform(0.12, 0.42)))
    # три-четыре белых «маяка» (высокие тонкие) вместо яркости по всему полю
    for _ in range(2):
        hh = rng.uniform(3.0, 3.6)
        st.append((Vector((rng.uniform(-half, half), rng.uniform(-half, half), hh / 2)), 0.03, hh / 2, 0.6, ice))
    objs = [lib.streak_set("far_towers", st, cy)]
    pts = lib.sample_box((0, 0, 0.15), (size - 0.6, size - 0.6, 0.3), 110, seed=seed + 3, min_z=0.01)
    pts += [Vector((sx * (size / 2 - 0.15), sy * (size / 2 - 0.15), 0.03)) for sx in (-1, 1) for sy in (-1, 1)]  # угловые точки: габарит симметричен, участки стыкуются по центру
    objs.append(lib.point_cloud("far_pts", pts, cy, half_size=0.03, seed=seed, a_min=0.2, a_max=0.7, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=100, budget_points=140, budget_streaks=320, origin="floor",
                      notes="дальний план: класть кольцами вокруг комнаты, не ближе 2 м до стен")


def build_doorway(out, name="doorway", seed=8):
    """Проём 2×2 м (вход/выход): два занавеса по бокам, яркие белые штрихи — косяки, короткая бахрома сверху, ряды точек порога.
    Ширина прохода 1,1 м. Origin на полу в центре. Проход вдоль оси Z Godot."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    side = curtain(rng, -0.98, -0.66, 18, WALL_H, depth=0.22, p_gap=0.07) + curtain(rng, 0.66, 0.98, 18, WALL_H, depth=0.22, p_gap=0.07)
    objs = [lib.streak_set("door_curtain", side, cy)]
    jambs = [(Vector((sx * d, 0, 1.0)), 0.016, 1.0, 1.0) for sx in (-1, 1) for d in (0.52, 0.57, 0.62)]
    fringe = [(Vector((-0.55 + i * 0.1, rng.uniform(-0.03, 0.03), 2.0 - hh)), 0.008, hh, 0.7) for i in range(12) for hh in [rng.uniform(0.2, 0.55)]]
    objs.append(lib.streak_set("door_jambs", jambs + fringe, ice))
    th = [Vector((x, y, 0.0)) for x in [-0.5 + i * 0.125 for i in range(9)] for y in (-0.06, 0.06)]
    objs.append(lib.point_cloud("door_threshold", th, ice, half_size=0.018, seed=7, a_min=0.8, a_max=1.0, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=40, budget_streaks=80, origin="floor")


SLAB_T = 0.03  # толщина плиты, м: равна полной ширине штриха (решение владельца) — тонкий чёрный лист, а не колонна


def _slab_bm(cx, cyy, hx, hy, hh, sg):
    """Тонкая чёрная плита 2hx × 2hy × 0,03 м: верхняя (обращённая в комнату) поверхность на высоте sg·hh. У неё рамка шириной 1,4 см (inset),
    боковые грани разрезаны на 1,4 см ниже поверхности: подсвечивается только верхний край. Метка света — цвет вершины (см. _slab_rgb, шейдер solid_dark).
    Свет живёт не в боковых гранях (их почти нет: 3 см), а в штрихах, свисающих от кромок."""
    zf = sg * hh
    bm = lib.box_bm((2 * hx, 2 * hy, SLAB_T), center=(cx, cyy, zf - sg * SLAB_T / 2))
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, 0, zf - sg * 0.014), plane_no=(0, 0, 1))
    bm.normal_update()
    top = [f for f in bm.faces if f.normal.z * sg > 0.9 and abs(f.calc_center_median().z - zf) < 1e-4]
    bmesh.ops.inset_individual(bm, faces=top, thickness=0.014)
    return bm


def _slab_rgb(infos, glow, dark):
    """Цвет вершины плиты: glow на внешнем контуре верхней поверхности (светится), чёрный везде ниже и внутри рамки. infos — [(cx, cyy, hx, hy, zf)]."""
    def fn(co):
        for cx, cyy, hx, hy, zf in infos:
            if abs(co.z - zf) < 1e-4 and abs(abs(co.x - cx) - hx) < 1e-4 and abs(abs(co.y - cyy) - hy) < 1e-4:
                return glow
        return dark
    return fn


def _place_slabs(rng, kinds, area, bound, gap, max_n=60):
    """Расставить плиты разного размера без пересечений. kinds — [(вес, (wmin, wmax), (dmin, dmax))]; первая плита берётся из двух крупнейших видов
    (рядом с крупными всегда есть мелкие, как в референсе), дальше по весам, пока суммарная площадь не дойдёт до area. Центры в пределах ±bound
    с учётом размера, зазор между плитами gap. Возвращает [(cx, cy, hx, hy)]; квадраты и вытянутые, ориентация по x или по y случайна."""
    rects, got = [], 0.0
    for attempt in range(900):
        if got >= area * 0.93 or len(rects) >= max_n:
            break
        if not rects:
            k = rng.choice(kinds[:2])
        else:
            k = rng.choices(kinds, weights=[x[0] for x in kinds])[0]
        w, d = rng.uniform(*k[1]), rng.uniform(*k[2])
        if rng.random() < 0.5:
            w, d = d, w
        if got + w * d > area * 1.12:
            continue
        if w / 2 > bound or d / 2 > bound:
            continue
        cx, cyy = rng.uniform(-bound + w / 2, bound - w / 2), rng.uniform(-bound + d / 2, bound - d / 2)
        if any(abs(cx - x) < (w + 2 * hx) / 2 + gap and abs(cyy - y) < (d + 2 * hy) / 2 + gap for x, y, hx, hy in rects):
            continue
        rects.append((cx, cyy, w / 2, d / 2))
        got += w * d
    return rects


def _slab_streaks(rng, cx, cyy, hx, hy, hh, sg, pitch, base, ln_max, wmin, wmax, amin, p_gap=0.1):
    """Штрихи вдоль всех 4 кромок плиты, свисают вниз от её нижней грани (у потолка вверх). Шаг ≈ pitch, пропуски p_gap, длина плывёт плавной
    волной вдоль кромки (base·0,4…1,0, ещё ×0,5…1,0 шумом) и шумом, не длиннее ln_max (глубина не больше допустимой для модуля)."""
    out, ph = [], rng.uniform(0, 6.28)
    for side in range(4):
        horiz = side % 2 == 0  # кромки вдоль x: y = cy ± hy; вдоль y: x = cx ± hx
        length = 2 * hx if horiz else 2 * hy
        n = max(1, round(length / pitch))
        for q in range(n):
            if rng.random() < p_gap:
                continue
            t = (q + 0.5 + rng.uniform(-0.3, 0.3)) / n - 0.5
            if side == 0:
                ex, ey = cx + t * length, cyy - hy
            elif side == 1:
                ex, ey = cx + hx, cyy + t * length
            elif side == 2:
                ex, ey = cx + t * length, cyy + hy
            else:
                ex, ey = cx - hx, cyy + t * length
            wave = 0.5 + 0.5 * math.sin(q * 1.3 + side * 1.9 + ph)
            ln = min(base * (0.4 + 0.6 * wave) * rng.uniform(0.5, 1.0), ln_max)
            if ln < 0.05:
                continue
            out.append((Vector((ex, ey, sg * (hh - SLAB_T - ln / 2))), rng.uniform(wmin, wmax), ln / 2, rng.uniform(amin, 1.0)))
    return out


def _slab_dots(rng, size, step, covered, margin, sg, forced=()):
    """Точки пола: шаг постоянный, ~15% пропущено, высота слегка разная (не выше поверхности); под плитами (с запасом margin) точек нет."""
    steps = int(size / step + 1e-9)
    pts = []
    for i in range(steps):
        for j in range(steps):
            x, y = -size / 2 + step / 2 + i * step, -size / 2 + step / 2 + j * step
            if (x, y) in forced:
                pts.append(Vector((x, y, sg * -rng.uniform(0.016, 0.09))))
                continue
            if rng.random() < 0.15 or any(abs(x - cx) < hx + margin and abs(y - cyy) < hy + margin for cx, cyy, hx, hy in covered):
                continue
            pts.append(Vector((x, y, sg * -rng.uniform(0.016, 0.09))))
    return pts


# Виды плит: (вес, (мин, макс) по одной стороне, (мин, макс) по другой), метры.
ROOM_KINDS = [(0.14, (1.3, 1.68), (0.3, 0.5)), (0.26, (0.8, 1.2), (0.5, 0.8)), (0.34, (0.4, 0.65), (0.35, 0.6)), (0.26, (0.22, 0.4), (0.22, 0.4))]
FAR_KINDS = [(0.16, (3.0, 4.6), (2.0, 3.2)), (0.28, (1.6, 3.0), (1.0, 2.0)), (0.3, (0.7, 1.3), (0.5, 1.0)), (0.26, (0.3, 0.6), (0.3, 0.6))]


def build_floor(out, name="floor", seed=2, ceiling=False, cover=0.22):
    """Плитка пола (или потолка при ceiling=True) 2×2 м: ~22% площади занимают тонкие (3 см) чёрные непрозрачные плиты РАЗНОГО размера — от
    вытянутых 1,6×0,4 м и крупных ~1×0,7 до мелких 0,25–0,4 м (расстановка зависит от seed: три варианта на пол и три на потолок, чтобы узор
    не повторялся). Боковых стенок нет: свет — штрихи, свисающие от всех четырёх кромок (шаг ≈ 5 см, пропуски 10%, длина до 0,9 м плывёт волной).
    Верх плиты чёрный, контур верха светится слабее штрихов. Пол: верх плиты НЕ ВЫШЕ поверхности пола (0…−0,45 м), штрихи висят вниз,
    точки на полу чуть ниже поверхности. Потолок — то же, инвертированное: плита не ниже плоскости потолка (0…+0,45 м), штрихи растут вверх.
    Ничего не выступает в комнату, коллизий нет. cover = 0: чистая площадка без плит (под хранилище). Origin на поверхности в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    sg = -1.0 if ceiling else 1.0  # знак по высоте: пол смотрит вниз от поверхности, потолок вверх
    rects = _place_slabs(rng, ROOM_KINDS, cover * 4.0, 0.84, 0.12) if cover > 0 else []  # края плит ≤ 0,84: угловые точки (±0,875) вне плит, габарит симметричен
    tiles, streaks, infos, covered = [], [], [], []
    perim = sum(4 * (hx + hy) for _, _, hx, hy in rects)
    pitch = max(0.05, perim * 0.9 / 175)  # бюджет 200 штрихов на модуль: при длинном периметре шаг растёт
    for cx, cyy, hx, hy in rects:
        hh = 0.0 if rng.random() < 0.3 else -rng.uniform(0.05, 0.45)  # плита на разной высоте, но не в сторону комнаты
        tiles.append(_slab_bm(cx, cyy, hx, hy, hh, sg))
        infos.append((cx, cyy, hx, hy, sg * hh))
        covered.append((cx, cyy, hx, hy))
        # Вглубь штрих не уходит ниже −0,95 м от плоскости.
        streaks += _slab_streaks(rng, cx, cyy, hx, hy, hh, sg, pitch, rng.uniform(0.6, 0.95), 0.95 + hh - SLAB_T, 0.011, 0.017, 0.65)
    del streaks[200:]
    rim = tuple(c * 0.6 for c in cy)  # контур верха слабее штрихов
    objs = [lib.obj_from_bm("tiles", lib.merge_bm(*tiles), "solid_dark", cy, rgb_fn=_slab_rgb(infos, rim, lib.lin("void")))] if tiles else []
    # пол: якорь сверху (имя *_hang); потолок: штрихи растут вверх от кромок, якорь по умолчанию у основания
    objs.append(lib.streak_set(("ceiling_streaks" if ceiling else "floor_streaks_hang"), streaks, cy))
    corners = {(sx * 0.875, sy * 0.875) for sx in (-1, 1) for sy in (-1, 1)}
    dots = _slab_dots(rng, 2.0, 0.25, covered, 0.06, sg, forced=corners)
    objs.append(lib.point_cloud("dots", dots, cy, half_size=0.016, seed=2, a_min=0.4, a_max=0.9))
    area = sum(4 * hx * hy for _, _, hx, hy in rects)
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=170, budget_streaks=200, origin=("ceiling" if ceiling else "surface"),
                      notes=f"{len(rects)} плит толщиной {SLAB_T * 100:.0f} см, покрытие {area / 4.0 * 100:.0f}% плитки 2×2 м")


def build_far_surface(out, name="far_floor", seed=61, ceiling=False, size=11.0, cover=0.20):
    """Пол (или потолок при ceiling=True) дальнего плана: участок 11×11 м из тех же тонких плит, что в комнате (build_floor), но крупнее и глубже:
    размеры от 0,3 м до 3–4,6 м, покрытие ~20%. Плиты лежат на разной глубине — от плоскости пола до −2,6 м (потолок: до +2,6 м), как «ямы»;
    штрихи свисают от кромок вниз длинные (до 3 м, не глубже −3 м: предел validate для far_*). Точки пола реже (шаг 0,75 м, ~15% пропусков),
    над плитами их нет. Нужен, чтобы пол и потолок были везде, а не только в комнате; в игре берутся участки сеткой 11 м.
    Origin на поверхности (потолок: на плоскости потолка) в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    sg = -1.0 if ceiling else 1.0
    rects = _place_slabs(rng, FAR_KINDS, cover * size * size, size / 2 - 0.3, 0.5, max_n=26)
    tiles, streaks, infos, covered = [], [], [], []
    perim = sum(4 * (hx + hy) for _, _, hx, hy in rects)
    pitch = max(0.2, perim * 0.9 / 235)  # бюджет 260 штрихов на участок
    for cx, cyy, hx, hy in rects:
        hh = 0.0 if rng.random() < 0.2 else -rng.uniform(0.1, 2.6)
        tiles.append(_slab_bm(cx, cyy, hx, hy, hh, sg))
        infos.append((cx, cyy, hx, hy, sg * hh))
        covered.append((cx, cyy, hx, hy))
        ln_max = 2.98 + hh - SLAB_T  # низ штриха не глубже −2,98 м
        streaks += _slab_streaks(rng, cx, cyy, hx, hy, hh, sg, pitch, ln_max * rng.uniform(0.6, 1.0), ln_max, 0.012, 0.018, 0.65)
    del streaks[260:]
    rim = tuple(c * 0.6 for c in cy)
    objs = [lib.obj_from_bm("tiles", lib.merge_bm(*tiles), "solid_dark", cy, rgb_fn=_slab_rgb(infos, rim, lib.lin("void")))]
    objs.append(lib.streak_set(("far_ceiling_streaks" if ceiling else "far_floor_streaks_hang"), streaks, cy))
    dots = _slab_dots(rng, size, 0.75, covered, 0.15, sg)
    dots += [Vector((sx * (size / 2 - 0.1), sy * (size / 2 - 0.1), sg * -0.03)) for sx in (-1, 1) for sy in (-1, 1)]  # угловые точки: габарит симметричен, участки стыкуются
    objs.append(lib.point_cloud("far_surface_pts", dots, cy, half_size=0.02, seed=2, a_min=0.3, a_max=0.8))
    area = sum(4 * hx * hy for _, _, hx, hy in rects)
    return lib.export(name, "env", objs, out, budget_tris=1100, budget_points=700, budget_streaks=260, origin=("ceiling" if ceiling else "surface"),
                      notes=f"{len(rects)} плит, покрытие {area / (size * size) * 100:.1f}% участка {size:g}×{size:g} м, глубина до 2,6 м, штрихи до 3 м")


def build_column_field(out, name="column_field", seed=77):
    """Поле колонн 4×4 м для дальнего плана (эксперимент «объёмный дисплей»): решётка шагом 0,1 м, один штрих на узел, высота по карте
    крупных «холмов» × шум (как cyan space в референсе), ~15% узлов пропущено. Один примитив, 2 треугольника на колонну. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    pitch, n, st = 0.1, 40, []
    for i in range(n):
        for j in range(n):
            if rng.random() < 0.15:
                continue
            x, y = -2.0 + pitch * (i + 0.5), -2.0 + pitch * (j + 0.5)
            e = 0.5 + 0.5 * math.sin(x * 0.9 + 1.1) * math.sin(y * 1.3 + 0.4)
            hh = 3.0 * (0.12 + 0.88 * e * e) * rng.uniform(0.55, 1.0)
            st.append((Vector((x, y, hh / 2)), rng.uniform(0.012, 0.02), hh / 2, 0.15 + 0.85 * e * rng.uniform(0.4, 1.0)))
    return lib.export(name, "env", [lib.streak_set("columns", st, cy)], out, budget_tris=300, budget_streaks=1700, origin="floor",
                      notes="эксперимент: поле колонн на решётке 0,1 м для дальнего плана")


def build_pillar(out):
    """Колонна на углу: пучок высоких штрихов (два белых) и несколько точек у основания. Высота до 3 м. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(6)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    st = []
    for _ in range(9):
        hh = rng.uniform(1.0, 1.5)
        st.append((Vector((rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07), hh)), rng.uniform(0.01, 0.018), hh, rng.uniform(0.4, 0.9)))
    objs = [lib.streak_set("pillar_streaks", st, cy)]
    objs.append(lib.streak_set("pillar_core", [(Vector((0, 0, 1.5)), 0.012, 1.5, 1.0), (Vector((0.03, 0.02, 1.2)), 0.01, 1.2, 0.9)], ice))
    return lib.export("pillar", "env", objs, out, budget_tris=300, budget_streaks=16, origin="floor")


if __name__ == "__main__":
    o = lib.args()
    build_pillar(o)
    build_column_field(o)
    for name, seed in (("wall", 21), ("wall_b", 34), ("wall_c", 55)):
        build_wall(o, name, seed)
    build_portal_wall(o)
    for name, seed in (("far_floor", 61), ("far_floor_b", 62), ("far_floor_c", 63)):
        build_far_surface(o, name, seed)
    for name, seed in (("far_ceiling", 71), ("far_ceiling_b", 72), ("far_ceiling_c", 73)):
        build_far_surface(o, name, seed, ceiling=True)
    for name, seed in (("far_field", 41), ("far_field_b", 42), ("far_field_c", 43)):
        build_far_field(o, name, seed)
    for name, seed in (("doorway", 8), ("doorway_b", 17)):
        build_doorway(o, name, seed)
    for name, seed in (("floor", 2), ("floor_b", 5), ("floor_c", 9)):
        build_floor(o, name, seed)
    build_floor(o, "floor_clear", 14, cover=0)
    for name, seed in (("ceiling", 3), ("ceiling_b", 6), ("ceiling_c", 11)):
        build_floor(o, name, seed, ceiling=True)

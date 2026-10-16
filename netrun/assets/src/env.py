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


def _place_slabs_dense(rng, bound, cover, tol=0.03, max_n=12, tries=3000):
    """Плотная расстановка для пола комнаты (решение владельца 2026-10-05: покрытие ≈ 43%, было ~22%). Случайная досыпка плит упирается в ~30%
    (крупные блокируют место), поэтому квадрат ±bound рекурсивно делится на ячейки разного размера (деление по длинной стороне, доля 0,3…0,7,
    у каждой ячейки свой предел размера, вытянутые крупные плиты разрешены), часть ячеек (12%) пустая, внутри каждой ячейки плита с отступом
    3…9 см от каждой стороны: щели между соседями 6…18 см разной ширины, а не ровная сетка. Из tries раскладок берётся первая с покрытием
    cover±tol, 5…max_n плитами, с одной крупной (≥ 1,2 м) и одной мелкой (≤ 0,36 м) плитой — узор не «одного размера». Возвращает [(cx, cy, hx, hy)]."""
    best = None
    for _ in range(tries):
        cells = []

        def split(x0, x1, y0, y1, depth):
            w, d = x1 - x0, y1 - y0
            big = rng.random() < 0.3  # вытянутая крупная плита: длинная сторона до 1,68 м, короткая ≤ 0,58 м
            lim = rng.choice((1.0, 0.7, 0.5, 0.34))
            if (depth >= 1 and big and min(w, d) <= 0.58) or max(w, d) <= lim or depth >= 5:
                cells.append((x0, x1, y0, y1))
                return
            if w > d * 1.3 or (d <= w * 1.3 and rng.random() < 0.5):
                m = x0 + w * rng.uniform(0.3, 0.7)
                split(x0, m, y0, y1, depth + 1)
                split(m, x1, y0, y1, depth + 1)
            else:
                m = y0 + d * rng.uniform(0.3, 0.7)
                split(x0, x1, y0, m, depth + 1)
                split(x0, x1, m, y1, depth + 1)

        split(-bound, bound, -bound, bound, 0)
        rects = []
        for x0, x1, y0, y1 in cells:
            if rng.random() < 0.12:
                continue
            a, b, c, e = x0 + rng.uniform(0.03, 0.09), x1 - rng.uniform(0.03, 0.09), y0 + rng.uniform(0.03, 0.09), y1 - rng.uniform(0.03, 0.09)
            if b - a < 0.22 or e - c < 0.22:
                continue
            rects.append(((a + b) / 2, (c + e) / 2, (b - a) / 2, (e - c) / 2))
        if not 5 <= len(rects) <= max_n:
            continue
        cov = sum(4 * hx * hy for _, _, hx, hy in rects) / 4.0
        err = abs(cov - cover)
        if best is None or err < best[0]:
            best = (err, rects)
        sizes = [max(2 * hx, 2 * hy) for _, _, hx, hy in rects]
        if err <= tol and max(sizes) >= 1.2 and min(sizes) <= 0.36:
            return rects
    return best[1]


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


SKIRT_H_ROOM = 0.7  # высота вуали под кромкой плиты в комнате, м: порядка длины штрихов (0,1…0,9)
SKIRT_H_FAR = 1.2   # то же в дальних пластах, где штрихи до 3 м (было 1,8: вуаль дальних пластов давала 1,4 из 2,3 слоёв перерисовки, замер 07.10)
SKIRT_FAR_SIDES = 2  # граней плиты с вуалью в дальних пластах (из 4; было 4): наполовину меньше площади при почти том же виде издали
RISE_H_ROOM = 0.45  # высота завесы ВВЕРХ от верхней кромки плиты пола в комнате, м (очки П5: «вуаль у плит потолка выглядит здорово» — та же завеса вместо штрихов)
RISE_H_FAR = 1.0    # то же у плит дальнего пола
RISE_FAR_SIDES = 2  # граней плиты дальнего пола с завесой вверх (из 4): как у вуали дальних пластов, вдвое меньше площади


def _slab_skirt(rng, cx, cyy, hx, hy, hh, sg, h_max, sides=4):
    """Вуаль плиты: по одному вертикальному квадрату на каждую из 4 боковых граней, от нижней кромки плиты вниз (у потолка вверх) на высоту
    h_max·0,6…1,0 (у каждой грани своя), плотность у кромки 0,7…1,0, внизу 0. Пространство под плитой не заливается: только плоскости по её периметру."""
    z0 = sg * (hh - SLAB_T)
    quads = []
    faces = ((cx - hx, cyy - hy, cx + hx, cyy - hy), (cx + hx, cyy - hy, cx + hx, cyy + hy),
             (cx + hx, cyy + hy, cx - hx, cyy + hy), (cx - hx, cyy + hy, cx - hx, cyy - hy))
    keep = sorted(rng.sample(range(4), sides)) if sides < 4 else range(4)  # какие грани получают вуаль (случайно, но детерминированно по seed)
    for (ax, ay, bx, by) in (faces[i] for i in keep):
        h = h_max * rng.uniform(0.6, 1.0)
        quads.append((Vector((ax, ay, z0)), Vector((bx, by, z0)), Vector((0, 0, -sg * h)), rng.uniform(0.7, 1.0), rng.uniform(0.7, 1.0)))
    return quads


def _slab_rise(rng, cx, cyy, hx, hy, hh, hmax, sides=4):
    """Завеса плиты ПОЛА вверх, в комнату: по вертикальному квадрату на грань от ВЕРХНЕЙ (светящейся) кромки плиты вверх на hmax·0,6…1,0, плотность у кромки
    0,7…1,0, вверху 0. Формат квада — как у _slab_skirt, плюс шестое поле — высота (в UV1.x, см. lib.skirt_set): по нему шейдер отличает завесу вверх от вуали вниз
    и применяет ручки tile_glow / tile_glow_h. Только пол (знак +1): у потолка вуаль и так идёт вверх от плиты, её очки одобрили."""
    z0 = hh
    quads = []
    faces = ((cx - hx, cyy - hy, cx + hx, cyy - hy), (cx + hx, cyy - hy, cx + hx, cyy + hy),
             (cx + hx, cyy + hy, cx - hx, cyy + hy), (cx - hx, cyy + hy, cx - hx, cyy - hy))
    keep = sorted(rng.sample(range(4), sides)) if sides < 4 else range(4)
    for (ax, ay, bx, by) in (faces[i] for i in keep):
        h = hmax * rng.uniform(0.6, 1.0)
        quads.append((Vector((ax, ay, z0)), Vector((bx, by, z0)), Vector((0, 0, h)), rng.uniform(0.7, 1.0), rng.uniform(0.7, 1.0), h))
    return quads


# Виды плит: (вес, (мин, макс) по одной стороне, (мин, макс) по другой), метры.
ROOM_KINDS = [(0.14, (1.3, 1.68), (0.3, 0.5)), (0.26, (0.8, 1.2), (0.5, 0.8)), (0.34, (0.4, 0.65), (0.35, 0.6)), (0.26, (0.22, 0.4), (0.22, 0.4))]
FAR_KINDS = [(0.16, (3.0, 4.6), (2.0, 3.2)), (0.28, (1.6, 3.0), (1.0, 2.0)), (0.3, (0.7, 1.3), (0.5, 1.0)), (0.26, (0.3, 0.6), (0.3, 0.6))]


def build_floor(out, name="floor", seed=2, ceiling=False, cover=0.22, dense=False):
    """Плитка пола (или потолка при ceiling=True) 2×2 м: тонкие (3 см) чёрные непрозрачные плиты РАЗНОГО размера — от вытянутых 1,6×0,4 м и
    крупных ~1×0,7 до мелких 0,25–0,4 м (расстановка зависит от seed: три варианта на пол и три на потолок, чтобы узор не повторялся).
    Потолок — ~22% площади (случайная досыпка, _place_slabs); пол комнаты dense=True — ≈ 43% (решение владельца 2026-10-05, деление на
    ячейки, _place_slabs_dense), бюджет tris пола 450. Боковых стенок нет: свет — штрихи, свисающие от всех четырёх кромок (шаг ≈ 5 см, пропуски 10%, длина до 0,9 м плывёт волной).
    Верх плиты чёрный, контур верха светится слабее штрихов. Пол: верх плиты НЕ ВЫШЕ поверхности пола (0…−0,45 м), штрихи висят вниз,
    точки на полу чуть ниже поверхности. Потолок — то же, инвертированное: плита не ниже плоскости потолка (0…+0,45 м), штрихи растут вверх.
    Ничего не выступает в комнату, коллизий нет. cover = 0: чистая площадка без плит (под хранилище). Origin на поверхности в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    sg = -1.0 if ceiling else 1.0  # знак по высоте: пол смотрит вниз от поверхности, потолок вверх
    # края плит ≤ 0,84: угловые точки (±0,875) вне плит, габарит симметричен
    if cover <= 0:
        rects = []
    elif dense:
        rects = _place_slabs_dense(rng, 0.84, cover, tol=0.025)
    else:
        rects = _place_slabs(rng, ROOM_KINDS, cover * 4.0, 0.84, 0.12)
    tiles, streaks, infos, covered, skirts = [], [], [], [], []
    srng = random.Random(seed * 7 + 3)  # свой генератор: вуаль не сдвигает раскладку штрихов и точек
    rrng = random.Random(seed * 11 + 5)  # и завеса вверх (у пола) — свой, чтобы не двигать вуаль
    perim = sum(4 * (hx + hy) for _, _, hx, hy in rects)
    pitch = max(0.05, perim * 0.9 / 175)  # бюджет 200 штрихов на модуль: при длинном периметре шаг растёт
    for cx, cyy, hx, hy in rects:
        hh = 0.0 if rng.random() < 0.3 else -rng.uniform(0.05, 0.45)  # плита на разной высоте, но не в сторону комнаты
        tiles.append(_slab_bm(cx, cyy, hx, hy, hh, sg))
        infos.append((cx, cyy, hx, hy, sg * hh))
        covered.append((cx, cyy, hx, hy))
        # Вглубь штрих не уходит ниже −0,95 м от плоскости.
        streaks += _slab_streaks(rng, cx, cyy, hx, hy, hh, sg, pitch, rng.uniform(0.6, 0.95), 0.95 + hh - SLAB_T, 0.011, 0.017, 0.65)
        skirts += _slab_skirt(srng, cx, cyy, hx, hy, hh, sg, min(SKIRT_H_ROOM, 0.95 + hh - SLAB_T))
        if not ceiling:  # пол: завеса вверх от верхней кромки (в тот же меш *_skirt: отдельный меш дал бы четвёртый слой прозрачности, предел 3)
            skirts += _slab_rise(rrng, cx, cyy, hx, hy, hh, RISE_H_ROOM)
    # B2 (12.10.2026): штрихи и точки окружения не рисуются (streak_keep=0 и point_keep=0 приняты на очках) и из модели убраны. Цикл выше всё равно считает штрихи:
    # они потребляют датчик rng, от которого зависит раскладка плит, — раскладка (то, что видели на очках) остаётся прежней.
    rim = tuple(c * 0.6 for c in cy)  # контур верха слабее штрихов
    objs = [lib.obj_from_bm("tiles", lib.merge_bm(*tiles), "solid_dark", cy, rgb_fn=_slab_rgb(infos, rim, lib.lin("void")))] if tiles else []
    if skirts:  # вуаль на гранях плит (имя *_skirt: в Godot шейдер skirt.gdshader); у чистой площадки без плит её нет
        objs.append(lib.skirt_set("ceiling_skirt" if ceiling else "floor_skirt", skirts, cy))
    area = sum(4 * hx * hy for _, _, hx, hy in rects)
    return lib.export(name, "env", objs, out, budget_tris=(450 if dense else 300), budget_points=0, budget_streaks=0, origin=("ceiling" if ceiling else "surface"),
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
    tiles, streaks, infos, covered, skirts = [], [], [], [], []
    srng = random.Random(seed * 7 + 3)
    rrng = random.Random(seed * 11 + 5)
    perim = sum(4 * (hx + hy) for _, _, hx, hy in rects)
    pitch = max(0.2, perim * 0.9 / 235)  # бюджет 260 штрихов на участок
    for cx, cyy, hx, hy in rects:
        hh = 0.0 if rng.random() < 0.2 else -rng.uniform(0.1, 2.6)
        tiles.append(_slab_bm(cx, cyy, hx, hy, hh, sg))
        infos.append((cx, cyy, hx, hy, sg * hh))
        covered.append((cx, cyy, hx, hy))
        ln_max = 2.98 + hh - SLAB_T  # низ штриха не глубже −2,98 м
        streaks += _slab_streaks(rng, cx, cyy, hx, hy, hh, sg, pitch, ln_max * rng.uniform(0.6, 1.0), ln_max, 0.012, 0.018, 0.65)
        skirts += _slab_skirt(srng, cx, cyy, hx, hy, hh, sg, min(SKIRT_H_FAR, ln_max), SKIRT_FAR_SIDES)
        if not ceiling:  # дальний пол: завеса вверх от верхней кромки (две грани из четырёх)
            skirts += _slab_rise(rrng, cx, cyy, hx, hy, hh, RISE_H_FAR, RISE_FAR_SIDES)
    # B2 (12.10.2026): штрихи и точки окружения убраны (не рисуются, см. build_floor); цикл выше считает штрихи ради датчика rng — раскладка плит прежняя.
    rim = tuple(c * 0.6 for c in cy)
    objs = [lib.obj_from_bm("tiles", lib.merge_bm(*tiles), "solid_dark", cy, rgb_fn=_slab_rgb(infos, rim, lib.lin("void")))]
    objs.append(lib.skirt_set("far_ceiling_skirt" if ceiling else "far_floor_skirt", skirts, cy))
    area = sum(4 * hx * hy for _, _, hx, hy in rects)
    return lib.export(name, "env", objs, out, budget_tris=1100, budget_points=0, budget_streaks=0, origin=("ceiling" if ceiling else "surface"),
                      notes=f"{len(rects)} плит, покрытие {area / (size * size) * 100:.1f}% участка {size:g}×{size:g} м, глубина до 2,6 м")


COVER_H = 2.2      # высота укрытия, м: выше головы стоящего игрока; одна на все (полуукрытий нет, решение Game: занятая клетка закрывает взгляд целиком)
COVER_CELL = 1.0   # клетка хода, м (NodeGrid.CELL_M)
COVER_BODY = 0.9   # корпус по центру клетки, щель 5 см до границы


def _cover_parts(centers, body_size=COVER_BODY, cell=COVER_CELL):
    """Столбы-укрытия на клетках с центрами `centers` (x, y): корпус body_size×body_size×2,2 м (по умолчанию 0,9 м, клетка 1×1) и плоская рамка по границе клетки
    cell×cell на полу. Корпус нарезан плоскостями у рёбер (3 см), у верха и на 0,3 м от пола: свет вершин остаётся только у вертикальных рёбер, верхнего контура
    и в основании. Колонна 2×2 м — один «столб» с body_size 1,9 и cell 2 (15.10: четыре укрытия с зазорами владелец принял за четыре колонны).
    Возвращает (корпус bmesh, рамки bmesh, rgb_fn корпуса)."""
    cy, void = lib.lin("cyan"), lib.lin("void")
    half, band, rise = body_size / 2, 0.03, 0.3
    bodies, frames = [], []
    for cx, cy_ in centers:
        bm = lib.box_bm((body_size, body_size, COVER_H), center=(cx, cy_, COVER_H / 2))
        for co, no in (((cx - half + band, 0, 0), (1, 0, 0)), ((cx + half - band, 0, 0), (1, 0, 0)),
                       ((0, cy_ - half + band, 0), (0, 1, 0)), ((0, cy_ + half - band, 0), (0, 1, 0)),
                       ((0, 0, rise), (0, 0, 1)), ((0, 0, COVER_H - band), (0, 0, 1))):
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=co, plane_no=no)
        bodies.append(bm)
        fb = bmesh.new()  # рамка шириной 3 см, внешний край — граница клетки; на 3 мм выше пола, чтобы не мерцать с плитой
        o, i = cell / 2, cell / 2 - 0.03
        ring = [[fb.verts.new(Vector((cx + sx * r, cy_ + sy * r, 0.003))) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))] for r in (o, i)]
        for k in range(4):
            fb.faces.new([ring[0][k], ring[0][(k + 1) % 4], ring[1][(k + 1) % 4], ring[1][k]])
        bmesh.ops.recalc_face_normals(fb, faces=list(fb.faces))
        frames.append(fb)
    body = lib.merge_bm(*bodies)
    lib.canon_faces(body)
    frame = lib.merge_bm(*frames)
    lib.canon_faces(frame)

    def lit(co):
        # расстояние до центра ближайшего столба по каждой оси
        lx, ly = min(((abs(co.x - cx), abs(co.y - cy_)) for cx, cy_ in centers), key=max)
        ring_ = max(lx, ly) > half - 1e-3
        if lx > half - 1e-3 and ly > half - 1e-3:
            k = 1.0                                   # вертикальное ребро
        elif ring_ and co.z > COVER_H - 1e-3:
            k = 1.0                                   # контур верха
        elif ring_ and co.z < rise:
            k = 0.6 * (1.0 - co.z / rise)             # мягкая подсветка основания
        else:
            k = 0.0
        return tuple(d + (g - d) * k for g, d in zip(cy, void))

    return body, frame, lit


def _cover_asset(out, name, centers, tris, notes, body_size=COVER_BODY, cell=COVER_CELL):
    lib.reset()
    cy = lib.lin("cyan")
    body, frame, lit = _cover_parts(centers, body_size, cell)
    objs = [lib.obj_from_bm("pillar_block", body, "solid_dark", cy, rgb_fn=lit, smooth=True),  # smooth: нормали для обводки силуэта (fringe.gdshader)
            lib.obj_from_bm("pillar_base", frame, "solid_dark", cy)]
    return lib.export(name, "env", objs, out, budget_tris=tris, origin="floor", notes=notes)


def build_cover(out):
    """Укрытие на одной клетке хода 1×1 м (Godot ставит по одному на занятую клетку): непрозрачный корпус 0,9×0,9×2,2 м по центру клетки, светятся
    вертикальные рёбра, контур верха и основание, плюс ровная рамка по границе клетки (тот же шаг, что швы пола): соседние укрытия складываются в стену,
    но клетки читаются. Origin на полу в центре клетки."""
    return _cover_asset(out, "cover", [(0.0, 0.0)], 140,
                        f"одна клетка {COVER_CELL:g} м, корпус {COVER_BODY:g}, высота {COVER_H:g} м, рамка по границе клетки")


def build_pillar(out):
    """Колонна модуля 2×2 м (блок «#» раскладки) = ОДИН корпус 1,9×1,9×2,2 м по центру модуля (15.10, карточка Godot П6-0г: из четырёх укрытий 0,9 м с зазорами
    владелец на П6 видел четыре колонны вместо одной). Рёбра, контур верха, подсветка основания и облако — как у `pillar_block` укрытия; рамка по границе модуля 2×2.
    Занятость клеток не меняется (её задаёт раскладка, не модель), одиночный `cover` 1×1 остаётся. Контракт (имя, путь, origin в центре модуля) сохранён."""
    return _cover_asset(out, "pillar", [(0.0, 0.0)], 140,
                        f"модуль 2×2 м = один корпус 1,9×1,9 м, высота {COVER_H:g} м, рамка по границе модуля",
                        body_size=1.9, cell=2.0)


if __name__ == "__main__":
    o = lib.args()
    build_pillar(o)
    build_cover(o)
    for name, seed in (("far_floor", 61), ("far_floor_b", 62), ("far_floor_c", 63)):
        build_far_surface(o, name, seed)
    for name, seed in (("far_ceiling", 71), ("far_ceiling_b", 72), ("far_ceiling_c", 73)):
        build_far_surface(o, name, seed, ceiling=True)
    for name, seed in (("floor", 2), ("floor_b", 5), ("floor_c", 9)):
        build_floor(o, name, seed, cover=0.425, dense=True)
    for name, seed in (("ceiling", 3), ("ceiling_b", 6), ("ceiling_c", 11)):
        build_floor(o, name, seed, ceiling=True)

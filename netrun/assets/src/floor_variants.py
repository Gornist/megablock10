"""ЭКСПЕРИМЕНТ: четыре варианта пола комнаты «разными способами», ассеты env/floor_v<N>_<размер> (N = 1…4, размер 8 или 16). Один код, два размера: `_8` — комната
просмотра 8×8 (край ±4), `_16` — настоящая комната 16×16 (NodeLayout.ROOM_MIN..ROOM_MAX, клиент ставит в ROOM_CENTER). Край квадрата = край room_edge_<размер>.
Запуск: blender -b --python floor_variants.py -- --out <корень netrun/assets>

Заказ владельца 2026-10-05: «несколько вариантов пола разными способами, чтобы пол читался, но не выбивался из визуального языка» (референсы: пол читается плотностью
света, чёрные блоки на разной высоте с яркими рёбрами, параллельные ряды дают перспективу, мягкость, к горизонту светлее). Предыдущие попытки: плитки floor*, плотные
плитки, одна плита floor_slab_*, стеклянная плита floor_glass_*. Здесь четыре иных механизма (в просмотре флаг `--floorv=<N>` заменяет пол комнаты выбранным вариантом):
  1. «Пыль» — поверхность из россыпи тонких коротких вертикальных штрихов (0,08–0,3 м над полом, как «дождь» референса 4) + очень слабая стеклянная дымка (glass.gdshader, альфа 0,06).
  2. «Террасы» — несколько крупных (3–7 м) тонких чёрных плит на трёх уровнях (0, −0,15, −0,3 м), щели 5–15 см, яркий контур верха, на ступенях вниз светится вуаль и свисают штрихи.
  3. «Решётка» — почти прозрачная стеклянная плита (альфа 0,10–0,15) с разметкой в шейдере: цепочки точек шагом 0,5 м, яркость убывает от центра, ~10% клеток подсвечены пятном.
  4. «Полосы-блоки» — параллельные ряды вытянутых узких плит (0,3 × 1,2–2,4 м) на слегка разной высоте (0…−0,2 м), щели 3–8 см, покрытие ≈ 60%, боковые штрихи.
Плиты v2 и v4 — меши `*_plates`: у плиты один квад верха (UV0 = локальные метры, UV1 = полуразмеры; кайму рисует solid_dark.gdshader по uv_rim), у v2 ещё 4 боковые грани по 3 см,
у v4 боковых граней нет (3 см невидимы, а 4 грани × 280 плит не лезут в бюджет). Верх плит не выше пола, коллизий нет. Цвета вершин — только cyan и ice_white, красного нет."""
import bmesh
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
import env  # noqa: E402
import floor_slab  # noqa: E402  (вуаль и квад стеклянного верха — те же функции, что у стеклянной плиты)

T = env.SLAB_T              # толщина плиты, м
TOP0 = -0.01                # верх плиты на уровне пола: 1 см ниже нуля, как у floor_slab
# Бюджет _16 (карточка; _8 — ×0,25 по площади). Те же числа — в validate.py (FLOOR_V_LIMITS).
BUDGET = {"tris": 600, "points": 900, "streaks": 600, "streaks_v1": 900}
DUST_PITCH_JITTER = 0.4     # разброс штрихов «пыли» внутри клетки, доли шага
VAULT_R = 1.4               # плиты в радиусе до хранилища (центр комнаты) — на уровне пола, чтобы оно не повисало над ямой
LEVELS_V2 = (TOP0, -0.15, -0.30)


# ---------------------------------------------------------------- общее

def _smooth(x, y, ph):
    """Плавный шум 0…1 из трёх синусов (без внешних библиотек, детерминированно)."""
    return 0.5 + 0.5 * (0.5 * math.sin(x * 0.9 + ph) + 0.3 * math.sin(y * 1.1 - x * 0.4 + 2.0 * ph) + 0.2 * math.sin((x + y) * 2.3 + 3.0 * ph))


def _quad(bm, uv0, uv1, pts, uvs, hs, outward=None):
    """Грань из четырёх точек. UV0 = uvs (локальные метры), UV1 = hs (полуразмеры). Экспортёр glTF переворачивает V, поэтому в Blender пишем (u, 1−v):
    в шейдер приходит (u, v). outward — ожидаемая внешняя нормаль (развернём грань, если нормаль смотрит внутрь)."""
    f = bm.faces.new([bm.verts.new(Vector(p)) for p in pts])
    if outward is not None:
        f.normal_update()
        if f.normal.dot(Vector(outward)) < 0:
            f.normal_flip()
    for loop, uv, h in zip(f.loops, uvs, hs):
        loop[uv0].uv = (uv[0], 1.0 - uv[1])
        loop[uv1].uv = (h[0], 1.0 - h[1])
    return f


def _plates_obj(name, plates, rgb, sides):
    """Плиты [(cx, cy, hx, hy, top)] одним мешем solid_dark: верх — один квад (2 треугольника) с UV для каймы; sides=True — ещё 4 боковые грани 3 см (UV1 огромны: каймы нет)."""
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UV0")
    uv1 = bm.loops.layers.uv.new("UV1")
    for cx, cy, hx, hy, top in plates:
        loc = ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy))
        _quad(bm, uv0, uv1, [(cx + a, cy + b, top) for a, b in loc], loc, [(hx, hy)] * 4)
        if sides:
            for (ax, ay), (bx, by), n in (((-hx, -hy), (hx, -hy), (0, -1, 0)), ((hx, -hy), (hx, hy), (1, 0, 0)), ((hx, hy), (-hx, hy), (0, 1, 0)), ((-hx, hy), (-hx, -hy), (-1, 0, 0))):
                pts = [(cx + ax, cy + ay, top), (cx + bx, cy + by, top), (cx + bx, cy + by, top - T), (cx + ax, cy + ay, top - T)]
                _quad(bm, uv0, uv1, pts, [(0, 0)] * 4, [(100.0, 100.0)] * 4, outward=n)
    return lib.obj_from_bm(name, bm, "solid_dark", rgb)


def _sides(p):
    """Четыре стороны плиты: (индекс, A, B, внешняя нормаль) по часовой/против, A→B вдоль кромки; Vector в плоскости пола."""
    cx, cy, hx, hy, _top = p
    return [(0, (cx - hx, cy - hy), (cx + hx, cy - hy), (0, -1)), (1, (cx + hx, cy - hy), (cx + hx, cy + hy), (1, 0)),
            (2, (cx + hx, cy + hy), (cx - hx, cy + hy), (0, 1)), (3, (cx - hx, cy + hy), (cx - hx, cy - hy), (-1, 0))]


def _is_boundary(a, b, half):
    """Сторона лежит на границе комнаты (±half): её кромку и так даёт room_edge, штрихи и вуаль здесь не нужны."""
    return (abs(a[0]) > half - 1e-3 and abs(b[0]) > half - 1e-3 and abs(a[0] - b[0]) < 1e-6) or (abs(a[1]) > half - 1e-3 and abs(b[1]) > half - 1e-3 and abs(a[1] - b[1]) < 1e-6)


def _plate_at(plates, x, y, skip=None):
    for p in plates:
        if p is not skip and abs(x - p[0]) <= p[2] + 1e-6 and abs(y - p[1]) <= p[3] + 1e-6:
            return p
    return None


def _hang_streaks(rng, plates, half, pitch, base, wmin, wmax, p_gap, ln_cap, long_only=False, p_side=1.0):
    """Подвесные штрихи вдоль кромок плит (кроме границы комнаты): шаг ≈ pitch, пропуски p_gap, длина плывёт волной; висят вниз от нижней грани. long_only —
    только вдоль длинных сторон; p_side — доля сторон со штрихами."""
    out, ph = [], rng.uniform(0, 6.28)
    for pl in plates:
        top = pl[4]
        sd = _sides(pl)
        long_x = pl[2] >= pl[3]
        for s, a, b, _n in sd:
            if _is_boundary(a, b, half) or rng.random() > p_side:
                continue
            if long_only and ((s % 2 == 0) != long_x):
                continue
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(1, round(length / pitch))
            for q in range(n):
                if rng.random() < p_gap:
                    continue
                t = (q + 0.5 + rng.uniform(-0.3, 0.3)) / n
                ex, ey = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                wave = 0.5 + 0.5 * math.sin(q * 1.3 + s * 1.9 + ph + pl[0])
                ln = min(base * (0.4 + 0.6 * wave) * rng.uniform(0.5, 1.0), ln_cap + top - T)
                if ln < 0.05:
                    continue
                out.append((Vector((ex, ey, top - T - ln / 2)), rng.uniform(wmin, wmax), ln / 2, rng.uniform(0.65, 1.0)))
    return out


def _cap(rng, items, limit):
    """Не больше limit элементов: лишние выбрасываются случайно (детерминированно по rng), порядок сохраняется."""
    if len(items) <= limit:
        return items
    keep = set(rng.sample(range(len(items)), limit))
    return [x for i, x in enumerate(items) if i in keep]


def _export(name, size, objs, tris, points, streaks, notes):
    k = (size / 16.0) ** 2  # бюджет _8 пропорционален площади
    return lib.export(name, "env", objs, OUT, budget_tris=int(tris * k), budget_points=int(points * k), origin="floorv", budget_streaks=int(streaks * k), notes=notes)


OUT = ""


# ---------------------------------------------------------------- 1. «Пыль»

def build_v1(size, seed):
    half = size / 2.0
    lib.reset()
    rng = random.Random(seed)
    cy, white = lib.lin("cyan"), lib.lin("ice_white")
    limit = int(BUDGET["streaks_v1"] * (size / 16.0) ** 2)
    pitch = 2 * (half - 0.2) * math.sqrt(0.74 / limit)  # средняя доля пропусков ≈ 26%: клеток чуть больше лимита, лишнее срежет _cap
    ph = rng.uniform(0, 6.28)
    n = int(2 * (half - 0.2) / pitch)
    streaks = []
    for i in range(n + 1):
        for j in range(n + 1):
            x = -(half - 0.2) + (i + rng.uniform(-DUST_PITCH_JITTER, DUST_PITCH_JITTER)) * pitch
            y = -(half - 0.2) + (j + rng.uniform(-DUST_PITCH_JITTER, DUST_PITCH_JITTER)) * pitch
            if abs(x) > half - 0.15 or abs(y) > half - 0.15:
                continue
            dens = _smooth(x, y, ph)
            if rng.random() < 0.10 + 0.34 * dens:  # пропуски: где-то густо, где-то реже, поле «дышит» плавными пятнами
                continue
            ln = min(rng.uniform(0.09, 0.30) * (0.75 + 0.5 * (1.0 - dens)), 0.30)
            z0 = rng.uniform(0.0, 0.05)
            col = white if rng.random() < 0.10 else cy  # редкий белый штрих-искра, как в референсе 4
            streaks.append((Vector((x, y, z0 + ln / 2)), rng.uniform(0.009, 0.014), ln / 2, rng.uniform(0.45, 1.0), col))
    streaks = _cap(rng, streaks, limit)
    objs = [floor_slab._glass_top(half, tuple(c * floor_slab.GLASS_DIM for c in cy)), lib.streak_set("dust_streaks", streaks, cy)]
    return _export(f"floor_v1_{size}", size, objs, BUDGET["tris"], 0, BUDGET["streaks_v1"],
                   f"ЭКСПЕРИМЕНТ v1 «пыль» {size}×{size} м: {len(streaks)} штрихов 0,08–0,3 м над полом на слабой стеклянной дымке (альфа 0,06 задаёт AssetMaterials)")


# ---------------------------------------------------------------- 2. «Террасы»

def _terrace_cells(rng, half):
    """Разбиение квадрата ±half на крупные ячейки 2,6…7 м (деление по длинной стороне, доля 0,35…0,65; ячейка < 2,2 м не получается)."""
    cells = []

    def split(x0, x1, y0, y1, depth):
        w, d = x1 - x0, y1 - y0
        lim = rng.uniform(3.4, 7.0)
        if max(w, d) <= lim or max(w, d) < 4.4 or depth >= 4:
            cells.append((x0, x1, y0, y1))
            return
        if w >= d:
            m = x0 + w * rng.uniform(max(0.35, 2.2 / w), min(0.65, 1 - 2.2 / w))
            split(x0, m, y0, y1, depth + 1)
            split(m, x1, y0, y1, depth + 1)
        else:
            m = y0 + d * rng.uniform(max(0.35, 2.2 / d), min(0.65, 1 - 2.2 / d))
            split(x0, x1, y0, m, depth + 1)
            split(x0, x1, m, y1, depth + 1)

    split(-half, half, -half, half, 0)
    return cells


def _terrace_plates(rng, half):
    """Плиты террас: ячейки со щелями 5…15 см (каждая внутренняя сторона отступает на 2,5…7,5 см, границы комнаты — вплотную). Уровни 0/−0,15/−0,3 м по случайной
    раскладке (все три присутствуют, центральная плита — на уровне пола под хранилищем)."""
    for _ in range(200):
        cells = _terrace_cells(rng, half)
        if len(cells) >= 4:
            break
    plates = []
    for x0, x1, y0, y1 in cells:
        sh = lambda edge: 0.0 if abs(abs(edge) - half) < 1e-6 else rng.uniform(0.025, 0.075)
        a, b, c, d = x0 + sh(x0), x1 - sh(x1), y0 + sh(y0), y1 - sh(y1)
        plates.append([(a + b) / 2, (c + d) / 2, (b - a) / 2, (d - c) / 2, LEVELS_V2[rng.randrange(3)]])
    for p in plates:
        if abs(p[0]) - p[2] < VAULT_R and abs(p[1]) - p[3] < VAULT_R:
            p[4] = LEVELS_V2[0]
    used = {p[4] for p in plates}
    for lv in LEVELS_V2[1:]:  # все три уровня должны встретиться: иначе ступенек не видно
        if lv not in used:
            cand = [p for p in plates if not (abs(p[0]) - p[2] < VAULT_R and abs(p[1]) - p[3] < VAULT_R)]
            if cand:
                rng.choice(cand)[4] = lv
    return [tuple(p) for p in plates]


def _step_skirts(rng, plates, half):
    """Вуаль на гранях плит (кроме границы): отрезки ≤ 2 м; где сосед ниже (ступень вниз) — яркая «боковая стенка» высотой в перепад + 0,35 м, иначе слабая 0,4 м."""
    quads = []
    for pl in plates:
        top = pl[4]
        for _s, a, b, nrm in _sides(pl):
            if _is_boundary(a, b, half):
                continue
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(1, math.ceil(length / floor_slab.SKIRT_SEG))
            for q in range(n):
                t0, t1 = q / n, (q + 1) / n
                mx = a[0] + (b[0] - a[0]) * (t0 + t1) / 2 + nrm[0] * 0.2
                my = a[1] + (b[1] - a[1]) * (t0 + t1) / 2 + nrm[1] * 0.2
                nb = _plate_at(plates, mx, my, pl)
                drop = (top - nb[4]) if nb is not None else 0.0
                step = drop > 0.01
                h = (drop + 0.35) if step else 0.4
                da = 1.0 if step else rng.uniform(0.35, 0.6)
                z0 = top - T
                pa = Vector((a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0, z0))
                pb = Vector((a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1, z0))
                quads.append((pa, pb, Vector((0, 0, -h)), da, da))
    return quads


def build_v2(size, seed):
    half = size / 2.0
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    plates = _terrace_plates(rng, half)
    perim = sum(4 * (p[2] + p[3]) for p in plates)
    limit = int(BUDGET["streaks"] * (size / 16.0) ** 2)
    pitch = max(0.25, perim * 0.88 / (limit * 0.85))
    streaks = _cap(rng, _hang_streaks(rng, plates, half, pitch, 0.9, 0.011, 0.017, 0.12, 0.95), limit)
    skirts = _step_skirts(rng, plates, half)
    objs = [_plates_obj("terraces_plates", plates, tuple(c * 0.9 for c in cy), True), lib.streak_set("terraces_streaks_hang", streaks, cy)]
    if skirts:
        objs.append(lib.skirt_set("terraces_skirt", skirts, cy))
    return _export(f"floor_v2_{size}", size, objs, BUDGET["tris"], 0, BUDGET["streaks"],
                   f"ЭКСПЕРИМЕНТ v2 «террасы» {size}×{size} м: {len(plates)} плит 3 см на уровнях {LEVELS_V2}, щели 5–15 см, вуаль на ступенях")


# ---------------------------------------------------------------- 3. «Решётка»

def build_v3(size, seed):
    half = size / 2.0
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    top = floor_slab._glass_top(half, tuple(c * floor_slab.GLASS_DIM for c in cy))
    streaks = env._slab_streaks(rng, 0.0, 0.0, half, half, floor_slab.TOP, 1.0, 0.3, 0.7, 0.7, 0.011, 0.017, 0.6, p_gap=0.15)
    objs = [top, lib.streak_set("grid_streaks_hang", streaks, cy), lib.skirt_set("grid_skirt", floor_slab._skirts(rng, half), cy)]
    return _export(f"floor_v3_{size}", size, objs, BUDGET["tris"], 0, BUDGET["streaks"],
                   f"ЭКСПЕРИМЕНТ v3 «решётка» {size}×{size} м: стеклянный квад, сетка 0,5 м и подсвеченные клетки — в шейдере (glass.gdshader, grid_*), по периметру штрихи и вуаль")


# ---------------------------------------------------------------- 4. «Полосы-блоки»

def build_v4(size, seed):
    half = size / 2.0
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    ph1, ph2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    plates = []
    y = -half
    row = 0
    while y < half - 0.15:
        w = min(rng.uniform(0.28, 0.34), half - y)
        x = -half
        gap_x = rng.uniform(0.03, 0.08)
        while x < half - 0.3:
            ln = min(rng.uniform(1.2, 2.4), half - x)
            if half - (x + ln) < 0.6:  # остаток короче 0,6 м — тянем последнюю плиту до границы, чтобы край совпал с room_edge
                ln = half - x
            skip = rng.random() < 0.23
            if not skip:
                cx, cyy = x + ln / 2, y + w / 2
                n = _smooth(cx * 0.5, row * 0.7, ph1) * 0.7 + 0.3 * _smooth(cx * 1.3, row * 0.2, ph2)
                top = TOP0 - 0.19 * n
                if math.hypot(max(0.0, abs(cx) - ln / 2), max(0.0, abs(cyy) - w / 2)) < VAULT_R:
                    top = TOP0
                plates.append((cx, cyy, ln / 2, w / 2, top))
            x += ln + gap_x * rng.uniform(0.7, 1.3)
        y += w + rng.uniform(0.03, 0.08)
        row += 1
    limit_t = int(BUDGET["tris"] * (size / 16.0) ** 2)
    plates = _cap(rng, plates, limit_t // 2)
    limit_s = int(BUDGET["streaks"] * (size / 16.0) ** 2)
    streaks = _cap(rng, _hang_streaks(rng, plates, half, 0.55, 0.45, 0.011, 0.016, 0.2, 0.5, long_only=True, p_side=0.5), limit_s)
    objs = [_plates_obj("stripes_plates", plates, tuple(c * 0.9 for c in cy), False), lib.streak_set("stripes_streaks_hang", streaks, cy)]
    area = sum(4 * p[2] * p[3] for p in plates) / (size * size)
    return _export(f"floor_v4_{size}", size, objs, BUDGET["tris"], 0, BUDGET["streaks"],
                   f"ЭКСПЕРИМЕНТ v4 «полосы-блоки» {size}×{size} м: {len(plates)} плит 0,3×1,2–2,4 м, покрытие {area * 100:.0f}%, ряды вдоль x, верх 0…−0,2 м")


BUILDERS = {1: build_v1, 2: build_v2, 3: build_v3, 4: build_v4}
SEEDS = {8: 311, 16: 312}

if __name__ == "__main__":
    OUT = lib.args()
    for v, builder in BUILDERS.items():
        for sz in (8, 16):
            builder(sz, seed=SEEDS[sz] + 10 * v)

"""ЭКСПЕРИМЕНТ: пол комнаты ОДНОЙ плитой, ассеты env/floor_slab_<N>. Один код, два размера: `floor_slab_8` (комната просмотра 8×8, край ±4) и
`floor_slab_16` (настоящая комната 16×16 = NodeLayout.ROOM_MIN..ROOM_MAX; клиент ставит в ROOM_CENTER (0, 0, −6)).
Запуск: blender -b --python floor_slab.py -- --out <корень netrun/assets>

Решение владельца 2026-10-05: «давай попробуем сделать пол одним тайлом». Старые модули floor/floor_b/floor_c остаются, это отдельный вариант для сравнения
кадров (в просмотре флаг `--floor1`). Те же правила, что у плит пола (env.py): плита тонкая (3 см), верх чёрный (solid_dark) на уровне пола (−1 см), контур верха
светится слабее штрихов (цвет вершин ×0,6), по всему периметру свисают вниз штрихи (шаг ≈ 25 см, ~12% пропусков, длина плывёт волной), по четырём граням
вуаль `*_skirt` (кромка делится на отрезки по 2 м). Чтобы пол не был плоской чёрной пустотой и читался масштаб, на верху — редкая сетка швов: цепочки слабых точек
(шаг швов 2 м, как стыки бывших модулей 2×2 м, точки каждые ≈ 32 см, ~10% пропущено, низкая яркость). Под плитой пустота и дальние пласты.
Край плиты ровно на линии края room_edge_<N> (сторона = N, край ±N/2): тот же параметр half, что в edge.py. Origin «slab» — центр плиты, верх на полу."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
import env  # noqa: E402  (плиты и штрихи кромки — те же функции, что у плиток пола)

TOP = -0.01          # верх плиты, м: на уровне пола, ничего не выступает
STREAK_PITCH = 0.25  # шаг подвесных штрихов, м: 16×16 → ≤ 260, 8×8 → ≤ 130
STREAK_GAP = 0.12    # доля пропусков
HANG_MAX = 0.9       # длина подвесных штрихов, м (с «горением» до ×1,3 → не глубже ≈ 1,2 м)
SEAM_STEP = 2.0      # шаг швов, м
SEAM_DOT_STEP = 0.32  # шаг точек вдоль шва, м
SKIRT_SEG = 2.0      # длина отрезка вуали вдоль кромки, м


def _skirts(rng, half):
    """Вуаль на 4 гранях: отрезки по SKIRT_SEG, у каждого своя высота 0,5…0,75 м и плотность (плавно «гуляют»)."""
    z0 = TOP - env.SLAB_T
    quads = []
    n = max(1, round(2 * half / SKIRT_SEG))
    ph = rng.uniform(0, 6.28)
    corners = [(-half, -half), (half, -half), (half, half), (-half, half)]
    for side in range(4):
        ax, ay = corners[side]
        bx, by = corners[(side + 1) % 4]
        for q in range(n):
            t0, t1 = q / n, (q + 1) / n
            a = Vector((ax + (bx - ax) * t0, ay + (by - ay) * t0, z0))
            b = Vector((ax + (bx - ax) * t1, ay + (by - ay) * t1, z0))
            h = 0.5 + 0.25 * (0.5 + 0.5 * math.sin(q * 1.1 + side * 2.3 + ph))
            da = 0.7 + 0.3 * (0.5 + 0.5 * math.sin(q * 0.8 + side + ph))
            db = 0.7 + 0.3 * (0.5 + 0.5 * math.sin((q + 1) * 0.8 + side + ph))
            quads.append((a, b, Vector((0, 0, -h)), da, db))
    return quads


def _seam_dots(rng, half):
    """Сетка швов: линии x = k·SEAM_STEP и y = k·SEAM_STEP внутри плиты (кроме самой кромки), цепочки точек с шагом SEAM_DOT_STEP, ~10% пропущено,
    яркость задаёт point_cloud (a_min…a_max, мала). Пересечения швов — одна точка (не дублируется)."""
    pts, seen = [], set()
    lines = [k * SEAM_STEP for k in range(-int(half / SEAM_STEP) + 1, int(half / SEAM_STEP))]
    n = int(2 * half / SEAM_DOT_STEP)
    for c in lines:
        for i in range(n):
            s = -half + SEAM_DOT_STEP * (i + 0.5)
            for p in ((c, s), (s, c)):
                key = (round(p[0], 2), round(p[1], 2))
                if key in seen or rng.random() < 0.10:
                    continue
                seen.add(key)
                pts.append(Vector((p[0], p[1], TOP + 0.012)))
    return pts


def build_floor_slab(out, size, seed):
    half = size / 2.0
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    rim = tuple(c * 0.6 for c in cy)  # контур верха слабее штрихов
    bm = env._slab_bm(0.0, 0.0, half, half, TOP, 1.0)
    infos = [(0.0, 0.0, half, half, TOP)]
    streaks = env._slab_streaks(rng, 0.0, 0.0, half, half, TOP, 1.0, STREAK_PITCH, HANG_MAX, HANG_MAX, 0.011, 0.017, 0.65, p_gap=STREAK_GAP)
    objs = [
        lib.obj_from_bm("slab", bm, "solid_dark", cy, rgb_fn=env._slab_rgb(infos, rim, lib.lin("void"))),
        lib.streak_set("floor_slab_streaks_hang", streaks, cy),
        lib.skirt_set("floor_slab_skirt", _skirts(rng, half), cy),
        lib.point_cloud("slab_seams", _seam_dots(rng, half), cy, half_size=0.02, seed=seed, a_min=0.4, a_max=0.8),
    ]
    k = size / 16.0  # бюджет карточки для 16×16, для 8×8 пропорционально по периметру/площади
    return lib.export(f"floor_slab_{size}", "env", objs, out, budget_tris=int(400 * k), budget_points=int(700 * k), origin="slab", budget_streaks=int(260 * k),
                      notes=f"ЭКСПЕРИМЕНТ: пол одной плитой {size}×{size} м (3 см, верх на {TOP * 100:.0f} см), швы каждые {SEAM_STEP:g} м, подвесные штрихи и вуаль по периметру")


if __name__ == "__main__":
    o = lib.args()
    build_floor_slab(o, 8, seed=201)
    build_floor_slab(o, 16, seed=202)

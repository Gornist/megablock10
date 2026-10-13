"""Пол комнаты ОДНОЙ плитой, ассет env/floor_slab_16 (настоящая комната 16×16 = NodeLayout.ROOM_MIN..ROOM_MAX; клиент ставит в ROOM_CENTER (0, 0, −6)).
Запуск: blender -b --python floor_slab.py -- --out <корень netrun/assets>

Решение владельца 2026-10-05: «давай попробуем сделать пол одним тайлом». Те же правила, что у плит пола (env.py): плита тонкая (3 см), верх чёрный (solid_dark)
на уровне пола (−1 см), контур верха светится полной яркостью cyan, по четырём граням вуаль `*_skirt` (кромка делится на отрезки по 2 м). Сетка клеток 1 м —
текстурой в шейдере solid_dark (ручка floor_grid), не геометрией. Под плитой пустота и дальние пласты.
Край плиты ровно на линии края room_edge_16 (сторона = 16, край ±8): тот же параметр half, что в edge.py. Origin «slab» — центр плиты, верх на полу.

Рефактор B2 (12.10.2026): подвесные штрихи и точки швов убраны (в окружении штрихи и точки не рисуются, streak_keep=0 и point_keep=0 приняты на очках;
сетка клеток — текстурой), как и размер 8×8, стеклянный вариант `floor_glass_<N>` и `_glass_top`. Вызовы генератора штрихов остаются без вывода, чтобы датчик
случайных чисел шёл прежним путём: вуаль и высоты остаются теми же, что на очках."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
import env  # noqa: E402  (плиты и штрихи кромки — те же функции, что у плиток пола)

TOP = -0.01          # верх плиты, м: на уровне пола, ничего не выступает
STREAK_PITCH = 0.25  # шаг подвесных штрихов, м (только для датчика случайных чисел, см. build_floor_slab)
STREAK_GAP = 0.12    # доля пропусков (там же)
HANG_MAX = 0.9       # длина подвесных штрихов, м (там же)
SKIRT_SEG = 2.0     # длина отрезка вуали вдоль кромки, м


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


def build_floor_slab(out, size, seed):
    """Непрозрачная чёрная плита `floor_slab_<N>` с вуалью по периметру."""
    half = size / 2.0
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    rim = cy  # контур верха полной яркости cyan: единственная граница комнаты без стен (кадр клиента 5 окт: при ×0,6 край терялся)
    name = f"floor_slab_{size}"
    infos = [(0.0, 0.0, half, half, TOP)]
    top = lib.obj_from_bm("slab", env._slab_bm(0.0, 0.0, half, half, TOP, 1.0), "solid_dark", cy, rgb_fn=env._slab_rgb(infos, rim, lib.lin("void")))
    env._slab_streaks(rng, 0.0, 0.0, half, half, TOP, 1.0, STREAK_PITCH, HANG_MAX, HANG_MAX, 0.011, 0.017, 0.65, p_gap=STREAK_GAP)  # вывод не нужен, см. докстроку файла
    objs = [
        top,
        lib.skirt_set(f"floor_slab_skirt", _skirts(rng, half), cy),
    ]
    return lib.export(name, "env", objs, out, budget_tris=400, budget_points=0, origin="slab", budget_streaks=0,
                      notes=f"пол одной чёрной плитой (3 см) {size}×{size} м (верх на {TOP * 100:.0f} см), вуаль по периметру; сетка клеток 1 м — текстурой в шейдере")


if __name__ == "__main__":
    o = lib.args()
    build_floor_slab(o, 16, seed=202)

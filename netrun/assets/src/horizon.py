"""Ассет env/horizon_band: кольцо тонких высоких штрихов далеко за комнатой — «туман» на линии горизонта.
Запуск: blender -b --python horizon.py -- --out <корень netrun/assets>

В референсе (киберпространство Cyberpunk 2077) к горизонту штрихи копятся в яркую бирюзовую дымку на уровне глаз, а ближние
чёрные плиты режут её силуэтами. Это кольцо даёт такую дымку: радиус 35–70 м, высота от −3 до +8 м, плотность и яркость растут к уровню
глаз (центры штрихов собраны около 1,5 м, яркость — гауссиана по высоте). Шаг по углу неравномерный, есть пропуски, разные радиус
и высота; ширина штриха растёт с радиусом, чтобы угловой размер был сопоставим. Меш `horizon_streaks`, 400 штрихов = 800 треугольников.
Одни штрихи давали смазанные прямоугольные пятна, а не туман, поэтому добавлен второй меш `horizon_mist` — сплошная дымка (владелец: «горизонт — сплошной
дымкой»): замкнутая цилиндрическая лента 48 сегментов × 2 пояса = 192 треугольника в один слой, радиус 45–60 м, плотность (альфа вершин) — «шатёр»
по высоте: 0 на −3 м, максимум на уровне глаз +1,5 м, 0 на +9 м (в шейдере сглаживается) и слабая вариация по азимуту. Штрихи кольца стали слабее (STREAK_GAIN):
остались «структурой внутри дымки». Шейдер дымки (`haze.gdshader`) подставляет Godot по имени меша `*_mist`.
Ставится ОДИН раз в центр узла (Origin на уровне пола в центре); затухание по расстоянию у него отодвинуто (fade ≥ 150 м),
яркость штрихов усиливает far_gain в шейдере streaks. Не ближе 35 м: вплотную штрихи не должны попадаться на глаза."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

R_MIN, R_MAX = 35.0, 70.0      # радиус кольца, м
Y_MIN, Y_MAX = -3.0, 8.0       # высота штрихов, м (от уровня пола узла)
EYE = 1.5                      # уровень глаз: здесь штрихи гуще и ярче
MAX_STREAKS = 400
STREAK_GAIN = 0.55             # штрихи кольца слабее: основную яркость на горизонте даёт сплошная дымка
HAZE_SEGS = 48                 # сегментов ленты по кругу: 48 × 2 пояса × 2 треугольника = 192 (≤ 200)
HAZE_Y = (-3.0, EYE, 9.0)      # кольца ленты: плотность 0 внизу, максимум на уровне глаз, 0 вверху (шатёр, в шейдере сглажен)
HAZE_R = (45.0, 60.0)          # радиус ленты по азимуту, м


def build_horizon_band(out, name="horizon_band", seed=81):
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    attempts = 440
    st, gap = [], 0
    ph = rng.uniform(0, 6.28)
    for i in range(attempts):
        if gap > 0:
            gap -= 1
            continue
        if rng.random() < 0.1:  # пропуск: 1–3 штриха подряд
            gap = rng.randint(0, 2)
            continue
        ang = 2 * math.pi * (i + rng.uniform(-0.45, 0.45)) / attempts
        # радиус плавно «дышит» по углу + шум: кольцо не читается как окружность
        r = 52.0 + 11.0 * math.sin(ang * 3 + ph) + 5.0 * math.sin(ang * 8 + 1.3 * ph) + rng.uniform(-7.0, 7.0)
        r = max(R_MIN, min(R_MAX, r))
        zc = rng.gauss(EYE, 2.1)
        h = rng.uniform(0.9, 3.0)
        zc = max(Y_MIN + h, min(Y_MAX - h * 1.6, zc))  # с дыханием (до ×1,3 от основания) верх не выше Y_MAX
        eye = math.exp(-(((zc - EYE) / 2.6) ** 2))
        a = (0.2 + 0.8 * eye) * rng.uniform(0.65, 1.0) * STREAK_GAIN
        w = r * rng.uniform(0.003, 0.008)  # шире штрихов комнаты: на 50 м это 15–40 см, вместе с ореолом сливается в дымку
        col = ice if (eye > 0.7 and rng.random() < 0.15) else cy
        st.append((Vector((r * math.cos(ang), r * math.sin(ang), zc)), w, h, a, col))
    st = st[:MAX_STREAKS]
    # сплошная дымка: радиус и плотность по азимуту плавно «гуляют» (не ровное кольцо), без случайных скачков между соседними вершинами
    mid_r, amp_r = (HAZE_R[0] + HAZE_R[1]) / 2, (HAZE_R[1] - HAZE_R[0]) / 2
    seg_r, seg_d = [], []
    for i in range(HAZE_SEGS):
        ang = 2 * math.pi * i / HAZE_SEGS
        w = 0.6 * math.sin(ang * 2 + ph) + 0.4 * math.sin(ang * 5 + 1.7 * ph)  # −1…1, периодична по кругу
        seg_r.append(mid_r + amp_r * w)
        d = 0.72 + 0.17 * math.sin(ang * 3 + 2.1 * ph) + 0.11 * math.sin(ang * 7 + 0.4 * ph) + rng.uniform(-0.06, 0.06)
        seg_d.append(max(0.5, min(1.0, d)))
    rings = [(y, [(seg_r[i], seg_d[i] if y == EYE else 0.0) for i in range(HAZE_SEGS)]) for y in HAZE_Y]
    objs = [lib.streak_set("horizon_streaks", st, cy), lib.haze_band("horizon_mist", rings, cy)]
    return lib.export(name, "env", objs, out, budget_tris=1000, budget_streaks=MAX_STREAKS, origin="horizon",
                      notes="кольцо штрихов 35–70 м и сплошная дымка 45–60 м вокруг центра узла, высота −3…+9 м; ставить один раз, fade ≥ 150 м, far_gain в streaks")


if __name__ == "__main__":
    build_horizon_band(lib.args())

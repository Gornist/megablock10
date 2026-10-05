"""Ассет env/horizon_band: кольцо тонких высоких штрихов далеко за комнатой — «туман» на линии горизонта.
Запуск: blender -b --python horizon.py -- --out <корень netrun/assets>

В референсе (киберпространство Cyberpunk 2077) к горизонту штрихи копятся в яркую бирюзовую дымку на уровне глаз, а ближние
чёрные плиты режут её силуэтами. Это кольцо даёт такую дымку: радиус 35–70 м, высота от −3 до +8 м, плотность и яркость растут к уровню
глаз (центры штрихов собраны около 1,5 м, яркость — гауссиана по высоте). Шаг по углу неравномерный, есть пропуски, разные радиус
и высота; ширина штриха растёт с радиусом, чтобы угловой размер был сопоставим. Один меш `horizon_streaks`, 400 штрихов = 800 треугольников.
Ставится ОДИН раз в центр узла (Origin на уровне пола в центре); затухание по расстоянию у него отодвинуто (fade ≥ 150 м),
яркость усиливает far_gain в шейдере streaks. Не ближе 35 м: вплотную штрихи не должны попадаться на глаза."""
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
        a = (0.2 + 0.8 * eye) * rng.uniform(0.65, 1.0)
        w = r * rng.uniform(0.003, 0.008)  # шире штрихов комнаты: на 50 м это 15–40 см, вместе с ореолом сливается в дымку
        col = ice if (eye > 0.7 and rng.random() < 0.15) else cy
        st.append((Vector((r * math.cos(ang), r * math.sin(ang), zc)), w, h, a, col))
    st = st[:MAX_STREAKS]
    objs = [lib.streak_set("horizon_streaks", st, cy)]
    return lib.export(name, "env", objs, out, budget_tris=800, budget_streaks=MAX_STREAKS, origin="horizon",
                      notes="кольцо 35–70 м вокруг центра узла, высота −3…+8 м; ставить один раз, fade ≥ 150 м, far_gain в streaks")


if __name__ == "__main__":
    build_horizon_band(lib.args())

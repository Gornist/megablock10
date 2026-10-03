"""Группа ice: существа Сети. Запуск: blender -b --python ice.py -- --out <корень netrun/assets>"""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def build_soft_ice(out):
    """Soft ICE: облако красных штрихов (как «сущности» в референсе Blackwall): плотное основание, рваный верх, наклон,
    раскалённое ядро и несколько высоких игл. Без конусов и геометрии. Origin «у ног» на полу. Анимации — следующим этапом."""
    lib.reset()
    rng = random.Random(14)
    red, hot = lib.lin("threat"), lib.lin("threat_hot")
    body, core = [], []
    for _ in range(150):
        ang, r = rng.uniform(0, math.tau), 0.5 * math.sqrt(rng.random())
        hh = max(0.15, 2.0 * (1.0 - (r / 0.5) ** 1.4) * rng.uniform(0.45, 1.0))
        x, y = r * math.cos(ang) + 0.16 * hh, 0.7 * r * math.sin(ang)
        body.append((Vector((x, y, hh / 2)), rng.uniform(0.01, 0.022), hh / 2, rng.uniform(0.25, 0.8)))
    for _ in range(26):
        ang, r = rng.uniform(0, math.tau), 0.14 * math.sqrt(rng.random())
        hh = rng.uniform(1.0, 1.7)
        core.append((Vector((r * math.cos(ang) + 0.16 * hh, 0.7 * r * math.sin(ang), hh / 2)), rng.uniform(0.012, 0.02), hh / 2, rng.uniform(0.7, 1.0)))
    for dx, hh in ((0.28, 2.15), (0.05, 2.0), (0.4, 1.8)):  # иглы: высокие тонкие штрихи над облаком
        core.append((Vector((dx, rng.uniform(-0.05, 0.05), hh / 2)), 0.009, hh / 2, 0.9))
    objs = [lib.streak_set("ice_body", body, red), lib.streak_set("ice_core", core, hot)]
    haze = [Vector((0.55 * math.sqrt(rng.random()) * math.cos(a), 0.4 * math.sqrt(rng.random()) * math.sin(a), 0.0)) for a in [rng.uniform(0, math.tau) for _ in range(160)]]
    objs.append(lib.point_cloud("ice_haze", haze, red, half_size=0.075, seed=3, a_min=0.1, a_max=0.35, on_floor=True))
    return lib.export("soft_ice", "ice", objs, out, budget_tris=300, budget_points=200, budget_streaks=200, origin="feet", notes="без анимаций (пилот)")


def build_black_ice(out, name="black_ice", seed=31, scale=2.0):
    """Black ICE (только узлы NIGHTMARE): человеческий силуэт ×2 (≈2,6 м, иглы до 3,4 м) из синих штрихов с повреждёнными данными.
    Оболочка синяя, внутри туловища и головы возникает красная форма (ядро ярче у головы). Повреждения: горизонтальные полосы, где штрихов
    нет (части пропадают), вырезанный кусок плеча, руки разной длины (одна тянется вперёд), смещённые вбок осколки точек. «Юбка» из красных
    штрихов вместо ног, выше и рваннее, чем у аватара. Без лица. Не робот и не человек: то, что нарушает язык Сети. Origin «feet».
    Анимации (idle, hunt, catch) — состояния шейдера и отдельные ассеты, скелета нет."""
    from avatar import _in_capsule, _in_ellipsoid, _in_torso
    lib.reset()
    rng = random.Random(seed)
    blue, red, hot = lib.lin("blue"), lib.lin("threat"), lib.lin("threat_hot")
    k = scale
    bands = [(rng.uniform(1.0, 2.5), rng.uniform(0.06, 0.16)) for _ in range(4)]  # выше пояса: «юбка» и пояс целы  # (z, толщина) полос потери данных, в метрах после масштаба
    cut = Vector((-0.17, 0.0, 1.02))  # вырезанный кусок левого плеча (в координатах до масштаба)

    def lost(p):
        if (p - cut).length < 0.14:
            return True
        return any(abs(p.z * k - z) < t / 2 and rng.random() < 0.9 for z, t in bands)

    shell, inner, pts = [], [], []

    def dash(p, color, store, a=(0.3, 0.8), hh=(0.04, 0.12), w=(0.016, 0.03), glitch=True):
        q = Vector((p.x * k, p.y * k, p.z * k))
        if glitch and lost(p):
            if rng.random() < 0.35:  # часть потерянного не пропадает, а смещается вбок осколком точек
                pts.append(q + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.1, 0.1), 0)))
            return
        store.append((q, rng.uniform(*w) * 1.3, rng.uniform(*hh) * 1.3, rng.uniform(*a), color))

    for _ in range(42):
        dash(_in_ellipsoid(rng, (0, 0.02, 1.31), (0.105, 0.12, 0.14)), blue, shell, a=(0.4, 0.85))   # голова: оболочка
    for _ in range(95):
        dash(_in_torso(rng), blue, shell, a=(0.35, 0.8))                                           # торс: оболочка
    for sx, long in ((-1, 0.0), (1, 0.55)):  # правая рука тянется вперёд и длиннее
        sh = (sx * 0.20, 0, 1.03)
        el = (sx * 0.24, 0.05 + 0.15 * long, 0.78 - 0.1 * long)
        hd = (sx * 0.17, 0.30 + 0.62 * long, 0.86 - 0.2 * long)
        for _ in range(12):
            dash(_in_capsule(rng, sh, el, 0.04), blue, shell, a=(0.35, 0.8))
        for _ in range(12):
            dash(_in_capsule(rng, el, hd, 0.035), blue, shell, a=(0.35, 0.8))
        for _ in range(8):
            dash(_in_ellipsoid(rng, hd, (0.06, 0.06, 0.06)), red, inner, a=(0.6, 1.0), glitch=False)  # кисть уже красная
    for _ in range(44):  # красная форма внутри: туловище уже оболочки, голова как раскалённая точка
        dash(_in_torso(rng) * 0.6 + Vector((0, 0, 0.35)), red, inner, a=(0.55, 1.0), hh=(0.03, 0.09), w=(0.012, 0.022), glitch=False)
    for _ in range(16):
        dash(_in_ellipsoid(rng, (0, 0.02, 1.31), (0.05, 0.06, 0.07)), hot, inner, a=(0.8, 1.0), hh=(0.02, 0.05), w=(0.012, 0.02), glitch=False)
    for _ in range(30):  # «юбка» красных штрихов, выше и рваннее
        r = 0.20 * math.sqrt(rng.random())
        ang = rng.uniform(0, math.tau)
        top = rng.uniform(0.3, 0.8) * k
        inner.append((Vector((r * math.cos(ang) * k, 0.7 * r * math.sin(ang) * k, top / 2)), rng.uniform(0.012, 0.022), top / 2, rng.uniform(0.2, 0.6), red))
    for dx, hh in ((0.12, 3.4), (-0.18, 3.1), (0.34, 2.9)):  # иглы над головой
        inner.append((Vector((dx, rng.uniform(-0.05, 0.05), hh / 2)), 0.011, hh / 2, 0.9, hot))
    objs = [lib.streak_set("black_ice_shell", shell, blue), lib.streak_set("black_ice_inner", inner, red)]
    dust = [(c + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.6))).normalized() * rng.uniform(0.05, 0.2)) for c in rng.sample([x[0] for x in shell], min(260, len(shell)))]
    dust = [Vector((p.x, p.y, max(p.z, 0.012))) for p in dust + pts]
    objs.append(lib.point_cloud("black_ice_dust", dust, blue, half_size=0.011, seed=seed, a_min=0.2, a_max=0.7, on_floor=True))
    return lib.export(name, "ice", objs, out, budget_tris=300, budget_points=600, budget_streaks=350, origin="feet",
                      notes="только NIGHTMARE; лицом к Blender +Y (Godot −Z); idle/hunt/catch — состояния шейдера")


if __name__ == "__main__":
    o = lib.args()
    build_soft_ice(o)
    build_black_ice(o)

"""Группа avatar: аватары других нетраннеров. Запуск: blender -b --python avatar.py -- --out <корень netrun/assets>

По сети чужие аватары передаются только позицией на полу (RemoteTracks, 20 раз/с): позы головы и рук нет, поэтому это целая фигура с
фиксированной позой и «дыханием» в шейдере, без скелета. Лицом к Blender +Y (в Godot −Z). Рост сидящего: голова на ~1,3 м."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def _in_ellipsoid(rng, c, r):
    while True:
        v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if v.length <= 1.0:
            return Vector((c[0] + v.x * r[0], c[1] + v.y * r[1], c[2] + v.z * r[2]))


def _in_capsule(rng, a, b, r):
    t = rng.random()
    while True:
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if d.length <= 1.0:
            return Vector(a).lerp(Vector(b), t) + d * r


def _in_torso(rng):
    """Усечённый эллиптический конус: плечи шире талии (z от 0,66 до 1,10)."""
    z = rng.uniform(0.66, 1.10)
    k = (z - 0.66) / 0.44
    hw, hd = 0.12 + 0.08 * k, 0.085 + 0.03 * k
    while True:
        x, y = rng.uniform(-hw, hw), rng.uniform(-hd, hd)
        if (x / hw) ** 2 + (y / hd) ** 2 <= 1.0:
            return Vector((x, y, z))


def build_runner(out, name="runner", seed=40):
    """Аватар: человек из облака красных штрихов — голова, шея, торс, руки вперёд на уровне груди (как с контроллерами), без ног:
    от талии «юбка» из штрихов вниз до пола заземляет фигуру. Голова и кисти горячее тела. Края рассыпаются точками.
    Origin «feet» на полу под фигурой. Варианты runner/runner_b/runner_c отличаются seed (девять одинаковых клонов запрещены)."""
    lib.reset()
    rng = random.Random(seed)
    red, hot = lib.lin("threat"), lib.lin("threat_hot")
    st, centers = [], []

    def dash(p, color, a=(0.35, 0.95), hh=(0.03, 0.09)):
        h = rng.uniform(*hh)
        st.append((p, rng.uniform(0.013, 0.022), h, rng.uniform(*a), color))  # широкие мягкие штрихи сливаются в светящийся объём
        centers.append(p)

    for _ in range(64):
        dash(_in_ellipsoid(rng, (0, 0.02, 1.31), (0.105, 0.12, 0.14)), hot, a=(0.6, 1.0), hh=(0.025, 0.06))        # голова
    for _ in range(8):
        dash(_in_capsule(rng, (0, 0, 1.16), (0, 0, 1.08), 0.04), red, a=(0.5, 1.0))                            # шея
    for _ in range(130):
        dash(_in_torso(rng), red, a=(0.5, 1.0))                                                                 # торс
    for sx in (-1, 1):
        sh, el, hd = (sx * 0.20, 0, 1.03), (sx * 0.22, 0.03, 0.77), (sx * 0.15, 0.36, 0.88)      # плечо, локоть, кисть
        for _ in range(16):
            dash(_in_capsule(rng, sh, el, 0.04), red, a=(0.45, 1.0))                                            # плечо → локоть
        for _ in range(16):
            dash(_in_capsule(rng, el, hd, 0.035), red, a=(0.45, 1.0))                                            # локоть → кисть
        for _ in range(8):
            dash(_in_ellipsoid(rng, hd, (0.05, 0.055, 0.05)), hot, a=(0.6, 1.0))                  # кисть
    for _ in range(36):  # «юбка» вместо ног: штрихи от пола до талии, тусклее тела, чтобы не читалась как колонна-нога
        r = 0.12 * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        top = rng.uniform(0.35, 0.72)
        st.append((Vector((r * math.cos(a), 0.7 * r * math.sin(a), top / 2)), rng.uniform(0.010, 0.016), top / 2, rng.uniform(0.15, 0.5), red))
    objs = [lib.streak_set(f"{name}_body", st, red)]
    edge = [c + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.6))).normalized() * rng.uniform(0.04, 0.14) for c in rng.sample(centers, 140)]
    objs.append(lib.point_cloud(f"{name}_dust", [p if p.z > 0.012 else Vector((p.x, p.y, 0.012)) for p in edge], red, half_size=0.009, seed=seed, a_min=0.15, a_max=0.6))
    return lib.export(name, "avatar", objs, out, budget_tris=300, budget_points=160, budget_streaks=360, origin="feet",
                      notes="лицом к Blender +Y (Godot −Z); поза головы и рук по сети не передаётся")


if __name__ == "__main__":
    o = lib.args()
    for name, seed in (("runner", 40), ("runner_b", 53), ("runner_c", 71)):
        build_runner(o, name, seed)

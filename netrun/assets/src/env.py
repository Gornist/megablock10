"""Группа env: модули окружения, сетка 2×2 м. Запуск: blender -b --python env.py -- --out <корень netrun/assets>

Стиль по референсам Blackwall (STYLE.md): свет живёт в вертикальных штрихах, поверхности чёрные и непрозрачные, пол — ряды точек.
Стена — только занавес из штрихов (яркость плывёт вдоль стены); чёрные тайлы лежат на ПОЛУ, не на стенах; сплошных реек и
стеклянных плиток нет. Граница модуля — яркие штрихи у краёв, остальное рваное."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


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
        full = hmax * rng.uniform(0.82, 1.0) * (0.8 + 0.2 * e)  # высота почти ровная (занавес), яркость плывёт по огибающей
        out.append((Vector((x, y, full / 2)), rng.uniform(*w_range), full / 2, 0.2 + 0.8 * e * rng.uniform(0.45, 1.0)))
    mid = (min(c[0].y for c in out) + max(c[0].y for c in out)) / 2  # центр разброса по глубине в нуле: модули стыкуются ровно
    return [(Vector((c.x, c.y - mid, c.z)), w, h, a) for c, w, h, a in out]


def build_wall(out, name="wall", seed=21):
    """Стена 2×2 м: занавес ~64 штрихов с плывущей яркостью, 6 ярких белых (две опоры по краям модуля), 3 чёрные плиты-перекрытия.
    Origin на полу в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    objs = [lib.streak_set("wall_curtain", curtain(rng, -0.97, 0.97, 100, 2.0), cy)]
    accents = [(Vector((-0.99, rng.uniform(-0.12, 0.12), 0.95)), 0.012, 0.95, 1.0), (Vector((0.99, rng.uniform(-0.12, 0.12), 1.0)), 0.012, rng.uniform(0.85, 1.0), 1.0)]
    for x in sorted(rng.uniform(-0.8, 0.8) for _ in range(rng.randint(3, 5))):
        hh = rng.uniform(0.7, 1.0)
        accents.append((Vector((x, rng.uniform(-0.25, 0.25), hh)), 0.011, hh, 0.95))
    objs.append(lib.streak_set("wall_accents", accents, ice))
    fill = lib.sample_box((0, 0, 1.0), (2.0, 0.4, 2.0), 50, seed=5, min_z=0.01)
    objs.append(lib.point_cloud("wall_pts", fill, cy, half_size=0.007, seed=11, a_min=0.15, a_max=0.5, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=80, budget_streaks=120, origin="floor")


def build_doorway(out, name="doorway", seed=8):
    """Проём 2×2 м (вход/выход): два занавеса по бокам, яркие белые штрихи — косяки, короткая бахрома сверху, ряды точек порога.
    Ширина прохода 1,1 м. Origin на полу в центре. Проход вдоль оси Z Godot."""
    lib.reset()
    rng = random.Random(seed)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    side = curtain(rng, -0.98, -0.66, 18, 2.0, depth=0.22, p_gap=0.07) + curtain(rng, 0.66, 0.98, 18, 2.0, depth=0.22, p_gap=0.07)
    objs = [lib.streak_set("door_curtain", side, cy)]
    jambs = [(Vector((sx * d, 0, 1.0)), 0.016, 1.0, 1.0) for sx in (-1, 1) for d in (0.52, 0.57, 0.62)]
    fringe = [(Vector((-0.55 + i * 0.1, rng.uniform(-0.03, 0.03), 2.0 - hh)), 0.008, hh, 0.7) for i in range(12) for hh in [rng.uniform(0.2, 0.55)]]
    objs.append(lib.streak_set("door_jambs", jambs + fringe, ice))
    th = [Vector((x, y, 0.0)) for x in [-0.5 + i * 0.125 for i in range(9)] for y in (-0.06, 0.06)]
    objs.append(lib.point_cloud("door_threshold", th, ice, half_size=0.018, seed=7, a_min=0.8, a_max=1.0, on_floor=True))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=40, budget_streaks=80, origin="floor")


def build_floor(out, name="floor", seed=2):
    """Плитка пола 2×2 м: ~22% площади занимают чёрные непрозрачные тайлы-блоки (5 из 16 ячеек, расстановка зависит от seed: три
    варианта floor, floor_b, floor_c, чтобы узор не повторялся). Тайлы на разной высоте, но ВЕРХ НЕ ВЫШЕ ПОВЕРХНОСТИ ПОЛА (0…−0,45 м): никаких выступов, коллизий нет. Верх чёрный,
    рёбра — цепочки частиц; штрихи висят вниз из рёбер под тайлы, в пустоту под полом (якорь сверху). Остальной пол — редкая решётка точек. Origin на поверхности пола в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    chosen = rng.sample([(i, j) for i in range(4) for j in range(4)], 5)
    tiles, streaks, edge, covered = [], [], [], []
    for i, j in chosen:
        cx, cyy = -0.75 + i * 0.5, -0.75 + j * 0.5
        hh = 0.0 if rng.random() < 0.3 else -rng.uniform(0.05, 0.45)  # верх тайла на разной высоте, но не выше пола (0): без выступов и коллизий
        covered.append((cx, cyy))
        tiles.append(lib.box_bm((0.42, 0.42, 0.3), center=(cx, cyy, hh - 0.15)))
        for a, b in (((cx - 0.21, cyy - 0.21, hh), (cx + 0.21, cyy - 0.21, hh)), ((cx - 0.21, cyy - 0.21, hh), (cx - 0.21, cyy + 0.21, hh))):
            edge += lib.sample_line(a, b, 22, spread=0.004, seed=len(edge) + 1)  # две видимые грани тайла — цепочка частиц
        for _ in range(10):  # штрихи уходят вниз из рёбер тайла, под пол
            if rng.random() < 0.5:
                ex, ey = cx + rng.choice((-0.21, 0.21)), cyy + rng.uniform(-0.21, 0.21)
            else:
                ex, ey = cx + rng.uniform(-0.21, 0.21), cyy + rng.choice((-0.21, 0.21))
            ln = rng.uniform(0.2, 0.45)
            streaks.append((Vector((ex, ey, hh - ln / 2)), rng.uniform(0.006, 0.012), ln / 2, rng.uniform(0.3, 0.85)))
    objs = [lib.obj_from_bm("floor_tiles", lib.merge_bm(*tiles), "solid_dark", lib.lin("void"), alpha=1.0)]  # верх чёрный: кайма не нужна
    objs.append(lib.streak_set("floor_streaks_hang", streaks, cy))
    objs.append(lib.point_cloud("floor_edges", edge, cy, half_size=0.011, seed=4, a_min=0.5, a_max=1.0))
    # Точки пола: шаг по горизонтали постоянный, часть точек пропущена (~15%), высота слегка разная, но не выше поверхности пола
    dots = [Vector((-0.875 + i * 0.25, -0.875 + j * 0.25, -rng.uniform(0.016, 0.09))) for i in range(8) for j in range(8) if rng.random() > 0.15]
    dots = [d for d in dots if not any(abs(d.x - cx) < 0.25 and abs(d.y - cyy) < 0.25 for cx, cyy in covered)]  # не под тайлами
    objs.append(lib.point_cloud("floor_dots", dots, cy, half_size=0.016, seed=2, a_min=0.4, a_max=0.9))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=170, budget_streaks=60, origin="surface",
                      notes=f"тайлы покрывают {5 * 0.42 * 0.42 / 4.0 * 100:.0f}% плитки 2×2 м")


def build_pillar(out):
    """Колонна на углу: пучок высоких штрихов (два белых) и несколько точек у основания. Высота до 2,4 м. Origin на полу в центре."""
    lib.reset()
    rng = random.Random(6)
    cy, ice = lib.lin("cyan"), lib.lin("ice_white")
    st = []
    for _ in range(9):
        hh = rng.uniform(0.7, 1.2)
        st.append((Vector((rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07), hh)), rng.uniform(0.01, 0.018), hh, rng.uniform(0.4, 0.9)))
    objs = [lib.streak_set("pillar_streaks", st, cy)]
    objs.append(lib.streak_set("pillar_core", [(Vector((0, 0, 1.1)), 0.012, 1.1, 1.0), (Vector((0.03, 0.02, 0.9)), 0.01, 0.9, 0.9)], ice))
    return lib.export("pillar", "env", objs, out, budget_tris=300, budget_streaks=16, origin="floor")


if __name__ == "__main__":
    o = lib.args()
    build_pillar(o)
    for name, seed in (("wall", 21), ("wall_b", 34), ("wall_c", 55)):
        build_wall(o, name, seed)
    for name, seed in (("doorway", 8), ("doorway_b", 17)):
        build_doorway(o, name, seed)
    for name, seed in (("floor", 2), ("floor_b", 5), ("floor_c", 9)):
        build_floor(o, name, seed)

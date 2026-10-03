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


def _tile_bm(cx, cyy, hh, sg):
    """Чёрный тайл 0,42×0,42×0,3 м: поверхность, обращённая в комнату, на высоте sg·hh. У неё сделана рамка шириной 1,4 см (inset), а боковые грани
    разрезаны на 1,4 см ниже поверхности: так подсвечивается сам верхний край тайла. Метка света — цвет вершины (см. _tile_rgb, шейдер solid_dark)."""
    bm = lib.box_bm((0.42, 0.42, 0.3), center=(cx, cyy, sg * (hh - 0.15)))
    zf = sg * hh
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, 0, zf - sg * 0.014), plane_no=(0, 0, 1))
    bm.normal_update()
    top = [f for f in bm.faces if f.normal.z * sg > 0.9 and abs(f.calc_center_median().z - zf) < 1e-4]
    bmesh.ops.inset_individual(bm, faces=top, thickness=0.014)
    return bm


def _tile_rgb(infos, glow, dark):
    """Цвет вершины тайла: glow на внешнем контуре поверхности (светится), чёрный везде ниже и внутри рамки. infos — [(cx, cyy, zf)]."""
    def fn(co):
        for cx, cyy, zf in infos:
            if abs(co.z - zf) < 1e-4 and abs(abs(co.x - cx) - 0.21) < 1e-4 and abs(abs(co.y - cyy) - 0.21) < 1e-4:
                return glow
        return dark
    return fn


def build_floor(out, name="floor", seed=2, ceiling=False, n_tiles=5):
    """Плитка пола (или потолка при ceiling=True) 2×2 м: ~22% площади занимают чёрные непрозрачные тайлы-блоки (5 из 16 ячеек,
    расстановка зависит от seed: три варианта на пол и три на потолок, чтобы узор не повторялся). Верх тайла чёрный, точек по граням нет (убрано по решению владельца). Пол: верх тайла НЕ ВЫШЕ поверхности пола (0…−0,45 м), штрихи висят вниз из рёбер, точки на полу чуть ниже поверхности.
    Потолок — то же, инвертированное (знак высоты меняется): низ тайла НЕ НИЖЕ плоскости потолка (0…+0,45 м), штрихи растут вверх из
    рёбер, точки чуть выше плоскости; ничего не выступает в комнату, коллизий нет. Origin на поверхности в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    sg = -1.0 if ceiling else 1.0  # знак по высоте: пол смотрит вниз от поверхности, потолок вверх
    chosen = rng.sample([(i, j) for i in range(4) for j in range(4)], n_tiles)  # n_tiles = 0: чистая площадка без тайлов (под хранилище)
    tiles, streaks, covered, infos = [], [], [], []
    for i, j in chosen:
        cx, cyy = -0.75 + i * 0.5, -0.75 + j * 0.5
        hh = 0.0 if rng.random() < 0.3 else -rng.uniform(0.05, 0.45)  # поверхность тайла на разной высоте, но не в сторону комнаты
        covered.append((cx, cyy))
        tiles.append(_tile_bm(cx, cyy, hh, sg))
        infos.append((cx, cyy, sg * hh))
        # занавес на боковых гранях тайла (те же штрихи, что у стен, но в разы тише): по 7 штрихов на грань вдоль ребра, ~20% пропусков,
        # длина плывёт плавной волной (до 0,7 м), яркость 0,12–0.4 (у стен 0,2–1,0); у пола вниз от ребра, у потолка вверх. Дыхание, бусины и
        # мерцание дают те же параметры шейдера, что у стен (без отдельной настройки). Вглубь штрих не уходит ниже −0,95 м от плоскости.
        base = rng.uniform(0.25, 0.7)
        ph = rng.uniform(0, 6.28)
        for side in range(4):
            for q in range(7):
                if rng.random() < 0.2:
                    continue
                t = -0.2 + 0.4 * (q + 0.5) / 7
                ex, ey = [(cx + t, cyy - 0.21), (cx + 0.21, cyy + t), (cx + t, cyy + 0.21), (cx - 0.21, cyy + t)][side]
                ln = base * (0.55 + 0.45 * (0.5 + 0.5 * math.sin(q * 1.3 + side * 1.9 + ph))) * rng.uniform(0.7, 1.0)
                ln = min(ln, 0.95 + hh)
                streaks.append((Vector((ex, ey, sg * (hh - ln / 2))), rng.uniform(0.006, 0.011), ln / 2, rng.uniform(0.12, 0.4)))
    objs = [lib.obj_from_bm("tiles", lib.merge_bm(*tiles), "solid_dark", cy, rgb_fn=_tile_rgb(infos, cy, lib.lin("void")))] if tiles else []  # чёрный блок, светится только контур верхней грани
    # пол: якорь сверху (имя *_hang); потолок: штрихи растут вверх от рёбер, якорь по умолчанию у основания
    objs.append(lib.streak_set(("ceiling_streaks" if ceiling else "floor_streaks_hang"), streaks, cy))
    # точки: шаг постоянный, ~15% пропущено, высота слегка разная, но не в сторону комнаты
    dots = [Vector((-0.875 + i * 0.25, -0.875 + j * 0.25, sg * -rng.uniform(0.016, 0.09))) for i in range(8) for j in range(8) if rng.random() > 0.15]
    dots = [d for d in dots if not any(abs(d.x - cx) < 0.25 and abs(d.y - cyy) < 0.25 for cx, cyy in covered)]  # не под тайлами
    objs.append(lib.point_cloud("dots", dots, cy, half_size=0.016, seed=2, a_min=0.4, a_max=0.9))
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=170, budget_streaks=160, origin=("ceiling" if ceiling else "surface"),
                      notes=f"тайлы покрывают {n_tiles * 0.42 * 0.42 / 4.0 * 100:.0f}% плитки 2×2 м")


def build_far_surface(out, name="far_floor", seed=61, ceiling=False, size=11.0, cover=0.05):
    """Пол (или потолок при ceiling=True) дальнего плана: участок 11×11 м того же устройства, что плитка комнаты (build_floor), но разреженный:
    чёрные тайлы занимают ~5% площади вместо 22% (cover). Тайлы на разной высоте, но не в сторону комнаты; штрихи из рёбер вниз (вверх у потолка);
    точки на полу реже (шаг 0,75 м, ~15% пропусков). Нужен, чтобы пол и потолок были везде, а не только в комнате; в игре берутся участки сеткой 11 м.
    Origin на поверхности (потолок: на плоскости потолка) в центре."""
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    sg = -1.0 if ceiling else 1.0
    half = size / 2 - 0.5
    n = int(cover * size * size / (0.42 * 0.42))
    tiles, streaks, covered, infos = [], [], [], []
    for _ in range(n):
        cx, cyy = rng.uniform(-half, half), rng.uniform(-half, half)
        hh = 0.0 if rng.random() < 0.3 else -rng.uniform(0.05, 0.45)
        covered.append((cx, cyy))
        tiles.append(_tile_bm(cx, cyy, hh, sg))
        infos.append((cx, cyy, sg * hh))
        for _ in range(4):
            if rng.random() < 0.5:
                ex, ey = cx + rng.choice((-0.21, 0.21)), cyy + rng.uniform(-0.21, 0.21)
            else:
                ex, ey = cx + rng.uniform(-0.21, 0.21), cyy + rng.choice((-0.21, 0.21))
            ln = rng.uniform(0.2, 0.45)
            streaks.append((Vector((ex, ey, sg * (hh - ln / 2))), rng.uniform(0.008, 0.014), ln / 2, rng.uniform(0.25, 0.7)))
    objs = [lib.obj_from_bm("tiles", lib.merge_bm(*tiles), "solid_dark", cy, rgb_fn=_tile_rgb(infos, cy, lib.lin("void")))]
    objs.append(lib.streak_set(("far_ceiling_streaks" if ceiling else "far_floor_streaks_hang"), streaks, cy))
    steps = int(size / 0.75)
    dots = [Vector((-size / 2 + 0.375 + i * 0.75, -size / 2 + 0.375 + j * 0.75, sg * -rng.uniform(0.016, 0.09))) for i in range(steps) for j in range(steps) if rng.random() > 0.15]
    dots = [d for d in dots if not any(abs(d.x - cx) < 0.3 and abs(d.y - cyy) < 0.3 for cx, cyy in covered)]
    dots += [Vector((sx * (size / 2 - 0.1), sy * (size / 2 - 0.1), sg * -0.03)) for sx in (-1, 1) for sy in (-1, 1)]  # угловые точки: габарит симметричен, участки стыкуются
    objs.append(lib.point_cloud("far_surface_pts", dots, cy, half_size=0.02, seed=2, a_min=0.3, a_max=0.8))
    return lib.export(name, "env", objs, out, budget_tris=1100, budget_points=700, budget_streaks=200, origin=("ceiling" if ceiling else "surface"),
                      notes=f"тайлы {n * 0.42 * 0.42 / (size * size) * 100:.1f}% площади участка {size:g}×{size:g} м")


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
    build_floor(o, "floor_clear", 14, n_tiles=0)
    for name, seed in (("ceiling", 3), ("ceiling_b", 6), ("ceiling_c", 11)):
        build_floor(o, name, seed, ceiling=True)

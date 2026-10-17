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
    objs.append(lib.anchor("AlertAnchor", (0.0, 0.0, 2.3)))
    rig = lib.make_rig("Rig", objs)
    I, ONE = (0, 0, 0), (1, 1, 1)
    lib.add_clips(rig, {
        # idle: подозрение, стоит и «дышит» всем телом
        "idle": (3.0, [(0, (0, 0, 0), I, ONE), (1.5, (0, 0, 0), (0, 1.5, 0), (1, 1, 1.05)), (3.0, (0, 0, 0), I, ONE)]),
        # patrol: шаг вперёд с лёгким наклоном и покачиванием, два «шага» за цикл
        "patrol": (1.6, [(0, (0, 0, 0), (-4, 0, 0), ONE), (0.4, (0, 0, 0.05), (-5, 0, 3), ONE), (0.8, (0, 0, 0), (-4, 0, 0), ONE),
                         (1.2, (0, 0, 0.05), (-5, 0, -3), ONE), (1.6, (0, 0, 0), (-4, 0, 0), ONE)]),
    })
    return lib.export("soft_ice", "ice", objs + [rig], out, budget_tris=300, budget_points=200, budget_streaks=200, origin="feet", animations=True,
                      notes="клипы idle и patrol на корневом узле Rig; метка AlertAnchor над головой")


BLACK_ICE_STATES = {
    # state: наклон вперёд, длина правой/левой руки (0…1), разведение рук в стороны, число полос потери, шанс потери в полосе,
    #        штрихов красной формы, трещин, игл, широкая красная завеса вокруг (поимка)
    "idle": dict(lean=0.0, arms=(0.55, 0.0), spread=0.0, bands=4, loss=0.9, red=44, cracks=8, spikes=3, veil=0),
    "hunt": dict(lean=0.45, arms=(0.9, 0.9), spread=0.0, bands=3, loss=0.8, red=60, cracks=12, spikes=5, veil=0),
    "catch": dict(lean=0.6, arms=(1.0, 1.0), spread=0.38, bands=7, loss=0.95, red=70, cracks=14, spikes=6, veil=40),
}


BLACK_KINDS = ("hound", "kraken", "raven", "scorpion", "lich")


def _black_kind_extras(kind, seed, shell, inner, pts, blue, red, hot):
    """Отличительная деталь вида Black ICE (ice.md §6.2): добавляется к ОБЩЕМУ силуэту (тот же seed 31, поэтому база побайтно та же, что у black_ice),
    свой датчик случайных чисел (seed + 1000), чтобы не сдвигать раскладку базы. Координаты — в метрах после масштаба (фигура ≈ 2,6 м, лицом к +Y).
    hound (Гончая: быстрая, жжёт деку) — грива из ярких штрихов вдоль спины; kraken (закрывает выход) — кольцо столбов-щупалец вокруг и точки по полу;
    raven (Ворон: сносит программу) — крылья из штрихов, поднимающиеся наружу; scorpion (Скорпион: сужает прыжок) — хвост дугой над спиной с жалом;
    lich (Лич: стирает «расшифрован») — корона над головой и кольцо плавающих осколков."""
    rng = random.Random(seed + 1000)
    ice = lib.lin("ice_white")
    if kind == "hound":
        # хвост из искр позади бегущей фигуры: убывающие вспышки по −Y и россыпь точек (поза — _pose_kind: низкая, вытянутая)
        for i in range(34):
            t = i / 33.0
            hh = rng.uniform(0.08, 0.30) * (1.0 - 0.5 * t)
            inner.append((Vector((rng.uniform(-0.28, 0.28) * (1.0 + t), -0.55 - 1.7 * t, rng.uniform(0.12, 0.75) * (1.0 - 0.4 * t) + hh)), rng.uniform(0.010, 0.018), hh, rng.uniform(0.6, 1.0), hot if i % 3 == 0 else red))
        for _ in range(60):
            t = rng.random()
            pts.append(Vector((rng.uniform(-0.45, 0.45), -0.6 - 2.2 * t, rng.uniform(0.05, 0.9))))
    elif kind == "kraken":
        # нити-щупальца к стенам и площадке выхода: восемь лучей по полу (цепочки точек до 2,8 м) и столбы-щупальца у корпуса
        for arm in range(8):
            a = math.tau * (arm + rng.uniform(-0.15, 0.15)) / 8.0
            length = rng.uniform(2.0, 2.8)
            for s in range(18):
                t = s / 17.0
                r = 0.5 + (length - 0.5) * t
                wob = 0.07 * math.sin(t * 9.0 + arm)
                pts.append(Vector((r * math.cos(a) - wob * math.sin(a), r * math.sin(a) + wob * math.cos(a), 0.014 + 0.05 * (1.0 - t))))
        n = 10
        for i in range(n):
            a = math.tau * (i + rng.uniform(-0.25, 0.25)) / n
            r = rng.uniform(0.8, 1.1)
            hh = rng.uniform(0.35, 0.8)
            inner.append((Vector((r * math.cos(a), 0.8 * r * math.sin(a), hh)), rng.uniform(0.02, 0.032), hh, rng.uniform(0.4, 0.7), red))
    elif kind == "raven":
        # крылья острыми гранями и клюв: наружу и вверх, концы горячие; клюв — три убывающих штриха вперёд у головы
        for side in (-1, 1):
            for i in range(18):
                t = i / 17.0
                hh = rng.uniform(0.34, 0.55) * (1.0 - 0.5 * t)
                z = 1.8 + 1.1 * t ** 1.3
                c = hot if i >= 14 else red
                inner.append((Vector((side * (0.30 + 1.15 * t), -0.15 - 0.45 * t, z)), rng.uniform(0.010, 0.016), hh, rng.uniform(0.5, 0.85), c))
        for j in range(4):
            inner.append((Vector((0.0, 0.35 + 0.16 * j, 2.62 - 0.10 * j)), 0.016 - 0.003 * j, 0.20 - 0.04 * j, 0.95, hot))
    elif kind == "scorpion":
        # плоский (поза) с поднятым жалом над корпусом и кольцом радиуса 4 м по полу (2 клетки карты по 2 м): «зона, где дальний прыжок режется»
        steps = 22
        for i in range(steps):
            t = i / (steps - 1.0)
            y = -0.3 - 0.9 * math.sin(math.pi * t) + 1.0 * t ** 3
            z = 0.9 + 2.2 * t
            tip = i >= steps - 4
            inner.append((Vector((rng.uniform(-0.01, 0.01), y, z)), 0.022 if tip else 0.014, 0.20 if tip else 0.10, 0.95 if tip else 0.75, hot if tip else red))
        for s in range(64):
            a = math.tau * s / 64.0
            pts.append(Vector((4.0 * math.cos(a), 4.0 * math.sin(a), 0.014)))
    elif kind == "lich":
        # маска-череп: овал из ярких штрихов вокруг головы с провалами глаз и носа; внутри корпуса мерцают «стираемые» символы (низкой яркости, шейдер даёт мерцание)
        for ci in range(9):
            x = -0.16 + 0.04 * ci
            eye = 0.05 < abs(x) < 0.13
            for z0, z1 in ((2.74, 2.92), (2.18, 2.48)):   # лоб и скулы с челюстью
                inner.append((Vector((x, 0.20 + 0.03 * abs(x) / 0.16, (z0 + z1) / 2)), 0.010, (z1 - z0) / 2, 0.95, ice))
            if not eye:   # переносица и межглазье цельные, глазницы пустые
                inner.append((Vector((x, 0.21, 2.62)), 0.010, 0.10, 0.9, ice))
        for _ in range(22):
            x, z = rng.uniform(-0.22, 0.22), rng.uniform(1.3, 2.1)
            inner.append((Vector((x, 0.0, z)), rng.uniform(0.006, 0.010), rng.uniform(0.04, 0.12), rng.uniform(0.3, 0.55), ice))
        for _ in range(26):
            a = rng.uniform(0, math.tau)
            r = rng.uniform(0.8, 1.0)
            pts.append(Vector((r * math.cos(a), 0.8 * r * math.sin(a), rng.uniform(1.6, 2.5))))
    else:
        raise ValueError(f"неизвестный вид Black ICE {kind}")


def _pose_kind(kind, shell, inner, pts):
    """Поза вида над общим силуэтом (до деталей вида): Гончая — низкая и вытянутая вперёд («бегущая»), Скорпион — плоский и широкий; остальные виды стоят как базовый.
    Сжатие по высоте, растяжение по +Y и наклон вперёд применяются к центрам штрихов и точек (высота штриха сжимается вместе с z). Правит списки на месте."""
    sq_z, st_y, lean = {"hound": (0.60, 1.55, 0.35), "scorpion": (0.52, 1.20, 0.0)}.get(kind, (1.0, 1.0, 0.0))
    if sq_z == 1.0 and st_y == 1.0:
        return

    def tf(v):
        z = v.z * sq_z
        return Vector((v.x * (1.25 if kind == "scorpion" else 1.0), v.y * st_y + lean * v.z * 0.5, z))

    shell[:] = [(tf(c), w, hh * sq_z, a, col) for c, w, hh, a, col in shell]
    inner[:] = [(tf(c), w, hh * sq_z, a, col) for c, w, hh, a, col in inner]
    pts[:] = [tf(p) for p in pts]


def build_black_ice(out, name="black_ice", seed=31, scale=2.0, state="idle", kind=""):
    """Black ICE (только узлы NIGHTMARE): человеческий силуэт ×2 (≈2,6 м, иглы до 3,4 м) из синих штрихов с повреждёнными данными.
    Оболочка синяя, внутри туловища и головы возникает красная форма (ядро ярче у головы). Повреждения: горизонтальные полосы, где штрихов
    нет (части пропадают), вырезанный кусок плеча, руки разной длины, смещённые вбок осколки точек, тонкие светящиеся трещины по телу.
    «Юбка» из красных штрихов вместо ног. Без лица. Не робот и не человек: то, что нарушает язык Сети. Origin «feet».
    Состояния (отдельные ассеты, скелета нет, переключает игра): idle — стоит, одна рука тянется; hunt — наклон вперёд, обе руки вперёд, красного больше;
    catch — красное почти вытеснило синее, руки разведены, вокруг красная завеса (поимка нетраннера)."""
    from avatar import _in_capsule, _in_ellipsoid, _in_torso
    lib.reset()
    cfg = BLACK_ICE_STATES[state]
    rng = random.Random(seed)
    blue, red, hot = lib.lin("blue"), lib.lin("threat"), lib.lin("threat_hot")
    k = scale
    bands = [(rng.uniform(1.0, 2.5), rng.uniform(0.06, 0.16)) for _ in range(cfg["bands"])]  # выше пояса: «юбка» и пояс целы
    cut = Vector((-0.17, 0.0, 1.02))  # вырезанный кусок левого плеча (в координатах до масштаба)

    def lost(p):
        if (p - cut).length < 0.14:
            return True
        return any(abs(p.z * k - z) < t / 2 and rng.random() < cfg["loss"] for z, t in bands)

    def leaned(p):  # наклон вперёд: чем выше точка, тем сильнее смещение по +Y (лицом к Blender +Y)
        return Vector((p.x, p.y + cfg["lean"] * 0.5 * (p.z / 1.3) ** 2, p.z))

    shell, inner, pts = [], [], []

    def dash(p, color, store, a=(0.3, 0.8), hh=(0.04, 0.12), w=(0.016, 0.03), glitch=True):
        p = leaned(p)
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
    for sx, long in ((-1, cfg["arms"][1]), (1, cfg["arms"][0])):
        sp = cfg["spread"]
        sh = (sx * 0.20, 0, 1.03)
        el = (sx * (0.24 + sp * 0.6), 0.05 + 0.15 * long, 0.78 - 0.1 * long)
        hd = (sx * (0.17 + sp), 0.30 + 0.62 * long, 0.86 - 0.2 * long)
        for _ in range(12):
            dash(_in_capsule(rng, sh, el, 0.04), blue, shell, a=(0.35, 0.8))
        for _ in range(12):
            dash(_in_capsule(rng, el, hd, 0.035), blue, shell, a=(0.35, 0.8))
        for _ in range(8):
            dash(_in_ellipsoid(rng, hd, (0.06, 0.06, 0.06)), red, inner, a=(0.6, 1.0), glitch=False)  # кисть уже красная
    for _ in range(cfg["red"]):  # красная форма внутри: туловище уже оболочки
        dash(_in_torso(rng) * 0.6 + Vector((0, 0, 0.35)), red, inner, a=(0.55, 1.0), hh=(0.03, 0.09), w=(0.012, 0.022), glitch=False)
    for _ in range(16):
        dash(_in_ellipsoid(rng, (0, 0.02, 1.31), (0.05, 0.06, 0.07)), hot, inner, a=(0.8, 1.0), hh=(0.02, 0.05), w=(0.012, 0.02), glitch=False)
    for _ in range(cfg["cracks"]):  # трещины: тонкие яркие вертикали поперёк тела, видно, что оно разбито изнутри
        x, z = rng.uniform(-0.28, 0.28), rng.uniform(0.9, 1.9)
        hh = rng.uniform(0.25, 0.6)
        q = leaned(Vector((x / k * 1.0, 0.02, z / k)))
        inner.append((Vector((q.x * k, q.y * k + 0.03, z)), 0.006, hh, 0.85, hot))
    for _ in range(30):  # «юбка» красных штрихов, выше и рваннее
        r = 0.20 * math.sqrt(rng.random())
        ang = rng.uniform(0, math.tau)
        top = rng.uniform(0.3, 0.8) * k
        inner.append((Vector((r * math.cos(ang) * k, 0.7 * r * math.sin(ang) * k, top / 2)), rng.uniform(0.012, 0.022), top / 2, rng.uniform(0.2, 0.6), red))
    for i in range(cfg["spikes"]):  # иглы над головой
        dx, hh = rng.uniform(-0.4, 0.4), rng.uniform(2.7, 3.4)
        inner.append((Vector((dx, 0.15 * cfg["lean"] * k + rng.uniform(-0.05, 0.05), hh / 2)), 0.011, hh / 2, 0.9, hot))
    for _ in range(cfg["veil"]):  # завеса поимки: красные штрихи кольцом вокруг фигуры, перекрывают её
        ang = rng.uniform(0, math.tau)
        r = rng.uniform(0.55, 0.95)
        hh = rng.uniform(0.5, 1.5)
        inner.append((Vector((r * math.cos(ang), 0.8 * r * math.sin(ang), hh / 2)), rng.uniform(0.012, 0.024), hh / 2, rng.uniform(0.25, 0.7), red))
    if kind:   # вид Black ICE: поза и деталь поверх общего силуэта (база не меняется)
        _pose_kind(kind, shell, inner, pts)
        _black_kind_extras(kind, seed, shell, inner, pts, blue, red, hot)
    objs = [lib.streak_set(f"{name}_shell", shell, blue), lib.streak_set(f"{name}_inner", inner, red)]
    dust = [(c + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.6))).normalized() * rng.uniform(0.05, 0.2)) for c in rng.sample([x[0] for x in shell], min(260, len(shell)))]
    dust = [Vector((p.x, p.y, max(p.z, 0.012))) for p in dust + pts]
    objs.append(lib.point_cloud(f"{name}_dust", dust, blue, half_size=0.011, seed=seed, a_min=0.2, a_max=0.7, on_floor=True))
    if state != "idle":  # состояния hunt и catch — запасные отдельные ассеты без клипов; клиент берёт black_ice.glb с тремя клипами
        return lib.export(name, "ice", objs, out, budget_tris=300, budget_points=600, budget_streaks=350, origin="feet",
                          notes=f"только NIGHTMARE; состояние {state}; лицом к Blender +Y (Godot −Z)")
    objs.append(lib.anchor("AlertAnchor", (0.0, 0.0, 3.5)))
    rig = lib.make_rig("Rig", objs)
    I, ONE = (0, 0, 0), (1, 1, 1)
    lib.add_clips(rig, {
        # idle: парит над полом, медленно покачивается
        "idle": (4.0, [(0, (0, 0, 0), I, ONE), (1.0, (0, 0, 0.08), (0, 2.5, 0), ONE), (2.0, (0, 0, 0.1), I, ONE), (3.0, (0, 0, 0.08), (0, -2.5, 0), ONE), (4.0, (0, 0, 0), I, ONE)]),
        # hunt: наклон вперёд, дрожит, частое покачивание (вперёд = +Y, поэтому rx отрицательный)
        "hunt": (1.2, [(0, (0, 0, 0), (-16, 0, 0), ONE), (0.3, (0, 0, 0.05), (-19, 0, 4), ONE), (0.6, (0, 0, 0), (-16, 0, 0), ONE),
                       (0.9, (0, 0, 0.05), (-19, 0, -4), ONE), (1.2, (0, 0, 0), (-16, 0, 0), ONE)]),
        # catch: сильный наклон, пульсирует и разрастается, раскачивается широко
        "catch": (0.8, [(0, (0, 0, 0), (-28, 0, 0), ONE), (0.2, (0, 0, 0.06), (-31, 0, 6), (1.1, 1.1, 1.1)), (0.4, (0, 0, 0), (-28, 0, 0), (1.18, 1.18, 1.18)),
                        (0.6, (0, 0, 0.06), (-31, 0, -6), (1.1, 1.1, 1.1)), (0.8, (0, 0, 0), (-28, 0, 0), ONE)]),
    })
    return lib.export(name, "ice", objs + [rig], out, budget_tris=300, budget_points=600, budget_streaks=350, origin="feet", animations=True,
                      notes="только NIGHTMARE; клипы idle, hunt, catch на корневом узле Rig; метка AlertAnchor; лицом к Blender +Y (Godot −Z)")


def build_black_lair(out, name="black_lair", seed=34):
    """Логово Black ICE (ice.md §6.1: «лежит в логове, 2×2 занятые клетки карты, видно от входа», клетка карты 2 м → 4×4 м; Game 14.10: «низкий холм или гнездо, во сне
    медленно пульсирует»): плита 4×4 м с красной кромкой, три кольца знаков, венец шипов по краю и узлы состояний: `State_sleep` (низкий холм красных штрихов, дышит —
    параметр шейдера `breathe`/пульс задаёт игра), `State_waking` (холм поднят до 1,4 м, штрихи горячие, над гнездом искры: игра растягивает его на 6 тактов пробуждения),
    `State_empty` (холм осыпался: пепел и потухшие знаки, Black ICE вышел). Включайте ровно один State_*. Спящий Black ICE ставится в якорь `Anchor_Sleeper`.
    Origin на полу в центре 4×4 м (2×2 клетки карты). Корпус сплошной (`/ice/` вне облака (А))."""
    lib.reset()
    rng = random.Random(seed)
    hot, red, void = lib.lin("threat_hot"), lib.lin("threat"), lib.lin("void")
    HALF = 2.0
    slab = lib.box_bm((4.0, 4.0, 0.10), bevel=0.03, center=(0, 0, 0.05))
    glow = lib.lit_part(slab, 0.10, 0.03)
    slab_obj = lib.obj_from_bm("black_lair_slab", slab, "solid_dark", hot, rgb_fn=lib.combine_rgb([glow], hot, void))
    signs = []
    for r, n in ((0.9, 40), (1.45, 64), (1.9, 88)):   # три кольца знаков на плите
        for i in range(n):
            a = math.tau * (i + rng.uniform(-0.3, 0.3)) / n
            signs.append(Vector((r * math.cos(a), r * math.sin(a), 0.11)))
    signs_obj = lib.point_cloud("black_lair_signs", signs, red, half_size=0.014, seed=seed, a_min=0.4, a_max=0.9)
    thorns = []
    for i in range(36):   # рваный венец: шипы по периметру разной высоты
        side = i % 4
        u = rng.uniform(-HALF + 0.1, HALF - 0.1)
        x, y = [(u, HALF - 0.05), (HALF - 0.05, u), (u, -HALF + 0.05), (-HALF + 0.05, u)][side]
        hh = rng.uniform(0.4, 0.95)   # П6-6 (в): было 0,25–0,6 — на П6 логово «не заметили» (в рост стоящего игрока шипы теперь выше колена и бёдер)
        thorns.append((Vector((x, y, 0.10 + hh)), rng.uniform(0.016, 0.03), hh, rng.uniform(0.5, 0.85), red))
    thorns_obj = lib.streak_set("black_lair_thorns", thorns, red)

    def _mound(n, r_max, h_lo, h_hi, a_lo, a_hi, color, name, rnd=rng, w_lo=0.016, w_hi=0.028):
        out_s = []
        for _ in range(n):
            a = rnd.uniform(0, math.tau)
            r = r_max * math.sqrt(rnd.random())
            hh = rnd.uniform(h_lo, h_hi) * (1.0 - 0.55 * r / r_max)   # к краю ниже: холм, а не стена
            out_s.append((Vector((r * math.cos(a), r * math.sin(a), 0.10 + hh)), rnd.uniform(w_lo, w_hi), hh, rnd.uniform(a_lo, a_hi), color))
        return lib.streak_set(name, out_s, color)

    # Спящий (П6-6 (в), владелец на П6 логова не заметил: «читается от входа — пульс, свой силуэт»): выше, гуще, ярче прежнего холма, а в середине — «сердце»:
    # пучок горячих штрихов выше холма (отдельный меш: шейдер даёт ему быстрый пульс, холму — медленный, AssetMaterials.apply). Отдельный датчик: остальные состояния не сдвигаются.
    srng = random.Random(seed + 7)
    sleep = _mound(110, 1.25, 0.25, 0.75, 0.5, 0.9, red, "black_lair_mound", rnd=srng, w_lo=0.02, w_hi=0.034)
    heart = _mound(14, 0.18, 1.0, 1.4, 0.8, 1.0, hot, "black_lair_heart", rnd=srng, w_lo=0.02, w_hi=0.03)
    waking = _mound(80, 1.2, 0.45, 1.4, 0.45, 0.9, hot, "black_lair_rise")
    embers = [Vector((rng.uniform(-1.3, 1.3), rng.uniform(-1.3, 1.3), 0.15 + rng.uniform(0.0, 1.6))) for _ in range(50)]
    embers_obj = lib.point_cloud("black_lair_embers", embers, hot, half_size=0.012, seed=seed + 1, a_min=0.5, a_max=1.0)
    ash = [Vector((rng.uniform(-1.1, 1.1), rng.uniform(-1.1, 1.1), 0.11)) for _ in range(40)]
    ash_obj = lib.point_cloud("black_lair_ash", ash, red, half_size=0.010, seed=seed + 2, a_min=0.15, a_max=0.4)
    groups = [lib.group("State_sleep", [sleep, heart]), lib.group("State_waking", [waking, embers_obj]), lib.group("State_empty", [ash_obj])]
    objs = [slab_obj, signs_obj, thorns_obj, sleep, heart, waking, embers_obj, ash_obj, *groups, lib.anchor("Anchor_Sleeper", (0, 0, 0.12))]
    return lib.export(name, "ice", objs, out, budget_tris=300, budget_points=360, budget_streaks=260, origin="floor", budget_draws=12,
                      notes="логово 4×4 м (2×2 клетки карты), State_sleep/waking/empty (ровно один), Anchor_Sleeper; красный по принципу 5")


if __name__ == "__main__":
    o = lib.args()
    build_soft_ice(o)
    for nm, st, sd in (("black_ice", "idle", 31), ("black_ice_hunt", "hunt", 32), ("black_ice_catch", "catch", 33)):
        build_black_ice(o, nm, sd, state=st)
    for kd in BLACK_KINDS:   # виды Black ICE: тот же силуэт (seed 31, idle) + деталь вида, три клипа как у базового
        build_black_ice(o, f"black_ice_{kd}", 31, state="idle", kind=kd)
    build_black_lair(o)

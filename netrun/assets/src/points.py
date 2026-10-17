"""Облако частиц объектов Сети (уровень (Б), docs/netrun-refactor-plan.md §4): `.points` рядом с `.glb`.

Чистый Python 3 без Blender: читает готовый `.glb` (positions, COLOR_0, индексы) и пишет `<модель>.points`.
Запуск: `python3 points.py --root <корень с models/>` (конвейер `pipeline.sh build` зовёт после сборки моделей и до validate);
`python3 points.py --check --root <корень>` — только проверка.

Формат (читает `VolumeCloud.parse`, netrun/client/volume_cloud.gd): little-endian float32 без заголовка, 7 чисел на точку
[x, y, z, полуразмер_м, фаза 0…1, вид (0 точка / 1 искра), вес 0…1] в координатах модели (Y вверх, как в Godot); порядок перемешан,
поэтому ЛОД = префикс массива остаётся равномерной выборкой. Размер файла кратен 28 байтам.

Почему не «площадь всех треугольников», как у `VolumeSampler` в клиенте (запасной путь, пока нет файла):
у моделей Сети свет несут не тела, а штрихи (квад = вертикальная линия) и точки (квад = центр), а ещё в файле лежат ореол/луч маяка
(`beacon_*`, квад 0,5 м), вуаль `*_skirt` и состояния, взаимно исключающие друг друга. Здесь каждый меш получает своё правило:
  surface — площадь треугольников, вес из цвета вершин (контур плиты светится, тело тёмное);
  line    — вертикальный штрих → отрезок между серединами коротких сторон квада, точки вдоль него;
  dot     — квад точки → одна частица в центре (круг по списку, повторы со сдвигом);
  dust    — равномерно в объёме бокса (данные «внутри» хранилища; состояние не важно).
Полуразмер задан на модуль: шард 13 см не должен получать частицы 2,4 см.
Детерминировано: seed = crc32(имя модуля), без `hash()` и времени. Бюджеты — RECIPES[...]["count"] (план: хранилище ≈ 1,5k, портал ≈ 0,8k, шард ≈ 0,3k).
"""
import fnmatch
import json
import math
import os
import random
import struct
import sys
import zlib

POINT_FLOATS = 7
POINT_BYTES = POINT_FLOATS * 4
SEED_BASE = 20261013
BODY_WEIGHT = 0.35        # вес «тела» без света (как VolumeSampler.BODY_WEIGHT): облако видно и там, где грань не светится
MAX_HALF = 0.05           # выше — это уже не частица (validate)
PAD = 0.03                # допуск габарита при проверке, м (сверх полуразмера)

# Правила по модулям. Ключ — путь модели без расширения относительно models/. parts: (шаблон имени меша, режим, доля).
# Доли нормируются; число частиц на часть = round(доля · count), остаток уходит в самую большую часть.
RECIPES = {
    "props/vault": {
        "count": 1500, "half": 0.012, "spark": 0.08,
        "parts": [
            ("vault_body", "surface", 0.25),          # лоток: контур верха светится (постамент — точки vault_base_pts, не ящик)
            ("vault_base_pts", "dot", 0.15),          # постамент облаком: точки по граням и рёбрам
            ("vault_streaks_hang", "line", 0.22),     # занавесы по граням
            ("vault_rim_pts", "dot", 0.13),           # точки обода
            ("dust", "dust", 0.25),                   # «данные внутри»: бокс клетки, общий для всех состояний
        ],
        # бокс клетки (closed_cage: x ±0,30, y 0,35…0,78, z ±0,28), чуть меньше, чтобы частицы не лежали на прутьях
        "dust_box": ((-0.27, 0.38, -0.25), (0.27, 0.74, 0.25)),
    },
    "props/portal": {
        "count": 800, "half": 0.016, "spark": 0.06,
        "parts": [
            ("portal_membrane_mid", "line", 0.55),    # мембрана: штрихи по хорде диска
            ("portal_rim", "dot", 0.45),              # обод
        ],
    },
    "props/shard": {
        "count": 300, "half": 0.004, "spark": 0.10,
        "parts": [
            ("shard_facets", "surface", 0.30),
            ("shard_edge_pts", "dot", 0.30),
            ("shard_core_shell*", "surface", 0.40),   # ядро: две вложенные оболочки
        ],
    },
    "props/shard_encrypted": {
        "count": 300, "half": 0.004, "spark": 0.10,
        "parts": [
            ("shard_facets", "surface", 0.25),
            ("shard_cage_pts", "dot", 0.35),
            ("shard_cage_bars", "line", 0.25),
            ("shard_glitch_pts", "dot", 0.15),
        ],
    },
    # Рамка выхода (бюджет плана ≈ 1k): брусья 14 см с яркой кромкой, столбы-занавесы штрихов, порог точками. Клиент exit_frame пока не ставит.
    "env/exit_frame": {
        "count": 1000, "half": 0.014, "spark": 0.08,
        "parts": [
            ("exit_bar_*", "surface", 0.42),
            ("exit_sill", "surface", 0.06),
            ("exit_post_*", "line", 0.32),
            ("exit_threshold", "dot", 0.20),
        ],
    },
    # ICE (голограмма: красное облако поверх модели; ICE двигается — точки в ЛОКАЛЬНЫХ координатах модели, ноги в (0,0), как у .glb:
    # клиент вешает облако потомком того же узла, что и модель (у Black ICE — внутри Rig), и оно идёт с ним). Бюджет ≈ 0,5–1k по поручению.
    "ice/soft_ice": {
        "count": 700, "half": 0.018, "spark": 0.10,
        "parts": [
            ("ice_body", "line", 0.50),     # плотное основание и рваный верх
            ("ice_core", "line", 0.20),     # раскалённое ядро и иглы
            ("ice_haze", "dot", 0.30),      # туман точек у пола
        ],
    },
}
RECIPES["ice/tracer_ice"] = {   # Трассировщик Soft ICE: низкое тело и гребень (хвост-плитки — Tail_1..4, не облако)
    "count": 500, "half": 0.014, "spark": 0.10,
    "parts": [
        ("tracer_ice_body", "surface", 0.60),   # корпус вместе с мордой
        ("tracer_ice_spine", "line", 0.40),
    ],
}
RECIPES["ice/black_lair"] = {   # логово Black ICE (4×4 м, 2×2 клетки карты): плита, знаки, шипы и холм СНА (пробуждение и «пусто» — без облака)
    "count": 1200, "half": 0.02, "spark": 0.08,
    "parts": [
        ("black_lair_slab", "surface", 0.30),
        ("black_lair_signs", "dot", 0.25),
        ("black_lair_thorns", "line", 0.15),
        ("black_lair_mound", "line", 0.30),
    ],
}
# базовый Black ICE, его запасные состояния и пять видов (ice.md §6.2): общий рецепт, имена мешей по имени модели
for _state in ("black_ice", "black_ice_hunt", "black_ice_catch") + tuple("black_ice_" + _k for _k in ("hound", "kraken", "raven", "scorpion", "lich")):
    RECIPES["ice/" + _state] = {
        "count": 900, "half": 0.02, "spark": 0.12,
        "parts": [
            (_state + "_shell", "line", 0.35),   # синяя оболочка силуэта
            (_state + "_inner", "line", 0.40),   # красная форма внутри (голова, трещины, «юбка»)
            (_state + "_dust", "dot", 0.25),     # осколки точек
        ],
    }
SKIP_MESHES = ("beacon_*", "*_skirt")   # ореол/луч маяка и вуаль: не объём, а подсветка (шаблон `skip` в части не нужен)


# ---------------------------------------------------------------- чтение .glb

_COMP = {5120: ("b", 1, 127.0), 5121: ("B", 1, 255.0), 5122: ("h", 2, 32767.0), 5123: ("H", 2, 65535.0), 5125: ("I", 4, 1.0), 5126: ("f", 4, 1.0)}


def _read(doc, blob, acc_index):
    """Значения accessor'а: список кортежей (нормализованные целые приведены к 0…1, как требует glTF)."""
    a = doc["accessors"][acc_index]
    bv = doc["bufferViews"][a["bufferView"]]
    fmt, size, scale = _COMP[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    stride = bv.get("byteStride") or size * n
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    norm = a.get("normalized", False) and a["componentType"] != 5126
    out = []
    for i in range(a["count"]):
        row = struct.unpack_from("<" + fmt * n, blob, base + i * stride)
        out.append(tuple(v / scale for v in row) if norm else row)
    return out


def load_glb(path):
    """[{name, material, pos, color, tris}] по примитивам; tris — тройки индексов в pos."""
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        raise ValueError(f"{path}: не glb")
    jl, _ = struct.unpack_from("<II", data, 12)
    doc = json.loads(data[20:20 + jl])
    off = 20 + jl
    bl, _ = struct.unpack_from("<II", data, off)
    blob = data[off + 8:off + 8 + bl]
    mats = doc.get("materials", [])
    prims = []
    for mesh in doc.get("meshes", []):
        for p in mesh["primitives"]:
            at = p["attributes"]
            pos = _read(doc, blob, at["POSITION"])
            col = _read(doc, blob, at["COLOR_0"]) if "COLOR_0" in at else [(1.0, 1.0, 1.0, 1.0)] * len(pos)
            if "indices" in p:
                idx = [v[0] for v in _read(doc, blob, p["indices"])]
            else:
                idx = list(range(len(pos)))
            prims.append({
                "name": mesh.get("name") or "",
                "material": mats[p["material"]]["name"] if "material" in p else "",
                "pos": pos,
                "color": [tuple(c) + (1.0,) * (4 - len(c)) for c in col],
                "tris": [(int(idx[i]), int(idx[i + 1]), int(idx[i + 2])) for i in range(0, len(idx) - 2, 3)],
            })
    return prims


def _matches(name, pattern):
    return fnmatch.fnmatchcase(name, pattern)


# ---------------------------------------------------------------- источники частиц

def _lum(prim, i):
    """Яркость вершины 0…1: у solid_dark свет несёт RGB (альфа до Godot не доходит), у остальных ролей — альфа (плотность)."""
    r, g, b, a = prim["color"][i]
    return max(r, g, b) if prim["material"] == "solid_dark" else a


def _weight(lum):
    return BODY_WEIGHT + (1.0 - BODY_WEIGHT) * min(max(lum, 0.0), 1.0)


def _lerp(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


class _Surface:
    def __init__(self, prims):
        self.tris = []   # (prim, i, j, k)
        self.cum = []
        total = 0.0
        for p in prims:
            for (i, j, k) in p["tris"]:
                a, b, c = p["pos"][i], p["pos"][j], p["pos"][k]
                u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
                v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
                cr = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
                total += 0.5 * math.sqrt(cr[0] ** 2 + cr[1] ** 2 + cr[2] ** 2)
                self.tris.append((p, i, j, k))
                self.cum.append(total)
        self.total = total

    def __bool__(self):
        return self.total > 0.0

    def draw(self, rng):
        lo, hi = 0, len(self.cum) - 1
        t = rng.random() * self.total
        while lo < hi:
            mid = (lo + hi) // 2
            if self.cum[mid] < t:
                lo = mid + 1
            else:
                hi = mid
        p, i, j, k = self.tris[lo]
        u, v = rng.random(), rng.random()
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        w0, w1, w2 = 1.0 - u - v, u, v
        a, b, c = p["pos"][i], p["pos"][j], p["pos"][k]
        pt = tuple(a[n] * w0 + b[n] * w1 + c[n] * w2 for n in range(3))
        lum = _lum(p, i) * w0 + _lum(p, j) * w1 + _lum(p, k) * w2
        return pt, _weight(lum)


def _quads(prims):
    """Группы по 4 вершины (так экспортирует streak_set/точки в lib.py)."""
    out = []
    for p in prims:
        for q in range(0, len(p["pos"]) - 3, 4):
            out.append((p, q))
    return out


class _Lines:
    def __init__(self, prims):
        self.items = []
        for p, q in _quads(prims):
            v = p["pos"][q:q + 4]
            # отрезок между серединами коротких сторон: соседние вершины (0-1, 2-3) или (0-3, 1-2) — берём пару пар с большей длиной оси
            m01, m23 = _lerp(v[0], v[1], 0.5), _lerp(v[2], v[3], 0.5)
            m03, m12 = _lerp(v[0], v[3], 0.5), _lerp(v[1], v[2], 0.5)
            d1 = sum((m01[n] - m23[n]) ** 2 for n in range(3))
            d2 = sum((m03[n] - m12[n]) ** 2 for n in range(3))
            a, b = (m01, m23) if d1 >= d2 else (m03, m12)
            lum = sum(_lum(p, q + n) for n in range(4)) / 4.0
            self.items.append((a, b, _weight(lum)))

    def __bool__(self):
        return bool(self.items)

    def draw(self, rng):
        a, b, w = self.items[rng.randrange(len(self.items))]
        return _lerp(a, b, rng.random()), w


class _Dots:
    def __init__(self, prims):
        self.items = []
        for p, q in _quads(prims):
            v = p["pos"][q:q + 4]
            c = tuple(sum(v[n][k] for n in range(4)) / 4.0 for k in range(3))
            r = max(max(abs(v[n][k] - c[k]) for k in range(3)) for n in range(4))
            lum = sum(_lum(p, q + n) for n in range(4)) / 4.0
            self.items.append((c, r, _weight(lum)))
        self._queue = []
        self._drawn = 0

    def __bool__(self):
        return bool(self.items)

    def draw(self, rng):
        # каждая точка модели один раз за круг; со второго круга — со сдвигом в пределах её квада, чтобы повторы не слипались
        if not self._queue:
            self._queue = list(range(len(self.items)))
            rng.shuffle(self._queue)
        c, r, w = self.items[self._queue.pop()]
        if self._drawn >= len(self.items):
            c = tuple(c[n] + rng.uniform(-r, r) for n in range(3))
        self._drawn += 1
        return c, w


class _Dust:
    def __init__(self, box):
        self.lo, self.hi = box

    def __bool__(self):
        return True

    def draw(self, rng):
        pt = tuple(rng.uniform(self.lo[n], self.hi[n]) for n in range(3))
        return pt, BODY_WEIGHT + 0.15   # пыль: чуть ярче тела, слабее светящейся кромки


def _source(mode, prims, recipe):
    if mode == "surface":
        return _Surface(prims)
    if mode == "line":
        return _Lines(prims)
    if mode == "dot":
        return _Dots(prims)
    if mode == "dust":
        return _Dust(recipe["dust_box"])
    raise ValueError(f"неизвестный режим {mode}")


# ---------------------------------------------------------------- сборка

def seed_for(module):
    return (zlib.crc32(module.encode("utf-8")) ^ SEED_BASE) & 0xFFFFFFFF


def quotas(recipe):
    """Число частиц на часть: round(доля·count), остаток — в самую большую часть. Сумма = count."""
    parts = recipe["parts"]
    total = sum(p[2] for p in parts)
    n = [int(round(recipe["count"] * p[2] / total)) for p in parts]
    n[max(range(len(n)), key=lambda i: n[i])] += recipe["count"] - sum(n)
    return n


def build_points(module, prims, recipe):
    """Список частиц [(x, y, z, half, phase, kind, weight)] в перемешанном порядке. Бросает ValueError, если у части нет источника."""
    rng = random.Random(seed_for(module))
    live = [p for p in prims if not any(_matches(p["name"], s) for s in SKIP_MESHES)]
    srcs = []
    for pattern, mode, _share in recipe["parts"]:
        sel = live if mode == "dust" else [p for p in live if _matches(p["name"], pattern)]
        if mode != "dust" and not sel:
            raise ValueError(f"{module}: нет меша «{pattern}» в модели")
        src = _source(mode, sel, recipe)
        if not src:
            raise ValueError(f"{module}: у «{pattern}» нет геометрии для режима {mode}")
        srcs.append(src)
    labels = []
    for k, n in enumerate(quotas(recipe)):
        labels += [k] * n
    rng.shuffle(labels)   # префикс любой длины — смесь частей в тех же пропорциях (ЛОД)
    out = []
    for k in labels:
        (x, y, z), w = srcs[k].draw(rng)
        kind = 1.0 if rng.random() < recipe["spark"] else 0.0
        out.append((x, y, z, recipe["half"], rng.random(), kind, min(max(w, 0.0), 1.0)))
    return out


def pack(points):
    return b"".join(struct.pack("<7f", *p) for p in points)


def unpack(data):
    if len(data) % POINT_BYTES:
        raise ValueError(f"размер {len(data)} не кратен {POINT_BYTES}")
    return [struct.unpack_from("<7f", data, i) for i in range(0, len(data), POINT_BYTES)]


# ---------------------------------------------------------------- проверка

def check(glb_path, points_path, recipe):
    """Список ошибок: размер кратен 28, число = бюджет, нет NaN, габарит модели (без маяка и вуали) + полуразмер + допуск, поля в диапазонах."""
    bad = []
    try:
        pts = unpack(open(points_path, "rb").read())
    except (OSError, ValueError) as e:
        return [str(e)]
    if len(pts) > recipe["count"]:
        bad.append(f"точек {len(pts)} > бюджета {recipe['count']}")
    if not pts:
        return bad + ["пустой файл"]
    prims = [p for p in load_glb(glb_path) if not any(_matches(p["name"], s) for s in SKIP_MESHES)]
    lo = [min(v[k] for p in prims for v in p["pos"]) for k in range(3)]
    hi = [max(v[k] for p in prims for v in p["pos"]) for k in range(3)]
    half = recipe["half"]
    oob = nan = badf = 0
    for (x, y, z, h, ph, kind, w) in pts:
        if any(math.isnan(v) or math.isinf(v) for v in (x, y, z, h, ph, kind, w)):
            nan += 1
            continue
        if not (0.0 < h <= MAX_HALF and 0.0 <= ph <= 1.0 and kind in (0.0, 1.0) and 0.0 <= w <= 1.0):
            badf += 1
        for v, l, u in ((x, lo[0], hi[0]), (y, lo[1], hi[1]), (z, lo[2], hi[2])):
            if v < l - half - PAD or v > u + half + PAD:
                oob += 1
                break
    if nan:
        bad.append(f"NaN/inf в {nan} точках")
    if badf:
        bad.append(f"поля вне диапазона в {badf} точках (полуразмер 0…{MAX_HALF}, фаза и вес 0…1, вид 0/1)")
    if oob:
        bad.append(f"{oob} точек вне габарита модели ({[round(v, 2) for v in lo]}…{[round(v, 2) for v in hi]}) + {half + PAD:g} м")
    return bad


def bounds(points):
    lo = [min(p[k] for p in points) for k in range(3)]
    hi = [max(p[k] for p in points) for k in range(3)]
    return lo, hi


# ---------------------------------------------------------------- запуск

def generate(root):
    """Пишет `.points` для модулей RECIPES, у которых есть `.glb`; возвращает [(модуль, путь, число точек)]."""
    done = []
    for module, recipe in RECIPES.items():
        glb = os.path.join(root, "models", module + ".glb")
        if not os.path.isfile(glb):
            continue
        pts = build_points(module, load_glb(glb), recipe)
        out = os.path.join(root, "models", module + ".points")
        with open(out, "wb") as f:
            f.write(pack(pts))
        done.append((module, out, len(pts)))
    return done


def main(argv):
    root = os.path.abspath(argv[argv.index("--root") + 1]) if "--root" in argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    root = os.path.abspath(root)
    if "--check" not in argv:
        for module, out, n in generate(root):
            print(f"POINTS {module}: {n} точек → {os.path.relpath(out, root)}")
    fails = 0
    for module, recipe in RECIPES.items():
        glb = os.path.join(root, "models", module + ".glb")
        pts = os.path.join(root, "models", module + ".points")
        if not os.path.isfile(glb):
            continue
        bad = ["нет файла .points"] if not os.path.isfile(pts) else check(glb, pts, recipe)
        fails += bool(bad)
        print(("FAIL " if bad else "ok   ") + module + ".points" + (" — " + "; ".join(bad) if bad else ""))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

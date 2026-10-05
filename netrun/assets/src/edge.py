"""Ассеты env/room_edge_<N>: кромка комнаты вместо стен — «пол кончается, за краем пустота». Один код, два размера:
`room_edge_8` (квадрат 8×8, как комната в просмотре) и `room_edge_16` (16×16 = NodeLayout.ROOM_MIN..ROOM_MAX в netrun/shared/node_layout.gd, граница телепорта).
Запуск: blender -b --python edge.py -- --out <корень netrun/assets>

Владелец убрал стены-занавесы («эквалайзер не то»), а без них не видно, где кончается комната (телепорт зажат в этот квадрат). Цепочку точек по
периметру он тоже убрал («точки с граней комнаты убери»): граница — два меша:
  * `edge_streaks_hang` — штрихи, свисающие ВНИЗ от кромки на 1–2,6 м (как подвесные штрихи плит: суффикс `_hang` даёт anchor = 1, длина плывёт от верха),
    шаг ≈ 13 см по горизонтали, в глубину — волна, групповые выступы и шум, ~10% пропусков, чуть смещены наружу: край читается как обрыв в данные;
  * `edge_mist` — НИЗКАЯ дымка (haze.gdshader по суффиксу `_mist`): лента-«клин» вдоль периметра, яркая у кромки на полу и гаснущая вверх и наружу
    до 0,5 м («до колена», решение владельца) на расстоянии 1,8 м за краем; внутрь комнаты — лишь 20 см у самого пола. Это не стена: глаза выше,
    штрихов вверх нет. Один слой, 192 треугольника.
Origin «edge» — центр квадрата на уровне пола (для комнаты узла — NodeLayout.ROOM_CENTER). Красного нет."""
import math
import os
import random
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

STREAK_PITCH = 0.13    # шаг подвесных штрихов, м: 8×8 → ≤ 260 штрихов, 16×16 → ≤ 500
HANG_MIN, HANG_MAX = 1.2, 2.6   # длина подвесных штрихов, м (с «горением» breathe до ×1,3 → не глубже 3,4 м)
MIST_SIDE_SEGS = 8     # сегментов дымки на сторону: 3 пояса × 4 × 8 × 2 = 192 треугольника (≤ 200)
# профиль дымки поперёк кромки: (смещение наружу от кромки, м; высота, м; плотность). Внутрь — 20 см у пола, наружу — клин до 0,5 м (колено)
MIST_PROFILE = ((-0.2, 0.0, 0.0), (0.0, 0.02, 1.0), (0.9, 0.22, 0.55), (1.8, 0.50, 0.0))
SKIP_TRIGGER = 0.055   # шанс начать пропуск; пропуск 1–3 подряд → ≈10% выпавших


def _side_points(half, side, t):
    """Точка на стороне side (0..3, против часовой от юго-западного угла) при параметре t 0…1, и внешняя нормаль стороны. Blender: x, y — пол, z — вверх."""
    s = 2 * half
    if side == 0:
        return Vector((-half + s * t, -half, 0)), Vector((0, -1, 0))
    if side == 1:
        return Vector((half, -half + s * t, 0)), Vector((1, 0, 0))
    if side == 2:
        return Vector((half - s * t, half, 0)), Vector((0, 1, 0))
    return Vector((-half, half - s * t, 0)), Vector((-1, 0, 0))


def _skipper(rng):
    """Пропуски: [True, …] — класть элемент; одиночные и по 2–3 подряд (STYLE.md, вариативность)."""
    gap = 0
    def take():
        nonlocal gap
        if gap > 0:
            gap -= 1
            return False
        if rng.random() < SKIP_TRIGGER:
            gap = rng.randint(0, 2)
            return False
        return True
    return take


def _hang_streaks(rng, half):
    take = _skipper(rng)
    ph = rng.uniform(0, 6.28)
    out = []
    for side in range(4):
        n = max(1, round(2 * half / STREAK_PITCH))
        for q in range(n):
            if not take():
                continue
            t = (q + 0.5 + rng.uniform(-0.3, 0.3)) / n
            p, nrm = _side_points(half, side, t)
            # в глубину (перпендикулярно кромке): плавная волна + групповые выступы соседних штрихов + шум, в основном чуть наружу
            off = 0.05 + 0.05 * math.sin(q * 0.37 + side * 2.1 + ph) + 0.04 * math.sin(q * 0.11 + ph) + rng.uniform(-0.03, 0.03)
            p += nrm * off
            wave = 0.5 + 0.5 * math.sin(q * 0.9 + side * 1.7 + ph) * math.sin(q * 0.23 + ph)
            ln = HANG_MIN + (HANG_MAX - HANG_MIN) * wave * rng.uniform(0.55, 1.0)
            p.z = -0.03 - ln / 2  # верх на 3 см ниже пола: ничего не выступает над поверхностью
            white = rng.random() < 0.35  # часть штрихов белее: без цепочки точек кромку держат они (кадр edge_view), на фоне плит и штрихов дальних пластов
            out.append((p, rng.uniform(0.013, 0.022), ln / 2, rng.uniform(0.85, 1.0), lib.lin("ice_white") if white else lib.lin("cyan")))
    return out


def _mist_rings(rng, half):
    """Кольца дымки по профилю MIST_PROFILE: квадраты со стороной, смещённой наружу на dx (углы совпадают с лучами из центра). Плотность
    плавно «гуляет» вдоль периметра (общая для всех колец), без случайных скачков между соседними вершинами."""
    ph = rng.uniform(0, 6.28)
    n = MIST_SIDE_SEGS
    k = []
    for i in range(4 * n):
        a = 2 * math.pi * i / (4 * n)
        k.append(max(0.5, min(1.0, 0.78 + 0.14 * math.sin(a * 3 + ph) + 0.1 * math.sin(a * 7 + 1.7 * ph))))
    rings = []
    for dx, y, d in MIST_PROFILE:
        s = half + dx
        ring = []
        for side in range(4):
            for j in range(n):
                p, _ = _side_points(s, side, j / n)
                p.z = y
                ring.append((p, d * k[side * n + j]))
        rings.append(ring)
    return rings


def build_room_edge(out, size, seed):
    half = size / 2.0
    name = f"room_edge_{size}"
    lib.reset()
    rng = random.Random(seed)
    cy = lib.lin("cyan")
    streaks = _hang_streaks(rng, half)
    mist = _mist_rings(rng, half)
    objs = [
        lib.streak_set("edge_streaks_hang", streaks, cy),
        lib.loop_band("edge_mist", mist, cy),
    ]
    budget_streaks = {8: 260, 16: 500}.get(size, int(size * 31.25))  # бюджет карточки; без пропусков по шагу 13 см вышло бы 246 и 492
    return lib.export(name, "env", objs, out, budget_tris=200, budget_points=0, origin="edge", budget_streaks=budget_streaks,
                      notes=f"кромка {size}×{size} м: подвесные штрихи 1–2,6 м и низкая дымка 0,5 м за краем; ставить в центр квадрата на уровне пола")


if __name__ == "__main__":
    o = lib.args()
    build_room_edge(o, 8, seed=101)
    build_room_edge(o, 16, seed=102)

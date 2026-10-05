"""Ассеты env/room_moat_<N>: «ров» вокруг плиты-пола комнаты — чёрная непрозрачная полоса-кольцо, которая перекрывает дальние пласты (`env/far_floor*`) в кольце за краем
комнаты и читается как канава/пропасть. Один код, два размера: `room_moat_8` (комната просмотра 8×8, край плиты ±4) и `room_moat_16` (16×16 = NodeLayout.ROOM_MIN..ROOM_MAX;
клиент ставит в ROOM_CENTER (0, 0, −6), как floor_slab_16 и room_edge_16).
Запуск: blender -b --python room_moat.py -- --out <корень netrun/assets>

Зачем (владелец 2026-10-05: «сделай ров вокруг комнаты»): без стен граница комнаты читалась слабо — сразу за краем плиты на том же уровне y ≈ 0 лежат дальние пласты и
выглядят продолжением пола. Теперь вид такой: яркий край плиты (контур cyan) — щель 0,35 м (через неё видны подвесные штрихи floor_slab и room_edge, стоящие на самом краю) —
чёрная полоса шириной 3 м — дальний мир за ней.
Геометрия: один меш `moat` (роль solid_dark, пишет глубину, свет несёт цвет вершин), 16 треугольников, плоское кольцо квадратного периметра на высоте MOAT_Y = −0,02 м
(на 1 см ниже верха плиты −0,01: нет z-fight). Внутренняя граница на GAP = 0,35 м от края плиты, внешняя ещё на WIDTH = 3 м дальше. По ВНЕШНЕМУ периметру — контур cyan
шириной 3 см (отдельные вершины у каждой грани: линия резкая, а не градиент); внутренняя кромка не обводится, чтобы рядом с краем плиты не было второй линии.
Точек, штрихов и прозрачности нет. Origin «moat» — центр квадрата на уровне пола (как «slab»/«edge»). Красного нет."""
import bmesh
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

MOAT_Y = -0.02   # высота крышки, м: на 1 см ниже верха плиты-пола (−0,01), иначе z-fight у щели
GAP = 0.35       # щель между краем плиты и рвом, м
WIDTH = 3.0      # ширина рва, м
RIM = 0.03       # ширина контура по внешнему периметру, м
RIM_GAIN = 1.0   # яркость контура относительно cyan (как у плиты-пола после 74e53ad)


def _ring_faces(bm, outer, inner, rgb):
    """Кольцо между квадратами с полустороной outer и inner: четыре трапеции (отдельные вершины у каждой, чтобы цвет не размывался между гранями кольца).
    Обход против часовой стрелки при взгляде сверху: нормаль вверх. Цвет вершин — rgb."""
    def corners(s):
        return [(-s, -s), (s, -s), (s, s), (-s, s)]
    co, ci = corners(outer), corners(inner)
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        pts = [co[i], co[j], ci[j], ci[i]]
        f = bm.faces.new([bm.verts.new(Vector((x, y, MOAT_Y))) for x, y in pts])
        faces.append((f, rgb))
    return faces


def build_room_moat(out, size):
    half = size / 2.0
    inner = half + GAP
    outer = inner + WIDTH
    lib.reset()
    cy = lib.lin("cyan")
    rim_rgb = tuple(c * RIM_GAIN for c in cy)
    dark = lib.lin("void")
    bm = bmesh.new()
    colored = _ring_faces(bm, outer, outer - RIM, rim_rgb) + _ring_faces(bm, outer - RIM, inner, dark)
    bm.normal_update()
    for f, _ in colored:
        if f.normal.z < 0:  # страховка от порядка обхода
            f.normal_flip()
    bm.normal_update()
    bm.verts.index_update()
    col = {}
    for f, c in colored:
        for v in f.verts:
            col[v.index] = c
    ob = lib.obj_from_bm("moat", bm, "solid_dark", dark, rgb_fn=None)
    # цвет по вершинам: obj_from_bm красит одним rgb, переписываем по индексам (to_mesh сохраняет порядок вершин)
    attr = ob.data.color_attributes.active_color
    for i in range(len(ob.data.vertices)):
        attr.data[i].color = (*col[i], 1.0)
    return lib.export(f"room_moat_{size}", "env", [ob], out, budget_tris=60, budget_points=0, origin="moat", budget_streaks=0,
                      notes=f"ров {size}×{size} м: чёрная непрозрачная полоса {WIDTH:g} м на y={MOAT_Y:g}, щель {GAP:g} м от края плиты, контур cyan по внешнему периметру; ставить в центр комнаты (как floor_slab_{size})")


if __name__ == "__main__":
    o = lib.args()
    build_room_moat(o, 8)
    build_room_moat(o, 16)

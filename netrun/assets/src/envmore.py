"""Группа env, дополнительные модули: ворота блокировки и платформа.
Запуск: blender -b --python envmore.py -- --out <корень netrun/assets>
B2c (13.10.2026): кольцо тоннеля, кабели и угол убраны вместе с модулями из одних штрихов и точек (клиент их не грузит, на очках они невидимы)."""
import os
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


GATE_X = (-0.40, -0.20, 0.0, 0.20, 0.40)  # прутья решётки по ширине проёма 1,04 м (как у exit_frame: косяки на ±0,52 м)
GATE_BAR = 0.09    # сечение прута, м: 9 см — читается с 6–8 м (штрих 1 см был бы меньше пикселя)
GATE_EDGE = 0.025  # светящаяся кромка по вертикальным рёбрам прута
GATE_H = 2.0       # высота закрытой решётки: как проём exit_frame
GATE_H_OPEN = 0.12  # втянутая решётка: пеньки у порога


def build_lockdown_gate(out, name="lockdown_gate", opened=False, seed=51):
    """Ворота блокировки (LOCKDOWN), ставятся на место проёма exit_frame (косяки и перемычку даёт он): пять непрозрачных прутьев 9 см (solid_dark) с яркой
    кромкой по вертикальным рёбрам — видимое тело вместо прежних красных штрихов, которые на очках не рисуются (streak_keep=0). Закрытые: высота 2 м,
    красная кромка (угроза: LOCKDOWN — единственное место, где красное в окружении разрешено). Открытые: те же прутья втянуты в пеньки 12 см,
    кромка бирюзовая, проход свободен. Origin на полу в центре, проход вдоль оси Z Godot. seed не используется (оставлен ради прежней сигнатуры)."""
    lib.reset()
    glow = lib.lin("cyan") if opened else lib.lin("threat")
    void = lib.lin("void")
    h = GATE_H_OPEN if opened else GATE_H
    half = GATE_BAR / 2
    bms = []
    for x in GATE_X:
        bm = lib.box_bm((GATE_BAR, GATE_BAR, h), center=(x, 0.0, h / 2))
        for ax in (0, 1):  # плоскости у вертикальных рёбер: полоска кромки GATE_EDGE по каждой из четырёх боковых граней
            for sgn in (-1, 1):
                co = [0.0, 0.0, 0.0]
                co[ax] = (x if ax == 0 else 0.0) + sgn * (half - GATE_EDGE)
                no = [0.0, 0.0, 0.0]
                no[ax] = 1.0
                bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=co, plane_no=no)
        lib.canon_faces(bm)
        bms.append(bm)

    def rgb(co):
        for x in GATE_X:
            if abs(co[0] - x) <= half + 1e-4:
                return glow if (abs(co[0] - x) > half - 1e-3 and abs(co[1]) > half - 1e-3) else void  # вертикальное ребро прута
        return void

    objs = [lib.obj_from_bm("gate_bars", lib.merge_bm(*bms), "solid_dark", glow, rgb_fn=rgb)]
    return lib.export(name, "env", objs, out, budget_tris=320, budget_points=0, budget_streaks=0, origin="floor",
                      notes=("закрыт: красные прутья 2 м" if not opened else "открыт: пеньки 12 см, бирюзовая кромка"))


def build_platform(out, name="platform", seed=91):
    """Платформа 2×2 м высотой 0,3 м (возвышение в комнате, например под кресло или хранилище): чёрный блок 1,9×1,9 с подсвеченным верхним контуром.
    Origin на полу в центре. В отличие от тайлов пола, платформа выступает в комнату намеренно (0,3 м).
    Чистка (15.10.2026): сетка точек на верхней грани и занавес штрихов по бокам убраны — у окружения с тиром штрихи и точки не рисуются
    (`streak_keep=0`, `point_keep=0`, решение владельца на очках П5), но спрятанные меши оставались в файле и в списке отрисовки; облако реквизита — на гранях блока (А)."""
    lib.reset()
    cy, void = lib.lin("cyan"), lib.lin("void")
    blk = lib.box_bm((1.9, 1.9, 0.3), center=(0, 0, 0.15))
    glow = lib.lit_part(blk, 0.3, 0.014)
    objs = [lib.obj_from_bm("platform_block", blk, "solid_dark", cy, rgb_fn=lib.combine_rgb([glow], cy, void))]
    return lib.export(name, "env", objs, out, budget_tris=300, budget_points=0, budget_streaks=0, origin="floor",
                      notes="высота 0,3 м, выступает в комнату намеренно; без штрихов и точек (чистка 15.10)")


if __name__ == "__main__":
    o = lib.args()
    build_lockdown_gate(o, "lockdown_gate", False)
    build_lockdown_gate(o, "lockdown_gate_open", True)
    build_platform(o)

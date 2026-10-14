"""Soft ICE узла: Маяк и Датчик (docs/gamedesign/ice.md §5, levels.md §9). Запуск: blender -b --python icegear.py -- --out <корень netrun/assets>

Маяк (`ice/lighthouse_ice`; не «beacon»: меши `beacon_*` у предметов — маячок читаемости шарда): тумба на одной клетке 1 м (origin на полу в центре клетки),
голова с линзой на узле `Head` (его поворачивает Godot: 45° за такт), под головой узел `Beam` с веером на полу (`lighthouse_fan`, единичный радиус 1 м, ±25° вокруг +Y Blender = −Z Godot, вершина веера на оси тумбы). Дальность
(5 клеток, +1 на тревоге 2+) — масштаб узла `Beam`: вершина веера в нуле, поэтому масштаб равномерный (0,0 — центр тумбы).

Датчик (`ice/sensor_ice`): ОДИН излучатель: низкая тумба 0,12×0,12×0,42 м, линза на высоте 0,30 м (ниже колена) лицом к +Y Blender (−Z Godot).
Пару ставит Godot: два экземпляра лицом друг к другу, на одном виден `Beam` (длина 1 м вдоль +Y; Godot масштабирует по Z Godot до 2–6 клеток).
В `Beam` три плоскости: `sensor_beam` (горизонтальная полоса на высоте линзы), `sensor_beam_v` (вертикальная — читается с любого угла) и `sensor_beam_floor` (слабая
полоса на полу: «тонкий луч на полу»). Состояния (горит / погашен / мигает) и вспышка — параметры шейдера `beam.gdshader` (`AssetMaterials.set_beam`),
цвета — слои `beam_on`, `beam_off`, `beam_flash`. Красный у ICE — по принципу 5; корпус светится кромкой верха, луч — `beam_on`.

Это не `props/sensor` (датчик узла: колонна с «глазом», старая комната): тот остаётся как есть.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

FAN_HALF_ANGLE = math.radians(25.0)   # ±25° (ice.md §5: Маяк — только фокус)
FAN_RINGS = (0.0, 0.34, 0.67, 1.0)    # радиусы колец веера (единичный)
FAN_STEPS = 6                          # сегментов по углу
FAN_Z = 0.03                           # веер лежит на 3 см над полом: не мерцает с плитой пола
BEAM_Z = 0.30                          # высота луча датчика (ниже колена сидящего/стоящего)


def _beam_object(name, verts, faces, uvs, alphas, rgb):
    """Меш луча: вершины, грани (индексы), UV0 по вершинам, альфа вершины = вес в шейдере. Роль shell_soft, имя меша выбирает beam.gdshader."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UV0")
    bv = [bm.verts.new(Vector(v)) for v in verts]
    for f in faces:
        face = bm.faces.new([bv[i] for i in f])
        for loop, i in zip(face.loops, f):
            loop[uv].uv = uvs[i]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(lib.material("shell_soft"))
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        attr.data[i].color = (*rgb, alphas[i])
    me.color_attributes.active_color = attr
    return ob


def _fan_object(name, rgb, z=FAN_Z):
    """Веер единичного радиуса вдоль +Y: u = радиус 0…1, v = угол 0…1 (края — 0 и 1). Вершина в (0, 0, z)."""
    verts, uvs, alphas, faces = [], [], [], []
    ring_idx = []
    for r in FAN_RINGS:
        idx = []
        for k in range(FAN_STEPS + 1):
            t = k / FAN_STEPS
            a = -FAN_HALF_ANGLE + 2.0 * FAN_HALF_ANGLE * t
            verts.append((r * math.sin(a), r * math.cos(a), z))
            uvs.append((r, t))
            alphas.append(1.0)
            idx.append(len(verts) - 1)
        ring_idx.append(idx)
    for k in range(FAN_STEPS):   # внутреннее кольцо — вершина: треугольники
        faces.append((ring_idx[0][k], ring_idx[1][k], ring_idx[1][k + 1]))
    for j in range(1, len(FAN_RINGS) - 1):
        for k in range(FAN_STEPS):
            a, b = ring_idx[j], ring_idx[j + 1]
            faces.append((a[k], b[k], b[k + 1]))
            faces.append((a[k], b[k + 1], a[k + 1]))
    return _beam_object(name, verts, faces, uvs, alphas, rgb)


def _ribbons_object(name, rgb, ribbons):
    """Несколько полос единичной длины вдоль +Y в ОДНОМ меше (один прозрачный слой): u = 0…1 вдоль луча, v = 0…1 поперёк.
    ribbons — [(полуширина, z, vertical, вес)]: horizontal в плоскости XY, vertical в плоскости YZ; вес идёт в альфу вершин (слабая полоса на полу)."""
    verts, faces, uvs, alphas = [], [], [], []
    for w, z, vertical, weight in ribbons:
        if vertical:
            pts = [(0, 0, z - w), (0, 0, z + w), (0, 1, z + w), (0, 1, z - w)]
        else:
            pts = [(-w, 0, z), (w, 0, z), (w, 1, z), (-w, 1, z)]
        i = len(verts)
        verts += pts
        uvs += [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
        alphas += [weight] * 4
        faces += [(i, i + 1, i + 2), (i, i + 2, i + 3)]
    return _beam_object(name, verts, faces, uvs, alphas, rgb)


def build_ice_lighthouse(out, name="lighthouse_ice", seed=61):
    """Маяк Soft ICE: тумба + голова с линзой (узел Head) + веер луча на полу (узел Beam под Head). Origin на полу в центре клетки."""
    lib.reset()
    hot, ice, void = lib.lin("threat_hot"), lib.lin("ice_white"), lib.lin("void")
    base = lib.cone_bm(0.30, 0.25, 0.52, segments=12, center=(0, 0, 0.26))
    glow_base = lib.lit_part(base, 0.52, 0.012, outer=lib.disc_glow(0.25))
    tower = lib.obj_from_bm("lighthouse_tower", base, "solid_dark", hot, rgb_fn=lib.combine_rgb([glow_base], hot, void))
    neck = lib.box_bm((0.10, 0.10, 0.16), bevel=0.006, center=(0, 0, 0.60))
    neck_obj = lib.obj_from_bm("lighthouse_neck", neck, "solid_dark", hot, rgb_fn=lambda co: void)
    head = lib.box_bm((0.24, 0.30, 0.16), bevel=0.01, center=(0, 0, 0.76))
    glow_head = lib.lit_part(head, 0.84, 0.010)
    head_obj = lib.obj_from_bm("lighthouse_head", head, "solid_dark", hot, rgb_fn=lib.combine_rgb([glow_head], hot, void))
    lens = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.07, 0.07, 0.07), center=(0, 0.16, 0.76))
    lens_objs = lib.shell_stack(lens, "lighthouse_lens", ice, layers=2, grow=0.35, a_inner=0.95, a_outer=0.25, pivot=(0, 0.16, 0.76))
    fan = _fan_object("lighthouse_fan", hot)
    beam = lib.group("Beam", [fan])
    head_node = lib.group("Head", [head_obj, neck_obj, *lens_objs, beam])
    objs = [tower, head_node, beam, head_obj, neck_obj, *lens_objs, fan]
    return lib.export(name, "ice", objs, out, budget_tris=300, budget_points=0, budget_streaks=0, origin="floor", budget_layers=3,
                      notes="узлы Head (поворачивает Godot) и Beam (масштаб = дальность, вершина веера на оси); луч — shader beam, слои beam_*")


def build_ice_sensor(out, name="sensor_ice", seed=62):
    """Излучатель датчика Soft ICE: низкая тумба с линзой на высоте 0,30 м лицом к +Y Blender, узел Beam с лучом единичной длины. Origin на полу."""
    lib.reset()
    hot, ice, void = lib.lin("threat_hot"), lib.lin("ice_white"), lib.lin("void")
    post = lib.box_bm((0.12, 0.12, 0.42), bevel=0.006, center=(0, 0, 0.21))
    glow_post = lib.lit_part(post, 0.42, 0.010)
    post_obj = lib.obj_from_bm("sensor_ice_post", post, "solid_dark", hot, rgb_fn=lib.combine_rgb([glow_post], hot, void))
    lens = lambda: lib.ico_bm(0.5, subdiv=1, scale=(0.05, 0.05, 0.05), center=(0, 0.08, BEAM_Z))
    lens_objs = lib.shell_stack(lens, "sensor_ice_lens", ice, layers=2, grow=0.4, a_inner=0.95, a_outer=0.25, pivot=(0, 0.08, BEAM_Z))
    # горизонтальная полоса на высоте линзы, вертикальная (читается с любого угла) и слабая полоса на полу — один меш, один прозрачный слой
    ribbons = _ribbons_object("sensor_ice_beam", hot, [(0.025, BEAM_Z, False, 1.0), (0.025, BEAM_Z, True, 1.0), (0.09, 0.02, False, 0.35)])
    beam = lib.group("Beam", [ribbons])
    objs = [post_obj, beam, *lens_objs, ribbons]
    return lib.export(name, "ice", objs, out, budget_tris=200, budget_points=0, budget_streaks=0, origin="floor", budget_layers=3,
                      notes="узел Beam: длина 1 м вдоль +Y Blender (−Z Godot), Godot масштабирует по длине; состояния — beam.gdshader (state, flash)")


if __name__ == "__main__":
    o = lib.args()
    build_ice_lighthouse(o)
    build_ice_sensor(o)

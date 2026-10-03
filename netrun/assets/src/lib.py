"""Общая библиотека сборки 3D-ассетов «Сети» (Blender 4.x, запуск без интерфейса).

    blender -b --python netrun/assets/src/<скрипт>.py -- --out <корень netrun/assets>

Стиль и бюджеты — `netrun/assets/STYLE.md`. Здесь только механика: палитра в одном месте, примитивы с фасками,
оболочки (объём), облако точек, экспорт `.glb`, отчёт для `validate.py`.

Контракт с Godot (шейдеры в `netrun/assets/shaders/`, подмена по имени материала):
  * материал каждого меша называется ролью: `glow_edge` (светящиеся рёбра), `shell_soft` (мягкая оболочка),
    `points` (облако точек), `solid_dark` (тёмная основа);
  * цвет вершин COLOR_0 = RGB цвет свечения, A = плотность/яркость;
  * `points`: каждая точка — квадрат в плоскости XZ Blender (в Godot — XY) с центром c и полуразмером h. UV0 углов
    квадрата (0..1), UV1.x = h. Вершинный шейдер Godot восстанавливает центр c = VERTEX - ((UV0-0.5)*2*h в XY) и разворачивает
    квадрат к камере.
Ось Z Blender смотрит вверх, экспорт переводит в Y вверх; 1 единица = 1 м.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS_ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import glbinfo  # noqa: E402

# ---------------------------------------------------------------- палитра (sRGB hex → линейный RGB, как ждёт glTF)

HEX = {
    "void": "#02050a",
    "cyan": "#18e6ff",        # тир BASE, окружение
    "blue": "#2a7bff",        # тир HARD
    "violet": "#8a5cff",      # тир NIGHTMARE
    "ice_white": "#d9f8ff",   # самые яркие рёбра
    "threat": "#ff1f3d",      # люди, ИИ, ICE — только они красные
    "threat_hot": "#ff7a6b",
    "amber": "#ff7a1a",       # экран деки
}
TIERS = {"BASE": "cyan", "HARD": "blue", "NIGHTMARE": "violet"}
ROLES = ("glow_edge", "shell_soft", "points", "solid_dark")


def lin(name):
    h = HEX[name].lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


# ---------------------------------------------------------------- сцена, материалы

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(role):
    """Один материал на роль; настоящий вид задаёт шейдер Godot, здесь — запасной вариант для просмотра в Blender."""
    assert role in ROLES, role
    m = bpy.data.materials.get(role)
    if m is None:
        m = bpy.data.materials.new(role)
        m.use_nodes = True
        node = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        node.inputs["Base Color"].default_value = (0.01, 0.02, 0.03, 1.0)
    return m


# ---------------------------------------------------------------- примитивы (bmesh, без bpy.ops: работает без контекста)

def _scale_move(bm, scale=(1, 1, 1), offset=(0, 0, 0)):
    off = Vector(offset)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + off
    return bm


def box_bm(size, bevel=0.0, center=(0, 0, 0)):
    """Параллелепипед size=(x,y,z); bevel — фаска (киберпанк: прямых углов нет)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    _scale_move(bm, size, center)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES")
    return bm


def ico_bm(radius, subdiv=1, scale=(1, 1, 1), center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    return _scale_move(bm, scale, center)


def cone_bm(r_bottom, r_top, depth, segments=8, center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=depth)
    return _scale_move(bm, (1, 1, 1), center)


def merge_bm(*parts):
    """Склеить несколько bmesh в один (источники освобождаются)."""
    out = bmesh.new()
    for src in parts:
        vmap = {v: out.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            out.faces.new([vmap[v] for v in f.verts])
        src.free()
    return out


def obj_from_bm(name, bm, role, rgb, alpha=1.0, alpha_fn=None, smooth=False):
    """Объект из bmesh: роль материала + цвет вершин (RGB свечения, A плотность). alpha_fn(co) — градиент по вершинам."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material(role))
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        attr.data[i].color = (*rgb, alpha_fn(v.co) if alpha_fn else alpha)
    me.color_attributes.active_color = attr
    return ob


# ---------------------------------------------------------------- объём: вложенные оболочки

def shell_stack(make_bm, name, rgb, layers=3, grow=0.06, a_inner=0.55, a_outer=0.12, pivot=(0, 0, 0)):
    """Объект как 2–3 вложенные оболочки (аддитивный Френель в Godot): внутри плотнее, снаружи прозрачнее.
    Грани сглажены: резкого края нет. Возвращает список объектов (материал shell_soft)."""
    out = []
    pv = Vector(pivot)
    for k in range(layers):
        bm = make_bm()
        s = 1.0 + k * grow
        for v in bm.verts:
            v.co = pv + (v.co - pv) * s
        t = k / max(layers - 1, 1)
        out.append(obj_from_bm(f"{name}_shell{k}", bm, "shell_soft", rgb, alpha=a_inner + (a_outer - a_inner) * t, smooth=True))
    return out


# ---------------------------------------------------------------- облако точек

def sample_surface(bm, count, seed=1, push=0.0):
    """Случайные точки на поверхности (по площади треугольников), сдвинутые наружу по нормали на случайное [0, push]."""
    rng = random.Random(seed)
    tmp = bm.copy()
    bmesh.ops.triangulate(tmp, faces=tmp.faces)
    tmp.normal_update()
    tris = [(f.calc_area(), [v.co.copy() for v in f.verts], f.normal.copy()) for f in tmp.faces]
    tmp.free()
    total = sum(t[0] for t in tris)
    pts = []
    for _ in range(count):
        r = rng.random() * total
        acc = 0.0
        for area, vs, n in tris:
            acc += area
            if acc >= r:
                break
        a, b = rng.random(), rng.random()
        if a + b > 1:
            a, b = 1 - a, 1 - b
        p = vs[0] + (vs[1] - vs[0]) * a + (vs[2] - vs[0]) * b
        pts.append(p + n * (rng.random() * push))
    return pts


def point_cloud(name, points, rgb, half_size=0.01, seed=1, a_min=0.4, a_max=1.0):
    """Облако из квадратиков (материал points); контракт — в докстринге модуля."""
    rng = random.Random(seed)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UV0")
    uv1 = bm.loops.layers.uv.new("UV1")
    cols = []
    h = half_size
    for c in points:
        vs = [bm.verts.new(c + Vector(d)) for d in ((-h, 0, -h), (h, 0, -h), (h, 0, h), (-h, 0, h))]
        f = bm.faces.new(vs)
        for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv0].uv = uv
            loop[uv1].uv = (h, 0)
        a = a_min + (a_max - a_min) * rng.random()
        cols.append(a)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material("points"))
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        attr.data[i].color = (*rgb, cols[i // 4])
    me.color_attributes.active_color = attr
    return ob


# ---------------------------------------------------------------- экспорт и отчёт

def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = ASSETS_ROOT
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    return out


def export(name, group, objs, out_root, budget_tris, budget_points=0, origin="floor", animations=False, notes=""):
    """Записать models/<group>/<name>.glb и reports/<name>.json (числа берём из самого .glb)."""
    path = os.path.join(out_root, "models", group, f"{name}.glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_cameras=False, export_lights=False, export_animations=animations,
    )
    info = glbinfo.parse(path)
    s = glbinfo.summary(info)
    report = {
        "name": name, "group": group, "file": f"models/{group}/{name}.glb", "origin": origin,
        "budget_tris": budget_tris, "budget_points": budget_points, **s,
        "size": info["size"], "bbox_min": info["bbox_min"], "bbox_max": info["bbox_max"],
        "materials": info["materials"], "animations": info["animations"],
        "moved_nodes": info["moved_nodes"], "notes": notes,
    }
    rp = os.path.join(out_root, "reports", f"{name}.json")
    os.makedirs(os.path.dirname(rp), exist_ok=True)
    json.dump(report, open(rp, "w"), ensure_ascii=False, indent=1)
    print("EXPORT", json.dumps({k: report[k] for k in ("name", "tris", "points", "layers", "size")}, ensure_ascii=False))
    return report

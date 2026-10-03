"""Превью PNG ассетов «Сети» (Workbench, без GPU-свечения): для приёмки формы, размеров и фасок.

    blender -b -P netrun/assets/src/preview.py -- env|props|assembly [имя ...]

Берёт готовые .glb из models/ (то есть проверяет и сам экспорт), кладёт PNG в previews/<группа>/.
Серый столбик слева — высота глаз сидящего (1,2 м), планка на полу — 1 м. Тёмные тела в превью осветлены (иначе формы
не читаются), неон показан цветом без свечения.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bl_common as bc  # noqa: E402
import palette  # noqa: E402

PREVIEWS = os.path.join(bc.ASSETS, "previews")
ENV_ORDER = ["floor", "wall", "corner", "pillar", "doorway", "platform", "lockdown_gate", "cable_straight", "cable_curve", "tunnel_ring"]


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_object_outline = True
    sc.display.shading.show_cavity = False
    sc.display.render_aa = "8"
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.render.dither_intensity = 0.0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.compression = 100
    w = bpy.data.worlds.new("w")
    w.color = (0.045, 0.05, 0.06)
    sc.world = w
    return sc


def place(path, loc=(0, 0, 0), rot_y=0.0):
    """Импортировать .glb и поставить в точку (координаты Godot, поворот вокруг Y в градусах)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    m = Matrix.Translation(bc.to_blender(loc)) @ Matrix.Rotation(math.radians(rot_y), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = m @ o.matrix_world
    for o in new:
        for slot in o.material_slots:
            mat = slot.material
            if mat is None or mat.get("pv"):
                continue
            bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            col = list(bsdf.inputs["Base Color"].default_value) if bsdf else list(mat.diffuse_color)
            if bsdf and bsdf.inputs["Emission Strength"].default_value < 0.01:  # тело — осветлить для превью
                col = [min(1.0, c * 3.2 + 0.035) for c in col[:3]] + [1.0]
            mat.diffuse_color = col
            mat["pv"] = 1
    return new


def add_ref(x, z):
    """Эталоны масштаба: столбик 1,2 м (глаза сидящего) и планка 1 м по полу."""
    gray = bc.make_material("ref", "#8A9B98")
    p = bc.Part("ref", [gray])
    p.box((x, 0.6, z), (0.04, 1.2, 0.04), 0)
    p.box((x, 1.22, z), (0.12, 0.04, 0.12), 0)
    p.box((x + 0.5, 0.01, z), (1.0, 0.02, 0.05), 0)
    return p.build()


def add_ground(sc, size=40):
    gm = bc.make_material("ground", "#2A3138")
    p = bc.Part("ground", [gm])
    p.box((0, -0.16, 0), (size, 0.1, size), 0)
    return p.build()


def render(sc, objs, path, width=720, height=520, az=32, el=24, margin=1.12):
    bpy.context.view_layer.update()
    meshes = [o for o in objs if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (lo + hi) / 2
    # направление взгляда в осях Godot -> Blender: вид сверху-спереди-справа
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e)))  # Godot
    d = Vector((d.x, -d.z, d.y))
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = center + d * 30
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    right, up = cam.matrix_world.col[0].xyz, cam.matrix_world.col[1].xyz
    w = max(p.dot(right) for p in pts) - min(p.dot(right) for p in pts)
    h = max(p.dot(up) for p in pts) - min(p.dot(up) for p in pts)
    aspect = width / height
    cam_data.ortho_scale = max(w, h * aspect) * margin
    cam_data.clip_end = 200
    # смещение, чтобы центр габарита был в центре кадра
    mid = Vector(((max(p.dot(right) for p in pts) + min(p.dot(right) for p in pts)) / 2,
                  (max(p.dot(up) for p in pts) + min(p.dot(up) for p in pts)) / 2, 0))
    cam.location += right * (mid.x - center.dot(right)) + up * (mid.y - center.dot(up))
    sc.render.resolution_x, sc.render.resolution_y = width, height
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("[PREVIEW]", os.path.relpath(path, bc.ASSETS))


def glb(group, name):
    return os.path.join(bc.MODELS, group, name + ".glb")


def preview_env(names):
    for name in names:
        sc = fresh()
        objs, step = [], None
        for k, (tier, spec) in enumerate(palette.TIERS.items()):
            new = place(glb("env", name + spec["suffix"]), (0, 0, 0))
            meshes = [o for o in new if o.type == "MESH"]
            if step is None:
                step = max(max(o.dimensions.x, o.dimensions.z) for o in meshes) + 0.9
            for o in new:
                if o.parent is None:
                    o.location.x += k * step
            objs += meshes
        add_ground(sc)
        ref = add_ref(-1.6, 1.5)
        render(sc, objs + [ref], os.path.join(PREVIEWS, "env", name + ".png"), 1100, 560, 28, 26, 1.1)


VIEW_AZ = {"seat": 215, "sensor": 28}  # кресло смотрим спереди (-Z); остальное — лицом (+Z)


def add_ref_small(x, z):
    """Для мелких предметов: планка 10 см на полу вместо столбика."""
    gray = bc.make_material("ref", "#8A9B98")
    p = bc.Part("ref", [gray])
    p.box((x, 0.004, z), (0.1, 0.008, 0.012), 0)
    return p.build()


def preview_props(names):
    for name in names:
        sc = fresh()
        new = place(glb("props", name))
        meshes = [o for o in new if o.type == "MESH"]
        big = max(max(o.dimensions) for o in meshes) >= 0.8
        add_ground(sc)
        half = max(o.dimensions.x for o in meshes) / 2
        ref = add_ref(-0.9 - half, 0.4) if big else add_ref_small(-0.05 - half, 0.0)
        render(sc, meshes + [ref], os.path.join(PREVIEWS, "props", name + ".png"), 720, 560, VIEW_AZ.get(name, 32), 22, 1.15)


def preview_assembly():
    """Собранный уголок узла: проверка стыков сетки и соотношения размеров."""
    sc = fresh()
    objs = []

    def put(group, name, loc, rot=0.0):
        path = glb(group, name)
        if os.path.exists(path):
            objs.extend(place(path, loc, rot))

    for cx in (-3, -1, 1, 3):
        for cz in (-3, -1, 1, 3):
            put("env", "floor", (cx, 0, cz))
    # северный ряд (z=-3): угол, ворота, проём, угол; стена ряда на крае z=-4
    put("env", "corner", (-3, 0, -3))
    put("env", "lockdown_gate", (-1, 0, -3))
    put("env", "doorway", (1, 0, -3))
    put("env", "corner", (3, 0, -3), 270)
    for cz in (-1, 1):
        put("env", "wall", (-3, 0, cz), 90)
        put("env", "wall", (3, 0, cz), 270)
    put("env", "pillar", (-1, 0, -1))
    put("env", "platform", (1, 0, -1))
    put("env", "cable_straight", (-1, 0, 1))
    put("env", "cable_curve", (1, 0, 1))
    for i, z in enumerate((-5, -7, -9)):
        put("env", "tunnel_ring", (1, 0, z))
    # предметы
    put("props", "vault_closed", (-3.35, 0, -0.3), 90)
    put("props", "shard", (-3.35, 1.0, -0.3))
    put("props", "portal", (2.6, 0, 2.6))
    put("props", "seat", (-1.3, 0, 1.0))
    put("props", "sensor", (2.5, 0, -2.5))
    put("props", "dead_deck", (-0.5, 0.035, -1.9), 20)
    meshes = [o for o in objs if o.type == "MESH"]
    add_ground(sc)
    ref = add_ref(0.2, 1.9)
    render(sc, meshes + [ref], os.path.join(PREVIEWS, "assembly.png"), 1400, 900, 22, 36, 1.04)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    what, names = (argv[0] if argv else "env"), argv[1:]
    if what == "env":
        preview_env(names or ENV_ORDER)
    elif what == "props":
        if not names:
            names = sorted(f[:-4] for f in os.listdir(os.path.join(bc.MODELS, "props")) if f.endswith(".glb"))
        preview_props(names)
    elif what == "assembly":
        preview_assembly()


if __name__ == "__main__":
    main()

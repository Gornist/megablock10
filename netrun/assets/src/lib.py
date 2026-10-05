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
from mathutils import Euler, Vector

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
ROLES = ("glow_edge", "shell_soft", "points", "streaks", "solid_dark")


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


def xform_bm(bm, rot=(0, 0, 0), scale=(1, 1, 1), offset=(0, 0, 0)):
    """Масштаб → поворот (градусы, Euler XYZ: сначала вокруг X, потом Y, потом Z) → смещение."""
    m = Euler([math.radians(a) for a in rot]).to_matrix()
    off = Vector(offset)
    for v in bm.verts:
        v.co = m @ Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + off
    return bm


def band_bm(radius, height, segments=12, center=(0, 0, 0)):
    """Открытое кольцо-«обечайка» без крышек (ось Z): контур ринга, края видны с обеих сторон."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=segments, radius1=radius, radius2=radius, depth=height)
    return _scale_move(bm, (1, 1, 1), center)


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


def lit_part(bm, top_z, thickness=0.012, outer=None):
    """Чёрная деталь с подсвеченным верхним контуром (как тайлы пола): боковые грани режутся на thickness ниже верха, верхняя грань получает
    рамку шириной thickness (inset). Возвращает предикат вершины «светится»: внешний контур верхней грани (вершины верхней плоскости до inset,
    поэтому работает и с фаской). outer(co) — своё условие вместо этого (например, для цилиндра)."""
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, 0, top_z - thickness), plane_no=(0, 0, 1))
    bm.normal_update()
    rim = {(round(v.co.x, 5), round(v.co.y, 5)) for v in bm.verts if abs(v.co.z - top_z) < 1e-4}
    top = [f for f in bm.faces if f.normal.z > 0.9 and abs(f.calc_center_median().z - top_z) < 1e-4]
    bmesh.ops.inset_individual(bm, faces=top, thickness=thickness)

    def glow(co):
        if abs(co.z - top_z) > 1e-4:
            return False
        if outer is not None:
            return outer(co)
        return (round(co.x, 5), round(co.y, 5)) in rim

    return glow


def disc_glow(radius):
    """Предикат внешнего контура круглой детали (для lit_part(outer=...))."""
    return lambda co: abs(math.hypot(co.x, co.y) - radius) < 1e-3


def combine_rgb(preds, glow, dark):
    """rgb_fn для obj_from_bm: glow на вершинах, где сработал любой предикат, иначе dark."""
    return lambda co: glow if any(p(co) for p in preds) else dark


def obj_from_bm(name, bm, role, rgb, alpha=1.0, alpha_fn=None, smooth=False, rgb_fn=None):
    """Объект из bmesh: роль материала + цвет вершин (RGB свечения, A плотность). alpha_fn(co) — градиент по вершинам; rgb_fn(co) — цвет по вершинам
    (альфа цвета вершин до Godot у непрозрачных материалов не доходит, поэтому метку света у solid_dark несёт RGB)."""
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
        attr.data[i].color = (*(rgb_fn(v.co) if rgb_fn else rgb), alpha_fn(v.co) if alpha_fn else alpha)
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

def sample_surface(bm, count, seed=1, push=0.0, min_z=None):
    """Случайные точки на поверхности (по площади треугольников), сдвинутые наружу по нормали на случайное [0, push].
    min_z — нижняя граница высоты (для предметов на полу: ниже пола точки не уходят)."""
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
        p = p + n * (rng.random() * push)
        if min_z is not None:
            p.z = max(p.z, min_z)
        pts.append(p)
    return pts


def sample_line(a, b, per_meter, spread=0.01, seed=1, min_z=None):
    """Грань как цепочка частиц: точки вдоль отрезка a→b (равномерно с шумом), небольшой разброс поперёк.
    Сплошных реек в ассетах нет (STYLE.md): линия = плотность точек."""
    rng = random.Random(seed)
    a, b = Vector(a), Vector(b)
    n = max(2, int((b - a).length * per_meter))
    out = []
    for i in range(n):
        p = a + (b - a) * ((i + rng.random()) / n) + Vector((rng.gauss(0, spread), rng.gauss(0, spread), rng.gauss(0, spread)))
        if min_z is not None:
            p.z = max(p.z, min_z)
        out.append(p)
    return out


def sample_lines(segments, per_meter, spread=0.01, seed=1, min_z=None):
    """Несколько отрезков [(a, b), ...] одним списком точек."""
    out = []
    for i, (a, b) in enumerate(segments):
        out += sample_line(a, b, per_meter, spread, seed + i, min_z)
    return out


def sample_box(center, size, count, seed=1, min_z=None):
    """Случайные точки внутри параллелепипеда (объёмная «пыль»), не на поверхности."""
    rng = random.Random(seed)
    c = Vector(center)
    out = []
    for _ in range(count):
        p = c + Vector(((rng.random() - 0.5) * size[0], (rng.random() - 0.5) * size[1], (rng.random() - 0.5) * size[2]))
        if min_z is not None:
            p.z = max(p.z, min_z)
        out.append(p)
    return out


def point_cloud(name, points, rgb, half_size=0.01, seed=1, a_min=0.4, a_max=1.0, on_floor=False):
    """Облако из квадратиков (материал points); контракт — в докстринге модуля."""
    rng = random.Random(seed)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UV0")
    uv1 = bm.loops.layers.uv.new("UV1")
    cols = []
    h = half_size
    for c in points:
        c = Vector(c)
        if on_floor:  # квадрат не уходит ниже пола: центр не ниже полуразмера
            c.z = max(c.z, half_size)
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


def skirt_set(name, quads, rgb):
    """«Вуаль» на боковой грани плиты: вертикальный квад (2 треугольника), яркий у кромки и гаснущий книзу. Роль материала shell_soft
    (в Godot имя меша `*_skirt` подменяет шейдер на skirt.gdshader: аддитивный, без записи глубины, без освещения). quads —
    [(верхний левый, верхний правый, вектор вниз, плотность слева, плотность справа)], плотность — альфа вершин вверху, внизу 0.
    UV: u вдоль кромки 0…1, v вдоль высоты (после экспорта glTF в шейдере UV.y = 0 вверху, 1 внизу)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UV0")
    dens = []  # плотность по вершинам: по четыре на квад в порядке создания (to_mesh сохраняет порядок)
    for a, b, down, da, db in quads:
        a, b, down = Vector(a), Vector(b), Vector(down)
        f = bm.faces.new([bm.verts.new(p) for p in (a, b, b + down, a + down)])
        for loop, t in zip(f.loops, ((0, 1), (1, 1), (1, 0), (0, 0))):
            loop[uv].uv = t
        dens += [da, db, 0.0, 0.0]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material("shell_soft"))
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        attr.data[i].color = (*rgb, dens[i])
    me.color_attributes.active_color = attr
    return ob


def streak_set(name, streaks, rgb):
    """Штрихи — основной примитив (STYLE.md): [(центр Vector, полуширина, полувысота, яркость)]. Один квадрат на штрих, в плоскости XZ.
    Для штриха от пола: центр.z = полувысота. UV0 — углы, UV1 = (w, 1-h): экспортёр glTF переворачивает V у всех развёрток, в файле
    получится (w, h), то есть в шейдере UV2 = (полуширина, полувысота)."""
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UV0")
    uv1 = bm.loops.layers.uv.new("UV1")
    cols = []
    rgbs = []
    for st in streaks:
        c, w, h, a = st[:4]
        rgbs.append(st[4] if len(st) > 4 else rgb)  # необязательный свой цвет штриха (голова и кисти аватара горячее тела)
        c = Vector(c)
        vs = [bm.verts.new(c + Vector(d)) for d in ((-w, 0, -h), (w, 0, -h), (w, 0, h), (-w, 0, h))]
        f = bm.faces.new(vs)
        for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv0].uv = uv
            loop[uv1].uv = (w, 1.0 - h)
        cols.append(a)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material("streaks"))
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        attr.data[i].color = (*rgbs[i // 4], cols[i // 4])
    me.color_attributes.active_color = attr
    return ob


def make_rig(name, children):
    """Пустой корневой узел для клипов: все меши и якоря становятся его дочерними (родитель без смещения, трансформации у всех нулевые)."""
    rig = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(rig)
    for c in children:
        c.parent = rig
    return rig


def add_clips(rig, clips, fps=30):
    """Клипы на корневом узле rig (покачивание, наклон, дыхание всего тела; движение штрихов делает шейдер). clips = {имя: (длительность_с, ключи)},
    ключ = (время_с, (x, y, z) смещение, (rx, ry, rz) градусы, (sx, sy, sz) масштаб). Первый и последний ключ клипа должны совпадать: клип зациклен.
    Каждый клип кладётся на свою NLA-дорожку с тем же именем (так glTF-экспорт делает из него отдельную анимацию; режим NLA_TRACKS в export)."""
    rig.animation_data_create()
    for name, (length, keys) in clips.items():
        act = bpy.data.actions.new(name)
        rig.animation_data.action = act
        for t, loc, rot, scl in keys:
            f = 1 + round(t * fps)
            rig.location = loc
            rig.rotation_euler = tuple(math.radians(a) for a in rot)
            rig.scale = scl
            rig.keyframe_insert("location", frame=f)
            rig.keyframe_insert("rotation_euler", frame=f)
            rig.keyframe_insert("scale", frame=f)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, act)
        rig.animation_data.action = None
    rig.location, rig.rotation_euler, rig.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)


def anchor(name, loc):
    """Якорь: пустой узел в точке loc (Blender, Z вверх), экспортируется как Node3D с этим именем («Anchor_Shard» и т. п.). Игра ставит
    в него предметы и эффекты; в проверках размера и атрибутов не участвует."""
    ob = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(ob)
    ob.location = Vector(loc)
    return ob


# ---------------------------------------------------------------- экспорт и отчёт

def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = ASSETS_ROOT
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    return out


def export(name, group, objs, out_root, budget_tris, budget_points=0, origin="floor", animations=False, notes="", budget_streaks=0):
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
        **({"export_animation_mode": "NLA_TRACKS"} if animations else {}),
    )
    info = glbinfo.parse(path)
    s = glbinfo.summary(info)
    report = {
        "name": name, "group": group, "file": f"models/{group}/{name}.glb", "origin": origin,
        "budget_tris": budget_tris, "budget_points": budget_points, "budget_streaks": budget_streaks, **s,
        "size": info["size"], "bbox_min": info["bbox_min"], "bbox_max": info["bbox_max"],
        "materials": info["materials"], "animations": info["animations"],
        "moved_nodes": info["moved_nodes"], "notes": notes,
    }
    rp = os.path.join(out_root, "reports", f"{name}.json")
    os.makedirs(os.path.dirname(rp), exist_ok=True)
    json.dump(report, open(rp, "w"), ensure_ascii=False, indent=1)
    print("EXPORT", json.dumps({k: report[k] for k in ("name", "tris", "points", "streaks", "layers", "size")}, ensure_ascii=False))
    return report

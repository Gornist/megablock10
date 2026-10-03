"""Общее для скриптов Blender: геометрия, материалы, экспорт .glb. Запуск — только внутри Blender (`blender -b -P скрипт.py`).

Модель строится в осях Godot: X вправо, Y вверх, Z к зрителю (лицо предмета смотрит в +Z, игрок смотрит вдоль -Z).
При записи в mesh координаты переводятся в оси Blender (x, -z, y) — это чистый поворот, обход граней сохраняется,
а экспортёр glTF (Y вверх) возвращает те же числа. Единицы — метры, масштаб 1, трансформации запечены в вершины.
"""
import math
import os
import sys
from contextlib import contextmanager

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette  # noqa: E402

ASSETS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ASSETS, "models")
EPS = 0.006  # на столько декаль-неон приподнят над поверхностью (z-fighting на мобильном рендерере)

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def to_blender(v):
    v = Vector(v)
    return Vector((v.x, -v.z, v.y))


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, base_hex, neon=False, strength=0.0, rough=0.7, metal=0.0):
    """Один плоский материал. Неон: base_color и emission одного цвета (в просмотрщиках без свечения он не чёрный)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    r, g, b = palette.linear(base_hex)
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if neon:
        bsdf.inputs["Emission Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    mat.diffuse_color = (r, g, b, 1.0)
    mat.use_backface_culling = True
    return mat


def body_material(name, body_hex):
    return make_material(name, body_hex, rough=0.8, metal=0.25)


def neon_material(name, neon_hex, strength):
    return make_material(name, neon_hex, neon=True, strength=strength, rough=0.5)


def basis_for(normal):
    """Пара перпендикулярных единичных векторов (u, v) в плоскости с нормалью normal."""
    n = Vector(normal).normalized()
    ref = X if abs(n.dot(Y)) > 0.9 else Y
    u = (ref - n * ref.dot(n)).normalized()
    v = n.cross(u)
    return u, v


def _newell(pts):
    n = Vector((0, 0, 0))
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n.x += (p.y - q.y) * (p.z + q.z)
        n.y += (p.z - q.z) * (p.x + q.x)
        n.z += (p.x - q.x) * (p.y + q.y)
    return n


def _centroid(pts):
    c = Vector((0, 0, 0))
    for p in pts:
        c += p
    return c / len(pts)


class Part:
    """Один объект Blender (mesh): bmesh в осях Godot + список материалов (индекс материала у граней)."""

    def __init__(self, name, mats):
        self.name = name
        self.mats = list(mats)
        self.bm = bmesh.new()
        self.T = Matrix.Identity(4)
        self._stack = []
        self._gid = 0
        self._weld = {}

    # --- система координат ---------------------------------------------------------------------------------------
    @contextmanager
    def frame(self, T):
        """Всё внутри блока создаётся в локальных координатах T (поворот на любой угол, перенос)."""
        self._stack.append(self.T)
        self.T = self.T @ T
        try:
            yield self
        finally:
            self.T = self._stack.pop()

    def _p(self, p):
        return self.T @ Vector(p)

    # --- грани ---------------------------------------------------------------------------------------------------
    def _vert(self, gid, co):
        key = (gid, round(co.x, 5), round(co.y, 5), round(co.z, 5))
        v = self._weld.get(key)
        if v is None:
            v = self.bm.verts.new(co)
            self._weld[key] = v
        return v

    def _face(self, gid, pts, mat, hint):
        """Грань по точкам (в локальных координатах); обход выбирается так, чтобы нормаль смотрела вдоль hint."""
        P = [self._p(p) for p in pts]
        n = _newell(P)
        h = self.T.to_3x3() @ Vector(hint)
        if n.dot(h) < 0:
            P.reverse()
        verts = [self._vert(gid, p) for p in P]
        f = self.bm.faces.new(verts)
        f.material_index = mat
        f.smooth = False
        return f

    def _next_gid(self):
        self._gid += 1
        return self._gid

    # --- примитивы -----------------------------------------------------------------------------------------------
    def box(self, center, size, mat, bevel=0.0, edges="all"):
        """Параллелепипед; bevel — фаска (м), edges: 'all' или набор через '+': top, bot, vert."""
        bm = self.bm
        c, s = Vector(center), Vector(size)
        verts = bmesh.ops.create_cube(bm, size=1.0)["verts"]
        for v in verts:
            v.co = Vector((v.co.x * s.x + c.x, v.co.y * s.y + c.y, v.co.z * s.z + c.z))
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mat
            f.smooth = False
        sel = []
        if bevel > 0 and edges != "none":
            want = set(edges.split("+"))
            ytop, ybot = c.y + s.y / 2, c.y - s.y / 2
            for e in {e for v in verts for e in v.link_edges}:
                a, b = e.verts[0].co, e.verts[1].co
                vert = abs(a.y - b.y) > 1e-6
                top = abs(a.y - ytop) < 1e-6 and abs(b.y - ytop) < 1e-6
                bot = abs(a.y - ybot) < 1e-6 and abs(b.y - ybot) < 1e-6
                if "all" in want or (vert and "vert" in want) or (top and "top" in want) or (bot and "bot" in want):
                    sel.append(e)
        for v in verts:
            v.co = self._p(v.co)
        if sel:
            bmesh.ops.bevel(bm, geom=sel, offset=bevel, offset_type="OFFSET", segments=1, profile=0.5, affect="EDGES")

    def frustum(self, cx, cz, y0, y1, r0, r1, n, mat, rot=0.0, caps="both"):
        """Усечённый конус/призма вокруг оси Y (n сторон, вершины на радиусе r). r1=0 — остриё. caps: both/bot/top/none."""
        gid = self._next_gid()
        ang = [rot + 2 * math.pi * k / n for k in range(n)]
        bot = [Vector((cx + r0 * math.cos(a), y0, cz + r0 * math.sin(a))) for a in ang]
        top = [Vector((cx + r1 * math.cos(a), y1, cz + r1 * math.sin(a))) for a in ang]
        mid = Vector((cx, (y0 + y1) / 2, cz))
        for k in range(n):
            k2 = (k + 1) % n
            pts = [bot[k], bot[k2], top[k2], top[k]] if r1 > 1e-9 else [bot[k], bot[k2], top[0]]
            self._face(gid, pts, mat, _centroid(pts) - mid)
        if caps in ("both", "bot"):
            self._face(gid, bot, mat, -Y)
        if caps in ("both", "top") and r1 > 1e-9:
            self._face(gid, top, mat, Y)

    def loft(self, rings, mat, caps=True):
        """Поверхность между кольцами точек одинаковой длины (трубы, арки). mat — число или f(индекс_секции)."""
        gid = self._next_gid()
        rings = [[Vector(p) for p in r] for r in rings]
        n = len(rings[0])
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            mid = (_centroid(a) + _centroid(b)) / 2
            m = mat(i) if callable(mat) else mat
            for k in range(n):
                k2 = (k + 1) % n
                pts = [a[k], a[k2], b[k2], b[k]]
                self._face(gid, pts, m, _centroid(pts) - mid)
        if caps:
            m0 = mat(0) if callable(mat) else mat
            m1 = mat(len(rings) - 2) if callable(mat) else mat
            self._face(gid, rings[0], m0, _centroid(rings[0]) - _centroid(rings[1]))
            self._face(gid, rings[-1], m1, _centroid(rings[-1]) - _centroid(rings[-2]))

    def annulus_prism(self, cy, r_in, r_out, n, z0, z1, mat, rot=0.0):
        """Кольцо-призма вдоль Z (тоннель): n-угольник, внутренняя и внешняя стены и торцы. Радиусы — по вершинам."""
        gid = self._next_gid()
        ang = [rot + 2 * math.pi * k / n for k in range(n)]
        c0, c1 = Vector((0, cy, z0)), Vector((0, cy, z1))

        def ring(r, z):
            return [Vector((r * math.cos(a), cy + r * math.sin(a), z)) for a in ang]

        i0, i1, o0, o1 = ring(r_in, z0), ring(r_in, z1), ring(r_out, z0), ring(r_out, z1)
        axis = Vector((0, cy, (z0 + z1) / 2))
        for k in range(n):
            k2 = (k + 1) % n
            q = [i0[k], i0[k2], i1[k2], i1[k]]
            self._face(gid, q, mat, axis - _centroid(q))
            q = [o0[k], o0[k2], o1[k2], o1[k]]
            self._face(gid, q, mat, _centroid(q) - axis)
            self._face(gid, [i0[k], i0[k2], o0[k2], o0[k]], mat, -Z)
            self._face(gid, [i1[k], i1[k2], o1[k2], o1[k]], mat, Z)

    # --- неоновые декали (плоские грани над поверхностью) ---------------------------------------------------------
    def poly(self, pts, normal, mat):
        n = Vector(normal).normalized()
        self._face(self._next_gid(), [Vector(p) + n * EPS for p in pts], mat, n)

    def strip(self, center, length, width, u, normal, mat, tip=None):
        """Вытянутый шестиугольник (полоса со скошенными концами). u — направление длины, normal — куда смотрит."""
        n, u = Vector(normal).normalized(), Vector(u).normalized()
        v = n.cross(u)
        c = Vector(center)
        tip = width / 2 if tip is None else tip
        h, w = length / 2, width / 2
        pts = [c - u * h, c - u * (h - tip) + v * w, c + u * (h - tip) + v * w,
               c + u * h, c + u * (h - tip) - v * w, c - u * (h - tip) - v * w]
        self.poly(pts, n, mat)

    def disc(self, center, r, n, normal, mat, rot=0.0):
        u, v = basis_for(normal)
        c = Vector(center)
        pts = [c + (u * math.cos(rot + 2 * math.pi * k / n) + v * math.sin(rot + 2 * math.pi * k / n)) * r for k in range(n)]
        self.poly(pts, normal, mat)

    def ring(self, center, r_in, r_out, n, normal, mat, rot=0.0):
        """Плоское кольцо-декаль (n-угольник с вершинами на радиусах)."""
        u, v = basis_for(normal)
        c = Vector(center) + Vector(normal).normalized() * EPS
        gid = self._next_gid()
        nn = Vector(normal).normalized()

        def pt(r, k):
            a = rot + 2 * math.pi * k / n
            return c + (u * math.cos(a) + v * math.sin(a)) * r

        for k in range(n):
            k2 = (k + 1) % n
            self._face(gid, [pt(r_in, k), pt(r_in, k2), pt(r_out, k2), pt(r_out, k)], mat, nn)

    # --- сборка ---------------------------------------------------------------------------------------------------
    def _validate(self):
        """Замкнутые оболочки обязаны смотреть наружу (объём > 0); открытые — декали — пропускаются."""
        bm = self.bm
        seen, bad = set(), []
        for f0 in bm.faces:
            if f0.index in seen:
                continue
            comp, stack = [], [f0]
            seen.add(f0.index)
            while stack:
                f = stack.pop()
                comp.append(f)
                for e in f.edges:
                    for g in e.link_faces:
                        if g.index not in seen:
                            seen.add(g.index)
                            stack.append(g)
            if all(len(e.link_faces) == 2 for f in comp for e in f.edges):
                vol = 0.0
                for f in comp:
                    vs = [v.co for v in f.verts]
                    for i in range(1, len(vs) - 1):
                        vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
                if vol < 0:
                    bad.append(len(comp))
        if bad:
            raise RuntimeError("%s: вывернутые оболочки (граней: %s)" % (self.name, bad))

    def build(self):
        bm = self.bm
        bm.faces.index_update()
        bm.verts.index_update()
        self._validate()
        for v in bm.verts:
            v.co = to_blender(v.co)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def empty(name, loc):
    """Метка (Node3D в Godot): точка крепления шарда, якорь глаз и т. п. Координаты Godot."""
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = "PLAIN_AXES"
    o.empty_display_size = 0.1
    o.location = to_blender(loc)
    bpy.context.scene.collection.objects.link(o)
    return o


def tri_count(obj):
    if obj.type != "MESH":
        return 0
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_glb(path, objs):
    """Записать объекты в .glb: без камер, света, анимаций, текстур; материалы как есть."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_extras=False,
        export_image_format="NONE",
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_vertex_color="NONE",
        export_attributes=False,
        export_unused_images=False,
        export_unused_textures=False,
    )
    tris = sum(tri_count(o) for o in objs)
    print("[ASSET] %s  треугольников: %d" % (os.path.relpath(path, MODELS), tris))
    return tris

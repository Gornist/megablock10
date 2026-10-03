#!/usr/bin/env python3
"""Собирает сцену приёмки netrun/assets/preview.tscn (все ассеты набора) и сцену-снимок preview_shot.tscn. Чистый Python.

    python3 netrun/assets/src/make_preview_scene.py

Сцена — текст .tscn: ассеты — экземпляры .glb, ничего не запекается. Состав:
  Assembly   собранный угол узла 12x10 м (env BASE) с props, двумя ICE, двумя аватарами, декой на подставке и жетонами в слотах
  Lineup     ряд существ на земле: Black ICE в клипах idle/hunt/catch, Soft ICE в idle/patrol, аватары (клипы — метаданные anim / anim_t)
  Tiers      все модули env в трёх тирах (BASE, HARD, NIGHTMARE)
  TokenShelf все восемь жетонов демонов на полке
  Cameras    CamOverview, CamCreatures, CamDeck, CamTokens, CamTiers — их снимает preview_shot.gd
Скрипт preview.gd запускает клипы существ, preview_shot.gd (сцена preview_shot.tscn) сохраняет кадры каждой камеры в previews/.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.dirname(HERE)

ENV = ["floor", "wall", "corner", "pillar", "doorway", "platform", "lockdown_gate", "cable_straight", "cable_curve", "tunnel_ring"]
TIERS = [("", "BASE"), ("_hard", "HARD"), ("_nightmare", "NIGHTMARE")]
EFFECTS = ["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]
# слоты деки (build_deck.py): центры жетонов
SLOT_X = [-0.068, -0.034, 0.0, 0.034, 0.068]
SLOT_Y, SLOT_Z = 0.094, 0.065
DECK_IN_SLOTS = ["EXTRACT_SHARD", "GHOST", "JITTER", "DECRYPT", "MINER"]


def f(v):
    return ("%.5f" % v).rstrip("0").rstrip(".") if v else "0"


def basis_rows(cols):
    (xx, xy, xz), (yx, yy, yz), (zx, zy, zz) = cols
    return [xx, yx, zx, xy, yy, zy, xz, yz, zz]


def xform(pos, rot_y=0.0, rot_x=0.0):
    """Transform3D: сначала поворот вокруг X, затем вокруг Y (градусы), потом перенос. Строки базиса — как пишет Godot."""
    ax, ay = math.radians(rot_x), math.radians(rot_y)
    cx, sx, cy, sy = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    m = [[sum(ry[i][k] * rx[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return "Transform3D(%s, %s)" % (", ".join(f(v) for r in m for v in r), ", ".join(f(v) for v in pos))


def rot_apply(v, rot_y=0.0, rot_x=0.0):
    """Вектор v после поворота xform(rot_y, rot_x): сначала вокруг X, затем вокруг Y."""
    ax, ay = math.radians(rot_x), math.radians(rot_y)
    x, y, z = v
    y, z = y * math.cos(ax) - z * math.sin(ax), y * math.sin(ax) + z * math.cos(ax)
    x, z = x * math.cos(ay) + z * math.sin(ay), -x * math.sin(ay) + z * math.cos(ay)
    return (x, y, z)


def look_at(pos, target):
    px, py, pz = pos
    z = [px - target[0], py - target[1], pz - target[2]]
    n = math.sqrt(sum(c * c for c in z))
    z = [c / n for c in z]
    up = [0, 1, 0]
    x = [up[1] * z[2] - up[2] * z[1], up[2] * z[0] - up[0] * z[2], up[0] * z[1] - up[1] * z[0]]
    n = math.sqrt(sum(c * c for c in x))
    x = [c / n for c in x]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    return "Transform3D(%s, %s)" % (", ".join(f(v) for v in basis_rows([x, y, z])), ", ".join(f(v) for v in pos))


class Scene:
    def __init__(self):
        self.ext, self.subs, self.nodes = {}, [], []

    def res(self, path, kind="PackedScene"):
        if path not in self.ext:
            self.ext[path] = (len(self.ext) + 1, kind)
        return self.ext[path][0]

    def model(self, group, name):
        return self.res("res://assets/models/%s/%s.glb" % (group, name))

    def sub(self, kind, props):
        sid = "%s_%d" % (kind, len(self.subs) + 1)
        self.subs.append((sid, kind, props))
        return sid

    def node(self, name, parent, kind=None, instance=None, transform=None, props=(), meta=None, groups=None):
        head = '[node name="%s"' % name
        if kind:
            head += ' type="%s"' % kind
        if parent is not None:
            head += ' parent="%s"' % parent
        if instance is not None:
            head += " instance=ExtResource(\"%d\")" % instance
        if groups:
            head += " groups=[%s]" % ", ".join('"%s"' % g for g in groups)
        head += "]"
        body = []
        if transform:
            body.append("transform = " + transform)
        body += list(props)
        for k, v in (meta or {}).items():
            body.append("metadata/%s = %s" % (k, v))
        self.nodes.append(head + ("\n" + "\n".join(body) if body else ""))

    def inst(self, parent, name, group, asset, pos, rot_y=0.0, rot_x=0.0, anim=None, anim_t=0.0):
        meta, groups = None, None
        if anim:
            meta, groups = {"anim": '"%s"' % anim, "anim_t": f(anim_t)}, ["creature"]
        self.node(name, parent, instance=self.model(group, asset), transform=xform(pos, rot_y, rot_x), meta=meta, groups=groups)

    def text(self):
        out = ["[gd_scene format=3]", ""]
        for path, (i, kind) in self.ext.items():
            out.append('[ext_resource type="%s" path="%s" id="%d"]' % (kind, path, i))
        out.append("")
        for sid, kind, props in self.subs:
            out.append('[sub_resource type="%s" id="%s"]' % (kind, sid))
            out += props
            out.append("")
        out.append("\n\n".join(self.nodes))
        return "\n".join(out) + "\n"


DECK_POS, DECK_ROT_Y, DECK_ROT_X = (-5.0, 0.62, 1.0), 25, 55


def deck_view(dist, angle_deg):
    """Камера над декой, отклонённая от нормали экрана к локтю (так на деку смотрит игрок): (позиция, цель).
    Центр деки в её осях — (0; 0,06; 0,145), локоть — +Z."""
    c = rot_apply((0, 0.06, 0.145), DECK_ROT_Y, DECK_ROT_X)
    n = rot_apply((0, 1, 0), DECK_ROT_Y, DECK_ROT_X)
    back = rot_apply((0, 0, 1), DECK_ROT_Y, DECK_ROT_X)
    a = math.radians(angle_deg)
    tgt = tuple(DECK_POS[i] + c[i] for i in range(3))
    return tuple(tgt[i] + (n[i] * math.cos(a) + back[i] * math.sin(a)) * dist for i in range(3)), tgt


def build_preview():
    s = Scene()
    script = s.res("res://assets/preview.gd", "Script")
    envr = s.sub("Environment", ["background_mode = 1", "background_color = Color(0.02, 0.024, 0.03, 1)", "ambient_light_source = 2",
                                 "ambient_light_color = Color(0.62, 0.7, 0.74, 1)", "ambient_light_energy = 0.5", "tonemap_mode = 0"])
    gmat = s.sub("StandardMaterial3D", ["shading_mode = 0", "albedo_color = Color(0.03, 0.036, 0.045, 1)"])
    plane = s.sub("PlaneMesh", ["material = SubResource(\"%s\")" % gmat, "size = Vector2(160, 160)"])
    shelf_mat = s.sub("StandardMaterial3D", ["albedo_color = Color(0.1, 0.12, 0.14, 1)", "roughness = 1.0"])
    shelf = s.sub("BoxMesh", ["material = SubResource(\"%s\")" % shelf_mat, "size = Vector3(0.46, 0.02, 0.07)"])
    s.node("Preview", None, "Node3D", props=["script = ExtResource(\"%d\")" % script])
    s.node("WorldEnvironment", ".", "WorldEnvironment", props=['environment = SubResource("%s")' % envr])
    s.node("Sun", ".", "DirectionalLight3D", transform=xform((0, 8, 0), 25, -52), props=["light_energy = 0.55"])
    s.node("Fill", ".", "DirectionalLight3D", transform=xform((0, 8, 0), 205, -30), props=["light_energy = 0.25"])
    s.node("Ground", ".", "MeshInstance3D", transform=xform((0, -0.15, 0)), props=['mesh = SubResource("%s")' % plane])

    # --- собранный угол узла ---------------------------------------------------------------------------------------
    s.node("Assembly", ".", "Node3D")
    n = 0
    for cx in (-5, -3, -1, 1, 3, 5):
        for cz in (-3, -1, 1, 3, 5):
            s.inst("Assembly", "Floor%d" % n, "env", "floor", (cx, 0, cz))
            n += 1
    for name, pos, rot in (("CornerNW", (-3, 0, -3), 0), ("Gate", (-1, 0, -3), 0), ("Doorway", (1, 0, -3), 0), ("CornerNE", (3, 0, -3), 270)):
        s.inst("Assembly", name, "env", {"CornerNW": "corner", "Gate": "lockdown_gate", "Doorway": "doorway", "CornerNE": "corner"}[name], pos, rot)
    for i, cz in enumerate((-1, 1)):
        s.inst("Assembly", "WallW%d" % i, "env", "wall", (-3, 0, cz), 90)
        s.inst("Assembly", "WallE%d" % i, "env", "wall", (3, 0, cz), 270)
    s.inst("Assembly", "Pillar", "env", "pillar", (-1, 0, -1))
    s.inst("Assembly", "Platform", "env", "platform", (1, 0, -1))
    s.inst("Assembly", "CableStraight", "env", "cable_straight", (-1, 0, 1))
    s.inst("Assembly", "CableCurve", "env", "cable_curve", (1, 0, 1))
    for i, z in enumerate((-5, -7, -9)):
        s.inst("Assembly", "Tunnel%d" % i, "env", "tunnel_ring", (1, 0, z))
    s.inst("Assembly", "VaultClosed", "props", "vault_closed", (-3.35, 0, -0.3), 90)
    s.inst("Assembly", "Shard", "props", "shard", (-3.35, 1.0, -0.3))
    s.inst("Assembly", "VaultOpen", "props", "vault_open", (-3.35, 0, -2.0), 90)
    s.inst("Assembly", "ShardEncrypted", "props", "shard_encrypted", (-3.35, 1.0, -2.0))
    s.inst("Assembly", "Portal", "props", "portal", (6.4, 0, 1.6))
    s.inst("Assembly", "PortalLocked", "props", "portal_locked", (6.4, 0, -2.6))
    s.inst("Assembly", "Seat", "props", "seat", (-1.3, 0, 1.0))
    s.inst("Assembly", "Sensor", "props", "sensor", (2.5, 0, -2.5))
    s.inst("Assembly", "DeadDeck", "props", "dead_deck", (-0.5, 0.035, -1.9), 20)
    s.inst("Assembly", "SoftIce", "ice", "soft_ice", (0.9, 0, 3.7), 215, anim="patrol", anim_t=0.5)
    s.inst("Assembly", "BlackIce", "ice", "black_ice", (-2.6, 0, 3.9), 225, anim="hunt", anim_t=0.3)
    s.inst("Assembly", "Runner1", "avatar", "runner", (1.6, 0, 1.9), 215)
    s.inst("Assembly", "Runner2", "avatar", "runner", (3.4, 0, 5.0), 230)
    # дека на подставке-помосте (поворот к камере), жетоны — детьми деки в слотах
    s.inst("Assembly", "DeckStand", "env", "platform", (-5.0, 0, 1.0))
    s.node("DeckPivot", "Assembly", "Node3D", transform=xform(DECK_POS, DECK_ROT_Y, DECK_ROT_X))
    s.node("Deck", "Assembly/DeckPivot", instance=s.model("deck", "wrist_deck"))
    for i, eff in enumerate(DECK_IN_SLOTS):
        s.node("Token%d" % (i + 1), "Assembly/DeckPivot/Deck", instance=s.model("deck", "daemon_" + eff),
               transform=xform((SLOT_X[i], SLOT_Y, SLOT_Z)))

    # --- ряд существ -----------------------------------------------------------------------------------------------
    s.node("Lineup", ".", "Node3D", transform=xform((-60, 0, 0)))
    row = [("BlackIdle", "ice", "black_ice", "idle", 0.9), ("BlackHunt", "ice", "black_ice", "hunt", 0.3),
           ("BlackCatch", "ice", "black_ice", "catch", 0.5), ("SoftIdle", "ice", "soft_ice", "idle", 0.5),
           ("SoftPatrol", "ice", "soft_ice", "patrol", 0.4), ("RunnerA", "avatar", "runner", None, 0), ("RunnerB", "avatar", "runner", None, 0)]
    x = -6.2
    for name, group, asset, anim, t in row:
        s.inst("Lineup", name, group, asset, (x, 0, 0), 150, anim=anim, anim_t=t)
        x += 2.5 if asset == "black_ice" else 1.9
    # --- тиры env: по тиру две строки по пять модулей -------------------------------------------------------------
    s.node("Tiers", ".", "Node3D", transform=xform((50, 0, -6)))
    for ti, (sfx, _label) in enumerate(TIERS):
        for mi, mod in enumerate(ENV):
            row, col = divmod(mi, 5)
            s.inst("Tiers", "%s%d" % (mod.title().replace("_", ""), ti), "env", mod + sfx, (col * 3.4, 0, ti * 9.0 + row * 4.5))
    # --- полка с жетонами ------------------------------------------------------------------------------------------
    s.node("TokenShelf", ".", "Node3D", transform=xform((-60.0, 1.0, 30.0)))
    s.node("Shelf", "TokenShelf", "MeshInstance3D", transform=xform((0.1575, -0.028, 0)), props=['mesh = SubResource("%s")' % shelf])
    for i, eff in enumerate(EFFECTS):
        s.inst("TokenShelf", "Token_" + eff, "deck", "daemon_" + eff, (0.045 * i, 0, 0))

    # --- камеры ----------------------------------------------------------------------------------------------------
    s.node("CamOverview", ".", "Camera3D", transform=look_at((5.2, 12.5, 12.8), (0.9, 0.6, 0.6)), props=["fov = 40.0", "current = true"])
    s.node("CamCreatures", ".", "Camera3D", transform=look_at((-59.65, 2.0, 12.0), (-59.65, 1.35, 0.0)), props=["fov = 36.0"])
    deck_cam = deck_view(0.5, 38)
    s.node("CamDeck", ".", "Camera3D", transform=look_at(*deck_cam), props=["fov = 36.0"])
    s.node("CamTokens", ".", "Camera3D", transform=look_at((-59.84, 1.1, 30.75), (-59.84, 1.0, 30.0)), props=["fov = 26.0"])
    s.node("CamTiers", ".", "Camera3D", transform=look_at((56.8, 13.0, 36.0), (56.8, 1.0, 6.0)), props=["fov = 40.0"])
    return s.text()


SHOT_SCENE = """[gd_scene format=3]

[ext_resource type="Script" path="res://assets/preview_shot.gd" id="1"]

[node name="PreviewShot" type="Node"]
script = ExtResource("1")
"""


def main():
    with open(os.path.join(ASSETS, "preview.tscn"), "w", encoding="utf-8") as fh:
        fh.write(build_preview())
    with open(os.path.join(ASSETS, "preview_shot.tscn"), "w", encoding="utf-8") as fh:
        fh.write(SHOT_SCENE)
    print("записаны preview.tscn и preview_shot.tscn")


if __name__ == "__main__":
    main()

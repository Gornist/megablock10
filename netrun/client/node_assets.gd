class_name NodeAssets
extends RefCounted
## 3D-ассеты «Сети» (assets/models, каталог и соглашения — MANIFEST.md): пути по тиру узла, экземпляры сцен и меши для MultiMesh.
## Тир узла (BASE, HARD, NIGHTMARE, graph.json) выбирает файл окружения: `имя.glb`, `имя_hard.glb`, `имя_nightmare.glb` — те же меши с другими материалами.

const ROOT := "res://assets/models/"
const TIER_SUFFIX := {"BASE": "", "HARD": "_hard", "NIGHTMARE": "_nightmare"}
const SOFT_ICE := ROOT + "ice/soft_ice.glb"
const BLACK_ICE := ROOT + "ice/black_ice.glb"
const RUNNER := ROOT + "avatar/runner.glb"

## путь файла -> [{name, mesh, xform}]: меши модели с их позой в корне (для MultiMesh), разбираются один раз
static var _parts: Dictionary = {}


## Неизвестный тир (и одиночный узел без тира) рисуется как BASE.
static func normalize_tier(tier: String) -> String:
	return tier if TIER_SUFFIX.has(tier) else "BASE"


static func env_path(module: String, tier: String) -> String:
	return "%senv/%s%s.glb" % [ROOT, module, TIER_SUFFIX[normalize_tier(tier)]]


static func prop_path(model: String) -> String:
	return "%sprops/%s.glb" % [ROOT, model]


## Экземпляр модели; в метке `asset` — путь файла (по ней тесты и отладка видят, какой ассет подключён).
static func instance(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	var n: Node3D = packed.instantiate() as Node3D if packed != null else Node3D.new()
	if packed == null:
		push_error("[node-assets] нет модели: " + path)
	n.set_meta("asset", path)
	return n


## Меши модели с позой относительно корня. У lockdown_gate их два (Frame, Bars_Closed), у остальных модулей — один (Mesh).
static func mesh_parts(path: String) -> Array:
	if _parts.has(path):
		return _parts[path]
	var parts: Array = []
	var root := instance(path)
	_collect(root, Transform3D.IDENTITY, parts)
	root.free()
	_parts[path] = parts
	return parts


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		var t := xf * (c as Node3D).transform if c is Node3D else xf
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append({"name": str(c.name), "mesh": (c as MeshInstance3D).mesh, "xform": t})
		_collect(c, t, out)

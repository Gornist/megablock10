class_name NodeAssets
extends RefCounted
## 3D-ассеты «Сети» (assets/models, канон — assets/ARCHITECTURE.md): пути, экземпляры сцен и меши для MultiMesh.
## .glb несут форму и цвета вершин; вид (аддитивность, свечение, дыхание штрихов, тир, отражение в полу) задают шейдеры из assets/shaders,
## которые подставляет AssetMaterials.apply. Тир узла (BASE, HARD, NIGHTMARE, graph.json) — параметр материала окружения, а не отдельные файлы:
## путь модуля от тира не зависит, тир передаётся в instance/mesh_parts. Существа, предметы и аватары тира не имеют (цвета из вершин).

const ROOT := "res://assets/models/"
const TIERS := ["BASE", "HARD", "NIGHTMARE"]
const SOFT_ICE := ROOT + "ice/soft_ice.glb"
const BLACK_ICE := ROOT + "ice/black_ice.glb"
const RUNNER := ROOT + "avatar/runner.glb"
## Отражение в полу: яркость зеркальной копии (assets/ARCHITECTURE.md, п. 8).
const REFLECTION_INTENSITY := 0.18
## У этих групп под ногами есть отражение; шард, парящий над полом, и мелочь без отражения.
const REFLECT_MARKS := ["/ice/", "/avatar/", "vault", "portal", "sensor", "seat"]

## ключ "путь|тир|яркость" -> [{name, mesh, xform}]: меши модели с материалами и позой в корне (для MultiMesh), разбираются один раз
static var _parts: Dictionary = {}


## Неизвестный тир (и одиночный узел без тира) рисуется как BASE.
static func normalize_tier(tier: String) -> String:
	return tier if TIERS.has(tier) else "BASE"


## Путь модуля окружения. От тира не зависит (тир — материал); аргумент оставлен ради прежних вызовов.
static func env_path(module: String, _tier: String = "BASE") -> String:
	return "%senv/%s.glb" % [ROOT, module]


static func prop_path(model: String) -> String:
	return "%sprops/%s.glb" % [ROOT, model]


## Экземпляр модели с материалами из assets/shaders; в метке `asset` — путь файла (по ней тесты и отладка видят, какой ассет подключён).
## tier — для окружения; пусто — цвета из вершин. Клипы (AnimationPlayer) зациклены. У существ, хранилищ, порталов, датчика и кресла — отражение в полу.
static func instance(path: String, tier: String = "") -> Node3D:
	var packed := load(path) as PackedScene
	var n: Node3D = packed.instantiate() as Node3D if packed != null else Node3D.new()
	if packed == null:
		push_error("[node-assets] нет модели: " + path)
	else:
		_dress(n, tier)
		if _reflects(path):
			_add_reflection(n, packed)
	n.set_meta("asset", path)
	return n


static func _reflects(path: String) -> bool:
	for m in REFLECT_MARKS:
		if path.contains(m):
			return true
	return false


static func _dress(n: Node, tier: String, intensity: float = 1.0) -> void:
	AssetMaterials.apply(n, normalize_tier(tier) if tier != "" else "")
	if intensity != 1.0:
		AssetMaterials.set_intensity(n, intensity)
	for p in n.find_children("*", "AnimationPlayer", true, false):
		for a in (p as AnimationPlayer).get_animation_list():
			(p as AnimationPlayer).get_animation(a).loop_mode = Animation.LOOP_LINEAR


## Зеркальная копия под полом (scale.y = −1) с яркостью REFLECTION_INTENSITY. Лежит в корневом узле клипов (Rig), чтобы наклон и покачивание
## шли и в отражении (у моделей без клипов — в корне). Работает, пока корень модели стоит на y = 0.
static func _add_reflection(n: Node3D, packed: PackedScene) -> void:
	var mirror := packed.instantiate() as Node3D
	for p in mirror.find_children("*", "AnimationPlayer", true, false):
		p.get_parent().remove_child(p)
		p.free()
	for a in mirror.find_children("*Anchor*", "Node3D", true, false):
		a.get_parent().remove_child(a)
		a.free()
	_dress(mirror, "", REFLECTION_INTENSITY)
	mirror.name = "Reflection"
	mirror.scale = Vector3(1, -1, 1)
	var rig := n.get_node_or_null("Rig")
	(rig if rig != null else n).add_child(mirror)


## Меши модели с материалами и позой относительно корня. Для MultiMesh: материал сидит на самом меше (у MultiMeshInstance3D своих по поверхностям нет).
## mirrored — зеркальная копия для отражения (яркость REFLECTION_INTENSITY, ось Y перевёрнута в самой позе).
static func mesh_parts(path: String, tier: String = "", mirrored: bool = false) -> Array:
	var key := "%s|%s|%s" % [path, normalize_tier(tier), mirrored]
	if _parts.has(key):
		return _parts[key]
	var parts: Array = []
	var root := Node3D.new()
	var packed := load(path) as PackedScene
	if packed != null:
		root.free()
		root = packed.instantiate() as Node3D
	_dress(root, tier, REFLECTION_INTENSITY if mirrored else 1.0)
	_collect(root, Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3.ZERO) if mirrored else Transform3D.IDENTITY, parts)
	root.free()
	_parts[key] = parts
	return parts


## Контракт предметов узла «волюметрик» (assets/ARCHITECTURE.md): в ассете включается РОВНО ОДНО из State_<имя> (без явного выключения видны все сразу);
## узлы ищутся по всему дереву, чтобы переключилась и зеркальная копия отражения в полу.
static func set_state(root: Node, state: String) -> void:
	for n in root.find_children("State_*", "Node3D", true, false):
		(n as Node3D).visible = str(n.name) == "State_" + state


## Тир предмета T кумулятивно: Tier_k виден при k <= T (кольца шарда, засечки на постаменте хранилища).
static func set_tier_nodes(root: Node, tier: int) -> void:
	for k in range(1, 4):
		for n in root.find_children("Tier_%d" % k, "Node3D", true, false):
			(n as Node3D).visible = k <= tier


## Затухание по расстоянию и параметры шейдера на материалах частей из mesh_parts (кэш общий для всех экземпляров пути и тира). Параметр, которого у шейдера
## материала нет (у дымки нет far_gain), пропускается, как в AssetMaterials.set_param.
static func tune_parts(parts: Array, fade: Vector2, params: Dictionary) -> void:
	for part in parts:
		var mesh := part["mesh"] as Mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as ShaderMaterial
			if m == null:
				continue
			var names: Array = m.shader.get_shader_uniform_list().map(func(u): return u["name"])
			if names.has("fade_start"):
				m.set_shader_parameter("fade_start", fade.x)
				m.set_shader_parameter("fade_end", fade.y)
			for k in params:
				if names.has(k):
					m.set_shader_parameter(k, params[k])


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		var t := xf * (c as Node3D).transform if c is Node3D else xf
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var mesh := mi.mesh.duplicate() as Mesh
			for s in mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m != null:
					mesh.surface_set_material(s, m)
			out.append({"name": str(c.name), "mesh": mesh, "xform": t})
		_collect(c, t, out)

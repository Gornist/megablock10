extends GdUnitTestSuite
## 3D-ассеты «Сети» (assets/models: env, props): все файлы импортируются, тиры — те же меши с другими материалами,
## метки (ShardSlot, SeatAnchor, EyeAnchor) на своих местах, материалов не больше двух и без прозрачности.
## Треугольники и бюджет проверяет assets/src/check_budget.py (чистый Python, по самим .glb).

const ENV := ["floor", "wall", "corner", "pillar", "doorway", "platform", "lockdown_gate", "cable_straight", "cable_curve", "tunnel_ring"]
const TIER_SUFFIX := {"BASE": "", "HARD": "_hard", "NIGHTMARE": "_nightmare"}
const PROPS := ["vault_closed", "vault_open", "shard", "shard_encrypted", "dead_deck", "portal", "sensor", "seat"]


func _load(group: String, asset: String) -> Node:
	var path := "res://assets/models/%s/%s.glb" % [group, asset]
	var scene := load(path) as PackedScene
	assert_bool(scene != null).override_failure_message("не импортируется: " + path).is_true()
	return auto_free(scene.instantiate()) if scene != null else null


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Материалы всех поверхностей (без повторов).
func _materials(root: Node) -> Array[BaseMaterial3D]:
	var out: Array[BaseMaterial3D] = []
	for mi in _meshes(root):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			assert_bool(m != null).is_true()
			if m != null and not out.has(m) and out.filter(func(o): return o.resource_name == m.resource_name).is_empty():
				out.append(m)
	return out


func _aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _neon(root: Node) -> BaseMaterial3D:
	for m in _materials(root):
		if m.emission_enabled:
			return m
	return null


func _check_plain(root: Node, label: String) -> void:
	if root == null:
		return
	assert_bool(_meshes(root).size() > 0).override_failure_message(label + ": нет мешей").is_true()
	var mats := _materials(root)
	assert_int(mats.size()).override_failure_message(label + ": материалов не больше двух").is_between(1, 2)
	for m in mats:
		assert_int(m.transparency).override_failure_message(label + ": прозрачность").is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert_bool(_neon(root) != null).override_failure_message(label + ": нет светящегося материала").is_true()


func test_env_all_tiers_import() -> void:
	for asset in ENV:
		for tier in TIER_SUFFIX:
			_check_plain(_load("env", asset + TIER_SUFFIX[tier]), "env/%s %s" % [asset, tier])


func test_props_import() -> void:
	for asset in PROPS:
		_check_plain(_load("props", asset), "props/" + asset)


func test_env_tiers_share_geometry_but_not_colors() -> void:
	for asset in ENV:
		var base := _load("env", asset)
		var hard := _load("env", asset + TIER_SUFFIX["HARD"])
		var night := _load("env", asset + TIER_SUFFIX["NIGHTMARE"])
		if base == null or hard == null or night == null:
			continue
		assert_vector(_aabb(hard).size).is_equal_approx(_aabb(base).size, Vector3.ONE * 0.001)
		assert_vector(_aabb(night).size).is_equal_approx(_aabb(base).size, Vector3.ONE * 0.001)
		assert_int(_meshes(hard).size()).is_equal(_meshes(base).size())
		if asset == "lockdown_gate":
			continue  # красный неон ворот одинаков во всех тирах, различается только тело
		assert_bool(_neon(base).albedo_color.is_equal_approx(_neon(hard).albedo_color)).override_failure_message(asset + ": неон HARD совпал с BASE").is_false()
		assert_bool(_neon(base).albedo_color.is_equal_approx(_neon(night).albedo_color)).override_failure_message(asset + ": неон NIGHTMARE совпал с BASE").is_false()
		assert_bool(_neon(hard).albedo_color.is_equal_approx(_neon(night).albedo_color)).is_false()


func test_grid_modules_fit_the_cell() -> void:
	# модули окружения лежат в ячейке 2x2 м (допуск на неон и фаски), пол и помост стоят на y=0 / выше
	for asset in ["floor", "wall", "corner", "doorway", "platform", "lockdown_gate"]:
		var root := _load("env", asset)
		if root == null:
			continue
		var b := _aabb(root)
		assert_float(b.size.x).override_failure_message(asset + ": ширина").is_between(1.99, 2.02)
		assert_float(b.position.x).is_between(-1.01, -0.99)
	var wall := _aabb(_load("env", "wall"))
	assert_float(wall.size.y).is_between(3.1, 3.3)
	assert_float(wall.position.y).is_between(-0.001, 0.001)
	var tunnel := _aabb(_load("env", "tunnel_ring"))
	assert_float(tunnel.size.z).override_failure_message("сегмент тоннеля 2 м вдоль Z").is_between(1.99, 2.01)
	# внутренний пол на y=0, оболочка толщиной 0,25 м уходит под пол
	assert_float(tunnel.position.y).override_failure_message("оболочка тоннеля под полом").is_between(-0.26, -0.24)


func test_lockdown_gate_parts() -> void:
	var g := _load("env", "lockdown_gate")
	if g == null:
		return
	assert_bool(g.get_node_or_null("Frame") is MeshInstance3D).is_true()
	assert_bool(g.get_node_or_null("Bars_Closed") is MeshInstance3D).is_true()


func test_marks_on_props() -> void:
	for asset in ["vault_closed", "vault_open"]:
		var v := _load("props", asset)
		if v == null:
			continue
		var slot := v.get_node_or_null("ShardSlot") as Node3D
		assert_bool(slot != null).override_failure_message(asset + ": нет ShardSlot").is_true()
		if slot != null:
			assert_vector(slot.position).is_equal_approx(Vector3(0, 1.0, 0), Vector3.ONE * 0.001)
	var seat := _load("props", "seat")
	if seat != null:
		assert_vector((seat.get_node("SeatAnchor") as Node3D).position).is_equal_approx(Vector3(0, 0.5, 0), Vector3.ONE * 0.001)
		assert_float((seat.get_node("EyeAnchor") as Node3D).position.y).is_equal_approx(1.2, 0.001)  # глаза сидящего ~1,2 м


func test_portal_pad_matches_graph_radius() -> void:
	# площадка портала — радиус прохода из graph.json (portal_radius 1,5 м)
	var radius := float(NodeGraph.load_file().settings["portal_radius"])
	var b := _aabb(_load("props", "portal"))
	assert_float(radius).is_equal(NodeLayout.PORTAL_RADIUS)
	assert_float(b.size.z).override_failure_message("площадка r=1.5 -> 3 м по Z").is_between(2 * radius - 0.01, 2 * radius + 0.01)


func test_shard_variants_share_mesh() -> void:
	var plain := _load("props", "shard")
	var enc := _load("props", "shard_encrypted")
	if plain == null or enc == null:
		return
	assert_vector(_aabb(enc).size).is_equal_approx(_aabb(plain).size, Vector3.ONE * 0.001)
	# ядро и поясок меняются местами: у обычного светится ядро (поверхность 0), у зашифрованного — поясок (поверхность 1)
	var p_mesh := _meshes(plain)[0].mesh as ArrayMesh
	var e_mesh := _meshes(enc)[0].mesh as ArrayMesh
	assert_bool((p_mesh.surface_get_material(0) as BaseMaterial3D).emission_enabled).is_true()
	assert_bool((p_mesh.surface_get_material(1) as BaseMaterial3D).emission_enabled).is_false()
	assert_bool((e_mesh.surface_get_material(0) as BaseMaterial3D).emission_enabled).is_false()
	assert_bool((e_mesh.surface_get_material(1) as BaseMaterial3D).emission_enabled).is_true()

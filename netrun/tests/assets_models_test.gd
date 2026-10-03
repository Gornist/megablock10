extends GdUnitTestSuite
## 3D-ассеты «Сети» (assets/models: env, props, ice, avatar, deck): все файлы импортируются, тиры — те же меши с другими
## материалами, метки (ShardSlot, SeatAnchor, EyeAnchor, AlertAnchor, NameAnchor, Slot1..5) на своих местах, материалов не больше
## двух и без прозрачности; у ICE клипы названы по ТЗ и зациклены, скелет не больше 20 костей; сцена preview.tscn содержит каждый .glb.
## Треугольники и бюджет проверяет assets/src/check_budget.py (чистый Python, по самим .glb).

const ENV := ["floor", "wall", "corner", "pillar", "doorway", "platform", "lockdown_gate", "cable_straight", "cable_curve", "tunnel_ring"]
const TIER_SUFFIX := {"BASE": "", "HARD": "_hard", "NIGHTMARE": "_nightmare"}
const PROPS := ["vault_closed", "vault_open", "shard", "shard_encrypted", "dead_deck", "portal", "portal_locked", "sensor", "seat"]
## клипы ICE — имена из ТЗ (docs/netrun-assets-brief.md, п. 11-12)
const ICE := {"soft_ice": ["idle", "patrol"], "black_ice": ["idle", "hunt", "catch"]}
## жетоны демонов в слотах деки — эффекты DaemonEffect (docs/netrun.md, «Демоны»)
const DAEMON_EFFECTS := ["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]
const MAX_BONES := 20


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


func _neon_color(root: Node) -> Color:
	return _neon(root).albedo_color


func _skeleton(root: Node) -> Skeleton3D:
	return root.find_child("Skeleton3D", true, false) as Skeleton3D


func _animation_player(root: Node) -> AnimationPlayer:
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer


func test_ice_skeleton_and_clips() -> void:
	for asset in ICE:
		var root := _load("ice", asset)
		if root == null:
			continue
		_check_plain(root, "ice/" + asset)
		var sk := _skeleton(root)
		assert_bool(sk != null).override_failure_message(asset + ": нет Skeleton3D").is_true()
		if sk != null:
			assert_int(sk.get_bone_count()).override_failure_message(asset + ": костей не больше 20").is_between(2, MAX_BONES)
		var skinned := _meshes(root).filter(func(m): return m.skin != null)
		assert_bool(skinned.size() > 0).override_failure_message(asset + ": меш не скинится").is_true()
		var ap := _animation_player(root)
		assert_bool(ap != null).override_failure_message(asset + ": нет AnimationPlayer").is_true()
		if ap == null:
			continue
		var names := Array(ap.get_animation_list())
		names.sort()
		var want: Array = ICE[asset].duplicate()
		want.sort()
		assert_array(names).override_failure_message(asset + ": клипы по ТЗ").is_equal(want)
		for clip in names:
			var anim := ap.get_animation(clip)
			assert_int(anim.loop_mode).override_failure_message("%s/%s: клип должен быть зациклен" % [asset, clip]).is_equal(Animation.LOOP_LINEAR)
			assert_float(anim.length).override_failure_message("%s/%s: короткий клип" % [asset, clip]).is_between(0.3, 4.0)
			assert_int(anim.get_track_count()).is_greater(0)
		var anchor := root.get_node_or_null("AlertAnchor") as Node3D
		assert_bool(anchor != null).override_failure_message(asset + ": нет AlertAnchor").is_true()


func test_ice_clips_move_the_skeleton() -> void:
	# клип действительно двигает кости: к середине каждого клипа хотя бы одна кость ушла от позы покоя
	for asset in ICE:
		var root := _load("ice", asset)
		if root == null:
			continue
		add_child(root)
		var sk := _skeleton(root)
		var ap := _animation_player(root)
		for clip in ICE[asset]:
			ap.play(clip)
			ap.seek(ap.get_animation(clip).length * 0.37, true)
			var moved := 0.0
			for i in sk.get_bone_count():
				moved = maxf(moved, sk.get_bone_pose_rotation(i).angle_to(sk.get_bone_rest(i).basis.get_rotation_quaternion()))
				moved = maxf(moved, sk.get_bone_pose_position(i).distance_to(sk.get_bone_rest(i).origin))
			assert_float(moved).override_failure_message("%s/%s: клип не двигает кости" % [asset, clip]).is_greater(0.02)
		remove_child(root)


func test_black_ice_is_taller_and_wider_than_soft() -> void:
	# силуэты различимы издалека: Black ICE крупнее и выше (ТЗ: «крупнее и заметно страшнее»)
	var soft := _aabb(_load("ice", "soft_ice"))
	var black := _aabb(_load("ice", "black_ice"))
	assert_float(black.size.y).override_failure_message("Black ICE выше 2,5 м").is_greater(2.5)
	assert_float(soft.size.y + soft.position.y).override_failure_message("Soft ICE ниже 1,8 м").is_less(1.8)
	assert_float(black.size.y).is_greater(soft.size.y * 1.6)
	assert_float(black.size.x).is_greater(soft.size.x * 1.4)
	# оба парят/стоят над полом и смотрят в -Z (линза и маска лежат в отрицательных z), origin на полу в центре
	for b in [soft, black]:
		assert_float(b.position.y).is_greater(-0.01)
		assert_float(b.get_center().x).is_between(-0.05, 0.05)


func test_avatar_runner() -> void:
	var root := _load("avatar", "runner")
	if root == null:
		return
	_check_plain(root, "avatar/runner")
	var sk := _skeleton(root)
	assert_bool(sk != null).is_true()
	if sk != null:
		assert_int(sk.get_bone_count()).is_between(2, MAX_BONES)
		for bone in ["Root", "Torso", "Head", "HandL", "HandR"]:
			assert_int(sk.find_bone(bone)).override_failure_message("нет кости " + bone).is_greater_equal(0)
		# глаза на 1,2 м, как у кресла: голова в роли «сидящего» человека
		assert_float(sk.get_bone_global_rest(sk.find_bone("Head")).origin.y).is_between(1.05, 1.3)
	var ap := _animation_player(root)
	assert_bool(ap == null or ap.get_animation_list().is_empty()).override_failure_message("у аватара клипов нет").is_true()
	var b := _aabb(root)
	assert_float(b.size.y + b.position.y).override_failure_message("аватар ростом сидящего, без ног").is_between(1.3, 1.7)
	assert_float(b.position.y).override_failure_message("без ног: низ выше пола").is_greater(0.3)
	assert_bool(root.get_node_or_null("NameAnchor") is Node3D).is_true()
	# неон — поверхность 1: клиент перекрашивает её под игрока
	var mesh := _meshes(root)[0].mesh
	assert_bool((mesh.surface_get_material(1) as BaseMaterial3D).emission_enabled).is_true()


func test_wrist_deck_slots_and_screen() -> void:
	var root := _load("deck", "wrist_deck")
	if root == null:
		return
	_check_plain(root, "deck/wrist_deck")
	# слоты: пять, в ряд, с шагом 3,4 см, на одной высоте
	var xs: Array[float] = []
	for i in range(1, 6):
		var slot := root.get_node_or_null("Slot%d" % i) as Node3D
		assert_bool(slot != null).override_failure_message("нет метки Slot%d" % i).is_true()
		if slot == null:
			return
		xs.append(slot.position.x)
		assert_float(slot.position.y).is_equal_approx(0.094, 0.001)
		assert_float(slot.position.z).is_equal_approx(0.065, 0.001)
	for i in range(1, 5):
		assert_float(xs[i] - xs[i - 1]).override_failure_message("шаг слотов 3,4 см").is_equal_approx(0.034, 0.0005)
	assert_float(xs[0] + xs[4]).override_failure_message("ряд слотов симметричен").is_equal_approx(0.0, 0.001)
	# экран: отдельный меш-плоскость 0,15 x 0,10 м, смотрит вверх (+Y), UV от (0,0) до (1,1), без своего свечения
	var screen := root.get_node_or_null("Screen") as MeshInstance3D
	assert_bool(screen != null).override_failure_message("нет плоскости Screen").is_true()
	if screen == null:
		return
	var box := screen.get_aabb()
	assert_vector(box.size).is_equal_approx(Vector3(0.15, 0.0, 0.10), Vector3(0.001, 0.001, 0.001))
	var arrays := screen.mesh.surface_get_arrays(0)
	assert_bool(arrays[Mesh.ARRAY_TEX_UV] != null).override_failure_message("у Screen нет UV").is_true()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in uv:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	assert_vector(lo).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))
	assert_vector(hi).is_equal_approx(Vector2.ONE, Vector2(0.001, 0.001))
	for n in arrays[Mesh.ARRAY_NORMAL]:
		assert_vector(n).is_equal_approx(Vector3.UP, Vector3(0.001, 0.001, 0.001))
	# левый верхний угол экрана для зрителя (x=-0,075, к кисти z=0,135) — UV (0,0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		if verts[i].x < 0 and verts[i].z < 0.16:
			assert_vector(uv[i]).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))
	assert_bool(screen.mesh.surface_get_material(0) is BaseMaterial3D and not (screen.mesh.surface_get_material(0) as BaseMaterial3D).emission_enabled).is_true()
	# origin — точка крепления: колодки ремней вокруг оси запястья, плита уходит к локтю в +Z
	var b := _aabb(root)
	assert_float(b.position.z).is_between(0.0, 0.05)
	assert_float(b.end.z).is_between(0.24, 0.3)
	assert_float(b.get_center().x).is_between(-0.01, 0.01)


func test_daemon_tokens() -> void:
	var colors: Array[Color] = []
	for effect in DAEMON_EFFECTS:
		var root := _load("deck", "daemon_" + effect)
		if root == null:
			continue
		_check_plain(root, "deck/daemon_" + effect)
		var b := _aabb(root)
		# жетон 3 см, origin в центре (штырь снизу уходит в слот), лицо в +Z
		assert_float(maxf(b.size.x, b.size.y)).override_failure_message(effect + ": жетон крупнее 5 см").is_between(0.02, 0.05)
		assert_float(b.size.z).override_failure_message(effect + ": глубина жетона").is_less(0.03)
		assert_float(b.get_center().x).override_failure_message(effect + ": центр по X").is_between(-0.003, 0.003)
		assert_float(b.get_center().y).override_failure_message(effect + ": центр по Y").is_between(-0.012, 0.012)
		assert_float(b.get_center().z).override_failure_message(effect + ": центр по Z").is_between(-0.003, 0.003)
		var c := _neon_color(root)
		for other in colors:
			var d := Vector3(c.r - other.r, c.g - other.g, c.b - other.b).length()
			assert_float(d).override_failure_message(effect + ": цвет совпал с другим жетоном").is_greater(0.18)
		colors.append(c)
	assert_int(colors.size()).is_equal(DAEMON_EFFECTS.size())


func test_portal_locked_is_the_same_arch_in_red() -> void:
	var open := _load("props", "portal")
	var locked := _load("props", "portal_locked")
	if open == null or locked == null:
		return
	assert_vector(_aabb(locked).size).is_equal_approx(_aabb(open).size, Vector3.ONE * 0.001)
	assert_vector(_aabb(locked).position).is_equal_approx(_aabb(open).position, Vector3.ONE * 0.001)
	# «закрыт» читается цветом: бирюзовый (acc) -> красный (bad)
	assert_bool(_neon_color(open).b > _neon_color(open).r).is_true()
	assert_bool(_neon_color(locked).r > _neon_color(locked).b + 0.3).is_true()


func _glb_paths(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_glb_paths(dir.path_join(d)))
	return out


func _instanced_models(n: Node, found: Dictionary) -> void:
	if n.scene_file_path.ends_with(".glb"):
		found[n.scene_file_path] = true
	for c in n.get_children():
		_instanced_models(c, found)


func test_preview_scene_contains_every_model() -> void:
	var scene := load("res://assets/preview.tscn") as PackedScene
	assert_bool(scene != null).override_failure_message("preview.tscn не загружается").is_true()
	if scene == null:
		return
	var root := auto_free(scene.instantiate()) as Node
	var found := {}
	_instanced_models(root, found)
	var missing: Array[String] = []
	for path in _glb_paths("res://assets/models"):
		if not found.has(path):
			missing.append(path)
	assert_array(missing).override_failure_message("в preview.tscn нет моделей: %s" % [missing]).is_empty()
	for cam in ["CamOverview", "CamCreatures", "CamDeck", "CamTokens", "CamTiers"]:
		assert_bool(root.get_node_or_null(cam) is Camera3D).override_failure_message("нет камеры " + cam).is_true()

extends GdUnitTestSuite
## 3D-ассеты «Сети» (assets/models: env, props, ice, avatar, deck): все файлы импортируются и одеваются шейдерами из assets/shaders, тир окружения —
## параметр материала (не отдельные файлы), метки на своих местах (Anchor_Shard, Anchor_Seat, Anchor_Slot0…4, Anchor_Screen, AlertAnchor), у ICE клипы названы
## по ТЗ и зациклены, модули окружения вписаны в ячейку 2×2 м, у существ и предметов есть отражение в полу. Бюджеты и форму самих .glb проверяет
## assets/src/validate.py (чистый Python, по самим .glb; CI гоняет его отдельным шагом). Канон — assets/ARCHITECTURE.md.

const ROOT := "res://assets/models/"
## модули окружения клиента (NodeView.MODULES) и их варианты
const ENV_VARIANTS := {
	"floor": ["floor", "floor_b", "floor_c"], "wall": ["wall", "wall_b", "wall_c"], "doorway": ["doorway", "doorway_b"],
	"ceiling": ["ceiling", "ceiling_b", "ceiling_c"], "corner": ["corner"], "pillar": ["pillar"], "platform": ["platform"],
	"lockdown_gate": ["lockdown_gate"], "tunnel_ring": ["tunnel_ring"],
	"far_field": ["far_field", "far_field_b", "far_field_c"], "far_floor": ["far_floor", "far_floor_b", "far_floor_c"],
	"far_ceiling": ["far_ceiling", "far_ceiling_b", "far_ceiling_c"],
}
const PROPS := ["vault_closed", "vault_open", "shard", "shard_encrypted", "dead_deck", "portal", "portal_locked", "sensor", "seat"]
## клипы ICE — имена из ТЗ (docs/netrun-assets-brief.md, п. 11-12)
const ICE := {"soft_ice": ["idle", "patrol"], "black_ice": ["idle", "hunt", "catch"]}
const DAEMON_EFFECTS := ["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]
const CELL_FIT := 2.2  # модуль в ячейке 2×2 м: допуск на дыхание штрихов и разброс по глубине


func _load(group: String, asset: String) -> Node3D:
	var path := "%s%s/%s.glb" % [ROOT, group, asset]
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


func _aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _shader_materials(root: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for mi in _meshes(root):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null:
				out.append(m)
	return out


# ---------------------------------------------------------------- импорт

func test_env_variants_import() -> void:
	for module in ENV_VARIANTS:
		for v in ENV_VARIANTS[module]:
			assert_bool(_load("env", v) != null).is_true()


func test_props_ice_avatar_deck_import() -> void:
	for p in PROPS:
		assert_bool(_load("props", p) != null).is_true()
	for i in ICE:
		assert_bool(_load("ice", i) != null).is_true()
	assert_bool(_load("avatar", "runner") != null).is_true()
	assert_bool(_load("deck", "wrist_deck") != null).is_true()
	for e in DAEMON_EFFECTS:
		assert_bool(_load("deck", "daemon_" + e) != null).is_true()


func test_every_model_is_dressed_in_our_shaders() -> void:
	## .glb приходят с материалами-ролями (streaks, points, solid_dark, shell_soft); NodeAssets.instance подменяет их на шейдеры.
	for path in ["env/floor", "env/wall", "props/vault_open", "props/portal", "ice/soft_ice", "avatar/runner"]:
		var n := NodeAssets.instance(ROOT + path + ".glb")
		auto_free(n)
		assert_int(_shader_materials(n).size()).override_failure_message("%s: нет шейдеров" % path).is_greater(0)
		assert_str(str(n.get_meta("asset"))).is_equal(ROOT + path + ".glb")


# ---------------------------------------------------------------- тир

func test_env_path_does_not_depend_on_tier() -> void:
	assert_str(NodeAssets.env_path("floor", "BASE")).is_equal("res://assets/models/env/floor.glb")
	assert_str(NodeAssets.env_path("floor", "HARD")).is_equal("res://assets/models/env/floor.glb")
	assert_str(NodeAssets.env_path("wall", "что-то новое")).is_equal("res://assets/models/env/wall.glb")
	assert_str(NodeAssets.normalize_tier("что-то новое")).is_equal("BASE")
	assert_str(NodeAssets.normalize_tier("")).is_equal("BASE")


func test_tier_is_a_material_tint() -> void:
	var colors := {}
	for tier in ["BASE", "HARD", "NIGHTMARE"]:
		var parts := NodeAssets.mesh_parts(NodeAssets.env_path("wall", tier), tier)
		assert_bool(parts.size() > 0).is_true()
		var mat := ((parts[0]["mesh"] as Mesh).surface_get_material(0)) as ShaderMaterial
		assert_bool(mat != null).override_failure_message("%s: на меше нет шейдера" % tier).is_true()
		assert_float(float(mat.get_shader_parameter("tint_amount"))).is_equal(1.0)
		colors[tier] = mat.get_shader_parameter("tint")
	assert_bool(colors["BASE"] != colors["HARD"] and colors["HARD"] != colors["NIGHTMARE"]).override_failure_message("тиры одного цвета").is_true()
	# красный в тирах не участвует (он только для угрозы)
	for tier in colors:
		assert_bool(colors[tier].b >= colors[tier].r).override_failure_message("%s: красный в окружении" % tier).is_true()


func _halo_of(m: ShaderMaterial) -> float:
	var v: Variant = m.get_shader_parameter("halo")  # не выставлен явно (существа) — null: действует значение по умолчанию 0
	return 0.0 if v == null else float(v)


func _streak_halos(n: Node) -> Array:
	var out: Array = []
	for mi in _meshes(n):
		for s in mi.mesh.get_surface_count():
			var m := (mi.get_surface_override_material(s) if mi.get_surface_override_material(s) != null else mi.mesh.surface_get_material(s)) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "halo"):
				out.append(_halo_of(m))
	return out


func test_env_streaks_have_a_soft_halo_and_creatures_do_not() -> void:
	## мягкий ореол (люминесценция) — только у окружения (с тиром); у существ, аватаров и деки штрихи резкие
	var env_parts := NodeAssets.mesh_parts(NodeAssets.env_path("wall", "BASE"), "BASE")
	var seen := 0
	for p in env_parts:
		var mesh := p["mesh"] as Mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "halo"):
				seen += 1
				assert_float(_halo_of(m)).is_greater(0.0)
	assert_int(seen).override_failure_message("в стене нет штрихов с ореолом").is_greater(0)
	for path in ["ice/soft_ice", "avatar/runner"]:
		var n := NodeAssets.instance(ROOT + path + ".glb")
		auto_free(n)
		var halos := _streak_halos(n)
		assert_int(halos.size()).override_failure_message("%s: нет штрихов" % path).is_greater(0)
		for h in halos:
			assert_float(h).override_failure_message("%s: ореол у существа" % path).is_equal(0.0)


func test_slab_modules_have_a_translucent_additive_skirt() -> void:
	## «вуаль» на гранях плит: меш `*_skirt` в модулях с плитами; шейдер аддитивный, без освещения и без записи глубины; по одному квадрату на грань
	var skirts := {"floor": "floor_skirt", "floor_c": "floor_skirt", "ceiling": "ceiling_skirt", "far_floor": "far_floor_skirt", "far_ceiling": "far_ceiling_skirt"}
	for module in skirts:
		var parts := NodeAssets.mesh_parts(NodeAssets.env_path(module), "BASE")
		var found := 0
		for p in parts:
			if p["name"] != skirts[module]:
				continue
			found += 1
			var mesh := p["mesh"] as Mesh
			assert_int(mesh.get_surface_count()).is_equal(1)
			var m := mesh.surface_get_material(0) as ShaderMaterial
			assert_bool(m != null and m.shader.resource_path.ends_with("skirt.gdshader")).override_failure_message("%s: у вуали не skirt.gdshader" % module).is_true()
			var code := m.shader.code
			for flag in ["blend_add", "unshaded", "depth_draw_never"]:
				assert_bool(code.contains(flag)).override_failure_message("%s: в шейдере вуали нет %s" % [module, flag]).is_true()
			assert_bool(code.contains("hint_depth_texture") or code.contains("DEPTH_TEXTURE")).override_failure_message("вуаль читает буфер глубины").is_false()
			assert_float(float(m.shader.get_shader_uniform_list().filter(func(u): return u["name"] == "veil_alpha").size())).is_equal(1.0)
			assert_bool(float(m.get_shader_parameter("tint_amount")) == 1.0).is_true()
			var verts := (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			assert_bool(verts > 0 and verts % 4 == 0).override_failure_message("%s: вуаль не из квадратов (%d вершин)" % [module, verts]).is_true()
			assert_bool(verts <= 4 * 4 * 30).override_failure_message("%s: слишком много граней вуали (%d вершин)" % [module, verts]).is_true()
		assert_int(found).override_failure_message("%s: нет меша %s" % [module, skirts[module]]).is_equal(1)
	# чистая площадка без плит вуали не имеет
	for p in NodeAssets.mesh_parts(NodeAssets.env_path("floor_clear"), "BASE"):
		assert_bool(str(p["name"]).ends_with("_skirt")).is_false()


func test_horizon_band_is_one_streak_mesh_and_far_gain_is_off_by_default() -> void:
	var band := _load("env", "horizon_band")
	var meshes := _meshes(band)
	assert_int(meshes.size()).override_failure_message("horizon_band: должен быть один меш").is_equal(1)
	var verts := (meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(verts).override_failure_message("horizon_band: больше 400 штрихов (4 вершины на штрих)").is_less_equal(1600)
	var sh := load("res://assets/shaders/streaks.gdshader") as Shader
	var names := sh.get_shader_uniform_list().map(func(u): return u["name"])
	for u in ["halo", "halo_width", "far_gain", "far_start", "far_end"]:
		assert_bool(u in names).override_failure_message("в streaks нет uniform " + u).is_true()
	assert_bool(sh.code.contains("uniform float far_gain : hint_range(1.0, 6.0) = 1.0;")).override_failure_message("far_gain по умолчанию не 1").is_true()
	assert_bool(sh.code.contains("uniform float halo : hint_range(0.0, 1.0) = 0.0;")).override_failure_message("halo по умолчанию не 0").is_true()


func test_mesh_parts_are_cached_per_tier_and_mirror() -> void:
	var a := NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "BASE")
	assert_bool(NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "BASE") == a).is_true()
	assert_bool(NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "HARD") != a).is_true()
	var mirror := NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "BASE", true)
	assert_bool(mirror != a).is_true()
	assert_float((mirror[0]["xform"] as Transform3D).basis.y.y).is_equal(-1.0)  # зеркало: ось Y перевёрнута


# ---------------------------------------------------------------- сетка

func test_grid_modules_fit_the_cell() -> void:
	for module in ["floor", "floor_b", "floor_c", "ceiling", "wall", "wall_b", "wall_c", "doorway", "doorway_b", "corner", "pillar", "platform", "lockdown_gate"]:
		var box := _aabb(_load("env", module))
		assert_float(box.size.x).override_failure_message("%s: шире ячейки (%.2f)" % [module, box.size.x]).is_less(CELL_FIT)
		assert_float(box.size.z).override_failure_message("%s: глубже ячейки (%.2f)" % [module, box.size.z]).is_less(CELL_FIT)
		assert_float(absf(box.get_center().x)).override_failure_message("%s: сдвинут по X" % module).is_less(0.1)
		assert_float(absf(box.get_center().z)).override_failure_message("%s: сдвинут по Z" % module).is_less(0.1)


func test_floor_never_rises_above_the_floor_and_ceiling_never_drops_below_the_ceiling() -> void:
	for f in ["floor", "floor_b", "floor_c"]:
		assert_float(_aabb(_load("env", f)).end.y).override_failure_message(f).is_less(0.05)
	for c in ["ceiling", "ceiling_b", "ceiling_c"]:
		assert_float(_aabb(_load("env", c)).position.y).override_failure_message(c).is_greater(-0.05)


func test_portal_is_as_wide_as_the_graph_radius() -> void:
	for p in ["portal", "portal_locked"]:
		var box := _aabb(_load("props", p))
		assert_float(box.size.x).override_failure_message("%s: ширина %.2f" % [p, box.size.x]).is_between(2.0 * NodeLayout.PORTAL_RADIUS - 0.4, 2.0 * NodeLayout.PORTAL_RADIUS + 0.4)


# ---------------------------------------------------------------- метки

func test_marks_on_props() -> void:
	for p in ["vault_closed", "vault_open"]:
		var vault := _load("props", p)
		assert_bool(vault.find_child("Anchor_Shard", true, false) != null).override_failure_message("%s: нет Anchor_Shard" % p).is_true()
	assert_bool(_load("props", "seat").find_child("Anchor_Seat", true, false) != null).is_true()


func test_wrist_deck_slots_and_screen() -> void:
	var deck := _load("deck", "wrist_deck")
	for i in 5:
		assert_bool(deck.find_child("Anchor_Slot%d" % i, true, false) != null).override_failure_message("нет гнезда %d" % i).is_true()
	assert_bool(deck.find_child("Anchor_Screen", true, false) != null).is_true()
	assert_bool(deck.find_child("deck_screen", true, false) != null).override_failure_message("нет плоскости экрана").is_true()


func test_daemon_tokens_are_small_and_not_red() -> void:
	for e in DAEMON_EFFECTS:
		var box := _aabb(_load("deck", "daemon_" + e))
		assert_float(box.get_longest_axis_size()).override_failure_message("%s: %.3f м" % [e, box.get_longest_axis_size()]).is_between(0.015, 0.1)


# ---------------------------------------------------------------- существа

func test_ice_clips_are_named_by_the_brief_and_looped() -> void:
	for ice in ICE:
		var model := NodeAssets.instance(ROOT + "ice/%s.glb" % ice)
		auto_free(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert_bool(player != null).override_failure_message("%s: нет AnimationPlayer" % ice).is_true()
		if player == null:
			continue
		for clip in ICE[ice]:
			assert_bool(player.has_animation(clip)).override_failure_message("%s: нет клипа %s" % [ice, clip]).is_true()
			assert_int(player.get_animation(clip).loop_mode).override_failure_message("%s/%s не зациклен" % [ice, clip]).is_equal(Animation.LOOP_LINEAR)
		assert_bool(model.find_child("AlertAnchor", true, false) != null).override_failure_message("%s: нет AlertAnchor" % ice).is_true()


func test_ice_clips_move_the_body() -> void:
	for ice in ICE:
		var model := NodeAssets.instance(ROOT + "ice/%s.glb" % ice)
		auto_free(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var rig := model.find_child("Rig", true, false) as Node3D
		assert_bool(rig != null).is_true()
		for clip in ICE[ice]:
			var anim := player.get_animation(clip)
			assert_bool(anim.get_track_count() > 0).override_failure_message("%s/%s: пустой клип" % [ice, clip]).is_true()
			assert_float(anim.length).override_failure_message("%s/%s: длина" % [ice, clip]).is_between(0.5, 6.0)


func test_black_ice_is_taller_and_wider_than_soft() -> void:
	var soft := _aabb(_load("ice", "soft_ice"))
	var black := _aabb(_load("ice", "black_ice"))
	assert_float(black.size.y).is_greater(soft.size.y)
	assert_float(black.size.x).is_greater(soft.size.x)


func test_ice_and_avatar_have_a_reflection_but_shard_does_not() -> void:
	for path in ["ice/soft_ice", "ice/black_ice", "avatar/runner", "props/vault_open", "props/portal"]:
		var n := NodeAssets.instance(ROOT + path + ".glb")
		auto_free(n)
		var mirror := n.find_child("Reflection", true, false) as Node3D
		assert_bool(mirror != null).override_failure_message("%s: нет отражения" % path).is_true()
		if mirror != null:
			assert_float(mirror.scale.y).is_equal(-1.0)
	var shard := NodeAssets.instance(ROOT + "props/shard.glb")
	auto_free(shard)
	assert_bool(shard.find_child("Reflection", true, false) == null).override_failure_message("шард парит над полом: отражения у него нет").is_true()


func test_avatar_runner() -> void:
	var box := _aabb(_load("avatar", "runner"))
	assert_float(box.size.y).override_failure_message("рост %.2f" % box.size.y).is_between(1.2, 1.7)
	assert_float(box.position.y).is_greater(-0.05)  # ног нет, но стоит на полу


func test_shard_variants_differ_only_in_colour() -> void:
	var a := _aabb(_load("props", "shard"))
	var b := _aabb(_load("props", "shard_encrypted"))
	assert_float(absf(a.size.y - b.size.y)).is_less(0.01)

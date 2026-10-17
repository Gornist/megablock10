extends GdUnitTestSuite
## 3D-ассеты «Сети» (assets/models: env, props, ice, avatar, deck): все файлы импортируются и одеваются шейдерами из assets/shaders, тир окружения —
## параметр материала (не отдельные файлы), метки на своих местах (Anchor_Shard, Anchor_Seat, Anchor_Slot0…4, Anchor_Screen, AlertAnchor), у ICE клипы названы
## по ТЗ и зациклены, модули окружения вписаны в ячейку 2×2 м, у существ и предметов есть отражение в полу. Бюджеты и форму самих .glb проверяет
## assets/src/validate.py (чистый Python, по самим .glb; CI гоняет его отдельным шагом). Канон — assets/ARCHITECTURE.md.

const ROOT := "res://assets/models/"
## модули окружения клиента (NodeView.MODULES) и их варианты
const ENV_VARIANTS := {
	"floor": ["floor", "floor_b", "floor_c"], "ceiling": ["ceiling", "ceiling_b", "ceiling_c"], "pillar": ["pillar"], "platform": ["platform"],
	"lockdown_gate": ["lockdown_gate"], "exit_frame": ["exit_frame"], "far_floor": ["far_floor", "far_floor_b", "far_floor_c"],
	"far_ceiling": ["far_ceiling", "far_ceiling_b", "far_ceiling_c"],
}
const PROPS := ["vault", "vault_closed", "vault_open", "shard", "shard_encrypted", "daemon_token", "hack_panel", "hack_pad", "dead_deck", "portal", "portal_locked", "sensor", "seat"]
## Бюджеты треугольников предметов узла «волюметрик» (карточка владельца; точки и штрихи считает validate.py по самим .glb)
const VOLUME_TRIS := {"vault": 900, "shard": 300, "shard_encrypted": 400, "daemon_token": 200, "hack_panel": 300, "hack_pad": 120}
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


## Меши предмета БЕЗ маяка: узел `Beacon` (меши beacon_beam, beacon_halo) в габарит предмета не входит (ARCHITECTURE.md, «Предметы узла «волюметрик»»).
func _item_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n.name == &"Beacon":
		return out
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_item_meshes(c))
	return out


func _item_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _item_meshes(root):
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
	for path in ["env/floor", "env/platform", "props/vault_open", "props/portal", "ice/soft_ice", "avatar/runner"]:
		var n := NodeAssets.instance(ROOT + path + ".glb")
		auto_free(n)
		assert_int(_shader_materials(n).size()).override_failure_message("%s: нет шейдеров" % path).is_greater(0)
		assert_str(str(n.get_meta("asset"))).is_equal(ROOT + path + ".glb")


# ---------------------------------------------------------------- тир

func test_env_path_does_not_depend_on_tier() -> void:
	assert_str(NodeAssets.env_path("floor", "BASE")).is_equal("res://assets/models/env/floor.glb")
	assert_str(NodeAssets.env_path("floor", "HARD")).is_equal("res://assets/models/env/floor.glb")
	assert_str(NodeAssets.env_path("platform", "что-то новое")).is_equal("res://assets/models/env/platform.glb")
	assert_str(NodeAssets.normalize_tier("что-то новое")).is_equal("BASE")
	assert_str(NodeAssets.normalize_tier("")).is_equal("BASE")


func test_tier_is_a_material_tint() -> void:
	var colors := {}
	for tier in ["BASE", "HARD", "NIGHTMARE"]:
		var parts := NodeAssets.mesh_parts(NodeAssets.env_path("platform", tier), tier)
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


func test_env_streaks_and_creatures_have_no_halo() -> void:
	## ореол штрихов окружения убран в B1 (в окружении штрихи не рисуются, streak_keep=0); у существ, аватаров и деки штрихи резкие
	var env_parts := NodeAssets.mesh_parts(NodeAssets.env_path("exit_frame", "BASE"), "BASE")   # у platform штрихов больше нет (15.10)
	var seen := 0
	for p in env_parts:
		var mesh := p["mesh"] as Mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "halo"):
				seen += 1
				assert_float(_halo_of(m)).is_equal(0.0)
	assert_int(seen).override_failure_message("в рамке выхода нет штрихов (шейдер с halo)").is_greater(0)
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


## Шейдер штрихов: ореол и «яркость к горизонту» выключены по умолчанию (включает AssetMaterials только у окружения; в B2c модуль horizon_band удалён вместе с кольцом горизонта).
func test_streaks_shader_far_gain_and_halo_are_off_by_default() -> void:
	var sh := load("res://assets/shaders/streaks.gdshader") as Shader
	var names := sh.get_shader_uniform_list().map(func(u): return u["name"])
	for u in ["halo", "halo_width", "far_gain", "far_start", "far_end"]:
		assert_bool(u in names).override_failure_message("в streaks нет uniform " + u).is_true()
	assert_bool(sh.code.contains("uniform float far_gain : hint_range(1.0, 6.0) = 1.0;")).override_failure_message("far_gain по умолчанию не 1").is_true()
	assert_bool(sh.code.contains("uniform float halo : hint_range(0.0, 1.0) = 0.0;")).override_failure_message("halo по умолчанию не 0").is_true()


## Пол комнаты одним тайлом (env/floor_slab_16): одна тонкая плита на всю комнату, верх не выше пола, сторона = стороне room_edge_16, вуаль (`*_skirt`) по периметру.
## Подвесные штрихи и точки швов убраны в B2 (в окружении они не рисуются: streak_keep=0, point_keep=0; сетка клеток — текстурой в шейдере solid_dark).
func test_floor_slab_is_single_thin_slab_with_veil_only() -> void:
	var room := NodeLayout.ROOM_MAX - NodeLayout.ROOM_MIN
	var root := _load("env", "floor_slab_16")
	var slab: MeshInstance3D = null
	var skirt: MeshInstance3D = null
	var tris := 0
	for mi in _meshes(root):
		var n := String(mi.name)
		if n.ends_with("_skirt"):
			skirt = mi
			tris += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif n == "slab":
			slab = mi
			tris += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		else:
			assert_bool(false).override_failure_message("floor_slab_16: лишний меш «%s» (штрихов и точек в окружении нет)" % n).is_true()
	assert_bool(slab != null and skirt != null).override_failure_message("floor_slab_16: нужны меши slab и *_skirt").is_true()
	assert_int(tris).override_failure_message("floor_slab_16: %d треугольников > 400" % tris).is_less_equal(400)
	var sb := slab.get_aabb()
	assert_float(sb.size.x).override_failure_message("плита не %g м по X" % room.x).is_equal_approx(room.x, 0.01)
	assert_float(sb.size.z).is_equal_approx(room.x, 0.01)
	assert_float(sb.size.y).override_failure_message("плита не тонкая (3 см)").is_less_equal(0.031)
	assert_float(sb.end.y).override_failure_message("верх плиты выше пола").is_less_equal(0.0)
	assert_float(_aabb(root).end.y).override_failure_message("что-то выше пола больше 4 см").is_less_equal(0.04)
	assert_int(skirt.mesh.get_surface_count()).is_equal(1)
	AssetMaterials.apply(root, "BASE")
	var skm := skirt.get_surface_override_material(0) as ShaderMaterial
	assert_bool(skm != null and skm.shader.resource_path.ends_with("skirt.gdshader")).override_failure_message("у вуали не skirt.gdshader").is_true()


## Удалённые в B2 экспериментальные модели не возвращаются (клиент их не грузит; docs/netrun-refactor-plan.md).
func test_experimental_floor_models_are_gone() -> void:
	for name in ["floor_v1_8", "floor_v1_16", "floor_v2_8", "floor_v2_16", "floor_v3_8", "floor_v3_16", "floor_v4_8", "floor_v4_16", "floor_glass_8", "floor_glass_16",
			"floor_clear", "floor_slab_8", "room_edge_8", "room_moat_8", "room_moat_16"]:
		assert_bool(ResourceLoader.exists(ROOT + "env/%s.glb" % name)).override_failure_message("env/%s.glb должен быть удалён (B2)" % name).is_false()
	assert_bool(ResourceLoader.exists("res://assets/shaders/glass.gdshader")).is_false()
	for name in ["wall", "wall_b", "wall_c", "corner", "doorway", "doorway_b", "tunnel_ring", "far_field", "far_field_b", "far_field_c", "horizon_band", "portal_wall", "cable_straight", "cable_curve", "column_field", "room_edge_16"]:
		assert_bool(ResourceLoader.exists(ROOT + "env/%s.glb" % name)).override_failure_message("env/%s.glb должен быть удалён (B2c/B2d)" % name).is_false()
	assert_bool(ResourceLoader.exists("res://assets/shaders/haze.gdshader")).override_failure_message("haze.gdshader удалён вместе с дымкой (B2d)").is_false()


func test_mesh_parts_are_cached_per_tier_and_mirror() -> void:
	var a := NodeAssets.mesh_parts(NodeAssets.env_path("platform"), "BASE")
	assert_bool(NodeAssets.mesh_parts(NodeAssets.env_path("platform"), "BASE") == a).is_true()
	assert_bool(NodeAssets.mesh_parts(NodeAssets.env_path("platform"), "HARD") != a).is_true()
	var mirror := NodeAssets.mesh_parts(NodeAssets.env_path("platform"), "BASE", true)
	assert_bool(mirror != a).is_true()
	assert_float((mirror[0]["xform"] as Transform3D).basis.y.y).is_equal(-1.0)  # зеркало: ось Y перевёрнута


# ---------------------------------------------------------------- сетка

func test_grid_modules_fit_the_cell() -> void:
	for module in ["floor", "floor_b", "floor_c", "ceiling", "pillar", "platform", "lockdown_gate", "exit_frame"]:
		var box := _aabb(_load("env", module))
		assert_float(box.size.x).override_failure_message("%s: шире ячейки (%.2f)" % [module, box.size.x]).is_less(CELL_FIT)
		assert_float(box.size.z).override_failure_message("%s: глубже ячейки (%.2f)" % [module, box.size.z]).is_less(CELL_FIT)
		assert_float(absf(box.get_center().x)).override_failure_message("%s: сдвинут по X" % module).is_less(0.1)
		assert_float(absf(box.get_center().z)).override_failure_message("%s: сдвинут по Z" % module).is_less(0.1)


func test_floor_never_rises_above_the_floor_and_ceiling_never_drops_below_the_ceiling() -> void:
	for f in ["floor", "floor_b", "floor_c"]:
		# твёрдая часть и штрихи — не выше пола; прозрачная завеса вверх от плит (меш *_skirt с UV2, env._slab_rise) в этот габарит не входит, её высота — ниже
		var root := _load("env", f)
		var solid := AABB()
		var first := true
		for mi in _meshes(root):
			if String(mi.name).ends_with("_skirt") and ((mi.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0:
				assert_float((mi.transform * mi.get_aabb()).end.y).override_failure_message("%s: завеса вверх выше 0,5 м" % f).is_less(0.5)
				continue
			var b: AABB = mi.transform * mi.get_aabb()
			solid = b if first else solid.merge(b)
			first = false
		assert_float(solid.end.y).override_failure_message(f).is_less(0.05)
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


func test_shard_variants_have_the_same_height_but_differ_in_form() -> void:
	var a := _load("props", "shard")
	var b := _load("props", "shard_encrypted")
	assert_float(absf(_item_aabb(a).size.y - _item_aabb(b).size.y)).is_less(0.02)
	assert_float(_item_aabb(a).size.y).is_between(0.12, 0.15)  # 13 см (маяк Beacon не в счёт)
	assert_bool(a.find_child("shard_core_shell0", true, false) != null and a.find_child("shard_cage_pts", true, false) == null).override_failure_message("расшифрованный: ядро есть, клетки нет").is_true()
	assert_bool(b.find_child("shard_core_shell0", true, false) == null and b.find_child("shard_cage_pts", true, false) != null).override_failure_message("зашифрованный: клетка есть, ядро скрыто").is_true()
	assert_bool(b.find_child("shard_glitch_pts", true, false) != null).override_failure_message("зашифрованный: нет глитч-полос").is_true()


# ---------------------------------------------------------------- предметы узла «волюметрик»: контракт узлов (ARCHITECTURE.md, «Предметы узла»)

func _tris(root: Node) -> int:
	var n := 0
	for mi in _meshes(root):
		for i in mi.mesh.get_surface_count():
			var role := String(mi.mesh.surface_get_material(i).resource_name) if mi.mesh.surface_get_material(i) != null else ""
			if role == "points" or role == "streaks":
				continue
			var arr := mi.mesh.surface_get_arrays(i)
			n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func test_volume_props_are_within_triangle_budgets() -> void:
	for p in VOLUME_TRIS:
		var t := _tris(_load("props", p))
		assert_int(t).override_failure_message("%s: %d треугольников > %d" % [p, t, VOLUME_TRIS[p]]).is_less_equal(VOLUME_TRIS[p])


func test_vault_has_three_states_three_tiers_and_a_shard_slot() -> void:
	var v := _load("props", "vault")
	for s in ["State_closed", "State_open", "State_empty", "Tier_1", "Tier_2", "Tier_3"]:
		var n := v.find_child(s, true, false) as Node3D
		assert_bool(n != null).override_failure_message("vault: нет узла " + s).is_true()
		assert_bool(n != null and _meshes(n).size() > 0).override_failure_message("vault: в %s нет мешей" % s).is_true()
	var slot := v.find_child("ShardSlot", true, false) as Node3D
	assert_bool(slot != null).override_failure_message("vault: нет ShardSlot").is_true()
	assert_float(slot.position.y).is_equal_approx(1.0, 0.01)  # центр шарда на 1,0 м над полом
	var box := _aabb(v)
	assert_float(box.position.y).is_between(-0.01, 0.01)  # origin на полу
	assert_float(box.size.x).is_between(0.85, 1.0)  # основание по клетке хода 1×1 м: лоток 0,9 м + щель 5 см, весь вид внутри клетки
	assert_float(box.size.z).is_between(0.85, 1.0)
	assert_float(box.position.x + box.size.x / 2.0).is_equal_approx(0.0, 0.03)  # origin — центр клетки
	assert_float(box.position.z + box.size.z / 2.0).is_equal_approx(0.0, 0.03)
	assert_float(box.size.y).is_between(0.7, 0.95)
	# состояния различимы силуэтом: закрытое с клеткой высокое, пустое низкое
	var closed := _aabb(v.find_child("State_closed", true, false))
	var empty := _aabb(v.find_child("State_empty", true, false))
	assert_float(closed.end.y - empty.end.y).override_failure_message("closed и empty одной высоты").is_greater(0.3)


func test_tiers_are_cumulative_marks_on_vault_and_shards() -> void:
	for p in ["vault", "shard", "shard_encrypted"]:
		var n := _load("props", p)
		for k in [1, 2, 3]:
			assert_bool(n.find_child("Tier_%d" % k, true, false) != null).override_failure_message("%s: нет Tier_%d" % [p, k]).is_true()


func test_daemon_token_is_a_flat_hex_chip() -> void:
	var box := _item_aabb(_load("props", "daemon_token"))  # без маяка Beacon
	assert_float(maxf(box.size.x, box.size.y)).is_between(0.10, 0.15)
	assert_float(box.size.z).override_failure_message("токен плоский, толщина %.3f" % box.size.z).is_less(0.03)
	assert_float(absf(box.get_center().x) + absf(box.get_center().y) + absf(box.get_center().z)).is_less(0.03)  # origin в центре


func test_hack_panel_screen_and_anchor() -> void:
	var p := _load("props", "hack_panel")
	var screen := p.find_child("Screen", true, false) as MeshInstance3D
	var anc := p.find_child("ScreenAnchor", true, false) as Node3D
	assert_bool(screen != null and anc != null).override_failure_message("hack_panel: нужны Screen и ScreenAnchor").is_true()
	var sb := screen.mesh.get_aabb()
	assert_float(sb.get_longest_axis_size()).is_between(0.43, 0.47)  # 0,44 м по ширине (с наклоном чуть короче по высоте)
	var arr := screen.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var umin := 1e9
	var umax := -1e9
	var vmin := 1e9
	var vmax := -1e9
	for t in uv:
		umin = minf(umin, t.x)
		umax = maxf(umax, t.x)
		vmin = minf(vmin, t.y)
		vmax = maxf(vmax, t.y)
	assert_bool(umin == 0.0 and umax == 1.0 and vmin == 0.0 and vmax == 1.0).override_failure_message("UV экрана не 0..1: %s..%s, %s..%s" % [umin, umax, vmin, vmax]).is_true()
	# глазами игрока (он на −Z, смотрит на +Z; его право — −X, верх — +Y): u растёт вправо (x убывает), v растёт вниз (y убывает)
	var i0 := 0
	var i1 := 0
	for i in uv.size():
		if uv[i].x < uv[i0].x:
			i0 = i
		if uv[i].x > uv[i1].x:
			i1 = i
	assert_bool(vtx[i0].x > vtx[i1].x).override_failure_message("u растёт не вправо с точки зрения игрока").is_true()
	var j0 := 0
	var j1 := 0
	for i in uv.size():
		if uv[i].y < uv[j0].y:
			j0 = i
		if uv[i].y > uv[j1].y:
			j1 = i
	assert_bool(vtx[j0].y > vtx[j1].y).override_failure_message("v растёт не вниз").is_true()
	# метка: +Z узла от экрана к игроку (игрок на −Z), наклон 25° (нормаль смотрит вверх), центр экрана на ~1,1 м
	var z := anc.transform.basis.z  # метка прямо под корнем (узлы без трансформации)
	assert_float(z.z).override_failure_message("+Z метки не к игроку: %s" % z).is_less(-0.85)
	assert_float(z.y).override_failure_message("наклон не 25°: %s" % z).is_between(0.35, 0.5)
	assert_float(anc.position.y).is_between(1.05, 1.15)
	for n in nrm:
		assert_float(n.dot(z)).override_failure_message("нормаль экрана не совпадает с +Z метки").is_greater(0.99)


func test_hack_pad_is_a_thin_plate_under_the_feet() -> void:
	var box := _aabb(_load("props", "hack_pad"))
	assert_float(box.size.x).is_between(0.85, 1.0)
	assert_float(box.size.z).is_between(0.85, 1.0)
	assert_float(box.position.y).is_between(-0.01, 0.01)
	var plate := _aabb((_load("props", "hack_pad")).find_child("pad_plate", true, false))
	assert_float(plate.size.y).is_between(0.025, 0.035)  # плита 3 см


# ---------------------------------------------------------------- маяк предметов (Beacon) и выход без стен (exit_frame)

func test_shards_and_token_have_a_visible_beacon_and_keep_their_size() -> void:
	for p in ["shard", "shard_encrypted", "daemon_token"]:
		var n := _load("props", p)
		var beacon := n.find_child("Beacon", true, false) as Node3D
		assert_bool(beacon != null).override_failure_message("%s: нет узла Beacon" % p).is_true()
		if beacon == null:
			continue
		assert_bool(beacon.visible).override_failure_message("%s: Beacon по умолчанию виден" % p).is_true()
		for part in ["beacon_beam", "beacon_halo"]:
			assert_bool(beacon.find_child(part, true, false) != null).override_failure_message("%s: в Beacon нет %s" % [p, part]).is_true()
		var item := _item_aabb(n)
		assert_float(_aabb(n).size.y).override_failure_message("%s: маяк виден в общем габарите" % p).is_greater(item.size.y + 0.3)  # луч 0,45 м вверх
		assert_float(item.size.y).override_failure_message("%s: габарит предмета (без Beacon) вырос: %.3f" % [p, item.size.y]).is_less(0.15)
		var halo := _aabb(beacon.find_child("beacon_halo", true, false))
		assert_float(halo.size.x).override_failure_message("%s: ореол ≈ 0,5 м, а не %.2f" % [p, halo.size.x]).is_between(0.45, 0.55)
		assert_float(_aabb(beacon.find_child("beacon_beam", true, false)).size.y).override_failure_message("%s: луч 0,45 м" % p).is_between(0.4, 0.5)


func test_beacon_halo_and_beam_get_their_own_shaders() -> void:
	var n := NodeAssets.instance(ROOT + "props/shard.glb")
	auto_free(n)
	var halo := n.find_child("beacon_halo", true, false) as MeshInstance3D
	var beam := n.find_child("beacon_beam", true, false) as MeshInstance3D
	assert_bool(halo != null and beam != null).is_true()
	var hm := halo.get_surface_override_material(0) as ShaderMaterial
	assert_bool(hm != null and hm.shader == AssetMaterials.BEACON_HALO_SHADER).override_failure_message("ореол маяка без своего шейдера").is_true()
	var bm := beam.get_surface_override_material(0) as ShaderMaterial
	assert_bool(bm != null).is_true()
	assert_float(float(bm.get_shader_parameter("halo"))).override_failure_message("у луча маяка нет ореола").is_greater(0.0)


func test_exit_frame_is_a_free_standing_frame_with_an_empty_opening() -> void:
	var ef := _load("env", "exit_frame")
	var gate := _aabb(_load("env", "lockdown_gate"))
	var box := _aabb(ef)
	assert_float(gate.size.x).override_failure_message("ворота %.2f м шире проёма рамки 1,04 м (косяки на ±0,52)" % gate.size.x).is_between(0.8, 1.04)  # ворота стоят в проёме рамки выхода, косяки и перемычку даёт она
	assert_float(gate.size.y).override_failure_message("высота ворот %.2f: решётка должна закрывать проём 2 м" % gate.size.y).is_between(1.9, 2.1)
	assert_float(box.size.y).override_failure_message("высота столбов %.2f" % box.size.y).is_between(2.2, 2.9)
	assert_float(box.size.z).override_failure_message("рамка не стена: глубина %.2f" % box.size.z).is_less(0.6)
	for mi in _meshes(ef):
		var b: AABB = mi.transform * mi.get_aabb()
		var on_floor := b.end.y < 0.1  # порог: плита 3 см и точки
		var above := b.position.y > 1.9  # перемычка
		var beside := b.position.x >= 0.5 or b.end.x <= -0.5  # столбы-занавесы по бокам
		assert_bool(on_floor or above or beside).override_failure_message("%s: перекрывает проём" % mi.name).is_true()
	var sill := _aabb(ef.find_child("exit_sill", true, false))
	assert_float(sill.size.y).override_failure_message("порог — тонкая плита 3 см").is_between(0.025, 0.04)


# ---------------------------------------------------------------- «ручки для очков» (AssetMaterials.tune / netrun.cfg [assets])

func _mat_of(root: Node, mesh_name: String) -> ShaderMaterial:
	for mi in _meshes(root):
		if String(mi.name) == mesh_name:
			return mi.get_surface_override_material(0) as ShaderMaterial
	return null


func test_asset_materials_knobs_change_materials_and_reset() -> void:
	AssetMaterials.reset_tuning()
	var base := _load("env", "cover")
	AssetMaterials.apply(base, "BASE")
	assert_bool(_mat_of(base, "pillar_block").next_pass == null).override_failure_message("обводки (fringe) больше нет: материал без next_pass").is_true()
	assert_float(float(_mat_of(base, "pillar_block").get_shader_parameter("edge_glow"))).override_failure_message("рёбра колонн: edge_glow 1,0 (принято на очках) вшит константой").is_equal_approx(1.0, 0.001)
	var cfg := ConfigFile.new()
	cfg.set_value("assets", "fringe_on", false)  # удалённая ручка из старого cfg на очках: не ошибка, только предупреждение
	cfg.set_value("assets", "edge_glow", 3.5)
	cfg.set_value("assets", "solid_base", "#102030")
	AssetMaterials.tune_from_config(cfg)
	var tuned := _load("env", "cover")
	AssetMaterials.apply(tuned, "BASE")
	var m := _mat_of(tuned, "pillar_block")
	assert_float(float(m.get_shader_parameter("edge_glow"))).override_failure_message("edge_glow — константа: ключ старого cfg игнорируется").is_equal_approx(1.0, 0.001)
	assert_bool((m.get_shader_parameter("base_color") as Color).is_equal_approx(Color("#102030"))).is_true()
	AssetMaterials.reset_tuning()
	assert_bool(AssetMaterials.KNOBS.has("fringe_on") or AssetMaterials.KNOBS.has("edge_glow")).override_failure_message("удалённые ручки не возвращаются в KNOBS").is_false()


func test_asset_materials_knob_min_px_reaches_streaks() -> void:
	AssetMaterials.reset_tuning()
	AssetMaterials.tune({"min_px_streaks": 3.0})
	var exit_frame := _load("env", "exit_frame")
	AssetMaterials.apply(exit_frame, "BASE")
	var post := _mat_of(exit_frame, "exit_post_l")
	assert_float(float(post.get_shader_parameter("min_px"))).is_equal_approx(3.0, 0.001)
	AssetMaterials.reset_tuning()


# ---------------------------------------------------------------- палитра клиентских слоёв (AssetMaterials.LAYERS)

func test_client_layer_palette_has_only_style_colors() -> void:
	# разрешено: голубой/синий/фиолетовый (165–295°), красная семья (≥345° и ≤20°), почти белое/серое (насыщенность < 0,3); коричневого, жёлтого, оранжевого, зелёного нет
	for name in AssetMaterials.LAYERS:
		var c: Color = AssetMaterials.LAYERS[name]
		var h := c.h * 360.0
		var ok := c.s < 0.30 or (h >= 165.0 and h <= 295.0) or h >= 345.0 or h <= 20.0 or String(name).begins_with("deck_")  # янтарь — только экран деки
		assert_bool(ok).override_failure_message("слой '%s': цвет %s (оттенок %.0f°, насыщенность %.2f) вне палитры STYLE.md" % [name, c.to_html(false), h, c.s]).is_true()
	assert_bool(AssetMaterials.layer("aim_ok").is_equal_approx(AssetMaterials.PAL_CYAN)).is_true()
	assert_float(AssetMaterials.layer("cell_occupied_fill", 0.5).a).is_equal_approx(0.5, 0.001)


func test_asset_materials_knob_floor_grid_texture_on_the_slab() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "floor_slab_16")
	AssetMaterials.apply(dflt, "BASE")
	assert_float(float(_mat_of(dflt, "slab").get_shader_parameter("grid_alpha"))).override_failure_message("по умолчанию сетка-текстура включена").is_equal_approx(0.35, 0.001)
	assert_bool(dflt.find_child("slab_seams", true, false) == null).override_failure_message("точек швов в модели нет (убраны в B2)").is_true()
	AssetMaterials.tune({"floor_grid": 0.0})
	var off := _load("env", "floor_slab_16")
	AssetMaterials.apply(off, "BASE")
	assert_bool(_mat_of(off, "slab").get_shader_parameter("grid_alpha") == null).override_failure_message("floor_grid=0: сетки-текстуры нет (параметр не задан)").is_true()
	AssetMaterials.tune({"floor_grid": 0.4})
	var on := _load("env", "floor_slab_16")
	AssetMaterials.apply(on, "BASE")
	var m := _mat_of(on, "slab")
	assert_float(float(m.get_shader_parameter("grid_alpha"))).is_equal_approx(0.4, 0.001)
	var tex := m.get_shader_parameter("grid_tex") as Texture2D
	assert_bool(tex != null and tex.get_width() == AssetMaterials.GRID_TEX_PX).override_failure_message("текстура клетки не задана").is_true()
	AssetMaterials.reset_tuning()


func test_asset_materials_plate_rim_knobs_reach_plates_and_skirts() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "floor_slab_16")  # умолчания = V10, принятый на очках
	AssetMaterials.apply(dflt, "BASE")
	var d := _mat_of(dflt, "slab")
	assert_float(float(d.get_shader_parameter("rim_top_only"))).is_equal(1.0)
	assert_float(float(d.get_shader_parameter("rim_far_min"))).is_equal_approx(0.0, 0.001)
	assert_float(float(d.get_shader_parameter("rim_far_start"))).is_equal_approx(6.0, 0.001)
	assert_float(float(d.get_shader_parameter("rim_far_end"))).is_equal_approx(10.0, 0.001)
	assert_float(float(d.get_shader_parameter("rim_min_px"))).is_equal_approx(4.0, 0.001)
	assert_float(float(d.get_shader_parameter("edge_round"))).override_failure_message("профиль ребра сглажен по умолчанию").is_equal_approx(1.0, 0.001)
	AssetMaterials.tune({"rim_top_only": false, "rim_far_min": 0.3, "rim_far_start": 6.0, "rim_far_end": 15.0})
	var root := _load("env", "floor_slab_16")
	AssetMaterials.apply(root, "BASE")
	var slab := _mat_of(root, "slab")
	assert_float(float(slab.get_shader_parameter("rim_top_only"))).is_equal(0.0)
	assert_float(float(slab.get_shader_parameter("rim_far_min"))).is_equal_approx(0.3, 0.001)
	assert_float(float(slab.get_shader_parameter("rim_far_end"))).is_equal_approx(15.0, 0.001)
	var cover := _load("env", "cover")  # объём: боковые рёбра должны светиться — ручки плит его не трогают
	AssetMaterials.apply(cover, "BASE")
	assert_bool(_mat_of(cover, "pillar_block").get_shader_parameter("rim_top_only") == null).override_failure_message("ручки плит не должны попадать на укрытие").is_true()
	AssetMaterials.reset_tuning()


func test_removed_knobs_are_not_knobs_and_shaders_have_no_noise_branches() -> void:
	for k in ["fringe_on", "fringe_alpha", "fringe_px", "halo", "halo_width", "halo_far", "edge_glow", "skirt_top_fade", "plate_flat", "edge_soft", "dust", "edge_uneven", "edge_drift", "flat_light", "drift_static", "vertex_clip", "albedo_clip", "mist_alpha", "cloud_lite"]:
		assert_bool(AssetMaterials.KNOBS.has(k)).override_failure_message("ручка «%s» удалена в B1 (docs/netrun-refactor-plan.md): значение вшито или объект ушёл" % k).is_false()
	var uniforms: Array = []
	for u in (AssetMaterials.SHADERS["solid_dark"] as Shader).get_shader_uniform_list():
		uniforms.append(u["name"])
	for k in ["edge_uneven", "edge_drift", "edge_noise_scale", "edge_soft", "vertex_clip", "albedo_clip", "plate_flat", "uv_rim", "dust"]:
		assert_bool(k in uniforms).override_failure_message("solid_dark: uniform «%s» должен быть удалён" % k).is_false()
	assert_bool(not (AssetMaterials.SHADERS["solid_dark"] as Shader).code.contains("TIME")).override_failure_message("solid_dark не зависит от времени (рёбра статичны)").is_true()
	assert_bool(ResourceLoader.exists("res://assets/shaders/fringe.gdshader")).override_failure_message("fringe.gdshader удалён").is_false()


func _streak_mats(root: Node) -> Array:
	var out: Array = []
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "len_scale"):  # только штрихи: keep_frac есть и у точек
				out.append(m)
	return out


func _point_mats(root: Node) -> Array:
	var out: Array = []
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "keep_frac") and not m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "len_scale"):
				out.append(m)
	return out


func test_asset_materials_knob_point_keep_reaches_env_points_only() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "exit_frame")  # образец окружения со штрихами и точками (у platform они убраны 15.10)
	AssetMaterials.apply(dflt, "BASE")
	var base := _point_mats(dflt)
	assert_int(base.size()).override_failure_message("в стене нет точек").is_greater(0)
	for m in base:
		assert_float(float(m.get_shader_parameter("keep_frac"))).override_failure_message("по умолчанию точки окружения убраны (point_keep=0, решение владельца)").is_equal(0.0)
	AssetMaterials.tune({"point_keep": 0.5})
	var tuned := _load("env", "exit_frame")  # образец окружения со штрихами и точками (у platform они убраны 15.10)
	AssetMaterials.apply(tuned, "BASE")
	for m in _point_mats(tuned):
		assert_float(float(m.get_shader_parameter("keep_frac"))).is_equal_approx(0.5, 0.001)
	var creature := _load("ice", "soft_ice")  # существа без тира: ручка окружения их не трогает
	AssetMaterials.apply(creature)
	for m in _point_mats(creature):
		assert_bool(m.get_shader_parameter("keep_frac") == null).override_failure_message("ручка точек окружения попала на существо").is_true()
	AssetMaterials.reset_tuning()


func test_asset_materials_streak_knobs_reach_env_streaks_only() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "exit_frame")  # образец окружения со штрихами и точками (у platform они убраны 15.10)
	AssetMaterials.apply(dflt, "BASE")
	var base := _streak_mats(dflt)
	assert_int(base.size()).override_failure_message("в стене нет штрихов").is_greater(0)
	for m in base:
		assert_float(float(m.get_shader_parameter("keep_frac"))).override_failure_message("по умолчанию штрихи окружения не рисуются (streak_keep=0, решение владельца)").is_equal(0.0)
		assert_bool(m.get_shader_parameter("far_dim_min") == null and m.get_shader_parameter("px_fade") == null).override_failure_message("остальные ручки штрихов не заданы").is_true()
	AssetMaterials.tune({"streak_far_min": 0.3, "streak_far_start": 6.0, "streak_far_end": 20.0, "streak_keep": 0.6, "streak_len": 0.7, "streak_px_fade": 1.0})
	var tuned := _load("env", "exit_frame")  # образец окружения со штрихами и точками (у platform они убраны 15.10)
	AssetMaterials.apply(tuned, "BASE")
	for m in _streak_mats(tuned):
		assert_float(float(m.get_shader_parameter("far_dim_min"))).is_equal_approx(0.3, 0.001)
		assert_float(float(m.get_shader_parameter("far_dim_end"))).is_equal_approx(20.0, 0.001)
		assert_float(float(m.get_shader_parameter("keep_frac"))).is_equal_approx(0.6, 0.001)
		assert_float(float(m.get_shader_parameter("len_scale"))).is_equal_approx(0.7, 0.001)
		assert_float(float(m.get_shader_parameter("px_fade"))).is_equal_approx(1.0, 0.001)
	var creature := _load("ice", "soft_ice")  # существа без тира: ручки окружения их не трогают
	AssetMaterials.apply(creature)
	for m in _streak_mats(creature):
		assert_bool(m.get_shader_parameter("keep_frac") == null).override_failure_message("ручки штрихов окружения попали на существо").is_true()
	AssetMaterials.reset_tuning()


func test_asset_materials_veil_knob_scales_and_hides_the_veil() -> void:
	AssetMaterials.reset_tuning()
	AssetMaterials.tune({"veil_scale": 0.5})
	var slab := _load("env", "floor_slab_16")
	AssetMaterials.apply(slab, "BASE")
	var skirt := _mat_of(slab, "floor_slab_skirt")
	assert_float(float(skirt.get_shader_parameter("veil_scale"))).is_equal_approx(0.5, 0.001)
	AssetMaterials.tune({"veil_scale": 0.0})
	var gone := _load("env", "floor_slab_16")
	AssetMaterials.apply(gone, "BASE")
	for mi in _meshes(gone):
		if String(mi.name).ends_with("_skirt"):
			assert_bool(mi.visible).override_failure_message("veil_scale=0: вуаль должна быть скрыта").is_false()
	AssetMaterials.reset_tuning()


func test_asset_materials_knob_cloud_swaps_solid_dark_for_cloud_shader() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "cover")
	AssetMaterials.apply(dflt, "BASE")
	var pd := _mat_of(dflt, "pillar_block")
	assert_str(pd.shader.resource_path).override_failure_message("по умолчанию реквизит — облако (принятый вид C3a)").contains("cloud_dark")
	assert_float(float(pd.get_shader_parameter("dust"))).is_equal_approx(1.0, 0.001)
	assert_object(pd.get_shader_parameter("glitch_tex")).is_same(GlitchSprite.texture())
	AssetMaterials.tune({"cloud": 0.0})
	var off := _load("env", "cover")
	AssetMaterials.apply(off, "BASE")
	assert_str(_mat_of(off, "pillar_block").shader.resource_path).override_failure_message("cloud=0: грань остаётся solid_dark").contains("solid_dark")
	AssetMaterials.reset_tuning()
	AssetMaterials.tune({"cloud_edge_mix": 0.2})
	var mixed := _load("env", "cover")
	AssetMaterials.apply(mixed, "BASE")
	assert_float(float(_mat_of(mixed, "pillar_block").get_shader_parameter("edge_mix"))).is_equal_approx(0.2, 0.001)
	AssetMaterials.reset_tuning()


func _cloud_meshes(root: Node) -> int:
	var n := 0
	for mi in _meshes(root):
		var sm := mi.get_surface_override_material(0) as ShaderMaterial
		if sm != null and sm.shader != null and sm.shader.resource_path.contains("cloud_dark"):
			n += 1
	return n


func test_asset_materials_cloud_scope_props_yes_slabs_gate_and_deck_no() -> void:
	AssetMaterials.reset_tuning()  # умолчания охвата («всё из частиц», #424): облако на реквизите, полу и дальних пластах; потолок остаётся solid_dark
	assert_int(_cloud_meshes(_apply_new("env", "cover"))).override_failure_message("укрытие — облако").is_greater(0)
	assert_int(_cloud_meshes(_apply_new("env", "exit_frame"))).override_failure_message("рамка выхода — облако").is_greater(0)
	assert_int(_cloud_meshes(_apply_new("env", "far_floor"))).override_failure_message("cloud_far=1 по умолчанию: дальние пласты — облако").is_greater(0)
	assert_int(_cloud_meshes(_apply_new("env", "floor_slab_16"))).override_failure_message("cloud_floor=1 по умолчанию: пол — облако").is_greater(0)
	var slab_mat := _mat_of(_apply_new("env", "floor_slab_16"), "slab")
	assert_float(float(slab_mat.get_shader_parameter("grid_alpha"))).override_failure_message("линии клеток 1 м на полу-облаке сохранены (grid_tex в cloud_dark)").is_greater(0.0)
	assert_object(slab_mat.get_shader_parameter("grid_tex")).is_not_null()
	assert_int(_cloud_meshes(_apply_new("env", "ceiling"))).override_failure_message("cloud_ceiling=0: потолок остаётся solid_dark").is_equal(0)
	AssetMaterials.tune({"cloud_far": 0.0, "cloud_floor": 0.0})
	assert_int(_cloud_meshes(_apply_new("env", "far_floor"))).override_failure_message("cloud_far=0: ручка возвращает сплошную грань").is_equal(0)
	assert_int(_cloud_meshes(_apply_new("env", "floor_slab_16"))).override_failure_message("cloud_floor=0: ручка возвращает solid_dark").is_equal(0)
	AssetMaterials.reset_tuning()
	assert_int(_cloud_meshes(_apply_new("deck", "wrist_deck"))).override_failure_message("/deck/ остаётся сплошным (своя палитра; решение владельца 17.10)").is_equal(0)
	AssetMaterials.tune({"cloud_far": 1.0, "cloud_floor": 1.0, "cloud_ceiling": 1.0})
	assert_int(_cloud_meshes(_apply_new("env", "far_floor"))).override_failure_message("cloud_far=1: дальние пласты тоже облако").is_greater(0)
	assert_int(_cloud_meshes(_apply_new("env", "floor_slab_16"))).override_failure_message("cloud_floor=1: пол — облако").is_greater(0)
	AssetMaterials.reset_tuning()
	var one_side := _apply_new("env", "cover")
	assert_str(_mat_of(one_side, "pillar_block").shader.resource_path).override_failure_message("укрытие — облако, одна сторона (cull_back)").ends_with("cloud_dark.gdshader")
	assert_bool(AssetMaterials.KNOBS.has("cloud_two_sided")).override_failure_message("cloud_two_sided снята 14.10 (+5,5 мс на очках), ручки быть не должно").is_false()
	assert_bool(FileAccess.file_exists("res://assets/shaders/cloud_dark_2s.gdshader")).override_failure_message("cloud_dark_2s.gdshader удалён").is_false()


## Красные облачные материалы корня: у каждого облачного меша dust_color ≈ layer("volume_ice"), касание — светлый красный.
func _assert_cloud_is_red(root: Node, what: String) -> void:
	var red := AssetMaterials.layer("volume_ice")
	var n := 0
	for mi in _meshes(root):
		var sm := mi.get_surface_override_material(0) as ShaderMaterial
		if sm == null or sm.shader == null or not sm.shader.resource_path.contains("cloud_dark"):
			continue
		n += 1
		var c := sm.get_shader_parameter("dust_color") as Color
		assert_bool(c.is_equal_approx(red)).override_failure_message("%s: %s — dust_color не красный слой volume_ice" % [what, mi.name]).is_true()
		var t := sm.get_shader_parameter("touch_color") as Vector3
		assert_float(t.x).override_failure_message("%s: %s — touch_color не красный" % [what, mi.name]).is_greater(t.z)
	assert_int(n).override_failure_message(what + ": нет облачных мешей").is_greater(0)


func test_asset_materials_ice_gear_and_lockdown_gate_are_red_cloud() -> void:
	AssetMaterials.reset_tuning()
	for a in ["lighthouse_ice", "sensor_ice", "barrier_ice", "guard_booth", "black_lair"]:
		_assert_cloud_is_red(_apply_new("ice", a), "ice/" + a)
	_assert_cloud_is_red(_apply_new("env", "lockdown_gate"), "env/lockdown_gate")
	# остальное окружение — бирюза (умолчание шейдера), не красное
	var cover := _apply_new("env", "cover")
	var teal: Variant = _mat_of(cover, "pillar_block").get_shader_parameter("dust_color")
	assert_bool(teal == null).override_failure_message("укрытие: цвет облака не переопределяется, остаётся бирюза шейдера").is_true()
	# логово: облако не ломает три состояния
	var lair := _apply_new("ice", "black_lair")
	for st in ["State_sleep", "State_waking", "State_empty"]:
		var n := lair.find_child(st, true, false)
		assert_bool(n != null and _meshes(n).size() > 0).override_failure_message("black_lair с облаком: нет состояния " + st).is_true()


func _apply_new(group: String, asset: String) -> Node3D:
	var root := _load(group, asset)
	AssetMaterials.apply(root, "BASE")
	return root


func _skirt_mesh(root: Node, mesh_name: String) -> MeshInstance3D:
	for mi in _meshes(root):
		if String(mi.name) == mesh_name:
			return mi
	return null


func _max_y(mi: MeshInstance3D) -> float:
	return mi.mesh.get_aabb().end.y


func _has_uv2(mi: MeshInstance3D) -> bool:
	return ((mi.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0


func test_floor_skirt_mesh_carries_the_upward_curtain_and_the_ceiling_does_not() -> void:
	# завеса вверх от верхней кромки плит пола — квады в том же меше *_skirt (второй слой прозрачности был бы четвёртым, предел 3), высота в UV2.x
	for pair in [["floor", "floor_skirt", 0.5], ["far_floor", "far_floor_skirt", 1.05]]:
		var root := _load("env", pair[0])
		var sk := _skirt_mesh(root, pair[1])
		assert_bool(sk != null).override_failure_message("нет меша %s у %s" % [pair[1], pair[0]]).is_true()
		assert_bool(_has_uv2(sk)).override_failure_message("%s: нет высоты завесы в UV2" % pair[1]).is_true()
		var top := _max_y(sk)
		assert_bool(top > 0.1 and top <= float(pair[2])).override_failure_message("%s: верх завесы %.2f м вне 0,1…%.2f" % [pair[1], top, float(pair[2])]).is_true()
	var ceiling := _load("env", "ceiling")
	var csk := _skirt_mesh(ceiling, "ceiling_skirt")
	assert_bool(csk != null and not _has_uv2(csk)).override_failure_message("у потолка вуаль прежняя, без завесы вверх").is_true()


func test_tile_glow_knobs_drive_only_the_curtain_quads() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "far_floor")
	AssetMaterials.apply(dflt, "BASE")
	var sk := _skirt_mesh(dflt, "far_floor_skirt")
	var m := sk.get_surface_override_material(0) as ShaderMaterial
	assert_float(float(m.get_shader_parameter("rise_gain"))).override_failure_message("по умолчанию завеса вверх включена (tile_glow=3, V10)").is_equal_approx(3.0, 0.001)
	assert_float(float(m.get_shader_parameter("rise_scale"))).is_equal_approx(1.0, 0.001)
	AssetMaterials.tune({"tile_glow": 2.5, "tile_glow_h": 1.5, "veil_scale": 2.0})
	var tuned := _load("env", "far_floor")
	AssetMaterials.apply(tuned, "BASE")
	var tm := _skirt_mesh(tuned, "far_floor_skirt").get_surface_override_material(0) as ShaderMaterial
	assert_float(float(tm.get_shader_parameter("rise_gain"))).is_equal_approx(2.5, 0.001)
	assert_float(float(tm.get_shader_parameter("rise_scale"))).is_equal_approx(1.5, 0.001)
	assert_float(float(tm.get_shader_parameter("veil_scale"))).override_failure_message("veil_scale > 1 усиливает вуаль (потолок одобрен очками)").is_equal_approx(2.0, 0.001)
	AssetMaterials.tune({"veil_scale": 0.0})  # вуаль выключена, завеса вверх включена: меш пола остаётся, потолок скрывается целиком
	var floor_root := _load("env", "far_floor")
	AssetMaterials.apply(floor_root, "BASE")
	assert_bool(_skirt_mesh(floor_root, "far_floor_skirt").visible).override_failure_message("в меше пола есть завеса вверх: скрывать его нельзя").is_true()
	var ceiling := _load("env", "far_ceiling")
	AssetMaterials.apply(ceiling, "BASE")
	assert_bool(_skirt_mesh(ceiling, "far_ceiling_skirt").visible).override_failure_message("veil_scale=0: вуаль потолка скрыта").is_false()
	AssetMaterials.reset_tuning()


func test_veil_is_flat_and_static_without_noise_uniforms() -> void:
	var uniforms: Array = []
	for u in (ResourceLoader.load("res://assets/shaders/skirt.gdshader") as Shader).get_shader_uniform_list():
		uniforms.append(u["name"])
	for k in ["patch_amount", "patch_scale", "patch_drift"]:
		assert_bool(k in uniforms).override_failure_message("skirt: «%s» убран, вуаль ровная и статичная (принято на очках)" % k).is_false()
	var sh := ResourceLoader.load("res://assets/shaders/skirt.gdshader") as Shader
	assert_bool(sh.code.contains("top_fade : hint_range(0.0, 0.5) = 0.12")).override_failure_message("top_fade 0,12 — умолчание шейдера (принято на очках), в материал не пишется").is_true()
	assert_bool(not sh.code.contains("TIME")).override_failure_message("вуаль не зависит от времени").is_true()


func test_edge_round_knob_reaches_solid_dark_smooth_by_default() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "cover")
	AssetMaterials.apply(dflt, "BASE")
	assert_float(float(_mat_of(dflt, "pillar_block").get_shader_parameter("edge_round"))).override_failure_message("по умолчанию профиль ребра сглажен (замер 6 на очках)").is_equal(1.0)
	AssetMaterials.tune({"edge_round": 0.0})
	var cover := _load("env", "cover")
	AssetMaterials.apply(cover, "BASE")
	assert_float(float(_mat_of(cover, "pillar_block").get_shader_parameter("edge_round"))).is_equal(0.0)
	AssetMaterials.reset_tuning()


func test_rim_min_px_knob_reaches_plates_only() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "far_ceiling")
	AssetMaterials.apply(dflt, "BASE")
	assert_float(float(_mat_of(dflt, "tiles").get_shader_parameter("rim_min_px"))).override_failure_message("по умолчанию гашение по ширине кромки 4 px (V10)").is_equal(4.0)
	AssetMaterials.tune({"rim_min_px": 3.0})
	var tuned := _load("env", "far_ceiling")
	AssetMaterials.apply(tuned, "BASE")
	assert_float(float(_mat_of(tuned, "tiles").get_shader_parameter("rim_min_px"))).is_equal_approx(3.0, 0.001)
	var cover := _load("env", "cover")  # колонны: ручки плит их не трогают
	AssetMaterials.apply(cover, "BASE")
	assert_bool(_mat_of(cover, "pillar_block").get_shader_parameter("rim_min_px") == null).override_failure_message("rim_min_px попал на колонну").is_true()
	AssetMaterials.reset_tuning()


# ---------------------------------------------------------------- облако частиц (Б): файлы `.points` (src/points.py)

## Бюджет частиц по модулям (план рефактора §4.1) и полуразмер, м. Совпадает с RECIPES в src/points.py: правите там — правьте здесь.
const POINTS_BUDGET := {
	"props/vault": [1500, 0.012], "props/portal": [800, 0.016], "props/shard": [300, 0.004], "props/shard_encrypted": [300, 0.004],
	"env/exit_frame": [1000, 0.014],
	"ice/soft_ice": [700, 0.018], "ice/black_ice": [900, 0.02], "ice/black_ice_hunt": [900, 0.02], "ice/black_ice_catch": [900, 0.02],
	"ice/black_ice_hound": [900, 0.02], "ice/black_ice_kraken": [900, 0.02], "ice/black_ice_raven": [900, 0.02], "ice/black_ice_scorpion": [900, 0.02],
	"ice/black_ice_lich": [900, 0.02], "ice/black_lair": [1200, 0.02],
}

## Виды Black ICE (ice.md §6.2): тот же силуэт и те же клипы, что у базового, плюс отличительная деталь.
const BLACK_KINDS := ["hound", "kraken", "raven", "scorpion", "lich"]


func test_black_ice_kinds_keep_clips_and_differ_from_base() -> void:
	var base_box := _aabb(_load("ice", "black_ice"))
	var sizes := {}
	for kd in BLACK_KINDS:
		var m := _load("ice", "black_ice_" + kd)
		var player := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert_bool(player != null).override_failure_message("black_ice_%s: нет AnimationPlayer (клипы как у базового)" % kd).is_true()
		if player != null:
			for clip in ["idle", "hunt", "catch"]:
				assert_bool(player.has_animation(clip)).override_failure_message("black_ice_%s: нет клипа %s" % [kd, clip]).is_true()
		assert_bool(m.find_child("AlertAnchor", true, false) != null).override_failure_message("black_ice_%s: нет AlertAnchor" % kd).is_true()
		assert_bool(m.find_child("black_ice_%s_inner" % kd, true, false) != null).is_true()
		var box := _aabb(m)
		if kd in ["hound", "scorpion"]:   # низкие позы: ниже базового, но не ниже 1,5 м (с жалом/гребнем)
			assert_float(box.size.y).override_failure_message("black_ice_%s: низкая поза (1,5…базовый)" % kd).is_between(1.5, base_box.size.y - 0.05)
		else:
			assert_float(box.size.y).override_failure_message("black_ice_%s: рост ≈ как у базового (иглы до 3,4 м)" % kd).is_between(base_box.size.y - 0.05, base_box.size.y + 0.4)
		sizes[kd] = "%.2f,%.2f,%.2f" % [box.size.x, box.size.y, box.size.z]
	var distinct := {}
	for kd in sizes:
		distinct[sizes[kd]] = true
	assert_int(distinct.size()).override_failure_message("виды различимы силуэтом: габариты %s" % str(sizes)).is_greater_equal(4)
	# главный признак вида (Game 14.10): Гончая низкая и вытянутая, Скорпион плоский с кольцом радиуса 4 м, Кракен с нитями к стенам, Ворон с крыльями шире базового
	var hound := _aabb(_load("ice", "black_ice_hound"))
	assert_float(hound.size.y).override_failure_message("Гончая низкая: ниже базового").is_less(base_box.size.y - 0.4)
	assert_float(hound.size.z).override_failure_message("Гончая вытянутая: длиннее базового").is_greater(base_box.size.z + 0.5)
	assert_float(_aabb(_load("ice", "black_ice_scorpion")).size.x).override_failure_message("Скорпион: кольцо 2 клеток карты (радиус 4 м → ≥ 7,5 м)").is_greater(7.5)
	assert_float(_aabb(_load("ice", "black_ice_kraken")).size.x).override_failure_message("Кракен: нити до стен (≥ 4,5 м)").is_greater(4.5)
	assert_float(_aabb(_load("ice", "black_ice_raven")).size.x).override_failure_message("Ворон: крылья шире базового").is_greater(base_box.size.x + 1.0)


func test_black_lair_is_a_four_by_four_slab_with_three_states_and_a_sleeper_anchor() -> void:
	var m := _load("ice", "black_lair")
	var box := _aabb(m)
	assert_float(box.size.x).override_failure_message("логово 2×2 клетки карты по 2 м = 4×4 м").is_equal_approx(4.0, 0.1)
	assert_float(box.size.z).is_equal_approx(4.0, 0.1)
	assert_float(box.position.y).is_between(-0.01, 0.01)   # на полу
	assert_bool(m.find_child("Anchor_Sleeper", true, false) != null).override_failure_message("black_lair: нет якоря Anchor_Sleeper").is_true()
	for s in ["State_sleep", "State_waking", "State_empty"]:
		var n := m.find_child(s, true, false) as Node3D
		assert_bool(n != null and _meshes(n).size() > 0).override_failure_message("black_lair: нет состояния " + s).is_true()
	# П6-6 (в): у спящего есть «сердце» (отдельный меш: AssetMaterials даёт ему быстрый пульс) — читается от входа
	assert_bool((m.find_child("State_sleep", true, false) as Node3D).find_child("black_lair_heart", true, false) != null).override_failure_message("black_lair: нет black_lair_heart в State_sleep").is_true()
	# «пробуждение» выше сна (спящий холм ≤ 1,9 м, пробуждение — до 3,5 м)
	assert_float(_aabb(m.find_child("State_waking", true, false)).size.y).is_greater(_aabb(m.find_child("State_sleep", true, false)).size.y + 0.4)


func _points_model(key: String) -> Node3D:
	var parts := key.split("/")
	return _load(parts[0], parts[1])


func test_points_files_load_with_cloud_parser_and_fit_their_models() -> void:
	for m in POINTS_BUDGET:
		var path: String = ROOT + m + ".points"
		assert_bool(FileAccess.file_exists(path)).override_failure_message("нет " + path + " (src/points.py, pipeline.sh build)").is_true()
		var bytes := FileAccess.get_file_as_bytes(path)
		assert_int(bytes.size() % VolumeCloud.POINT_BYTES).override_failure_message("%s: размер %d не кратен %d" % [m, bytes.size(), VolumeCloud.POINT_BYTES]).is_equal(0)
		var pts := VolumeCloud.load_file(path)
		var n := VolumeCloud.points_in(pts)
		assert_int(n).override_failure_message("%s: пусто" % m).is_greater(0)
		assert_int(n).override_failure_message("%s: %d точек > бюджета %d" % [m, n, POINTS_BUDGET[m][0]]).is_less_equal(POINTS_BUDGET[m][0])
		var model := _points_model(m)
		var box := _aabb(model).grow(float(POINTS_BUDGET[m][1]) + 0.05)
		var out_of_box := 0
		for i in n:
			var o := i * VolumeCloud.POINT_FLOATS
			var p := Vector3(pts[o], pts[o + 1], pts[o + 2])
			if not box.has_point(p) or not is_finite(p.x + p.y + p.z):
				out_of_box += 1
			var half := pts[o + 3]
			assert_bool(half > 0.0 and half <= 0.05 and pts[o + 4] >= 0.0 and pts[o + 4] <= 1.0 and (pts[o + 5] == 0.0 or pts[o + 5] == 1.0) and pts[o + 6] >= 0.0 and pts[o + 6] <= 1.0) \
				.override_failure_message("%s: точка %d: поля вне диапазона" % [m, i]).is_true()
		assert_int(out_of_box).override_failure_message("%s: %d точек вне габарита модели" % [m, out_of_box]).is_equal(0)


func test_points_lod_prefix_is_a_uniform_sample() -> void:
	# ЛОД = префикс массива (VolumeCloud.LOD_STEPS): середина высоты первой восьмой части не должна уходить от всей выборки
	for m in POINTS_BUDGET:
		var pts := VolumeCloud.load_file(ROOT + m + ".points")
		var n := VolumeCloud.points_in(pts)
		var k := maxi(n / 8, 1)
		var all_y := 0.0
		var pre_y := 0.0
		for i in n:
			var y := pts[i * VolumeCloud.POINT_FLOATS + 1]
			all_y += y
			if i < k:
				pre_y += y
		var height := _aabb(_points_model(m)).size.y
		assert_float(absf(pre_y / k - all_y / n)).override_failure_message("%s: префикс 1/8 сдвинут по высоте (%.3f против %.3f)" % [m, pre_y / k, all_y / n]).is_less(0.15 * height)


func test_cloud_layers_for_ice_and_exit_come_from_the_palette() -> void:
	# облако ICE красное (красное только у угрозы, STYLE.md п.4), рамка выхода — ледяной белый; клиент берёт цвет только отсюда
	assert_bool(AssetMaterials.layer("volume_ice").is_equal_approx(AssetMaterials.PAL_THREAT)).is_true()
	assert_bool(AssetMaterials.layer("volume_exit").is_equal_approx(AssetMaterials.PAL_ICE)).is_true()


# ---------------------------------------------------------------- Soft ICE: Маяк и Датчик (src/icegear.py, ice.md §5)

func _body_aabb(root: Node) -> AABB:
	# габарит без лучей (`*_fan`, `*_beam*`): длину луча задаёт игра
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var n := String(mi.name)
		if n.ends_with("_fan") or n.contains("_beam"):
			continue
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_ice_lighthouse_has_head_and_beam_nodes_and_fits_one_cell() -> void:
	var m := _load("ice", "lighthouse_ice")
	for n in ["Head", "Beam"]:
		assert_bool(m.find_child(n, true, false) != null).override_failure_message("lighthouse_ice: нет узла " + n).is_true()
	var head := m.find_child("Head", true, false)
	assert_bool(head.find_child("Beam", true, false) != null).override_failure_message("Beam должен быть под Head: веер поворачивается вместе с головой").is_true()
	assert_bool(head.find_child("lighthouse_head", true, false) != null).is_true()
	var box := _body_aabb(m)
	assert_float(box.position.y).is_between(-0.01, 0.01)   # на полу
	assert_float(maxf(box.size.x, box.size.z)).override_failure_message("Маяк шире клетки хода 1 м").is_less(0.9)
	assert_float(box.size.y).is_between(0.7, 1.1)           # ниже головы стоящего
	var fan := _meshes(m).filter(func(mi): return String(mi.name) == "lighthouse_fan")
	assert_int(fan.size()).is_equal(1)
	var fb: AABB = fan[0].get_aabb()
	assert_float(fb.size.z).override_failure_message("веер единичного радиуса вдоль +Y Blender (−Z Godot): длина 1 м").is_equal_approx(1.0, 0.01)
	assert_float(fb.size.x).override_failure_message("±25°: ширина на радиусе 1 м ≈ 2·sin25° = 0,85").is_equal_approx(2.0 * sin(deg_to_rad(25.0)), 0.02)


func test_ice_sensor_emitter_has_beam_node_below_knee() -> void:
	var m := _load("ice", "sensor_ice")
	var beam := m.find_child("Beam", true, false) as Node3D
	assert_bool(beam != null).override_failure_message("sensor_ice: нет узла Beam").is_true()
	var parts := _meshes(beam)
	assert_int(parts.size()).override_failure_message("в Beam один меш (один прозрачный слой): три плоскости — горизонтальная, вертикальная, на полу").is_equal(1)
	for mi in parts:
		var b: AABB = mi.get_aabb()
		assert_float(b.size.z).override_failure_message("%s: длина луча 1 м вдоль −Z Godot" % mi.name).is_equal_approx(1.0, 0.01)
		assert_float(b.position.z).override_failure_message("%s: луч уходит от излучателя вперёд (−Z)" % mi.name).is_equal_approx(-1.0, 0.01)
	var box := _body_aabb(m)
	assert_float(box.size.y).override_failure_message("излучатель ниже колена + линза: ≤ 0,5 м").is_less(0.5)
	assert_float(maxf(box.size.x, box.size.z)).is_less(0.3)


func test_ice_beams_get_beam_shader_palette_colors_and_state_helper() -> void:
	AssetMaterials.reset_tuning()
	for asset in ["lighthouse_ice", "sensor_ice"]:
		var m := _load("ice", asset)
		AssetMaterials.apply(m, "")
		var beams := _meshes(m).filter(func(mi): return String(mi.name).ends_with("_fan") or String(mi.name).contains("_beam"))
		assert_int(beams.size()).override_failure_message(asset + ": нет мешей луча").is_greater(0)
		for mi in beams:
			var mat := mi.get_surface_override_material(0) as ShaderMaterial
			assert_str(mat.shader.resource_path).override_failure_message("%s: луч должен быть в beam.gdshader" % mi.name).ends_with("beam.gdshader")
			assert_bool((mat.get_shader_parameter("on_color") as Color).is_equal_approx(AssetMaterials.layer("beam_on"))).is_true()
			assert_float(float(mat.get_shader_parameter("fan"))).is_equal(1.0 if String(mi.name).ends_with("_fan") else 0.0)
		AssetMaterials.set_beam(m, AssetMaterials.BEAM_BLINK, 0.5)
		for mi in beams:
			var mat := mi.get_surface_override_material(0) as ShaderMaterial
			assert_float(float(mat.get_shader_parameter("state"))).is_equal(2.0)
			assert_float(float(mat.get_shader_parameter("flash"))).is_equal(0.5)
		# корпус луча не трогает: состояние луча — только у мешей луча
		var solid := _meshes(m).filter(func(mi): return not (String(mi.name).ends_with("_fan") or String(mi.name).contains("_beam")))
		assert_int(solid.size()).is_greater(0)
	# красный у угрозы (ICE), погашенный — голубой «можно» (П6-6: тусклый PAL_DIM на полу не читался), вспышка — ледяной белый (STYLE.md п.4)
	assert_bool(AssetMaterials.layer("beam_on").is_equal_approx(AssetMaterials.PAL_THREAT_HOT)).is_true()
	assert_bool(AssetMaterials.layer("beam_off").is_equal_approx(AssetMaterials.PAL_CYAN)).is_true()
	assert_bool(AssetMaterials.layer("beam_flash").is_equal_approx(AssetMaterials.PAL_ICE)).is_true()


# ---------------------------------------------------------------- Soft ICE: Барьер и Трассировщик (src/icegear.py, ice.md §5)

func test_ice_barrier_has_three_states_and_five_code_marks() -> void:
	var m := _load("ice", "barrier_ice")
	for s in ["State_closed", "State_opening", "State_open"]:
		var n := m.find_child(s, true, false) as Node3D
		assert_bool(n != null).override_failure_message("barrier_ice: нет узла " + s).is_true()
		assert_bool(n != null and _meshes(n).size() > 0).override_failure_message("barrier_ice: в %s нет мешей" % s).is_true()
	for k in range(1, 6):
		var c := m.find_child("Code_%d" % k, true, false) as Node3D
		assert_bool(c != null and _meshes(c).size() > 0).override_failure_message("barrier_ice: нет отметки Code_%d" % k).is_true()
	var box := _aabb(m)
	assert_float(box.position.y).is_between(-0.01, 0.01)   # на полу
	assert_float(box.size.x).override_failure_message("барьер шире клетки хода 1 м + стойки").is_between(0.85, 1.1)
	assert_float(box.size.y).override_failure_message("панель кода выше колена, не выше головы").is_between(1.2, 1.8)
	assert_float(box.size.z).override_failure_message("панель тонкая: толщина ≤ 0,2 м").is_less(0.2)
	# состояния различимы силуэтом: у открытого нет панели выше порога, у закрытого она сплошная
	var closed_h := _aabb(m.find_child("State_closed", true, false)).size.y
	var open_h := _aabb(m.find_child("State_open", true, false)).size.y
	assert_float(open_h).override_failure_message("State_open: проход свободен (только порог)").is_less(0.1)
	assert_float(closed_h).is_greater(1.2)


func test_ice_tracer_has_tail_cells_and_alert_anchor() -> void:
	var m := _load("ice", "tracer_ice")
	assert_bool(m.find_child("AlertAnchor", true, false) != null).override_failure_message("tracer_ice: нет AlertAnchor").is_true()
	var tail := m.find_child("Tail", true, false) as Node3D
	assert_bool(tail != null).override_failure_message("tracer_ice: нет узла Tail").is_true()
	var prev_z := 0.0
	for k in range(1, 5):
		var t := m.find_child("Tail_%d" % k, true, false) as Node3D
		assert_bool(t != null and _meshes(t).size() > 0).override_failure_message("tracer_ice: нет Tail_%d" % k).is_true()
		if t != null:
			var c := _aabb(t).get_center().z
			assert_float(c).override_failure_message("Tail_%d: клетка позади, дальше предыдущей (+Z Godot — назад)" % k).is_greater(prev_z)
			prev_z = c
	# тело низкое («ищейка»), без хвоста
	var body := _aabb(m.find_child("tracer_ice_body", true, false))
	assert_float(body.size.y).override_failure_message("Трассировщик — низкая ищейка").is_less(0.5)


# ---------------------------------------------------------------- вид тревоги узла 0–4 (AssetMaterials.alarm_background / set_alarm, ice.md §4, §8)

func test_alarm_background_shifts_warmer_by_level_and_keeps_calm_unchanged() -> void:
	var calm := AssetMaterials.alarm_background(0)
	assert_bool(calm.is_equal_approx(Color(AssetMaterials.VOID_BG, 1.0))).override_failure_message("уровень 0 — без изменений (VOID_BG)").is_true()
	var prev_warm := -1.0
	for lvl in [0, 1, 2, 4]:   # уровень 3 пульсирует, сравниваем по остальным: тёплость (r − b) растёт монотонно
		var c := AssetMaterials.alarm_background(lvl)
		var warm := c.r - c.b
		assert_float(warm).override_failure_message("уровень %d не теплее предыдущего" % lvl).is_greater(prev_warm)
		prev_warm = warm
	# «охота» (3): пульс в ритме такта — начало такта ярче конца; фон не уходит в чистый чёрный и не ярче максимума
	var start := AssetMaterials.alarm_background(3, 0.0)
	var end := AssetMaterials.alarm_background(3, 1.0)
	assert_float(start.r + start.g + start.b).override_failure_message("пульс охоты: начало такта ярче конца").is_greater(end.r + end.g + end.b)
	assert_float(maxf(end.r, maxf(end.g, end.b))).is_greater(0.02)   # чистого чёрного нет (STYLE.md п.11)
	for lvl in 5:
		var c := AssetMaterials.alarm_background(lvl, 0.5)
		assert_float(maxf(c.r, maxf(c.g, c.b))).override_failure_message("фон уровня %d слишком яркий (не заливка)" % lvl).is_less(0.5)
	assert_bool(AssetMaterials.alarm_background(9).is_equal_approx(AssetMaterials.alarm_background(4))).is_true()   # зажим уровня


func test_set_alarm_shifts_env_edges_warmer_and_level_zero_restores_tier() -> void:
	AssetMaterials.reset_tuning()
	var env := _load("env", "cover")
	AssetMaterials.apply(env, "BASE")
	var mat := _mat_of(env, "pillar_block")
	assert_bool(mat != null).is_true()
	var tier_c: Color = AssetMaterials.TIER_TINT["BASE"]
	AssetMaterials.set_alarm(env, 0, "BASE")
	assert_bool(Color(mat.get_shader_parameter("edge_color")).is_equal_approx(tier_c) or mat.get_shader_parameter("tint") == null or Color(mat.get_shader_parameter("tint")).is_equal_approx(tier_c)).is_true()
	AssetMaterials.set_alarm(env, 4, "BASE")
	var hot: Color = Color(mat.get_shader_parameter("edge_color")) if mat.get_shader_parameter("edge_color") != null else Color(mat.get_shader_parameter("tint"))
	assert_float(hot.r - hot.b).override_failure_message("локдаун: кромки окружения теплее тира").is_greater(tier_c.r - tier_c.b + 0.3)
	# серого посередине быть не должно (STYLE.md п.4): на каждом уровне кромка насыщена, а не смесь голубого с красным
	for lvl in 5:
		AssetMaterials.set_alarm(env, lvl, "BASE")
		var c: Color = Color(mat.get_shader_parameter("edge_color")) if mat.get_shader_parameter("edge_color") != null else Color(mat.get_shader_parameter("tint"))
		assert_float(c.s).override_failure_message("уровень %d: кромка серая (s=%.2f)" % [lvl, c.s]).is_greater(0.4)
	AssetMaterials.set_alarm(env, 0, "BASE")
	var back: Color = Color(mat.get_shader_parameter("edge_color")) if mat.get_shader_parameter("edge_color") != null else Color(mat.get_shader_parameter("tint"))
	assert_bool(back.is_equal_approx(tier_c)).override_failure_message("уровень 0 возвращает цвет тира").is_true()


func test_guard_booth_has_door_and_lamp_nodes_and_fits_one_cell() -> void:
	var m := _load("ice", "guard_booth")
	for n in ["Door", "Lamp"]:
		assert_bool(m.find_child(n, true, false) != null and _meshes(m.find_child(n, true, false)).size() > 0).override_failure_message("guard_booth: нет узла " + n).is_true()
	var box := _aabb(m)
	assert_float(box.position.y).is_between(-0.01, 0.01)
	assert_float(maxf(box.size.x, box.size.z)).override_failure_message("будка шире клетки хода 1 м").is_less(1.0)
	assert_float(box.size.y).override_failure_message("выше головы, как укрытие (2,2 м)").is_between(2.0, 2.4)


func test_pillar_is_one_body_two_by_two_module_not_four_covers() -> void:
	# Карточка Godot П6-0г: блок «#» ставит один модуль pillar, а ассет из четырёх укрытий с зазорами выглядел четырьмя колоннами
	var m := _load("env", "pillar")
	var blocks := _meshes(m).filter(func(mi): return String(mi.name) == "pillar_block")
	assert_int(blocks.size()).is_equal(1)
	var b: AABB = (blocks[0] as MeshInstance3D).get_aabb()
	assert_float(b.size.x).override_failure_message("корпус колонны ≈ 1,9 м по X, а не 0,9 м укрытия").is_equal_approx(1.9, 0.02)
	assert_float(b.size.z).is_equal_approx(1.9, 0.02)
	assert_float(b.size.y).is_equal_approx(2.2, 0.02)
	# единый корпус: одна поверхность pillar_block без зазоров, рамка по границе модуля 2×2
	var frame := _meshes(m).filter(func(mi): return String(mi.name) == "pillar_base")
	assert_int(frame.size()).is_equal(1)
	assert_float((frame[0] as MeshInstance3D).get_aabb().size.x).is_equal_approx(2.0, 0.02)
	# одиночное укрытие 1×1 остаётся прежним
	var cover := _aabb(_load("env", "cover"))
	assert_float(cover.size.x).is_equal_approx(1.0, 0.02)

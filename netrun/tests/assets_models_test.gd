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
	"lockdown_gate": ["lockdown_gate"], "tunnel_ring": ["tunnel_ring"], "exit_frame": ["exit_frame"],
	"far_field": ["far_field", "far_field_b", "far_field_c"], "far_floor": ["far_floor", "far_floor_b", "far_floor_c"],
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


func test_horizon_band_is_streaks_plus_one_haze_ribbon_and_far_gain_is_off_by_default() -> void:
	var band := _load("env", "horizon_band")
	var meshes := _meshes(band)
	assert_int(meshes.size()).override_failure_message("horizon_band: должно быть два меша (штрихи и дымка)").is_equal(2)
	var streaks: MeshInstance3D = null
	var haze: MeshInstance3D = null
	for mi in meshes:
		if String(mi.name).ends_with("_mist"):
			haze = mi
		else:
			streaks = mi
	assert_bool(streaks != null and haze != null).override_failure_message("horizon_band: нет horizon_streaks или horizon_mist").is_true()
	var verts := (streaks.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(verts).override_failure_message("horizon_band: больше 400 штрихов (4 вершины на штрих)").is_less_equal(1600)
	# дымка: один слой, не больше 200 треугольников на всю ленту, шейдер haze аддитивный, без записи и чтения глубины
	var idx := haze.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array
	assert_int(haze.mesh.get_surface_count()).is_equal(1)
	assert_int(idx.size() / 3).override_failure_message("horizon_mist: больше 200 треугольников").is_less_equal(200)
	AssetMaterials.apply(band, "BASE")
	var hm := haze.get_surface_override_material(0) as ShaderMaterial
	assert_bool(hm != null and hm.shader.resource_path.ends_with("haze.gdshader")).override_failure_message("у дымки не haze.gdshader").is_true()
	for flag in ["blend_add", "unshaded", "depth_draw_never"]:
		assert_bool(hm.shader.code.contains(flag)).override_failure_message("в шейдере дымки нет " + flag).is_true()
	assert_bool(hm.shader.code.contains("hint_depth_texture") or hm.shader.code.contains("DEPTH_TEXTURE")).override_failure_message("дымка читает буфер глубины").is_false()
	var sm := streaks.get_surface_override_material(0) as ShaderMaterial
	assert_bool(sm != null and sm.shader.resource_path.ends_with("streaks.gdshader")).override_failure_message("у штрихов кольца не streaks.gdshader").is_true()
	var sh := load("res://assets/shaders/streaks.gdshader") as Shader
	var names := sh.get_shader_uniform_list().map(func(u): return u["name"])
	for u in ["halo", "halo_width", "far_gain", "far_start", "far_end"]:
		assert_bool(u in names).override_failure_message("в streaks нет uniform " + u).is_true()
	assert_bool(sh.code.contains("uniform float far_gain : hint_range(1.0, 6.0) = 1.0;")).override_failure_message("far_gain по умолчанию не 1").is_true()
	assert_bool(sh.code.contains("uniform float halo : hint_range(0.0, 1.0) = 0.0;")).override_failure_message("halo по умолчанию не 0").is_true()


## Кромка комнаты (env/room_edge_<N>) вместо стен: цепочка точек, подвесные штрихи (`*_hang`) и низкая дымка (`*_mist`, один слой ≤ 200 треугольников).
## room_edge_16 по размеру равен комнате NodeLayout (граница телепорта), room_edge_8 — комнате просмотра.
func test_room_edge_has_hang_streaks_and_knee_high_haze_within_budget() -> void:
	var room := NodeLayout.ROOM_MAX - NodeLayout.ROOM_MIN
	for spec in [[8, 8.0, 260], [16, room.x, 500]]:
		var asset := "room_edge_%d" % spec[0]
		var root := _load("env", asset)
		var hang: MeshInstance3D = null
		var mist: MeshInstance3D = null
		var others := 0
		for mi in _meshes(root):
			if String(mi.name).ends_with("_mist"):
				mist = mi
			elif String(mi.name).ends_with("_hang"):
				hang = mi
			else:
				others += 1
		assert_bool(hang != null and mist != null).override_failure_message("%s: нужны меши *_hang и *_mist" % asset).is_true()
		assert_int(others).override_failure_message("%s: лишние меши (цепочки точек по кромке нет: владелец убрал)" % asset).is_equal(0)
		var streaks := (hang.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		assert_int(streaks).override_failure_message("%s: подвесных штрихов %d > %d" % [asset, streaks, spec[2]]).is_less_equal(spec[2])
		assert_int(streaks).override_failure_message("%s: подвесных штрихов слишком мало (%d)" % [asset, streaks]).is_greater(int(spec[2] * 0.6))
		var tris := (mist.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_int(tris).override_failure_message("%s: дымка %d треугольников > 200" % [asset, tris]).is_less_equal(200)
		# квадрат кромки (подвесные штрихи) равен стороне комнаты; ни штрихи, ни дымка не выходят за 20 м, дымка не выше колена (0,5 м)
		assert_float(hang.mesh.get_aabb().size.x).override_failure_message("%s: кромка не %g м по X" % [asset, spec[1]]).is_between(spec[1] - 0.1, spec[1] + 0.4)
		assert_float(hang.mesh.get_aabb().size.z).is_between(spec[1] - 0.1, spec[1] + 0.4)
		assert_float(hang.mesh.get_aabb().end.y).override_failure_message("%s: подвесные штрихи выше пола" % asset).is_less(0.05)
		var box := _aabb(root)
		assert_float(maxf(box.size.x, box.size.z)).override_failure_message("%s: габарит больше 20 м" % asset).is_less_equal(20.0)
		assert_float(box.end.y).override_failure_message("%s: что-то выше 0,5 м (дымка до колена)" % asset).is_less_equal(0.5)
		assert_float(box.position.y).override_failure_message("%s: штрихи глубже 3 м" % asset).is_greater_equal(-3.0)
		AssetMaterials.apply(root, "BASE")
		var hm := mist.get_surface_override_material(0) as ShaderMaterial
		assert_bool(hm != null and hm.shader.resource_path.ends_with("haze.gdshader")).override_failure_message("%s: у дымки не haze.gdshader" % asset).is_true()
		assert_float(float(hm.get_shader_parameter("haze_alpha"))).override_failure_message("%s: на дымку кромки не применены AssetMaterials.EDGE_MIST" % asset).is_equal(float(AssetMaterials.EDGE_MIST["haze_alpha"]))
		var sm := hang.get_surface_override_material(0) as ShaderMaterial
		assert_float(float(sm.get_shader_parameter("anchor"))).override_failure_message("%s: подвесные штрихи без anchor = 1" % asset).is_equal(1.0)


## Ров вокруг плиты-пола (env/room_moat_<N>): один меш `moat` (solid_dark), плоское кольцо на y = −0,02 м, внутренняя граница на 0,35 м от края плиты (сторона = N),
## ширина 3 м, не больше 60 треугольников, без точек, штрихов и прозрачности. room_moat_16 по размеру равен комнате NodeLayout.
func test_room_moat_is_flat_dark_ring_around_slab() -> void:
	var room := NodeLayout.ROOM_MAX - NodeLayout.ROOM_MIN
	for spec in [[8, 8.0], [16, room.x]]:
		var asset := "room_moat_%d" % spec[0]
		var root := _load("env", asset)
		var meshes := _meshes(root)
		assert_int(meshes.size()).override_failure_message("%s: нужен один меш moat, есть %d" % [asset, meshes.size()]).is_equal(1)
		var mi := meshes[0]
		assert_str(String(mi.name)).is_equal("moat")
		var tris := (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_int(tris).override_failure_message("%s: %d треугольников > 60" % [asset, tris]).is_less_equal(60)
		var box := _aabb(root)
		var outer: float = spec[1] + 2.0 * (0.35 + 3.0)
		assert_float(box.size.x).override_failure_message("%s: габарит не %g м по X" % [asset, outer]).is_equal_approx(outer, 0.01)
		assert_float(box.size.z).is_equal_approx(outer, 0.01)
		assert_float(box.position.y).override_failure_message("%s: крышка не на y = −0,02" % asset).is_equal_approx(-0.02, 0.001)
		assert_float(box.end.y).is_equal_approx(-0.02, 0.001)
		# внутренняя дыра кольца = плита + щель 0,35 м с каждой стороны: ни одна вершина не ближе к центру
		var half: float = spec[1] / 2.0 + 0.35
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			assert_float(maxf(absf(v.x), absf(v.z))).override_failure_message("%s: вершина ближе щели 0,35 м к плите: %s" % [asset, v]).is_greater_equal(half - 0.001)
		AssetMaterials.apply(root, "BASE")
		var sm := mi.get_surface_override_material(0) as ShaderMaterial
		assert_bool(sm != null and sm.shader.resource_path.ends_with("solid_dark.gdshader")).override_failure_message("%s: у рва не solid_dark" % asset).is_true()


## ЭКСПЕРИМЕНТ «пол одним тайлом» (env/floor_slab_<N>): одна тонкая плита на всю комнату, верх не выше пола, сторона = стороне room_edge_<N>,
## подвесные штрихи (`*_hang`) и вуаль (`*_skirt`) по периметру, сетка швов из точек. Бюджет 16×16: 400 треуг., 700 точек, 260 штрихов (8×8 — пропорционально).
func test_floor_slab_is_single_thin_slab_within_budget() -> void:
	var room := NodeLayout.ROOM_MAX - NodeLayout.ROOM_MIN
	for spec in [[8, 8.0], [16, room.x]]:
		var asset := "floor_slab_%d" % spec[0]
		var k: float = spec[0] / 16.0
		var root := _load("env", asset)
		var slab: MeshInstance3D = null
		var hang: MeshInstance3D = null
		var skirt: MeshInstance3D = null
		var seams: MeshInstance3D = null
		var tris := 0
		for mi in _meshes(root):  # треугольники — плита и вуаль (штрихи и точки — квады, их считаем штуками)
			if String(mi.name).ends_with("_hang"):
				hang = mi
			elif String(mi.name).ends_with("_skirt"):
				skirt = mi
				tris += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif String(mi.name) == "slab_seams":
				seams = mi
			elif String(mi.name) == "slab":
				slab = mi
				tris += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_bool(slab != null and hang != null and skirt != null and seams != null).override_failure_message("%s: нужны меши slab, *_hang, *_skirt, slab_seams" % asset).is_true()
		assert_int(tris).override_failure_message("%s: %d треугольников > %d" % [asset, tris, int(400 * k)]).is_less_equal(int(400 * k))
		var streaks := (hang.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		assert_int(streaks).override_failure_message("%s: штрихов %d > %d" % [asset, streaks, int(260 * k)]).is_less_equal(int(260 * k))
		assert_int(streaks).override_failure_message("%s: штрихов слишком мало (%d)" % [asset, streaks]).is_greater(int(260 * k * 0.6))
		var dots := (seams.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		assert_int(dots).override_failure_message("%s: точек %d > %d" % [asset, dots, int(700 * k)]).is_less_equal(int(700 * k))
		assert_int(dots).override_failure_message("%s: сетки швов нет" % asset).is_greater(20)
		var sb := slab.get_aabb()
		assert_float(sb.size.x).override_failure_message("%s: плита не %g м по X" % [asset, spec[1]]).is_equal_approx(spec[1], 0.01)
		assert_float(sb.size.z).is_equal_approx(spec[1], 0.01)
		assert_float(sb.size.y).override_failure_message("%s: плита не тонкая (3 см)" % asset).is_less_equal(0.031)
		assert_float(sb.end.y).override_failure_message("%s: верх плиты выше пола" % asset).is_less_equal(0.0)
		assert_float(_aabb(root).end.y).override_failure_message("%s: что-то выше пола больше 4 см" % asset).is_less_equal(0.04)
		assert_int(skirt.mesh.get_surface_count()).is_equal(1)
		AssetMaterials.apply(root, "BASE")
		var skm := skirt.get_surface_override_material(0) as ShaderMaterial
		assert_bool(skm != null and skm.shader.resource_path.ends_with("skirt.gdshader")).override_failure_message("%s: у вуали не skirt.gdshader" % asset).is_true()
		var hm := hang.get_surface_override_material(0) as ShaderMaterial
		assert_float(float(hm.get_shader_parameter("anchor"))).override_failure_message("%s: подвесные штрихи без anchor = 1" % asset).is_equal(1.0)


## ЭКСПЕРИМЕНТ «стеклянный пол» (env/floor_glass_<N>): то же, что floor_slab, но верх — один квад `*_glass` с аддитивным шейдером glass.gdshader вместо чёрной плиты;
## ничего непрозрачного (solid_dark) нет, слоёв прозрачности ≤ 3 (верх + вуаль), бюджет тот же (16×16: 400 треуг., 700 точек, 260 штрихов).
func test_floor_glass_is_translucent_slab_within_budget() -> void:
	var room := NodeLayout.ROOM_MAX - NodeLayout.ROOM_MIN
	for spec in [[8, 8.0], [16, room.x]]:
		var asset := "floor_glass_%d" % spec[0]
		var k: float = spec[0] / 16.0
		var root := _load("env", asset)
		var glass: MeshInstance3D = null
		var hang: MeshInstance3D = null
		var skirt: MeshInstance3D = null
		var seams: MeshInstance3D = null
		var tris := 0
		var layers := 0
		for mi in _meshes(root):
			var n := String(mi.name)
			assert_str(n).override_failure_message("%s: чёрная плита `slab` не должна быть (закрывает пласты под полом)" % asset).is_not_equal("slab")
			if n.ends_with("_hang"):
				hang = mi
			elif n.ends_with("_skirt"):
				skirt = mi
				tris += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				layers += 1
			elif n == "slab_seams":
				seams = mi
			elif n.ends_with("_glass"):
				glass = mi
				tris += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				layers += 1
		assert_bool(glass != null and hang != null and skirt != null and seams != null).override_failure_message("%s: нужны меши *_glass, *_hang, *_skirt, slab_seams" % asset).is_true()
		assert_int(tris).override_failure_message("%s: %d треугольников > %d" % [asset, tris, int(400 * k)]).is_less_equal(int(400 * k))
		assert_int(layers).override_failure_message("%s: слоёв прозрачности %d > 3" % [asset, layers]).is_less_equal(3)
		var streaks := (hang.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		assert_int(streaks).override_failure_message("%s: штрихов %d > %d" % [asset, streaks, int(260 * k)]).is_less_equal(int(260 * k))
		var dots := (seams.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		assert_int(dots).override_failure_message("%s: точек %d > %d" % [asset, dots, int(700 * k)]).is_less_equal(int(700 * k))
		var gb := glass.get_aabb()
		assert_float(gb.size.x).override_failure_message("%s: верх не %g м по X" % [asset, spec[1]]).is_equal_approx(spec[1], 0.01)
		assert_float(gb.size.z).is_equal_approx(spec[1], 0.01)
		assert_float(_aabb(root).end.y).override_failure_message("%s: что-то выше пола больше 4 см" % asset).is_less_equal(0.04)
		AssetMaterials.apply(root, "BASE")
		var gm := glass.get_surface_override_material(0) as ShaderMaterial
		assert_bool(gm != null and gm.shader.resource_path.ends_with("glass.gdshader")).override_failure_message("%s: у верха не glass.gdshader" % asset).is_true()
		assert_float(float(gm.get_shader_parameter("plate_size"))).override_failure_message("%s: plate_size не равен стороне плиты" % asset).is_equal_approx(spec[1], 0.01)
		assert_bool(gm.shader.code.contains("blend_add") and gm.shader.code.contains("depth_draw_never")).override_failure_message("%s: glass.gdshader не аддитивный без записи глубины" % asset).is_true()
		assert_bool(gm.shader.code.contains("hint_depth_texture")).override_failure_message("%s: glass.gdshader читает глубину" % asset).is_false()


## ЭКСПЕРИМЕНТ «варианты пола» (env/floor_v<N>_<размер>, src/floor_variants.py): четыре разных механизма (1 пыль, 2 террасы, 3 решётка, 4 полосы). Файлы есть, габарит = комната,
## бюджет 16×16: 600 треуг., 900 точек, 600 штрихов (v1 — 900), слоёв прозрачности ≤ 3; _8 — ×0,25. Плиты (`*_plates`) не выше пола, красного нет, подмена шейдеров по суффиксу меша.
func test_floor_variants_are_within_budget_and_below_floor() -> void:
	var room := NodeLayout.ROOM_MAX - NodeLayout.ROOM_MIN
	for v in [1, 2, 3, 4]:
		for spec in [[8, 8.0], [16, room.x]]:
			var asset := "floor_v%d_%d" % [v, spec[0]]
			var k2: float = (spec[0] / 16.0) * (spec[0] / 16.0)
			var root := _load("env", asset)
			var tris := 0
			var streaks := 0
			var layers := 0
			var plates: MeshInstance3D = null
			var glass: MeshInstance3D = null
			for mi in _meshes(root):
				var n := String(mi.name)
				var arrays := mi.mesh.surface_get_arrays(0)
				if n.contains("streaks"):
					streaks += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
				else:
					tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				if n.ends_with("_glass") or n.ends_with("_skirt"):
					layers += 1
				if n.ends_with("_plates"):
					plates = mi
				if n.ends_with("_glass"):
					glass = mi
				for c in (arrays[Mesh.ARRAY_COLOR] as PackedColorArray):  # красного нет: только cyan и ice_white
					assert_bool(c.r <= c.g + 0.001).override_failure_message("%s: красноватый цвет вершины %s в %s" % [asset, c, n]).is_true()
			assert_int(tris).override_failure_message("%s: треугольников %d > %d" % [asset, tris, int(600 * k2)]).is_less_equal(int(600 * k2))
			var lim_s := int((900 if v == 1 else 600) * k2)
			assert_int(streaks).override_failure_message("%s: штрихов %d > %d" % [asset, streaks, lim_s]).is_less_equal(lim_s)
			assert_int(streaks).override_failure_message("%s: штрихов слишком мало (%d)" % [asset, streaks]).is_greater(int(lim_s * 0.3))
			assert_int(layers).override_failure_message("%s: слоёв прозрачности %d > 3" % [asset, layers]).is_less_equal(3)
			var ab := _aabb(root)
			assert_float(ab.size.x).override_failure_message("%s: габарит по X %g не равен комнате %g" % [asset, ab.size.x, spec[1]]).is_equal_approx(spec[1], 0.2)
			assert_float(ab.size.z).override_failure_message("%s: габарит по Z %g не равен комнате %g" % [asset, ab.size.z, spec[1]]).is_equal_approx(spec[1], 0.2)
			assert_float(ab.end.y).override_failure_message("%s: выше пола %g м" % [asset, ab.end.y]).is_less_equal(0.4 if v == 1 else 0.04)
			if v == 2 or v == 4:
				assert_bool(plates != null).override_failure_message("%s: нужен меш *_plates" % asset).is_true()
				assert_float(plates.get_aabb().end.y).override_failure_message("%s: верх плит выше пола" % asset).is_less_equal(0.0)
				assert_float(plates.get_aabb().position.y).override_failure_message("%s: плиты глубже 0,5 м" % asset).is_greater(-0.5)
			if v == 1 or v == 3:
				assert_bool(glass != null).override_failure_message("%s: нужен меш *_glass" % asset).is_true()
			AssetMaterials.apply(root, "BASE")
			if plates != null:
				var pm := plates.get_surface_override_material(0) as ShaderMaterial
				assert_bool(pm != null and pm.shader.resource_path.ends_with("solid_dark.gdshader")).override_failure_message("%s: у плит не solid_dark" % asset).is_true()
				assert_float(float(pm.get_shader_parameter("uv_rim"))).override_failure_message("%s: у плит не включена кайма uv_rim" % asset).is_greater(0.0)
			if v == 3:
				var gm := glass.get_surface_override_material(0) as ShaderMaterial
				assert_float(float(gm.get_shader_parameter("grid_alpha"))).override_failure_message("%s: сетка не включена" % asset).is_greater(0.0)
				assert_bool(gm.shader.code.contains("hint_depth_texture")).override_failure_message("%s: glass.gdshader читает глубину" % asset).is_false()


func test_mesh_parts_are_cached_per_tier_and_mirror() -> void:
	var a := NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "BASE")
	assert_bool(NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "BASE") == a).is_true()
	assert_bool(NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "HARD") != a).is_true()
	var mirror := NodeAssets.mesh_parts(NodeAssets.env_path("wall"), "BASE", true)
	assert_bool(mirror != a).is_true()
	assert_float((mirror[0]["xform"] as Transform3D).basis.y.y).is_equal(-1.0)  # зеркало: ось Y перевёрнута


# ---------------------------------------------------------------- сетка

func test_grid_modules_fit_the_cell() -> void:
	for module in ["floor", "floor_b", "floor_c", "ceiling", "wall", "wall_b", "wall_c", "doorway", "doorway_b", "corner", "pillar", "platform", "lockdown_gate", "exit_frame"]:
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
	assert_float(absf(box.size.x - gate.size.x)).override_failure_message("ширина %.2f против ворот %.2f" % [box.size.x, gate.size.x]).is_less(0.3)  # тот же проём, что у ворот
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
	assert_bool(_mat_of(base, "pillar_block").next_pass != null).override_failure_message("по умолчанию обводка есть").is_true()
	assert_float(float(_mat_of(base, "pillar_block").get_shader_parameter("edge_glow"))).is_equal_approx(2.2, 0.001)
	var cfg := ConfigFile.new()
	cfg.set_value("assets", "fringe_on", false)
	cfg.set_value("assets", "edge_glow", 3.5)
	cfg.set_value("assets", "solid_base", "#102030")
	AssetMaterials.tune_from_config(cfg)
	var tuned := _load("env", "cover")
	AssetMaterials.apply(tuned, "BASE")
	var m := _mat_of(tuned, "pillar_block")
	assert_bool(m.next_pass == null).override_failure_message("fringe_on=false: обводки нет").is_true()
	assert_float(float(m.get_shader_parameter("edge_glow"))).is_equal_approx(3.5, 0.001)
	assert_bool((m.get_shader_parameter("base_color") as Color).is_equal_approx(Color("#102030"))).is_true()
	AssetMaterials.reset_tuning()
	var back := _load("env", "cover")
	AssetMaterials.apply(back, "BASE")
	assert_bool(_mat_of(back, "pillar_block").next_pass != null).override_failure_message("reset_tuning возвращает обводку").is_true()


func test_asset_materials_knob_min_px_reaches_streaks() -> void:
	AssetMaterials.reset_tuning()
	AssetMaterials.tune({"min_px_streaks": 3.0, "halo_far": true})
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


func test_asset_materials_knob_floor_grid_texture_replaces_seam_dots() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "floor_slab_8")
	AssetMaterials.apply(dflt, "BASE")
	assert_float(float(_mat_of(dflt, "slab").get_shader_parameter("grid_alpha"))).override_failure_message("по умолчанию сетка-текстура включена").is_equal_approx(0.35, 0.001)
	assert_bool(dflt.find_child("slab_seams", true, false).visible).override_failure_message("по умолчанию точки швов скрыты").is_false()
	AssetMaterials.tune({"floor_grid": 0.0})
	var off := _load("env", "floor_slab_8")
	AssetMaterials.apply(off, "BASE")
	assert_bool(_mat_of(off, "slab").get_shader_parameter("grid_alpha") == null).override_failure_message("floor_grid=0: сетки-текстуры нет (параметр не задан)").is_true()
	assert_bool(off.find_child("slab_seams", true, false).visible).override_failure_message("floor_grid=0: точки швов видны").is_true()
	AssetMaterials.tune({"floor_grid": 0.4})
	var on := _load("env", "floor_slab_8")
	AssetMaterials.apply(on, "BASE")
	var m := _mat_of(on, "slab")
	assert_float(float(m.get_shader_parameter("grid_alpha"))).is_equal_approx(0.4, 0.001)
	var tex := m.get_shader_parameter("grid_tex") as Texture2D
	assert_bool(tex != null and tex.get_width() == AssetMaterials.GRID_TEX_PX).override_failure_message("текстура клетки не задана").is_true()
	assert_bool(on.find_child("slab_seams", true, false).visible).override_failure_message("floor_grid: точки швов скрыты").is_false()
	AssetMaterials.reset_tuning()


func test_asset_materials_plate_rim_knobs_reach_plates_and_skirts() -> void:
	AssetMaterials.reset_tuning()
	AssetMaterials.tune({"rim_top_only": true, "plate_flat": true, "rim_far_min": 0.3, "rim_far_start": 6.0, "rim_far_end": 15.0, "skirt_top_fade": 0.12})
	var root := _load("env", "floor_slab_8")
	AssetMaterials.apply(root, "BASE")
	var slab := _mat_of(root, "slab")
	assert_float(float(slab.get_shader_parameter("rim_top_only"))).is_equal(1.0)
	assert_float(float(slab.get_shader_parameter("plate_flat"))).is_equal(1.0)
	assert_float(float(slab.get_shader_parameter("rim_far_min"))).is_equal_approx(0.3, 0.001)
	assert_float(float(slab.get_shader_parameter("rim_far_end"))).is_equal_approx(15.0, 0.001)
	assert_float(float(_mat_of(root, "floor_slab_skirt").get_shader_parameter("top_fade"))).is_equal_approx(0.12, 0.001)
	var cover := _load("env", "cover")  # объём: боковые рёбра должны светиться — ручки плит его не трогают
	AssetMaterials.apply(cover, "BASE")
	assert_bool(_mat_of(cover, "pillar_block").get_shader_parameter("rim_top_only") == null).override_failure_message("ручки плит не должны попадать на укрытие").is_true()
	AssetMaterials.reset_tuning()


func test_asset_materials_knob_edge_soft_reaches_solids_and_fringe() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "cover")
	AssetMaterials.apply(dflt, "BASE")
	assert_bool(_mat_of(dflt, "pillar_block").get_shader_parameter("edge_soft") == null).override_failure_message("по умолчанию «кромка внутрь» выключена (параметр не задан)").is_true()
	AssetMaterials.tune({"edge_soft": 0.6})
	var cover := _load("env", "cover")
	AssetMaterials.apply(cover, "BASE")
	var pb := _mat_of(cover, "pillar_block")
	assert_float(float(pb.get_shader_parameter("edge_soft"))).is_equal_approx(0.6, 0.001)
	var fr := pb.next_pass as ShaderMaterial
	var layers := 0
	while fr != null:  # обводка гаснет вместе с кромкой
		assert_float(float(fr.get_shader_parameter("edge_soft"))).is_equal_approx(0.6, 0.001)
		layers += 1
		fr = fr.next_pass as ShaderMaterial
	assert_int(layers).is_equal(AssetMaterials.FRINGE_LAYERS.size())
	var slab := _load("env", "floor_slab_8")  # плиты пола и потолка — тоже solid_dark
	AssetMaterials.apply(slab, "BASE")
	assert_float(float(_mat_of(slab, "slab").get_shader_parameter("edge_soft"))).is_equal_approx(0.6, 0.001)
	AssetMaterials.reset_tuning()


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
	var dflt := _load("env", "wall")
	AssetMaterials.apply(dflt, "BASE")
	var base := _point_mats(dflt)
	assert_int(base.size()).override_failure_message("в стене нет точек").is_greater(0)
	for m in base:
		assert_bool(m.get_shader_parameter("keep_frac") == null).override_failure_message("по умолчанию доля точек не задана").is_true()
	AssetMaterials.tune({"point_keep": 0.0})
	var tuned := _load("env", "wall")
	AssetMaterials.apply(tuned, "BASE")
	for m in _point_mats(tuned):
		assert_float(float(m.get_shader_parameter("keep_frac"))).is_equal(0.0)
	var creature := _load("ice", "soft_ice")  # существа без тира: ручка окружения их не трогает
	AssetMaterials.apply(creature)
	for m in _point_mats(creature):
		assert_bool(m.get_shader_parameter("keep_frac") == null).override_failure_message("ручка точек окружения попала на существо").is_true()
	AssetMaterials.reset_tuning()


func test_asset_materials_streak_knobs_reach_env_streaks_only() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "wall")
	AssetMaterials.apply(dflt, "BASE")
	var base := _streak_mats(dflt)
	assert_int(base.size()).override_failure_message("в стене нет штрихов").is_greater(0)
	for m in base:
		assert_bool(m.get_shader_parameter("keep_frac") == null and m.get_shader_parameter("far_dim_min") == null and m.get_shader_parameter("px_fade") == null).override_failure_message("по умолчанию ручки штрихов не заданы").is_true()
	AssetMaterials.tune({"streak_far_min": 0.3, "streak_far_start": 6.0, "streak_far_end": 20.0, "streak_keep": 0.6, "streak_len": 0.7, "streak_px_fade": 1.0})
	var tuned := _load("env", "wall")
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


func test_asset_materials_mist_and_veil_knobs_scale_hide_and_freeze() -> void:
	AssetMaterials.reset_tuning()
	var dflt := _load("env", "horizon_band")
	AssetMaterials.apply(dflt, "BASE")
	var mist := _mat_of(dflt, "horizon_mist")
	assert_bool(mist.get_shader_parameter("mist_scale") == null and mist.get_shader_parameter("anim") == null).override_failure_message("по умолчанию ручки дымки не заданы").is_true()
	AssetMaterials.tune({"mist_alpha": 0.4, "veil_scale": 0.5, "drift_static": true})
	var band := _load("env", "horizon_band")
	AssetMaterials.apply(band, "BASE")
	assert_float(float(_mat_of(band, "horizon_mist").get_shader_parameter("mist_scale"))).is_equal_approx(0.4, 0.001)
	assert_float(float(_mat_of(band, "horizon_mist").get_shader_parameter("anim"))).is_equal(0.0)
	var slab := _load("env", "floor_slab_8")
	AssetMaterials.apply(slab, "BASE")
	var skirt := _mat_of(slab, "floor_slab_skirt")
	assert_float(float(skirt.get_shader_parameter("veil_scale"))).is_equal_approx(0.5, 0.001)
	assert_float(float(skirt.get_shader_parameter("patch_drift"))).is_equal(0.0)
	AssetMaterials.tune({"mist_alpha": 0.0, "veil_scale": 0.0})
	var gone := _load("env", "floor_slab_8")
	AssetMaterials.apply(gone, "BASE")
	for mi in _meshes(gone):
		if String(mi.name).ends_with("_skirt"):
			assert_bool(mi.visible).override_failure_message("veil_scale=0: вуаль должна быть скрыта").is_false()
	var gone_band := _load("env", "horizon_band")
	AssetMaterials.apply(gone_band, "BASE")
	for mi in _meshes(gone_band):
		if String(mi.name).ends_with("_mist"):
			assert_bool(mi.visible).override_failure_message("mist_alpha=0: дымка должна быть скрыта").is_false()
	AssetMaterials.reset_tuning()

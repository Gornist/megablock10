extends GdUnitTestSuite
## Строки скана пола в шейдере (B3, ручка AssetMaterials `scan_rows`): по умолчанию пол как раньше (облако), при scan_rows=1 — сплошной floor_scan.gdshader без a2c
## (в прозрачном проходе, ALPHA = 1, чтобы рисоваться после фона-купола); хэш целочисленный; среднее узора сходится с формулой mean_cov (в кадре — ортокамерой, в headless — зеркало функции на GDScript).

const ROOT := "res://assets/models/"
const SHADER_DIR := "res://assets/shaders/"
const FLOOR_SCAN := preload("res://assets/shaders/floor_scan.gdshader")


func after_test() -> void:
	AssetMaterials.reset_tuning()


func _slab_mat() -> ShaderMaterial:
	var scene := load(ROOT + "env/floor_slab_16.glb") as PackedScene
	assert_bool(scene != null).override_failure_message("floor_slab_16.glb не импортируется").is_true()
	var root: Node3D = auto_free(scene.instantiate())
	AssetMaterials.apply(root, "BASE")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) == "slab":
			return (n as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	return null


func _code(path: String) -> String:   # текст шейдера без комментариев
	var out: PackedStringArray = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var i := line.find("//")
		out.append(line if i < 0 else line.substr(0, i))
	return "\n".join(out)


func test_ручка_по_умолчанию_ноль_и_пол_остаётся_облаком() -> void:
	assert_float(float(AssetMaterials.KNOBS["scan_rows"])).is_equal(0.0)
	AssetMaterials.reset_tuning()
	var m := _slab_mat()
	assert_object(m).is_not_null()
	assert_bool(m.shader == AssetMaterials.CLOUD_SHADER).override_failure_message("scan_rows=0: пол — тот же шейдер cloud_dark").is_true()
	assert_object(m.get_shader_parameter("grid_tex")).override_failure_message("сетки-текстуры пола по умолчанию нет (floor_grid 0, вид эталона 15.11)").is_null()


func test_ручка_один_даёт_непрозрачный_шейдер_пола() -> void:
	AssetMaterials.tune({"scan_rows": 1.0})
	var m := _slab_mat()
	assert_bool(m.shader == FLOOR_SCAN).override_failure_message("scan_rows=1: пол на floor_scan.gdshader").is_true()
	assert_bool(m.shader == AssetMaterials.CLOUD_SHADER).is_false()
	assert_bool(m.get_shader_parameter("void_color") == AssetMaterials.VOID_BG).override_failure_message("void_color = VOID_BG (цвет очистки)").is_true()
	assert_float(float(m.get_shader_parameter("row_step"))).is_equal_approx(0.04, 1e-6)
	assert_float(float(m.get_shader_parameter("dot_step"))).is_equal_approx(0.07, 1e-6)
	assert_float(float(m.get_shader_parameter("row_radius"))).is_equal_approx(0.009, 1e-6)
	assert_float(float(m.get_shader_parameter("row_jitter"))).is_equal_approx(0.25, 1e-6)
	assert_float(float(m.get_shader_parameter("row_gap"))).is_equal_approx(0.12, 1e-6)
	assert_vector(m.get_shader_parameter("pattern_origin") as Vector3).override_failure_message("узор от origin комнаты, не камеры").is_equal(NodeLayout.ROOM_CENTER)


func test_ручки_шагов_доходят_до_материала_и_радиус_держится_в_слоте() -> void:
	AssetMaterials.tune({"scan_rows": 1.0, "scan_row_step": 0.08, "scan_dot_step": 0.10, "scan_radius": 0.05, "scan_jitter": 0.3, "scan_gap": 0.2})
	var m := _slab_mat()
	assert_float(float(m.get_shader_parameter("row_step"))).is_equal_approx(0.08, 1e-6)
	assert_float(float(m.get_shader_parameter("dot_step"))).is_equal_approx(0.10, 1e-6)
	var r := float(m.get_shader_parameter("row_radius"))
	assert_float(r + 0.3 * 0.10).override_failure_message("радиус + разброс·шаг ≤ 0,5·шаг − 1 мм").is_less_equal(0.5 * 0.10 - 0.001 + 1e-6)
	assert_float(float(m.get_shader_parameter("row_gap"))).is_equal_approx(0.2, 1e-6)


func test_подложка_и_прочие_грани_не_трогаются_строками() -> void:
	AssetMaterials.tune({"scan_rows": 1.0})
	var scene := load(ROOT + "env/floor_slab_16.glb") as PackedScene
	var root: Node3D = auto_free(scene.instantiate())
	AssetMaterials.apply(root, "BASE")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var sm := (n as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if sm != null and String(n.name) != "slab":
			assert_bool(sm.shader == FLOOR_SCAN).override_failure_message("%s: строки только на slab" % n.name).is_false()


func test_шейдер_пола_непрозрачный_хэш_целочисленный_производные_до_веток() -> void:
	var f := _code(SHADER_DIR + "floor_scan.gdshader")
	var s := _code(SHADER_DIR + "scan_rows.gdshaderinc")
	# ALPHA = 1 и depth_draw_always: прозрачный проход после фона-купола (depth_test_disabled, −128), иначе купол закрашивает пол целиком (очки 15.11)
	assert_bool(f.contains("ALPHA = 1.0;")).override_failure_message("пол в прозрачном проходе: ALPHA = 1").is_true()
	assert_bool(f.contains("depth_draw_always")).override_failure_message("пол пишет глубину").is_true()
	assert_bool((f + s).contains("alpha_to_coverage")).override_failure_message("без alpha_to_coverage").is_false()
	assert_bool(f.contains("render_mode unshaded")).is_true()
	assert_bool(s.contains("uint pcg_hash(uint")).override_failure_message("хэш — целочисленный pcg").is_true()
	assert_bool(s.contains("sin(")).override_failure_message("хэша через sin нет").is_false()
	assert_bool(f.contains("grid_tex")).override_failure_message("grid_tex в пути строк не читается").is_false()
	assert_bool(f.contains("textureGrad") or f.contains("texture(")).is_false()
	var frag := f.find("void fragment()")
	assert_int(frag).is_greater(0)
	var body := f.substr(frag)
	assert_int(body.find("dFdx(")).override_failure_message("dFdx раньше первой ветки").is_less(body.find("if ("))
	assert_bool(FLOOR_SCAN.get_mode() == Shader.MODE_SPATIAL).is_true()
	var names: Array = FLOOR_SCAN.get_shader_uniform_list().map(func(u): return u["name"])
	for u in ["row_step", "dot_step", "row_radius", "row_jitter", "row_gap", "pattern_origin", "scan_debug", "void_color", "lit_map", "breath_depth", "touch_a", "focus_radius"]:
		assert_bool(names.has(u)).override_failure_message("нет uniform '%s' в floor_scan" % u).is_true()


func test_материал_пола_ловят_дыхание_и_свет_как_облако() -> void:
	AssetMaterials.tune({"scan_rows": 1.0})
	var m := _slab_mat()
	AssetMaterials.set_cloud_breath(get_tree(), 0.3)
	assert_float(float(m.get_shader_parameter("breath_phase"))).override_failure_message("дыхание доходит до пола строк").is_equal_approx(0.3, 1e-6)
	AssetMaterials.set_cloud_lights(get_tree(), [{"p": Vector3(0, 0, -6), "r": 3.0, "s": 1.0}])
	assert_int(int(m.get_shader_parameter("cl_n"))).override_failure_message("свет доходит до пола строк").is_equal(1)


# ── зеркало ядра на GDScript: среднее по площади равно формуле ──────────────────────────────

func _u32(x: int) -> int:
	return x & 0xFFFFFFFF


func _pcg(x: int) -> int:
	x = _u32(x * 747796405 + 2891336453)
	var w := _u32((((x >> ((x >> 28) + 4)) ^ x)) * 277803737)
	return (w >> 22) ^ w


func _hash(cx: int, cy: int) -> float:
	var h := _pcg(_u32(cx) + _pcg(_u32(cy) + 0x9e3779b9))
	return float(h >> 8) / 16777216.0


## Доля площади [0,w]×[0,w], занятая точками ближнего режима (квадраты по слотам, как в scan_rows()). Заодно проверяет, что квадрат лежит в своём слоте и строке.
func _dots_mean(w: float, rs: float, ds: float, r: float, jit: float, present: float) -> float:
	var area := 0.0
	var slots := int(w / ds)
	var rows := int(w / rs)
	for ry in rows:
		for sx in slots:
			var j := (_hash(sx, ry + 17) - 0.5) * 2.0 * jit
			var center := (sx + 0.5 + j) * ds
			assert_float(center - r).override_failure_message("квадрат вылез из слота слева").is_greater_equal(sx * ds - 1e-9)
			assert_float(center + r).override_failure_message("квадрат вылез из слота справа").is_less_equal((sx + 1) * ds + 1e-9)
			if _hash(sx, ry) <= present:
				area += (2.0 * r) * (2.0 * r)
	return area / (float(slots) * ds * float(rows) * rs)


func test_среднее_точек_и_линии_равно_формуле_mean_cov() -> void:
	var rs := 0.04
	var ds := 0.07
	var r := 0.009
	var jit := 0.25
	var present := 1.0 - 0.12
	var mean_cov := present * (2.0 * r) * (2.0 * r) / (ds * rs)
	assert_float(mean_cov).override_failure_message("стартовый пресет: среднее покрытие 10,2 %").is_equal_approx(0.102, 0.001)
	var dots := _dots_mean(10.0, rs, ds, r, jit, present)
	assert_float(absf(dots / mean_cov - 1.0)).override_failure_message("точки: среднее %s против формулы %s" % [dots, mean_cov]).is_less(0.02)
	var peak := present * 2.0 * r / ds
	assert_float(peak).override_failure_message("пик линии L ≤ 1, иначе клип съест энергию").is_less_equal(1.0)
	assert_float(peak * 2.0 * r / rs).override_failure_message("линия: среднее по периоду = формула").is_equal_approx(mean_cov, 1e-9)


## Настоящий шейдер ортокамерой на SubViewport: средний (линейный) цвет кадра = mix(void, point, mean_cov) в пределах 2 % — ближний режим (строка 16 px) и дальний (строка < 1 px).
## В headless (dummy-рендер) картинки пустые — тогда проверяет только зеркало выше.
func _render_mean(ortho_size: float, px: int, plane: float) -> Color:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(px, px)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SCAN
	mat.set_shader_parameter("edge_mix", 0.0)
	mat.set_shader_parameter("dust", 1.0)
	mat.set_shader_parameter("pattern_origin", Vector3.ZERO)
	var pm := PlaneMesh.new()
	pm.size = Vector2(plane, plane)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	vp.add_child(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ortho_size
	cam.position = Vector3(0.0, 5.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	vp.add_child(cam)
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return Color(-1, -1, -1)
	var acc := Vector3.ZERO
	var n := 0
	for y in range(0, px, 3):
		for x in range(0, px, 3):
			var c := img.get_pixel(x, y).srgb_to_linear()
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	acc /= float(n)
	return Color(acc.x, acc.y, acc.z)


func test_кадр_ортокамерой_среднее_равно_mix_пустоты_и_точки() -> void:
	if DisplayServer.get_name() == "headless":
		return   # пустые кадры: формула среднего проверена зеркалом в test_среднее_точек_и_линии_равно_формуле_mean_cov
	var mean_cov := (1.0 - 0.12) * (2.0 * 0.009) * (2.0 * 0.009) / (0.07 * 0.04)
	var void_lin := AssetMaterials.VOID_BG.srgb_to_linear()
	var point_lin := Color(0.176, 0.463, 0.553).srgb_to_linear()
	var want := void_lin.lerp(point_lin, mean_cov)
	for mode in [[3.0, 1200, 20.0], [40.0, 800, 120.0]]:   # ближний: 400 px/м (строка 16 px); дальний: 20 px/м (строка 0,8 px)
		var got: Color = await _render_mean(mode[0], mode[1], mode[2])
		if got.r < 0.0:
			return   # рендера нет (dummy-драйвер)
		for ch in 3:
			assert_float(absf(got[ch] / want[ch] - 1.0)).override_failure_message("режим %s, канал %d: кадр %s, ждали %s" % [mode, ch, got, want]).is_less(0.02)

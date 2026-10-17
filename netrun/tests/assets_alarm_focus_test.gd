extends GdUnitTestSuite
## Тревога у игрока (AssetMaterials.set_alarm_focus, alarm_focus.gdshaderinc, П6-6 (б)): шейдеры окружения имеют общие uniform'ы, значения доходят до материалов окружения,
## уровни 0–1 и radius 0 выключают. Вид — по кадру клиента (assets/preview_alarm.tscn, focus_2…4) и с очков.

const UNIFORMS := ["focus_pos", "focus_radius", "focus_color", "focus_gain"]


func after_test() -> void:
	AssetMaterials.reset_tuning()


func _names(sh: Shader) -> Array:
	return sh.get_shader_uniform_list().map(func(u): return u["name"])


## Меш с материалом solid_dark в узле, прошедшем apply(): то, что клиент получает для окружения.
func _env_material() -> ShaderMaterial:
	var root: Node3D = auto_free(Node3D.new())
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var src := ShaderMaterial.new()
	src.resource_name = "solid_dark"
	src.shader = AssetMaterials.SHADERS["solid_dark"]
	mesh.surface_set_material(0, src)
	mi.mesh = mesh
	root.add_child(mi)
	AssetMaterials.apply(root, "BASE")
	return mi.get_surface_override_material(0) as ShaderMaterial


func test_шейдеры_окружения_имеют_uniform_фокуса_тревоги() -> void:
	for sh in [AssetMaterials.SHADERS["solid_dark"], AssetMaterials.CLOUD_SHADER, AssetMaterials.SKIRT_SHADER]:
		var have := _names(sh)
		for u in UNIFORMS:
			assert_bool(have.has(u)).override_failure_message("нет uniform '%s' в %s" % [u, sh.resource_path]).is_true()


func test_фокус_тревоги_доходит_до_материала_окружения() -> void:
	var m := _env_material()
	AssetMaterials.set_alarm_focus(Vector3(1, 2, 3), 3)
	assert_float(float(m.get_shader_parameter("focus_radius"))).is_equal_approx(float(AssetMaterials.ALARM_FOCUS_RADIUS[3]), 1e-6)
	assert_float(float(m.get_shader_parameter("focus_gain"))).is_equal_approx(float(AssetMaterials.ALARM_FOCUS_GAIN[3]), 1e-6)
	assert_vector(m.get_shader_parameter("focus_pos") as Vector3).is_equal_approx(Vector3(1, 2, 3), Vector3(1e-6, 1e-6, 1e-6))
	assert_bool((m.get_shader_parameter("focus_color") as Color).is_equal_approx(AssetMaterials.layer("alarm_focus"))).is_true()


func test_уровни_ниже_двух_фокус_выключают() -> void:
	var m := _env_material()
	AssetMaterials.set_alarm_focus(Vector3.ZERO, 4)
	assert_float(float(m.get_shader_parameter("focus_radius"))).is_greater(0.0)
	for l in [0, 1]:
		AssetMaterials.set_alarm_focus(Vector3.ZERO, l)
		assert_float(float(m.get_shader_parameter("focus_radius"))).is_equal(0.0)


func test_радиус_и_усиление_растут_с_уровнем() -> void:
	for l in range(3, 5):
		assert_float(float(AssetMaterials.ALARM_FOCUS_RADIUS[l])).is_greater(float(AssetMaterials.ALARM_FOCUS_RADIUS[l - 1]))
		assert_float(float(AssetMaterials.ALARM_FOCUS_GAIN[l])).is_greater(float(AssetMaterials.ALARM_FOCUS_GAIN[l - 1]))


func test_без_материалов_окружения_вызов_ничего_не_ломает() -> void:
	AssetMaterials.set_alarm_focus(Vector3(5, 0, 5), 2)
	assert_bool(true).is_true()

extends GdUnitTestSuite
## Дыхание объёмного облака и отклик на приближение (AssetMaterials.set_cloud_breath / set_cloud_touch, particles_body.gdshaderinc).
## Проверяем то, что видно без глаз: шейдеры компилируются и общие uniform'ы на месте, по умолчанию руки и тело не меняются (глубина 0, источники выключены),
## значения доходят до материала облака. Вид — по кадру клиента и с очков.

const BODY := preload("res://assets/shaders/body_particles.gdshader")
const HAND := preload("res://assets/shaders/hand_particles.gdshader")
const UNIFORMS := ["breath_depth", "breath_phase", "breath_spread", "touch_a", "touch_b", "touch_c", "touch_d", "touch_gain", "touch_grow", "touch_push", "touch_color"]


func after_test() -> void:
	AssetMaterials.reset_tuning()


func _names(sh: Shader) -> Array:
	return sh.get_shader_uniform_list().map(func(u): return u["name"])


func _cloud() -> VolumeCloud:
	var pts := PackedFloat32Array([0, 1, 0, 0.02, 0.3, 0, 1,  0.1, 1, 0, 0.02, 0.6, 0, 1])
	var c: VolumeCloud = auto_free(VolumeCloud.new())
	add_child(c)
	c.setup(pts, Color(0.2, 0.9, 1.0), AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1)))
	return c


func _mat(c: VolumeCloud) -> ShaderMaterial:
	return (c.get_node("Particles") as MultiMeshInstance3D).multimesh.mesh.material as ShaderMaterial


func test_шейдеры_тела_и_руки_имеют_общие_uniform_дыхания_и_отклика() -> void:
	for sh in [BODY, HAND]:
		var have := _names(sh)
		for u in UNIFORMS:
			assert_bool(have.has(u)).override_failure_message("нет uniform '%s' в %s" % [u, sh.resource_path]).is_true()


## Умолчания читаем из исходника общей части: RenderingServer.shader_get_parameter_default без устройства отрисовки отдаёт null.
func test_по_умолчанию_дыхание_и_отклик_выключены() -> void:
	var src := FileAccess.get_file_as_string("res://assets/shaders/particles_body.gdshaderinc")
	assert_bool(src.length() > 0).override_failure_message("не прочитан particles_body.gdshaderinc").is_true()
	assert_bool(src.contains("uniform float breath_depth : hint_range(0.0, 1.0) = 0.0;")).override_failure_message("breath_depth по умолчанию должен быть 0").is_true()
	for u in ["touch_a", "touch_b", "touch_c", "touch_d"]:
		assert_bool(src.contains("uniform vec4 %s = vec4(0.0);" % u)).override_failure_message("%s по умолчанию должен быть выключен (w = 0)" % u).is_true()


func test_доля_такта_по_полю_tk() -> void:
	var tk := {"n": 5, "at": 100.0, "win": 2.0}
	assert_float(AssetMaterials.tick_phase(tk, 100.0)).is_equal(0.0)
	assert_float(AssetMaterials.tick_phase(tk, 101.0)).is_equal_approx(0.5, 1e-6)
	assert_float(AssetMaterials.tick_phase(tk, 99.0)).is_equal(0.0)    # время клиента отстало от сервера — не уходим в минус
	assert_float(AssetMaterials.tick_phase(tk, 105.0)).is_equal(1.0)   # тик задержался — держимся на конце такта, не перескакиваем
	assert_float(AssetMaterials.tick_phase({}, 1.0)).is_equal(0.0)


func test_дыхание_доходит_до_материала_и_глубина_из_ручки() -> void:
	var c := _cloud()
	AssetMaterials.set_cloud_breath(get_tree(), 0.25)
	var m := _mat(c)
	assert_float(float(m.get_shader_parameter("breath_phase"))).is_equal_approx(0.25, 1e-6)
	assert_float(float(m.get_shader_parameter("breath_depth"))).is_equal_approx(0.6, 1e-6)
	AssetMaterials.tune({"cloud_breath": 0.0})
	AssetMaterials.set_cloud_breath(get_tree(), 0.5)
	assert_float(float(m.get_shader_parameter("breath_depth"))).is_equal(0.0)


func test_отклик_ставит_источники_и_гасит_лишние_слоты() -> void:
	var c := _cloud()
	AssetMaterials.set_cloud_touch(get_tree(), [Vector4(0.1, 1.0, 0.0, 0.5), Vector4(1, 2, 3, 0.3)])
	var m := _mat(c)
	assert_vector(Vector3((m.get_shader_parameter("touch_a") as Vector4).x, 0, 0)).is_equal_approx(Vector3(0.1, 0, 0), Vector3(1e-6, 1e-6, 1e-6))
	assert_float((m.get_shader_parameter("touch_b") as Vector4).w).is_equal_approx(0.3, 1e-6)
	assert_float((m.get_shader_parameter("touch_c") as Vector4).w).is_equal(0.0)
	AssetMaterials.set_cloud_touch(get_tree(), [])    # источники ушли — слоты чистые, следа нет
	assert_float((m.get_shader_parameter("touch_a") as Vector4).w).is_equal(0.0)
	assert_float((m.get_shader_parameter("touch_b") as Vector4).w).is_equal(0.0)


func test_ручка_cloud_touch_ноль_гасит_отклик() -> void:
	var c := _cloud()
	AssetMaterials.tune({"cloud_touch": 0.0})
	AssetMaterials.set_cloud_touch(get_tree(), [Vector4(0, 1, 0, 1.0)])
	assert_float((_mat(c).get_shader_parameter("touch_a") as Vector4).w).is_equal(0.0)


func test_без_облаков_помощники_ничего_не_ломают() -> void:
	AssetMaterials.set_cloud_breath(get_tree(), 0.3)
	AssetMaterials.set_cloud_touch(get_tree(), [Vector4(0, 0, 0, 1)])
	AssetMaterials.set_cloud_breath(null, 0.3)
	assert_bool(true).is_true()

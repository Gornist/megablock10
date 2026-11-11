extends GdUnitTestSuite
## Пустота (вид V11, 31.10): купола, неба, звёзд и дымки нет — BackdropDome ничего не рисует и только передаёт сдвиг пустоты по тревоге просветам граней облака
## (assets/backdrop_dome.gd, shaders/backdrop_sky.gdshaderinc). Вид — по кадру `dev.sh shot res://assets/preview_sky.tscn` и с очков.


func test_dome_draws_nothing() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	assert_object(d).is_instanceof(Node3D)
	assert_bool((d as Node).is_class("GeometryInstance3D")).override_failure_message("V11: купол ничего не рисует (ни звёзд, ни неба)").is_false()
	assert_int(d.get_child_count()).is_equal(0)


func test_no_sky_shaders_or_knobs_left() -> void:
	assert_bool(FileAccess.file_exists("res://assets/shaders/stars.gdshader")).override_failure_message("звёзд нет с V11").is_false()
	for k in ["cloud_sky", "backdrop", "backdrop_haze", "backdrop_dust", "backdrop_star_size"]:
		assert_bool(AssetMaterials.KNOBS.has(k)).override_failure_message("ручка %s убрана с V11" % k).is_false()
	var code := FileAccess.get_file_as_string("res://assets/shaders/backdrop_sky.gdshaderinc")
	assert_bool(code.contains("sky_haze") or code.contains("backdrop_sky(")).override_failure_message("дымки и функции неба нет").is_false()


func test_alarm_void_goes_to_cloud_gaps_and_calm_adds_nothing() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	d.set_alarm(0)
	var c0 := AssetMaterials.sky_void_color()
	assert_float(c0.r + c0.g + c0.b).override_failure_message("спокойный узел: ничего не добавляет к фону").is_equal_approx(0.0, 0.0001)
	d.set_alarm(3)
	assert_float(AssetMaterials.sky_void_color().r).override_failure_message("тревога добавляет красный сдвиг просветам").is_greater(0.0)
	d.set_alarm(0)


## Просвет непрозрачной грани облака — цвет пустоты (фон клиента + сдвиг тревоги), без неба: у материала нет sky_fill и дымки, сдвиг доходит.
func test_cloud_gaps_are_void_colored() -> void:
	AssetMaterials.reset_tuning()
	var m := ((auto_free(NodeAssets.instance("res://assets/models/env/cover.glb", "BASE")) as Node).find_children("*", "MeshInstance3D", true, false)
		.map(func(n): return (n as MeshInstance3D).get_surface_override_material(0)).filter(func(x): return x is ShaderMaterial and x.shader == AssetMaterials.CLOUD_SHADER))
	assert_int(m.size()).override_failure_message("у укрытия есть облачный материал").is_greater(0)
	var cloud := m[0] as ShaderMaterial
	assert_bool(cloud.get_shader_parameter("sky_fill") == null and cloud.get_shader_parameter("sky_haze_gain") == null).override_failure_message("неба и дымки в материале нет").is_true()
	AssetMaterials.set_sky_void(null, Color(0.2, 0.0, 0.0))
	assert_float(AssetMaterials._sky_void.r).is_equal_approx(0.2, 0.0001)
	AssetMaterials.set_sky_void(null, Color(0, 0, 0))

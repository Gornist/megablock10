extends GdUnitTestSuite
## Фон — мировые звёзды (assets/backdrop_dome.gd, shaders/stars.gdshader): позиции на сфере, аддитивно без альфы и без неба в пикселе; свет пустоты по тревоге доходит до просветов граней облака.
## Вид — по кадру `dev.sh shot res://assets/preview_sky.tscn` и с очков.


func test_dome_is_world_stars_with_first_render_priority() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	assert_object(d.multimesh).is_not_null()
	assert_int(d.multimesh.instance_count).is_equal(BackdropDome.STAR_COUNT)
	var m := d.material_override as ShaderMaterial
	assert_int(m.render_priority).override_failure_message("звёзды рисуются первыми").is_equal(-128)
	# звезда — мировая позиция на сфере STAR_RADIUS: от вида не зависит
	assert_int(d.star_positions.size()).is_equal(BackdropDome.STAR_COUNT)
	for i in [0, 100, BackdropDome.STAR_COUNT - 1]:
		assert_float(d.star_positions[i].length()).is_equal_approx(BackdropDome.STAR_RADIUS, 0.01)


func test_dome_is_additive_and_keeps_frame_alpha() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	var code := "\n".join(Array((d.material_override as ShaderMaterial).shader.code.split("\n")).filter(func(l): return not String(l).strip_edges().begins_with("//")))   # без комментариев
	assert_bool(code.contains("blend_premul_alpha") and code.contains("ALPHA = 0.0")).override_failure_message("звёзды не трогают альфу кадра (иначе закроют слой деки)").is_true()
	assert_bool(code.contains("depth_draw_never") and not code.contains("depth_test_disabled")).override_failure_message("тест глубины включён: пол и колонны закрывают звёзды").is_true()
	assert_bool(not code.contains("atan") and not code.contains("INV_VIEW_MATRIX")).override_failure_message("небо в пикселе (atan/INV_VIEW) на очках стоило +2 мс и ехало с головой").is_true()


func test_alarm_void_goes_to_cloud_gaps_and_calm_adds_nothing() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	d.set_alarm(0)
	var c0 := AssetMaterials.sky_void_color()
	assert_float(c0.r + c0.g + c0.b).override_failure_message("спокойный узел: ничего не добавляет к фону").is_equal_approx(0.0, 0.0001)
	d.set_alarm(3)
	assert_float(AssetMaterials.sky_void_color().r).override_failure_message("тревога добавляет красный сдвиг просветам").is_greater(0.0)
	d.set_alarm(0)


func test_dome_knob_off_hides_it() -> void:
	AssetMaterials.tune({"backdrop": 0.0})
	var d := auto_free(BackdropDome.new()) as BackdropDome
	assert_bool(d.visible).is_false()
	AssetMaterials.reset_tuning()
	assert_bool((auto_free(BackdropDome.new()) as BackdropDome).visible).is_true()


## Просветы непрозрачной грани облака показывают небо купола (20.10): по умолчанию sky_fill = 1, цвет пустоты по тревоге доходит и до облака.
func test_cloud_gaps_show_the_dome_sky() -> void:
	AssetMaterials.reset_tuning()
	var m := ((auto_free(NodeAssets.instance("res://assets/models/env/cover.glb", "BASE")) as Node).find_children("*", "MeshInstance3D", true, false)
		.map(func(n): return (n as MeshInstance3D).get_surface_override_material(0)).filter(func(x): return x is ShaderMaterial and x.shader == AssetMaterials.CLOUD_SHADER))
	assert_int(m.size()).override_failure_message("у укрытия есть облачный материал").is_greater(0)
	var cloud := m[0] as ShaderMaterial
	assert_float(float(cloud.get_shader_parameter("sky_fill"))).override_failure_message("sky_fill = 1 по умолчанию").is_equal(1.0)
	assert_float(float(cloud.get_shader_parameter("sky_haze_gain"))).override_failure_message("облако получает дымку неба по ручке backdrop_haze").is_equal(float(AssetMaterials.KNOBS["backdrop_haze"]))
	AssetMaterials.set_sky_void(null, Color(0.2, 0.0, 0.0))
	assert_float(AssetMaterials._sky_void.r).is_equal_approx(0.2, 0.0001)
	AssetMaterials.set_sky_void(null, Color(0, 0, 0))
	AssetMaterials.tune({"cloud_sky": 0.0})
	var off := (auto_free(NodeAssets.instance("res://assets/models/env/cover.glb", "BASE")) as Node).find_children("*", "MeshInstance3D", true, false)
	for n in off:
		var sm := (n as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if sm != null and sm.shader == AssetMaterials.CLOUD_SHADER:
			assert_float(float(sm.get_shader_parameter("sky_fill"))).override_failure_message("cloud_sky = 0 — чёрные просветы").is_equal(0.0)
	AssetMaterials.reset_tuning()

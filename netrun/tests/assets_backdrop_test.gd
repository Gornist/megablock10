extends GdUnitTestSuite
## Фон-купол (assets/backdrop_dome.gd, shaders/backdrop.gdshader): шейдер компилируется, текстура пылинок не пустая и детерминирована, цвет пустоты следует за тревогой.
## Вид — по кадру `dev.sh shot res://assets/preview_shimmer.tscn --dome` и с очков.


func test_dome_builds_with_first_render_priority() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	assert_object(d.mesh).is_not_null()
	var m := d.material_override as ShaderMaterial
	assert_int(m.render_priority).override_failure_message("купол рисуется первым").is_equal(-128)
	assert_object(m.get_shader_parameter("sky_dust_tex")).is_not_null()
	assert_bool(m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "sky_void")).is_true()


func test_dust_texture_has_sparse_stable_dots() -> void:
	var t := BackdropDome.dust_texture()
	assert_object(BackdropDome.dust_texture()).override_failure_message("один раз на процесс").is_same(t)
	var img := t.get_image()
	assert_int(img.get_width()).is_equal(BackdropDome.DUST_SIZE.x)
	var lit := 0
	var total := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			total += 1
			if img.get_pixel(x, y).r > 0.02:
				lit += 1
	assert_int(lit).override_failure_message("пылинки есть").is_greater(50)
	assert_float(float(lit) / float(total)).override_failure_message("но их мало: это пустота, не шум").is_less(0.1)


func test_dome_is_additive_and_calm_adds_nothing() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	var m := d.material_override as ShaderMaterial
	d.set_alarm(0)
	var c0: Color = m.get_shader_parameter("sky_void")
	assert_float(c0.r + c0.g + c0.b).override_failure_message("спокойный узел: купол ничего не добавляет к чёрному фону").is_equal_approx(0.0, 0.0001)
	d.set_alarm(3)
	var c3: Color = m.get_shader_parameter("sky_void")
	assert_float(c3.r).override_failure_message("тревога добавляет красный сдвиг фона").is_greater(0.0)
	assert_bool(m.shader.code.contains("blend_premul_alpha") and m.shader.code.contains("ALPHA = 0.0")).override_failure_message("купол не трогает альфу кадра (иначе закроет слой деки)").is_true()


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
	assert_float(float(cloud.get_shader_parameter("sky_haze_gain"))).override_failure_message("облако получает дымку неба").is_equal(1.0)
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

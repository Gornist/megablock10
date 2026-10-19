extends GdUnitTestSuite
## Фон-купол (assets/backdrop_dome.gd, shaders/backdrop.gdshader): шейдер компилируется, текстура пылинок не пустая и детерминирована, цвет пустоты следует за тревогой.
## Вид — по кадру `dev.sh shot res://assets/preview_shimmer.tscn --dome` и с очков.


func test_dome_builds_with_first_render_priority() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	assert_object(d.mesh).is_not_null()
	var m := d.material_override as ShaderMaterial
	assert_int(m.render_priority).override_failure_message("купол рисуется первым").is_equal(-128)
	assert_object(m.get_shader_parameter("dust_tex")).is_not_null()
	assert_bool(m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "void_color")).is_true()


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
	var c0: Color = m.get_shader_parameter("void_color")
	assert_float(c0.r + c0.g + c0.b).override_failure_message("спокойный узел: купол ничего не добавляет к чёрному фону").is_equal_approx(0.0, 0.0001)
	d.set_alarm(3)
	var c3: Color = m.get_shader_parameter("void_color")
	assert_float(c3.r).override_failure_message("тревога добавляет красный сдвиг фона").is_greater(0.0)
	assert_bool(m.shader.code.contains("blend_premul_alpha") and m.shader.code.contains("ALPHA = 0.0")).override_failure_message("купол не трогает альфу кадра (иначе закроет слой деки)").is_true()


func test_dome_knob_off_hides_it() -> void:
	AssetMaterials.tune({"backdrop": 0.0})
	var d := auto_free(BackdropDome.new()) as BackdropDome
	assert_bool(d.visible).is_false()
	AssetMaterials.reset_tuning()
	assert_bool((auto_free(BackdropDome.new()) as BackdropDome).visible).is_true()

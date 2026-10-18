extends GdUnitTestSuite
## Фон-купол (assets/backdrop_dome.gd, shaders/backdrop.gdshader): шейдер компилируется, текстура пылинок не пустая и детерминирована, цвет пустоты следует за тревогой.
## Вид — по кадру `dev.sh shot res://assets/preview_shimmer.tscn --dome --nofar` и с очков.


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


func test_dome_void_color_follows_alarm() -> void:
	var d := auto_free(BackdropDome.new()) as BackdropDome
	d.set_alarm(2)
	var c: Color = (d.material_override as ShaderMaterial).get_shader_parameter("void_color")
	var want := AssetMaterials.alarm_background(2)
	assert_float(c.r).is_equal_approx(want.r, 0.0001)
	assert_float(c.g).is_equal_approx(want.g, 0.0001)
	assert_float(c.b).is_equal_approx(want.b, 0.0001)

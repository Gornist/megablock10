extends GdUnitTestSuite
## Глитч-спрайт частиц (assets/glitch_sprite.gd): атлас строится кодом, цикл «покой → рывок → спад», руки рисуются им по умолчанию.

func _cell_coverage(img: Image, f: int) -> float:
	var ox := (f % GlitchSprite.COLS) * GlitchSprite.CELL_W
	var oy := (f / GlitchSprite.COLS) * GlitchSprite.CELL_H
	var sum := 0.0
	for y in GlitchSprite.CELL_H:
		for x in GlitchSprite.CELL_W:
			sum += img.get_pixel(ox + x, oy + y).r
	return sum / float(GlitchSprite.CELL_W * GlitchSprite.CELL_H)


func _cell_rows(img: Image, f: int) -> Array:
	# первая и последняя строка ячейки, где есть заметный свет
	var ox := (f % GlitchSprite.COLS) * GlitchSprite.CELL_W
	var oy := (f / GlitchSprite.COLS) * GlitchSprite.CELL_H
	var first := -1
	var last := -1
	for y in GlitchSprite.CELL_H:
		for x in GlitchSprite.CELL_W:
			if img.get_pixel(ox + x, oy + y).r > 0.4:
				if first < 0:
					first = y
				last = y
				break
	return [first, last]


func test_atlas_has_the_documented_layout() -> void:
	var img := GlitchSprite.build_image()
	assert_int(img.get_width()).is_equal(GlitchSprite.COLS * GlitchSprite.CELL_W)
	assert_int(img.get_height()).is_equal(GlitchSprite.ROWS * GlitchSprite.CELL_H)
	assert_int(GlitchSprite.FRAMES).is_equal(GlitchSprite.COLS * GlitchSprite.ROWS)
	assert_bool(img.has_mipmaps()).is_true()
	assert_object(GlitchSprite.texture()).is_same(GlitchSprite.texture())


func test_timeline_rests_bursts_and_settles() -> void:
	assert_int(GlitchSprite.frame_height(0)).is_equal(GlitchSprite.REST_H)
	assert_int(GlitchSprite.frame_height(12)).is_equal(GlitchSprite.BURST_H)
	assert_int(GlitchSprite.frame_height(31)).is_equal(GlitchSprite.REST_H)
	var prev := GlitchSprite.BURST_H
	for f in range(14, 26):  # спад не растёт
		var h := GlitchSprite.frame_height(f)
		assert_bool(h <= prev).override_failure_message("кадр %d: высота %d больше предыдущей %d" % [f, h, prev]).is_true()
		prev = h
	for f in GlitchSprite.FRAMES:
		assert_int(GlitchSprite.frame_height(f) % GlitchSprite.BLOCK).is_equal(0)


func test_burst_frame_is_taller_than_rest_and_inside_the_cell() -> void:
	var img := GlitchSprite.build_image()
	var rest := _cell_rows(img, 3)
	var burst := _cell_rows(img, 12)
	assert_bool(rest[0] >= 0 and burst[0] >= 0).override_failure_message("в кадре нет света").is_true()
	assert_bool((burst[1] - burst[0]) > (rest[1] - rest[0]) * 1.8).override_failure_message("рывок должен быть ≥ ×1,8 выше покоя: %s против %s" % [burst, rest]).is_true()
	assert_bool(burst[0] >= 0 and burst[1] <= GlitchSprite.CELL_H - 1).is_true()
	assert_bool(_cell_coverage(img, 12) > _cell_coverage(img, 3)).is_true()


func test_every_frame_has_light_and_none_is_flooded() -> void:
	var img := GlitchSprite.build_image()
	for f in GlitchSprite.FRAMES:
		var c := _cell_coverage(img, f)
		assert_bool(c > 0.03 and c < 0.6).override_failure_message("кадр %d: доля света %.3f вне 0,03…0,6" % [f, c]).is_true()


func test_atlas_is_deterministic() -> void:
	var a := GlitchSprite.build_image().get_data()
	var b := GlitchSprite.build_image().get_data()
	assert_bool(a == b).is_true()


func test_hands_use_the_glitch_sprite_by_default_and_can_switch_it_off() -> void:
	var v := HandView.new(false)
	auto_free(v)
	var m := v.material()
	assert_float(float(m.get_shader_parameter("glitch_mix"))).is_equal(1.0)
	assert_object(m.get_shader_parameter("glitch_tex")).is_same(GlitchSprite.texture())
	# размер по очкам П5: вполовину от исходного (1,0), яркость компенсирует меньшую площадь
	assert_float(float(m.get_shader_parameter("glitch_scale"))).is_equal_approx(0.5, 0.001)
	assert_float(float(m.get_shader_parameter("intensity"))).is_equal_approx(1.8, 0.001)
	HandView.glitch_sprite = false
	var off := HandView.new(false)
	auto_free(off)
	HandView.glitch_sprite = true
	assert_bool(off.material().get_shader_parameter("glitch_mix") == null).override_failure_message("без спрайта параметр не задан (в шейдере 0)").is_true()


func test_body_shader_keeps_round_dots_without_the_sprite() -> void:
	var sh := load("res://assets/shaders/body_particles.gdshader") as Shader
	var u := sh.get_shader_uniform_list().filter(func(x): return x["name"] == "glitch_mix")
	assert_int(u.size()).is_equal(1)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	assert_bool(mat.get_shader_parameter("glitch_mix") == null).override_failure_message("тело не включает спрайт: параметр не задан, в шейдере 0").is_true()
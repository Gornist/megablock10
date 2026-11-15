extends GdUnitTestSuite
## B0 «корректность шейдеров» (15.11): то, что ловится без видеокарты — текстом шейдеров и кодом клиента.
## Вид — по кадру клиента и с очков; здесь — перевёрнутые границы smoothstep, общий world_per_px с abs, инварианты ручек, ручной ЛОД.

const SHADER_DIR := "res://assets/shaders/"


func after_test() -> void:
	AssetMaterials.reset_tuning()


## Тексты всех шейдеров и включаемых файлов без однострочных комментариев.
func _sources() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(SHADER_DIR):
		if not (f.ends_with(".gdshader") or f.ends_with(".gdshaderinc")):
			continue
		var lines: PackedStringArray = []
		for line in FileAccess.get_file_as_string(SHADER_DIR + f).split("\n"):
			var i := line.find("//")
			lines.append(line if i < 0 else line.substr(0, i))
		out[f] = "\n".join(lines)
	return out


func test_в_шейдерах_нет_smoothstep_с_первой_границей_больше_второй() -> void:
	var re := RegEx.new()
	re.compile("smoothstep\\(\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)\\s*,")
	var bad: Array[String] = []
	var src := _sources()
	for f in src:
		for m in re.search_all(src[f]):
			if float(m.get_string(1)) >= float(m.get_string(2)):
				bad.append("%s: %s" % [f, m.get_string()])
	assert_array(bad).override_failure_message("перевёрнутые границы smoothstep (неопределённое поведение): %s" % [bad]).is_empty()


func test_smoothstep_с_uniform_границей_не_строится_как_1_и_1_минус_x() -> void:
	var src := _sources()
	for f in src:
		assert_bool(src[f].contains("smoothstep(1.0, 1.0 -")).override_failure_message("%s: smoothstep(1.0, 1.0 - …)" % f).is_false()


func test_world_per_px_берёт_модуль_и_им_пользуются_все() -> void:
	var common: String = _sources()["pixel_math.gdshaderinc"]
	assert_bool(common.contains("abs(p11)")).is_true()
	assert_bool(common.contains("inversesqrt")).is_true()
	var src := _sources()
	for f in src:
		if f == "pixel_math.gdshaderinc" or f == "cloud_dark.gdshaderinc":   # cloud_dark только передаёт P[1][1]·высота в volume_cloud(), там world_per_px
			continue
		for line in src[f].split("\n"):
			if line.contains("PROJECTION_MATRIX[1][1]"):
				assert_bool(line.contains("world_per_px(")).override_failure_message("%s: P[1][1] без world_per_px: %s" % [f, line.strip_edges()]).is_true()


func test_ранний_выход_по_дальности_стоит_после_fill_w() -> void:
	var s: String = _sources()["volume_cloud.gdshaderinc"]
	var fill := s.find("float fill_w")
	var exit_at := s.find("if (far_k <= 0.0)")
	var tex := s.find("textureGrad")
	assert_int(fill).is_greater(0)
	assert_int(exit_at).is_greater(fill)
	assert_int(tex).is_greater(exit_at)


func test_производные_позиции_берутся_до_ветвей() -> void:
	var s: String = _sources()["volume_cloud.gdshaderinc"]
	assert_int(s.find("dFdx(wp)")).is_less(s.find("if (an.y"))
	assert_bool(s.contains("dFdx(coord)")).is_false()


func test_клампы_инвариантов_ручек() -> void:
	AssetMaterials.tune({"dust_cell": 0.0, "dust_fill_lo": 5.0, "dust_fill_hi": 3.0, "rim_far_start": 8.0, "rim_far_end": 8.0})
	assert_float(float(AssetMaterials._k("dust_cell"))).is_greater(0.0)
	assert_float(float(AssetMaterials._k("dust_fill_hi"))).is_greater(float(AssetMaterials._k("dust_fill_lo")))
	assert_float(float(AssetMaterials._k("rim_far_end"))).is_greater(float(AssetMaterials._k("rim_far_start")))


func test_допустимые_ручки_не_меняются() -> void:
	AssetMaterials.tune({"dust_cell": 0.02, "dust_fill_lo": 1.0, "dust_fill_hi": 3.0})
	assert_float(float(AssetMaterials._k("dust_cell"))).is_equal(0.02)
	assert_float(float(AssetMaterials._k("dust_fill_hi"))).is_equal(3.0)


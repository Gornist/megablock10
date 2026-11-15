extends GdUnitTestSuite
## Сущности Сети (B2a + G1 + B4, ручки AssetMaterials): минимальный размер точки тела в пикселях, плавный LOD облака, развёртка и квантование яркости «объёмного дисплея».
## При умолчаниях ручек вид и поведение прежние (min_px 0, glitch_fps 12, lod_count 0, sweep_gain 0, lum_steps 0); шейдеры должны компилироваться и нести новые uniform'ы.

const SHADER_DIR := "res://assets/shaders/"


func after_test() -> void:
	AssetMaterials.reset_tuning()


func _cloud(count: int = 4) -> VolumeCloud:
	var pts := PackedFloat32Array()
	for i in count:
		pts.append_array(PackedFloat32Array([float(i) * 0.1, 0.0, 0.0, 0.01, 0.5, 0.0, 1.0]))
	var c := VolumeCloud.new()
	add_child(c)
	auto_free(c)
	c.setup(pts, Color(0.2, 0.8, 1.0), AABB())
	return c


func _mat(c: VolumeCloud) -> ShaderMaterial:
	return ((c.get_node("Particles") as MultiMeshInstance3D).multimesh.mesh as QuadMesh).material as ShaderMaterial


func _uniforms(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
		out.append(String(u["name"]))
	return out


func test_ручки_по_умолчанию() -> void:
	var want := {"body_min_px": 0.0, "body_glitch_fps": 12.0, "volume_lod_smooth": 0.0, "volume_lod_energy": 0.0,
		"sweep_gain": 0.0, "sweep_period": 4.0, "sweep_span": 6.0, "sweep_decay": 0.15, "lum_steps": 0.0}
	for k: String in want:
		assert_bool(AssetMaterials.KNOBS.has(k)).override_failure_message("нет ручки " + k).is_true()
		assert_float(float(AssetMaterials.KNOBS[k])).is_equal(float(want[k]))


func test_материал_облака_несёт_новые_параметры_с_умолчаниями() -> void:
	var m := _mat(_cloud())
	assert_float(float(m.get_shader_parameter("min_px"))).is_equal(0.0)
	assert_float(float(m.get_shader_parameter("glitch_fps"))).is_equal(12.0)
	assert_float(float(m.get_shader_parameter("lod_count"))).is_equal(0.0)
	assert_float(float(m.get_shader_parameter("sweep_gain"))).is_equal(0.0)
	assert_int(int(m.get_shader_parameter("lum_steps"))).is_equal(0)


func test_ручки_тела_доходят_до_материала() -> void:
	AssetMaterials.tune({"body_min_px": 2.0, "body_glitch_fps": 6.0, "sweep_gain": 0.2, "lum_steps": 4})
	var m := _mat(_cloud())
	assert_float(float(m.get_shader_parameter("min_px"))).is_equal(2.0)
	assert_float(float(m.get_shader_parameter("min_angle"))).is_equal(0.0)
	assert_float(float(m.get_shader_parameter("glitch_fps"))).is_equal(6.0)
	assert_float(float(m.get_shader_parameter("sweep_gain"))).is_equal(0.2)
	assert_int(int(m.get_shader_parameter("lum_steps"))).is_equal(4)


func test_своя_рука_без_min_px() -> void:
	AssetMaterials.tune({"body_min_px": 2.0})
	var own := HandView.new(false)
	auto_free(own)
	var m := ((own.get_node("Particles") as MultiMeshInstance3D).multimesh.mesh as QuadMesh).material as ShaderMaterial
	assert_float(float(m.get_shader_parameter("min_px"))).override_failure_message("у своей руки min_px не задаётся").is_equal(0.0)
	var other := HandView.new(false)
	auto_free(other)
	other.set_occluded(true)
	var m2 := ((other.get_node("Particles") as MultiMeshInstance3D).multimesh.mesh as QuadMesh).material as ShaderMaterial
	assert_float(float(m2.get_shader_parameter("min_px"))).is_equal(2.0)


func test_плавная_доля_в_узлах() -> void:
	assert_float(VolumeCloud.lod_fraction_smooth(0.0)).is_equal(1.0)
	assert_float(VolumeCloud.lod_fraction_smooth(4.0)).is_equal_approx(1.0, 1e-5)
	assert_float(VolumeCloud.lod_fraction_smooth(8.0)).is_equal_approx(0.5, 1e-5)
	assert_float(VolumeCloud.lod_fraction_smooth(16.0)).is_equal_approx(0.25, 1e-5)
	assert_float(VolumeCloud.lod_fraction_smooth(32.0)).is_equal_approx(0.125, 1e-5)
	assert_float(VolumeCloud.lod_fraction_smooth(100.0)).is_equal_approx(0.125, 1e-5)


func test_плавная_доля_непрерывна_и_не_возрастает() -> void:
	var prev := VolumeCloud.lod_fraction_smooth(0.0)
	var d := 0.01
	while d <= 40.0:
		var f := VolumeCloud.lod_fraction_smooth(d)
		assert_float(absf(f - prev)).override_failure_message("скачок на %.2f м" % d).is_less(0.01)
		assert_bool(f <= prev + 1e-6).override_failure_message("рост на %.2f м" % d).is_true()
		prev = f
		d += 0.01


func test_догон_экспонентой() -> void:
	assert_float(VolumeCloud.smooth_follow(1.0, 0.125, 0.0)).is_equal(1.0)
	var a := VolumeCloud.smooth_follow(1.0, 0.125, 0.1)
	assert_bool(a < 1.0 and a > 0.125).is_true()
	assert_float(VolumeCloud.smooth_follow(1.0, 0.125, 100.0)).is_equal_approx(0.125, 1e-4)


func test_число_точек_за_кадр_ограничено() -> void:
	var count := 1000
	var step := ceili(VolumeCloud.LOD_BAND * count)
	var prev := count
	for i in 40:
		var n := VolumeCloud.limit_count_step(prev, 125, count)
		assert_bool(absi(n - prev) <= step).override_failure_message("кадр %d: %d → %d" % [i, prev, n]).is_true()
		prev = n
	assert_int(prev).is_equal(125)
	assert_int(VolumeCloud.limit_count_step(100, 105, count)).is_equal(105)


func test_расстояние_до_габарита() -> void:
	var xf := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var box := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))   # в мире x ∈ [9, 11]
	assert_float(VolumeCloud.aabb_distance(Vector3(20, 0, 0), xf, box)).is_equal_approx(9.0, 1e-4)
	assert_float(VolumeCloud.aabb_distance(Vector3(10, 0, 0), xf, box)).is_equal_approx(0.0, 1e-4)


func test_плавный_режим_материал_и_ручная_доля() -> void:
	AssetMaterials.tune({"volume_lod_smooth": 1, "volume_lod_energy": 1})
	var c := _cloud(100)
	var m := _mat(c)
	assert_float(float(m.get_shader_parameter("lod_count"))).is_equal(100.0)
	assert_float(float(m.get_shader_parameter("lod_band"))).is_equal_approx(VolumeCloud.LOD_BAND, 1e-6)
	c.set_lod(0.25)
	assert_float(float(m.get_shader_parameter("lod_keep"))).is_equal_approx(0.25, 1e-5)
	assert_float(float(m.get_shader_parameter("lod_gain"))).is_equal_approx(4.0, 1e-4)
	var seen := c.visible_count()
	assert_int(seen).is_equal(VolumeCloud.visible_for(100, 0.25 + VolumeCloud.LOD_BAND))
	c._process(0.5)   # ручная доля не затирается (auto_lod выключен set_lod)
	assert_int(c.visible_count()).is_equal(seen)
	assert_float(float(m.get_shader_parameter("lod_keep"))).is_equal_approx(0.25, 1e-5)


func test_плотность_множитель_в_плавном_режиме() -> void:
	AssetMaterials.tune({"volume_lod_smooth": 1})
	var c := _cloud(100)
	c.set_density(0.5)
	assert_float(float(_mat(c).get_shader_parameter("lod_keep"))).is_equal_approx(0.5, 1e-5)


func test_ступенчатый_режим_не_тронут() -> void:
	var c := _cloud(100)
	assert_float(float(_mat(c).get_shader_parameter("lod_count"))).is_equal(0.0)
	c.set_lod(0.5)
	assert_int(c.visible_count()).is_equal(50)


func test_фаза_развёртки() -> void:
	assert_float(NodeView.sweep_phase_at(0.0, 4.0)).is_equal(0.0)
	assert_float(NodeView.sweep_phase_at(1.0, 4.0)).is_equal_approx(0.25, 1e-6)
	assert_float(NodeView.sweep_phase_at(5.0, 4.0)).is_equal_approx(0.25, 1e-6)
	assert_float(NodeView.sweep_phase_at(1.0, 0.5)).override_failure_message("период меньше 2 с поднимается до 2").is_equal_approx(0.5, 1e-6)


func test_шейдеры_компилируются_и_несут_sweep() -> void:
	for f in ["body_particles", "hand_particles", "points", "cloud_dark"]:
		var u := _uniforms(SHADER_DIR + f + ".gdshader")
		assert_bool(u.size() > 0).override_failure_message("%s: пустой список uniform'ов" % f).is_true()
		assert_bool("sweep_gain" in u).override_failure_message("%s: нет sweep_gain" % f).is_true()
		assert_bool("lum_steps" in u).override_failure_message("%s: нет lum_steps" % f).is_true()
	var b := _uniforms(SHADER_DIR + "body_particles.gdshader")
	for n in ["min_px", "glitch_fps", "lod_keep", "lod_band", "lod_count", "lod_gain"]:
		assert_bool(n in b).override_failure_message("body_particles: нет " + n).is_true()

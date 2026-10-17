extends GdUnitTestSuite
## Диагностика рендера на очках (client/xr_diag.gd): сбор состояния вьюпорта, яркость кадра, формат строки, конфиг perf = "diag".


func test_collect_без_xr_отдаёт_состояние_вьюпорта() -> void:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(64, 32)
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var d := XrDiag.collect(vp, null)
	assert_int(d["msaa_3d"]).is_equal(int(Viewport.MSAA_4X))
	assert_str(d["size"]).is_equal("64x32")
	assert_bool(d.has("iface")).is_false()   # интерфейса нет — только вьюпорт


func test_яркость_кадра_пустой_чёрный_и_светлый() -> void:
	var black := Image.create(32, 32, false, Image.FORMAT_RGB8)
	assert_float(XrDiag.mean_luma(black)).is_equal_approx(0.0, 0.001)
	var white := Image.create(32, 32, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	assert_float(XrDiag.mean_luma(white)).is_equal_approx(1.0, 0.001)
	assert_float(XrDiag.mean_luma(Image.new())).is_equal(0.0)


func _flat(w: int, h: int, c: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


func test_разница_кадров_одинаковые_ноль_разные_и_несовместимые() -> void:
	assert_float(XrDiag.frame_diff(_flat(64, 64, Color(0.5, 0.5, 0.5)), _flat(64, 64, Color(0.5, 0.5, 0.5)))).is_equal_approx(0.0, 0.0001)
	assert_float(XrDiag.frame_diff(_flat(64, 64, Color.BLACK), _flat(64, 64, Color.WHITE))).is_equal_approx(1.0, 0.0001)
	assert_float(XrDiag.frame_diff(_flat(64, 64, Color(0.2, 0.2, 0.2)), _flat(64, 64, Color(0.3, 0.3, 0.3)))).is_equal_approx(0.1, 0.002)
	assert_float(XrDiag.frame_diff(_flat(64, 64, Color.BLACK), _flat(32, 32, Color.BLACK))).is_equal(-1.0)   # разный размер
	assert_float(XrDiag.frame_diff(Image.new(), _flat(8, 8, Color.BLACK))).is_equal(-1.0)


func test_итог_глаза_среднее_и_максимум_по_парам_и_формат() -> void:
	var shots: Array[Image] = [_flat(64, 64, Color(0.2, 0.2, 0.2)), _flat(64, 64, Color(0.3, 0.3, 0.3)), _flat(64, 64, Color(0.3, 0.3, 0.3))]
	var s := XrDiag.eye_summary(shots)
	assert_int(s["shots"]).is_equal(3)
	assert_float(s["luma"]).is_equal_approx(0.2, 0.002)
	assert_float(s["diff"]).is_equal_approx(0.05, 0.002)       # (0,1 + 0) / 2
	assert_float(s["diff_max"]).is_equal_approx(0.1, 0.002)
	assert_str(XrDiag.format_eye({"diff": 0.05, "luma": 0.2})).is_equal("[eye] diff=0.05 luma=0.2")
	var one: Array[Image] = [_flat(8, 8, Color.WHITE)]
	assert_float(XrDiag.eye_summary(one)["diff"]).is_equal(-1.0)   # одного снимка мало для разницы
	var none: Array[Image] = []
	assert_int(XrDiag.eye_summary(none)["shots"]).is_equal(0)


func test_кадр_глаза_без_камеры_и_с_камерой_отдаёт_итог_и_не_падает() -> void:
	var diag: XrDiag = auto_free(XrDiag.new())
	add_child(diag)
	diag.set_process(false)
	await diag._capture_eye()   # камеры во вьюпорте теста нет
	assert_str(str(diag.last_eye.get("eye", ""))).is_equal("no_camera")
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	await diag._capture_eye()
	assert_bool(diag.last_eye.has("shots")).is_true()   # в headless картинки пустые (shots 0), на устройстве и в окне — EYE_SHOTS
	assert_bool(diag.last_eye.has("diff")).is_true()
	cam.queue_free()


func test_формат_строки_и_конфиг_diag() -> void:
	assert_str(XrDiag.format({"msaa_3d": 4, "vrs_mode": 0})).is_equal("[xr-diag] msaa_3d=4 vrs_mode=0")
	var cfg := ConfigFile.new()
	cfg.set_value("render", "perf", "DIAG")
	var c := RenderConfig.from_config(cfg)
	assert_str(c.perf).is_equal("diag")
	assert_bool(RenderConfig.perf_enabled(c.perf)).is_true()   # diag включает и счётчик кадра
	assert_bool(RenderConfig.perf_diag(c.perf)).is_true()
	assert_bool(RenderConfig.perf_diag("on")).is_false()

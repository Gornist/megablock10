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


func test_формат_строки_и_конфиг_diag() -> void:
	assert_str(XrDiag.format({"msaa_3d": 4, "vrs_mode": 0})).is_equal("[xr-diag] msaa_3d=4 vrs_mode=0")
	var cfg := ConfigFile.new()
	cfg.set_value("render", "perf", "DIAG")
	var c := RenderConfig.from_config(cfg)
	assert_str(c.perf).is_equal("diag")
	assert_bool(RenderConfig.perf_enabled(c.perf)).is_true()   # diag включает и счётчик кадра
	assert_bool(RenderConfig.perf_diag(c.perf)).is_true()
	assert_bool(RenderConfig.perf_diag("on")).is_false()

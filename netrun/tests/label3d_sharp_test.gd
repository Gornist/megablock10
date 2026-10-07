extends GdUnitTestSuite
## Чёткий текст Label3D (client/ui/label3d_sharp.gd): растр крупнее вдвое, размер в мире тот же, фильтр с анизотропией.


func _label(font_size: int, pixel_size: float, outline: int) -> Label3D:
	var l: Label3D = auto_free(Label3D.new())
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.outline_size = outline
	return l


func test_растр_вдвое_размер_в_мире_тот_же() -> void:
	var l := _label(56, 0.004, 12)
	var world_before := l.font_size * l.pixel_size
	Label3DSharp.apply(l)
	assert_int(l.font_size).is_equal(112)
	assert_float(l.pixel_size).is_equal_approx(0.002, 0.000001)
	assert_float(l.font_size * l.pixel_size).is_equal_approx(world_before, 0.000001)
	assert_int(l.outline_size).is_equal(24)


func test_фильтр_с_мипами_и_анизотропией() -> void:
	var l := _label(40, 0.004, 0)
	Label3DSharp.apply(l)
	assert_int(l.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)


func test_без_обводки_обводка_не_появляется() -> void:
	var l := _label(48, 0.004, 0)
	Label3DSharp.apply(l)
	assert_int(l.outline_size).is_equal(0)


func test_тонкая_обводка_не_тоньше_минимума() -> void:
	var l := _label(48, 0.004, 1)
	Label3DSharp.apply(l)
	assert_int(l.outline_size).is_greater_equal(Label3DSharp.MIN_OUTLINE)


func test_крупный_шрифт_упирается_в_предел_размер_в_мире_тот_же() -> void:
	var l := _label(200, 0.005, 0)
	var world_before := l.font_size * l.pixel_size
	Label3DSharp.apply(l)
	assert_int(l.font_size).is_less_equal(Label3DSharp.MAX_FONT_SIZE)
	assert_float(l.font_size * l.pixel_size).is_equal_approx(world_before, 0.0001)


func test_множитель() -> void:
	assert_float(Label3DSharp.factor(40)).is_equal(2.0)
	assert_float(Label3DSharp.factor(256)).is_equal(1.0)
	assert_float(Label3DSharp.factor(0)).is_equal(1.0)

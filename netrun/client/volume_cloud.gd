class_name VolumeCloud
extends Node3D
## Объект Сети как объём из частиц (план «волюметрик», уровень Б): облако квадов-билбордов в одном MultiMesh, как у рук (hand_view.gd) и чужого тела
## (avatar_body.gd), тот же шейдер body_particles.gdshader (аддитивно, без записи глубины, с проверкой глубины). Точки берутся из файла `<модель>.points`
## рядом с .glb (генератор — сторона Blender): little-endian float32 без заголовка, POINT_FLOATS (7) float на точку
## [x, y, z, полуразмер_м, фаза 0…1, вид (0 точка / 1 искра), вес 0…1] в координатах модели, порядок ПЕРЕМЕШАН заранее, поэтому ЛОД — префикс массива.
## Буфер экземпляров пишется один раз при построении (анимация — в шейдере по TIME), без обновления от кадра к кадру. Видимость облаков по модулям —
## VolumeRegistry ([render] volumetric); по умолчанию облаков нет.

const POINT_FLOATS := 7
const POINT_BYTES := POINT_FLOATS * 4
const STRIDE := 20   # float на экземпляр в буфере MultiMesh: 12 — преобразование, 4 — цвет, 4 — данные частицы
const SHADER := preload("res://assets/shaders/body_particles.gdshader")
## ЛОД по расстоянию до камеры (доля видимых точек): ближе 4 м — все, до 8 м — половина, до 16 м — четверть, дальше — восьмая часть.
const LOD_STEPS := [[4.0, 1.0], [8.0, 0.5], [16.0, 0.25]]
const LOD_FAR := 0.125
const LOD_PERIOD_SEC := 0.25

## Менять ли ЛОД по расстоянию сам (тесты и стенды с фиксированной плотностью выключают).
var auto_lod := true
## Дополнительный множитель плотности (регулятор бюджета кадра): 1 — как есть.
var density := 1.0

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _count := 0
var _lod := 1.0
var _acc := 0.0


## Точки из байтов файла; пусто, если размер не кратен POINT_BYTES.
static func parse(bytes: PackedByteArray) -> PackedFloat32Array:
	if bytes.is_empty() or bytes.size() % POINT_BYTES != 0:
		return PackedFloat32Array()
	return bytes.to_float32_array()


## Точки из файла `.points` (пусто и предупреждение, если файла нет или он битый).
static func load_file(path: String) -> PackedFloat32Array:
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	var pts := parse(f.get_buffer(f.get_length()))
	if pts.is_empty():
		push_warning("VolumeCloud: %s — размер не кратен %d байтам, облако пропущено" % [path, POINT_BYTES])
	return pts


## Сколько точек в массиве.
static func points_in(points: PackedFloat32Array) -> int:
	return points.size() / POINT_FLOATS


## Доля видимых точек на расстоянии distance от камеры (ступени LOD_STEPS, дальше LOD_FAR).
static func lod_fraction(distance: float) -> float:
	for s: Array in LOD_STEPS:
		if distance < float(s[0]):
			return float(s[1])
	return LOD_FAR


## Буфер экземпляров MultiMesh (STRIDE float на точку): единичный базис, положение точки в origin, цвет облака, данные частицы (полуразмер, фаза, вид, вес).
static func make_buffer(points: PackedFloat32Array, color: Color) -> PackedFloat32Array:
	var count := points_in(points)
	var buf := PackedFloat32Array()
	buf.resize(count * STRIDE)
	for i in count:
		var p := i * POINT_FLOATS
		var o := i * STRIDE
		buf[o] = 1.0        # базис единичный: билборд строит шейдер, положение — в origin
		buf[o + 3] = points[p]
		buf[o + 5] = 1.0
		buf[o + 7] = points[p + 1]
		buf[o + 10] = 1.0
		buf[o + 11] = points[p + 2]
		buf[o + 12] = color.r
		buf[o + 13] = color.g
		buf[o + 14] = color.b
		buf[o + 15] = 1.0
		buf[o + 16] = points[p + 3]   # полуразмер
		buf[o + 17] = points[p + 4]   # фаза
		buf[o + 18] = points[p + 5]   # вид
		buf[o + 19] = points[p + 6]   # вес
	return buf


## Строит MultiMesh: points — массив POINT_FLOATS на точку (см. шапку), color — цвет облака (палитра клиента), bounds — габарит модели (для отсечения по кадру).
func setup(points: PackedFloat32Array, color: Color, bounds: AABB) -> void:
	_count = points_in(points)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = _count
	_mm.custom_aabb = bounds.grow(0.1)
	_mm.buffer = make_buffer(points, color)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Particles"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_apply()


## Задать долю видимых точек вручную (0…1; префикс массива); выключает автоматический ЛОД до следующего set_auto.
func set_lod(fraction: float) -> void:
	_lod = clampf(fraction, 0.0, 1.0)
	_apply()


func point_count() -> int:
	return _count


## Сколько точек рисуется сейчас (префикс по ЛОД и плотности).
func visible_count() -> int:
	return visible_for(_count, _lod * density)


## Сколько точек остаётся при доле fraction (округление вверх, чтобы у непустого облака не пропадало всё).
static func visible_for(count: int, fraction: float) -> int:
	if count <= 0 or fraction <= 0.0:
		return 0
	return clampi(ceili(count * minf(fraction, 1.0)), 1, count)


func _apply() -> void:
	if _mm != null:
		_mm.visible_instance_count = visible_count()


func _process(delta: float) -> void:
	if not auto_lod or _mm == null:
		return
	_acc += delta
	if _acc < LOD_PERIOD_SEC:
		return
	_acc = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_lod = lod_fraction(cam.global_position.distance_to(global_position))
		_apply()

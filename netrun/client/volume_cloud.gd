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
## Плавный ЛОД (ручка AssetMaterials `volume_lod_smooth`, G1): узлы доли по расстоянию до габарита облака, постоянная догона, полоса затухания у границы доли.
const LOD_SMOOTH_NODES := [[4.0, 1.0], [8.0, 0.5], [16.0, 0.25], [32.0, 0.125]]
const LOD_TAU := 0.3
const LOD_BAND := 0.08

## Менять ли ЛОД по расстоянию сам (тесты и стенды с фиксированной плотностью выключают).
var auto_lod := true
## Дополнительный множитель плотности (регулятор бюджета кадра): 1 — как есть.
var density := 1.0
## Порог импостора, м (0 — выкл., по умолчанию): дальше облако заменяется запечённым билбордом (VolumeImpostor, гистерезис ±1 м).
var impostor_m := 0.0

var _bounds := AABB()
var _impostor: Node3D
var _far := false
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _count := 0
var _lod := 1.0
var _acc := 0.0
## Плавный режим (читается из ручки при setup): доля догоняет цель каждый кадр, число точек меняется ограниченными шагами, на границе доли — затухание в шейдере.
var smooth_lod := false
var _shown := 1.0
var _shown_count := 0
var _mat: ShaderMaterial


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


## Плавная доля видимых точек: кусочно-линейная по узлам LOD_SMOOTH_NODES (4/8/16/32 м → 1/0,5/0,25/0,125), ближе 4 м — 1, дальше 32 м — 0,125; непрерывна и не возрастает.
static func lod_fraction_smooth(d: float) -> float:
	var nodes := LOD_SMOOTH_NODES
	if d <= float((nodes[0] as Array)[0]):
		return float((nodes[0] as Array)[1])
	for i in range(1, nodes.size()):
		var a: Array = nodes[i - 1]
		var b: Array = nodes[i]
		if d <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (d - float(a[0])) / (float(b[0]) - float(a[0])))
	return float((nodes[nodes.size() - 1] as Array)[1])


## Показанная доля догоняет цель экспонентой с постоянной LOD_TAU (не зависит от частоты кадров).
static func smooth_follow(shown: float, target: float, delta: float) -> float:
	return lerpf(shown, target, 1.0 - exp(-maxf(delta, 0.0) / LOD_TAU))


## Число точек за кадр: от prev к wanted не дальше чем на ceil(LOD_BAND · count) (скачок дистанции не даёт скачка облака).
static func limit_count_step(prev: int, wanted: int, count: int) -> int:
	var step := ceili(LOD_BAND * count)
	return clampi(wanted, prev - step, prev + step)


## Расстояние от камеры до ближайшей точки габарита облака в мире (xf — его глобальное преобразование).
static func aabb_distance(cam_pos: Vector3, xf: Transform3D, bounds: AABB) -> float:
	var local := xf.affine_inverse() * cam_pos
	var lo := bounds.position
	var hi := bounds.end
	var nearest := Vector3(clampf(local.x, lo.x, hi.x), clampf(local.y, lo.y, hi.y), clampf(local.z, lo.z, hi.z))
	return (xf * nearest).distance_to(cam_pos)


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
	_bounds = bounds if bounds.size != Vector3.ZERO else VolumeSampler.bounds_of(points)   # у файла .points габарита нет — по самим точкам
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	_mat = mat
	AssetMaterials.push_body_particle_knobs(mat)   # min_px, glitch_fps, развёртка и ступени яркости (в умолчании тождественны)
	smooth_lod = float(AssetMaterials.knob("volume_lod_smooth")) > 0.0
	mat.set_shader_parameter("lod_count", 0.0)   # ступенчатый режим: шейдер LOD не трогает
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = _count
	_mm.custom_aabb = _bounds.grow(0.1)
	_mm.buffer = make_buffer(points, color)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Particles"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	NodeAssets.limit_range(_mmi)   # дальше far_cull_m облако не рисуется (редкая восьмая часть точек вдали — тоже мусор)
	add_child(_mmi)
	add_to_group("volume_clouds")   # регулятор плотности (VolumeBudget) находит облака по группе
	_apply()


## Плотность облака (множитель к ЛОД; регулятор VolumeBudget зовёт через группу `volume_clouds`).
func set_density(value: float) -> void:
	density = clampf(value, 0.0, 1.0)
	_apply()


## Задать долю видимых точек вручную (0…1; префикс массива); выключает автоматический ЛОД до следующего set_auto.
func set_lod(fraction: float) -> void:
	auto_lod = false   # иначе _process в ближайшие LOD_PERIOD_SEC перезапишет ручное значение
	_lod = clampf(fraction, 0.0, 1.0)
	_shown = _lod   # плавный режим: показанная доля и цель — сразу
	_apply()


## Вернуть автоматический ЛОД (по дистанции до камеры) или выключить его, не трогая текущую долю.
func set_auto(enabled: bool) -> void:
	auto_lod = enabled


func point_count() -> int:
	return _count


## Сколько точек рисуется сейчас (префикс по ЛОД и плотности).
func visible_count() -> int:
	if smooth_lod:
		return _shown_count
	return visible_for(_count, _lod * density)


## Сколько точек остаётся при доле fraction (округление вверх, чтобы у непустого облака не пропадало всё).
static func visible_for(count: int, fraction: float) -> int:
	if count <= 0 or fraction <= 0.0:
		return 0
	return clampi(ceili(count * minf(fraction, 1.0)), 1, count)


func _apply() -> void:
	if smooth_lod:
		_apply_smooth(false)
	elif _mm != null:
		_mm.visible_instance_count = visible_count()


## Плавный режим: итоговая доля f = _shown · density; точек — префикс на f + LOD_BAND (хвост полосы гаснет в шейдере по рангу), шагами не больше ceil(LOD_BAND · count);
## immediate — без ограничения шага (настройка, ручная доля, плотность).
func _apply_smooth(step_limited: bool) -> void:
	if _mm == null:
		return
	var f := _shown * density
	var wanted := visible_for(_count, f + LOD_BAND) if f > 0.0 else 0
	_shown_count = limit_count_step(_shown_count, wanted, _count) if step_limited else wanted
	_mm.visible_instance_count = _shown_count
	_mat.set_shader_parameter("lod_keep", f)
	_mat.set_shader_parameter("lod_band", LOD_BAND)
	_mat.set_shader_parameter("lod_count", float(_count))
	_mat.set_shader_parameter("lod_gain", 1.0 / maxf(f, 0.125) if float(AssetMaterials.knob("volume_lod_energy")) > 0.0 else 1.0)


func _process(delta: float) -> void:
	if not auto_lod or _mm == null:
		return
	if smooth_lod:
		var cam_s := get_viewport().get_camera_3d()
		if cam_s != null:
			_shown = smooth_follow(_shown, lod_fraction_smooth(aabb_distance(cam_s.global_position, global_transform, _bounds)), delta)
			_apply_smooth(true)
	_acc += delta
	if _acc < LOD_PERIOD_SEC:
		return
	_acc = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var dist := cam.global_position.distance_to(global_position)
		_set_far(VolumeImpostor.next_far(_far, dist, impostor_m))
		if not smooth_lod:   # плавный режим доли ведёт выше, каждый кадр
			_lod = lod_fraction(dist)
			_apply()


## Далеко — вместо тысяч квадов один билборд (запекается при первом переходе); близко — снова живое облако.
func _set_far(far: bool) -> void:
	if far == _far or _mmi == null:
		return
	if far and _impostor == null:
		_impostor = VolumeImpostor.bake(_mm, _bounds)
		if _impostor == null:
			return
		add_child(_impostor)
	_far = far
	_mmi.visible = not far
	if _impostor != null:
		_impostor.visible = far


func is_far() -> bool:
	return _far

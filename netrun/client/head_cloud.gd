class_name HeadCloud
extends Node3D
## Голова чужого нетраннера: облако из ≈470 светящихся точек той же породы, что и руки (assets/shaders/body_particles.gdshader — решётка, волна, с проверкой глубины).
## Спереди (-Z) «маска»: яркие контур лица, глаза, брови, нос, рот и подбородок читаются издали и показывают, куда смотрит игрок; затылок, макушка и бока — слабее
## (оболочка черепа, вертикальные дуги, кольца), внутри лёгкое заполнение, под подбородком кольцо у шеи, над макушкой искры. Узел ставится в позу головы
## (камера игрока: -Z вперёд, начало между глаз), буфер частиц задаётся один раз при создании — за кадр ничего не пересчитывается.

const STRIDE := HandView.STRIDE
const SHADER := preload("res://assets/shaders/body_particles.gdshader")
## Полуоси черепа вокруг центра головы (м) и сам центр относительно глаз: глаза на высоте начала координат, череп на 8,5 см позади них,
## от глаз до макушки и до подбородка по 12,5 см.
const HALF := Vector3(0.085, 0.125, 0.10)
const CENTER := Vector3(0.0, 0.0, 0.085)
## Сколько первых частиц шаблона — «маска» лица (контур, глаза, брови, нос, рот, заполнение лица): ярче остальных и обращена к -Z.
const OUTLINE_POINTS := 56
const EYE_LINE_POINTS := 16
const EYE_PUPIL_POINTS := 4
const BROW_POINTS := 10
const NOSE_POINTS := 18
const NOSTRIL_POINTS := 4
const MOUTH_POINTS := 22
const CHIN_POINTS := 16
const FACE_POINTS := 210
const SHELL_POINTS := 110
const MERIDIANS := 4
const MERIDIAN_POINTS := 9
const RINGS := 3
const RING_POINTS := 18
const FILL_POINTS := 40
const NECK_POINTS := 14
const SPARK_COUNT := 4
const COLOR_SPARK_MIX := 0.5
## Яркость головы выше, чем у рук (uniform glow шейдера): лицо должно читаться и на светлом фоне стен.
const GLOW := 2.6
## Решётка головы мельче, чем у рук (6 мм): черты лица — линии из точек через 1–1,5 см, крупная решётка их рвёт.
const LATTICE := 0.003

var tint := HandView.COLOR_HAND
var _mm: MultiMesh
var _mat: ShaderMaterial
var _buf := PackedFloat32Array()
var _kinds := PackedFloat32Array()


func _init(color: Color = HandView.COLOR_HAND) -> void:
	name = "HeadCloud"
	var tpl := template(23)
	_buf.resize(tpl.size() * STRIDE)
	_kinds.resize(tpl.size())
	for i in tpl.size():
		var p: Array = tpl[i]
		var o := i * STRIDE
		_buf[o] = 1.0
		_buf[o + 5] = 1.0
		_buf[o + 10] = 1.0
		_buf[o + 3] = p[0].x
		_buf[o + 7] = p[0].y
		_buf[o + 11] = p[0].z
		_buf[o + 16] = p[1]
		_buf[o + 17] = p[3]
		_buf[o + 18] = p[2]
		_buf[o + 19] = p[4]
		_kinds[i] = p[2]
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("min_angle", HandView.REMOTE_MIN_ANGLE)
	_mat.set_shader_parameter("facing_fade", 1.0)
	_mat.set_shader_parameter("glow", GLOW)
	_mat.set_shader_parameter("lattice", LATTICE)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mat
	_mm.mesh = quad
	_mm.instance_count = tpl.size()
	_mm.custom_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
	set_tint(color)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Particles"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("facing_center", global_transform * CENTER)  # «наружу» для гашения обратной стороны считается от центра черепа


func set_tint(c: Color) -> void:
	tint = c
	var spark := c.lerp(Color.WHITE, COLOR_SPARK_MIX)
	for i in _kinds.size():
		var col := spark if _kinds[i] > 0.5 else c
		var o := i * STRIDE
		_buf[o + 12] = col.r
		_buf[o + 13] = col.g
		_buf[o + 14] = col.b
		_buf[o + 15] = 1.0
	_mm.buffer = _buf


func particle_count() -> int:
	return _kinds.size()


func particle_position(i: int) -> Vector3:
	var o := i * STRIDE
	return Vector3(_buf[o + 3], _buf[o + 7], _buf[o + 11])


func multimesh() -> MultiMesh:
	return _mm


func material() -> ShaderMaterial:
	return _mat


## Частицы в системе головы: [позиция, размер, вид (0 точка, 1 искра), яркость, фаза 0 (шея) … 1 (макушка)]. Первые FACE_POINTS — маска лица. Детерминировано по зерну.
static func template(rng_seed: int = 23) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	for i in OUTLINE_POINTS:  # контур лица: овал на передней поверхности черепа
		var t := TAU * float(i) / float(OUTLINE_POINTS)
		out.append(_face_point(0.80 * cos(t), 0.92 * sin(t), 0.0, 0.0028, 0.9))
	for side in [-1.0, 1.0]:  # глаза: слегка изогнутая яркая черта и зрачок
		for i in EYE_LINE_POINTS:
			var k := float(i) / float(EYE_LINE_POINTS - 1)
			out.append(_face_point(side * lerpf(0.26, 0.56, k), 0.05 * sin(k * PI) + 0.02, 0.0, 0.0034, 1.0))
		for i in EYE_PUPIL_POINTS:
			out.append(_face_point(side * 0.40 + rng.randf_range(-0.03, 0.03), rng.randf_range(-0.02, 0.05), 0.003, 0.0042, 1.0))
	for side in [-1.0, 1.0]:  # брови
		for i in BROW_POINTS:
			var k := float(i) / float(BROW_POINTS - 1)
			out.append(_face_point(side * lerpf(0.20, 0.62, k), 0.26 + 0.05 * k, 0.0, 0.0030, 0.9))
	for i in NOSE_POINTS:  # спинка носа от переносицы вниз, к кончику нос выступает вперёд
		var k := float(i) / float(NOSE_POINTS - 1)
		out.append(_face_point(0.0, lerpf(0.15, -0.42, k), 0.004 + 0.016 * k, 0.0032, 1.0))
	for side in [-1.0, 1.0]:  # крылья носа
		out.append(_face_point(side * 0.12, -0.44, 0.012, 0.0030, 0.95))
		out.append(_face_point(side * 0.07, -0.48, 0.012, 0.0030, 0.95))
	for i in MOUTH_POINTS:  # рот: дуга чуть вниз по краям
		var k := lerpf(-1.0, 1.0, float(i) / float(MOUTH_POINTS - 1))
		out.append(_face_point(0.34 * k, -0.64 + 0.06 * k * k, 0.002, 0.0032, 1.0))
	for i in CHIN_POINTS:  # подбородок: дуга под ртом
		var k := lerpf(-1.0, 1.0, float(i) / float(CHIN_POINTS - 1))
		out.append(_face_point(0.30 * k, -0.86 - 0.03 * (1.0 - k * k), 0.0, 0.0030, 0.9))
	while out.size() < FACE_POINTS:  # слабое заполнение лица внутри овала: скулы и лоб
		var u := rng.randf_range(-0.7, 0.7)
		var v := rng.randf_range(-0.8, 0.85)
		if (u / 0.75) * (u / 0.75) + (v / 0.9) * (v / 0.9) < 1.0:
			out.append(_face_point(u, v, 0.0, rng.randf_range(0.0018, 0.0026), 0.5))
	for i in SHELL_POINTS:  # оболочка черепа по всему эллипсоиду: затылок, макушка, бока (спереди тоже, но там маска перекрывает)
		var v := rng.randf_range(-0.95, 0.95)
		var a := rng.randf() * TAU
		out.append([_on_skull(a, v, sqrt(maxf(1.0 - v * v, 0.0))), rng.randf_range(0.0018, 0.0026), 0.0, 0.5, 0.5 + 0.5 * v])
	for m in MERIDIANS:  # вертикальные дуги по бокам и сзади: череп читается объёмным
		var a := PI * float(m) / 1.0 if m < 2 else 3.0 * PI / 2.0 + (-0.5 if m == 2 else 0.5)
		for i in MERIDIAN_POINTS:
			var v := lerpf(-0.95, 0.95, (float(i) + rng.randf_range(0.0, 0.6)) / float(MERIDIAN_POINTS))
			out.append([_on_skull(a, v, sqrt(maxf(1.0 - v * v, 0.0))), rng.randf_range(0.0022, 0.0030), 0.0, 0.75, 0.5 + 0.5 * v])
	for r in RINGS:  # кольца вокруг головы на трёх высотах
		var v := lerpf(-0.5, 0.8, float(r) / float(RINGS - 1))
		for i in RING_POINTS:
			var a := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(RING_POINTS)
			out.append([_on_skull(a, v, sqrt(maxf(1.0 - v * v, 0.0))), rng.randf_range(0.0022, 0.0030), 0.0, 0.6, 0.5 + 0.5 * v])
	for i in FILL_POINTS:  # заполнение внутри: объём
		var q := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		while q.length() > 1.0:
			q = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		out.append([CENTER + q * HALF * 0.8, rng.randf_range(0.0016, 0.0024), 0.0, 0.35, 0.5 + 0.5 * q.y])
	for i in NECK_POINTS:  # кольцо у шеи: край, на котором «обрывается» голова
		var a := TAU * float(i) / float(NECK_POINTS)
		out.append([CENTER + Vector3(sin(a) * 0.05, -0.145, cos(a) * 0.05), rng.randf_range(0.0022, 0.0030), 0.0, 0.7, 0.0])
	for i in SPARK_COUNT:  # искры над макушкой
		out.append([CENTER + Vector3(rng.randf_range(-0.04, 0.04), 0.13, rng.randf_range(-0.04, 0.04)), 0.0016, 1.0, 0.9, rng.randf()])
	return out


## Точка лица: u — по горизонтали (−1…1, плюс — вправо), v — по высоте (−1…1, 0 — линия глаз), push — на сколько выступает вперёд (нос, зрачки), м.
static func _face_point(u: float, v: float, push: float, size: float, weight: float) -> Array:
	var vv := clampf(v, -0.98, 0.98)
	var q := _on_skull(PI / 2.0 - u, vv, sqrt(1.0 - vv * vv) * 1.02) + Vector3(0, 0, -push)
	return [q, size, 0.0, weight, 0.5 + 0.5 * vv]


## Точка на эллипсоиде черепа: угол a вокруг вертикали (0 — вправо, π/2 — вперёд, к -Z), y — доля высоты (−1…1), rr — радиус кольца.
static func _on_skull(a: float, y: float, rr: float) -> Vector3:
	return CENTER + Vector3(cos(a) * rr * HALF.x, y * HALF.y, -sin(a) * rr * HALF.z)

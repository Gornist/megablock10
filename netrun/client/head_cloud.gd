class_name HeadCloud
extends Node3D
## Голова чужого нетраннера: облако из ≈500 светящихся точек той же породы, что и руки (assets/shaders/body_particles.gdshader — решётка, волна, с проверкой глубины).
## Форма — настоящая модель головы человека (low-poly скан владельца), а не нарисованное лицо: точки по резким граням (нос, глазницы, губы, челюсть, уши — линии) и по поверхности,
## на лице гуще, чем на затылке; точки сняты скриптом assets/src/head_points.py, данные — client/head_points.gd. Над макушкой искры. Узел ставится в позу головы
## (камера игрока: -Z вперёд, начало между глаз), буфер частиц задаётся один раз при создании — за кадр ничего не пересчитывается.

const STRIDE := HandView.STRIDE
const SHADER := preload("res://assets/shaders/body_particles.gdshader")
## Центр и полуразмеры модели в системе головы (из head_points.gd): центр объёма нужен шейдеру, чтобы гасить обратную сторону.
const CENTER := HeadPoints.CENTER
const HALF := HeadPoints.HALF
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


## Частицы в системе головы: [позиция, размер, вид (0 точка, 1 искра), яркость, фаза 0 (шея) … 1 (макушка)]. Сначала точки модели (самые яркие первыми), затем искры.
static func template(rng_seed: int = 23) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	var d := HeadPoints.DATA
	for i in HeadPoints.COUNT:
		var o := i * HeadPoints.STRIDE
		out.append([Vector3(d[o], d[o + 1], d[o + 2]), d[o + 3], 0.0, d[o + 4], d[o + 5]])
	var crown := CENTER.y + HALF.y
	for i in SPARK_COUNT:  # искры над макушкой
		out.append([Vector3(rng.randf_range(-0.04, 0.04), crown + 0.015, CENTER.z + rng.randf_range(-0.04, 0.04)), 0.0016, 1.0, 0.9, rng.randf()])
	return out

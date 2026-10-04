class_name HeadCloud
extends Node3D
## Голова чужого нетраннера: облако из ≈180 светящихся точек той же породы, что и руки (assets/shaders/body_particles.gdshader — решётка, волна, с проверкой глубины).
## Лица нет: «шлем» из пяти колец вокруг головы, яркая полоса спереди на уровне глаз показывает, куда смотрит игрок, над макушкой — искры. Узел ставится в позу
## головы (камера игрока: -Z вперёд, начало между глаз), буфер частиц задаётся один раз при создании — за кадр ничего не пересчитывается.

const STRIDE := HandView.STRIDE
const SHADER := preload("res://assets/shaders/body_particles.gdshader")
## Полуоси черепа вокруг центра головы (м) и сам центр относительно глаз: череп чуть позади и выше точки между глаз.
const HALF := Vector3(0.085, 0.115, 0.10)
const CENTER := Vector3(0.0, 0.04, 0.085)
const RINGS := 5
const RING_POINTS := 18
const VISOR_POINTS := 24
const FILL_POINTS := 50
const NECK_POINTS := 12
const SPARK_COUNT := 4
const COLOR_SPARK_MIX := 0.5

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


## Частицы в системе головы: [позиция, размер, вид (0 точка, 1 искра), яркость, фаза 0 (шея) … 1 (макушка)]. Детерминировано по зерну.
static func template(rng_seed: int = 23) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	for r in RINGS:  # кольца по высоте черепа от затылка к макушке; у экватора шире
		var y := lerpf(-0.8, 0.8, float(r) / float(RINGS - 1))
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		for i in RING_POINTS:
			var a := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(RING_POINTS)
			out.append([_on_skull(a, y, rr), rng.randf_range(0.0022, 0.0030), 0.0, 0.55 + 0.25 * (1.0 - absf(y)), 0.5 + 0.5 * y])
	for i in VISOR_POINTS:  # полоса «взгляда»: дуга спереди чуть выше экватора, ярче и крупнее
		var a := lerpf(-0.9, 0.9, (float(i) + rng.randf_range(0.1, 0.9)) / float(VISOR_POINTS))
		var y := 0.12 + rng.randf_range(-0.07, 0.07)
		var rr := sqrt(1.0 - y * y)
		out.append([_on_skull(PI / 2.0 + a, y, rr * 1.02), rng.randf_range(0.0030, 0.0042), 0.0, 1.0, 0.55])
	for i in FILL_POINTS:  # заполнение внутри: объём
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		while v.length() > 1.0:
			v = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		out.append([CENTER + v * HALF * 0.8, rng.randf_range(0.0016, 0.0024), 0.0, 0.4, 0.5 + 0.5 * v.y])
	for i in NECK_POINTS:  # кольцо у основания: край, на котором «обрывается» голова
		var a := TAU * float(i) / float(NECK_POINTS)
		out.append([CENTER + Vector3(sin(a) * 0.05, -0.115, cos(a) * 0.05), rng.randf_range(0.0022, 0.0030), 0.0, 0.7, 0.0])
	for i in SPARK_COUNT:  # искры над макушкой
		out.append([CENTER + Vector3(rng.randf_range(-0.04, 0.04), 0.115, rng.randf_range(-0.04, 0.04)), 0.0016, 1.0, 0.9, rng.randf()])
	return out


## Точка на эллипсоиде черепа: угол a вокруг вертикали (0 — вправо, π/2 — вперёд, к -Z), y — доля высоты (−1…1), rr — радиус кольца.
static func _on_skull(a: float, y: float, rr: float) -> Vector3:
	return CENTER + Vector3(cos(a) * rr * HALF.x, y * HALF.y, -sin(a) * rr * HALF.z)

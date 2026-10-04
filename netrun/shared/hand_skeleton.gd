class_name HandSkeleton
extends RefCounted
## Скелет руки для объёмной отрисовки (client/hand_view.gd): 26 суставов в порядке OpenXR (XRHandTracker.HAND_JOINT_*), открытая поза
## в системе ладони, прямая кинематика для сгиба пальцев (поза от контроллера: курок и хват) и шаблон облака частиц на костях и ладони.
## Чистая логика без узлов и без графики: считается и проверяется в тестах (tests/hand_view_test.gd).
##
## Система ладони (правая рука, как поза grip): начало — центр ладони, -Z — к кончикам пальцев, +Y — тыльная сторона, +X — вправо
## (мизинец при ладони вниз справа, большой палец слева). Левая рука — зеркало по X. Размеры взрослой руки: от запястья до кончика среднего пальца ≈ 19 см.

const PALM := 0
const WRIST := 1
const THUMB_META := 2
const THUMB_PROX := 3
const THUMB_DIST := 4
const THUMB_TIP := 5
const INDEX_META := 6
const INDEX_PROX := 7
const INDEX_INTER := 8
const INDEX_DIST := 9
const INDEX_TIP := 10
const MIDDLE_META := 11
const MIDDLE_PROX := 12
const MIDDLE_INTER := 13
const MIDDLE_DIST := 14
const MIDDLE_TIP := 15
const RING_META := 16
const RING_PROX := 17
const RING_INTER := 18
const RING_DIST := 19
const RING_TIP := 20
const LITTLE_META := 21
const LITTLE_PROX := 22
const LITTLE_INTER := 23
const LITTLE_DIST := 24
const LITTLE_TIP := 25
const COUNT := 26

## Открытая правая рука, система ладони, метры.
const REST: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.050),
	Vector3(-0.022, -0.004, 0.030), Vector3(-0.045, -0.008, -0.002), Vector3(-0.060, -0.010, -0.028), Vector3(-0.069, -0.012, -0.044),
	Vector3(-0.020, 0.0, 0.022), Vector3(-0.032, 0.0, -0.040), Vector3(-0.034, 0.0, -0.083), Vector3(-0.035, 0.0, -0.107), Vector3(-0.035, 0.0, -0.125),
	Vector3(-0.007, 0.0, 0.024), Vector3(-0.011, 0.0, -0.044), Vector3(-0.011, 0.0, -0.090), Vector3(-0.011, 0.0, -0.118), Vector3(-0.011, 0.0, -0.137),
	Vector3(0.007, 0.0, 0.022), Vector3(0.011, 0.0, -0.040), Vector3(0.012, 0.0, -0.082), Vector3(0.012, 0.0, -0.108), Vector3(0.012, 0.0, -0.127),
	Vector3(0.019, -0.001, 0.020), Vector3(0.030, -0.001, -0.032), Vector3(0.033, 0.0, -0.065), Vector3(0.034, 0.0, -0.084), Vector3(0.035, 0.0, -0.100),
]

## Цепочки пальцев: основание пястной кости, сустав у ладони, средний, дальний, кончик.
const FINGERS := {
	"thumb": [THUMB_META, THUMB_PROX, THUMB_DIST, THUMB_TIP],
	"index": [INDEX_META, INDEX_PROX, INDEX_INTER, INDEX_DIST, INDEX_TIP],
	"middle": [MIDDLE_META, MIDDLE_PROX, MIDDLE_INTER, MIDDLE_DIST, MIDDLE_TIP],
	"ring": [RING_META, RING_PROX, RING_INTER, RING_DIST, RING_TIP],
	"little": [LITTLE_META, LITTLE_PROX, LITTLE_INTER, LITTLE_DIST, LITTLE_TIP],
}
const TIPS := [THUMB_TIP, INDEX_TIP, MIDDLE_TIP, RING_TIP, LITTLE_TIP]
## Сгиб суставов пальца при полном сжатии, градусы: у ладони, средний, дальний.
const FLEX_DEG := [80.0, 100.0, 60.0]
## Большой палец: разворот к ладони и сгиб при полном сжатии, градусы.
const THUMB_SWING_DEG := 38.0
const THUMB_FLEX_DEG := 40.0
## Спокойная рука: пальцы чуть согнуты, а не вытянуты струной.
const RELAXED_CURL := 0.12

## Кости облака: [от сустава, к суставу, радиус у начала, радиус у конца], метры. Пястные кости — внутри ладони, их закрывает облако ладони.
const BONES := [
	[THUMB_META, THUMB_PROX, 0.011, 0.010], [THUMB_PROX, THUMB_DIST, 0.010, 0.008], [THUMB_DIST, THUMB_TIP, 0.008, 0.006],
	[INDEX_PROX, INDEX_INTER, 0.0090, 0.0080], [INDEX_INTER, INDEX_DIST, 0.0080, 0.0070], [INDEX_DIST, INDEX_TIP, 0.0070, 0.0050],
	[MIDDLE_PROX, MIDDLE_INTER, 0.0092, 0.0082], [MIDDLE_INTER, MIDDLE_DIST, 0.0082, 0.0072], [MIDDLE_DIST, MIDDLE_TIP, 0.0072, 0.0052],
	[RING_PROX, RING_INTER, 0.0088, 0.0078], [RING_INTER, RING_DIST, 0.0078, 0.0068], [RING_DIST, RING_TIP, 0.0068, 0.0048],
	[LITTLE_PROX, LITTLE_INTER, 0.0078, 0.0068], [LITTLE_INTER, LITTLE_DIST, 0.0068, 0.0058], [LITTLE_DIST, LITTLE_TIP, 0.0058, 0.0042],
]
## Облако ладони: полуоси эллипса по ширине (X) и длине (Z) и расстояние от плоскости ладони до поверхностей (тыльной и ладонной).
const PALM_HALF_W := 0.044
const PALM_HALF_L := 0.058
const PALM_CENTER_Z := -0.004
const PALM_THICK := 0.012

const PALM_POINTS := 100
const BONE_POINTS := 20
const WRIST_POINTS := 14
const SPARK_COUNT := 5

## Виды частиц.
const KIND_POINT := 0.0
const KIND_SPARK := 1.0


## Позиции 26 суставов в системе ладони. curls — сгиб пальцев 0…1 (thumb, index, middle, ring, little); left — зеркало по X.
static func pose(curls: Dictionary, left: bool = false) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(COUNT)
	for i in COUNT:
		out[i] = REST[i]
	for name in FINGERS:
		var chain: Array = FINGERS[name]
		var c: float = clampf(float(curls.get(name, 0.0)), 0.0, 1.0)
		if name == "thumb":
			_pose_thumb(out, chain, c)
		else:
			_pose_finger(out, chain, c)
	if left:
		for i in COUNT:
			out[i] = Vector3(-out[i].x, out[i].y, out[i].z)
	return out


static func _pose_finger(pos: PackedVector3Array, chain: Array, c: float) -> void:
	# цепочка [meta, prox, inter, dist, tip]: сгиб у prox, inter, dist; отрезок после сустава k повёрнут на сумму сгибов до k включительно
	var cum := 0.0
	for k in range(1, chain.size() - 1):
		cum += deg_to_rad(FLEX_DEG[k - 1]) * c
		var seg: Vector3 = REST[chain[k + 1]] - REST[chain[k]]
		# сгиб — поворот вокруг X вниз к ладони (к -Y), вперёд идёт -Z: вектор отрезка уходит из (0,0,-L) в (0,-L·sin,-L·cos)
		pos[chain[k + 1]] = pos[chain[k]] + Basis(Vector3.RIGHT, -cum) * seg


static func _pose_thumb(pos: PackedVector3Array, chain: Array, c: float) -> void:
	# большой палец: разворот вокруг Y к пальцам (в сторону +X) и сгиб вокруг X; каждый следующий отрезок поворачивается сильнее
	var swing := 0.0
	var flex := 0.0
	for k in range(chain.size() - 1):
		swing += deg_to_rad(THUMB_SWING_DEG) * c * 0.45
		flex += deg_to_rad(THUMB_FLEX_DEG) * c * 0.5
		var seg: Vector3 = REST[chain[k + 1]] - REST[chain[k]]
		pos[chain[k + 1]] = pos[chain[k]] + Basis(Vector3.UP, swing) * (Basis(Vector3.RIGHT, -flex) * seg)


## Сгиб пальцев по входам контроллера: курок — указательный, хват — остальные три, большой палец — по хвату (и чуть по курку).
static func curls_from_inputs(trigger: float, grip: float) -> Dictionary:
	var t := clampf(trigger, 0.0, 1.0)
	var g := clampf(grip, 0.0, 1.0)
	return {
		"thumb": clampf(RELAXED_CURL + 0.6 * g + 0.2 * t, 0.0, 1.0),
		"index": clampf(RELAXED_CURL + (1.0 - RELAXED_CURL) * t, 0.0, 1.0),
		"middle": clampf(RELAXED_CURL + (1.0 - RELAXED_CURL) * g, 0.0, 1.0),
		"ring": clampf(RELAXED_CURL + (1.0 - RELAXED_CURL) * g, 0.0, 1.0),
		"little": clampf(RELAXED_CURL + (1.0 - RELAXED_CURL) * g, 0.0, 1.0),
	}


## Система ладони по 26 позициям (мировым или любым): начало — сустав PALM, ось Z — назад к запястью, X — поперёк ладони, Y — нормаль ладони.
## Не зависит от того, откуда позиции (трекинг или кинематика).
static func palm_basis(pos: PackedVector3Array) -> Basis:
	var fwd := (pos[MIDDLE_PROX] - pos[WRIST]).normalized()
	var side := pos[LITTLE_PROX] - pos[INDEX_PROX]
	side = (side - fwd * side.dot(fwd)).normalized()
	var nrm := side.cross(fwd).normalized()
	return Basis(side, nrm, -fwd).orthonormalized()


## Куда смотрит тыл руки (единичный вектор): нормаль ладони с учётом руки — у зеркальной левой формула даёт ладонную сторону, её разворачиваем.
static func back_direction(pos: PackedVector3Array, left: bool) -> Vector3:
	var y := palm_basis(pos).y
	return -y if left else y


## Шаблон облака частиц, детерминированный по rng_seed. Каждая частица — строка [kind, a, b, t, u, v, size, weight, phase]:
##  kind 0 (точка на кости): a, b — суставы кости; t — вдоль кости 0…1; u — угол вокруг оси; v — доля радиуса;
##  kind 0 с a = -1 (ладонь): u, v — координаты на эллипсе ладони (-1…1), t — поверхность (-1 тыльная, 1 ладонная);
##  kind 0 с a = -2 (запястье): кольцо у запястья, u — угол;
##  kind 1 (искра): a — сустав-кончик, из которого поднимается штрих.
## size — полуразмер точки, м; weight — яркость 0…1 (поверхность ярче заполнения); phase — вдоль руки 0 (запястье) … 1 (кончики), для бегущей волны.
static func template(rng_seed: int = 1) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	for i in PALM_POINTS:  # ладонь: точки на двух поверхностях (тыльной и ладонной), в эллипсе, чуть гуще у края
		var r := sqrt(rng.randf()) * 0.96 + 0.04
		var ang := rng.randf() * TAU
		var surf := 1.0 if i % 2 == 0 else -1.0
		out.append([KIND_POINT, -1, -1, surf, cos(ang) * r, sin(ang) * r, rng.randf_range(0.0020, 0.0030), 0.45 + 0.4 * r, 0.15 + 0.2 * (sin(ang) * r * -0.5 + 0.5)])
	for bone in BONES.size():
		for i in BONE_POINTS:
			var t := (float(i) + rng.randf_range(0.1, 0.9)) / float(BONE_POINTS)
			var kind_roll := rng.randf()
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(0.85, 1.0)
			var wt := 0.8
			if kind_roll < 0.2:  # заполнение внутри кости: объём
				rad = rng.randf_range(0.0, 0.55)
				wt = 0.4
			elif kind_roll < 0.5:  # хребет: две линии вдоль кости (по нормали ладони и против неё), по ним читается каждый палец
				ang = (0.0 if i % 2 == 0 else PI) + rng.randf_range(-0.2, 0.2)
				rad = 1.0
				wt = 1.0
			var finger_phase := 0.3 + 0.7 * (float(bone % 3) + t) / 3.0
			var tip_bone: bool = TIPS.has(BONES[bone][1])  # последняя кость пальца: кончики ярче и крупнее, на них смотрит игрок
			out.append([KIND_POINT, BONES[bone][0], BONES[bone][1], t, ang, rad, rng.randf_range(0.0015, 0.0023) * (1.35 if tip_bone else 1.0), 1.0 if tip_bone else wt, finger_phase])
	for i in WRIST_POINTS:  # кольцо у запястья: «манжета», задаёт край руки
		out.append([KIND_POINT, -2, -2, 0.0, TAU * float(i) / float(WRIST_POINTS) + rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(0.0020, 0.0030), 0.7, 0.0])
	for tip in TIPS:  # искры над кончиками пальцев: тонкие вертикальные штрихи
		out.append([KIND_SPARK, tip, tip, 0.0, 0.0, 0.0, 0.0016, 0.9, rng.randf()])
	return out


## Число частиц одной руки.
static func particle_count() -> int:
	return PALM_POINTS + BONES.size() * BONE_POINTS + WRIST_POINTS + SPARK_COUNT

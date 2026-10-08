class_name HandView
extends Node3D
## Рука игрока от первого лица в нашем стиле: облако светящихся точек на 26 суставах (shared/hand_skeleton.gd), объёмный эффект «воксельного дисплея»
## (решётка 8 мм), волна света от запястья к кончикам и искры над пальцами. Одна рука — один MultiMesh (один вызов отрисовки), буфер экземпляров
## обновляется раз в кадр. Ставится ребёнком XROrigin3D (риг) с нулевым смещением: позы суставов — в системе рига.
##
## Откуда поза (по порядку): 1) pose_source — для тестов и просмотра; 2) трекинг рук XRHandTracker (/user/hand_tracker/left|right), если он есть и отдаёт данные
## (на Pico нужны feature handtracking в манифесте и согласие владельца, по умолчанию трекинга нет); 3) контроллер: поза grip ладонью, пальцы сгибаются
## курком (указательный) и хватом (остальные). Нет данных ни там, ни там — рука скрыта. Поза grip на Pico 4 не мерилась: калибровка — пара pitch и смещение
## (ComfortConfig, comfort.cfg: hand_pitch_deg, hand_offset_x/y/z).

const STRIDE := 20  # float на экземпляр: 12 — преобразование, 4 — цвет, 4 — данные
const TRACKER_LEFT := &"/user/hand_tracker/left"
const TRACKER_RIGHT := &"/user/hand_tracker/right"
## Чтобы поза от трекинга считалась годной: не меньше стольких суставов с верной позицией.
const MIN_VALID_JOINTS := 22
## Якорь запястья: подъём над тылом запястья и сдвиг к локтю (м). Дека лежит у запястья, не на пальцах и не на ладони.
const WRIST_ANCHOR_BACK := 0.045
const WRIST_ANCHOR_ELBOW := 0.075
## Посадка руки на контроллере по отзыву с очков: на 10% крупнее, повёрнута на 90° по часовой (вид сзади, вдоль пальцев; у левой, зеркальной, знак обратный), на 4 см к зрителю.
## Поверх калибровки comfort.cfg: она по-прежнему относительна этой посадки.
const HAND_SCALE := 1.1
const HAND_ROLL_DEG := 90.0
const HAND_TOWARD_VIEWER := 0.04
const SHADER := preload("res://assets/shaders/hand_particles.gdshader")
const SHADER_OCCLUDED := preload("res://assets/shaders/body_particles.gdshader")  # чужие руки: стены и плитки их закрывают
## Чужое тело видно издали: точка не мельче этого угла (≈ 2–3 пикселя на Pico 4), иначе на расстоянии нескольких метров она меньше пикселя.
const REMOTE_MIN_ANGLE := 0.002
const COLOR_HAND := Color(0.18, 0.72, 0.85)  # холодный голубой: свои руки не красные (красные — другие люди и угроза)
const COLOR_SPARK := Color(0.6, 0.95, 1.0)

## Проба 07.10 (по ролику владельца «частица, из которой собирается волюметрик»): точки рук рисуются анимированным глитч-блоком (GlitchSprite) вместо круглых.
## false — прежние круглые точки; решать по кадру с очков. Читается при создании руки.
static var glitch_sprite := true
## Масштаб спрайта относительно полуразмера точки. Очки П5 (08.10): «читаются, но примерно в 4 раза меньше» — было 1,0; 0,25 и 0,3 владелец счёл чересчур мелкими — «вполовину меньше»: 0,5 с яркостью ×1,8.
static var glitch_scale := 0.5
## Множитель яркости при спрайте (шейдер: intensity): площадь блока пропорциональна квадрату масштаба, без компенсации мелкий спрайт гаснет.
static var glitch_gain := 1.8

enum Mode { NONE, POSE_SOURCE, TRACKED, CONTROLLER }

var left := false
var controller: XRController3D
## Для тестов и просмотра: Callable() -> PackedVector3Array из 26 позиций в системе этого узла; пустой массив — руки нет.
var pose_source: Callable
var mode := Mode.NONE
## Цвет свечения и искр (свои руки голубые, чужие — цвет игрока, см. set_tint).
var tint := COLOR_HAND
## Рамка ладони, сгиб и признак «есть» по последнему кадру от контроллера: из них собирается поза для других игроков (AvatarPose).
var frame_valid := false
var frame_palm := Transform3D.IDENTITY
var frame_trigger := 0.0
var frame_hold := 0.0
## Калибровка позы grip: поворот вокруг X (вверх +) и смещение, в системе контроллера.
var grip_pitch_deg := 0.0
var grip_offset := Vector3.ZERO

## Якорь на запястье для деки и прочего, что носят на руке: на тыльной стороне запястья, ближе к локтю, панелью (+Z) от тыла руки, верх (+Y) к пальцам.
var wrist_anchor: Node3D
var _template: Array
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _buf := PackedFloat32Array()
var _pos := PackedVector3Array()
var _bone_of := PackedInt32Array()  # на частицу: номер кости в HandSkeleton.BONES (для точек на костях), иначе -1


func _init(is_left: bool = false, ctrl: XRController3D = null) -> void:
	left = is_left
	controller = ctrl
	name = "LeftHandView" if left else "RightHandView"
	_template = HandSkeleton.template(31 if left else 17)
	_buf.resize(_template.size() * STRIDE)
	_init_static_buffer()
	_bone_of.resize(_template.size())
	for i in _template.size():
		var tp: Array = _template[i]
		_bone_of[i] = _bone_index(int(tp[1]), int(tp[2])) if float(tp[0]) < 0.5 and int(tp[1]) >= 0 else -1
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	if glitch_sprite:
		_mat.set_shader_parameter("glitch_tex", GlitchSprite.texture())
		_mat.set_shader_parameter("glitch_mix", 1.0)
		_mat.set_shader_parameter("glitch_scale", glitch_scale)
		_mat.set_shader_parameter("intensity", glitch_gain)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mat
	_mm.mesh = quad
	_mm.instance_count = _template.size()
	_mm.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))  # частицы двигаются по кадрам; мелкий AABB их отсекал бы
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Particles"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	wrist_anchor = Node3D.new()
	wrist_anchor.name = "WristAnchor"
	add_child(wrist_anchor)
	visible = false


## Поля буфера, которые не меняются от кадра к кадру: базис (единичный), цвет и данные частицы. Каждый кадр перезаписываются только три числа положения.
func _init_static_buffer() -> void:
	for i in _template.size():
		var p: Array = _template[i]
		var col := COLOR_SPARK if float(p[0]) > 0.5 else COLOR_HAND
		var o := i * STRIDE
		_buf[o] = 1.0
		_buf[o + 5] = 1.0
		_buf[o + 10] = 1.0
		_buf[o + 12] = col.r
		_buf[o + 13] = col.g
		_buf[o + 14] = col.b
		_buf[o + 15] = 1.0
		_buf[o + 16] = p[6]
		_buf[o + 17] = p[8]
		_buf[o + 18] = p[0]
		_buf[o + 19] = p[7]


func _process(_delta: float) -> void:
	update_hand()


## Прочитать позу, пересчитать частицы и залить буфер. Видимость — по тому, есть ли поза.
func update_hand() -> void:
	_pos = read_pose()
	if _pos.size() != HandSkeleton.COUNT:
		visible = false
		mode = Mode.NONE if not pose_source.is_valid() else mode
		return
	visible = true
	fill_buffer(_pos)
	_mm.buffer = _buf
	_place_wrist_anchor(_pos)


## Якорь запястья по позе: начало — над тылом запястья у локтя, ось Z — от тыла руки, ось Y — к пальцам (панель читается, когда смотришь на запястье).
func _place_wrist_anchor(pos: PackedVector3Array) -> void:
	var pb := HandSkeleton.palm_basis(pos)
	var back := HandSkeleton.back_direction(pos, left)
	var fingers := -pb.z
	var x := fingers.cross(back).normalized()
	wrist_anchor.transform = Transform3D(Basis(x, fingers, back).orthonormalized(),
		pos[HandSkeleton.WRIST] + back * WRIST_ANCHOR_BACK + pb.z * WRIST_ANCHOR_ELBOW)


## Калибровка позы grip (ComfortConfig): поворот вокруг X и смещение в системе контроллера; у левой руки смещение по X зеркальное.
func calibrate(pitch_deg: float, offset: Vector3) -> void:
	grip_pitch_deg = pitch_deg
	grip_offset = Vector3(-offset.x if left else offset.x, offset.y, offset.z)


## Позиции 26 суставов в системе этого узла или пустой массив. Выставляет mode.
func read_pose() -> PackedVector3Array:
	frame_valid = false
	if pose_source.is_valid():
		var p: Variant = pose_source.call()
		mode = Mode.POSE_SOURCE
		return p if p is PackedVector3Array else PackedVector3Array()
	var tracked := _tracked_pose()
	if tracked.size() == HandSkeleton.COUNT:
		mode = Mode.TRACKED
		return tracked
	if controller != null and controller.get_has_tracking_data():
		mode = Mode.CONTROLLER
		frame_valid = true
		return controller_pose(controller.transform, controller.get_float("trigger"), controller.get_float("grip"))
	mode = Mode.NONE
	return PackedVector3Array()


## Трекинг рук: позиции суставов из XRHandTracker; пусто, если трекера нет, он не отдаёт данных или верных суставов мало.
func _tracked_pose() -> PackedVector3Array:
	var trk := XRServer.get_tracker(TRACKER_LEFT if left else TRACKER_RIGHT) as XRHandTracker
	if trk == null or not trk.has_tracking_data:
		return PackedVector3Array()
	var out := PackedVector3Array()
	out.resize(HandSkeleton.COUNT)
	var valid := 0
	for j in HandSkeleton.COUNT:
		if trk.get_hand_joint_flags(j) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID:
			valid += 1
		out[j] = trk.get_hand_joint_transform(j).origin
	return out if valid >= MIN_VALID_JOINTS else PackedVector3Array()


## Рамка ладони по позе grip: сдвиг к зрителю, калибровка comfort.cfg и поворот посадки (без масштаба — рамка едет по сети как есть, AvatarPose).
func palm_frame(grip: Transform3D) -> Transform3D:
	var roll := Basis(Vector3(0, 0, -1), deg_to_rad(-HAND_ROLL_DEG if left else HAND_ROLL_DEG))
	return grip * Transform3D(Basis.IDENTITY, Vector3(0, 0, HAND_TOWARD_VIEWER)) \
		* Transform3D(Basis(Vector3.RIGHT, deg_to_rad(grip_pitch_deg)), grip_offset) * Transform3D(roll, Vector3.ZERO)


## 26 суставов по рамке ладони и сгибу: пальцы по курку и хвату, размер руки с HAND_SCALE.
func pose_at(frame: Transform3D, trigger: float, hold: float) -> PackedVector3Array:
	var local := HandSkeleton.pose(HandSkeleton.curls_from_inputs(trigger, hold), left)
	var out := PackedVector3Array()
	out.resize(HandSkeleton.COUNT)
	for j in HandSkeleton.COUNT:
		out[j] = frame * (local[j] * HAND_SCALE)
	return out


## Поза от контроллера: система ладони = поза grip с калибровкой, пальцы по курку и хвату.
func controller_pose(grip: Transform3D, trigger: float, hold: float) -> PackedVector3Array:
	frame_palm = palm_frame(grip)
	frame_trigger = trigger
	frame_hold = hold
	return pose_at(frame_palm, trigger, hold)


## Цвет свечения: точки — c, искры — светлее. Меняет статичные поля буфера; на экран попадает при ближайшем update_hand.
func set_tint(c: Color) -> void:
	tint = c
	var spark := c.lerp(Color.WHITE, 0.5)
	for i in _template.size():
		var col := spark if float((_template[i] as Array)[0]) > 0.5 else c
		var o := i * STRIDE
		_buf[o + 12] = col.r
		_buf[o + 13] = col.g
		_buf[o + 14] = col.b


## Чужая рука: рисуется с проверкой глубины (стены её закрывают), а не поверх всего.
func set_occluded(on: bool) -> void:
	_mat.shader = SHADER_OCCLUDED if on else SHADER
	_mat.set_shader_parameter("min_angle", REMOTE_MIN_ANGLE if on else 0.0)


## Обновить положения частиц в буфере экземпляров по позиции суставов (остальные поля заданы один раз при создании).
func fill_buffer(pos: PackedVector3Array) -> void:
	var pb := HandSkeleton.palm_basis(pos)
	var origin := pos[HandSkeleton.PALM]
	var nrm := pb.y
	var frames := []  # на кость: [начало, направление*длина, e1, e2, r0, r1]
	for b in HandSkeleton.BONES:
		var a: Vector3 = pos[b[0]]
		var d: Vector3 = pos[b[1]] - a
		var dn := d.normalized() if d.length() > 0.0001 else Vector3.FORWARD
		var e1 := (nrm - dn * nrm.dot(dn)).normalized()
		if e1.length() < 0.5:
			e1 = pb.x
		frames.append([a, d, e1, dn.cross(e1), float(b[2]), float(b[3])])
	var i := 0
	for p in _template:
		var q: Vector3
		var kind: float = p[0]
		var a_idx: int = p[1]
		if kind > 0.5:  # искра над кончиком
			q = pos[a_idx]
		elif a_idx == -1:  # ладонь
			q = origin + pb.x * (float(p[4]) * HandSkeleton.PALM_HALF_W) + pb.z * (float(p[5]) * HandSkeleton.PALM_HALF_L + HandSkeleton.PALM_CENTER_Z) + pb.y * (float(p[3]) * HandSkeleton.PALM_THICK)
		elif a_idx == -2:  # кольцо у запястья
			q = pos[HandSkeleton.WRIST] + pb.x * (cos(float(p[4])) * 0.030) + pb.y * (sin(float(p[4])) * 0.020)
		else:  # точка на кости
			var f: Array = frames[_bone_of[i]]
			var t: float = p[3]
			var r: float = lerpf(f[4], f[5], t) * float(p[5])
			q = (f[0] as Vector3) + (f[1] as Vector3) * t + (f[2] as Vector3) * (cos(float(p[4])) * r) + (f[3] as Vector3) * (sin(float(p[4])) * r)
		var o := i * STRIDE
		_buf[o + 3] = q.x
		_buf[o + 7] = q.y
		_buf[o + 11] = q.z
		i += 1


static var _bone_lookup: Dictionary = {}


static func _bone_index(a: int, b: int) -> int:
	if _bone_lookup.is_empty():
		for k in HandSkeleton.BONES.size():
			_bone_lookup[HandSkeleton.BONES[k][0] * 100 + HandSkeleton.BONES[k][1]] = k
	return _bone_lookup.get(a * 100 + b, 0)


## Позиция частицы i по последнему заполнению буфера (для тестов).
func particle_position(i: int) -> Vector3:
	var o := i * STRIDE
	return Vector3(_buf[o + 3], _buf[o + 7], _buf[o + 11])


func particle_count() -> int:
	return _template.size()


func buffer() -> PackedFloat32Array:
	return _buf


func multimesh() -> MultiMesh:
	return _mm


func material() -> ShaderMaterial:
	return _mat


## Последняя прочитанная поза (26 позиций) или пусто.
func last_pose() -> PackedVector3Array:
	return _pos

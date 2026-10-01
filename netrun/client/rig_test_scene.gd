extends Node3D
## Сцена прототипа (V1 + V3): пол, один узел (площадка с постаментом), один берущийся объект и счётчик времени кадра в мире.
## Общая для плоской и VR-сборок; не игровой мир (его даёт сервер). Простая геометрия, без ассетов.
## Объект берёт СЕРВЕР: сцена только просит (grab_requested) и двигает объект после confirm_grab.
## Взять: VR — grip контроллера рядом с объектом; плоская сборка — F или левая кнопка мыши.

signal grab_requested(object_id: String)
signal frame_slow(ms: float)

const SLOW_FRAME_SEC := 1.0 / 72.0
const VR_REACH := 0.4
const FLAT_REACH := 3.0
const STATS_PERIOD := 0.5

var rig: XRRig
var pickup: MeshInstance3D
var held := false
var slow_frames := 0

var _pending_holder: Node3D
var _label: Label3D
var _acc := 0.0
var _count := 0
var _max_ms := 0.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.03, 0.06)
	add_child(env)
	_add_box(Vector3(40, 0.1, 40), Vector3(0, -0.05, 0), Color(0.1, 0.12, 0.18))
	# Узел: круглая площадка и постамент.
	_add_mesh(_cylinder(2.0, 0.1), Vector3(0, 0.05, -1.5), Color(0.1, 0.35, 0.45))
	_add_mesh(_cylinder(0.25, 0.9), Vector3(0, 0.45, -1.5), Color(0.2, 0.2, 0.3))
	pickup = _add_mesh(SphereMesh.new(), Vector3(0, 1.0, -1.5), Color(1.0, 0.6, 0.1))
	pickup.name = NetConfig.PICKUP_ID
	(pickup.mesh as SphereMesh).radius = 0.1
	(pickup.mesh as SphereMesh).height = 0.2
	# Счётчик кадра — надпись на панели в мире, не HUD.
	_add_box(Vector3(2.4, 0.5, 0.03), Vector3(0, 1.8, -3.5), Color(0.03, 0.03, 0.05))
	_label = Label3D.new()
	_label.position = Vector3(0, 1.8, -3.48)
	_label.pixel_size = 0.004
	_label.font_size = 48
	_label.text = "кадр …"
	add_child(_label)
	rig = preload("res://client/xr_rig.tscn").instantiate()
	add_child(rig)
	for hand in [rig.left_hand, rig.right_hand]:
		hand.button_pressed.connect(func(action: String):
			if action == "grip_click":
				try_grab(hand.global_position, VR_REACH, hand))


func _process(delta: float) -> void:
	_count += 1
	_acc += delta
	_max_ms = maxf(_max_ms, delta * 1000.0)
	if delta > SLOW_FRAME_SEC:
		slow_frames += 1
		frame_slow.emit(delta * 1000.0)
	if _acc >= STATS_PERIOD:
		_label.text = "кадр %.1f мс (макс %.1f)\nдолгих кадров: %d" % [_acc / _count * 1000.0, _max_ms, slow_frames]
		_acc = 0.0
		_count = 0
		_max_ms = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if rig.xr_active:
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if key or click:
		try_grab(rig.camera.global_position, FLAT_REACH, rig.camera)


## Просит сервер отдать объект, если он лежит и достаточно близко. Сам объект не двигает.
func try_grab(origin: Vector3, reach: float, holder: Node3D) -> bool:
	if held or _pending_holder != null or origin.distance_to(pickup.global_position) > reach:
		return false
	_pending_holder = holder
	grab_requested.emit(NetConfig.PICKUP_ID)
	return true


## Сервер подтвердил: объект переходит в руку (плоская сборка — перед камерой).
func confirm_grab() -> void:
	if _pending_holder == null:
		return
	pickup.reparent(_pending_holder, false)
	pickup.position = Vector3(0.25, -0.25, -0.7) if _pending_holder is Camera3D else Vector3.ZERO
	held = true
	_pending_holder = null


func deny_grab() -> void:
	_pending_holder = null


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	return c


func _add_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(b, pos, color)


func _add_mesh(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	m.mesh = mesh
	m.position = pos
	add_child(m)
	return m

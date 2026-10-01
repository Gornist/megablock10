class_name XRRig
extends XROrigin3D
## XR-риг сидя: голова только смотрит, движение — левым стиком, поворот — правым (рывками или плавно).
## В плоской сборке (нет очков) тот же риг: WASD, Q/E — рывок, мышь (ПКМ зажата) — осмотр, R — центровка.
## Логика — в shared/rig_math.gd. Камера двигается только по воле игрока.

signal xr_failed(reason: String)

@export var smooth_turn_enabled := false
@export var move_speed := RigMath.MOVE_SPEED
@export var snap_step_deg := RigMath.SNAP_STEP_DEG

var camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var xr_active := false
var _snap_armed := true
var _mouse_yaw := 0.0
var _mouse_pitch := 0.0


func _ready() -> void:
	camera = $XRCamera3D
	left_hand = $LeftHand
	right_hand = $RightHand
	right_hand.button_pressed.connect(_on_right_button)


## Пытается поднять OpenXR; без очков возвращает false и пишет понятную причину (риг остаётся плоским).
func start_xr() -> bool:
	var iface := XRServer.find_interface("OpenXR")
	if iface == null:
		return _fail("Интерфейс OpenXR недоступен (xr/openxr/enabled выключен или нет платформы)")
	if not iface.is_initialized() and not iface.initialize():
		return _fail("OpenXR не стартовал: очки не подключены или не запущен рантайм OpenXR")
	get_viewport().use_xr = true
	# Сидя: опорная точка — голова, а не пол.
	if "play_area_mode" in iface:
		iface.play_area_mode = XRInterface.XR_PLAY_AREA_SITTING
	xr_active = true
	recenter()
	return true


func _fail(reason: String) -> bool:
	push_warning("[netrun-xr] " + reason)
	xr_failed.emit(reason)
	return false


## Центровка: голова — над origin, взгляд — прямо (наклон головы сохраняется).
func recenter() -> void:
	if xr_active:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	else:
		_mouse_yaw = 0.0
		_mouse_pitch = 0.0
		camera.rotation = Vector3.ZERO
	position = RigMath.recenter_origin(position, camera.global_position, global_position)


func _on_right_button(action: String) -> void:
	if action == "by_button" or action == "ax_button":
		recenter()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	var turn_x := 0.0
	if xr_active:
		move = left_hand.get_vector2("primary")
		turn_x = right_hand.get_vector2("primary").x
	else:
		move = _flat_move()
		turn_x = _flat_turn()
	_apply_turn(turn_x, delta)
	var yaw := camera.global_rotation.y
	global_position += RigMath.move_velocity(move, yaw, move_speed) * delta


func _apply_turn(stick_x: float, delta: float) -> void:
	var deg := 0.0
	if smooth_turn_enabled:
		deg = RigMath.smooth_turn(stick_x, delta)
	else:
		var r := RigMath.snap_turn(stick_x, _snap_armed, snap_step_deg)
		_snap_armed = r["armed"]
		deg = r["delta_deg"]
	if deg != 0.0:
		_rotate_around_head(deg_to_rad(deg))


## Вращение origin вокруг головы, чтобы взгляд повернулся, а игрок остался на месте.
func _rotate_around_head(rad: float) -> void:
	var head := camera.global_position
	var offset := global_position - head
	global_position = head + offset.rotated(Vector3.UP, rad)
	rotate_y(rad)


func _key_axis(neg: Key, pos: Key) -> float:
	return float(Input.is_physical_key_pressed(pos)) - float(Input.is_physical_key_pressed(neg))


func _flat_move() -> Vector2:
	return Vector2(_key_axis(KEY_A, KEY_D), _key_axis(KEY_S, KEY_W))


func _flat_turn() -> float:
	return _key_axis(KEY_Q, KEY_E)


func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_yaw -= event.relative.x * 0.003
		_mouse_pitch = clampf(_mouse_pitch - event.relative.y * 0.003, -1.4, 1.4)
		camera.rotation = Vector3(_mouse_pitch, _mouse_yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		recenter()

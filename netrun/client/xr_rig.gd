class_name XRRig
extends XROrigin3D
## XR-риг сидя: голова только смотрит, движение — левым стиком, поворот — правым (рывками или плавно).
## В плоской сборке (нет очков) тот же риг: WASD, Q/E — рывок, мышь (ПКМ зажата) — осмотр, R — центровка.
## Логика — в shared/rig_math.gd. Камера двигается только по воле игрока.

signal xr_failed(reason: String)
## Экстренное отключение: причина — ExitLogic.REASON_*; подключает к сети тот, кто собрал клиент.
signal exit_requested(reason: String)
signal recentered(xr: bool)

@export var smooth_turn_enabled := false
@export var move_speed := RigMath.MOVE_SPEED
@export var snap_step_deg := RigMath.SNAP_STEP_DEG
## Кнопка удержания в VR (действие XRController3D); настройкой можно заменить, например на "grip_click".
@export var exit_button := "menu_button"
@export var exit_hold_sec := ExitLogic.HOLD_SEC

var camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var xr_active := false
## Идёт цифровой тоннель (W1): ход заблокирован, пока сервер не поставит игрока в новый узел. Поворот головы и рывки — как всегда.
var movement_locked := false
var _snap_armed := true
var _mouse_yaw := 0.0
var _mouse_pitch := 0.0
var _exit_state := ExitLogic.hold_new()
var _exit_vr_pressed := false
var _exit_bar: MeshInstance3D


func _ready() -> void:
	camera = $XRCamera3D
	left_hand = $LeftHand
	right_hand = $RightHand
	right_hand.button_pressed.connect(_on_right_button)
	left_hand.button_pressed.connect(_on_exit_button.bind(true))
	left_hand.button_released.connect(_on_exit_button.bind(false))
	right_hand.button_pressed.connect(_on_exit_button.bind(true))
	right_hand.button_released.connect(_on_exit_button.bind(false))
	_build_exit_bar()


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
	# Снял очки / потерян фокус — тот же запрос, что и удержание (сигналы есть не во всех версиях).
	for sig in ["session_stopping", "focus_lost"]:
		if iface.has_signal(sig):
			iface.connect(sig, _request_exit.bind(ExitLogic.REASON_HEADSET_OFF))
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
	recentered.emit(xr_active)


func _on_right_button(action: String) -> void:
	if action == "by_button" or action == "ax_button":
		recenter()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_request_exit(ExitLogic.REASON_HEADSET_OFF)


func _request_exit(reason: String) -> void:
	exit_requested.emit(reason)


func _on_exit_button(action: String, pressed: bool) -> void:
	if action == exit_button:
		_exit_vr_pressed = pressed


## Полоса удержания — предмет мира перед глазами (ребёнок камеры), не HUD: растёт слева направо.
func _build_exit_bar() -> void:
	_exit_bar = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.3, 0.01, 0.002)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.2)
	mat.no_depth_test = true
	b.material = mat
	_exit_bar.mesh = b
	_exit_bar.position = Vector3(0, -0.15, -0.6)
	_exit_bar.visible = false
	camera.add_child(_exit_bar)


func _update_exit_hold(delta: float) -> void:
	var pressed := _exit_vr_pressed if xr_active else Input.is_physical_key_pressed(KEY_ESCAPE)
	_exit_state = ExitLogic.hold_step(_exit_state, pressed, delta, exit_hold_sec)
	var p: float = _exit_state["progress"]
	_exit_bar.visible = p > 0.0
	_exit_bar.scale.x = maxf(p, 0.001)
	_exit_bar.position.x = -0.15 * (1.0 - p)
	if _exit_state["just_fired"]:
		_request_exit(ExitLogic.REASON_MANUAL_HOLD)


func _process(delta: float) -> void:
	_update_exit_hold(delta)
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
	if not movement_locked:
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

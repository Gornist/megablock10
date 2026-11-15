extends "res://assets/look_v11/look_v11.gd"
## VR-демо эталона V11 на Pico 4: та же сцена, точки из запечённых наборов (assets/look_v11/baked, пишет look_v11 --bake).
## Отдельное приложение com.megablok10.lookv11 (собирает pico_demo.sh в копии проекта) — игру на очках не трогает.
## Управление: A / X или курок — следующая точка обзора (общий → у колонны → пол вдаль), правый стик влево/вправо — поворот 45°.
## В журнал (adb logcat -s godot) раз в 2 с: `LOOKVR fps=… ` — замер цены вида на очках.

const VIEWS := [  # [позиция пола, взгляд] — те же ракурсы, что кадры эталона на ПК
	[Vector3(2.0, 0.0, 7.2), Vector3(-0.2, 1.0, -6.0)],
	[Vector3(0.9, 0.0, 4.2), Vector3(2.6, 1.0, 2.2)],
	[Vector3(-1.2, 0.0, 7.4), Vector3(-0.3, 0.0, -1.5)],
]

var _origin: XROrigin3D
var _xr_cam: XRCamera3D
var _view := 0
var _fps_t := 0.0
var _turn_armed := true
var _eye_h := 1920.0


func _ready() -> void:
	_have_baked = DirAccess.dir_exists_absolute(BAKED_DIR)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = VOID
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_origin = XROrigin3D.new()
	add_child(_origin)
	_xr_cam = XRCamera3D.new()
	_xr_cam.far = 60.0
	_origin.add_child(_xr_cam)
	for side in ["left_hand", "right_hand"]:
		var c := XRController3D.new()
		c.tracker = side
		c.button_pressed.connect(_on_button)
		_origin.add_child(c)
		if side == "right_hand":
			c.input_vector2_changed.connect(_on_stick)
	var iface := XRServer.find_interface("OpenXR")
	if iface and (iface.is_initialized() or iface.initialize()):
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X  # база клиента на Pico (решение 08.10)
		var oxr := iface as OpenXRInterface
		if oxr and 90.0 in oxr.get_available_display_refresh_rates():
			oxr.display_refresh_rate = 90.0
		_eye_h = iface.get_render_target_size().y
		print("LOOKVR xr ok, глаз %s, запечено=%s" % [iface.get_render_target_size(), _have_baked])
	else:
		print("LOOKVR OpenXR не поднялся — плоский режим")
	var t0 := Time.get_ticks_msec()
	var n := _build()
	print("LOOKVR сцена: точек %d, %d мс" % [n, Time.get_ticks_msec() - t0])
	_set_view(0)


func _vp_h() -> float:
	return _eye_h


func _set_view(i: int) -> void:
	_view = i % VIEWS.size()
	var pos: Vector3 = VIEWS[_view][0]
	var look: Vector3 = VIEWS[_view][1]
	var d := look - pos
	_origin.transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), pos)
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)


func _on_button(action: String) -> void:
	if action in ["ax_button", "trigger_click"]:
		_set_view(_view + 1)


func _on_stick(action: String, v: Vector2) -> void:
	if action != "primary":
		return
	if absf(v.x) < 0.3:
		_turn_armed = true
	elif _turn_armed and absf(v.x) > 0.7:
		_turn_armed = false
		var head := _xr_cam.global_position
		_origin.rotate_y(-signf(v.x) * PI / 4.0)
		_origin.global_position += head - _xr_cam.global_position


func _process(delta: float) -> void:
	for hl in _halos:
		hl.look_at(_xr_cam.global_position, Vector3.UP)
		hl.rotate_object_local(Vector3.UP, PI)
	_fps_t += delta
	if _fps_t >= 2.0:
		_fps_t = 0.0
		print("LOOKVR fps=%d вид=%d" % [Engine.get_frames_per_second(), _view])

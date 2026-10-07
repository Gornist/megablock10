class_name XRRig
extends XROrigin3D
## XR-риг сидя: голова только смотрит, двигаемся телепортом, поворачивается сам игрок (решения владельца, 4 октября 2026, после
## теста на Pico 4: ходьба стиком, рывок 30° и плавный поворот стиком слишком укачивают, поворот самим игроком — нет).
##
## Телепорт и поворот — один правый стик. Отклонил и держишь (за порог в любую сторону) — дуга-прицел от правого контроллера и кольцо
## в точке посадки (зелёное — можно, красное — нельзя или перезарядка) со стрелкой «куда смотреть после прыжка»: она плавно
## разворачивается вслед за положением стика (вверх — как сейчас, вправо/влево — 90°, вниз — 180°). Отпустил стик — «моргание»:
## затемнение, перенос и поворот в самой тёмной точке, проявление (~0,2 с, камера не скользит, мир на глазах не вращается).
## Нажатие стика — отмена. Дальность и перезарядка — RigMath.TELEPORT_*; сервер проверяет сам (NetServer), отказ возвращает риг на место.
## Вращение мира стиком (левый стик по X) — только turn_mode = smooth (плавно, 60°/с, виньетка по краям, ComfortFx) или snap (рывок
## 30°), настройки для других игроков и разработки. Все числа ощущений настраиваются без пересборки (ComfortConfig).
## Плоская (разработческая) сборка, тот же риг: T зажата — прицел по взгляду, отпустить — телепорт, C — отмена; при зажатой T Q/E
## выбирают поворот при телепорте (∓90°); WASD-ходьба — только с флагом --walk; мышь (ПКМ зажата) — осмотр, R — центровка.
## Логика — в shared/rig_math.gd. Камера двигается только по воле игрока.

signal xr_failed(reason: String)
## Экстренное отключение: причина — ExitLogic.REASON_*; подключает к сети тот, кто собрал клиент.
signal exit_requested(reason: String)
## События «ушёл из игры» для журнала: kind — begin | end | exit; source — pause | focus | session | presence; sec — сколько уже нет.
signal away_event(kind: String, source: String, sec: float)
signal recentered(xr: bool)
## Игрок отпустил стик прицела: from/to — точки на полу (риг, где стоял / куда идёт); ok = false — отказ на месте, reason —
## WorldMsg.REASON_* (перезарядка, тоннель). При ok = true клиент просит сервер (ProtoClient), риг переедет в тёмной точке моргания.
signal teleport_attempted(from: Vector3, to: Vector3, ok: bool, reason: String)

@export var turn_mode := RigMath.TURN_MODE_DEFAULT
@export var turn_speed_deg_s := RigMath.TURN_SPEED_DEG_S
@export var turn_ramp_up_s := RigMath.TURN_RAMP_UP_SEC
@export var turn_ramp_down_s := RigMath.TURN_RAMP_DOWN_SEC
## Насколько закрываются края поля зрения при полной скорости поворота (0 — виньетки нет).
@export var turn_vignette := RigMath.TURN_VIGNETTE_MAX
@export var snap_step_deg := RigMath.SNAP_STEP_DEG
@export var teleport_range := RigMath.TELEPORT_RANGE
@export var teleport_cooldown := RigMath.TELEPORT_COOLDOWN
## Затемнение и проявление моргания — каждое по этому времени.
@export var teleport_blink_s := RigMath.TELEPORT_BLINK_SEC
## Ходьба WASD в плоской сборке (--walk, для разработки и старых сценариев); в VR ходьбы нет.
@export var walk_enabled := false
@export var move_speed := RigMath.MOVE_SPEED
## Кнопка удержания в VR (действие XRController3D); настройкой можно заменить, например на "grip_click".
@export var exit_button := "menu_button"
@export var exit_hold_sec := ExitLogic.HOLD_SEC

var camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
## Левый контроллер в позе «aim» (направление указки): от неё целимся. Нет данных — берём руку (grip).
var right_aim: XRController3D
var xr_active := false
## Настройки рендера (netrun.cfg [render]); клиент подставляет прочитанные до start_xr, по умолчанию — msaa выкл., aa none, масштаб 1, фовеация 2.
var render := RenderConfig.new()
## Свойства OpenXR-интерфейса, которых нет в этой версии Godot (RenderConfig.apply_xr); клиент пишет их в журнал.
var xr_render_missing := PackedStringArray()
## Идёт цифровой тоннель (W1): телепорт запрещён, пока сервер не поставит игрока в новый узел. Поворот головы и поворот стиком — как всегда.
var movement_locked := false
var aim_visual: TeleportAim
## Руки в нашем стиле (облако светящихся точек): по контроллерам, а при трекинге рук — по суставам. Скрыты, пока нет данных позы.
var left_hand_view: HandView
var right_hand_view: HandView
var fx: ComfortFx
var _snap_armed := true
var _mouse_yaw := 0.0
var _mouse_pitch := 0.0
var _exit_state := ExitLogic.hold_new()
var _exit_vr_pressed := false
var _exit_bar: MeshInstance3D
var _turn_rate := 0.0          # текущая угловая скорость, °/с (вправо — минус)
var _vignette := 0.0
var _aim := RigMath.aim_new()
var _aim_info: Dictionary = {}
## Клетки комнаты: прицел притягивается к достижимой клетке 1 м (NodeGrid.pick), занятые колоннами показывает серыми.
var grid: NodeGrid = NodeGrid.for_layout()
var _last_pick := Vector3.ZERO
## Такты узла (RemoteTracks сцены): намерения ICE, tk и секунды до такта. Не задан или без tk в снимках — прежний режим (перезарядка, зелёная рамка).
var tick_source: RemoteTracks
var _hold_cell := Vector2i(-9999, -9999)   # клетка, на которой стоит рамка прицела, и сколько секунд (залипание красной, stealth.md С9)
var _hold_t := 0.0
var _last_threat := -1                     # прогноз TickForecast для клетки под последним показанным прицелом (−1 — не тактовый / не hop)
var _moved_n := -1                         # номер такта, на котором сервер отказал «moved»: до следующего такта показываем «ход принят»
var _since_tp := INF       # секунд с прошлого телепорта
var _tp_click := false
var _blink := RigMath.blink_new()
var _blink_dest := Vector3.ZERO
var _queued_dest: Variant = null
var away := AwayGuard.new()   # окно на «ушёл из игры» (пауза, фокус, датчик на лбу): выход только после AwayGuard.GRACE_SEC
var _face_deg := 0.0           # куда смотреть после прыжка (RigMath.facing_deg), пока наведён прицел; вправо — плюс
var _blink_face_deg := 0.0     # то же для идущего моргания: применяется в самой тёмной точке
## Привязка точки телепорта к площадке у хранилища (К3): func(Vector3) -> {p: Vector3, look: Vector3 | null}; не задана — цель как есть.
## look — хранилище, к которому в самой тёмной точке моргания разворачивается взгляд (панель взлома и шард тогда прямо перед игроком).
var teleport_snap: Callable
var _blink_look: Variant = null


func _ready() -> void:
	camera = $XRCamera3D
	left_hand = $LeftHand
	right_hand = $RightHand
	right_aim = get_node_or_null("RightAim") as XRController3D
	right_hand.button_pressed.connect(_on_right_button)
	left_hand.button_pressed.connect(_on_exit_button.bind(true))
	left_hand.button_released.connect(_on_exit_button.bind(false))
	right_hand.button_pressed.connect(_on_exit_button.bind(true))
	right_hand.button_released.connect(_on_exit_button.bind(false))
	_build_exit_bar()
	fx = ComfortFx.new()
	camera.add_child(fx)
	aim_visual = TeleportAim.new()
	add_child(aim_visual)
	left_hand_view = HandView.new(true, left_hand)
	right_hand_view = HandView.new(false, right_hand)
	add_child(left_hand_view)
	add_child(right_hand_view)


## Пытается поднять OpenXR; без очков возвращает false и пишет понятную причину (риг остаётся плоским).
func start_xr() -> bool:
	var iface := XRServer.find_interface("OpenXR")
	if iface == null:
		return _fail("Интерфейс OpenXR недоступен (xr/openxr/enabled выключен или нет платформы)")
	if not iface.is_initialized() and not iface.initialize():
		return _fail("OpenXR не стартовал: очки не подключены или не запущен рантайм OpenXR")
	get_viewport().use_xr = true
	# Сглаживание, масштаб и фовеация из netrun.cfg [render] — один раз при старте (RenderConfig).
	render.apply_msaa(get_viewport())
	xr_render_missing = render.apply_xr(iface)
	# Панели слоями композитора: хосты (XrLayerHost) решают по этому флагу в первом кадре, когда XR уже поднят.
	XrLayerHost.layers_requested = RenderConfig.layers_enabled(render.layers)
	# Сидя: опорная точка — голова, а не пол.
	if "play_area_mode" in iface:
		iface.play_area_mode = XRInterface.XR_PLAY_AREA_SITTING
	xr_active = true
	# Ушёл из игры (снял очки, системное меню, остановка сессии): выход с причиной headset_off только если не вернулся за
	# AwayGuard.GRACE_SEC. В Godot 4.7 у OpenXRInterface нет сигнала focus_lost: потеря фокуса — session_visible (видно, но без
	# фокуса), возвращение — session_focussed; снятие очков — user_presence_changed(false), если рантайм сообщает присутствие.
	_connect_away(iface, "session_visible", "focus", true)
	_connect_away(iface, "session_focussed", "focus", false)
	_connect_away(iface, "session_stopping", "session", true)
	_connect_away(iface, "session_begun", "session", false)
	if iface.has_signal("user_presence_changed"):
		iface.connect("user_presence_changed", func(present: bool): _away_signal("presence", not present))
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
	elif action == "primary_click":
		_tp_click = true   # нажатие правого стика — отмена прицела


func _connect_away(iface: Object, sig: String, source: String, begin: bool) -> void:
	if iface.has_signal(sig):
		iface.connect(sig, func(): _away_signal(source, begin))


func _away_signal(source: String, begin: bool) -> void:
	if begin:
		away_begin(source, Time.get_ticks_msec())
	else:
		away_end(source, Time.get_ticks_msec())


## Причина «ушёл» началась (время подают тесты; в игре — Time.get_ticks_msec()).
func away_begin(source: String, now_ms: int) -> void:
	away.begin(source, now_ms)
	away_event.emit("begin", source, 0.0)


## Причина кончилась; вернулся после окна — запрос выхода headset_off.
func away_end(source: String, now_ms: int) -> void:
	var sec := away.away_sec(now_ms)
	if not away.is_away():
		return
	var late := away.end(source, now_ms)
	away_event.emit("end", source, sec)
	if late:
		away_event.emit("exit", source, sec)
		_request_exit(ExitLogic.REASON_HEADSET_OFF)


## Каждый кадр: потеря фокуса без паузы затянулась дольше окна.
func away_tick(now_ms: int) -> void:
	if away.is_away():
		var sec := away.away_sec(now_ms)
		if away.due(now_ms):
			away_event.emit("exit", "timeout", sec)
			_request_exit(ExitLogic.REASON_HEADSET_OFF)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		away_begin("pause", Time.get_ticks_msec())
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		away_end("pause", Time.get_ticks_msec())


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
	away_tick(Time.get_ticks_msec())
	_update_exit_hold(delta)
	var turn_x := 0.0
	var tp_stick := Vector2.ZERO
	var walk := Vector2.ZERO
	if xr_active:
		tp_stick = right_hand.get_vector2("primary")    # телепорт: правый стик — отклонил и держишь, отпустил
		turn_x = left_hand.get_vector2("primary").x     # вращение мира левым стиком — только turn_mode smooth/snap (настройка)
	else:
		turn_x = _flat_turn()
		if Input.is_physical_key_pressed(KEY_T):
			tp_stick = Vector2(turn_x, 0.0) if turn_x != 0.0 else Vector2(0.0, 1.0)   # T — прицел; T + Q/E — поворот ∓90°
		walk = _flat_move()
	var clicked := _tp_click
	_tp_click = false
	drive(turn_x, tp_stick, clicked, delta, walk)


## Один шаг управления по готовому вводу (так же зовут тесты): turn_x — вращение мира (левый стик по X или Q/E; только режимы smooth
## и snap), tp_stick — правый стик телепорта (x вправо, y вперёд: отклонил — прицел, положение стика — поворот при телепорте, вернул
## к центру — прыжок), clicked — нажатие стика (отмена), walk — ходьба WASD (только плоская сборка с walk_enabled).
func drive(turn_x: float, tp_stick: Vector2, clicked: bool, delta: float, walk: Vector2 = Vector2.ZERO) -> void:
	_since_tp += delta
	_apply_turn(turn_x, delta)
	if walk_enabled and not xr_active and not movement_locked:
		global_position += RigMath.move_velocity(walk, camera.global_rotation.y, move_speed) * delta
	_step_teleport(tp_stick, clicked, delta)
	_step_blink(delta)


# ---------------------------------------------------------------- поворот

func _apply_turn(stick_x: float, delta: float) -> void:
	var target_vignette := 0.0
	if turn_mode == RigMath.TURN_MODE_NONE:
		_turn_rate = 0.0   # стик мир не вращает: игрок поворачивается сам, а при телепорте — поворот в моргании
	elif turn_mode == RigMath.TURN_MODE_SNAP:
		var r := RigMath.snap_turn(stick_x, _snap_armed, snap_step_deg)
		_snap_armed = r["armed"]
		_turn_rate = 0.0
		if r["delta_deg"] != 0.0:
			_rotate_around_head(deg_to_rad(r["delta_deg"]))
	else:
		var speed := clampf(turn_speed_deg_s, 0.0, RigMath.TURN_SPEED_MAX_DEG_S)
		_turn_rate = RigMath.turn_rate_step(_turn_rate, RigMath.turn_target_rate(stick_x, speed), delta, speed, turn_ramp_up_s, turn_ramp_down_s)
		if _turn_rate != 0.0:
			_rotate_around_head(deg_to_rad(_turn_rate * delta))
		target_vignette = RigMath.vignette_target(_turn_rate, turn_vignette)
	_vignette = RigMath.vignette_step(_vignette, target_vignette, delta, turn_vignette)
	fx.set_vignette(_vignette)


## Вращение origin вокруг головы, чтобы взгляд повернулся, а игрок остался на месте.
func _rotate_around_head(rad: float) -> void:
	var head := camera.global_position
	var offset := global_position - head
	global_position = head + offset.rotated(Vector3.UP, rad)
	rotate_y(rad)


## Затемнение краёв сейчас (0…turn_vignette).
func vignette_amount() -> float:
	return _vignette


# ---------------------------------------------------------------- телепорт

func is_aiming() -> bool:
	return _aim["aiming"]


## Центр клетки, выбранной последним принятым телепортом (до привязки к площадке у хранилища): его клиент просит у сервера.
func last_pick() -> Vector3:
	return _last_pick


## Точка посадки, на которую сейчас наведён прицел (пол); нули, пока не целимся.
func aim_target() -> Vector3:
	return _aim_info.get("p", Vector3.ZERO)


func blink_alpha() -> float:
	return _blink["alpha"]


func teleport_cooldown_left() -> float:
	return RigMath.cooldown_left(_since_tp, teleport_cooldown)


func _step_teleport(stick: Vector2, clicked: bool, delta: float) -> void:
	if movement_locked:
		if _aim["aiming"]:
			_cancel_aim()
		return
	_aim = RigMath.aim_step(_aim, stick, clicked, delta)
	# Поворот при телепорте — угол того же стика, пока он отклонён: при отпускании стик возвращается к центру, и берётся последнее
	# значение «держу» (слабее RigMath.FACING_STICK_MIN угол не обновляем).
	if turn_mode == RigMath.TURN_MODE_NONE and _aim["aiming"] and stick.length() >= RigMath.FACING_STICK_MIN:
		_face_deg = RigMath.facing_deg(stick)
	elif not _aim["aiming"] and _aim["event"] != RigMath.AIM_FIRE:
		_face_deg = 0.0
	match _aim["event"]:
		RigMath.AIM_CANCEL:
			_cancel_aim()
		RigMath.AIM_FIRE:
			aim_visual.hide_aim()
			_fire_teleport()
			_aim_info = {}
			_reset_hold()
	if _aim["aiming"]:
		_show_aim(delta)


func _reset_hold() -> void:
	_hold_cell = Vector2i(-9999, -9999)
	_hold_t = 0.0


func _cancel_aim() -> void:
	_aim = RigMath.aim_new()
	_aim_info = {}
	_reset_hold()
	_face_deg = 0.0
	aim_visual.hide_aim()


## Откуда и куда смотрит указка: VR — контроллер в позе aim (нет данных — рука), плоская сборка — взгляд.
func _aim_pose() -> Dictionary:
	if xr_active:
		var n: Node3D = right_aim if right_aim != null and right_aim.get_has_tracking_data() else right_hand
		return {"origin": n.global_position, "dir": -n.global_basis.z, "arc_from": n.global_position}
	var c := camera.global_transform
	var dir := -c.basis.z
	return {"origin": c.origin, "dir": dir, "arc_from": c.origin + dir * 0.4 + Vector3(0.0, -0.25, 0.0)}


## Поле tk последнего снимка (пусто — не тактовый режим).
func _tick_info() -> Dictionary:
	return tick_source.tick_info() if tick_source != null else {}


## Ход в этом такте уже принят: сервер сообщил tk.mv или отказал «moved» на этом такте.
func _tick_moved(tick: Dictionary) -> bool:
	return int(tick.get("mv", 0)) == 1 or _moved_n == int(tick.get("n", -2))


## Прогноз TickForecast для клетки под последним показанным прицелом (0 / 1 / 2); −1 — не тактовый режим или не прыжок.
func last_threat() -> int:
	return _last_threat


## Сколько секунд рамка прицела стоит на текущей клетке.
func aim_hold_sec() -> float:
	return _hold_t


func _show_aim(delta: float = 0.0) -> void:
	var pose := _aim_pose()
	var info := RigMath.teleport_aim(pose["origin"], pose["dir"], global_position, teleport_range, global_position.y)
	if info["valid"]:
		# Прицел притягивается к клетке: «p» — центр выбранной клетки (сюда ляжет прыжок), «raw» — куда указывает рука.
		var pick := grid.pick(global_position, info["p"])
		info["raw"] = info["p"]
		info["p"] = Vector3(pick["p"].x, global_position.y, pick["p"].z)
		info["kind"] = pick["kind"]
		info["reason"] = pick["reason"]
		info["cell"] = pick["cell"]
	_aim_info = info
	var left := teleport_cooldown_left()
	var ok: bool = info["valid"] and left <= 0.0 and info.get("kind", "") == "hop"
	var charge := 1.0 if left <= 0.0 else 1.0 - left / maxf(teleport_cooldown, 0.001)
	var cell: Vector2i = info.get("cell", Vector2i(-9999, -9999))
	if cell == _hold_cell:
		_hold_t += delta
	else:
		_hold_cell = cell
		_hold_t = 0.0
	var kind: String = info.get("kind", "")
	var threat := -1
	var note := ""
	var tick := _tick_info()
	_last_threat = -1
	if not tick.is_empty():
		# Тактовый режим: перезарядки на клиенте нет (сервер: «ход один за такт»), рамка красится прогнозом, подписи — «ход принят» / «ждать».
		var moved := _tick_moved(tick)
		ok = info["valid"] and kind == "hop" and not moved
		charge = 1.0
		if kind == "hop" and info["valid"]:
			threat = TickForecast.threat(grid, tick_source.intents(), cell)
			_last_threat = threat
		if moved and kind != "denied":
			note = "ХОД ПРИНЯТ"
		elif kind == "wait":
			note = "ЖДАТЬ · ОКНО ЧЕРЕЗ %d" % tick_source.window_left(Time.get_ticks_msec() / 1000.0)
	aim_visual.show_at(pose["arc_from"], info["p"], ok, charge, kind, info.get("reason", ""), threat, note)
	aim_visual.set_heading(_heading_after_teleport())


## Поворот идущего моргания, градусы вправо (0 — без поворота): для журнала `rig.teleport … face=`.
func pending_face_deg() -> float:
	return _blink_face_deg


## Куда игрок будет смотреть после прыжка: горизонтальный взгляд сейчас, повёрнутый на выбранные градусы вправо.
func _heading_after_teleport() -> Vector3:
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return Vector3.ZERO
	return fwd.normalized().rotated(Vector3.UP, -deg_to_rad(_face_deg))


func _fire_teleport() -> void:
	if _aim_info.is_empty() or not _aim_info["valid"]:
		return
	var from := global_position
	var to: Vector3 = _aim_info["p"]
	to.y = from.y
	var kind: String = _aim_info.get("kind", "")
	var tick := _tick_info()
	var in_ticks := not tick.is_empty()
	if kind == "denied":
		teleport_attempted.emit(from, to, false, str(_aim_info.get("reason", "")))   # клетка закрыта: рамка уже была серой
		return
	if in_ticks and _tick_moved(tick):
		teleport_attempted.emit(from, to, false, WorldMsg.REASON_MOVED)   # ход в этом такте уже сделан: запрос не уходит до следующего такта
		return
	if kind == "wait":
		if in_ticks:
			# «Ждать» — ход: серверу уходит центр своей клетки (сервер считает это ходом «ждать»); риг остаётся на месте.
			_last_pick = Vector3(to.x, from.y, to.z)
			teleport_attempted.emit(from, _last_pick, true, "wait")
		return   # без тактов: прицел в свою клетку, двигаться некуда
	if in_ticks and _last_threat == TickForecast.RED and not TickForecast.red_hold_ok(_hold_t):
		teleport_attempted.emit(from, to, false, "hold")   # залипание красной: рамка не простояла на клетке 0,4 с — отмена без запроса
		return
	# Клетка уже проверена по дальности (центр до центра), а сам игрок стоит не в центре своей клетки: запас — одна клетка.
	# В тактовом режиме перезарядки на клиенте нет: ход один за такт считает сервер.
	var cooldown := 0.0 if in_ticks else teleport_cooldown
	var reason := RigMath.teleport_verdict(from, to, _since_tp, movement_locked, teleport_range + NodeGrid.CELL_M, cooldown)
	if not reason.is_empty():
		teleport_attempted.emit(from, to, false, reason)
		return
	var look: Variant = null
	_last_pick = to   # серверу уходит выбранная клетка (до площадки): он проверяет её и сам привязывает к площадке теми же правилами
	if teleport_snap.is_valid():
		var snapped_to: Dictionary = teleport_snap.call(to)
		to = Vector3(snapped_to["p"].x, from.y, snapped_to["p"].z)
		look = snapped_to.get("look")
	_since_tp = 0.0
	_start_blink(to, _face_deg, look)
	teleport_attempted.emit(from, to, true, "")


func _start_blink(dest: Vector3, face_deg: float = 0.0, look: Variant = null) -> void:
	_blink = RigMath.blink_start()
	_blink_dest = dest
	_blink_face_deg = face_deg
	_blink_look = look


func _step_blink(delta: float) -> void:
	if _blink["phase"] == 0:
		return
	_blink = RigMath.blink_step(_blink, delta, teleport_blink_s)
	if _blink["moved"]:
		global_position = Vector3(_blink_dest.x, global_position.y, _blink_dest.z)
		if _blink_look != null:
			face_toward(_blink_look)   # площадка у хранилища: взгляд на него, выбранный поворот стиком не нужен
			_blink_look = null
			_blink_face_deg = 0.0
		elif _blink_face_deg != 0.0:
			_rotate_around_head(-deg_to_rad(_blink_face_deg))   # вправо — по часовой, yaw уменьшается; экран в этот момент чёрный
			_blink_face_deg = 0.0
	fx.set_blink(_blink["alpha"])
	if _blink["phase"] == 0 and _queued_dest != null:
		_start_blink(_queued_dest as Vector3)
		_queued_dest = null


## Развернуть риг вокруг головы так, чтобы горизонтальный взгляд смотрел на точку target.
func face_toward(target: Vector3) -> void:
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	var want := target - camera.global_position
	want.y = 0.0
	if fwd.length() < 0.001 or want.length() < 0.001:
		return
	_rotate_around_head(fwd.signed_angle_to(want, Vector3.UP))


## Сервер отказал в телепорте (NetClient.teleport_denied): риг возвращается в позицию аватара на сервере. Если затемнение ещё не
## дошло до переноса, переноса не будет вовсе — риг остаётся там, где сервер. Перезарядку берём у сервера.
func apply_teleport_denial(reason: String, server_pos: Vector3, left: float) -> void:
	if reason == WorldMsg.REASON_MOVED and tick_source != null:
		_moved_n = int(tick_source.tick_info().get("n", -1))   # ход уже сделан: до следующего такта прицел пишет «ХОД ПРИНЯТ»
	if reason == WorldMsg.REASON_COOLDOWN and left > teleport_cooldown_left():
		_since_tp = teleport_cooldown - left
	var dest := Vector3(server_pos.x, global_position.y, server_pos.z)
	match _blink["phase"]:
		1:
			_blink_dest = dest
			_blink_face_deg = 0.0   # сервер вернул на старое место: поворот к нему не относится
		2:
			_queued_dest = dest
		_:
			if NodeLayout.flat_distance(global_position, dest) > 0.05:
				_start_blink(dest)


# ---------------------------------------------------------------- плоская сборка

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
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		_tp_click = true

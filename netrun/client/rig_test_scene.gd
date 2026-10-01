extends Node3D
## Сцена прототипа (V1 + V3): пол, один узел (площадка с постаментом), один берущийся объект и счётчик времени кадра в мире.
## Общая для плоской и VR-сборок; не игровой мир (его даёт сервер). Простая геометрия, без ассетов.
## Объект берёт СЕРВЕР: сцена только просит (grab_requested) и двигает объект после confirm_grab.
## Взять: VR — grip контроллера рядом с объектом; плоская сборка — F или левая кнопка мыши.

signal grab_requested(object_id: String)
signal frame_slow(ms: float)
## Применить демона из деки / выйти чисто на площадке выхода (N7); решает сервер.
signal daemon_use_requested(daemon_id: String)
signal leave_requested

const SLOW_FRAME_SEC := 1.0 / 72.0
const VR_REACH := 0.4
const FLAT_REACH := 3.0
const STATS_PERIOD := 0.5

var rig: XRRig
var world_ui: WorldUI
var pickup: MeshInstance3D
var held := false
var slow_frames := 0

## Что показывает дека сейчас (с сервера): [{id, name, left}] и выбранный демон (VR: Y — следующий, X — применить).
var deck_state: Array = []
## Звук ICE на самих ICE (N5): включает тот, кто собрал клиент (в тестах без звука — выключен).
var ice_audio_enabled := false
var selected_daemon := ""
var _ice_nodes: Dictionary = {}      # id ICE -> Node3D
var _ice_targets: Dictionary = {}    # id ICE -> {p: Vector3, f: Vector2}
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
	# Узел (shared/node_layout.gd): площадка и постамент шарда, укрытия, площадка выхода.
	var sp := NodeLayout.SHARD_POS
	_add_mesh(_cylinder(2.0, 0.1), Vector3(sp.x, 0.05, sp.z), Color(0.1, 0.35, 0.45))
	_add_mesh(_cylinder(0.25, 0.9), Vector3(sp.x, 0.45, sp.z), Color(0.2, 0.2, 0.3))
	for c in NodeLayout.COVERS:
		_add_box(c[1], c[0], Color(0.18, 0.2, 0.3))
	_add_mesh(_cylinder(NodeLayout.EXIT_RADIUS, 0.06), NodeLayout.EXIT_POS + Vector3(0, 0.03, 0), Color(0.1, 0.6, 0.3))
	pickup = _add_mesh(SphereMesh.new(), sp, Color(1.0, 0.6, 0.1))
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
	# Интерфейс в мире (N4). Данные приходят с сервера (apply_state); до первого снимка — пустая дека и trace 0.
	world_ui = WorldUI.new()
	add_child(world_ui)
	world_ui.attach(rig)
	world_ui.deck.set_deck({"daemons": [], "selected": ""})
	world_ui.trace.set_trace(0.0)
	for hand in [rig.left_hand, rig.right_hand]:
		hand.button_pressed.connect(func(action: String):
			if action == "grip_click":
				try_grab(hand.global_position, VR_REACH, hand))
	rig.left_hand.button_pressed.connect(func(action: String):
		if action == "ax_button":
			use_selected()
		elif action == "by_button":
			select_next())


func _process(delta: float) -> void:
	for id in _ice_nodes:
		var n: Node3D = _ice_nodes[id]
		var t: Dictionary = _ice_targets[id]
		n.position = n.position.lerp(t["p"], clampf(delta * 12.0, 0.0, 1.0))
		var f: Vector2 = t["f"]
		if f.length() > 0.001:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-f.x, -f.y), clampf(delta * 12.0, 0.0, 1.0))
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
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			use_slot(k - KEY_1)
		elif k == KEY_X:
			leave_requested.emit()
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if key or click:
		try_grab(rig.camera.global_position, FLAT_REACH, rig.camera)


## Снимок узла с сервера: trace, дека с перезарядками, ICE (простые фигуры), перезарядки.
func apply_state(state: Dictionary) -> void:
	world_ui.trace.set_trace(float(state.get("trace", 0.0)))
	deck_state = state.get("cd", [])
	var ids: Array = deck_state.map(func(d): return d["id"])
	if not selected_daemon in ids:
		selected_daemon = ids[0] if not ids.is_empty() else ""
	_refresh_deck()
	for ice in state.get("ice", []):
		var id := str(ice["id"])
		var p: Array = ice["p"]
		var f: Array = ice["f"]
		if not _ice_nodes.has(id):
			_ice_nodes[id] = _make_ice(id)
			_ice_nodes[id].position = Vector3(p[0], p[1], p[2])
			_ice_targets[id] = {}
		_ice_targets[id] = {"p": Vector3(p[0], p[1], p[2]), "f": Vector2(f[0], f[1])}
		_paint_ice(_ice_nodes[id], int(ice["s"]))


## Сервер закончил забег (выход, выброс, флэтлайн): надпись перед глазами. Связь закроется сама.
func show_ended(reason: String) -> void:
	var text := {"clean": "ВЫХОД", "ejected": "ICE ВЫБРОСИЛ ВАС", "flatline": "ФЛЭТЛАЙН"}.get(reason, "ВЫХОД: " + reason) as String
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0008
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.3, 0.3) if reason != "clean" else Color(0.3, 1.0, 0.5)
	l.position = Vector3(0, 0, -0.9)
	rig.camera.add_child(l)


func ice_node(id: String) -> Node3D:
	return _ice_nodes.get(id)


func use_slot(index: int) -> void:
	if index >= 0 and index < deck_state.size():
		selected_daemon = str(deck_state[index]["id"])
		_refresh_deck()
		use_selected()


func use_selected() -> void:
	if not selected_daemon.is_empty():
		daemon_use_requested.emit(selected_daemon)


func select_next() -> void:
	var ids: Array = deck_state.map(func(d): return d["id"])
	if ids.is_empty():
		return
	selected_daemon = ids[(maxi(ids.find(selected_daemon), 0) + 1) % ids.size()]
	_refresh_deck()


func _refresh_deck() -> void:
	var rows: Array = []
	for d in deck_state:
		rows.append({"id": d["id"], "name": "%d %s" % [rows.size() + 1, d["name"]], "cooldown_left": float(d["left"])})
	world_ui.deck.set_deck({"daemons": rows, "selected": selected_daemon})


func _make_ice(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = id
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	cap.material = StandardMaterial3D.new()
	body.mesh = cap
	body.position.y = 0.9
	body.name = "Body"
	n.add_child(body)
	var nose := MeshInstance3D.new()  # «лицо»: куда смотрит ICE
	var nm := BoxMesh.new()
	nm.size = Vector3(0.3, 0.15, 0.3)
	nm.material = _unshaded_color(Color(1, 1, 1))
	nose.mesh = nm
	nose.position = Vector3(0, 1.4, -0.4)
	n.add_child(nose)
	if ice_audio_enabled:
		var a := IceAudio.new()
		a.name = "Audio"
		a.position = Vector3(0, 1.2, 0)
		n.add_child(a)
	add_child(n)
	return n


func _paint_ice(n: Node3D, state: int) -> void:
	var mat := ((n.get_node("Body") as MeshInstance3D).mesh as CapsuleMesh).material as StandardMaterial3D
	mat.albedo_color = [Color(0.5, 0.15, 0.2), Color(1.0, 0.8, 0.1), Color(1.0, 0.1, 0.1)][clampi(state, 0, 2)]
	var audio := n.get_node_or_null("Audio") as IceAudio
	if audio != null and audio.state != state:
		audio.set_state(state)


func _unshaded_color(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


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

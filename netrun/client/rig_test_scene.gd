extends Node3D
## Сцена клиента: узел в 3D-ассетах (NodeView: комната по тиру, хранилища, порталы, выход), ICE (IceView) и чужие нетраннеры (AvatarView),
## один берущийся объект и счётчик времени кадра в мире. Общая для плоской и VR-сборок; не игровой мир (его даёт сервер).
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
const FLATLINE_FADE_SEC := 0.8
## Шард на хранилище вращается и парит (shard.glb: «вращение и парение — на стороне клиента»).
const SHARD_SPIN_RAD := 0.9
const SHARD_BOB_M := 0.03
const SHARD_BOB_HZ := 0.35
## Вид окружения (как в сцене приёмки ассетов): окружающий свет и два направленных без теней — тени на Pico не рассчитываем.
const AMBIENT_COLOR := Color(0.62, 0.7, 0.74)
const AMBIENT_ENERGY := 0.5

var rig: XRRig
var world_ui: WorldUI
## Узел в ассетах: комната, хранилища, порталы, кресло, датчик, выход.
var view: NodeView
## Шард прототипа (pickup_01) — единственный в одиночном узле; в графе узлов шардов несколько (_pickups).
var pickup: Node3D
var held := false
## Какой узел графа сейчас показан и что про него сказал сервер (WorldMsg.EV_NODE); в одиночном узле пусто.
var current_node := ""
var node_info: Dictionary = {}
var tunnel: TunnelFx
var _pickups: Dictionary = {}        # id слота шарда -> модель shard.glb (в том числе та, что в руке)
var _held_ids: Dictionary = {}       # id шардов в руке: из узла в узел они идут с игроком
var _pending_id := ""
var _node_props: Array[Node3D] = []  # подписи порталов и таблички узла (модели — в NodeView)
var slow_frames := 0
## Показан экран флэтлайна (для тестов).
var flatline_shown := false

## Что показывает дека сейчас (с сервера): [{id, name, left}] и выбранный демон (VR: Y — следующий, X — применить).
var deck_state: Array = []
## Звук ICE на самих ICE (N5): включает тот, кто собрал клиент (в тестах без звука — выключен).
var ice_audio_enabled := false
var selected_daemon := ""
var _ice_nodes: Dictionary = {}      # id ICE -> IceView
var _avatar_nodes: Dictionary = {}   # id чужого аватара -> AvatarView
## Чужие ICE и аватары показываются из буфера состояний с задержкой (RemoteTracks), а не прыжками по пакетам.
var remote := RemoteTracks.new()
var _pending_holder: Node3D
var _label: Label3D
var _acc := 0.0
var _spin_t := 0.0
var _count := 0
var _max_ms := 0.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.024, 0.03)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = AMBIENT_COLOR
	env.environment.ambient_light_energy = AMBIENT_ENERGY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	_add_light(Vector3(-52.0, 25.0, 0.0), 0.55)
	_add_light(Vector3(-30.0, 205.0, 0.0), 0.25)
	view = NodeView.new()
	add_child(view)
	# Постаменты (хранилища) шардов и порталы — _build_node (до ответа сервера: один шард в слоте SHARD_POS).
	var sp := NodeLayout.SHARD_POS
	_build_node([{"id": NetConfig.PICKUP_ID, "p": [sp.x, sp.y, sp.z], "ready": true}], [], NodeLayout.PORTAL_RADIUS)
	pickup = _pickups[NetConfig.PICKUP_ID]
	# Счётчик кадра — надпись на панели в мире, не HUD.
	var panel := NodeLayout.SPAWN + Vector3(0.0, 1.8, -3.5)
	_add_box(Vector3(2.4, 0.5, 0.03), panel, Color(0.03, 0.03, 0.05))
	_label = Label3D.new()
	_label.position = panel + Vector3(0.0, 0.0, 0.02)
	_label.pixel_size = 0.004
	_label.font_size = 48
	_label.text = "кадр …"
	add_child(_label)
	rig = preload("res://client/xr_rig.tscn").instantiate()
	rig.position = NodeLayout.SPAWN  # в кресле узла (props/seat.glb)
	add_child(rig)
	tunnel = TunnelFx.new()
	rig.camera.add_child(tunnel)
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
	var now := Time.get_ticks_msec() / 1000.0
	for id in _ice_nodes:
		var pose := remote.ice_pose(id, now)
		if not pose.is_empty():
			var n: Node3D = _ice_nodes[id]
			n.position = pose["p"]
			n.rotation.y = pose["yaw"]
	for id in _avatar_nodes:
		var pose := remote.avatar_pose(id, now)
		if not pose.is_empty():
			(_avatar_nodes[id] as AvatarView).move_to(pose["p"], delta)
	_animate_shards(delta)
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


## Снимок узла с сервера: trace, дека с перезарядками, ICE (модели, клип по состоянию), перезарядки; охота и уровень LOCKDOWN
## меняют вид узла (порталы закрываются, двери выхода сменяются воротами).
func apply_state(state: Dictionary) -> void:
	world_ui.trace.set_trace(float(state.get("trace", 0.0)))
	view.set_hunted(bool(state.get("hunt", false)))
	view.set_exit_locked(int(state.get("level", 0)) >= HudLogic.LEVEL_LOCKDOWN)
	deck_state = state.get("cd", [])
	var ids: Array = deck_state.map(func(d): return d["id"])
	if not selected_daemon in ids:
		selected_daemon = ids[0] if not ids.is_empty() else ""
	_refresh_deck()
	remote.on_state(state, Time.get_ticks_msec() / 1000.0)
	var seen := {}
	for ice in state.get("ice", []):
		var id := str(ice["id"])
		var p: Array = ice["p"]
		var pos := Vector3(p[0], p[1], p[2])
		seen[id] = true
		if not _ice_nodes.has(id):
			_ice_nodes[id] = _make_ice(id, int(ice.get("b", 0)) == 1)
			_ice_nodes[id].position = pos
		_show_ice_state(_ice_nodes[id], int(ice["s"]), pos)
	# ICE, которого в снимке больше нет (игрок перешёл в другой узел), убираем: иначе Black ICE прошлого узла стоял бы в новом.
	for id in _ice_nodes.keys():
		if not seen.has(id):
			(_ice_nodes[id] as Node).free()
			_ice_nodes.erase(id)
			remote.ice.erase(id)


## Позиции других нетраннеров узла (WorldMsg.AVATARS): новым — фигура, вышедшим — убрать; двигает их _process по буферу.
func apply_avatars(msg: Dictionary) -> void:
	for id in remote.on_avatars(msg, Time.get_ticks_msec() / 1000.0):
		var gone: Node3D = _avatar_nodes.get(id)
		if gone != null:
			gone.queue_free()
		_avatar_nodes.erase(id)
	for e in msg.get("a", []):
		var id := str(int(e[0]))
		if not _avatar_nodes.has(id):
			_avatar_nodes[id] = _make_avatar(int(e[0]), Vector3(float(e[1]), 0.0, float(e[2])))


func avatar_node(id: String) -> Node3D:
	return _avatar_nodes.get(id)


func avatar_ids() -> Array:
	return _avatar_nodes.keys()


func _make_avatar(id: int, pos: Vector3) -> AvatarView:
	var n := AvatarView.new()
	n.name = "avatar_%d" % id
	n.position = pos
	add_child(n)
	n.setup(id)
	return n


## Сервер закончил забег (выход, выброс, флэтлайн): надпись перед глазами. Связь закроется сама.
func show_ended(reason: String) -> void:
	if reason == ExitLogic.REASON_FLATLINE:
		_show_flatline()
		return
	var text := {"clean": "ВЫХОД", "ejected": "ICE ВЫБРОСИЛ ВАС", "flatline": "ФЛЭТЛАЙН"}.get(reason, "ВЫХОД: " + reason) as String
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0008
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.3, 0.3) if reason != "clean" else Color(0.3, 1.0, 0.5)
	l.position = Vector3(0, 0, -0.9)
	rig.camera.add_child(l)


## Флэтлайн: экран плавно гаснет (чёрный экран на голове, камера не двигается и не трясётся), поверх — «ФЛЭТЛАЙН».
## Ничего не мигает и не шатается: в VR резкая подача рядом с головой хуже, чем тишина.
func _show_flatline() -> void:
	var veil := MeshInstance3D.new()
	veil.name = "FlatlineVeil"
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.no_depth_test = true
	mat.render_priority = 100
	quad.material = mat
	veil.mesh = quad
	veil.position = Vector3(0, 0, -0.25)
	rig.camera.add_child(veil)
	var l := Label3D.new()
	l.name = "FlatlineText"
	l.text = "ФЛЭТЛАЙН"
	l.font_size = 64
	l.pixel_size = 0.0008
	l.no_depth_test = true
	l.render_priority = 101
	l.modulate = Color(1.0, 0.15, 0.2, 0.0)
	l.position = Vector3(0, 0, -0.9)
	rig.camera.add_child(l)
	flatline_shown = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 1.0, FLATLINE_FADE_SEC)
	tw.tween_property(l, "modulate:a", 1.0, FLATLINE_FADE_SEC).set_delay(FLATLINE_FADE_SEC * 0.5)


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


func _make_ice(id: String, black: bool) -> IceView:
	var n := IceView.new(black)
	n.name = id
	if ice_audio_enabled:
		var a := IceAudio.new()
		a.name = "Audio"
		a.position = Vector3(0, 1.2, 0)
		n.add_child(a)
	add_child(n)
	return n


## Состояние ICE с сервера -> клип модели и звук. Black ICE на охоте вплотную к игроку (или другому нетраннеру) ловит: клип catch.
func _show_ice_state(n: IceView, state: int, pos: Vector3) -> void:
	var near := n.black and state == IceView.STATE_HUNT and _someone_within(pos, IceView.CATCH_NEAR)
	n.apply_state(state, near)
	var audio := n.get_node_or_null("Audio") as IceAudio
	if audio != null and audio.state != state:
		audio.set_state(state)


func _someone_within(pos: Vector3, dist: float) -> bool:
	if NodeLayout.flat_distance(pos, rig.global_position) <= dist:
		return true
	for id in _avatar_nodes:
		if NodeLayout.flat_distance(pos, (_avatar_nodes[id] as Node3D).position) <= dist:
			return true
	return false


## Просит сервер отдать объект, если он лежит и достаточно близко. Сам объект не двигает.
func try_grab(origin: Vector3, reach: float, holder: Node3D) -> bool:
	if _pending_holder != null:
		return false
	var best := ""
	var best_d := reach
	for id in _pickups:
		var m: Node3D = _pickups[id]
		if _held_ids.has(id) or not m.visible:
			continue
		var d := origin.distance_to(m.global_position)
		if d <= best_d:
			best = id
			best_d = d
	if best.is_empty():
		return false
	_pending_holder = holder
	_pending_id = best
	grab_requested.emit(best)
	return true


## Сервер подтвердил: объект переходит в руку (плоская сборка — перед камерой).
func confirm_grab() -> void:
	if _pending_holder == null:
		return
	var m: Node3D = _pickups[_pending_id]
	m.reparent(_pending_holder, false)
	m.position = Vector3(0.25, -0.25, -0.7) if _pending_holder is Camera3D else Vector3.ZERO
	_held_ids[_pending_id] = true
	held = true
	_pending_holder = null
	_pending_id = ""


func deny_grab() -> void:
	_pending_holder = null
	_pending_id = ""


# ---------------------------------------------------------------- граф узлов (W1)

## Сервер рассказал узел (WorldMsg.EV_NODE): шарды, порталы; после перехода — риг на место входа, тоннель открывается.
func apply_node(info: Dictionary) -> void:
	node_info = info
	current_node = str(info.get("node", ""))
	view.set_tier(str(info.get("tier", "")))
	view.set_dead_decks(info.get("dead", []))
	_build_node(info.get("shards", []), info.get("portals", []), float(info.get("r", NodeLayout.PORTAL_RADIUS)))
	_build_signs(info.get("signs", []))
	var arrive: Variant = info.get("arrive")
	if arrive is Array and (arrive as Array).size() == 2:
		rig.global_position = Vector3(float(arrive[0]), rig.global_position.y, float(arrive[1]))
	end_tunnel()


## Слоты шардов узла изменились (вынесли, пополнилось): лежащий шард виден, вынесенный — нет.
func apply_shards(shards: Array) -> void:
	for sh in shards:
		var id := str(sh["id"])
		var m: Node3D = _pickups.get(id)
		if m != null and not _held_ids.has(id):
			m.visible = bool(sh.get("ready", true))
		view.set_vault_ready(id, bool(sh.get("ready", true)))


## Тоннель: затемнение вокруг головы и блок хода (камеру не двигаем); надпись «куда».
func begin_tunnel(title: String, sec: float) -> void:
	rig.movement_locked = true
	tunnel.begin()
	show_notice("→ " + title, maxf(sec, 1.5))


func end_tunnel() -> void:
	rig.movement_locked = false
	if tunnel.is_active():
		tunnel.finish()


## Короткая надпись перед глазами (портал закрыт, куда ведёт тоннель).
func show_notice(text: String, sec: float = 2.5) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0008
	l.no_depth_test = true
	l.render_priority = 120
	l.modulate = Color(0.5, 0.95, 1.0)
	l.position = Vector3(0, -0.12, -0.9)
	rig.camera.add_child(l)
	if is_inside_tree():
		get_tree().create_timer(sec).timeout.connect(l.queue_free)


func show_portal_denied(ev: Dictionary) -> void:
	if str(ev.get("reason", "")) == "lockdown":
		view.close_portal(str(ev.get("to", "")))
	var text := {
		"lockdown": "Узел закрыт: локдаун (ещё %d с)" % int(ev.get("left", 0)),
		"hunt": "Портал закрыт: за вами охота",
	}.get(str(ev.get("reason", "")), "") as String
	if text != "":
		show_notice(text)


## Хранилища шардов и порталы узла. Старые убираются; шарды в руке остаются в руке; одиночный pickup_01 не освобождается никогда.
func _build_node(shards: Array, portals: Array, _portal_radius: float) -> void:
	for n in _node_props:
		n.queue_free()
	_node_props.clear()
	var ids: Array = shards.map(func(sh): return str(sh["id"]))
	for id in _pickups.keys():
		var m: Node3D = _pickups[id]
		if _held_ids.has(id) or id in ids:
			continue
		if m == pickup:
			m.visible = false
		else:
			m.queue_free()
			_pickups.erase(id)
	view.set_vaults(shards)
	for sh in shards:
		var id := str(sh["id"])
		if _held_ids.has(id):
			continue
		var p: Array = sh["p"]
		var asset := NodeAssets.prop_path("shard_encrypted" if bool(sh.get("enc", false)) else "shard")
		var m: Node3D = _pickups.get(id)
		if m != null and str(m.get_meta("asset", "")) != asset:  # шард стал зашифрованным (или наоборот): другая модель
			m.queue_free()
			_pickups.erase(id)
			m = null
		if m == null:
			m = NodeAssets.instance(asset)
			m.name = id
			add_child(m)
			_pickups[id] = m
		m.position = Vector3(p[0], p[1], p[2])
		m.set_meta("y0", float(p[1]))
		m.visible = bool(sh.get("ready", true))
	view.set_portals(portals)
	for pt in portals:
		var pos: Array = pt["p"]
		var open: bool = bool(pt.get("open", true))
		var l := Label3D.new()
		l.text = "%s\n%s%s" % [pt.get("title", ""), pt.get("tier", ""), "" if open else " — закрыт"]
		l.font_size = 40
		l.pixel_size = 0.004
		l.position = Vector3(pos[0], 3.4, pos[1])
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		_node_props.append(l)


## Шарды на хранилищах медленно вращаются и парят; шард в руке (и в чужих руках) стоит как стоит.
func _animate_shards(delta: float) -> void:
	_spin_t += delta
	for id in _pickups:
		var m: Node3D = _pickups[id]
		if _held_ids.has(id) or not m.visible or not m.has_meta("y0"):
			continue
		m.rotation.y += delta * SHARD_SPIN_RAD
		m.position.y = float(m.get_meta("y0")) + sin(_spin_t * TAU * SHARD_BOB_HZ) * SHARD_BOB_M


## Таблички учебного узла (диегетические подсказки, без HUD): надпись в мире на уровне глаз, поворачивается к игроку.
func _build_signs(signs: Array) -> void:
	for sg in signs:
		var p: Array = sg["p"]
		var l := Label3D.new()
		l.text = str(sg.get("text", ""))
		l.font_size = 36
		l.pixel_size = 0.004
		l.modulate = Color(0.6, 1.0, 0.8)
		l.position = Vector3(p[0], 1.6, p[1])
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		_node_props.append(l)


func _add_light(rot_deg: Vector3, energy: float) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_energy = energy
	l.shadow_enabled = false
	add_child(l)


## Все подключённые и видимые ассеты сцены (по метке asset): окружение, предметы, шарды, ICE, чужие аватары.
func used_assets() -> Array:
	return NodeView.collect_assets(self)


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

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
## Отправка добычи (К5б): запрос списка получателей и подтверждённая отправка — их шлёт в сеть тот, кто собрал клиент.
signal give_list_requested
signal give_requested(item_id: String, to: Dictionary)
## Шард ушёл в деку (id слота): для журнала клиента. Серверу сообщать нечего — предмет в деке Моста с момента grab.
signal shard_stowed(object_id: String)
## Панель взлома (К3): игрок выбрал демонов и нажал «НАЧАТЬ» / нажал клетку / завершил. Просит сервер ProtoClient; решает сервер.
signal breach_start_requested(vault: String, daemon_ids: Array)
signal breach_tap_requested(cell: Vector2i)
signal breach_cancel_requested
## Заряд защитного демона на запястье (К6): «ЗАРЯДИТЬ» у программы / клетка сетки заряда / «ОТМЕНА». Просит сервер ProtoClient; решает сервер.
signal charge_requested(daemon_id: String)
signal charge_cell_tapped(cell: Vector2i)
signal decrypt_requested(item_id: String)
signal charge_cancel_requested

## Импульс левого контроллера: демон запущен / запуск отказан / заряд готов.
const LAUNCH_PULSE_AMP := 0.8
const LAUNCH_PULSE_S := 0.25
const DENY_PULSE_AMP := 0.3
const DENY_PULSE_S := 0.08
const CHARGED_PULSE_AMP := 0.55
const CHARGED_PULSE_S := 0.15
const VR_REACH := 0.4
const FLAT_REACH := 3.0
const STATS_PERIOD := 0.5
const FLATLINE_FADE_SEC := 0.8
## Шард в правой руке «втягивается» в деку, если рука ближе этого к центру деки на запястье (м); дека на запястье ~24 см длиной.
const STOW_REACH := 0.2
## Шард летит в деку и сжимается, сек.
const STOW_SEC := 0.3
## Рамка деки светится столько секунд после того, как шард втянулся.
const STOW_FLASH_SEC := 0.5
## Шард в закрытом хранилище: меньше и полупрозрачный, не вращается (взять нельзя).
const SHARD_DIM_SCALE := 0.7
const SHARD_DIM_ALPHA := 0.55
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
var _hand_of: Dictionary = {}        # держатель (рука или камера) -> id шарда в нём
var _stow_flash := 0.0
var _vault_state: Dictionary = {}    # id слота -> NodeView.VAULT_*: брать можно только из открытого
var _vault_info: Dictionary = {}     # id слота -> последняя запись от сервера ({id, p, vault, access, left, ...}): панель взлома и привязка телепорта
var _breach_ctx_key: Variant = null
var _pending_id := ""
var _node_props: Array[Node3D] = []  # подписи порталов и таблички узла (модели — в NodeView)
var slow_frames := 0
## Показан экран флэтлайна (для тестов).
var flatline_shown := false

## Что показывает дека сейчас (с сервера): [{id, name, left}] и выбранный демон (VR: Y — следующий, X — применить).
var deck_state: Array = []
## Последнее событие `ev deck` сервера (RAM, свойства рабочих демонов, груз); пустое, пока оно не пришло.
var deck_info: Dictionary = {}
var _state_k := 0.0   # время сервера в последнем снимке: по нему until из state.cd превращается в «осталось N с»
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
	rig.teleport_snap = snap_teleport
	world_ui.breach_panel.start_requested.connect(func(vault: String, ids: Array): breach_start_requested.emit(vault, ids))
	world_ui.breach_panel.cell_tapped.connect(func(cell: Vector2i): breach_tap_requested.emit(cell))
	world_ui.breach_panel.cancel_requested.connect(func(): breach_cancel_requested.emit())
	world_ui.deck.charge_requested.connect(func(id: String): charge_requested.emit(id))
	world_ui.deck.charge_cell_tapped.connect(func(cell: Vector2i): charge_cell_tapped.emit(cell))
	world_ui.deck.decrypt_requested.connect(func(id: String): decrypt_requested.emit(id))
	world_ui.deck.charge_cancel_requested.connect(func(): charge_cancel_requested.emit())
	world_ui.deck.set_deck({"daemons": [], "selected": ""})
	world_ui.deck.give_list_requested.connect(func(): give_list_requested.emit())
	world_ui.deck.give_requested.connect(func(item_id: String, to: Dictionary): give_requested.emit(item_id, to))
	world_ui.trace.set_trace(0.0)
	for hand in [rig.left_hand, rig.right_hand]:
		hand.button_pressed.connect(func(action: String):
			if action == "grip_click":
				on_grip(hand))
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
	_update_stow_target(delta)
	_update_breach_panel()
	_count += 1
	_acc += delta
	_max_ms = maxf(_max_ms, delta * 1000.0)
	if FrameStats.is_slow(delta):
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
		elif k == KEY_C:
			charge_selected()   # заряд выбранного демона (в VR — кнопка «ЗАРЯДИТЬ» на деке)
		elif k == KEY_G:
			stow(rig.camera)   # плоская сборка: шард «из руки» (перед камерой) в деку
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if key or click:
		try_grab(rig.camera.global_position, FLAT_REACH, rig.camera)


## Снимок узла с сервера: trace, дека с перезарядками, ICE (модели, клип по состоянию), перезарядки; охота и уровень LOCKDOWN
## меняют вид узла (порталы закрываются, двери выхода сменяются воротами).
func apply_state(state: Dictionary) -> void:
	world_ui.trace.set_trace(float(state.get("trace", 0.0)))
	world_ui.breach_panel.set_trace(float(state.get("trace", 0.0)))
	view.set_hunted(bool(state.get("hunt", false)))
	view.set_exit_locked(int(state.get("level", 0)) >= HudLogic.LEVEL_LOCKDOWN)
	deck_state = state.get("cd", [])
	_state_k = float(state.get("k", 0.0))
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
		# Поза тела: свежая — рисуем голову и руки вместо runner.glb; в пакете её нет (старая, мусор) — null, тело спрячется само.
		(_avatar_nodes[id] as AvatarView).apply_pose(remote.poses.get(id))


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


## Слот деки по номеру (плоская сборка, цифры): выбрать и запустить именно его.
func use_slot(index: int) -> void:
	if index >= 0 and index < deck_state.size():
		selected_daemon = str(deck_state[index]["id"])
		_refresh_deck()
		daemon_use_requested.emit(selected_daemon)


## Заряженные демоны деки в её порядке: те, что можно запустить одним нажатием.
func charged_ids() -> Array:
	return deck_state.filter(func(d: Dictionary) -> bool: return str(d.get("st", "")) == "charged").map(func(d: Dictionary) -> String: return str(d["id"]))


## Кого запускает левый X: выбранного, если он заряжен, иначе первого заряженного (в погоне нет времени листать). Никто не заряжен — выбранный:
## сервер ответит not_charged, и дека скажет об этом словами.
func launch_target() -> String:
	var charged := charged_ids()
	if charged.is_empty() or selected_daemon in charged:
		return selected_daemon
	return charged[0]


func use_selected() -> void:
	var id := launch_target()
	if not id.is_empty():
		daemon_use_requested.emit(id)


## Y / следующий: среди заряженных, если они есть (запуск в погоне), иначе по всей деке.
func select_next() -> void:
	var ids: Array = charged_ids()
	if ids.is_empty():
		ids = deck_state.map(func(d): return d["id"])
	if ids.is_empty():
		return
	selected_daemon = ids[(maxi(ids.find(selected_daemon), -1) + 1) % ids.size()]
	_refresh_deck()


## Зарядить выбранного демона (плоская сборка, клавиша C; в VR то же делает кнопка на деке). Выбранный не заряжается — первый, которого можно.
func charge_selected() -> void:
	var id := selected_daemon
	if not _can_charge_id(id):
		id = ""
		for d in deck_state:
			if _can_charge_id(str(d["id"])):
				id = str(d["id"])
				break
	if not id.is_empty():
		charge_requested.emit(id)


func _can_charge_id(id: String) -> bool:
	for d in deck_state:
		if str(d["id"]) == id:
			for info in deck_info.get("daemons", []):
				if str(info.get("id", "")) == id:
					return HudLogic.can_charge(str(d.get("st", "")), bool(info.get("chargeable", false)))
	return false


## Ответ сервера на `use`: запуск удался — импульс левой руки (состояние «активен N с» придёт в снимке); отказ — слово на деке.
func apply_daemon_result(ev: Dictionary) -> void:
	if bool(ev.get("ok", false)):
		world_ui.feedback.pulse("left", LAUNCH_PULSE_AMP, LAUNCH_PULSE_S)
	else:
		world_ui.deck.show_notice(HudLogic.launch_error_text(str(ev.get("error", ""))))
		world_ui.feedback.pulse("left", DENY_PULSE_AMP, DENY_PULSE_S)


## Событие `ev deck`: RAM, свойства рабочих демонов и груз. Вкладка ДОБЫЧА появляется с первым таким событием.
func apply_deck(ev: Dictionary) -> void:
	deck_info = ev
	_refresh_breach_context()
	world_ui.deck.set_loot(ev.get("loot", []), int(ev.get("eddies", 0)), ev.get("daemons", []))
	_refresh_deck()


## Событие `give_list`: нетраннеры в Сети, которым можно отправить добычу.
func apply_give_list(ev: Dictionary) -> void:
	world_ui.deck.set_give_runners(ev.get("runners", []))


## Событие `give`: исход отправки (dir out) или новый предмет в ГРУЗе (dir in — строка мигает сама, когда придёт `ev deck`; здесь тихий сигнал и подпись).
func apply_give(ev: Dictionary) -> void:
	world_ui.deck.show_give_result(ev)
	if str(ev.get("dir", "")) == WorldMsg.GIVE_IN and bool(ev.get("ok", false)):
		world_ui.feedback.loot_cue()


func _refresh_deck() -> void:
	var rows := HudLogic.program_entries(deck_state, deck_info.get("daemons", []), _state_k)
	for i in rows.size():
		rows[i]["name"] = "%d %s" % [i + 1, rows[i]["name"]]
	var deck := {"daemons": rows, "selected": selected_daemon}
	if deck_info.has("ram"):
		deck["ram"] = int(deck_info["ram"])
		deck["used"] = int(deck_info.get("used", 0))
		deck["ram_default"] = bool(deck_info.get("ram_default", false))
	world_ui.deck.set_deck(deck)


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


## Grip руки: с шардом в руке и дека рядом — положить в деку; пустая рука — взять ближайший открытый шард. Рука с шардом, но вдали от деки,
## ничего не делает (бросать в MVP нельзя: уронить ценность хуже, чем не уметь её бросить).
func on_grip(hand: Node3D) -> void:
	if _hand_of.has(hand):
		if can_stow_from(hand):
			stow(hand)
		return
	try_grab(hand.global_position, VR_REACH, hand)


## Просит сервер отдать объект, если он лежит, его хранилище открыто для нас и он достаточно близко. Сам объект не двигает.
func try_grab(origin: Vector3, reach: float, holder: Node3D) -> bool:
	if _pending_holder != null or _hand_of.has(holder):
		return false
	var best := ""
	var best_d := reach
	for id in _pickups:
		var m: Node3D = _pickups[id]
		if _held_ids.has(id) or not m.visible or _vault_state.get(id, NodeView.VAULT_OPEN) != NodeView.VAULT_OPEN:
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


## Сервер подтвердил: объект переходит в руку (плоская сборка — перед камерой). Взятый левой рукой шард сразу уходит в деку: он уже у запястья.
func confirm_grab() -> void:
	if _pending_holder == null:
		return
	var holder := _pending_holder
	var m: Node3D = _pickups[_pending_id]
	m.reparent(holder, false)
	m.position = Vector3(0.25, -0.25, -0.7) if holder is Camera3D else Vector3.ZERO
	_set_dim(m, false)
	_held_ids[_pending_id] = true
	_hand_of[holder] = _pending_id
	held = true
	_pending_holder = null
	_pending_id = ""
	if holder == rig.left_hand:
		stow(holder)


func deny_grab() -> void:
	_pending_holder = null
	_pending_id = ""


# ---------------------------------------------------------------- шард в деку

## Что держит рука (или камера): id шарда или "".
func held_in(holder: Node3D) -> String:
	return str(_hand_of.get(holder, ""))


## Рука с шардом у деки: правая рука — ближе STOW_REACH к центру деки; камера (плоская сборка) — всегда.
func can_stow_from(holder: Node3D) -> bool:
	if not _hand_of.has(holder):
		return false
	return holder is Camera3D or holder.global_position.distance_to(world_ui.deck.global_position) <= STOW_REACH


## Шард из держателя «втягивается» в деку: летит к деке, сжимается, пропадает; дека на миг светится рамкой. Серверу не сообщаем.
func stow(holder: Node3D) -> bool:
	var id := held_in(holder)
	if id.is_empty():
		return false
	var m: Node3D = _pickups.get(id)
	_hand_of.erase(holder)
	_held_ids.erase(id)
	_pickups.erase(id)
	held = not _held_ids.is_empty()
	if m != null:
		var from := m.global_position
		m.reparent(self, true)
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(t: float): m.global_position = from.lerp(world_ui.deck.global_position, t), 0.0, 1.0, STOW_SEC)
		tw.tween_property(m, "scale", Vector3.ONE * 0.1, STOW_SEC)
		tw.chain().tween_callback(m.queue_free)
	world_ui.deck.set_receiving(true)
	_stow_flash = STOW_FLASH_SEC
	shard_stowed.emit(id)
	return true


## Дека подсвечивает приёмник, пока правая рука с шардом у запястья.
func _update_stow_target(delta: float) -> void:
	var want := false
	for holder in _hand_of:
		if holder == rig.right_hand and can_stow_from(holder):
			want = true
	if _stow_flash > 0.0:
		_stow_flash -= delta
		want = true
	world_ui.deck.set_receiving(want)


# ---------------------------------------------------------------- граф узлов (W1)

## Сервер рассказал узел (WorldMsg.EV_NODE): шарды, порталы; после перехода — риг на место входа, тоннель открывается.
func apply_node(info: Dictionary) -> void:
	node_info = info
	current_node = str(info.get("node", ""))
	view.set_tier(str(info.get("tier", "")))
	view.set_dead_decks(info.get("dead", []))
	if world_ui.breach_panel.mode() != BreachPanel.MODE_RUN:
		world_ui.breach_panel.hide_panel()   # другой узел — другие хранилища
	_build_node(info.get("shards", []), info.get("portals", []), float(info.get("r", NodeLayout.PORTAL_RADIUS)))
	_build_signs(info.get("signs", []))
	var arrive: Variant = info.get("arrive")
	if arrive is Array and (arrive as Array).size() == 2:
		rig.global_position = Vector3(float(arrive[0]), rig.global_position.y, float(arrive[1]))
	end_tunnel()


## Слоты шардов узла изменились (вынесли, пополнилось, хранилище открылось/закрылось): лежащий шард виден, вынесенный — нет; вид хранилища — по vault
## (закрытое — шард внутри тусклый и не берётся).
func apply_shards(shards: Array) -> void:
	_refresh_dead_decks(shards)
	for sh in shards:
		var id := str(sh["id"])
		_vault_info[id] = sh
		var state := NodeView.vault_state_of(sh)
		_vault_state[id] = state
		view.set_vault_state(id, state)
		if _held_ids.has(id):
			continue
		var ready := bool(sh.get("ready", true))
		if ready and sh.has("p"):
			_ensure_shard_model(sh, false)   # слот пополнился: прошлую модель убрали, когда шард ушёл в деку
		var m: Node3D = _pickups.get(id)
		if m != null:
			m.visible = ready
			_set_dim(m, state == NodeView.VAULT_CLOSED)


## Мёртвые деки (К8): слот держит демона погибшего нетраннера — рядом с хранилищем лежит мёртвая дека; хранилище опустело — деки нет.
## Новый сервер шлёт `dead` в каждом слоте; старый поля не знает — тогда деки из `node.dead` остаются как есть.
func _refresh_dead_decks(shards: Array) -> void:
	if not shards.any(func(sh: Dictionary) -> bool: return sh.has("dead")):
		return
	var spots: Array = []
	for sh in shards:
		if bool(sh.get("dead", false)) and sh.has("p") and bool(sh.get("ready", true)):
			var p: Array = sh["p"]
			var to_center := Vector2(-float(p[0]), -float(p[2])).normalized() * 0.8
			spots.append([float(p[0]) + to_center.x, float(p[2]) + to_center.y])
	view.set_dead_decks(spots)


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
	_vault_info.clear()
	for sh in shards:
		_vault_info[str(sh["id"])] = sh
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
		var state := NodeView.vault_state_of(sh)
		_vault_state[id] = state
		var m := _ensure_shard_model(sh, true)
		m.visible = bool(sh.get("ready", true))
		_set_dim(m, state == NodeView.VAULT_CLOSED)
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


## Модель шарда слота: создаёт (или меняет на другую, если шард стал зашифрованным / открытым) и подписывает тир. enc в описании нет — модель не
## меняется. Положение — по p при создании или reposition.
func _ensure_shard_model(sh: Dictionary, reposition: bool) -> Node3D:
	var id := str(sh["id"])
	var m: Node3D = _pickups.get(id)
	var asset := NodeAssets.prop_path("shard")
	if sh.has("enc"):
		asset = NodeAssets.prop_path("shard_encrypted" if bool(sh["enc"]) else "shard")
	elif m != null:
		asset = str(m.get_meta("asset", asset))
	if m != null and str(m.get_meta("asset", "")) != asset:  # шард стал зашифрованным (или наоборот): другая модель
		m.queue_free()
		_pickups.erase(id)
		m = null
	if m == null:
		m = NodeAssets.instance(asset)
		m.name = id
		add_child(m)
		_pickups[id] = m
		reposition = true
	if reposition and sh.has("p"):
		var p: Array = sh["p"]
		m.position = Vector3(p[0], p[1], p[2])
		m.set_meta("y0", float(p[1]))
	_set_tier_label(m, int(sh.get("tier", 0)), str(sh.get("kind", "shard")) == "daemon")
	return m


## Подпись тира над шардом («ТИР 2»), смотрит на игрока; тира не знаем (0) — без подписи.
func _set_tier_label(m: Node3D, tier: int, daemon: bool = false) -> void:
	var l := m.get_node_or_null("TierLabel") as Label3D
	if tier <= 0:
		if l != null:
			l.queue_free()
		return
	if l == null:
		l = Label3D.new()
		l.name = "TierLabel"
		l.font_size = 40
		l.pixel_size = 0.0015
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color(0.5, 0.95, 1.0)
		l.position = Vector3(0, 0.2, 0)
		m.add_child(l)
	l.text = ("ДЕМОН · ТИР %d" if daemon else "ТИР %d") % tier


## Шард в закрытом хранилище: меньше и полупрозрачный (по меткам-мешам модели); открытый и тот, что в руке, — обычные.
func _set_dim(m: Node3D, dim: bool) -> void:
	m.scale = Vector3.ONE * (SHARD_DIM_SCALE if dim else 1.0)
	for n in m.find_children("*", "MeshInstance3D", true, false):
		(n as GeometryInstance3D).transparency = 1.0 - SHARD_DIM_ALPHA if dim else 0.0
	m.set_meta("dim", dim)


## Шарды на хранилищах медленно вращаются и парят; шард в руке (и в чужих руках) стоит как стоит.
func _animate_shards(delta: float) -> void:
	_spin_t += delta
	for id in _pickups:
		var m: Node3D = _pickups[id]
		if _held_ids.has(id) or not m.visible or not m.has_meta("y0") or bool(m.get_meta("dim", false)):
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


# ---------------------------------------------------------------- взлом хранилища (К3)

## Привязка точки телепорта к площадке перед хранилищем (XRRig.teleport_snap): те же числа, что у сервера (NodeLayout.snap_to_vault_pad).
func snap_teleport(to: Vector3) -> Dictionary:
	return NodeLayout.snap_to_vault_pad(to, _vault_list().map(func(v: Dictionary) -> Vector3: return v["p"]))


## Хранилища узла: [{id, p: Vector3}] по последним записям сервера.
func _vault_list() -> Array:
	var out: Array = []
	for id in _vault_info:
		var sh: Dictionary = _vault_info[id]
		if sh.has("p"):
			var p: Array = sh["p"]
			out.append({"id": id, "p": Vector3(float(p[0]), float(p[1]), float(p[2]))})
	return out


## Демоны, годные для взлома (рабочие, с цепочкой), и RAM — в панель. Не чаще, чем меняются.
func _refresh_breach_context() -> void:
	var list: Array = []
	for d in deck_info.get("daemons", []):
		if bool(d.get("loaded", true)) and not (d.get("cells", []) as Array).is_empty():
			list.append({"id": str(d["id"]), "name": str(d.get("name", d["id"])), "effect": str(d.get("effect", "")), "tier": int(d.get("tier", 1)), "cells": d["cells"]})
	var key := [str(node_info.get("title", "")), str(node_info.get("tier", "")), int(deck_info.get("ram", 6)), list]
	if key == _breach_ctx_key:
		return
	_breach_ctx_key = key
	world_ui.breach_panel.set_context(key[0], key[1], list, key[2])


## Панель до начала взлома: появляется у ближайшего хранилища, где можно что-то сделать (взломать, дождаться, увидеть «ЗАНЯТО»), и гаснет, когда
## игрок отошёл. Открытое для игрока хранилище панели не требует — шард берут рукой. Поза ставится один раз при появлении: дальше панель стоит в мире.
func _update_breach_panel() -> void:
	var bp := world_ui.breach_panel
	var mode := bp.mode()
	if mode == BreachPanel.MODE_RUN:
		return
	var vaults := _vault_list()
	if mode == BreachPanel.MODE_RESULT:
		if not vaults.is_empty() and BreachPanelLayout.target_vault(rig.global_position, vaults, bp.vault_id()) == "":
			bp.hide_panel()   # игрок ушёл от хранилища — итог можно не закрывать
		return
	var target := BreachPanelLayout.target_vault(rig.global_position, vaults, bp.vault_id() if mode == BreachPanel.MODE_IDLE else "")
	if target.is_empty() or movement_blocked():
		if mode == BreachPanel.MODE_IDLE:
			bp.hide_panel()
		return
	var info: Dictionary = _vault_info[target]
	if str(info.get("access", "ok")) == "open" or str(info.get("vault", "")) == "":
		if mode == BreachPanel.MODE_IDLE:
			bp.hide_panel()
		return
	if mode != BreachPanel.MODE_IDLE or bp.vault_id() != target:
		bp.place(BreachPanelLayout.pose(rig.camera.global_position, _vault_pos(target)))
	bp.show_idle(target, info)


func movement_blocked() -> bool:
	return rig.movement_locked


func _vault_pos(id: String) -> Vector3:
	var p: Array = _vault_info[id]["p"]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## События взлома от сервера (WorldMsg.EV_BK*): сетка, ответ на тап, итог, отказ. Панель в мире уже стоит (idle) или ставится здесь.
func apply_breach_event(ev: Dictionary) -> void:
	if str(ev.get("mode", "")) == WorldMsg.MODE_CHARGE or str(ev.get("mode", "")) == WorldMsg.MODE_DECRYPT:
		_apply_charge_event(ev)   # заряд демона и расшифровка шарда идут на деке запястья, а не на панели у хранилища
		return
	var bp := world_ui.breach_panel
	match str(ev.get("kind", "")):
		WorldMsg.EV_BK:
			var m := BreachMirror.from_event(ev)
			if m == null:
				return
			if bp.mode() != BreachPanel.MODE_IDLE or bp.vault_id() != m.vault:
				if _vault_info.has(m.vault):
					bp.place(BreachPanelLayout.pose(rig.camera.global_position, _vault_pos(m.vault)))
			_refresh_breach_context()
			bp.begin(m)
		WorldMsg.EV_BK_TICK:
			bp.apply_tick(ev)
		WorldMsg.EV_BK_END:
			bp.apply_end(ev)
		WorldMsg.EV_BK_NO:
			bp.show_denied(str(ev.get("reason", "")), int(ev.get("left", 0)))


## События заряда (mode = charge): сетка на деке, ответ на тап, итог, отказ.
func _apply_charge_event(ev: Dictionary) -> void:
	var deck := world_ui.deck
	var decrypting := str(ev.get("mode", "")) == WorldMsg.MODE_DECRYPT
	match str(ev.get("kind", "")):
		WorldMsg.EV_BK:
			deck.begin_charge(BreachMirror.from_event(ev), WorldMsg.MODE_DECRYPT if decrypting else WorldMsg.MODE_CHARGE, str(ev.get("title", "")) if decrypting else "")
		WorldMsg.EV_BK_TICK:
			deck.apply_charge_tick(ev)
		WorldMsg.EV_BK_END:
			deck.apply_charge_end(ev)
			var done := bool(ev.get("decrypted", false)) if decrypting else bool(ev.get("charged", false))
			world_ui.feedback.pulse("left", CHARGED_PULSE_AMP if done else DENY_PULSE_AMP, CHARGED_PULSE_S if done else DENY_PULSE_S)
		WorldMsg.EV_BK_NO:
			if decrypting:
				deck.show_decrypt_denied(str(ev.get("reason", "")))
			else:
				deck.show_charge_denied(str(ev.get("reason", "")), int(ev.get("left", 0)))
			world_ui.feedback.pulse("left", DENY_PULSE_AMP, DENY_PULSE_S)

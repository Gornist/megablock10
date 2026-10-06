class_name GrayNode
extends Node
## Серый узел node_07 (N7): собирает N1–N6 в одну играбельную сцену на сервере.
## На сессию — TraceMeter и DaemonSession; ICE шагает 10 раз/с (IceNode), видимость учитывает GHOST;
## игрокам раз в 0.1 с уходит снимок (trace, ICE, перезарядки), события — отдельными сообщениями.
## Добыча: взяли шард — op.take_from_node (в деку); выход — одна операция run.finish: при чистом выходе добыча на телефон,
## при выбросе/флэтлайне/обрыве остаётся в узле (и физически лежит на постаменте). Без Моста ценности не трогаем.
## Сервер мира одноразовый (M5): всё, что должно пережить рестарт, лежит в Мосте. При старте узел подписывается на
## session/deck/node/item, берёт снимок и продолжает: активные сессии ждут возврата игрока, шард на месте или у держателя,
## локдаун узла запомнен. Своё состояние узел пишет в node.data.world, связь игрока — в session.data.world.

## Black ICE (P4): живёт только в узлах тира NIGHTMARE. Поймал — флэтлайн: клиенту «ended flatline», а в Мосте перед
## run.finish(black_ice) — «ждём мастера» (master.gate flatline, если включено await_flatline): approve → флэтлайн как есть
## (мёртвая дека остаётся в узле, защищённый демон — на телефон, карточка «ФЛЭТЛАЙН»), deny («пощадить до применения») →
## исход как при выбросе Soft ICE. Персонажа код не убивает: это только карточка мастеру. Охота: за нетраннером с trace ≥ TRACE
## Black ICE идёт по позиции; пока она идёт, NetServer считает выход аварийным «под охотой» — дека сгорает.

## Что произошло в узле: {kind: ice_eject|flatline|hunt|waiting_master|exit|shard_taken|daemon|level, session, ...}. Для журнала и тестов.
signal event(ev: Dictionary)

## Игрок простоял в радиусе портала достаточно (W1): граф переводит его в узел `to`.
signal portal_requested(session: String, to: String)
## Строка журнала ICE (то же печатается в stdout): переход состояния или выброс.
signal ice_logged(line: String)

const STATE_INTERVAL := 0.1
## Позиции других аватаров — вдвое чаще (docs/netrun.md: ~20 раз/с).
const AVATAR_INTERVAL := 0.05
## Допуск на дробное число физических тиков в интервале (60 Гц: 0.1 с — 6 тиков с погрешностью).
const TICK_EPS := 0.001
const NODE_ID := "node_07"
## Исход забега не теряем, если Мост недоступен: повтор с тем же rid (finish:<сессия>) раз в FINISH_RETRY_SEC.
const FINISH_ATTEMPTS := 60
const FINISH_RETRY_SEC := 2.0
## Дека меняется под ногами (пришёл предмет по op.give_item): moves пересобираются и уходят тем же rid не больше стольких раз.
const MOVES_ATTEMPTS := 4
## Запись охоты в сессию (world.hunt): охота не критична для хода — при недоступном Мосте HUNT_ATTEMPTS попыток с паузой
## hunt_retry_sec, потом пропускаем (не копим очередь); следующая смена охоты запишется заново.
const HUNT_ATTEMPTS := 6
const HUNT_RETRY_SEC := 0.5
## Типы документов, на которые узел подписывается в Мосте.
const SYNC_TYPES: Array = ["session", "deck", "node", "item"]
## Тир узла, где живёт Black ICE (документ node, поле tier).
const TIER_BLACK := "NIGHTMARE"
## Вид хранилища слота (vault_state): пусто / закрыто (шард внутри, не взять) / открыто (можно взять).
const VAULT_EMPTY := "empty"
const VAULT_CLOSED := "closed"
const VAULT_OPEN := "open"
## Как часто спрашиваем Мост «решил ли мастер», пока он не решил (срок и действие по таймауту ведёт сам Мост).
const GATE_POLL_SEC := 1.0
## Срок ожидания по умолчанию и запас сверх него (с): дольше — запись в журнал и дальше те же опросы, исхода сами не назначаем.
const GATE_DEFAULT_TIMEOUT_SEC := 60.0
const GATE_GRACE_SEC := 30.0

var net: NetServer
## Узел, которому служит этот GrayNode: снимки и аватары получают только сессии, чей узел (NetServer.node_of) — он.
var node_id: String = NODE_ID
## Описание узла из графа (NodeGraph.nodes[id]: title, tier, ice, shards, links); пусто — прежний одиночный серый узел.
var node_def: Dictionary = {}
## Числа графа (NodeGraph.settings): переход, пополнение, тревога, локдаун. Работают только вместе с node_def.
var settings: Dictionary = NodeGraph.DEFAULT_SETTINGS
## Узлы графа ходят по общим часам (GraphClock), чтобы перезарядки демонов и trace сессии при переходе оставались верными.
var shared_clock: GraphClock
## Сети и вход игроков подключает граф (GraphWorld): один узел из многих не должен перетирать обработчики NetServer.
var manage_net_hooks := true
## Подписку на Мост и снимок берёт сам узел; в графе — GraphWorld один раз на всех (повторная подписка на те же типы снимка не даёт).
var manage_sync := true
var bridge: BridgeApi
var daemons := DaemonService.new()
## Настройки ICE и trace (подбираются на этапе 2); пусто — значения по умолчанию.
var ice_settings: Dictionary = {}
var trace_settings: Dictionary = {}
## Поверх ice_settings — только для Black ICE (hunt_speed, hunt_level, дальность взгляда…).
var black_ice_settings: Dictionary = {}

var _now := 0.0
var _state_acc := 0.0
var _avatar_acc := 0.0
var _step_count := 0
var _step_us_total := 0
var _step_us_max := 0
var _ices: Array[IceNode] = []
var _sessions: Dictionary = {}       # сессия -> DaemonSession (в нём trace)
var _effect_logged: Dictionary = {}  # сессия -> {id демона: true}: эффект, начало которого записано в журнал (конец — когда st перестал быть active)
var _shard_items: Dictionary = {}    # id объекта -> id предмета в Мосте
var _item_meta: Dictionary = {}      # id предмета узла -> {tier, enc}: что показывать на шарде (из документа Моста)
var _vault_open: Dictionary = {}     # id слота -> сессия, для которой хранилище открыто взломом (K3); нужно, только если включён vault_requires_open
var _vault_open_until: Dictionary = {} # id слота -> время узла, когда открытость кончается (нет записи — без срока)
## Взлом хранилищ (К3): сетка, таймер, тапы, итог в Мост.
var breach: VaultBreach
var charge: ChargeBreach
var decrypt: DecryptBreach
var _takes_inflight: Dictionary = {} # сессия -> число незавершённых op.take_from_node (в графе общий на все узлы)
var _slot_pos: Dictionary = {}       # id объекта (слот шарда узла) -> позиция
var _entered_at: Dictionary = {}     # сессия -> время узла, когда она вошла (журнал ICE: «секунды от входа»)
var _taken_by: Dictionary = {}       # сессия -> [id слотов этого узла, которые она взяла]
var _refill_at: Dictionary = {}      # id пустого слота -> когда пробовать пополнить (время узла)
var _refill_busy: Dictionary = {}    # id слота -> идёт запрос шарда в Мосте
var _portals: Array = []             # [{to, slot, pos}] порталы узла графа
var _portal_state: Dictionary = {}   # сессия -> {to, since, fired} — сколько стоит у портала
var _exiting: Dictionary = {}        # сессия -> true между «аватар убран» и событием выхода: её забег закрывает этот узел
var _level_cbs: Dictionary = {}      # сессия -> Callable, подключённый к trace.level_changed (при переходе переподключается)
var _local_lock_until := 0.0         # локдаун узла от сервера мира (время узла), когда Моста нет
var _alert_t := 0.0
var _ready_done := false
## Сессии, чей исход уже уходит в Мост (в том числе восстановленный флэтлайн): второй исход и повторный вход не допускаем.
var _finishing: Dictionary = {}
var _hunted: Dictionary = {}         # сессия -> true, пока за ней идёт охота Black ICE
var hunt_retry_sec := HUNT_RETRY_SEC # пауза между попытками записи охоты (тест ставит поменьше)
var _given: Dictionary = {}          # id предмета, отданного игроком другому (К5б) -> сессия, у которой он теперь ("" — ушёл на телефон); слот отданного шарда не вернуть на постамент
var _hunt_written: Dictionary = {}   # сессия -> bool: что Мост подтвердил в world.hunt (нет записи — не писали, то есть false)
var _hunt_writing: Dictionary = {}   # сессия -> true, пока идёт запись: она одна на сессию и сама перечитывает нужное значение
var _flat_disconnect: Dictionary = {} # сессия -> true: Black ICE догнал в окне возврата после обрыва («обрыв до флэтлайна»)
## Снимок Моста принят (после рестарта — активные сессии и шард восстановлены).
var synced := false
## Сессии, взятые из снимка Моста: ждали возврата игрока.
var recovered_sessions: Array[String] = []
## Сессии с недовершённым флэтлайном из прошлого процесса (пометка world.finish в Мосте).
var recovered_flatlines: Array[String] = []
## Конец локдауна узла (мс Unix, время Моста; 0 — нет) — из документа node.
var lockdown_until := 0
var node_writes := 0
var _node_write_busy := false
var _node_write_again := false
## Тревога узла 0…1 (граф): растёт от trace игроков и выбросов, остывает; усиливает зрение ICE.
var alert := 0.0


## Узел графа (W1): id, тир, число Soft ICE, шарды, порталы. Вызывается до start(); Black ICE ставится по тиру NIGHTMARE.
func apply_def(id: String, def: Dictionary, graph_settings: Dictionary, graph: NodeGraph) -> void:
	node_id = id
	node_def = def
	settings = graph_settings
	_portals.clear()
	for i in (def.get("links", []) as Array).size():
		var to := str(def["links"][i])
		_portals.append({"to": to, "slot": i, "pos": NodeLayout.PORTAL_SLOTS[i], "title": graph.title_of(to), "tier": graph.tier_of(to)})


func is_graph_node() -> bool:
	return not node_def.is_empty()


## Учебный узел: шард-заглушка без ценности (в Мосте предмета нет, слот не пустеет), выброс не закрывает узел.
func is_tutorial() -> bool:
	return bool(node_def.get("tutorial", false))


func tier() -> String:
	return str(node_def.get("tier", ""))


## Общий словарь «сессия -> незавершённые take» на весь граф: итог забега ждёт take, начатый в предыдущем узле.
func share_takes_inflight(d: Dictionary) -> void:
	_takes_inflight = d


static func shard_id(node: String, k: int) -> String:
	return "%s_pk%d" % [node, k]


func start(server: NetServer, bridge_api: BridgeApi = null) -> void:
	net = server
	bridge = bridge_api
	breach = VaultBreach.new(self)
	charge = ChargeBreach.new(self)
	decrypt = DecryptBreach.new(self)
	daemons.load_dir()
	_build_slots()
	if manage_net_hooks:
		net.grab_check = can_grab
		net.teleport_snap = func(_session: String, to: Vector3) -> Dictionary: return snap_teleport(to)
		net.join_check = func(session: String) -> bool: return not join_blocked(session)
	net.session_joined.connect(_on_joined)
	net.avatar_removed.connect(_on_avatar_removed)
	net.object_taken.connect(_on_object_taken)
	net.exit_event.connect(_on_exit_event)
	net.daemon_requested.connect(_on_daemon_requested)
	net.leave_requested.connect(_on_leave_requested)
	net.breach_open_requested.connect(_on_breach_open)
	net.charge_requested.connect(_on_charge_requested)
	net.decrypt_requested.connect(_on_decrypt_requested)
	# Клетки и отмена идут одним сообщением на обе мини-игры; у игрока одновременно одна из них (заряд и взлом друг друга исключают).
	net.breach_tap_requested.connect(func(session: String, cell: Array) -> void:
		if charge.has_attempt(session):
			charge.request_tap(session, cell)
		elif decrypt.has_attempt(session):
			decrypt.request_tap(session, cell)
		else:
			breach.request_tap(session, cell))
	net.breach_cancel_requested.connect(func(session: String) -> void:
		if charge.has_attempt(session):
			charge.request_cancel(session)
		elif decrypt.has_attempt(session):
			decrypt.request_cancel(session)
		else:
			breach.request_cancel(session))
	net.teleported.connect(func(session: String, _from: Vector3, _to: Vector3) -> void:
		breach.end_early(session, "teleport")
		charge.end_early(session, "teleport")
		decrypt.end_early(session, "teleport"))
	var soft := NodeLayout.ICE.size() if node_def.is_empty() else int(node_def.get("ice", 1))
	for i in soft:
		_add_ice(NodeLayout.ICE[i]["id"], NodeLayout.ICE[i]["waypoints"])
	if tier() == NodeGraph.TIER_BLACK:
		enable_black_ice()
	net.session_lost.connect(_on_session_lost)
	if bridge != null:
		bridge.doc_changed.connect(_on_doc_changed)
	if manage_sync:
		_sync_from_bridge()
	set_physics_process(true)
	_ready_done = true


## Слоты шардов: одиночный узел — один объект pickup_01 на постаменте, узел графа — по числу шардов в def.
func _build_slots() -> void:
	if node_def.is_empty():
		_slot_pos[NetConfig.PICKUP_ID] = NodeLayout.SHARD_POS
		net.place_object(NetConfig.PICKUP_ID, NodeLayout.SHARD_POS)
		return
	for k in int(node_def.get("shards", 1)):
		var id := shard_id(node_id, k)
		_slot_pos[id] = NodeLayout.SHARD_SLOTS[k]
		net.add_object(id, NodeLayout.SHARD_SLOTS[k])


func now() -> float:
	return _now


func session_state(session: String) -> DaemonSession:
	return _sessions.get(session)


func ices() -> Array[IceNode]:
	return _ices


## Сколько времени занимает шаг сервера узла (_physics_process целиком, мкс): {count, avg_us, max_us}.
func step_stats() -> Dictionary:
	return {"count": _step_count, "avg_us": _step_us_total / maxi(_step_count, 1), "max_us": _step_us_max}


## Сессии, которым сейчас что-то уходит: в этом узле и с аватаром.
func _live_sessions() -> Array:
	var out: Array = []
	for session in _sessions:
		if net.node_of(session) == node_id and net.has_avatar(session):
			out.append(session)
	return out


## Есть ли в узле Black ICE (тир NIGHTMARE или добавлен тестом).
func has_black_ice() -> bool:
	for ice in _ices:
		if ice.brain != null and ice.brain.is_black():
			return true
	return false


## Поселить Black ICE узла (NodeLayout.BLACK_ICE); повторный вызов ничего не добавляет.
func enable_black_ice() -> void:
	if has_black_ice():
		return
	for d in NodeLayout.BLACK_ICE:
		_add_ice(d["id"], d["waypoints"], true)


## Для тестов: убрать Black ICE (узел без него).
func queue_free_black_for_test() -> void:
	for ice in _ices.duplicate():
		if ice.brain != null and ice.brain.is_black():
			_ices.erase(ice)
			ice.queue_free()


func _add_ice(id: String, waypoints: Array, black: bool = false) -> void:
	var wps: Array[Vector3] = []
	for w in waypoints:
		wps.append(w)
	var ice := IceNode.new()
	ice.name = id
	ice.position = wps[0]
	ice.time_source = now
	var settings := ice_settings.duplicate(true)
	settings.merge(node_def.get("ice_settings", {}), true)  # узел может смягчить ICE (учебный)
	if black:
		settings.merge(black_ice_settings, true)
		settings["black"] = true
	ice.setup(settings, wps)
	# Журнал — до _on_ice_ejected: выброс убирает аватар, а строке нужна позиция игрока.
	ice.brain.state_changed.connect(_log_ice_state.bind(ice))
	ice.ejected.connect(_log_ice_eject.bind(ice))
	ice.ejected.connect(_on_ice_ejected)
	add_child(ice)
	_ices.append(ice)


## Журнал ICE (разбор забегов): строка на переход состояния и на выброс, без строки на кадр.
func _log_ice_state(old_state: int, new_state: int, ice: IceNode) -> void:
	var what := "%s→%s" % [IceBrain.state_name(old_state), IceBrain.state_name(new_state)]
	_log_ice(ice, ice.brain.target(), what, ice.brain.awareness())


func _log_ice_eject(session: String, reason: String, ice: IceNode) -> void:
	_log_ice(ice, session, "ВЫБРОС %s" % reason, -1.0)


## «t» — секунды от входа этой сессии в узел (нет сессии или входа — часы узла); awareness < 0 не печатаем.
func _log_ice(ice: IceNode, session: String, what: String, awareness: float) -> void:
	var t := _now - float(_entered_at.get(session, 0.0))
	var d := "—"
	var p: Variant = ice.targets.get(session)
	if p is Vector3:
		d = "%.1f" % ice.brain.position.distance_to(p)
	var aw := "" if awareness < 0.0 else " aw=%.2f" % awareness
	var line := "[ice] t=%.1f %s %s%s alert=%.2f d=%s %s" % [t, ice.name, what, aw, alert, d, session]
	print(line)
	ice_logged.emit(line)


## Снимок Моста: ждём связи, подписываемся, восстанавливаем (после рестарта сервера мира здесь же приходит прошлый забег).
func _sync_from_bridge() -> void:
	if bridge == null:
		return
	while not bridge.is_ready():
		await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
	@warning_ignore("redundant_await")
	var snap: Dictionary = await bridge.subscribe(SYNC_TYPES)
	if not is_inside_tree():
		return
	if not snap.get("ok", false):
		push_warning("[gray-node] подписка на Мост не удалась: %s" % BridgeApi.err_code(snap))
		return
	apply_snapshot(snap.get("docs", []))


## Снимок Моста принят: восстановление и первая запись состояния узла.
func apply_snapshot(docs: Array) -> void:
	recover(docs)
	synced = true
	for session in _hunt_written.keys():
		_sync_hunt(session)  # охота прошлого процесса не продолжается: снять её отметку в Мосте
	_write_node_state()


## Разбор снимка: узел (локдаун), шард, активные сессии этого узла. Публичный — для тестов.
func recover(docs: Array) -> void:
	var node_items: Array[String] = []   # свободные предметы узла: шарды и демоны (хранилище с демоном — К8)
	var deck_docs: Array = []            # предметы deck:<сессия> — кто из них добыча, решает session.loaded (после разбора всех сессий)
	var active_data: Dictionary = {}     # активные сессии этого узла: id -> data документа
	var active: Array[String] = []
	var opened: Array = []               # [{session, item, until}] хранилища, открытые взломами активных сессий (session.data.opened, пишет Мост)
	var flatlined: Dictionary = {}  # сессия -> disconnect: сервер упал, пока ждал мастера (пометка world.finish)
	var saved_world: Dictionary = {}     # node.data.world прошлого процесса: тревога и сроки пополнения слотов
	for d in docs:
		var data: Dictionary = d.get("data", {})
		match str(d.get("type", "")):
			BridgeApi.T_NODE:
				if d["id"] == node_id:
					lockdown_until = int(data.get("lockdown_until", 0))
					if data.get("world") is Dictionary:
						saved_world = data["world"]
					if node_def.is_empty() and str(data.get("tier", "")) == TIER_BLACK:
						enable_black_ice()  # у узла графа тир задаёт graph.json
			BridgeApi.T_SESSION:
				if data.get("state") == "active" and _session_location(data) == node_id:
					var w: Variant = data.get("world")
					if w is Dictionary and (w as Dictionary).get("finish") == "flatline":
						flatlined[str(d["id"])] = bool((w as Dictionary).get("disconnect", false))
					else:
						active.append(str(d["id"]))
						active_data[str(d["id"])] = data
						for o in data.get("opened", []):
							if o is Dictionary and str(o.get("node", node_id)) == node_id:
								opened.append({"session": str(d["id"]), "item": str(o.get("item", "")), "until": int(o.get("until", 0))})
						if w is Dictionary and (w as Dictionary).get("hunt") == true:
							_hunt_written[str(d["id"])] = true  # отметка прошлого процесса: его охоты нет, apply_snapshot её снимет
			BridgeApi.T_ITEM:
				if data.get("kind") != "SHARD" and data.get("kind") != "DAEMON":
					continue
				var owner := str(data.get("owner", ""))
				if owner == "node:" + node_id:
					node_items.append(str(d["id"]))
					_item_meta[str(d["id"])] = vault_meta(data)
				elif owner.begins_with("deck:"):
					deck_docs.append(d)
	var held := held_items(deck_docs, active_data, node_id, node_def.is_empty())   # [{item, by}] добыча, которую игроки несут из этого узла
	if is_tutorial():
		node_items.clear()  # шард учебного узла — заглушка: предметов Моста к нему не привязываем
		held.clear()
	node_items.sort()
	var free_slots: Array = _slot_pos.keys()
	_restore_alert(saved_world)
	var pending := _restore_refill_slots(saved_world)  # слоты, чьё пополнение ещё не подошло: остаются пустыми
	for sid in pending:
		free_slots.erase(sid)
	# Шард, который игрок уже несёт, остаётся у него: клиент второй раз его не возьмёт, выход вернёт его по moves.
	for h in held:
		if h["by"] in active and not free_slots.is_empty():
			var sid: String = free_slots.pop_front()
			_shard_items[sid] = h["item"]
			net.restore_holder(sid, h["by"])
			_taken_by[h["by"]] = _taken_by.get(h["by"], []) + [sid]
	for item in node_items:
		if free_slots.is_empty():
			break
		_shard_items[free_slots.pop_front()] = item
		_given.erase(item)
	if not free_slots.is_empty() and not is_tutorial():
		if node_def.is_empty():
			push_warning("[gray-node] в Мосте нет шарда в узле %s: добыча останется только игровой" % node_id)
		else:
			for sid in free_slots:  # слот без шарда пуст, пока в Мосте не появится свободный (пополнение)
				_deplete(sid, 0.0)
	for sid in pending:
		_deplete(sid, float(pending[sid]))
	# Хранилища, открытые взломом до рестарта, остаются открытыми взломщику до срока (Мост помнит их в session.opened).
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for o in opened:
		var slot := slot_of_item(o["item"])
		if slot != "" and float(o["until"]) > now_ms:
			open_vault(slot, o["session"], (float(o["until"]) - now_ms) / 1000.0)
	for s in active:
		recovered_sessions.append(s)
		_exiting[s] = true  # аватара не было: avatar_removed не придёт, а в графе забег закрывает только узел с этой меткой
		net.set_node(s, node_id)
		net.expect_session(s)
	# Флэтлайн, начатый прошлым процессом: окна возврата нет, ждём мастера дальше и закрываем забег тем же исходом.
	for s in flatlined:
		recovered_flatlines.append(s)
		_finishing[s] = true
		print("[gray-node] сессия ", s, ": флэтлайн из прошлого процесса, продолжаем ожидание мастера")
		_finish_in_bridge({"session": s, "reason": ExitLogic.REASON_FLATLINE, "under_hunt": false, "deck_burned": false,
			"disconnect": flatlined[s]})
	print("[gray-node] снимок Моста (", node_id, "): активных сессий ", active.size(), ", шард ", ",".join(_shard_items.values()) if not _shard_items.is_empty() else "—", ", локдаун до ", lockdown_until)


## Тревога из прошлого процесса: остывала по alert_cool_sec с момента записи (alert_at, мс Unix), пока сервера мира не было.
func _restore_alert(saved_world: Dictionary) -> void:
	var a := float(saved_world.get("alert", 0.0))
	if a <= 0.0 or not saved_world.has("alert_at"):
		return
	var elapsed := maxf(Time.get_unix_time_from_system() - float(saved_world["alert_at"]) / 1000.0, 0.0)
	alert = clampf(a - elapsed / maxf(float(settings["alert_cool_sec"]), 0.001), 0.0, 1.0)
	_apply_alert()


## Слоты, которые к рестарту ждали пополнения: id слота -> сколько секунд осталось (refill — {слот: срок, мс Unix}).
## Без этого пополнение после рестарта начиналось бы сразу, а не по таймеру узла.
func _restore_refill_slots(saved_world: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var saved: Variant = saved_world.get("refill")
	if not saved is Dictionary:
		return out
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for sid in saved:
		if _slot_pos.has(sid):
			out[sid] = maxf((float(saved[sid]) - now_ms) / 1000.0, 0.0)
	return out


## Где сессия сейчас: последняя запись сервера мира (world.node), иначе узел из документа Моста (куда её приняли).
func _session_location(data: Dictionary) -> String:
	var w: Variant = data.get("world")
	if w is Dictionary and (w as Dictionary).has("node"):
		return str((w as Dictionary)["node"])
	return str(data.get("node", node_id))


## Добыча, которую активные сессии этого узла несут в деке: шарды и демоны `deck:<сессия>`, не сданные при входе (`session.loaded`), —
## по `loaded`, а не по `origin`: шард мастера (`master:*`), демон мёртвой деки (`phone:<погибший>`) и отдача другого нетраннера по
## происхождению не «узловые», но тоже добыча (протокол, 6.9). [param sessions] — id -> `data` активных сессий здесь; чужие и закрытые
## пропускаются. В графе предмет с `origin: node:<другой узел>` этому узлу не принадлежит; остальные происхождения (`master:`, `phone:`)
## отнести к узлу нечем — их берёт тот узел, где сессия сейчас. Результат — [{item, by}] по возрастанию id.
static func held_items(deck: Array, sessions: Dictionary, node: String, single_node: bool) -> Array:
	var out: Array = []
	for d in deck:
		var data: Dictionary = d.get("data", {})
		var by := str(data.get("owner", "")).trim_prefix("deck:")
		if not sessions.has(by) or str(d.get("id", "")) == "":
			continue
		if is_working_item(d, sessions[by]):
			continue
		# taken_at — узел, где предмет взяли (op.take_from_node). origin у оставленного в чужом узле предмета прежний (где создан), и по нему
		# шард из узла B, взятый игроком, считался бы чужой добычей. Документы без taken_at (до этой правки) — по origin.
		var taken_at := "" if data.get("taken_at") == null else str(data["taken_at"])  # null после leave_in_node: str(null) — "<null>"
		var origin := str(data.get("origin", ""))
		if not single_node:
			if taken_at != "":
				if taken_at != node:
					continue
			elif origin.begins_with("node:") and origin != "node:" + node:
				continue
		out.append({"item": str(d["id"]), "by": by})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item"] < b["item"])
	return out


func _on_doc_changed(doc: Dictionary, deleted: bool) -> void:
	if deleted or doc.get("type") != BridgeApi.T_NODE or doc.get("id") != node_id:
		return
	lockdown_until = int((doc.get("data", {}) as Dictionary).get("lockdown_until", 0))


## node.data.world = {up, players}: что видит мастер. Мост — источник правды, остальные поля узла не трогаем.
func _write_node_state() -> void:
	if bridge == null or not synced:
		return
	if _node_write_busy:
		_node_write_again = true
		return
	_node_write_busy = true
	while true:
		_node_write_again = false
		var world := {"up": true, "players": _live_sessions().size()}
		if is_graph_node():
			world["alert"] = snappedf(alert, 0.01)
			world["slots_empty"] = _refill_at.size()
			world["alert_at"] = int(Time.get_unix_time_from_system() * 1000.0)
			var refill: Dictionary = {}
			var now_ms := Time.get_unix_time_from_system() * 1000.0
			for sid in _refill_at:
				refill[sid] = int(now_ms + maxf(float(_refill_at[sid]) - _now, 0.0) * 1000.0)
			world["refill"] = refill
		var ok := await put_field(BridgeApi.T_NODE, node_id, "world", world)
		if ok:
			node_writes += 1
		if not _node_write_again or not is_inside_tree():
			break
	_node_write_busy = false


## Чтение-правка-запись одного поля data документа с повтором при version_conflict. false — не вышло (документа нет, отказ).
func put_field(type: String, id: String, key: String, value: Variant) -> bool:
	for attempt in 3:
		@warning_ignore("redundant_await")
		var g: Dictionary = await bridge.get_doc(type, id)
		if not g.get("ok", false):
			return false
		var cur: Dictionary = g["doc"]
		var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
		data[key] = value
		@warning_ignore("redundant_await")
		var r: Dictionary = await bridge.put_doc(type, id, int(cur["ver"]), data)
		if r.get("ok", false):
			return true
		if BridgeApi.err_code(r) != "version_conflict":
			push_warning("[gray-node] put %s/%s: %s" % [type, id, BridgeApi.err_code(r)])
			return false
	return false


## Рабочий ли демон по происхождению: только принесённый с телефона (`phone:*`). Запасное правило для вызова без документа сессии;
## настоящее деление — [method is_working_item] (docs/netrun-bridge-protocol.md, раздел 5, «Рабочие и груз»).
static func is_loaded_origin(origin: String) -> bool:
	return origin.begins_with("phone:")


## Рабочий ли предмет `deck:<сессия>` (ПРОГРАММЫ деки), как у Моста (`ItemFacts.isWorking`): его id есть в `session.loaded` (сданное при
## входе). Всё остальное в деке — груз: взятое в узле, наполнение мастера, мёртвая дека или отдача от другого нетраннера (у них у всех
## разное `origin`, включая `phone:<чужой>`). Сессия без `loaded` (создана до К2): рабочий — `origin == phone:<runner>`; нет и `runner`
## (документ сессии не получен) — любой `phone:*`. [param doc] — документ предмета {id, data}, [param session_data] — `data` сессии.
static func is_working_item(doc: Dictionary, session_data: Dictionary) -> bool:
	var loaded: Variant = session_data.get("loaded")
	if loaded is Array:
		return str(doc.get("id", "")) in (loaded as Array)
	var origin := str((doc.get("data", {}) as Dictionary).get("origin", ""))
	var runner := str(session_data.get("runner", ""))
	return is_loaded_origin(origin) if runner == "" else origin == "phone:" + runner


## Дека игрока из Моста: **рабочие** демоны предметов deck:<сессия> (по [method is_working_item]) с полем `daemon` ({effect, tier, name,
## cells}, его пишет Мост при приёме карточки). Возвращает [{id: id предмета, daemon: {...}, protected}]; нет ни одного — вызывающий
## оставляет деку по умолчанию. [param session_data] — `data` документа сессии (пусто — запасное правило по origin).
static func deck_from_items(items: Array, session: String, session_data: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in items:
		var data: Dictionary = d.get("data", {})
		if data.get("owner") != "deck:" + session or data.get("kind") != "DAEMON":
			continue
		if not is_working_item(d, session_data):
			continue
		var daemon: Variant = data.get("daemon")
		if daemon is Dictionary and str(d.get("id", "")) != "":
			out.append({"id": str(d["id"]), "daemon": daemon, "protected": bool(data.get("protected", false))})
	return out


## Груз игрока из Моста: шарды (kind SHARD) и демоны не из `session.loaded` предметов deck:<сессия> →
## [{id, kind: shard | daemon, tier, title, enc, give}] по id (список не прыгает). give — можно ли отдать другому игроку (К5б): нельзя то, что
## сдано при входе (`session.loaded`, включая шард, принесённый с телефона: Мост отвечает loaded_item) и защищённое. Шард без разобранного поля `shard` или без признака
## `decrypted` считается зашифрованным: тела мы не знаем, открыть его нельзя.
static func loot_from_items(items: Array, session: String, session_data: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in items:
		var data: Dictionary = d.get("data", {})
		if data.get("owner") != "deck:" + session or str(d.get("id", "")) == "":
			continue
		var kind := str(data.get("kind", ""))
		if kind == "SHARD":
			var sh: Variant = data.get("shard")
			var shard: Dictionary = sh if sh is Dictionary else {}
			out.append({"id": str(d["id"]), "kind": "shard", "tier": clampi(int(shard.get("tier", 1)), 1, 3),
				"title": str(shard.get("title", "Шард")), "enc": shard_encrypted(shard),
				"give": not is_working_item(d, session_data) and not bool(data.get("protected", false))})
		elif kind == "DAEMON" and not is_working_item(d, session_data):
			var dm: Variant = data.get("daemon")
			var daemon: Dictionary = dm if dm is Dictionary else {}
			var cells: Variant = daemon.get("cells")
			var chain: Array = (cells as Array).map(func(c: Variant) -> String: return str(c)) if cells is Array else []
			out.append({"id": str(d["id"]), "kind": "daemon", "tier": clampi(int(daemon.get("tier", 1)), 1, 3),
				"title": str(daemon.get("name", daemon.get("effect", "Демон"))), "enc": false, "give": not bool(data.get("protected", false)),
				"effect": str(daemon.get("effect", "")), "cells": chain})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	return out


## `moves` для `run.finish`: каждый незащищённый предмет `deck:<сессия>` — груз (не рабочий, [method is_working_item]) идёт туда, куда
## по исходу идёт добыча (`plan["loot"]`), рабочий демон — как демоны (`plan["daemon"]`). Так же делит Мост (протокол, 6.5): чужой
## `phone:<…>` в грузе иначе ушёл бы по правилу демонов и Мост отказал бы `bad_request` без повтора.
static func finish_moves(items: Array, session: String, session_data: Dictionary, plan: Dictionary) -> Array:
	var moves: Array = []
	for d in items:
		var data: Dictionary = d.get("data", {})
		if data.get("owner") != "deck:" + session or data.get("protected", false):
			continue
		moves.append({"item": str(d["id"]), "to": plan["daemon"] if is_working_item(d, session_data) else plan["loot"]})
	return moves


## Что дека показывает про сессию (событие `ev deck`): RAM и занятое ею, рабочие демоны (имя, эффект, тир, цепочка), груз и эдди.
func deck_view(ds: DaemonSession) -> Dictionary:
	var rows: Array = []
	var used := 0
	for id in ds.deck:
		var def := daemons.get_def(id)
		var meta: Dictionary = ds.deck_meta.get(id, {})
		var cells: Array = (meta.get("cells", []) as Array).map(func(c: Variant) -> String: return str(c))
		used += cells.size()
		var row := {"id": id, "name": daemons.display_name(id, NodeLayout.DAEMON_NAMES.get(id, id)), "effect": def.effect if def != null else "",
			"tier": def.tier if def != null else 1, "cells": cells, "prot": bool(meta.get("prot", false)), "loaded": true, "chargeable": daemons.is_chargeable(id)}
		if def != null and def.unsupported_reason != "":
			row["unsupported"] = def.unsupported_reason
		rows.append(row)
	return {"kind": WorldMsg.EV_DECK, "ram": ds.ram, "ram_default": ds.ram_default, "used": used, "daemons": rows,
		"loot": ds.loot_view, "eddies": ds.loot_eddies}


func _push_deck(session: String) -> void:
	var ds: DaemonSession = _sessions.get(session)
	if ds != null:
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, deck_view(ds)))


## Строка перезарядок в снимке: к {id, name, left} добавлены st (ready | charged | cooldown | active | unsupported) и until (время сервера, когда
## состояние кончится; нет у ready и unsupported). active — действует эффект (GHOST, JITTER) и важнее перезарядки, которая идёт параллельно.
func cd_entry(ds: DaemonSession, id: String, now: float) -> Dictionary:
	var def := daemons.get_def(id)
	var left := ds.cooldown_left(id, now)
	var entry := {"id": id, "name": daemons.display_name(id, NodeLayout.DAEMON_NAMES.get(id, id)), "left": left, "st": "ready"}
	if def != null and def.unsupported_reason != "":
		entry["st"] = "unsupported"
		return entry
	var act := ds.active_left(def.effect, now) if def != null else 0.0
	if act > 0.0:
		entry["st"] = "active"
		entry["until"] = snappedf(now + act, 0.001)
	elif left > 0.0:
		entry["st"] = "cooldown"
		entry["until"] = snappedf(now + left, 0.001)
	elif ds.is_charged(id):
		entry["st"] = "charged"
	return entry


## Дека и груз из Моста (предметы deck:<сессия>), RAM и эдди из документа сессии; в конце — событие `ev deck` игроку.
func _load_deck(session: String) -> void:
	if bridge == null or not bridge.is_ready():
		return
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_ITEM)
	var ds: DaemonSession = _sessions.get(session)
	if ds == null or not r.get("ok", false):
		return
	var docs: Array = r.get("docs", [])
	# Сессия нужна до деления на рабочих и груз (`loaded`, RAM): документ предметов один без неё не скажет, кто рабочий.
	@warning_ignore("redundant_await")
	var sr: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
	if _sessions.get(session) != ds:
		return   # сессия ушла, пока ждали Мост
	var sdata: Dictionary = {}
	if sr.get("ok", false):
		sdata = (sr["doc"] as Dictionary).get("data", {})
	var ids: Array[String] = []
	var meta := {}
	for e in deck_from_items(docs, session, sdata):
		var def := daemons.add_item_daemon(e["id"], e["daemon"])
		if def != null:
			ids.append(def.id)
			meta[def.id] = {"cells": e["daemon"].get("cells", []), "prot": e["protected"]}
			if def.unsupported_reason != "":
				print("[gray-node] ", session, ": демон ", def.display_name, " (", def.effect, ") не работает в Сети: ", def.unsupported_reason)
	if not ids.is_empty():
		ds.deck = ids
		ds.deck_meta = meta
	ds.loot_view = loot_from_items(docs, session, sdata)
	if not sdata.is_empty():
		var ram := int(sdata.get("ram", 0))
		if ram > 0:   # нет поля (сессия до К2): остаётся значение по умолчанию с пометкой
			ds.ram = ram
			ds.ram_default = false
		ds.loot_eddies = int(sdata.get("loot_eddies", 0))
		ds.runner_key = str(sdata.get("runner", ""))
	await _load_cooldown(session, ds)
	if _sessions.get(session) == ds:
		_push_deck(session)


## Остывание узлов для игрока из документа runner (breach_cooldown: узел -> мс Unix): по ключу игрока из сессии. Нет документа — остывания нет.
func _load_cooldown(session: String, ds: DaemonSession) -> void:
	if ds.runner_key.is_empty():
		return
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_RUNNER)
	if _sessions.get(session) != ds or not r.get("ok", false):
		return
	for d in r.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if str(data.get("key", "")) == ds.runner_key and data.get("breach_cooldown") is Dictionary:
			var cds: Dictionary = {}
			for k in data["breach_cooldown"]:
				cds[str(k)] = int(data["breach_cooldown"][k])
			ds.breach_cooldown = cds
			_push_shards()   # панель взлома показывает «ОСТЫВАЕТ»


# ---------------------------------------------------------------- отправка добычи (К5б, GiveService)

## Сессия игрока сейчас у этого узла (в графе — в узле, где он стоит или откуда ушёл в тоннель).
func has_session(session: String) -> bool:
	return _sessions.has(session)


## Можно ли менять груз сессии: она в узле, аватар на месте и забег не закрывается (выход, флэтлайн, охота за исходом).
func can_exchange(session: String) -> bool:
	return _sessions.has(session) and net != null and net.has_avatar(session) and not _finishing.has(session) and not _exiting.has(session)


## Отдача в Мосте началась/кончилась: исход забега ждёт её, как ждёт take (протокол, 6.7). Начинать до первого await.
func begin_inflight(session: String) -> void:
	_takes_inflight[session] = int(_takes_inflight.get(session, 0)) + 1


func end_inflight(session: String) -> void:
	_takes_inflight[session] = maxi(int(_takes_inflight.get(session, 0)) - 1, 0)


## Предмет отдан: теперь он у сессии `holder` ("" — на телефоне контакта). Запоминаем, чтобы слот шарда, откуда его взяли, не показал его
## снова. Вернулся к тому, кто его брал (A -> B -> A), — settle_shards снова видит его у него и слот не пустеет зря.
func note_given(item: String, holder: String = "") -> void:
	_given[item] = holder


## Предмет отдан кому-то, кроме `session` (у неё его нет): слот, откуда она его взяла, после её выхода не вернуть на постамент.
func is_given_away(item: String, session: String) -> bool:
	return _given.has(item) and str(_given[item]) != session


## Перечитать груз и деку игрока из Моста и отправить ему `ev deck`.
func refresh_deck(session: String) -> void:
	await _load_deck(session)


func callsign_of(session: String) -> String:
	return str(_callsign_of(session))


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	var us := Time.get_ticks_usec() - t0
	_step_count += 1
	_step_us_total += us
	_step_us_max = maxi(_step_us_max, us)


func _step(delta: float) -> void:
	if shared_clock != null:
		_now = shared_clock.now
	else:
		_now += delta
	var targets := {}
	var meters := {}
	for session in _live_sessions():
		var avatar := net.get_avatar(session)
		if avatar == null:
			continue
		var ds: DaemonSession = _sessions[session]
		meters[session] = ds.trace
		if not ds.is_ghost(_now):
			targets[session] = avatar.position
	for ice in _ices:
		ice.netrunner_count = meters.size()
		ice.targets = targets
		ice.meters = meters
	_update_hunts()
	breach.tick(delta)
	charge.tick(delta)
	decrypt.tick(delta)
	_expire_vaults()
	if is_graph_node():
		_check_portals()
		_tick_refill()
		_tick_alert()
	_state_acc += delta
	if _state_acc >= STATE_INTERVAL - TICK_EPS:
		_state_acc = maxf(_state_acc - STATE_INTERVAL, 0.0)
		_tick_traces()
		_broadcast_state()
	_avatar_acc += delta
	if _avatar_acc >= AVATAR_INTERVAL - TICK_EPS:
		_avatar_acc = maxf(_avatar_acc - AVATAR_INTERVAL, 0.0)
		_broadcast_avatars()


## Охота Black ICE → флаг «под охотой» у NetServer (аварийный выход сожжёт деку). Каждый тик: выход не ждёт 0,1 с.
func _update_hunts() -> void:
	for session in _live_sessions():
		var hunted := false
		for ice in _ices:
			if ice.brain != null and ice.brain.is_black() and ice.brain.is_hunting(session):
				hunted = true
		if hunted != bool(_hunted.get(session, false)):
			_hunted[session] = hunted
			net.set_under_hunt(session, hunted)
			event.emit({"kind": "hunt", "session": session, "on": hunted})
			_sync_hunt(session)


## Спад trace, пока никто из ICE не следит за игроком.
func _tick_traces() -> void:
	for session in _sessions.keys():
		if net.node_of(session) != node_id:
			continue  # в тоннеле между узлами trace стоит
		var watched := false
		for ice in _ices:
			if ice.brain != null and ice.brain.target() == session:
				watched = true
		(_sessions[session] as DaemonSession).trace.tick(_now, not watched)


func _broadcast_state() -> void:
	var ice_list: Array = []
	for ice in _ices:
		var b := ice.brain
		ice_list.append({
			"id": str(ice.name),
			"p": [ice.position.x, ice.position.y, ice.position.z],
			"f": [b.facing.x, b.facing.z],
			"s": b.state(),
			"b": 1 if b.is_black() else 0,
		})
	for session in _live_sessions():
		var ds: DaemonSession = _sessions[session]
		var cd: Array = []
		for id in ds.deck:
			cd.append(cd_entry(ds, id, _now))
		_log_effect_ends(session, cd)
		var msg := WorldMsg.encode_fields(WorldMsg.STATE, {
			"trace": ds.trace.value(),
			"level": ds.trace.level(),
			"ghost": ds.is_ghost(_now),
			"hunt": is_hunted(session),  # за этим игроком идёт охота Black ICE: клиент закрывает порталы (portal_locked)
			"k": snappedf(_now, 0.001),
			"ice": ice_list,
			"cd": cd,
		})
		net.send_to(session, msg, false)


## Позиции аватаров узла: каждому игроку — все остальные в его узле (себя клиент знает сам).
func _broadcast_avatars() -> void:
	var live := _live_sessions()
	var entries := {}
	for session in live:
		entries[session] = net.avatar_entry(session)  # [id, x, z] и счётчик скачков после телепорта
	var k := snappedf(_now, 0.001)
	for session in live:
		var others: Array = []
		for other in live:
			if other != session:
				others.append(entries[other])
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.AVATARS, {"k": k, "a": others}), false)


## Сессию не пускаем: её исход уже уходит в Мост.
func join_blocked(session: String) -> bool:
	return _finishing.has(session)


func _on_joined(session: String, _peer: int, _resumed: bool) -> void:
	if net.node_of(session) != node_id:
		return  # игрок в другом узле (граф): это дело того узла
	_exiting.erase(session)  # игрок вернулся: метка восстановления не нужна (при выходе её поставит _on_avatar_removed)
	if _sessions.has(session):
		if bridge != null and synced:
			_merge_world(session, {"connected": true, "trace": 0, "node": node_id})
		_push_deck(session)   # клиент вернулся (обрыв, перезапуск очков): его дека пуста, пока не пришло событие
		return
	var meter := TraceMeter.new(trace_settings)
	meter.reset(_now)
	_connect_meter(session, meter)
	var fresh := DaemonSession.new(NodeLayout.DEFAULT_DECK, meter)
	for id in NodeLayout.DEFAULT_DECK_CELLS:
		fresh.deck_meta[id] = {"cells": NodeLayout.DEFAULT_DECK_CELLS[id], "prot": false}
	_sessions[session] = fresh
	_entered_at[session] = _now
	print("[gray-node] ", session, " вошёл в ", node_id)
	_push_deck(session)   # сразу то, что известно (дека по умолчанию); настоящую деку и груз подтянет _load_deck
	if bridge != null:
		_load_deck(session)
		_merge_world(session, {"connected": true, "trace": 0, "node": node_id})
		_write_node_state()


func _connect_meter(session: String, meter: TraceMeter) -> void:
	var cb := _on_level_changed.bind(session)
	_level_cbs[session] = cb
	meter.level_changed.connect(cb)


func _on_session_lost(session: String) -> void:
	breach.end_early(session, "session_lost")   # обрыв посреди взлома — досрочный итог по собранному
	charge.end_early(session, "session_lost")   # заряд просто бросается
	decrypt.end_early(session, "session_lost")
	if bridge != null and synced and _sessions.has(session):
		_merge_world(session, {"connected": false, "trace": 0, "node": node_id})


func _on_avatar_removed(session: String) -> void:
	breach.end_early(session, "avatar_removed")   # до того, как сессия забыта: итогу нужна её дека
	charge.end_early(session, "avatar_removed")
	decrypt.end_early(session, "avatar_removed")
	_close_vaults_of(session)
	_portal_state.erase(session)
	if not _sessions.has(session):
		return
	_sessions.erase(session)
	_effect_logged.erase(session)
	_entered_at.erase(session)
	_exiting[session] = true
	_level_cbs.erase(session)
	_hunted.erase(session)
	_sync_hunt(session)  # игрок ушёл: охоты за сессией больше нет (Мосту сказать «false»)
	_write_node_state()
	for ice in _ices:
		if ice.brain != null:
			ice.brain.forget(session)


func _on_level_changed(old_level: int, new_level: int, value: float, session: String) -> void:
	event.emit({"kind": "level", "session": session, "from": old_level, "to": new_level, "value": value})
	# Мост (правило сигнала СБ, P3) читает session.world.trace_level: с уровня TRACE шлёт сигнал с номером терминала.
	if bridge != null and synced:
		_mark_trace_level(session, new_level, value, _sessions[session].active_effects(_now) if _sessions.has(session) else [])
	if is_graph_node() and old_level < TraceMeter.Level.TRACE and new_level >= TraceMeter.Level.TRACE:
		raise_alert(float(settings["alert_per_trace"]))
	# trace 100: ICE хватает. С Black ICE в узле это делает охота (она идёт с уровня TRACE); без него Soft ICE выбрасывает.
	if new_level == TraceMeter.Level.FLATLINE and not has_black_ice():
		_end(session, ExitLogic.REASON_EJECTED, "ice_eject")


func _on_ice_ejected(session: String, reason: String) -> void:
	if reason == "black_caught":
		# Поймали в окне возврата после обрыва — в карточке мастеру «обрыв до флэтлайна».
		if net.peer_of(session) == -1:
			_flat_disconnect[session] = true
		_end(session, ExitLogic.REASON_FLATLINE, "flatline")
	elif reason == "flatline" and has_black_ice():
		return  # Soft ICE при trace 100 в узле с Black ICE не выбрасывает: добивает охота
	else:
		_end(session, ExitLogic.REASON_EJECTED, "ice_eject")


func _end(session: String, exit_reason: String, kind: String) -> void:
	if not net.has_avatar(session):
		return
	if is_graph_node():
		raise_alert(float(settings["alert_per_eject"]))
		if kind == "ice_eject" and bridge == null and not is_tutorial():
			lock_for(float(settings["lockdown_sec"]))  # с Мостом локдаун выставляет он (run.finish soft_ice)
	event.emit({"kind": kind, "session": session})
	net.end_session(session, exit_reason)


func _on_leave_requested(session: String) -> void:
	if not _sessions.has(session):
		return
	var avatar := net.get_avatar(session)
	if avatar == null or not NodeLayout.on_exit_pad(avatar.position):
		return
	net.end_session(session, ExitLogic.REASON_CLEAN)


## Просьба начать взлом: отвечает только узел, где игрок (в графе обработчик подключён у каждого узла).
func _on_breach_open(session: String, vault: String, ids: Array) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	breach.request_open(session, vault, ids)


## Привязка телепорта к площадке у хранилища узла (см. NodeLayout.snap_to_vault_pad).
func snap_teleport(to: Vector3) -> Dictionary:
	return NodeLayout.snap_to_vault_pad(to, _slot_pos.values())


## Просьба зарядить защитного демона: отвечает только узел, где игрок (в графе обработчик подключён у каждого узла).
func _on_charge_requested(session: String, daemon_id: String) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	charge.request_start(session, daemon_id)


## Просьба расшифровать шард из ГРУЗа (К7): отвечает только узел, где игрок.
func _on_decrypt_requested(session: String, item: String) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	decrypt.request_start(session, item)


func _on_daemon_requested(session: String, daemon_id: String) -> void:
	var ds: DaemonSession = _sessions.get(session)
	if ds == null:
		return
	var before: Dictionary = cd_entry(ds, daemon_id, _now)
	log_line("daemon.use", {"phase": "request", "session": session, "daemon": daemon_id, "st": before["st"]})
	var res := daemons.apply(ds, daemon_id, {}, _now)
	var reply := {"kind": WorldMsg.EV_DAEMON, "daemon": daemon_id, "ok": bool(res.get("ok", false))}
	if not reply["ok"]:
		reply["error"] = str(res.get("error", ""))
		if res.has("reason"):
			reply["reason"] = str(res["reason"])
		log_line("daemon.use", {"phase": "denied", "session": session, "daemon": daemon_id, "error": reply["error"], "reason": reply.get("reason", "")})
	else:
		var def := daemons.get_def(daemon_id)
		var left := ds.active_left(def.effect, _now) if def != null else 0.0
		if left > 0.0:
			log_line("daemon.use", {"phase": "start", "session": session, "daemon": daemon_id, "effect": def.effect, "left": snappedf(left, 0.1)})
			if not _effect_logged.has(session):
				_effect_logged[session] = {}
			_effect_logged[session][daemon_id] = true
		else:
			log_line("daemon.use", {"phase": "ok", "session": session, "daemon": daemon_id, "effect": def.effect if def != null else ""})
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, reply))
	event.emit({"kind": "daemon", "session": session, "daemon": daemon_id, "ok": reply["ok"]})


## Строка журнала сервера узла: `событие ключ=значение` (формат MbLog, как у клиента); токенов в полях нет — только сессия, демон, числа.
static func log_line(event_name: String, fields: Dictionary) -> void:
	print("[gray-node] ", MbLog.format(event_name, fields))


## Конец действия эффекта в журнал: раньше записанный start, а демон в снимке уже не active. Вызывает _broadcast_state на каждом снимке.
func _log_effect_ends(session: String, cd: Array) -> void:
	var logged: Dictionary = _effect_logged.get(session, {})
	if logged.is_empty():
		return
	for e in cd:
		var id := str(e["id"])
		if logged.has(id) and str(e.get("st", "")) != "active":
			logged.erase(id)
			log_line("daemon.use", {"phase": "end", "session": session, "daemon": id})
	if logged.is_empty():
		_effect_logged.erase(session)


## Может ли игрок взять объект: он в этом узле, объект — слот этого узла и достаточно близко.
func can_grab(session: String, object_id: String) -> bool:
	var avatar := net.get_avatar(session)
	if avatar == null or net.node_of(session) != node_id or not _slot_pos.has(object_id):
		return false
	if vault_state(object_id, session) != VAULT_OPEN:
		return false
	return NodeLayout.flat_distance(avatar.position, net.object_position(object_id)) <= NodeLayout.GRAB_REACH


## Шард взят: игровая часть уже сделана (NetServer), в Мосте он переходит из узла в деку.
func _on_object_taken(object_id: String, session: String) -> void:
	if not _slot_pos.has(object_id):
		return
	_taken_by[session] = _taken_by.get(session, []) + [object_id]
	_vault_open.erase(object_id)   # взят: открытость кончилась вместе с шардом
	_vault_open_until.erase(object_id)
	event.emit({"kind": "shard_taken", "session": session, "id": object_id})
	var item: String = _shard_items.get(object_id, "")
	if bridge == null or item.is_empty():
		return
	_takes_inflight[session] = int(_takes_inflight.get(session, 0)) + 1
	var r: Dictionary = {}
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		r = await bridge.op_take_from_node(session, node_id, item)
		if not is_transient(r) or not is_inside_tree():
			break
		await get_tree().create_timer(FINISH_RETRY_SEC).timeout
	_takes_inflight[session] = int(_takes_inflight[session]) - 1
	if r.get("ok", false):
		print("[gray-node] take ", item, " ok (", session, ")")
		_load_deck(session)   # шард теперь в деке игрока: груз изменился
	else:
		push_warning("[gray-node] take %s: %s" % [item, BridgeApi.err_code(r)])


func _on_exit_event(ev: Dictionary) -> void:
	_portal_state.erase(ev["session"])
	# Граф: сигнал приходит всем узлам, забег закрывает тот, чей игрок это был (метка _exiting из _on_avatar_removed).
	if not _exiting.erase(ev["session"]) and is_graph_node():
		return
	event.emit({"kind": "exit", "session": ev["session"], "reason": ev["reason"]})
	_finishing[ev["session"]] = true
	if ev["reason"] == ExitLogic.REASON_FLATLINE:
		ev = ev.duplicate()
		ev["disconnect"] = bool(_flat_disconnect.get(ev["session"], false))
		_flat_disconnect.erase(ev["session"])
	_finish_in_bridge(ev)


## Исход забега по причине выхода (раздел 6.5 протокола и таблица исходов в netrun.md).
static func outcome_plan(ev: Dictionary) -> Dictionary:
	var reason: String = ev["reason"]
	match reason:
		ExitLogic.REASON_CLEAN:
			return {"outcome": "clean", "disconnect": false, "loot": "phone", "daemon": "phone"}
		ExitLogic.REASON_EJECTED:
			return {"outcome": "soft_ice", "disconnect": false, "loot": "node", "daemon": "phone"}
		ExitLogic.REASON_FLATLINE:
			return {"outcome": "black_ice", "disconnect": bool(ev.get("disconnect", false)), "loot": "node", "daemon": "node"}
	var daemon := "burned" if ev.get("deck_burned", false) else "phone"
	return {"outcome": "emergency", "disconnect": reason == ExitLogic.REASON_CONNECTION_LOST, "loot": "node", "daemon": daemon}


## Ошибки связи (Мост недоступен, обрыв, таймаут): запрос повторяют с тем же rid; всё остальное — окончательный ответ.
static func is_transient(resp: Dictionary) -> bool:
	return BridgeApi.err_code(resp) in ["unavailable", "timeout", "disconnected", "internal"]


## Уровень trace в session.data.world (trace_level — число TraceMeter.Level, trace — значение, effects — активные GHOST/TIMESKEW/BLACKOUT): Мост по нему решает про сигнал СБ.
## Остальные поля world сохраняются; повтор при version_conflict и обрыве, не вышло окончательно — без записи (уровень не критичен для хода).
func _mark_trace_level(session: String, level: int, value: float, effects: Array) -> void:
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			w["trace_level"] = level
			w["trace"] = int(value)
			w["effects"] = effects
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				return
			g = r
		if not is_transient(g) and BridgeApi.err_code(g) != "version_conflict":
			push_warning("[gray-node] trace_level %s: %s" % [session, BridgeApi.err_code(g)])
			return
		if not is_inside_tree():
			return


## Охота Black ICE в session.data.world.hunt: Мост по true шлёт быстрое событие ice.hunt, конец охоты событием не является.
## Пишем смену, а не каждый тик: нужное значение берётся из _hunted, подтверждённое Мостом — из _hunt_written. Писатель один на
## сессию: пока он ждёт Мост, смена охоты только меняет _hunted, а он по возвращении видит свежее значение (true и сразу false
## не обгоняют друг друга и очередь запросов не растёт). Мост недоступен — HUNT_ATTEMPTS попыток и отказ без записи: охота не
## критична для хода, а следующая смена охоты запишется заново.
func _sync_hunt(session: String) -> void:
	if bridge == null or not synced or _hunt_writing.has(session):
		return
	_hunt_writing[session] = true
	while bool(_hunted.get(session, false)) != bool(_hunt_written.get(session, false)):
		var want := bool(_hunted.get(session, false))
		if not await _put_hunt(session, want):
			break
		_hunt_written[session] = want
	_hunt_writing.erase(session)
	if not _sessions.has(session):
		_hunt_written.erase(session)  # игрока в узле нет: помнить нечего


## Один раз записать world.hunt (чтение-правка-запись, остальные поля world сохраняются). Повтор при version_conflict и обрыве
## связи, но не больше HUNT_ATTEMPTS. false — не вышло.
func _put_hunt(session: String, hunt: bool) -> bool:
	for attempt in HUNT_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			w["hunt"] = hunt
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				return true
			g = r
		var code := BridgeApi.err_code(g)
		if is_transient(g):
			if not is_inside_tree():
				return false
			await get_tree().create_timer(hunt_retry_sec).timeout
		elif code != "version_conflict":
			push_warning("[gray-node] hunt %s: %s" % [session, code])
			return false
	push_warning("[gray-node] hunt %s: не записано за %d попыток" % [session, HUNT_ATTEMPTS])
	return false


## Слить поля в session.data.world, не трогая остальные (trace_level, effects, finish). Повтор при version_conflict.
func _merge_world(session: String, fields: Dictionary) -> void:
	for attempt in 3:
		@warning_ignore("redundant_await")
		var g: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
		if not g.get("ok", false):
			return
		var cur: Dictionary = g["doc"]
		var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
		var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
		w.merge(fields, true)
		data["world"] = w
		@warning_ignore("redundant_await")
		var r: Dictionary = await bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
		if r.get("ok", false) or BridgeApi.err_code(r) != "version_conflict":
			return


## Пометка в session.data.world: что сервер мира закрывает эту сессию (finish, disconnect). Остальные поля world сохраняются.
## Повтор при version_conflict и обрыве связи; не вышло окончательно (документа нет, отказ) — продолжаем без пометки.
func _mark_finish(session: String, finish: String, disconnect: bool) -> void:
	if bridge == null:
		return
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		var g: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
		if g.get("ok", false):
			var cur: Dictionary = g["doc"]
			var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
			var w: Dictionary = (data.get("world", {}) as Dictionary).duplicate(true) if data.get("world") is Dictionary else {}
			w["finish"] = finish
			w["disconnect"] = disconnect
			data["world"] = w
			@warning_ignore("redundant_await")
			var r: Dictionary = await bridge.put_doc(BridgeApi.T_SESSION, session, int(cur["ver"]), data)
			if r.get("ok", false):
				return
			g = r
		if not is_transient(g) and BridgeApi.err_code(g) != "version_conflict":
			push_warning("[gray-node] пометка finish %s: %s" % [session, BridgeApi.err_code(g)])
			return
		if not is_inside_tree():
			return
		await get_tree().create_timer(FINISH_RETRY_SEC if is_transient(g) else 0.05).timeout
	push_warning("[gray-node] пометка finish %s не записана" % session)


## «Ждём мастера» перед флэтлайном. Возвращает "approve" (применять), "deny" (пощадить) или "" (узел закрывается).
## Мост сам ведёт срок и решение по таймауту; нам остаётся спрашивать раз в GATE_POLL_SEC, пока он отвечает wait.
## Сбой связи или отказ Моста решения не заменяют: опрос продолжается, исход сами не назначаем (run.finish без Моста
## всё равно не пройдёт). Дольше срока await_timeout_s + запас — запись в журнал и дальше те же опросы.
func _await_master_flatline(session: String) -> String:
	var announced := false
	var summary := "ФЛЭТЛАЙН: %s" % str(_callsign_of(session))
	var started := Time.get_ticks_msec()
	var limit_sec := await _gate_limit_sec()
	var warned_at := 0.0
	var failures := 0
	while is_inside_tree():
		@warning_ignore("redundant_await")
		var r: Dictionary = await bridge.master_gate("flatline", session, node_id, summary)
		if not r.get("ok", false):
			failures += 1
			if failures == 1 or failures % 60 == 0:
				push_warning("[gray-node] master.gate flatline %s: %s (опрос продолжается)" % [session, BridgeApi.err_code(r)])
		else:
			failures = 0
			var mode := str(r.get("mode", "auto"))
			if mode != "wait":
				var decision := str(r.get("decision", "approve")) if r.get("decision") != null else "approve"
				print("[gray-node] flatline ", session, ": ", mode, " ", decision)
				event.emit({"kind": "flatline_gate", "session": session, "mode": mode, "decision": decision})
				return decision
			if not announced:
				announced = true
				print("[gray-node] flatline ", session, ": ждём мастера")
				event.emit({"kind": "waiting_master", "session": session})
		var waited := (Time.get_ticks_msec() - started) / 1000.0
		if waited >= limit_sec + warned_at:
			warned_at += limit_sec
			push_warning("[gray-node] flatline %s: ждём решения уже %d с (срок %d с) — Мост должен решить по таймауту, опрос продолжается" % [session, int(waited), int(limit_sec)])
			event.emit({"kind": "gate_overdue", "session": session, "waited": waited})
		if not is_inside_tree():
			break
		await get_tree().create_timer(GATE_POLL_SEC).timeout
	return ""


## Срок «ждём мастера» из настроек Моста (settings/global.await_timeout_s) плюс запас; нет связи — по умолчанию.
func _gate_limit_sec() -> float:
	var timeout := GATE_DEFAULT_TIMEOUT_SEC
	@warning_ignore("redundant_await")
	var g: Dictionary = await bridge.get_doc("settings", "global")
	if g.get("ok", false):
		var t: Variant = ((g["doc"] as Dictionary).get("data", {}) as Dictionary).get("await_timeout_s")
		if t is int or t is float:
			timeout = maxf(float(t), 1.0)
	return timeout + GATE_GRACE_SEC


func _callsign_of(session: String) -> String:
	if bridge == null:
		return session
	var d: Variant = bridge.get("docs")
	if d is Dictionary:
		var s: Dictionary = ((d as Dictionary).get(BridgeApi.T_SESSION, {}) as Dictionary).get(session, {})
		var cs := str((s.get("data", {}) as Dictionary).get("callsign", ""))
		if cs != "":
			return cs
	return session


func _finish_in_bridge(ev: Dictionary) -> void:
	if bridge == null:
		return
	var session: String = ev["session"]
	while int(_takes_inflight.get(session, 0)) > 0:
		await get_tree().process_frame
	if ev["reason"] == ExitLogic.REASON_FLATLINE:
		# Пометка в Мосте ДО ожидания: рестарт сервера мира посреди него продолжит этот же флэтлайн (recover).
		await _mark_finish(session, "flatline", bool(ev.get("disconnect", false)))
		var verdict := await _await_master_flatline(session)
		if verdict == "":
			return  # узел закрывается: продолжит следующий процесс по пометке
		if verdict == "deny":
			ev = ev.duplicate()
			ev["reason"] = ExitLogic.REASON_EJECTED  # мастер пощадил до применения: как Soft ICE, без блокировки
			ev["disconnect"] = false
	var plan := outcome_plan(ev)
	# Дека могла измениться между чтением и вызовом (пришёл предмет по op.give_item, протокол 6.5/6.7): Мост отвечает bad_request «не упомянут
	# в moves» и не записывает rid — перечитываем деку, пересобираем moves и шлём тот же rid. Это не новое намерение.
	var r: Dictionary = {}
	for round_no in MOVES_ATTEMPTS:
		var moves := await _collect_moves(session, plan)
		for attempt in FINISH_ATTEMPTS:
			@warning_ignore("redundant_await")
			r = await bridge.run_finish(session, plan["outcome"], node_id, plan["disconnect"], moves)
			if not is_transient(r) or not is_inside_tree():
				break
			await get_tree().create_timer(FINISH_RETRY_SEC).timeout
		if not is_moves_stale(r) or not is_inside_tree():
			break
	print("[gray-node] run.finish ", session, " ", plan["outcome"], ": ", "ok" if r.get("ok", false) else BridgeApi.err_code(r))
	if r.get("ok", false):
		_finishing.erase(session)  # сессия закрыта в Мосте: terminal.auth её уже не отдаст
	event.emit({"kind": "finished", "session": session, "outcome": plan["outcome"], "ok": r.get("ok", false)})


## moves исхода по свежему чтению деки и документа сессии. Деление на рабочих и груз — по `session.loaded` (как у Моста); документ сессии
## не получен — запасное правило по origin.
func _collect_moves(session: String, plan: Dictionary) -> Array:
	var listed: Dictionary = {}
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		listed = await bridge.list_docs(BridgeApi.T_ITEM)
		if listed.get("ok", false) or not is_transient(listed) or not is_inside_tree():
			break
		await get_tree().create_timer(FINISH_RETRY_SEC).timeout
	var sdata: Dictionary = {}
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		var sr: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
		if sr.get("ok", false):
			sdata = (sr["doc"] as Dictionary).get("data", {})
			break
		if not is_transient(sr) or not is_inside_tree():
			break
		await get_tree().create_timer(FINISH_RETRY_SEC).timeout
	return finish_moves(listed.get("docs", []), session, sdata, plan)


## Ответ Моста «в деке предмет, которого нет в moves» (протокол 6.5): деку надо перечитать и повторить тем же rid.
static func is_moves_stale(resp: Dictionary) -> bool:
	return BridgeApi.err_code(resp) == "bad_request" and str((resp.get("err", {}) as Dictionary).get("msg", "")).contains("не упомянут в moves")


# ---------------------------------------------------------------- граф узлов (W1)

func portals() -> Array:
	return _portals


func slot_ids() -> Array:
	return _slot_pos.keys()


## Вид хранилища слота для сессии: empty — шарда нет (вынесен, ждёт пополнения); closed — шард внутри, взять нельзя;
## open — можно взять. Пока флаг `vault_requires_open` выключен (по умолчанию), лежащий шард открыт всем; К3 включает флаг, и
## хранилище открывается только взломом (open_vault) и только для сессии, которая его взломала.
func vault_state(slot: String, session: String = "") -> String:
	if net.holder_of(slot) != "":
		return VAULT_EMPTY
	if vault_requires_open() and not (session != "" and _vault_open.get(slot) == session):
		return VAULT_CLOSED
	return VAULT_OPEN


## Нужно ли открывать хранилище взломом, чтобы взять шард (settings.vault_requires_open). true / false — как задано графом; "auto" (по умолчанию) —
## включено у узла графа с Мостом (там ценности настоящие); одиночный серый узел, учебный узел и стенды без Моста берут шард, как раньше.
func vault_requires_open() -> bool:
	var v: Variant = settings.get("vault_requires_open", false)
	if v is bool:
		return v
	return str(v) == "auto" and bridge != null and is_graph_node() and not is_tutorial()


## Тир сетки взлома: тир узла графа; у одиночного узла (тира нет) — BASE.
func breach_tier() -> String:
	return tier() if tier() in NodeGraph.TIERS else "BASE"


## Хранилище слота открыто для сессии (взлом удался): взять шард может только она. sec > 0 — на столько секунд (vault_open_sec), 0 — без срока.
## Шлёт обновление слотов всем игрокам узла.
func open_vault(slot: String, session: String, sec: float = 0.0) -> void:
	if not _slot_pos.has(slot):
		return
	_vault_open[slot] = session
	if sec > 0.0:
		_vault_open_until[slot] = _now + sec
	else:
		_vault_open_until.erase(slot)
	_push_shards()


## Хранилище закрылось снова (срок vault_open_sec вышел, шард взят или слот опустел).
func close_vault(slot: String) -> void:
	_vault_open_until.erase(slot)
	if _vault_open.erase(slot):
		_push_shards()


## Закрыть всё, что было открыто для сессии (игрок ушёл из узла или кончил забег).
func _close_vaults_of(session: String) -> void:
	for slot in _vault_open.keys():
		if _vault_open[slot] == session:
			close_vault(slot)


func _expire_vaults() -> void:
	if _vault_open_until.is_empty():
		return
	for slot in _vault_open_until.keys():
		if _now >= float(_vault_open_until[slot]):
			close_vault(slot)
			event.emit({"kind": "vault_closed", "id": slot})


## Слот, в котором лежит предмет Моста item ("" — ни в одном).
func slot_of_item(item: String) -> String:
	for slot in _shard_items:
		if _shard_items[slot] == item:
			return slot
	return ""


## Сколько секунд слоту ждать пополнения (0 — не ждёт).
func refill_left(slot: String) -> int:
	return ceili(maxf(float(_refill_at.get(slot, _now)) - _now, 0.0)) if _refill_at.has(slot) else 0


## Доступ сессии к хранилищу для панели взлома: access — empty (ждёт пополнения, left — секунд) | open (можно брать) | busy (взламывает другой) |
## cooldown (узел остывает для неё, left — секунд) | ok (можно начинать).
func vault_access(slot: String, session: String) -> Dictionary:
	if net.holder_of(slot) != "":
		return {"access": "empty", "left": refill_left(slot)}
	if vault_state(slot, session) == VAULT_OPEN:
		return {"access": "open"}
	if breach != null and breach.is_busy(slot, session):
		return {"access": "busy"}
	var ds: DaemonSession = _sessions.get(session)
	if ds != null and not is_tutorial():
		var left := breach.cooldown_left(ds)
		if left > 0.0:
			return {"access": "cooldown", "left": ceili(left)}
	return {"access": "ok"}


## Зашифрован ли шард документа: берётся `shard.encrypted` Моста (`decryptAction && !decrypted`); у документа без него — `!decrypted`.
static func shard_encrypted(shard: Dictionary) -> bool:
	if shard.has("encrypted"):
		return bool(shard["encrypted"])
	return not bool(shard.get("decrypted", false))


## Признаки шарда из документа предмета Моста: тир 1–3 и зашифрован ли.
static func shard_meta(item_data: Dictionary) -> Dictionary:
	var sh: Variant = item_data.get("shard")
	var shard: Dictionary = sh if sh is Dictionary else {}
	return {"tier": clampi(int(shard.get("tier", 1)), 1, 3), "enc": shard_encrypted(shard)}


## Признаки предмета в хранилище для клиента: {kind: shard | daemon, tier, enc, dead?}. Шард — как [method shard_meta]; демон не шифруется
## (enc всегда false), а демон мёртвой деки (`origin: phone:*`: дека погибшего нетраннера осталась в узле) помечен dead — клиент ставит
## рядом модель мёртвой деки (К8).
static func vault_meta(item_data: Dictionary) -> Dictionary:
	if item_data.get("kind") == "DAEMON":
		var dm: Variant = item_data.get("daemon")
		var daemon: Dictionary = dm if dm is Dictionary else {}
		var meta := {"kind": "daemon", "tier": clampi(int(daemon.get("tier", 1)), 1, 3), "enc": false}
		if str(item_data.get("origin", "")).begins_with("phone:"):
			meta["dead"] = true
		return meta
	var out := shard_meta(item_data)
	out["kind"] = "shard"
	return out


## Мёртвые деки в узле для клиента: [[x, z]] рядом со слотами, где лежит демон мёртвой деки (на 0,8 м к центру комнаты от хранилища).
func dead_decks() -> Array:
	var out: Array = []
	for id in _slot_pos:
		var meta: Dictionary = _item_meta.get(_shard_items.get(id, ""), {})
		if bool(meta.get("dead", false)):
			var p: Vector3 = _slot_pos[id]
			var to_center := Vector2(-p.x, -p.z).normalized() * 0.8
			out.append([p.x + to_center.x, p.z + to_center.y])
	return out


## Слоты шардов для клиента: [{id, p, ready, vault, tier?, enc?, kind?, dead?}] для сессии. ready — предмет лежит; vault — empty | closed | open
## (vault_state); tier, enc и kind — признаки лежащего предмета (из Моста; учебный узел и работа без Моста их не знают).
func shard_view(session: String = "") -> Array:
	var out: Array = []
	for id in _slot_pos:
		var p: Vector3 = _slot_pos[id]
		var st := vault_state(id, session)
		var e := {"id": id, "p": [p.x, p.y, p.z], "ready": st != VAULT_EMPTY, "vault": st, "dead": false}
		e.merge(vault_access(id, session))
		var meta: Dictionary = _item_meta.get(_shard_items.get(id, ""), {})
		if st != VAULT_EMPTY and not meta.is_empty():
			e["tier"] = meta["tier"]
			e["enc"] = meta["enc"]
			e["kind"] = meta.get("kind", "shard")
			if meta.has("dead"):
				e["dead"] = true
		out.append(e)
	return out


## Сколько слотов шардов ждут пополнения.
func empty_slots() -> int:
	return _refill_at.size()


## Идёт ли запись охоты в Мост (тест ждёт, пока писатель закончит или сдастся).
func is_hunt_writing() -> bool:
	return not _hunt_writing.is_empty()


func is_hunted(session: String) -> bool:
	return bool(_hunted.get(session, false))


## Идёт ли в узле охота Black ICE (за кем-то из игроков узла).
func is_hunt_active() -> bool:
	for session in _hunted:
		if bool(_hunted[session]):
			return true
	return false


## Портал: игрок простоял в радиусе `portal_dwell_sec` (повтор отказа — не чаще `portal_deny_repeat_sec`).
func _check_portals() -> void:
	if _portals.is_empty():
		return
	var radius := float(settings["portal_radius"])
	var dwell := float(settings["portal_dwell_sec"])
	var repeat := float(settings["portal_deny_repeat_sec"])
	for session in _live_sessions():
		var p := net.get_avatar(session).position
		var near := ""
		for pt in _portals:
			if NodeLayout.flat_distance(p, pt["pos"]) <= radius:
				near = pt["to"]
				break
		if near.is_empty():
			_portal_state.erase(session)
			continue
		var st: Dictionary = _portal_state.get(session, {})
		if st.get("to", "") != near:
			st = {"to": near, "since": _now, "fired": -INF}
		if _now - float(st["since"]) >= dwell and _now - float(st["fired"]) >= repeat:
			st["fired"] = _now
			portal_requested.emit(session, near)
		_portal_state[session] = st


# --- тревога и локдаун узла

## Тревога узла растёт (0…1) и усиливает ICE: зрение и внимание выше на alert_boost при полной.
func raise_alert(amount: float) -> void:
	alert = minf(alert + amount, 1.0)
	_apply_alert()
	event.emit({"kind": "alert", "node": node_id, "value": alert})
	_write_node_state()  # тревога переживает рестарт сервера мира (node.data.world.alert + alert_at)


func _apply_alert() -> void:
	var k := 1.0 + alert * float(settings["alert_boost"])
	for ice in _ices:
		if ice.brain != null:
			ice.brain.alert_scale = k


## Остывание: за alert_cool_sec от полной до нуля, по общим часам.
func _tick_alert() -> void:
	var dt := _now - _alert_t
	_alert_t = _now
	if alert <= 0.0 or dt <= 0.0:
		return
	alert = maxf(alert - dt / maxf(float(settings["alert_cool_sec"]), 0.001), 0.0)
	_apply_alert()


## Закрыть узел сервером мира на sec секунд (когда Моста нет; с Мостом локдаун — lockdown_until узла).
func lock_for(sec: float) -> void:
	_local_lock_until = maxf(_local_lock_until, _now + sec)
	event.emit({"kind": "lockdown", "node": node_id, "sec": sec})


## Сколько секунд узел ещё закрыт (0 — открыт): большее из локдауна сервера мира и lockdown_until Моста (мс Unix).
func lockdown_left_sec() -> float:
	var left := maxf(_local_lock_until - _now, 0.0)
	var ms := lockdown_until - int(Time.get_unix_time_from_system() * 1000.0)
	if ms > 0:
		left = maxf(left, ms / 1000.0)
	return left


func is_locked_down() -> bool:
	return lockdown_left_sec() > 0.0


# --- шарды: вынос и пополнение

## Шард слота ушёл навсегда (на телефон или в другой узел) — слот пуст, пополнится через delay секунд (если в Мосте найдётся шард).
func _deplete(id: String, delay: float) -> void:
	net.lock_object(id)
	_shard_items.erase(id)
	_vault_open.erase(id)
	_vault_open_until.erase(id)
	_refill_at[id] = _now + delay
	event.emit({"kind": "shard_depleted", "id": id})


## Забег игрока закончился (GraphWorld зовёт все узлы): слоты, где он взял шард, пустеют — кроме случая, когда добыча осталась
## в этом же узле (выброс/флэтлайн/обрыв: предмет вернулся в узел, слот снова с шардом).
func settle_shards(session: String, end_node: String, loot: String) -> void:
	var ids: Array = _taken_by.get(session, [])
	_taken_by.erase(session)
	if ids.is_empty() or is_tutorial():  # заглушка учебного узла лежит снова — пополнять нечего
		return
	var delay := float((settings["shard_refill_sec"] as Dictionary).get(tier(), 0.0))
	for id in ids:
		if loot == "node" and end_node == node_id and not is_given_away(str(_shard_items.get(id, "")), session):
			continue   # добыча осталась в узле — кроме отданной другому игроку: она в узел не вернётся
		_deplete(id, delay)
	_push_shards()
	_write_node_state()


## Автопополнение стоит, пока узел в локдауне и пока в нём идёт охота Black ICE (docs/netrun.md, «Открытые вопросы», п. 2): сроки слотов
## не сбрасываются, слот оживает на ближайшем тике после конца локдауна/охоты. Сколько слотов — решает граф: сверх его числа шардов не будет.
func is_refill_paused() -> bool:
	return is_locked_down() or is_hunt_active()


func _tick_refill() -> void:
	if _refill_at.is_empty() or is_refill_paused():
		return
	for id in _refill_at.keys():
		if _now >= float(_refill_at[id]) and not _refill_busy.has(id):
			_refill(id)


## Пополнение слота: с Мостом нужен свободный шард `node:<узел>` (Мост выпускает шарды; сервер мира их не создаёт), без Моста
## слот просто оживает. Нет свободного — повтор через refill_retry_sec.
func _refill(id: String) -> void:
	_refill_busy[id] = true
	var item := ""
	if bridge != null:
		item = await _free_shard_item()
		if item.is_empty() or item in _shard_items.values():
			_refill_busy.erase(id)
			if _refill_at.has(id):
				_refill_at[id] = _now + float(settings["refill_retry_sec"])
			return
	_refill_busy.erase(id)
	if not _refill_at.has(id) or is_refill_paused():
		return  # пока шард искали в Мосте, узел закрылся или началась охота: слот остаётся пустым, повторит тик
	_refill_at.erase(id)
	if not item.is_empty():
		_shard_items[id] = item
		_given.erase(item)   # шард лежит в узле: прежняя отдача (A -> B -> узел) к нему больше не относится
	net.unlock_object(id)
	event.emit({"kind": "shard_refilled", "id": id, "item": item})
	_push_shards()
	_write_node_state()


## Свободный предмет узла в Мосте — шард или демон: owner node:<узел>, не привязанный к слоту. "" — нет. Демоны («мёртвая дека», наполнение
## мастера) — такие же свободные предметы, их достаёт EXTRACT_DAEMON (протокол, 6.9); порядок общий, по возрастанию id.
func _free_shard_item() -> String:
	if not synced or not bridge.is_ready():
		return ""
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_ITEM)
	if not r.get("ok", false):
		return ""
	var ids: Array[String] = []
	for d in r.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if (data.get("kind") == "SHARD" or data.get("kind") == "DAEMON") and data.get("owner") == "node:" + node_id \
				and not (str(d["id"]) in _shard_items.values()):
			ids.append(str(d["id"]))
			_item_meta[str(d["id"])] = vault_meta(data)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func _push_shards() -> void:
	for session in _live_sessions():   # вид хранилищ у каждого свой: «открыто для тебя»
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_SHARDS, "shards": shard_view(session)}))


# --- переход игрока между узлами: GraphWorld забирает сессию из одного узла и отдаёт другому

## Снять сессию с узла (уходит в тоннель/в другой узел): состояние (trace, дека, перезарядки) возвращается вызывающему целым.
func release_session(session: String) -> DaemonSession:
	var ds: DaemonSession = _sessions.get(session)
	if ds == null:
		return null
	breach.end_early(session, "transit")
	charge.end_early(session, "transit")
	decrypt.end_early(session, "transit")
	_close_vaults_of(session)
	var cb: Callable = _level_cbs.get(session, Callable())
	if cb.is_valid() and ds.trace.level_changed.is_connected(cb):
		ds.trace.level_changed.disconnect(cb)
	_level_cbs.erase(session)
	_sessions.erase(session)
	_effect_logged.erase(session)
	_entered_at.erase(session)
	_hunted.erase(session)
	_sync_hunt(session)  # сессия уходит в другой узел: охота этого узла за ней кончилась
	_portal_state.erase(session)
	net.set_under_hunt(session, false)
	for ice in _ices:
		if ice.brain != null:
			ice.brain.forget(session)
	_write_node_state()
	return ds


## Принять сессию с её состоянием: trace и дека те же объекты, что были в прошлом узле.
func adopt_session(session: String, ds: DaemonSession) -> void:
	_sessions[session] = ds
	_entered_at[session] = _now
	_connect_meter(session, ds.trace)
	print("[gray-node] ", session, " вошёл в ", node_id, " (переход)")
	_push_deck(session)
	if bridge != null and synced:
		# Мост читает world.node (где игрок сейчас) и trace_level/effects (сигнал СБ): после перехода пишем их для нового узла.
		_merge_world(session, {"connected": net.peer_of(session) != -1, "trace": int(ds.trace.value()), "node": node_id,
			"trace_level": ds.trace.level(), "effects": ds.active_effects(_now)})
		_write_node_state()

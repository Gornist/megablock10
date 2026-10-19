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
## Шкала тревоги узла (ice.md §4) и пороги уровней 1…4.
const ALARM_MAX := 100.0
const ALARM_LEVEL_AT := [25.0, 50.0, 75.0, 100.0]
## Прибавка к зрению ICE на тревоге 2+: «+1 клетка» ice.md §4 — клетка карты 2 м (Страж 3 клетки = 6 м), а дальности в коде — в клетках 1 м.
const ALARM_SIGHT_BONUS := 2.0
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
## Поверх ice_settings — только для Black ICE логова (дальность взгляда sight_range, tick…).
var black_ice_settings: Dictionary = {}
## Ожоги Black ICE за забег: сессия → число. Один словарь на весь мир (GraphWorld выдаёт его всем узлам): ожог не лечится и не сбрасывается
## переходом в другой узел (ice.md §6.1). Отдельный узел без мира — свой словарь.
var black_burns: Dictionary = {}
## Клетки 1 м с колоннами: одна на узел, её видят все ICE (колонна закрывает им взгляд).
var ice_grid: NodeGrid = NodeGrid.for_layout()
## Раскладка узла (data/layouts): сетка, хранилища, порталы, вход, выход, маршруты Стражей. Узел без поля layout и одиночный узел — legacy
## (те же значения, что константы NodeLayout). Задаётся в apply_def до start().
var layout: LayoutData = LayoutData.cached(LayoutData.LEGACY)

var _now := 0.0
var _state_acc := 0.0
var _avatar_acc := 0.0
var _step_count := 0
var _step_us_total := 0
var _step_us_max := 0
var _ices: Array[IceNode] = []
var _sessions: Dictionary = {}       # сессия -> DaemonSession (в нём trace)
var _effect_logged: Dictionary = {}  # сессия -> {id демона: true}: эффект, начало которого записано в журнал (конец — когда st перестал быть active)
## Шарды и хранилища узла — в ShardVaults (shard_vaults.gd). Приватные словари ниже — прежние имена-алиасы на его поля (тот же Dictionary:
## их читают и правят vault_breach.gd и тесты).
var shards: ShardVaults = ShardVaults.new(self)
var _shard_items: Dictionary:        # id объекта -> id предмета в Мосте
	get:
		return shards.items
var _vault_open: Dictionary:         # id слота -> сессия, для которой хранилище открыто взломом (K3)
	get:
		return shards.vault_open
var _slot_pos: Dictionary:           # id объекта (слот шарда узла) -> позиция
	get:
		return shards.slot_pos
var _taken_by: Dictionary:           # сессия -> [id слотов этого узла, которые она взяла]
	get:
		return shards.taken_by
var _refill_at: Dictionary:          # id пустого слота -> когда пробовать пополнить (время узла)
	get:
		return shards.refill_at
## Взлом хранилищ (К3): сетка, таймер, тапы, итог в Мост.
var breach: VaultBreach
var charge: ChargeBreach
var decrypt: DecryptBreach
var barrier: BarrierBreach
var _takes_inflight: Dictionary = {} # сессия -> число незавершённых op.take_from_node (в графе общий на все узлы)
var _entered_at: Dictionary = {}     # сессия -> время узла, когда она вошла (журнал ICE: «секунды от входа»)
var _portals: Array = []             # [{to, slot, pos}] порталы узла графа
var _portal_state: Dictionary = {}   # сессия -> {to, since, fired} — сколько стоит у портала
var _exiting: Dictionary = {}        # сессия -> true между «аватар убран» и событием выхода: её забег закрывает этот узел
var _level_cbs: Dictionary = {}      # сессия -> Callable, подключённый к trace.level_changed (при переходе переподключается)
var _alert_t: float:                 # время узла последнего шага остывания (тесты ставят напрямую)
	get:
		return alarm_state.alert_t
	set(v):
		alarm_state.alert_t = v
var _ready_done := false
## Сессии, чей исход уже уходит в Мост (в том числе восстановленный флэтлайн): второй исход и повторный вход не допускаем.
## Исход забега и охота Black ICE — в RunOutcome (run_outcome.gd). _finishing / _hunted / hunt_retry_sec ниже — прежние имена-алиасы
## на его поля (тот же Dictionary: их читают breach-классы и тесты).
var outcome: RunOutcome = RunOutcome.new(self)
var _finishing: Dictionary:          # сессия -> true: её исход уже уходит в Мост
	get:
		return outcome.finishing
var _hunted: Dictionary:             # сессия -> true, пока за ней идёт охота Black ICE
	get:
		return outcome.hunted
var hunt_retry_sec: float:           # пауза между попытками записи охоты (тест ставит поменьше)
	get:
		return outcome.hunt_retry_sec
	set(value):
		outcome.hunt_retry_sec = value
var _given: Dictionary = {}          # id предмета, отданного игроком другому (К5б) -> сессия, у которой он теперь ("" — ушёл на телефон); слот отданного шарда не вернуть на постамент
## Снимок Моста принят (после рестарта — активные сессии и шард восстановлены).
var synced := false
## Сессии, взятые из снимка Моста: ждали возврата игрока.
var recovered_sessions: Array[String] = []
## Сессии с недовершённым флэтлайном из прошлого процесса (пометка world.finish в Мосте).
var recovered_flatlines: Array[String] = []
## Конец локдауна узла (мс Unix, время Моста; 0 — нет) — из документа node.
var lockdown_until: int:
	get:
		return alarm_state.lockdown_until
	set(v):
		alarm_state.lockdown_until = v
var node_writes := 0
var _node_write_busy := false
var _node_write_again := false
## Тревога и локдаун узла — в NodeAlarm (node_alarm.gd); alarm, alarm_level, sensors_armed, lockdown_until — прежние имена-алиасы на его поля.
var alarm_state: NodeAlarm = NodeAlarm.new(self)
## Тревога узла 0…100 (ice.md §4; граф): растёт от присутствия нетраннера (за такт) и событий, остывает только в пустом узле.
var alarm: float:
	get:
		return alarm_state.alarm
	set(v):
		alarm_state.alarm = v
## Тревога 0…1 = alarm / 100 — прежнее поле для событий, Моста и клиента (контракт не менялся; новое поле — Т3b).
var alert: float:
	get:
		return alarm / ALARM_MAX
	set(v):
		alarm = clampf(v, 0.0, 1.0) * ALARM_MAX
## Уровень тревоги 0…4 (alarm_level_for) и эффекты: 1 — «спящие» датчики включены (флаг), 2 — зрение тактовых ICE +1 клетка,
## 3 — в NIGHTMARE просыпается Black ICE, 4 — через alert_lockdown_ticks тактов порталы закрыты на lockdown_sec.
var alarm_level: int:
	get:
		return alarm_state.alarm_level
	set(v):
		alarm_state.alarm_level = v
var sensors_armed: bool:
	get:
		return alarm_state.sensors_armed
	set(v):
		alarm_state.sensors_armed = v

## Тактовое время узла (режим realtime удалён, аудит 17.10): часы тактов, мозги Soft ICE на клетках, Black ICE логова.
var tick_clock: TickClock
var _tick_ices: Dictionary = {}      # IceNode -> TickIce (только Soft ICE тактового режима)
var devices: LayoutDevices = LayoutDevices.new(self)   # Маяки, Датчики, Барьеры раскладки (ice.md §5): состояние и правила — в layout_devices.gd
var _black_brain: TickBlackBrain     # Black ICE по тактам (раскладка с логовом); null — в узле нет Black ICE
var _no_lair_warned := false         # предупреждение «NIGHTMARE без логова» уже было
var _black_log: Dictionary = {}      # сессия → журнал Black ICE на момент флэтлайна (уйдёт в session.data.world.black_log)
var _intents: Dictionary = {}        # IceNode -> TickIce.intent() после последнего такта (рассылается 10 раз/с без пересчёта)
var _entered_tick: Dictionary = {}   # сессия -> номер такта узла, когда она вошла (скрыта первые entry_hidden_ticks тактов)
var _grace_spent: Dictionary = {}    # сессия -> true: ходила после входа, грейс прибытия (arrival_grace_ticks) кончился досрочно

## Тактовый режим: строка о такте в журнал сервера (то же печатается в stdout), как ice_logged.
signal tick_logged(line: String)


## Узел графа (W1): id, тир, число Soft ICE, шарды, порталы. Вызывается до start(); Black ICE ставится по тиру NIGHTMARE.
func apply_def(id: String, def: Dictionary, graph_settings: Dictionary, graph: NodeGraph) -> void:
	node_id = id
	node_def = def
	settings = graph_settings
	layout = _load_layout(str(def.get("layout", "")))
	ice_grid = layout.grid()
	_portals.clear()
	for i in (def.get("links", []) as Array).size():
		var to := str(def["links"][i])
		if i >= layout.portals.size() or layout.portals[i] == Vector3.INF:
			push_warning("[node] %s: у раскладки «%s» нет портала %d — связь с %s без портала" % [node_id, layout.name, i + 1, to])
			continue
		_portals.append({"to": to, "slot": i, "pos": layout.portals[i], "title": graph.title_of(to), "tier": graph.tier_of(to)})


## Раскладка узла по имени; нет файла или ошибка разбора — строка в журнал и legacy (узел остаётся играбельным).
func _load_layout(layout_name: String) -> LayoutData:
	var ld := LayoutData.cached(layout_name)
	if ld.error != "":
		push_warning("[node] %s: раскладка «%s» не загрузилась (%s), берём legacy" % [node_id, layout_name, ld.error])
		return LayoutData.cached(LayoutData.LEGACY)
	return ld


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
	barrier = BarrierBreach.new(self)
	daemons.load_dir()
	tick_clock = TickClock.new(float(settings["tick_window_sec"]), float(settings["tick_min_interval_sec"]))
	shards.build_slots()
	if manage_net_hooks:
		net.move_check = move_made
		net.grab_check = can_grab
		net.teleport_snap = func(_session: String, to: Vector3) -> Dictionary: return snap_teleport(to)
		net.spawn_of = func(_session: String) -> Vector3: return layout.spawn
		net.grid_of = func(_session: String) -> NodeGrid: return ice_grid
		net.hop_limit_of = func(_session: String, from: Vector2i) -> float: return hop_limit_at(from)
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
	net.barrier_requested.connect(_on_barrier_requested)
	# Клетки и отмена идут одним сообщением на все мини-игры; у игрока одновременно одна из них (заряд, расшифровка, барьер и взлом друг друга исключают).
	net.breach_tap_requested.connect(func(session: String, cell: Array) -> void:
		if charge.has_attempt(session):
			charge.request_tap(session, cell)
		elif decrypt.has_attempt(session):
			decrypt.request_tap(session, cell)
		elif barrier.has_attempt(session):
			barrier.request_tap(session, cell)
		else:
			breach.request_tap(session, cell))
	net.breach_cancel_requested.connect(func(session: String) -> void:
		if charge.has_attempt(session):
			charge.request_cancel(session)
		elif decrypt.has_attempt(session):
			decrypt.request_cancel(session)
		elif barrier.has_attempt(session):
			barrier.request_cancel(session)
		else:
			breach.request_cancel(session))
	net.teleported.connect(func(session: String, from: Vector3, to: Vector3) -> void:
		register_move(session)
		devices.sensors_hop(session, from, to)
		if _black_brain != null:
			_black_brain.black.on_hop(session, NodeGrid.cell_of(to))
		breach.end_early(session, "teleport")
		charge.end_early(session, "teleport")
		decrypt.end_early(session, "teleport")
		barrier.end_early(session, "teleport"))
	var soft := NodeLayout.ICE.size() if node_def.is_empty() else int(node_def.get("ice", 1))
	if not layout.is_legacy():
		# Такты: Стражи — по раскладке (маршрут в клетках с ожиданием и поворотом); столько, сколько просит узел, но не больше, чем в файле.
		for i in mini(soft, layout.sentries.size()):
			_add_layout_sentry(layout.sentries[i])
		devices.build(layout, tier())   # Маяки, Датчики, Барьеры раскладки
	else:
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


## Есть ли в узле Black ICE (раскладка с логовом и тир NIGHTMARE; Black ICE живёт только в логове).
func has_black_ice() -> bool:
	return _black_brain != null


## Поселить Black ICE узла в логове раскладки; повторный вызов ничего не добавляет. Раскладка без логова Black ICE не селит
## (режима «бродит по маршруту» нет, решение владельца 19.10): узел NIGHTMARE без логова — предупреждение и только Soft ICE.
func enable_black_ice() -> void:
	if has_black_ice():
		return
	if layout.lair.is_empty():
		if not _no_lair_warned:
			_no_lair_warned = true
			push_warning("[node] %s: NIGHTMARE без логова: Black ICE не будет" % node_id)
		return
	# Логово раскладки: Black ICE спит в нём и живёт по тактам (TickBlack).
	_add_ice(str(layout.lair["id"]), [NodeGrid.center(layout.lair["home"])], [], true)


## Страж раскладки (тактовый режим): sentry = {id, route: [{cell, wait, look}]} — маршрут как есть, без пересчёта точек в клетки.
func _add_layout_sentry(sentry: Dictionary) -> void:
	var route: Array = sentry["route"]
	var wps: Array = []
	for pt: Dictionary in route:
		wps.append(NodeGrid.center(pt["cell"]))
	_add_ice(str(sentry["id"]), wps, route)


## Soft ICE (Страж по тактам) или, при in_lair, Black ICE логова (TickBlackBrain вместо IceBrain).
func _add_ice(id: String, waypoints: Array, route: Array = [], in_lair: bool = false) -> void:
	var wps: Array[Vector3] = []
	for w in waypoints:
		wps.append(w)
	var ice := IceNode.new()
	ice.name = id
	ice.position = wps[0]
	ice.time_source = now
	var settings := ice_settings.duplicate(true)
	settings.merge(node_def.get("ice_settings", {}), true)  # узел может смягчить ICE (учебный)
	if in_lair:
		settings.merge(black_ice_settings, true)
		settings["black"] = true
	ice.setup(settings, wps, ice_grid)
	if in_lair:
		var lair_cells: Array[Vector2i] = []
		for c: Vector2i in layout.lair["cells"]:
			lair_cells.append(c)
		var tsettings: Dictionary = (black_ice_settings.get("tick", {}) as Dictionary).duplicate()
		var kind := str((node_def.get("black", {}) as Dictionary).get("kind", str(layout.lair.get("kind", "")))) if node_def.get("black") is Dictionary else str(layout.lair.get("kind", ""))
		if kind != "" and not TickBlack.KINDS.has(kind):
			push_warning("[node] %s: неизвестный вид Black ICE «%s», базовый" % [node_id, kind])
			kind = ""
		tsettings["kind"] = kind
		var tb := TickBlack.new(lair_cells, layout.lair["home"], ice_grid, tsettings, black_burns)
		_black_brain = TickBlackBrain.new(tb, settings)
		_black_brain.ejected.connect(func(s: String, r: String) -> void: ice.ejected.emit(s, r))
		ice.brain = _black_brain
	if not in_lair:
		var ti := TickIce.new(_tick_ice_settings(settings), route if not route.is_empty() else TickIce.route_from_points(wps), ice_grid)
		_tick_ices[ice] = ti
		ice.position = NodeGrid.center(ti.cell())
		ice.brain.position = ice.position
		_sync_brain_view(ice, ti)
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
	var tk := " tick=%d" % tick_clock.tick_no
	var line := "[ice] t=%.1f %s %s%s alert=%.2f d=%s %s%s" % [t, ice.name, what, aw, alert, d, session, tk]
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
	for session in outcome.hunt_written.keys():
		outcome._sync_hunt(session)  # охота прошлого процесса не продолжается: снять её отметку в Мосте
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
							outcome.hunt_written[str(d["id"])] = true  # отметка прошлого процесса: его охоты нет, apply_snapshot её снимет
			BridgeApi.T_ITEM:
				if data.get("kind") != "SHARD" and data.get("kind") != "DAEMON":
					continue
				var owner := str(data.get("owner", ""))
				if owner == "node:" + node_id:
					node_items.append(str(d["id"]))
					shards.item_meta[str(d["id"])] = vault_meta(data)
				elif owner.begins_with("deck:"):
					deck_docs.append(d)
	var held := held_items(deck_docs, active_data, node_id, node_def.is_empty())   # [{item, by}] добыча, которую игроки несут из этого узла
	if is_tutorial():
		node_items.clear()  # шард учебного узла — заглушка: предметов Моста к нему не привязываем
		held.clear()
	node_items.sort()
	alarm_state.restore(saved_world)
	shards.restore(node_items, held, active, saved_world)   # слоты: добыча игроков, свободные предметы узла, ожидающие пополнения
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
	print("[gray-node] снимок Моста (", node_id, "): активных сессий ", active.size(), ", шард ", ",".join(shards.items.values()) if not shards.items.is_empty() else "—", ", локдаун до ", lockdown_until)




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
			world["alert"] = snappedf(alert, 0.01)           # прежняя шкала 0…1 (читатели прошлой версии)
			world["alarm"] = snappedf(alarm, 1.0)            # Т3b: шкала 0–100 и уровень 0–4 рядом со старым полем
			world["alert_level"] = alarm_level
			world["slots_empty"] = shards.empty_slots()
			world["alert_at"] = int(Time.get_unix_time_from_system() * 1000.0)
			world["refill"] = shards.refill_deadlines()
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
		# IceNode не думает сам (netrunner_count = 0 — только rest()): ICE шагает по такту, см. _tick_step.
		ice.netrunner_count = 0
		ice.targets = targets
		ice.meters = meters
	_tick_step(meters)
	_update_hunts()
	breach.tick(delta)
	charge.tick(delta)
	decrypt.tick(delta)
	barrier.tick(delta)
	shards.expire_vaults()
	if is_graph_node():
		_check_portals()
		shards.tick_refill()
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


# --- тактовое время (docs/gamedesign/time-and-movement.md, 3)

## Запомнить ход нетраннера этого узла (телепорт, «ждать», взять, демон, начало панели, портал): до такта второй ход ему закрыт.
func register_move(session: String) -> void:
	if net.node_of(session) == node_id:
		tick_clock.register_move(session)


## Вход в узел: первые entry_hidden_ticks тактов нетраннер невидим для ICE (отсчёт — от номера такта узла в момент входа).
func _mark_entered_tick(session: String) -> void:
	_entered_tick[session] = tick_clock.tick_no
	_grace_spent.erase(session)


## Грейс прибытия (W3, правило «безопасный выход портала»): нетраннер, вошедший в узел и ещё не ходивший, неуязвим для ICE в тактах n после
## скрытых entry_hidden_ticks: n − вход ≤ entry_hidden_ticks + arrival_grace_ticks. ICE не заходит в его клетку и не берёт его, счётчик ≤ «?».
## Кончается досрочно, как только нетраннер сходил (его ход в окне перед тактом n снимает грейс со следующего такта): стоять вечно нельзя.
func _arrival_immune(session: String, n: int) -> bool:
	if _grace_spent.has(session):
		return false
	var since := n - int(_entered_tick.get(session, -1000000))
	var hidden := int(settings.get("entry_hidden_ticks", 2))
	return since >= 1 and since <= hidden + int(settings.get("arrival_grace_ticks", 2))


## Хук NetServer.move_check: нетраннер уже сходил в этом такте (Т4).
func move_made(session: String) -> bool:
	return tick_clock.moved(session)


## Настройки TickIce из настроек ICE узла: известные ему ключи как есть, дальность зрения — по тиру (settings.ice_sight_cells);
## в учебном узле — его sight_range (смягчение), конус — из sight_half_angle_deg.
func _tick_ice_settings(ice_cfg: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in TickIce.DEFAULTS:
		if ice_cfg.has(k):
			out[k] = ice_cfg[k]
	if not out.has("sight_cells"):
		if layout.has_sight and not layout.is_legacy():
			out["sight_cells"] = layout.sight_cells   # раскладка знает свою дальность (карта и Стражи подобраны вместе)
		elif is_tutorial() and ice_cfg.has("sight_range"):
			out["sight_cells"] = float(ice_cfg["sight_range"])
		else:
			var table: Variant = settings.get("ice_sight_cells", {})
			var t := tier() if not tier().is_empty() else "BASE"
			out["sight_cells"] = float((table as Dictionary).get(t, 6)) if table is Dictionary else 6.0
	if not out.has("half_angle_deg") and ice_cfg.has("sight_half_angle_deg"):
		out["half_angle_deg"] = float(ice_cfg["sight_half_angle_deg"])
	return out


## IceBrain тактового ICE не думает, но журнал, trace и тесты читают его position/facing: держим их по клетке TickIce.
func _sync_brain_view(ice: IceNode, ti: TickIce) -> void:
	ice.brain.position = NodeGrid.center(ti.cell())
	var d := ti.dir()
	ice.brain.facing = Vector3(d.x, 0.0, d.y).normalized() if d != Vector2i.ZERO else ice.brain.facing


## Состояние TickIce (0 Патруль, 1 Взгляд, 2 Проверка, 3 Поиск) в код IceBrain.State для старого клиента: Взгляд и Проверка — «подозрение».
static func tick_state_to_legacy(st: int) -> int:
	match st:
		TickIce.Mode.PATROL:
			return IceBrain.State.PATROL
		TickIce.Mode.GAZE, TickIce.Mode.CHECK:
			return IceBrain.State.SUSPICIOUS
	return IceBrain.State.SEARCH


static func tick_state_name(st: int) -> String:
	return ["PATROL", "GAZE", "CHECK", "SEARCH"][clampi(st, 0, 3)]


## Часы тактов: кто в узле, кто свободен (Т3), и на такте — шаг каждого ICE.
func _tick_step(meters: Dictionary) -> void:
	var live := _live_sessions()
	tick_clock.set_present(not live.is_empty(), _now)
	var free: Array = []
	for session in live:
		# Не свободен: оборвана связь (аватар ждёт возврата) или идёт панель взлома / заряда / расшифровки. В тоннеле сессия не «live».
		if net.peer_of(session) != -1 and not breach.has_attempt(session) and not charge.has_attempt(session) and not decrypt.has_attempt(session) and not barrier.has_attempt(session):
			free.append(session)
	tick_clock.set_free(free)
	var prev := tick_clock.last_tick_at
	if tick_clock.poll(_now):
		_run_tick(live, meters, _now - prev)


## Один такт узла: ходы уже применены; ICE делают шаг, считаются видимость, trace, события; Black ICE логова делает свой такт.
func _run_tick(live: Array, meters: Dictionary, dt_sec: float) -> void:
	var n := tick_clock.tick_no
	var line := "[tick] n=%d moves=%d by=%s" % [n, tick_clock.last_moves, tick_clock.last_by]
	print(line)
	tick_logged.emit(line)
	barrier.on_node_tick()   # удержание силового вскрытия барьера: такт засчитан
	_alarm_on_tick()   # тревога +alert_per_tick за такт, пока в узле нетраннер; отсчёт до закрытия порталов (уровень 4)
	var pos := {}
	var hidden := {}
	var immune := {}     # неуязвимые: грейс прибытия (скрытые тоже — сразу после скрытых тактов он продолжается)
	var hide_ticks := int(settings.get("entry_hidden_ticks", 2))
	for session in live:
		var avatar := net.get_avatar(session)
		if avatar == null:
			continue
		var ds: DaemonSession = _sessions[session]
		var h := ds.is_ghost(_now) or n - int(_entered_tick.get(session, -1000000)) <= hide_ticks
		pos[session] = avatar.position
		hidden[session] = h
		immune[session] = _arrival_immune(session, n)
	var captured := {}   # сессия -> ICE, который её взял
	for ice: IceNode in _tick_ices:
		var ti: TickIce = _tick_ices[ice]
		var evs := ti.tick(pos, hidden, immune)
		ice.position = NodeGrid.center(ti.cell())
		_sync_brain_view(ice, ti)
		for ev: Dictionary in evs:
			match ev["kind"]:
				"state":
					_log_ice(ice, _tick_target(ti, pos), "%s→%s" % [tick_state_name(int(ev["from"])), tick_state_name(int(ev["state"]))], float(ti.max_awareness()))
				"search_started":
					_log_ice(ice, _tick_target(ti, pos), "SEARCH_STARTED", float(ti.max_awareness()))
					# Поиск (ice.md §3–4): trace цели +10 один раз за Поиск и тревога узла +10 — вместо прежних +8/с «на виду»
					var searched := _tick_target(ti, pos)
					if searched != "":
						add_trace_event(searched, "search")
					alarm_event("search")
				"capture":
					if not captured.has(ev["session"]):
						captured[ev["session"]] = ice
	# Маяки раскладки: поворот, зрение только фокусом; «Поиск» маяка — как Поиск Стража (trace +10 цели, тревога узла +10).
	var suspicious := {}
	for s in meters:
		suspicious[s] = (meters[s] as TraceMeter).level() >= TraceMeter.Level.SUSPICIOUS
	devices.beacons_tick(pos, hidden, immune, suspicious)
	devices.sensors_tick(pos, hidden, immune)
	for session in captured:
		if net.has_avatar(session):
			(captured[session] as IceNode).ejected.emit(session, "caught")
	_step_tick_black(pos, hidden, immune, meters)
	for s: Variant in tick_clock.last_moved:
		_grace_spent[s] = true   # ходила: грейс кончится со следующего такта (в этом ICE уже отходил по правилу)
	# Следующий такт: кто будет неуязвим (по позиции сейчас) — по ним intent() строит шаг с обходом, стрелка не врёт.
	var next_immune := {}
	for session in pos:
		if _arrival_immune(session, n + 1):
			next_immune[session] = pos[session]
	for ice: IceNode in _tick_ices:
		(_tick_ices[ice] as TickIce).expect_immune(next_immune)
		_intents[ice] = (_tick_ices[ice] as TickIce).intent()


## Black ICE логова: один такт TickBlack. Скрытые (Призрак, входные такты) — пинг мимо; пробуждение, пинги, захваты — в журнал узла;
## флэтлайн откладывает журнал (_black_log) для session.data.world.black_log.
func _step_tick_black(pos: Dictionary, hidden: Dictionary, immune: Dictionary, meters: Dictionary) -> void:
	if _black_brain == null:
		return
	var targets := {}
	var traces := {}
	for s in pos:
		targets[s] = NodeGrid.cell_of(pos[s])
		if meters.has(s):
			traces[s] = (meters[s] as TraceMeter).value()
	var flat := ""
	var ctx := {"targets": targets, "hidden": hidden, "immune": immune, "traces": traces, "alarm_level": alarm_level}
	var events := _black_brain.tick_step(ctx)
	for ice in _ices:
		if ice.brain == _black_brain:
			ice.position = _black_brain.position   # рассылка состояния («p») берёт позицию IceNode
	for ev: Dictionary in events:
		var kind := str(ev["kind"])
		print("[black] %s %s" % [kind, str(ev)])
		if kind == "flatline":
			_black_log[str(ev["session"])] = ev["journal"]
			flat = str(ev["session"])
		elif kind == "burn_charge" or kind == "strip_charge":
			_strip_charge(str(ev["session"]))   # Гончая жжёт за такт захвата, Ворон сносит на первом такте
		elif kind == "strip_decrypt":
			event.emit({"kind": "black_strip_decrypt", "session": str(ev["session"])})   # Лич: снятие «расшифрован» делает Мост по этому событию (пара)
		elif kind in ["wake", "hunt", "lost", "capture", "feel"]:
			var e := ev.duplicate()
			e["kind"] = "black_" + kind
			event.emit(e)
	if flat != "":
		# Выброс — после записи журнала: цепочка ejected → _end → _finish_in_bridge синхронна и сразу читает _black_log.
		_black_brain.ejected.emit(flat, "black_caught")


## Black ICE сжигает заряд одного демона деки сессии (Гончая — каждый ожог, Ворон — первый такт захвата). Нет заряженных — ничего.
func _strip_charge(session: String) -> void:
	if not _sessions.has(session):
		return
	var ds: DaemonSession = _sessions[session]
	var ids := ds.charged_ids()
	if ids.is_empty():
		return
	ds.set_charged(str(ids[0]), false)
	event.emit({"kind": "black_strip_charge", "session": session, "daemon": str(ids[0])})


## Мастер будит Black ICE узла (ice.md §6.1: «мастер» — одна из причин пробуждения).
func wake_black_ice() -> void:
	if _black_brain != null:
		_black_brain.black.wake_by_master()


## Black ICE логова по тактам (для тестов, сценариев и панели мастера); null — узел без логова.
func black_ice() -> TickBlack:
	return _black_brain.black if _black_brain != null else null


## Сессия с наибольшим счётчиком у этого ICE (для журнала); пусто — никого.
func _tick_target(ti: TickIce, pos: Dictionary) -> String:
	var best := ""
	var best_aw := -1
	for session in pos:
		var a := ti.awareness_of(session)
		if a > best_aw:
			best_aw = a
			best = session
	return best


## Охота Black ICE → флаг «под охотой» у NetServer (аварийный выход сожжёт деку). Каждый тик: выход не ждёт 0,1 с.
func _update_hunts() -> void:
	outcome._update_hunts()


## Trace во времени (ice.md §3): прежний спад decay_per_sec (по умолчанию 0 — пассивного спада нет) и дрейф узла графа — +1 за
## trace_drift_sec[тир] секунд, в хабе −1 за hub_trace_decay_sec (дрейфа нет). JITTER замораживает оба (TraceMeter).
func _tick_traces() -> void:
	var rate := trace_drift_rate()
	for session in _sessions.keys():
		if net.node_of(session) != node_id:
			continue  # в тоннеле между узлами trace стоит
		var watched := false
		for ice in _ices:
			if ice.brain != null and ice.brain.target() == session:
				watched = true
			elif _tick_ices.has(ice) and (_tick_ices[ice] as TickIce).awareness_of(session) > 0:
				watched = true
		(_sessions[session] as DaemonSession).trace.tick(_now, not watched, rate)


## Хаб графа (тихий узел: node_def.hub).
func is_hub() -> bool:
	return bool(node_def.get("hub", false))


## Скорость дрейфа trace игрока в этом узле, 1/с: хаб — отрицательная, узел графа — по тиру, прочее (одиночный узел) — 0.
func trace_drift_rate() -> float:
	if not is_graph_node():
		return 0.0
	if is_hub():
		return -1.0 / maxf(float(settings["hub_trace_decay_sec"]), 0.001)
	var table: Variant = settings.get("trace_drift_sec", {})
	var sec := float((table as Dictionary).get(tier(), 0.0)) if table is Dictionary else 0.0
	return 1.0 / sec if sec > 0.0 else 0.0


## Trace игрока за событие из trace_events (поиск, датчик, барьер, FAIL, Трассировщик). Заморозка JITTER — в TraceMeter.
func add_trace_event(session: String, event_name: String) -> void:
	if not _sessions.has(session):
		return
	var amount := float((settings.get("trace_events", {}) as Dictionary).get(event_name, 0.0))
	if amount > 0.0:
		(_sessions[session] as DaemonSession).trace.add_amount(amount, _now)


func _broadcast_state() -> void:
	var ice_list: Array = []
	for ice in _ices:
		var b := ice.brain
		var entry := {
			"id": str(ice.name),
			"p": [ice.position.x, ice.position.y, ice.position.z],
			"f": [b.facing.x, b.facing.z],
			"s": b.state(),
			"b": 1 if b.is_black() else 0,
		}
		_add_tick_fields(entry, ice)
		if b is TickBlackBrain:
			# Фаза: 0 сон, 1 пробуждение, 2 охота, 3 возврат; bw — тактов до конца пробуждения (на деке «ЧЁРНЫЙ ЛЁД 6…»); pg — до пинга; bc — клетка.
			var bb: TickBlack = (b as TickBlackBrain).black
			var bc := bb.cell()
			entry["bp"] = bb.phase
			entry["bw"] = bb.wake_left()
			entry["pg"] = bb.ping_in()
			entry["c"] = [bc.x, bc.y]
			if bb.kind() != "":
				entry["kd"] = bb.kind()   # вид (hound, kraken, raven, scorpion, lich): клиент рисует модель вида; нет поля — базовый Black ICE
		ice_list.append(entry)
	for session in _live_sessions():
		var ds: DaemonSession = _sessions[session]
		var cd: Array = []
		for id in ds.deck:
			cd.append(cd_entry(ds, id, _now))
		_log_effect_ends(session, cd)
		var fields := {
			"trace": ds.trace.value(),
			"level": ds.trace.level(),
			"ghost": ds.is_ghost(_now),
			"hunt": is_hunted(session),  # за этим игроком идёт охота Black ICE: клиент закрывает порталы (portal_locked)
			"k": snappedf(_now, 0.001),
			"ice": ice_list,
			"cd": cd,
		}
		fields["tk"] = _tick_field(session)
		if not devices.beacons.is_empty():
			fields["bk"] = devices.beacon_view()
		if not devices.sensors.is_empty():
			fields["sn"] = devices.sensor_view()
			var fired := devices.take_sensor_fired(session)
			if not fired.is_empty():
				fields["sf"] = fired   # сработал Датчик на этого игрока: вспышка луча, звук и «ТРЕВОГА +n» в центре зрения (ice.md П8)
		if not devices.barriers.is_empty():
			fields["br"] = devices.barrier_view()
		if layout != null and not layout.booths.is_empty():
			fields["bo"] = booth_view()
		if _black_brain != null:
			fields["burn"] = int(black_burns.get(session, 0))   # ожоги за забег, на деке «ОЖОГ 1/3»
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.STATE, fields), false)


## Устройства раскладки (Датчики, Барьеры, Маяки) живут в LayoutDevices (`devices`); ниже — прежние публичные имена узла, тонкие делегаты.

## Датчики узла для state (поле `sn`): [{id, c: [[x, z], …] клетки луча, on 0/1, bl 1 — мигает перед включением, l — тактов до смены}].
func sensor_view() -> Array:
	return devices.sensor_view()


## Сработал датчик (trace +5, тревога узла +5, ближайший Страж — в Проверку): для тестов и сценариев.
func _sensor_fire(ts: TickSensor, session: String, cell: Vector2i) -> void:
	devices.sensor_fire(ts, session, cell)


## Срабатывания Датчика на эту сессию с прошлого вызова (и сразу забыть): [{id, a}] — для поля `sf` state. Пусто — ничего не срабатывало.
func take_sensor_fired(session: String) -> Array:
	return devices.take_sensor_fired(session)


## Для тестов и сценариев: датчики узла.
func sensors() -> Array[TickSensor]:
	return devices.sensors


## Барьеры узла для state (поле `br`): [{id, c: [[x, z], …] клетки блока, open 0/1}].
func barrier_view() -> Array:
	return devices.barrier_view()


## Закрыт ли барьер (нет такого — false).
func barrier_closed(id: String) -> bool:
	return devices.barrier_closed(id)


## Вскрыть барьер (ice.md §5; how: "charge" | "force" | "pick"). Подробно — LayoutDevices.open_barrier.
func open_barrier(id: String, how: String, session: String = "") -> bool:
	return devices.open_barrier(id, how, session)


## Маяки узла для state (поле `bk`).
func beacon_view() -> Array:
	return devices.beacon_view()


## Для тестов и сценариев: маяки узла.
func beacons() -> Array[TickBeacon]:
	return devices.beacons


## Тактовые поля ICE в state (старые id, p, f, s, b остаются): c — клетка [x, z], d — направление, st — состояние TickIce 0..3, nc / nd — клетка и
## направление после следующего шага (намерение), aw — наибольший счётчик 0..6, rt (необязательное) — клетки следующих 3 шагов [[x, z], …] (первая = nc,
## клетка повторяется, пока ICE стоит; нет, если все три — его клетка), fp (необязательное) — [x, z] отпечатка, где ICE заметил нетраннера (Взгляд / Проверка; Проверка идёт к нему),
## lost (необязательное) — 1 в тот такт, когда ICE потерял нетраннера (спал до нуля после замечания). Soft ICE — из TickIce; Black ICE (IceBrain) — по его позиции, без намерения.
func _add_tick_fields(entry: Dictionary, ice: IceNode) -> void:
	var ti: TickIce = _tick_ices.get(ice)
	if ti != null:
		var it: Dictionary = _intents.get(ice, {})
		if it.is_empty():
			it = ti.intent()
			_intents[ice] = it
		entry["s"] = tick_state_to_legacy(int(it["state"]))
		entry["c"] = [(it["cell"] as Vector2i).x, (it["cell"] as Vector2i).y]
		entry["d"] = [(it["dir"] as Vector2i).x, (it["dir"] as Vector2i).y]
		entry["st"] = int(it["state"])
		entry["nc"] = [(it["next_cell"] as Vector2i).x, (it["next_cell"] as Vector2i).y]
		entry["nd"] = [(it["next_dir"] as Vector2i).x, (it["next_dir"] as Vector2i).y]
		entry["aw"] = int(it["aware"])
		var ahead: Array = it.get("ahead", [])
		var moves_ahead := false
		for a: Vector2i in ahead:
			if a != (it["cell"] as Vector2i):
				moves_ahead = true
		if moves_ahead:   # стоит все 3 шага — следа нет, поле не шлём
			entry["rt"] = ahead.map(func(a: Vector2i) -> Array: return [a.x, a.y])
		if it.get("fp") is Vector2i:   # Взгляд / Проверка: клетка, где ICE заметил нетраннера
			entry["fp"] = [(it["fp"] as Vector2i).x, (it["fp"] as Vector2i).y]
		if bool(it.get("lost", false)):   # потерял нетраннера (один такт): над ICE «…»
			entry["lost"] = 1
		var soft := ice_settings.duplicate(true)
		soft.merge(node_def.get("ice_settings", {}), true)
		entry["sc"] = float(_tick_ice_settings(soft)["sight_cells"])   # дальность зрения в клетках: по ней клиент рисует свет на полу и красит рамку прицела
		return
	var dark := ice_settings.duplicate(true)
	dark.merge(node_def.get("ice_settings", {}), true)
	dark.merge(black_ice_settings, true)
	entry["sc"] = roundi(float(dark.get("sight_range", 12.0)) / NodeGrid.CELL_M)   # Black ICE: дальность из метров в клетки
	var cell := NodeGrid.cell_of(ice.position)
	var dir := NodeGrid.dir8(Vector2i.ZERO, Vector2i(roundi(ice.brain.facing.x * 100.0), roundi(ice.brain.facing.z * 100.0)))
	entry["c"] = [cell.x, cell.y]
	entry["d"] = [dir.x, dir.y]
	entry["st"] = ice.brain.state()
	entry["nc"] = [cell.x, cell.y]
	entry["nd"] = [dir.x, dir.y]
	entry["aw"] = clampi(roundi(ice.brain.awareness() * 6.0), 0, 6)


## Поле `tk` сообщения state: n — номер такта узла, at — когда был последний (время узла, как «k»), win — окно, inh — «вдох» перед тактом по окну,
## mv — «твой ход принят» (для каждого игрока своё).
func _tick_field(session: String) -> Dictionary:
	return {
		"n": tick_clock.tick_no,
		"at": snappedf(tick_clock.last_tick_at, 0.001),
		"win": tick_clock.window_sec,
		"inh": 1 if tick_clock.inhale(_now, float(settings.get("tick_inhale_sec", 0.5))) else 0,
		"mv": 1 if tick_clock.moved(session) else 0,
	}


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
	_mark_entered_tick(session)
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
	barrier.end_early(session, "session_lost")
	if bridge != null and synced and _sessions.has(session):
		_merge_world(session, {"connected": false, "trace": 0, "node": node_id})


func _on_avatar_removed(session: String) -> void:
	breach.end_early(session, "avatar_removed")   # до того, как сессия забыта: итогу нужна её дека
	charge.end_early(session, "avatar_removed")
	decrypt.end_early(session, "avatar_removed")
	barrier.end_early(session, "avatar_removed")
	shards.close_vaults_of(session)
	_portal_state.erase(session)
	if not _sessions.has(session):
		return
	_sessions.erase(session)
	_effect_logged.erase(session)
	_entered_at.erase(session)
	_exiting[session] = true
	_level_cbs.erase(session)
	outcome.hunted.erase(session)
	outcome._sync_hunt(session)  # игрок ушёл: охоты за сессией больше нет (Мосту сказать «false»)
	_write_node_state()
	_forget_in_ices(session)


## ICE забывает нетраннера (вышел, выброшен, ушёл в другой узел): осведомлённость и память Soft ICE на клетках, цель IceBrain.
func _forget_in_ices(session: String) -> void:
	_entered_tick.erase(session)
	_grace_spent.erase(session)
	for ice in _ices:
		if ice.brain != null:
			ice.brain.forget(session)
	for ice: IceNode in _tick_ices:
		(_tick_ices[ice] as TickIce).forget(session)
	if _black_brain != null:
		_black_brain.black.forget(session)


func _on_level_changed(old_level: int, new_level: int, value: float, session: String) -> void:
	event.emit({"kind": "level", "session": session, "from": old_level, "to": new_level, "value": value})
	# Мост (правило сигнала СБ, P3) читает session.world.trace_level: с уровня TRACE шлёт сигнал с номером терминала.
	if bridge != null and synced:
		_mark_trace_level(session, new_level, value, _sessions[session].active_effects(_now) if _sessions.has(session) else [])
	# trace 100: ICE хватает. С Black ICE в узле это делает охота (она идёт с уровня TRACE); без него Soft ICE выбрасывает.
	if new_level == TraceMeter.Level.FLATLINE and not has_black_ice():
		_end(session, ExitLogic.REASON_EJECTED, "ice_eject")


func _on_ice_ejected(session: String, reason: String) -> void:
	if reason == "black_caught":
		# Поймали в окне возврата после обрыва — в карточке мастеру «обрыв до флэтлайна».
		if net.peer_of(session) == -1:
			outcome.flat_disconnect[session] = true
		_end(session, ExitLogic.REASON_FLATLINE, "flatline")
	elif reason == "flatline" and has_black_ice():
		return  # Soft ICE при trace 100 в узле с Black ICE не выбрасывает: добивает охота
	else:
		_end(session, ExitLogic.REASON_EJECTED, "ice_eject")


func _end(session: String, exit_reason: String, kind: String) -> void:
	outcome._end(session, exit_reason, kind)


func _on_leave_requested(session: String) -> void:
	if not _sessions.has(session):
		return
	var avatar := net.get_avatar(session)
	if avatar == null or not NodeLayout.on_exit_pad_in(layout, avatar.position):
		return
	if _black_brain != null and _black_brain.black.exit_locked():
		return   # Кракен бодрствует: площадка выхода закрыта (аварийный выход — отдельным путём)
	net.end_session(session, ExitLogic.REASON_CLEAN)


## Предел прыжка (м) из клетки: Скорпион в 2 клетках карты от себя разрешает прыжок только на 1 клетку; 0 — предела нет.
func hop_limit_at(from: Vector2i) -> float:
	return _black_brain.black.hop_limit_at(from) if _black_brain != null else 0.0


## Просьба начать взлом: отвечает только узел, где игрок (в графе обработчик подключён у каждого узла).
func _on_breach_open(session: String, vault: String, ids: Array) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	breach.request_open(session, vault, ids)
	if breach.has_attempt(session):
		register_move(session)   # начало взлома — ход


## Привязка телепорта к площадке у хранилища узла: legacy — прежнее правило (NodeLayout.snap_to_vault_pad), иначе клетка pad раскладки.
func snap_teleport(to: Vector3) -> Dictionary:
	if layout.is_legacy():
		return NodeLayout.snap_to_vault_pad(to, shards.slot_pos.values())
	return NodeLayout.snap_to_vault_pad_in(layout, to, shards.slot_pos.values())


## Просьба зарядить защитного демона: отвечает только узел, где игрок (в графе обработчик подключён у каждого узла).
func _on_charge_requested(session: String, daemon_id: String) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	charge.request_start(session, daemon_id)
	if charge.has_attempt(session):
		register_move(session)   # начало заряда — ход


## Просьба вскрыть барьер (ice.md §5): отвечает только узел, где игрок. Начало вскрытия — ход.
func _on_barrier_requested(session: String, barrier_id: String, how: String) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	barrier.request_start(session, barrier_id, how)
	if barrier.has_attempt(session):
		register_move(session)


## Барьер с таким id есть в узле (открытый или закрытый).
func has_barrier(id: String) -> bool:
	return devices.has_barrier(id)


## Клетка `cell` — соседняя (по восьми направлениям) с блоком барьера и сама свободна: оттуда барьер вскрывают.
func barrier_adjacent(id: String, cell: Vector2i) -> bool:
	return devices.barrier_adjacent(id, cell)


## Просьба расшифровать шард из ГРУЗа (К7): отвечает только узел, где игрок.
func _on_decrypt_requested(session: String, item: String) -> void:
	if not _sessions.has(session) or net.node_of(session) != node_id:
		return
	decrypt.request_start(session, item)
	if decrypt.has_attempt(session):
		register_move(session)   # начало расшифровки — ход


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
	if reply["ok"]:
		register_move(session)   # удачный запуск демона — ход
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
	if avatar == null or net.node_of(session) != node_id or not shards.has_slot(object_id):
		return false
	if vault_state(object_id, session) != VAULT_OPEN:
		return false
	return NodeLayout.flat_distance(avatar.position, net.object_position(object_id)) <= NodeLayout.GRAB_REACH


## Шард взят: игровая часть уже сделана (NetServer), в Мосте он переходит из узла в деку.
func _on_object_taken(object_id: String, session: String) -> void:
	if not shards.has_slot(object_id):
		return
	register_move(session)   # взять шард — ход
	shards.on_taken(object_id, session)   # слот за сессией; открытость кончилась вместе с шардом
	event.emit({"kind": "shard_taken", "session": session, "id": object_id})
	var item: String = shards.items.get(object_id, "")
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
	outcome._on_exit_event(ev)


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


## Исход забега и запись в Мост (_mark_finish, _finish_in_bridge, ожидание мастера, охота) — в RunOutcome (run_outcome.gd);
## ниже тонкие делегаты с прежними именами.
func _mark_finish(session: String, finish: String, disconnect: bool, extra: Dictionary = {}) -> void:
	await outcome._mark_finish(session, finish, disconnect, extra)


func _callsign_of(session: String) -> String:
	return outcome._callsign_of(session)


func _finish_in_bridge(ev: Dictionary) -> void:
	await outcome._finish_in_bridge(ev)


## Ответ Моста «в деке предмет, которого нет в moves» (протокол 6.5): деку надо перечитать и повторить тем же rid.
static func is_moves_stale(resp: Dictionary) -> bool:
	return BridgeApi.err_code(resp) == "bad_request" and str((resp.get("err", {}) as Dictionary).get("msg", "")).contains("не упомянут в moves")


# ---------------------------------------------------------------- граф узлов (W1)

func portals() -> Array:
	return _portals


func slot_ids() -> Array:
	return shards.slot_ids()


## Таблички узла для события node: [{p: [x, z], text}]. Узел с раскладкой (не legacy) — из её signs (клетка карты → место в мире),
## без раскладки — signs из graph.json (`graph_signs`, координаты прежней комнаты).
func event_signs(graph_signs: Array) -> Array:
	if layout.is_legacy():
		return graph_signs
	var out: Array = []
	for s: Dictionary in layout.signs:
		var pos: Vector3 = s["pos"]
		out.append({"p": [pos.x, pos.z], "text": s["text"]})
	return out


## Вид хранилища слота для сессии: empty — шарда нет (вынесен, ждёт пополнения); closed — шард внутри, взять нельзя;
## open — можно взять. Пока флаг `vault_requires_open` выключен (по умолчанию), лежащий шард открыт всем; К3 включает флаг, и
## хранилище открывается только взломом (open_vault) и только для сессии, которая его взломала.
func vault_state(slot: String, session: String = "") -> String:
	return shards.vault_state(slot, session)


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
	shards.open_vault(slot, session, sec)


## Хранилище закрылось снова (срок vault_open_sec вышел, шард взят или слот опустел).
func close_vault(slot: String) -> void:
	shards.close_vault(slot)


## Слот, в котором лежит предмет Моста item ("" — ни в одном).
func slot_of_item(item: String) -> String:
	return shards.slot_of_item(item)


## Сколько секунд слоту ждать пополнения (0 — не ждёт).
func refill_left(slot: String) -> int:
	return shards.refill_left(slot)


## Доступ сессии к хранилищу для панели взлома: access — empty | open | busy | cooldown | ok (ShardVaults.vault_access).
func vault_access(slot: String, session: String) -> Dictionary:
	return shards.vault_access(slot, session)


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
	return shards.dead_decks()


## Слоты шардов для клиента: [{id, p, ready, vault, tier?, enc?, kind?, dead?}] для сессии (ShardVaults.shard_view).
func shard_view(session: String = "") -> Array:
	return shards.shard_view(session)


## Сколько слотов шардов ждут пополнения.
func empty_slots() -> int:
	return shards.empty_slots()


## Идёт ли запись охоты в Мост (тест ждёт, пока писатель закончит или сдастся).
func is_hunt_writing() -> bool:
	return outcome.is_hunt_writing()


func is_hunted(session: String) -> bool:
	return outcome.is_hunted(session)


## Идёт ли в узле охота Black ICE (за кем-то из игроков узла).
func is_hunt_active() -> bool:
	return outcome.is_hunt_active()


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
			register_move(session)   # вход в портал — ход
			portal_requested.emit(session, near)
		_portal_state[session] = st


# --- тревога и локдаун узла

## Уровень тревоги 0…4 по значению шкалы 0…100 (ice.md §4: 25 / 50 / 75 / 100).
static func alarm_level_for(value: float) -> int:
	return NodeAlarm.level_for(value)


## Состояние и правила тревоги — в NodeAlarm (`alarm_state`); ниже — прежние публичные имена узла, тонкие делегаты.

## Тревога узла растёт на amount шкалы 0…1 (прежний вызов: тесты, Мост) — это amount × 100 пунктов.
func raise_alert(amount: float) -> void:
	alarm_state.raise_points(amount * ALARM_MAX)


## Тревога растёт на points пунктов шкалы 0…100; событие и запись узла — когда целое значение или уровень изменились.
func raise_alarm(points: float) -> void:
	alarm_state.raise_points(points)


## Событие из alert_events (поиск, выброс, FAIL, датчик, барьер, Трассировщик); только в узле графа.
func alarm_event(event_name: String) -> void:
	alarm_state.on_event(event_name)


## Будки запасных Стражей для state (поле `bo`): [{id, c: [x, z] клетка 1 м, open 0/1 — запасной вышел (створка сдвинута)}].
func booth_view() -> Array:
	return alarm_state.booth_view()


func _apply_alert() -> void:
	alarm_state.apply()


func _node_occupied() -> bool:
	return alarm_state.occupied()


func _alarm_on_tick() -> void:
	alarm_state.on_tick()


func _tick_alert() -> void:
	alarm_state.cool_tick()


## Закрыть узел сервером мира на sec секунд (когда Моста нет; с Мостом локдаун — lockdown_until узла).
func lock_for(sec: float) -> void:
	alarm_state.lock_for(sec)


## Сколько секунд узел ещё закрыт (0 — открыт): большее из локдауна сервера мира и lockdown_until Моста (мс Unix).
func lockdown_left_sec() -> float:
	return alarm_state.lockdown_left_sec()


func is_locked_down() -> bool:
	return alarm_state.is_locked_down()


# --- шарды: вынос и пополнение

## Шард слота ушёл навсегда (на телефон или в другой узел) — слот пуст, пополнится через delay секунд (если в Мосте найдётся шард).
func _deplete(id: String, delay: float) -> void:
	shards.deplete(id, delay)


## Забег игрока закончился (GraphWorld зовёт все узлы): слоты, где он взял шард, пустеют — кроме случая, когда добыча осталась
## в этом же узле (выброс/флэтлайн/обрыв: предмет вернулся в узел, слот снова с шардом).
func settle_shards(session: String, end_node: String, loot: String) -> void:
	shards.settle_shards(session, end_node, loot)


## Автопополнение стоит, пока узел в локдауне и пока в нём идёт охота Black ICE (docs/netrun.md, «Открытые вопросы», п. 2).
func is_refill_paused() -> bool:
	return shards.is_refill_paused()


## Пополнение слота: с Мостом нужен свободный шард `node:<узел>`, без Моста слот просто оживает (ShardVaults.refill).
func _refill(id: String) -> void:
	await shards.refill(id)


## Свободный предмет узла в Мосте — шард или демон: owner node:<узел>, не привязанный к слоту. "" — нет.
func _free_shard_item() -> String:
	return await shards.free_shard_item()


func _push_shards() -> void:
	shards.push_shards()


# --- переход игрока между узлами: GraphWorld забирает сессию из одного узла и отдаёт другому

## Снять сессию с узла (уходит в тоннель/в другой узел): состояние (trace, дека, перезарядки) возвращается вызывающему целым.
func release_session(session: String) -> DaemonSession:
	return outcome.release_session(session)


## Принять сессию с её состоянием: trace и дека те же объекты, что были в прошлом узле.
func adopt_session(session: String, ds: DaemonSession) -> void:
	_sessions[session] = ds
	_entered_at[session] = _now
	_mark_entered_tick(session)
	_connect_meter(session, ds.trace)
	print("[gray-node] ", session, " вошёл в ", node_id, " (переход)")
	_push_deck(session)
	if bridge != null and synced:
		# Мост читает world.node (где игрок сейчас) и trace_level/effects (сигнал СБ): после перехода пишем их для нового узла.
		_merge_world(session, {"connected": net.peer_of(session) != -1, "trace": int(ds.trace.value()), "node": node_id,
			"trace_level": ds.trace.level(), "effects": ds.active_effects(_now)})
		_write_node_state()

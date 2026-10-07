extends GdUnitTestSuite
## Тактовое время узла (settings.time_mode = "tick"): ICE по клеткам, такт по ходам и по окну, несколько нетраннеров, панели, рассылка, правило «один ход за такт».
## Сервер (NetServer + GrayNode, без Моста) и клиенты NetClient в одном процессе. Время узла подаёт тест через GraphClock (shared_clock):
## окно 5 с — это clock.now += 5.0, без sleep. Сеть живёт реальным временем: ждём доставки пакетов кадрами.

static var _next_port := 18791

var _root: Node
var _server: NetServer
var _node: GrayNode
var _clock := GraphClock.new()
var _clients: Dictionary = {}     # сессия -> NetClient
var _states: Dictionary = {}      # сессия -> последний state
var _denied: Dictionary = {}      # сессия -> [причины отказа телепорта]
var _events: Array = []
var _cfg: NetConfig
var _tokens := {"tok_a": "s_a", "tok_b": "s_b"}


func _boot(tick: bool, extra: Dictionary = {}, only_one_ice: bool = true) -> void:
	_root = Node.new()
	_root.name = "TickTestRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, DictTokenVerifier.new(_tokens))).is_equal(OK)
	_node = GrayNode.new()
	var s := NodeGraph.DEFAULT_SETTINGS.duplicate(true)
	if tick:
		s["time_mode"] = "tick"
	s.merge(extra, true)
	_node.settings = s
	_node.trace_settings = {"weights": {"seen_by_ice": 0.5}, "decay_per_sec": 0.0}   # trace не должен выбросить раньше ICE
	_node.shared_clock = _clock
	sroot.add_child(_node)
	_node.start(_server)
	if only_one_ice:
		# Один Страж (ice_1: пояс z = -4 с востока на запад): второй не мешает считать клетки.
		var second: IceNode = _node.ices()[1]
		_node._tick_ices.erase(second)
		_node._ices.erase(second)
		second.queue_free()
	_events = []
	_node.event.connect(func(ev: Dictionary): _events.append(ev))


func after_test() -> void:
	for c: NetClient in _clients.values():
		if is_instance_valid(c):
			await c.drop()
	_server.stop_net()
	_root.queue_free()
	_clients.clear()
	_states.clear()
	_denied.clear()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## Подключить клиента; ждём, пока у сессии появится аватар на сервере.
func _join(token: String) -> String:
	var session: String = _tokens[token]
	var croot := Node.new()
	croot.name = "C_" + session
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var c := NetClient.new()
	c.name = "Net"
	croot.add_child(c)
	c.state_received.connect(func(st: Dictionary): _states[session] = st)
	c.teleport_denied.connect(func(reason: String, _p: Vector3, _l: float):
		if not _denied.has(session):
			_denied[session] = []
		_denied[session].append(reason))
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = token
	c.start_client(cfg)
	_clients[session] = c
	assert_bool(await _wait_for(func(): return _server.has_avatar(session))).is_true()
	return session


## Ход: просьба о прыжке в клетку и ожидание ответа сервера (принят — счётчик скачков вырос, отказан — пришла причина).
func _hop(session: String, to: Vector2i) -> void:
	var before := _server.teleport_count(session)
	var nden: int = (_denied.get(session, []) as Array).size()
	(_clients[session] as NetClient).request_teleport(NodeGrid.center(to))
	assert_bool(await _wait_for(func(): return _server.teleport_count(session) > before or (_denied.get(session, []) as Array).size() > nden)).is_true()


func _cell_of(session: String) -> Vector2i:
	return NodeGrid.cell_of(_server.get_avatar(session).position)


## Соседняя свободная клетка (не своя): для хода.
func _neighbor(c: Vector2i, k: int = 0) -> Vector2i:
	var out: Array[Vector2i] = []
	for d: Vector2i in NodeGrid.DIRS8:
		if _server.grid.can_step(c, d):
			out.append(c + d)
	return out[k % out.size()]


func _tick_no() -> int:
	return _node.tick_clock.tick_no


func _ice_cell() -> Vector2i:
	return NodeGrid.cell_of(_node.ices()[0].position)


## Время узла вперёд и несколько кадров, чтобы узел отработал.
func _advance(sec: float) -> void:
	_clock.now += sec
	await _frames(3)


func test_а_страж_идёт_по_маршруту_по_две_клетки_за_такт() -> void:
	_boot(true)
	await _join("tok_a")
	await _advance(0.1)
	assert_object(_ice_cell()).is_equal(Vector2i(8, 10))   # старт — первая точка маршрута (0; -4)
	var seen: Array = []
	for _i in 3:
		await _advance(5.0)
		seen.append(_ice_cell())
	assert_array(seen).is_equal([Vector2i(10, 10), Vector2i(12, 10), Vector2i(14, 10)])
	assert_int(_tick_no()).is_equal(3)


func test_б_такт_по_ходу_игрока_не_раньше_минимального_интервала() -> void:
	_boot(true)
	var a := await _join("tok_a")
	await _advance(0.1)
	await _hop(a, _neighbor(_cell_of(a)))
	await _advance(0.2)
	assert_int(_tick_no()).is_equal(0)   # сходил, но прошло меньше 0,6 с
	await _advance(0.5)
	assert_int(_tick_no()).is_equal(1)
	assert_str(_node.tick_clock.last_by).is_equal("moves")
	assert_object(_ice_cell()).is_equal(Vector2i(10, 10))


func test_в_такт_по_окну_через_пять_секунд_без_хода() -> void:
	_boot(true)
	await _join("tok_a")
	await _advance(0.1)
	await _advance(4.7)
	assert_int(_tick_no()).is_equal(0)
	await _advance(0.4)
	assert_int(_tick_no()).is_equal(1)
	assert_str(_node.tick_clock.last_by).is_equal("window")
	assert_int(_node.tick_clock.last_moves).is_equal(0)


func test_г_взгляд_проверка_поиск_и_выброс_на_четвёртом_такте() -> void:
	_boot(true, {"entry_hidden_ticks": 0, "arrival_grace_ticks": 0})
	var a := await _join("tok_a")
	# Нетраннер стоит на пути Стража (ряд z = -4): сервер ставит его в клетку без хода.
	_server.teleport(a, NodeGrid.center(Vector2i(12, 10)))
	await _advance(0.1)
	var states: Array = []
	for _i in 3:
		await _advance(5.0)
		states.append((_node._tick_ices[_node.ices()[0]] as TickIce).state())
		if states.size() == 1:
			# На виду за такт набегает «секунды с прошлого такта» (5 с) × вес 0,5.
			assert_float(_node.session_state(a).trace.value()).is_equal_approx(2.5, 0.3)
	assert_array(states).is_equal([1, 2, 3])   # «?» → Проверка → Поиск: на третьем такте тревога
	assert_bool(_events.any(func(e): return e["kind"] == "ice_eject")).is_false()
	assert_float(_node.alert).is_greater(0.0)   # search_started поднял тревогу узла
	await _advance(5.0)   # четвёртый такт, целиком проведённый в Поиске: захват
	assert_bool(_events.any(func(e): return e["kind"] == "ice_eject")).is_true()


func test_д_двое_такт_ждёт_обоих_но_не_дольше_окна() -> void:
	_boot(true)
	var a := await _join("tok_a")
	var b := await _join("tok_b")
	await _advance(0.1)
	await _hop(a, _neighbor(_cell_of(a)))
	await _advance(3.0)
	assert_int(_tick_no()).is_equal(0)   # Бета ещё думает
	await _hop(b, _neighbor(_cell_of(b), 2))
	await _advance(0.1)
	assert_int(_tick_no()).is_equal(1)
	assert_str(_node.tick_clock.last_by).is_equal("moves")
	assert_int(_node.tick_clock.last_moves).is_equal(2)
	# Теперь ходит только Альфа: такт — по окну от прошлого.
	await _hop(a, _neighbor(_cell_of(a), 1))
	await _advance(4.5)
	assert_int(_tick_no()).is_equal(1)
	await _advance(0.6)
	assert_int(_tick_no()).is_equal(2)
	assert_str(_node.tick_clock.last_by).is_equal("window")


## Не свободен (Т3): оборвана связь — аватар ждёт возврата в узле, но такт не держит. Панели (взлом, заряд, расшифровка) отсекаются тем же
## списком свободных (GrayNode._tick_step), а в TickClock — тестом «нетраннер в панели такт не держит».
func test_е_нетраннер_без_связи_такт_не_держит() -> void:
	_boot(true)
	var a := await _join("tok_a")
	var b := await _join("tok_b")
	await _advance(0.1)
	var cb: NetClient = _clients[b]
	_clients.erase(b)
	await cb.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of(b) == -1)).is_true()
	assert_bool(_server.has_avatar(b)).is_true()   # аватар Беты ждёт возврата и остаётся в узле
	await _hop(a, _neighbor(_cell_of(a)))
	await _advance(0.7)
	assert_int(_tick_no()).is_equal(1)   # Бета не ходила, а такт наступил по ходу Альфы
	assert_str(_node.tick_clock.last_by).is_equal("moves")


func test_ж_нетраннера_нет_тактов_нет() -> void:
	_boot(true)
	await _advance(30.0)
	assert_int(_tick_no()).is_equal(0)
	assert_object(_ice_cell()).is_equal(Vector2i(8, 10))
	await _join("tok_a")
	await _advance(0.1)
	await _advance(4.5)
	assert_int(_tick_no()).is_equal(0)   # окно отсчитывается с появления нетраннера, а не с запуска
	await _advance(0.6)
	assert_int(_tick_no()).is_equal(1)


func test_з_state_в_тактовом_режиме_несёт_tk_и_намерения() -> void:
	_boot(true)
	var a := await _join("tok_a")
	assert_bool(await _wait_for(func(): return _states.has(a))).is_true()
	await _advance(5.1)
	await _frames(10)
	assert_bool(await _wait_for(func(): return int((_states[a].get("tk", {}) as Dictionary).get("n", 0)) == 1)).is_true()
	var st: Dictionary = _states[a]
	var tk: Dictionary = st["tk"]
	assert_float(float(tk["win"])).is_equal(5.0)
	assert_int(int(tk["mv"])).is_equal(0)
	assert_bool(tk.has("at") and tk.has("inh")).is_true()
	var ice: Dictionary = st["ice"][0]
	for key in ["id", "p", "f", "s", "b", "c", "d", "st", "nc", "nd", "aw", "sc"]:
		assert_bool(ice.has(key)).is_true()
	assert_float(float(ice["sc"])).is_greater(0.0)   # дальность зрения в клетках
	assert_int(int(ice["c"][0])).is_equal(10)   # после первого такта клетка (10; 10)
	assert_int(int(ice["c"][1])).is_equal(10)
	assert_int(int(ice["nc"][0])).is_equal(12)   # намерение: куда пойдёт на следующем такте
	assert_int(int(ice["nc"][1])).is_equal(10)
	assert_int(int(ice["st"])).is_equal(0)
	assert_int(int(ice["aw"])).is_equal(0)


func test_з_state_в_реальном_времени_без_тактовых_полей() -> void:
	_boot(false)
	var a := await _join("tok_a")
	assert_bool(await _wait_for(func(): return _states.has(a))).is_true()
	var st: Dictionary = _states[a]
	assert_bool(st.has("tk")).is_false()
	for key in ["c", "d", "st", "nc", "nd", "aw", "sc"]:
		assert_bool((st["ice"][0] as Dictionary).has(key)).is_false()


func test_и_один_ход_за_такт_второй_отказ_moved_и_mv() -> void:
	_boot(true)
	var a := await _join("tok_a")
	await _advance(0.1)
	await _hop(a, _cell_of(a))   # «ждать» — прыжок на свою клетку — тоже ход
	assert_array(_denied.get(a, [])).is_empty()
	assert_bool(_node.move_made(a)).is_true()
	assert_bool(await _wait_for(func(): return int(((_states.get(a, {}) as Dictionary).get("tk", {}) as Dictionary).get("mv", 0)) == 1)).is_true()
	await _hop(a, _neighbor(_cell_of(a)))
	assert_array(_denied[a]).is_equal([WorldMsg.REASON_MOVED])
	await _advance(0.7)   # такт: ход принят, ходы очищены
	assert_int(_tick_no()).is_equal(1)
	assert_bool(_node.move_made(a)).is_false()
	var before := _server.teleport_count(a)
	await _hop(a, _neighbor(_cell_of(a)))
	assert_int(_server.teleport_count(a)).is_equal(before + 1)   # в новом такте снова можно


func test_ход_в_реальном_времени_по_прежнему_ограничен_перезарядкой() -> void:
	_boot(false)
	var a := await _join("tok_a")
	await _hop(a, _neighbor(_cell_of(a)))
	await _hop(a, _neighbor(_cell_of(a), 1))
	assert_array(_denied[a]).is_equal([WorldMsg.REASON_COOLDOWN])


func test_black_ice_за_такт_идёт_black_tick_sec_виртуального_времени() -> void:
	_boot(true)
	_node.black_ice_settings = {"sight_range": 0.0}   # слеп: патрулирует, не охотится
	_node.enable_black_ice()
	var black: IceNode = _node.ices().filter(func(i: IceNode): return i.brain.is_black())[0]
	await _join("tok_a")
	await _advance(0.1)
	var p0 := black.position
	await _advance(5.0)   # такт по окну
	assert_int(_tick_no()).is_equal(1)
	assert_float(p0.distance_to(black.position)).is_equal_approx(1.0, 0.15)   # patrol_speed 1 м/с × black_tick_sec 1 с
	await _advance(0.3)   # без нового такта Black ICE стоит
	assert_float(p0.distance_to(black.position)).is_equal_approx(1.0, 0.15)


# --- Грейс прибытия (W3): безопасный выход из портала ---

func test_грейс_прибытия_ice_не_наступает_и_не_берёт_пока_игрок_стоит() -> void:
	_boot(true)   # entry_hidden_ticks 2 + arrival_grace_ticks 2 (по умолчанию)
	var a := await _join("tok_a")
	_server.teleport(a, NodeGrid.center(Vector2i(12, 10)))   # на пути Стража (он дойдёт до неё на втором такте), без хода
	await _advance(0.1)
	var here := Vector2i(12, 10)
	var states: Array = []
	for n in range(1, 5):
		await _advance(5.0)
		assert_bool(_node._arrival_immune(a, n)).override_failure_message("такт %d: грейса нет" % n).is_true()
		assert_object(_ice_cell()).override_failure_message("такт %d: Страж наступил на клетку игрока" % n).is_not_equal(here)
		states.append((_node._tick_ices[_node.ices()[0]] as TickIce).state())
	assert_bool(_events.any(func(e): return e["kind"] == "ice_eject")).is_false()
	assert_int(states[2]).is_less_equal(TickIce.Mode.GAZE)   # на виду с третьего такта, но самое большее «?»
	assert_int(states[3]).is_less_equal(TickIce.Mode.GAZE)
	assert_bool(_node._arrival_immune(a, 5)).is_false()
	# после грейса прежнее поведение: стоящий на виду доходит до Поиска и захвата
	for _i in 6:
		await _advance(5.0)
	assert_bool(_events.any(func(e): return e["kind"] == "ice_eject")).is_true()


func test_ход_игрока_снимает_грейс_прибытия() -> void:
	_boot(true)
	var a := await _join("tok_a")
	await _advance(0.1)
	assert_bool(_node._arrival_immune(a, 1)).is_true()
	await _hop(a, _neighbor(_cell_of(a)))
	await _advance(0.7)   # такт по ходу: первый такт после входа
	assert_int(_tick_no()).is_equal(1)
	assert_bool(_node._arrival_immune(a, 2)).override_failure_message("сходил, а грейс остался").is_false()


func test_грейс_прибытия_ноль_отключает_неуязвимость() -> void:
	_boot(true, {"arrival_grace_ticks": 0})
	var a := await _join("tok_a")
	await _advance(0.1)
	assert_bool(_node._arrival_immune(a, 2)).is_true()    # скрытые такты (entry_hidden_ticks) остаются неуязвимыми
	assert_bool(_node._arrival_immune(a, 3)).is_false()

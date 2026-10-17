extends Node
## Одиночная игра для тестеров без гарнитуры (docs/gamedesign/flat-playtest.md, docs/netrun-flat-windows.md): сервер мира и плоский клиент в одном процессе, один exe, без сети и Моста.
## Два поддерева с отдельным SceneMultiplayer (как в tests/teleport_proto_test.gd): сервер — «SoloServer», клиент — «SoloClient»; сеть — ENet по 127.0.0.1 (тот же путь кода, что на стенде и очках).
## Мост — FakeBridge с фикстурой data/solo (Призрак, RAM 14, демоны П5/П6; учебный узел, Архив → Серверная → Реактор). Сервер слушает только петлю: брандмауэр Windows не спрашивает.
## Забег: первый запуск — учебный узел; конец сессии (чистый выход, выброс, флэтлайн, аварийный выход) — сигнал run_finished; restart() поднимает
## сервер и клиент заново (фикстура читается с нуля), по умолчанию с Архива.

## Конец забега: result — причина выхода (ExitLogic.REASON_*), tutorial — попытка шла в учебном узле (журнал её помечает, анкету после неё не показывают).
signal run_finished(result: String, tutorial: bool)

## Сервер грузим по пути без class_name: в APK очков server/ нет (см. main.gd), в сборке для тестеров он есть.
const SERVER_SCRIPT := "res://server/world_server.gd"
const GRAPH := "res://data/solo/graph.json"
const FIXTURE := "res://data/solo/bridge_fixture.json"
## Фикстура текущей попытки (FIXTURE с профилем бегуна): сервер читает её с нуля на каждом restart().
const FIXTURE_RUN := "user://solo/bridge_fixture.json"
## Терминал, токен, сессия и профиль бегуна из фикстуры.
const TERMINAL := "t03"
const TOKEN := "t03:token-t03"
const SESSION := "s_fake000000000001"
const RUNNER_DOC := "r_alice"
const NODE_TUTORIAL := "node_00"
## Отладка: первый запуск сразу с Архива.
const SKIP_TUTORIAL_ARG := "--skip-tutorial"
const LOOPBACK := "127.0.0.1"
const PORT_FIRST := 49200
const PORT_LAST := 49299
## Сервер закрывает связь через NetServer.DISCONNECT_DELAY_SEC (0,3 с) после выхода: столько ждём, прежде чем убрать его поддерево.
const EXIT_SETTLE_SEC := 0.5

var port := 0
var server_root: Node
var client_root: Node
var server: Node
var flat: Node
## Текущая попытка идёт в учебном узле.
var tutorial := false
var _user_args := PackedStringArray()
var _finished := false
var _exit_ms := -1


## Первый свободный порт петли в диапазоне; 0 — не нашли. Проба открывает и закрывает ENet-сервер на этом адресе.
static func free_port(first: int = PORT_FIRST, last: int = PORT_LAST) -> int:
	for p in range(first, last + 1):
		var probe := ENetMultiplayerPeer.new()
		probe.set_bind_ip(LOOPBACK)
		if probe.create_server(p, 1) == OK:
			probe.close()
			return p
	return 0


## Аргументы сервера мира для одиночной игры.
static func server_args(port_: int, fixture: String = FIXTURE) -> PackedStringArray:
	return PackedStringArray(["--port=%d" % port_, "--bind=" + LOOPBACK, "--graph=" + GRAPH, "--bridge=fake", "--bridge-fixture=" + fixture,
		"--grace=3600", "--vault-requires-open=true"])


## Аргументы клиента: пользовательские (если есть) и адрес петли с токеном; их значения перекрывают netrun.cfg.
static func client_args(user_args: PackedStringArray, port_: int) -> PackedStringArray:
	var out := PackedStringArray(user_args)
	out.append_array(PackedStringArray(["--host=" + LOOPBACK, "--port=%d" % port_, "--token=" + TOKEN]))
	return out


## Профиль бегуна, как его ведёт настоящий Мост: новичок (tutorial_done=false) входит в учебный узел, остальные — в узел терминала
## (bridge_api.gd: «Мост сам подменяет node на учебный при первом входе»). FakeBridge этой подмены не делает, а сервер мира читает
## узел сессии из фикстуры уже при старте (снимок Моста) — поэтому правим разобранную фикстуру до запуска сервера. false — в фикстуре нет сессии или терминала.
static func apply_profile(fixture: Dictionary, with_tutorial: bool) -> bool:
	var s: Variant = (fixture.get("sessions", {}) as Dictionary).get(SESSION)
	var t: Variant = (fixture.get("terminals", {}) as Dictionary).get(TERMINAL)
	if not (s is Dictionary and t is Dictionary):
		return false
	(s as Dictionary)["node"] = NODE_TUTORIAL if with_tutorial else str((t as Dictionary).get("node", ""))
	var r: Variant = (fixture.get("runners", {}) as Dictionary).get(RUNNER_DOC)
	if r is Dictionary:
		(r as Dictionary)["tutorial_done"] = not with_tutorial
	return true


## Фикстура попытки: data/solo с профилем бегуна, записанная в user:// (папка программы бывает закрыта на запись). "" — не вышло.
static func write_fixture(with_tutorial: bool, path: String = FIXTURE_RUN) -> String:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (parsed is Dictionary) or not apply_profile(parsed, with_tutorial):
		push_error("[netrun-solo] фикстура %s не читается или в ней нет сессии %s / терминала %s" % [FIXTURE, SESSION, TERMINAL])
		return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("[netrun-solo] не записать %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	out.store_string(JSON.stringify(parsed, "  "))
	out.close()
	return path


## Первый запуск: учебный узел (with_tutorial), если в аргументах нет --skip-tutorial.
func start(args: PackedStringArray, with_tutorial: bool = true) -> bool:
	_user_args = args
	return _launch(with_tutorial and not (SKIP_TUTORIAL_ARG in args))


## Новая попытка без перезапуска exe: остановить сервер и клиент, поднять заново на новом порту. По умолчанию — с Архива
## (учебный пройден, tutorial_done), with_tutorial — снова учебный узел.
func restart(with_tutorial: bool = false) -> bool:
	await stop()
	return _launch(with_tutorial)


## Остановить попытку: клиент прощается и закрывает сокет, сервер закрывает свой, оба поддерева уходят; порт свободен.
func stop() -> void:
	_finished = true   # остановка — не конец забега: run_finished не шлём
	if _exit_ms >= 0:
		var left := EXIT_SETTLE_SEC - (Time.get_ticks_msec() - _exit_ms) / 1000.0
		if left > 0.0:
			await get_tree().create_timer(left).timeout   # сервер ещё отключает игрока после выхода (сопрограмма в NetServer)
	var proto := _proto()
	if proto != null and proto.net != null:
		proto.net.stop_reconnect()
		await proto.net.drop()
	if server != null and is_instance_valid(server) and server.get("net") != null:
		var mp := (server.net as Node).multiplayer as SceneMultiplayer
		if mp != null and mp.multiplayer_peer != null:
			mp.multiplayer_peer.close()
		server.net.stop_net()
	for r: Node in [client_root, server_root]:
		if r != null and is_instance_valid(r):
			get_tree().set_multiplayer(null, r.get_path())
			remove_child(r)
			r.free()
	server_root = null
	client_root = null
	server = null
	flat = null


func _launch(with_tutorial: bool) -> bool:
	var next := free_port(port + 1) if port > 0 and port < PORT_LAST else 0
	port = next if next != 0 else free_port()   # новый порт на каждую попытку: запоздалый пакет прошлой попытки в новую не попадёт
	if port == 0:
		push_error("[netrun-solo] нет свободного порта %d–%d на %s" % [PORT_FIRST, PORT_LAST, LOOPBACK])
		return false
	var fixture := write_fixture(with_tutorial)
	if fixture.is_empty():
		return false
	tutorial = with_tutorial
	_finished = false
	_exit_ms = -1
	server_root = Node.new()
	server_root.name = "SoloServer"
	add_child(server_root)
	get_tree().set_multiplayer(SceneMultiplayer.new(), server_root.get_path())
	client_root = Node.new()
	client_root.name = "SoloClient"
	add_child(client_root)
	get_tree().set_multiplayer(SceneMultiplayer.new(), client_root.get_path())
	var server_script: GDScript = load(SERVER_SCRIPT)
	server = server_script.new()
	server.name = "WorldServer"
	server_root.add_child(server)
	server.call("start", server_args(port, fixture))
	if server.get("net") != null:
		server.net.exit_event.connect(_on_exit)
	flat = preload("res://client/flat_stub.gd").new()
	client_root.add_child(flat)
	flat.start(client_args(_user_args, port))
	var proto := _proto()
	if proto != null and proto.net != null:
		proto.net.reconnect_gave_up.connect(func(): _finish(ExitLogic.REASON_CONNECTION_LOST))
	print("[netrun-solo] сервер и клиент в одном процессе, порт ", port, ", учебный узел" if with_tutorial else ", с Архива")
	return true


func _proto() -> ProtoClient:
	return flat.get_node_or_null("Proto") as ProtoClient if flat != null and is_instance_valid(flat) else null


## Выход сессии на сервере мира (чистый, выброс ICE, флэтлайн, аварийный выход): забег окончен.
func _on_exit(ev: Dictionary) -> void:
	if str(ev.get("session", "")) == SESSION:
		_finish(str(ev.get("reason", "")))


func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_exit_ms = Time.get_ticks_msec()
	print("[netrun-solo] забег окончен: ", reason, " (учебный узел)" if tutorial else "")
	run_finished.emit(reason, tutorial)

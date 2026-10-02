class_name WorldServer
extends Node
## Сервер мира (каркас G0): живёт без экрана, выходит по сигналу или по `--exit-after=<секунды>`.
## Сеть — NetServer (V2); логика мира — в следующих задачах.

signal stopped

var _exit_after: float = -1.0
var _elapsed: float = 0.0
var net: NetServer
## Мост: FakeBridge (фикстура, по умолчанию) или BridgeClient (WebSocket). null — токены из --tokens (V2).
var bridge: BridgeApi
## Серый узел node_07 (N7): ICE, trace, демоны, шард, выход.
var node: GrayNode
## Граф узлов (по умолчанию; `--graph=<путь>` — другой файл, `--single-node` — прежний одиночный узел): узлы из data/graph.json с тоннелями.
var graph_world: GraphWorld
## Состояние очков -> Мост (P6).
var beat_relay: TerminalBeatRelay


func start(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--exit-after="):
			_exit_after = float(a.trim_prefix("--exit-after="))
	print("[netrun-server] запущен, Godot ", Engine.get_version_info().string)
	var cfg := NetConfig.from_args(args)
	net = NetServer.new()
	net.name = "Net"
	add_child(net)
	bridge = make_bridge(args, cfg)
	if bridge != null:
		bridge.start()
	net.start(cfg, bridge if bridge != null else DictTokenVerifier.new(cfg.tokens))
	if bridge != null:
		beat_relay = TerminalBeatRelay.new(net, bridge)
	var graph := load_graph(args)
	if graph != null:
		graph_world = GraphWorld.new()
		graph_world.name = "GraphWorld"
		add_child(graph_world)
		graph_world.start(net, bridge, graph)
	else:
		node = GrayNode.new()
		node.name = "GrayNode"
		add_child(node)
		node.start(net, bridge)
	set_process(true)


## Граф узлов: по умолчанию data/graph.json, `--graph=<путь>` — другой файл, `--single-node` — без графа. null — одиночный режим
## или граф не прошёл проверку (ошибки в журнал, сервер работает одним серым узлом: лучше один узел, чем ни одного).
static func load_graph(args: PackedStringArray) -> NodeGraph:
	var path := NodeGraph.DEFAULT_PATH
	for a in args:
		if a == "--single-node":
			return null
		elif a.begins_with("--graph="):
			path = a.trim_prefix("--graph=")
	var g := NodeGraph.load_file(path)
	var errs := g.errors()
	if not errs.is_empty():
		for e in errs:
			push_error("[netrun-server] граф %s: %s" % [path, e])
		return null
	return g


## `--bridge=fake` (по умолчанию) | `--bridge=ws://хост:порт/netrun/v1`; ключ роли world — `--bridge-key=` или NETRUN_KEY_WORLD.
## Старый путь `--tokens=` без `--bridge=` остаётся (словарь токен -> сессия, без Моста). Фикстура фейка — `--bridge-fixture=`.
static func make_bridge(args: PackedStringArray, cfg: NetConfig) -> BridgeApi:
	var spec := ""
	var key := OS.get_environment("NETRUN_KEY_WORLD")
	var fixture := FakeBridge.DEFAULT_FIXTURE
	for a in args:
		if a.begins_with("--bridge="):
			spec = a.trim_prefix("--bridge=")
		elif a.begins_with("--bridge-key="):
			key = a.trim_prefix("--bridge-key=")
		elif a.begins_with("--bridge-fixture="):
			fixture = a.trim_prefix("--bridge-fixture=")
	if spec.is_empty():
		if not cfg.tokens.is_empty():
			return null
		spec = "fake"
	if spec == "fake":
		return FakeBridge.new(fixture)
	if spec.begins_with("ws://") or spec.begins_with("wss://"):
		var url := spec if spec.count("/") > 2 else spec + "/netrun/v1"
		return BridgeClient.new(url, key)
	push_error("[netrun-server] --bridge= принимает fake или ws://хост:порт, получено «%s»" % spec)
	return FakeBridge.new(fixture)


func _process(delta: float) -> void:
	if bridge != null:
		bridge.poll()
	_elapsed += delta
	if _exit_after >= 0.0 and _elapsed >= _exit_after:
		stop("по таймеру --exit-after")


func stop(reason: String) -> void:
	set_process(false)
	print("[netrun-server] остановка: ", reason)
	stopped.emit()
	get_tree().quit()


# SIGINT/SIGTERM на Unix Godot приводит к закрытию окна (в headless — тоже).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop("сигнал завершения")

extends Node
## Одиночная игра для тестеров без гарнитуры (docs/gamedesign/flat-playtest.md, docs/netrun-flat-windows.md): сервер мира и плоский клиент в одном процессе, один exe, без сети и Моста.
## Два поддерева с отдельным SceneMultiplayer (как в tests/teleport_proto_test.gd): сервер — «SoloServer», клиент — «SoloClient»; сеть — ENet по 127.0.0.1 (тот же путь кода, что на стенде и очках).
## Мост — FakeBridge с фикстурой data/solo (Призрак, RAM 14, демоны П5/П6; Архив → Серверная → Реактор). Сервер слушает только петлю: брандмауэр Windows не спрашивает.

## Сервер грузим по пути без class_name: в APK очков server/ нет (см. main.gd), в сборке для тестеров он есть.
const SERVER_SCRIPT := "res://server/world_server.gd"
const GRAPH := "res://data/solo/graph.json"
const FIXTURE := "res://data/solo/bridge_fixture.json"
## Терминал и токен из фикстуры: вход в Архив.
const TOKEN := "t03:token-t03"
const LOOPBACK := "127.0.0.1"
const PORT_FIRST := 49200
const PORT_LAST := 49299

var port := 0
var server_root: Node
var client_root: Node
var server: Node
var flat: Node


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
static func server_args(port_: int) -> PackedStringArray:
	return PackedStringArray(["--port=%d" % port_, "--bind=" + LOOPBACK, "--graph=" + GRAPH, "--bridge=fake", "--bridge-fixture=" + FIXTURE,
		"--grace=3600", "--vault-requires-open=true"])


## Аргументы клиента: пользовательские (если есть) и адрес петли с токеном; их значения перекрывают netrun.cfg.
static func client_args(user_args: PackedStringArray, port_: int) -> PackedStringArray:
	var out := PackedStringArray(user_args)
	out.append_array(PackedStringArray(["--host=" + LOOPBACK, "--port=%d" % port_, "--token=" + TOKEN]))
	return out


func start(args: PackedStringArray) -> bool:
	port = free_port()
	if port == 0:
		push_error("[netrun-solo] нет свободного порта %d–%d на %s" % [PORT_FIRST, PORT_LAST, LOOPBACK])
		return false
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
	server.call("start", server_args(port))
	flat = preload("res://client/flat_stub.gd").new()
	client_root.add_child(flat)
	flat.start(client_args(args, port))
	print("[netrun-solo] сервер и клиент в одном процессе, порт ", port)
	return true

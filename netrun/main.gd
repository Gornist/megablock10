extends Node
## Точка входа: по метке сборки и аргументам выбирает сервер, клиент или плоскую сборку.
## Аргументы пользователя — после `--`, например: godot --headless --path netrun -- --exit-after=5

## Сервер и бот — по пути, без class_name: в APK очков нет server/ и tests/ (export_presets.cfg, exclude_filter), и ссылка
## на их глобальные классы (WorldServer, BotClient) ломала разбор main.gd на Pico 4 — клиент не стартовал (2026-10-04).
## Сторож — tests/client_export_test.gd.
const SERVER_SCRIPT := "res://server/world_server.gd"
const BOT_SCRIPT := "res://tests/bot/bot_client.gd"


func _ready() -> void:
	var features := {
		"dedicated_server": OS.has_feature("dedicated_server"),
		"android": OS.has_feature("android"),
	}
	# Без экрана (godot --headless) режим по умолчанию — сервер, пока не указано иное.
	var args := OS.get_cmdline_user_args()
	# Бот из командной строки (скрипт live_run.sh): без сцены, свой выход по итогу сценария.
	for a in args:
		if a.begins_with("--bot="):
			run_bot(args, a.trim_prefix("--bot="))
			return
	var mode := RunMode.detect(features, args)
	if DisplayServer.get_name() == "headless" and not ("--flat" in args or "--client" in args):
		mode = RunMode.Mode.SERVER
	match mode:
		RunMode.Mode.SERVER:
			var server_script: GDScript = load(SERVER_SCRIPT)
			var s: Node = server_script.new()
			s.name = "WorldServer"
			add_child(s)
			s.call("start", args)
		RunMode.Mode.CLIENT:
			var c := preload("res://client/client_stub.gd").new()
			add_child(c)
			c.start(args)
		RunMode.Mode.FLAT:
			var f := preload("res://client/flat_stub.gd").new()
			add_child(f)
			f.start(args)


## `--bot=ghost_run|exposed_run|black_run|graph_run` (+ `--bot-route=node_02,node_03`, `--bot-ghost`, `--host=`, `--port=`, `--token=`, `--bot-reconnect`, `--bot-hold=<с после шарда>`, `--bot-daemon=<id GHOST-демона>`, `--exit-after=`): бот проходит узел и выходит
## из процесса: код 0 — чистый выход, 1 — любой другой итог. Итог печатается строкой `[bot] итог: <result>`.
## Для стенда e2e со взломом: `--bot-give=<ключ телефона>` — отдать взятый шард контакту телефона; `--bot-force-breach` — проба отказа
## (просит взлом при «ОСТЫВАЕТ», печатает «[bot] взлом отклонён: <причина>» и выходит без шарда).
func run_bot(args: PackedStringArray, kind: String) -> void:
	var bot_script: GDScript = load(BOT_SCRIPT)
	var sc: Dictionary = bot_script.get_script_constant_map()["Scenario"]
	var scenarios := {"ghost_run": sc["GHOST_RUN"], "exposed_run": sc["EXPOSED_RUN"], "black_run": sc["BLACK_RUN"], "graph_run": sc["GRAPH_RUN"]}
	if not scenarios.has(kind):
		push_error("[bot] --bot= принимает ghost_run, exposed_run, black_run или graph_run, получено «%s»" % kind)
		get_tree().quit(2)
		return
	var bot = bot_script.new()  # без типа: класс BotClient в APK очков не входит
	bot.name = "Bot"
	bot.verbose = true
	bot.reconnect = "--bot-reconnect" in args
	for a in args:
		if a.begins_with("--bot-hold="):
			bot.hold_after_grab = float(a.trim_prefix("--bot-hold="))
		elif a.begins_with("--bot-daemon="):
			bot.ghost_daemon = a.trim_prefix("--bot-daemon=")
		elif a.begins_with("--bot-route="):  # graph_run: узлы через запятую, в которые пройти порталами; шард — в последнем
			for id in a.trim_prefix("--bot-route=").split(",", false):
				bot.route.append(id)
		elif a.begins_with("--bot-give="):
			bot.give_phone = a.trim_prefix("--bot-give=")
		elif a == "--bot-force-breach":
			bot.force_breach = true
		elif a == "--bot-ghost":
			bot.use_ghost = true
	add_child(bot)
	bot.finished.connect(func(r: String):
		print("[bot] итог: ", r, ", переподключений: ", bot.reconnects)
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0 if r == "clean" else 1))
	for a in args:
		if a.begins_with("--exit-after="):
			get_tree().create_timer(float(a.trim_prefix("--exit-after="))).timeout.connect(func():
				print("[bot] итог: timeout:exit-after")
				get_tree().quit(1))
	bot.start(NetConfig.from_args(args), scenarios[kind])

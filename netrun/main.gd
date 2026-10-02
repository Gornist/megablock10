extends Node
## Точка входа: по метке сборки и аргументам выбирает сервер, клиент или плоскую сборку.
## Аргументы пользователя — после `--`, например: godot --headless --path netrun -- --exit-after=5

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
			var s := WorldServer.new()
			s.name = "WorldServer"
			add_child(s)
			s.start(args)
		RunMode.Mode.CLIENT:
			var c := preload("res://client/client_stub.gd").new()
			add_child(c)
			c.start(args)
		RunMode.Mode.FLAT:
			var f := preload("res://client/flat_stub.gd").new()
			add_child(f)
			f.start(args)


## `--bot=ghost_run|exposed_run` (+ `--host=`, `--port=`, `--token=`, `--bot-reconnect`, `--bot-hold=<с после шарда>`, `--exit-after=`): бот проходит узел и выходит
## из процесса: код 0 — чистый выход, 1 — любой другой итог. Итог печатается строкой `[bot] итог: <result>`.
func run_bot(args: PackedStringArray, kind: String) -> void:
	var scenarios := {"ghost_run": BotClient.Scenario.GHOST_RUN, "exposed_run": BotClient.Scenario.EXPOSED_RUN}
	if not scenarios.has(kind):
		push_error("[bot] --bot= принимает ghost_run или exposed_run, получено «%s»" % kind)
		get_tree().quit(2)
		return
	var bot := BotClient.new()
	bot.name = "Bot"
	bot.verbose = true
	bot.reconnect = "--bot-reconnect" in args
	for a in args:
		if a.begins_with("--bot-hold="):
			bot.hold_after_grab = float(a.trim_prefix("--bot-hold="))
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

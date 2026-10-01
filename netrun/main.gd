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

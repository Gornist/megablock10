extends Node
## Плоская отладочная сборка: тестовая сцена и тот же XR-риг, управляемый клавиатурой и мышью.
## WASD — ход, Q/E — поворот рывками, ПКМ+мышь — осмотр, R — центровка, Esc 3 с — экстренное отключение.

func start(_args: PackedStringArray) -> void:
	var scene := preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	print("[netrun-flat] тестовая сцена, риг управляется мышью и клавиатурой")
	var cfg := NetConfig.from_args(_args)
	if not cfg.token.is_empty():
		var n := NetClient.new()
		n.name = "Net"
		add_child(n)
		n.start_client(cfg)
		scene.rig.exit_requested.connect(n.request_exit)

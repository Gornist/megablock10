extends Node
## Плоская отладочная сборка (каркас G0): разработка, боты, CI.

func start(_args: PackedStringArray) -> void:
	print("[netrun-flat] каркас плоской сборки")
	var cfg := NetConfig.from_args(_args)
	if not cfg.token.is_empty():
		var n := NetClient.new()
		n.name = "Net"
		add_child(n)
		n.start_client(cfg)

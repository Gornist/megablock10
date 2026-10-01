extends Node
## Клиент для Pico 4: сцена прототипа и XR-риг; без очков остаётся плоский риг, причина — в журнале.

func start(args: PackedStringArray) -> void:
	var p := ProtoClient.new()
	p.name = "Proto"
	add_child(p)
	p.start(args, "client", true)

extends Node
## Плоская отладочная сборка: сцена узла и тот же XR-риг, управляемый клавиатурой и мышью.
## WASD — ход, Q/E — поворот рывками, ПКМ+мышь — осмотр, R — центровка, Esc 3 с — экстренное отключение,
## F / ЛКМ — взять объект (просит сервер), 1–9 — применить демона из деки, X — выйти чисто на площадке выхода.
## Trace, ICE, перезарядки и звук приходят с сервера (ProtoClient).


func start(args: PackedStringArray) -> void:
	var p := ProtoClient.new()
	p.name = "Proto"
	add_child(p)
	p.start(args, "flat", false)
	if p.net != null:
		p.scene.rig.exit_requested.connect(p.net.request_exit)
	print("[netrun-flat] сцена узла, риг управляется мышью и клавиатурой")

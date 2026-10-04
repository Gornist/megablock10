extends Node3D
## Кадры настоящей сцены клиента (NodeView, IceView, AvatarView) — то же, что увидит игрок в узле.
## Запуск: godot --path netrun --display-driver wayland --resolution 1280x720 res://assets/preview_node.tscn -- --out=/каталог [--tier=HARD] [--only=a,b]
## Без аргумента --only снимает все кадры. Для просмотра ассетов вне клиента есть preview_capture.gd (assets/tools/pipeline.sh).

var _out := "/tmp/node_shots"
var _tier := "BASE"
var _only: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tier="):
			_tier = a.substr(7)
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var view := NodeView.new()
	add_child(view)
	view.set_tier(_tier)
	var shards: Array = []
	for i in NodeLayout.SHARD_SLOTS.size():
		var p: Vector3 = NodeLayout.SHARD_SLOTS[i]
		shards.append({"id": "s%d" % i, "p": [p.x, p.y, p.z], "ready": i != 2})
	view.set_vaults(shards)
	var portals: Array = []
	for i in NodeLayout.PORTAL_SLOTS.size():
		var q: Vector3 = NodeLayout.PORTAL_SLOTS[i]
		portals.append({"to": "n%d" % i, "p": [q.x, q.z], "open": i != 2})
	view.set_portals(portals)
	view.set_dead_decks([[2.0, -3.0]])
	for i in shards.size():
		var shard := NodeAssets.instance(NodeAssets.prop_path("shard"))
		shard.position = Vector3(NodeLayout.SHARD_SLOTS[i].x, NodeLayout.SHARD_SLOTS[i].y, NodeLayout.SHARD_SLOTS[i].z)
		shard.visible = i != 2
		add_child(shard)
	var soft := IceView.new(false)
	soft.position = Vector3(-4, 0, -6)
	add_child(soft)
	var black := IceView.new(true)
	black.position = Vector3(4, 0, -12)
	add_child(black)
	black.apply_state(IceView.STATE_HUNT, false)
	for i in 3:
		var av := AvatarView.new()
		add_child(av)
		av.setup(i)
		av.position = Vector3(5.5 - i * 1.4, 0, -2.5 - i * 0.6)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	add_child(cam)
	var shots := [
		["spawn", Vector3(-1, 1.2, -1), Vector3(-1, 1.1, -9)],
		["overview", Vector3(15, 13, 8), Vector3(0, 0, -6)],
		["portal", Vector3(-1, 1.2, -1), Vector3(-5, 1.2, -1)],
		["vault", Vector3(-1, 1.2, -5), Vector3(-1, 0.8, -9)],
		["ice", Vector3(0, 1.2, -3), Vector3(0, 1.4, -9)],
		["black", Vector3(2, 1.2, -6), Vector3(4, 1.6, -12)],
		["exit", Vector3(1, 1.2, -4), Vector3(4, 1.0, 1)],
		["up", Vector3(-1, 1.2, -6), Vector3(-1, 6.0, -9)],
	]
	for sh in shots:
		if not _only.is_empty() and not _only.has(sh[0]):
			continue
		cam.look_at_from_position(sh[1], sh[2])
		for k in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, sh[0]])
		print("кадр ", sh[0])
	var info := func(k): return RenderingServer.get_rendering_info(k)
	print("вызовов отрисовки=%d примитивов=%d" % [info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), info.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()

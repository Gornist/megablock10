extends Node3D
## Кадры рук в комнате (HandView): открытая ладонь, кулак, указание, захват, вид вблизи. Запуск на дисплее devbox отдельным процессом:
## godot --path netrun --display-driver wayland --resolution 1280x720 res://assets/preview_hands.tscn -- --out=/каталог [--only=a,b]

var _out := "/tmp/hand_shots"
var _only: Array = []
var _black := false  # --black: без комнаты, только руки на тёмном фоне


func _palm(pos: Vector3, pitch_deg: float, yaw_deg: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)), pos)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--black":
			_black = true
		elif a == "--noglitch":  # прежние круглые точки для сравнения
			HandView.glitch_sprite = false
		elif a.begins_with("--glitch-scale="):
			HandView.glitch_scale = float(a.substr(15))
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if not _black:
		var view := NodeView.new()
		add_child(view)
		view.set_tier("BASE")
	var origin := Node3D.new()
	origin.name = "RigStandIn"
	add_child(origin)
	var right := HandView.new(false)
	var left := HandView.new(true)
	origin.add_child(right)
	origin.add_child(left)
	var deck := DeckPanel.new()  # дека на запястье левой руки, как её носит WorldUI в VR
	deck.scale = Vector3.ONE * WorldUI.WRIST_DECK_SCALE
	left.wrist_anchor.add_child(deck)
	deck.set_deck({"daemons": [{"id": "ghost_1", "name": "Призрак", "cooldown_left": 0.0}, {"id": "jitter_1", "name": "Дрожь", "cooldown_left": 30.0}], "selected": "ghost_1"})
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	add_child(cam)
	var open := {}
	var fist := {"thumb": 1.0, "index": 1.0, "middle": 1.0, "ring": 1.0, "little": 1.0}
	var point := {"thumb": 0.8, "index": 0.0, "middle": 1.0, "ring": 1.0, "little": 1.0}
	var hold := HandSkeleton.curls_from_inputs(0.15, 0.55)
	var shots := [
		["open", Vector3(-1, 1.2, -1), Vector3(-1, 1.0, -3), open, open, 0.0],
		["fist", Vector3(-1, 1.2, -1), Vector3(-1, 1.0, -3), fist, fist, 0.0],
		["point", Vector3(-1, 1.2, -1), Vector3(-1, 1.0, -3), point, hold, 0.0],
		["close", Vector3(-1, 1.12, -1.15), Vector3(-1, 1.0, -1.5), hold, open, 0.0],
		["macro", Vector3(-0.9, 1.12, -1.3), Vector3(-0.85, 1.0, -1.45), hold, hold, 0.0],
		["deck", Vector3(-1.05, 1.5, -1.0), Vector3(-1.15, 0.98, -1.5), open, hold, 0.0],
		["m_open", Vector3(-0.83, 1.42, -1.0), Vector3(-0.83, 0.98, -1.45), open, open, 0.0],
		["m_fist", Vector3(-0.83, 1.42, -1.0), Vector3(-0.83, 0.98, -1.45), fist, fist, 0.0],
		["m_point", Vector3(-0.83, 1.42, -1.0), Vector3(-0.83, 0.98, -1.45), point, hold, 0.0],
		["side", Vector3(-0.65, 1.1, -1.4), Vector3(-1, 1.0, -1.45), hold, hold, 0.0],
	]
	for sh in shots:
		if not _only.is_empty() and not _only.has(sh[0]):
			continue
		var rc: Dictionary = sh[3]
		var lc: Dictionary = sh[4]
		var base := Vector3(-1, 0.98, -1.45)
		var rp := HandSkeleton.pose(rc, false)
		var lp := HandSkeleton.pose(lc, true)
		var rx := _palm(base + Vector3(0.17, 0, 0), 8.0, -8.0)
		var lx := _palm(base + Vector3(-0.17, 0, 0), 8.0, 8.0)
		right.pose_source = func():
			var o := PackedVector3Array()
			for p in rp:
				o.append(rx * p)
			return o
		left.pose_source = func():
			var o := PackedVector3Array()
			for p in lp:
				o.append(lx * p)
			return o
		cam.look_at_from_position(sh[1], sh[2])
		for k in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, sh[0]])
		print("кадр ", sh[0])
	var info := func(k): return RenderingServer.get_rendering_info(k)
	print("вызовов отрисовки=%d" % info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	get_tree().quit()

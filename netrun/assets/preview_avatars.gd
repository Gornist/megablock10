extends Node3D
## Кадры чужих нетраннеров (AvatarView с позой тела: голова и две руки) в комнате: четверо разного цвета в разных позах, вид спереди, сбоку, вблизи и из-за колонны.
## Запуск на дисплее devbox: godot --path netrun --display-driver wayland --resolution 1280x720 res://assets/preview_avatars.tscn -- --out=/каталог

var _out := "/tmp/avatar_shots"
const C := Vector3(0, 0, -6)  # центр комнаты (NodeLayout.ROOM_CENTER): все положения ниже — от него
var _avatars: Array = []  # [AvatarView, AvatarPose]: в игре поза приходит ~20 раз/с, здесь повторяется каждый кадр


func _process(_d: float) -> void:
	for a in _avatars:
		(a[0] as AvatarView).apply_pose(a[1])


func _pose(head_pos: Vector3, yaw: float, l: Vector3, r: Vector3, lc: Vector2, rc: Vector2) -> AvatarPose:
	var p := AvatarPose.new()
	p.head = Transform3D(Basis(Vector3.UP, yaw), head_pos)
	var b := Basis(Vector3.UP, yaw)
	p.set_hand(AvatarPose.LEFT, Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(-30.0)), l), lc.x, lc.y)
	p.set_hand(AvatarPose.RIGHT, Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(-30.0)), r), rc.x, rc.y)
	return p


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var view := NodeView.new()
	add_child(view)
	view.set_tier("BASE")
	var poses := [
		[Vector3(-1.4, 0, 0.0), _pose(Vector3(0, 1.62, 0), 0.0, Vector3(-0.28, 1.05, -0.3), Vector3(0.28, 1.05, -0.3), Vector2(0.2, 0.5), Vector2(0.2, 0.5))],
		[Vector3(-0.4, 0, -0.9), _pose(Vector3(0, 1.58, 0), 0.5, Vector3(-0.3, 1.3, -0.35), Vector3(0.3, 0.95, -0.4), Vector2(0.0, 0.0), Vector2(1.0, 1.0))],
		[Vector3(0.7, 0, 0.3), _pose(Vector3(0, 1.7, 0), -0.4, Vector3(-0.25, 1.5, -0.3), Vector3(0.25, 1.5, -0.3), Vector2(0.0, 0.0), Vector2(0.0, 0.0))],
		[Vector3(1.6, 0, -0.8), _pose(Vector3(0, 1.55, 0), 2.6, Vector3(-0.25, 1.0, -0.3), Vector3(0.28, 1.1, -0.35), Vector2(0.6, 0.9), Vector2(0.1, 0.2))],
	]
	for i in poses.size():
		var av := AvatarView.new()
		add_child(av)
		av.setup(i)
		av.position = poses[i][0] + C
		_avatars.append([av, poses[i][1]])
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.current = true
	add_child(cam)
	var shots := [
		["front", Vector3(0.1, 1.5, 3.0), Vector3(0.1, 1.2, -0.4)],
		["side", Vector3(-3.6, 1.6, 0.4), Vector3(0.1, 1.2, -0.3)],
		["close", Vector3(-1.0, 1.55, 1.1), Vector3(-1.4, 1.4, 0.0)],
		["face", Vector3(-1.4, 1.62, 0.9), Vector3(-1.4, 1.5, 0.0)],
		["mid", Vector3(-0.6, 1.5, 2.0), Vector3(-0.5, 1.3, -0.4)],
		["high", Vector3(0.2, 2.8, 2.6), Vector3(0.1, 1.2, -0.4)],
		["far", Vector3(0.1, 1.5, 6.5), Vector3(0.1, 1.2, -0.4)],
	]
	for sh in shots:
		cam.look_at_from_position(sh[1] + C, sh[2] + C)
		for k in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, sh[0]])
		print("кадр ", sh[0])
	var info := func(k): return RenderingServer.get_rendering_info(k)
	print("вызовов отрисовки=%d" % info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	get_tree().quit()

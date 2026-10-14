extends Node3D
## Вид тревоги узла по уровням 0–4 (AssetMaterials.alarm_background + set_alarm): один и тот же кадр окружения (плита пола, колонны, ворота, будка Стража) на пяти уровнях.
## Запуск: netrun/tools/dev.sh shot res://assets/preview_alarm.tscn  (кадры alarm_0 … alarm_4; уровень 3 снят в начале такта — пульс на пике)

var _out := "/tmp/alarm_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var room := Node3D.new()
	add_child(room)
	room.add_child(NodeAssets.instance(NodeAssets.env_path("floor_slab_16"), "BASE"))
	for x in [-2.0, 2.0]:
		var p := NodeAssets.instance(NodeAssets.env_path("pillar"), "BASE")
		p.position = Vector3(x, 0, -4.0)
		room.add_child(p)
	var gate := NodeAssets.instance(NodeAssets.env_path("lockdown_gate"), "")
	gate.position = Vector3(0, 0, -6.5)
	room.add_child(gate)
	var booth := NodeAssets.instance("res://assets/models/ice/guard_booth.glb")
	booth.position = Vector3(3.5, 0, -2.0)
	add_child(booth)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.2, 3.0), Vector3(0.0, 1.0, -5.0))
	for lvl in 5:
		env.background_color = AssetMaterials.alarm_background(lvl, 0.0)
		AssetMaterials.set_alarm(room, lvl, "BASE")
		for k in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/alarm_%d.png" % [_out, lvl])
		print("кадр alarm_", lvl)
	get_tree().quit()

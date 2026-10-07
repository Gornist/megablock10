extends Node3D
## Кадры телеграфа такта (RigTestScene.show_tick_demo): свет зрения ICE на полу, стрелки, глаз, рамка прицела по прогнозу.
## Запуск: netrun/tools/dev.sh shot res://tests/tick_demo_preview.tscn  (кадры: top — сверху наискосок, eye — глазами игрока)

var _out := "/tmp/tick_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	scene.show_tick_demo()
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	await _shot(cam, "top", Vector3(0.5, 2.6, 2.0), Vector3(0.0, 0.3, -6.0))   # под потолком (5 м): сверху потолок закрывает пол; обе колонны по бокам прохода
	scene.rig.camera.current = true
	scene.rig.camera.rotation = Vector3(deg_to_rad(-22.0), 0.0, 0.0)
	await _shot(null, "eye", Vector3.ZERO, Vector3.ZERO)
	get_tree().quit()


func _shot(cam: Camera3D, name_: String, pos: Vector3, look: Vector3) -> void:
	if cam != null:
		cam.look_at_from_position(pos, look)
		cam.current = true
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])

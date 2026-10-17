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
	# П6-6 (б): тревога 2–4 у игрока — свет кромок и пола в радиусе вокруг него уходит в тревожный цвет; игрок стоит на (0, 0, −1): колонны и ворота дальше за ним
	for lvl in [2, 3, 4]:
		env.background_color = AssetMaterials.alarm_background(lvl, 0.0)
		AssetMaterials.set_alarm(room, lvl, "BASE")
		AssetMaterials.set_alarm_focus(Vector3(0.0, 0.0, -1.0), lvl)
		for k in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/focus_%d.png" % [_out, lvl])
		print("кадр focus_", lvl)
	# П6-6 (г): ожог — красная вспышка по краям зрения (квад на камере, как в DangerCue); уровень 0 — «до», 1,0 — старт вспышки, 0,5 — середина спада
	AssetMaterials.set_alarm_focus(Vector3(0.0, 0.0, -1.0), 0)
	AssetMaterials.set_alarm(room, 0, "BASE")
	env.background_color = AssetMaterials.alarm_background(0, 0.0)
	var flash_mat := AssetMaterials.burn_flash_material(deg_to_rad(cam.fov) * 0.5 * 1.6)   # горизонтальная половина при 16:9 ≈ 1,6 × вертикальной
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = flash_mat
	var flash := MeshInstance3D.new()
	flash.mesh = quad
	flash.position = Vector3(0.0, 0.0, -0.24)
	flash.extra_cull_margin = 16.0
	cam.add_child(flash)
	for s in [0.0, 1.0, 0.5]:
		flash_mat.set_shader_parameter("strength", s)
		for k in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/burn_%d.png" % [_out, int(s * 10)])
		print("кадр burn_", int(s * 10))
	get_tree().quit()

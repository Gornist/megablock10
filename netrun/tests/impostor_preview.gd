extends Node3D
## Кадр импостора: слева живое облако хранилища, справа то же облако, переведённое в билборд (VolumeCloud._set_far). Билборд — запечённая
## текстура: он должен быть похож на облако, а не пустым прямоугольником. Запуск: netrun/tools/dev.sh shot res://tests/impostor_preview.tscn

var _out := "/tmp/impostor_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.024, 0.03)
	add_child(env)
	var path := "res://assets/models/props/vault.glb"
	VolumeRegistry.configure("all")
	for i in 2:
		var c := VolumeRegistry.spawn("vault", path, AssetMaterials.layer("hud_ok"), AABB())
		if c == null:
			push_error("нет облака хранилища")
			continue
		c.auto_lod = false
		c.position = Vector3(-1.2 + i * 2.4, 0.0, 0.0)
		add_child(c)
		if i == 1:
			c.impostor_m = 8.0
			c._set_far(true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(0, 1.4, 4.2), Vector3(0, 0.3, 0), Vector3.UP)
	cam.current = true
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/impostor.png" % _out)
	get_tree().quit()

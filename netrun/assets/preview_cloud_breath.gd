extends Node3D
## Дыхание облака (Б) по доле такта и отклик на приближение (AssetMaterials.set_cloud_breath / set_cloud_touch): хранилище и портал на плите пола.
## Кадры breath_0 … breath_3 — фаза такта 0 (тик, вдох), 0,25, 0,5, 0,75; touch_0 … touch_1 — без дыхания, источник справа от хранилища на 0,4 м и вплотную.
## Запуск: netrun/tools/dev.sh shot res://assets/preview_cloud_breath.tscn

var _out := "/tmp/cloud_breath_shots"
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = AssetMaterials.alarm_background(0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var room := Node3D.new()
	add_child(room)
	room.add_child(NodeAssets.instance(NodeAssets.env_path("floor_slab_16"), "BASE"))
	VolumeRegistry.configure("all")
	_spawn(room, "res://assets/models/props/vault.glb", "vault", Vector3(0, 0, -2.5), 0.0)
	_spawn(room, "res://assets/models/props/shard.glb", "shard", Vector3(1.6, 0.9, -1.6), 0.0)
	for px in [-2.2, 2.2]:  # колонны: облако на гранях (А) дышит и откликается так же, как объёмное (Б)
		var p := NodeAssets.instance(NodeAssets.env_path("pillar"), "BASE")
		p.position = Vector3(px, 0, -2.0)
		room.add_child(p)
	_cam = Camera3D.new()
	_cam.fov = 85.0
	_cam.current = true
	add_child(_cam)
	_cam.look_at_from_position(Vector3(0.0, 1.3, 0.4), Vector3(0.0, 0.9, -2.5))
	AssetMaterials.set_cloud_touch(get_tree(), [])
	for i in 4:
		AssetMaterials.set_cloud_breath(get_tree(), 0.25 * i)
		await _shot("breath_%d" % i)
	AssetMaterials.tune({"cloud_breath": 0.0})
	AssetMaterials.set_cloud_breath(get_tree(), 0.0)
	var v0 := Vector3(0.0, 1.0, -2.5)
	for i in 2:
		var src := v0 + Vector3(0.5, -0.2, 0.2) if i == 0 else Vector3(-1.7, 1.0, -0.9)   # 0 — у хранилища (Б), 1 — у левой колонны (А)
		AssetMaterials.set_cloud_touch(get_tree(), [Vector4(src.x, src.y, src.z, 0.8)])
		await _shot("touch_%d" % i)
	get_tree().quit()


func _spawn(parent: Node3D, glb: String, module: String, pos: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var model := NodeAssets.instance(glb, "")
	holder.add_child(model)
	var c := VolumeRegistry.spawn(module, glb, VolumeRegistry.color_of(module), AABB())
	if c != null:
		holder.add_child(c)


func _shot(label: String) -> void:
	for k in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
	print("кадр ", label)

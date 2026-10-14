extends Node3D
## Кадры Black ICE: базовый и пять видов (Гончая, Кракен, Ворон, Скорпион, Лич; ice.md §6.2) в ряд и логово 2×2 клетки (ice/black_lair).
## Запуск: netrun/tools/dev.sh shot res://assets/preview_black_ice.tscn  (по умолчанию облако (Б) выключено в сцене; `--volumetric=ice` включает его на моделях)

var _out := "/tmp/black_ice_shots"
const KINDS := ["black_ice", "black_ice_hound", "black_ice_kraken", "black_ice_raven", "black_ice_scorpion", "black_ice_lich"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--volumetric="):
			VolumeRegistry.configure(a.substr(13))
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = AssetMaterials.VOID_BG
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var slab := NodeAssets.instance(NodeAssets.env_path("floor_slab_16"), "BASE")
	add_child(slab)
	for i in KINDS.size():
		var m := NodeAssets.instance("res://assets/models/ice/%s.glb" % KINDS[i])
		m.position = Vector3(-7.5 + 3.0 * i, 0, 0)
		add_child(m)
		var cloud := VolumeRegistry.spawn("ice", "res://assets/models/ice/%s.glb" % KINDS[i], VolumeRegistry.color_of("ice"), AABB())
		if cloud != null:
			(m.find_child("Rig", true, false) as Node3D).add_child(cloud)
	var lair := NodeAssets.instance("res://assets/models/ice/black_lair.glb")
	lair.position = Vector3(0, 0, -6.0)
	for s in ["State_sleep", "State_waking", "State_empty"]:
		(lair.find_child(s, true, false) as Node3D).visible = s == "State_sleep"   # ровно одно состояние (как у клиента)
	add_child(lair)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.current = true
	add_child(cam)
	var shots := [
		["row", Vector3(0.0, 2.2, 8.0), Vector3(0.0, 1.5, 0.0)],
		["lair", Vector3(0.0, 3.0, 2.0), Vector3(0.0, 0.0, -5.0)],
		# профиль каждого вида (камера справа, фигура смотрит в −Z): грива, хвост, крылья, корона читаются сбоку
		["side_hound", Vector3(-4.5 + 4.0, 1.7, 0.0), Vector3(-4.5, 1.6, 0.0)],
		["side_kraken", Vector3(-1.5 + 4.0, 1.7, 0.0), Vector3(-1.5, 1.4, 0.0)],
		["side_raven", Vector3(1.5 + 4.0, 1.9, 0.0), Vector3(1.5, 1.8, 0.0)],
		["side_scorpion", Vector3(4.5 + 4.0, 1.9, 0.0), Vector3(4.5, 1.8, 0.0)],
	]
	for sh in shots:
		cam.look_at_from_position(sh[1], sh[2])
		for k in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, sh[0]])
		print("кадр ", sh[0])
	get_tree().quit()

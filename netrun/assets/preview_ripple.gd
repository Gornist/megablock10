extends Node3D
## Рябь облака во времени: одна и та же комната со статичной камерой, два кадра через 0,1 с и средняя разница яркости между ними (0 — картинка неподвижна).
## Сравнивает умолчание ручки dust_fps (кадр ячейки постоянный) со старым 10 кадров/с (владелец 17.10: «частицы жутко рябят»). Кадры <ключ>_a/_b — в /tmp/ripple_shots.
## Запуск: netrun/tools/dev.sh shot res://assets/preview_ripple.tscn   (число «рябь» печатается в журнал)

var _out := "/tmp/ripple_shots"
var _room: Node3D
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
	_cam = Camera3D.new()
	_cam.fov = 85.0
	_cam.current = true
	add_child(_cam)
	_cam.look_at_from_position(Vector3(0.0, 1.3, 0.4), Vector3(0.0, 0.8, -2.5))
	VolumeRegistry.configure("all")
	for fps in [10.0, 3.0, 0.0]:
		AssetMaterials.tune({"dust_fps": fps})
		_build()
		var key := "fps%d" % int(fps)
		var a := await _shot(key + "_a")
		await get_tree().create_timer(0.1).timeout
		var b := await _shot(key + "_b")
		print("рябь %s: %.3f (средняя разница яркости 0…255 между кадрами через 0,1 с)" % [key, _diff(a, b)])
	AssetMaterials.reset_tuning()
	get_tree().quit()


func _build() -> void:
	if _room != null:
		_room.queue_free()
	_room = Node3D.new()
	add_child(_room)
	_room.add_child(NodeAssets.instance(NodeAssets.env_path("floor_slab_16"), "BASE"))
	var v := NodeAssets.instance("res://assets/models/props/vault.glb", "")
	v.position = Vector3(0, 0, -2.5)
	_room.add_child(v)
	for px in [-2.2, 2.2]:
		var p := NodeAssets.instance(NodeAssets.env_path("pillar"), "BASE")
		p.position = Vector3(px, 0, -2.0)
		_room.add_child(p)


func _shot(label: String) -> Image:
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, label])
	return img


func _diff(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	var n := mini(da.size(), db.size())
	var sum := 0
	for i in range(0, n, 4):
		sum += absi(int(da[i]) - int(db[i]))
	return float(sum) / float(maxi(n / 4, 1))

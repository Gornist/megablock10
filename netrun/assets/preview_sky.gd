extends Node3D
## Кадры клиента для приёмки вида «грань облака + небо купола» (владелец 20.10: «чёрный солид везде»): Фойе глазами игрока (кадр на глаз Pico 4), четыре позы —
## `close` (вплотную к грани колонны), `through` (через колонну на дальнюю), `horizon` (взгляд на горизонт), `hand` (рука у грани, отклик поверхности).
## Позы: close, through, base (стык колонны с полом), horizon, hand.
## Запуск: netrun/tools/dev.sh shot res://assets/preview_sky.tscn [--tune=cloud_sky=0,...] [--out=каталог]; кадры <поза>.png.

const EYE := Vector2i(1504, 1504)

var _out := "/tmp/sky_shots"
var _yaw := 0.0   # --yaw=градусы: поворот головы в позе horizon (проверка, что небо стоит в мире, а не едет с головой)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		elif a.begins_with("--tune="):
			var d := {}
			for kv in a.trim_prefix("--tune=").split(","):
				var p := kv.split("=")
				if p.size() == 2:
					d[p[0]] = p[1]
			AssetMaterials.tune(d)
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: Node3D = preload("res://client/world_scene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	var foyer := LayoutData.cached("foyer")
	scene.apply_node({"kind": "node", "node": "foyer", "title": "Фойе", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": [], "portals": [], "layout": foyer.name})
	scene.apply_state({"k": Time.get_ticks_msec() / 1000.0, "trace": 0.0, "level": 0, "cd": [], "ice": [], "bk": [], "sn": [], "tk": {"n": 4, "at": 0.0, "win": 5.0, "inh": 0, "mv": 0}})
	var rects: Array = []
	for pp: Vector3 in scene.view.pillar_positions():
		rects.append(Rect2(pp.x - 0.95, pp.z - 0.95, 1.9, 1.9))
	AssetMaterials.set_cloud_occluders(get_tree(), rects)   # основания колонн: пол вокруг редеет (как вызовет клиент)
	var vp := SubViewport.new()
	vp.size = EYE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var render := RenderConfig.new()
	render.apply_msaa(vp)
	vp.transparent_bg = true   # как у клиента на очках (слой деки позади)
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = EyePresets.FOV_DEG
	vp.add_child(cam)
	cam.current = true
	var pillars: Array[Vector3] = scene.view.pillar_positions()
	assert(not pillars.is_empty())
	# Колонна ближе всего к центру комнаты и вторая позади неё по линии «центр → колонна».
	var c: Vector3 = scene.view.room_center()
	var p0: Vector3 = pillars[0]
	for p in pillars:
		if Vector2(p.x - c.x, p.z - c.z).length() < Vector2(p0.x - c.x, p0.z - c.z).length():
			p0 = p
	var dir := Vector3(p0.x - c.x, 0.0, p0.z - c.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, -1)
	var eye_y := EyePresets.EYE_HEIGHT
	# 1. вплотную к грани: 0,7 м от поверхности колонны (грань 0,95 м от центра), взгляд на грань
	var face := p0 - dir * 0.95
	await _shot(cam, "close", face - dir * 0.7 + Vector3(0, eye_y, 0), face + Vector3(0, 1.0, 0))
	# 2. через колонну: камера на линии позади колонны (от центра), смотрит сквозь неё в центр комнаты и дальше
	await _shot(cam, "through", p0 - dir * 4.5 + Vector3(0, eye_y, 0), c + dir * -6.0 + Vector3(0, 1.0, 0))
	# 5. стык колонны с полом: камера в 2,2 м от грани, взгляд на основание (растушёвка у пола)
	await _shot(cam, "base", face - dir * 2.2 + Vector3(0, eye_y, 0), face + Vector3(0, 0.15, 0))
	# 3. горизонт: поза у спавна, взгляд ровно вперёд (к горизонту), небо в верхней половине кадра
	var hl := Vector3(0.0, 0.1, -43.0).rotated(Vector3.UP, deg_to_rad(_yaw))
	await _shot(cam, "horizon", Vector3(c.x, eye_y, c.z + 3.0), Vector3(c.x, eye_y, c.z + 3.0) + hl)
	# 4. рука у грани: источник отклика на грани колонны, камера в 1,1 м
	AssetMaterials.set_cloud_touch(get_tree(), [Vector4(face.x, 1.2, face.z, 0.5)])
	await _shot(cam, "hand", face - dir * 1.1 + Vector3(0, eye_y, 0), face + Vector3(0, 1.1, 0))
	get_tree().quit()


func _shot(cam: Camera3D, label: String, pos: Vector3, look: Vector3) -> void:
	cam.look_at_from_position(pos, look, Vector3.UP)
	for k in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := cam.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, label])
	print("кадр ", label)

extends Node3D
## Кадры Фойе (раскладка data/layouts/foyer.json) глазами клиента: колонны, хранилища с площадками, порталы, вход S, выход E,
## Страж со светом зрения (фокус/периферия) и стрелкой, рамка прицела по прогнозу.
## Запуск: netrun/tools/dev.sh shot res://tests/foyer_preview.tscn  (кадры: eye — глазами игрока на входе, top — сверху на всю комнату)

var _out := "/tmp/foyer_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	var foyer := LayoutData.cached("foyer")
	scene.apply_node(_foyer_info(foyer))
	var guard_cell := Vector2i(9, 9)   # блок (4; 4), лицом на юг, к входу: свет зрения накрывает площадку у входа и колонну
	var g := NodeGrid.center(guard_cell)
	var now := Time.get_ticks_msec() / 1000.0
	scene.apply_state({"k": now, "trace": 0.0, "level": 0, "cd": [], "ice": [
		{"id": "g1", "p": [g.x, 0.0, g.z], "f": [0.0, 1.0], "s": 1, "b": 0, "c": [guard_cell.x, guard_cell.y], "d": [0, 1], "st": 2, "nc": [11, 9], "nd": [1, 0], "aw": 3, "sc": 6},
	], "tk": {"n": 4, "at": now - 1.0, "win": 5.0, "inh": 0, "mv": 0}})
	var target := Vector2i(7, 11)   # впереди-слева от Стража: периферия его зрения
	scene.aim_visual_demo(scene.rig.global_position + Vector3(0.35, 0.8, -0.25), NodeGrid.center(target), TickForecast.threat(scene.rig.grid, scene.remote.intents(), target))
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	scene.rig.camera.current = true
	scene.rig.camera.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
	await _shot(null, "eye", Vector3.ZERO, Vector3.ZERO)
	_hide_ceilings(scene)
	# Сверху: потолок и дальние пласты прячем, иначе закрывают пол; «вверх» кадра — север (−Z).
	cam.look_at_from_position(Vector3(0.0, 21.0, -5.5), Vector3(0.0, 0.0, -5.5), Vector3(0.0, 0.0, -1.0))
	cam.current = true
	await _shot(cam, "top", Vector3.ZERO, Vector3.ZERO)
	# Крупнее: северная половина (хранилища, порталы, колонны) и южная (вход, выход, Страж).
	cam.look_at_from_position(Vector3(0.0, 11.0, -9.5), Vector3(0.0, 0.0, -9.5), Vector3(0.0, 0.0, -1.0))
	await _shot(cam, "north", Vector3.ZERO, Vector3.ZERO)
	cam.look_at_from_position(Vector3(0.0, 11.0, -2.5), Vector3(0.0, 0.0, -2.5), Vector3(0.0, 0.0, -1.0))
	await _shot(cam, "south", Vector3.ZERO, Vector3.ZERO)
	get_tree().quit()


## Событие node для Фойе: хранилища по слотам раскладки, порталы по номерам связей.
func _foyer_info(ld: LayoutData) -> Dictionary:
	var shards: Array = []
	for k in ld.vaults.size():
		var p: Vector3 = ld.vaults[k]["slot"]
		shards.append({"id": "foyer_pk%d" % k, "p": [p.x, p.y, p.z], "ready": true, "vault": "open"})
	var portals: Array = []
	for k in ld.portals.size():
		var q: Vector3 = ld.portals[k]
		portals.append({"to": "n%d" % k, "title": "Узел %d" % (k + 1), "tier": "BASE", "p": [q.x, q.z], "open": true})
	return {"kind": "node", "node": "foyer", "title": "Фойе", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS,
		"shards": shards, "portals": portals, "layout": ld.name}


func _hide_ceilings(scene: Node3D) -> void:
	for c in scene.view.get_node("Room").get_children():
		var n := str(c.name) + str(c.get_meta("asset", ""))   # варианты модулей получают имена @MultiMeshInstance3D@N — смотрим путь ассета
		if "ceiling" in n or "far_" in n or str(c.name) == "Horizon":
			(c as Node3D).visible = false


func _shot(cam: Camera3D, name_: String, _pos: Vector3, _look: Vector3) -> void:
	if cam != null:
		cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])

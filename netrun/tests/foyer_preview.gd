extends Node3D
## Кадры Фойе (раскладка data/layouts/foyer.json) глазами клиента: колонны, хранилища с площадками, порталы, вход S, выход E,
## Страж со светом зрения (фокус/периферия) и стрелкой, рамка прицела по прогнозу.
## Облако частиц у хранилищ и порталов: `--volumetric=vault,portal` (VolumeRegistry; точки сэмплируются по модели, если нет .points).
## Запуск: netrun/tools/dev.sh shot res://tests/foyer_preview.tscn  (кадры — по пресетам EyePresets: entry, north, south, vault_w глазами игрока; top, top_north, top_south сверху)
## Кадры глазами — 2160×2160 (на глаз Pico 4), msaa как в клиенте; A/B: `dev.sh shot res://tests/foyer_preview.tscn --msaa=0|2|4`

var _out := "/tmp/foyer_shots"
var _layout_name := "foyer"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--layout="):   # другая раскладка тем же набором кадров: --layout=server_room (Маяк и Датчик берутся из раскладки)
			_layout_name = a.substr(9)
		elif a.begins_with("--volumetric="):   # объёмные модули до построения узла (как [render] volumetric): --volumetric=vault,portal | all
			VolumeRegistry.configure(a.substr(13))
		elif a.begins_with("--tune="):  # ручки AssetMaterials до построения окружения (как [assets] в netrun.cfg): --tune=edge_soft=0.8,fringe_on=false
			var d := {}
			for kv in a.trim_prefix("--tune=").split(","):
				var p := kv.split("=")
				if p.size() == 2:
					d[p[0]] = p[1]
			AssetMaterials.tune(d)
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	var foyer := LayoutData.cached(_layout_name)
	scene.apply_node(_foyer_info(foyer))
	var guard_cell := Vector2i(9, 9)   # блок (4; 4), лицом на юг, к входу: свет зрения накрывает площадку у входа и колонну
	var g := NodeGrid.center(guard_cell)
	var now := Time.get_ticks_msec() / 1000.0
	scene.apply_state({"k": now, "trace": 0.0, "level": 0, "cd": [], "ice": [
		{"id": "g1", "p": [g.x, 0.0, g.z], "f": [0.0, 1.0], "s": 1, "b": 0, "c": [guard_cell.x, guard_cell.y], "d": [0, 1], "st": 2, "nc": [11, 9], "nd": [1, 0], "aw": 3, "sc": 6},
	], "bk": _beacons_state(foyer), "sn": _sensors_state(foyer), "tk": {"n": 4, "at": now - 1.0, "win": 5.0, "inh": 0, "mv": 0}})
	var target := Vector2i(7, 11)   # впереди-слева от Стража: периферия его зрения
	scene.aim_visual_demo(scene.rig.global_position + Vector3(0.35, 0.8, -0.25), NodeGrid.center(target), TickForecast.threat(scene.rig.grid, scene.remote.intents(), target))
	# Кадры — по общим пресетам камеры (shared/eye_presets.gd): теми же принимается окружение (assets/ARCHITECTURE.md, п. 18).
	# Кадры «глазами» — Viewport размером на один глаз Pico 4 и с тем же msaa_3d, что в клиенте (RenderConfig по умолчанию; --msaa=0|2|4 для A/B);
	# кадры сверху — окном, как раньше. Общий мир: SubViewport берёт World3D родителя.
	var render := RenderConfig.new()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--msaa="):
			var m := a.substr(7)
			if m in ["0", "2", "4"]:
				render.msaa = int(m)
			else:
				push_warning("--msaa=: допустимо 0, 2 или 4, получено «%s»" % m)
	var eye_vp := SubViewport.new()
	eye_vp.size = EyePresets.EYE_VIEWPORT
	eye_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render.apply_msaa(eye_vp)
	add_child(eye_vp)
	var eye_cam := Camera3D.new()
	eye_vp.add_child(eye_cam)
	var cam := Camera3D.new()
	add_child(cam)
	# Карта не 8×8 (--layout=server_room_hard10): центр, края и высота обзора — по раскладке; 8×8 — прежние пресеты Фойе.
	var sized: LayoutData = null if foyer.cols == NodeLayout.GRID and foyer.rows == NodeLayout.GRID else foyer
	for n: String in EyePresets.names():
		var p := EyePresets.get_preset(n, sized)
		var c := eye_cam if p["eye"] else cam
		c.fov = p["fov"]
		c.look_at_from_position(p["pos"], p["look"], p["up"])
		await _shot(c, n, eye_vp if p["eye"] else get_viewport())
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


## Поле bk state: Маяки раскладки в стартовом угле (как шлёт GrayNode.beacon_view).
func _beacons_state(ld: LayoutData) -> Array:
	var out: Array = []
	for bd: Dictionary in ld.beacons:
		var c: Vector2i = bd["cell"]
		var d: Vector2i = bd["start"]
		var i := TickBeacon.DIRS.find(d)
		var nd: Vector2i = TickBeacon.DIRS[posmod(i + 1, TickBeacon.DIRS.size())]
		out.append({"id": bd["id"], "c": [c.x, c.y], "d": [d.x, d.y], "nd": [nd.x, nd.y], "aw": 0, "r": float(TickBeacon.DEFAULTS["sight_cells"])})
	return out


## Поле sn state: Датчики раскладки включёнными.
func _sensors_state(ld: LayoutData) -> Array:
	var out: Array = []
	for sd: Dictionary in ld.sensors:
		var cells: Array = []
		for c: Vector2i in sd["cells"]:
			cells.append([c.x, c.y])
		out.append({"id": sd["id"], "c": cells, "on": 1, "bl": 0, "l": 2})
	return out


func _shot(cam: Camera3D, name_: String, vp: Viewport) -> void:
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s.png" % [_out, name_])

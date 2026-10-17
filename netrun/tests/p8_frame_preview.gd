extends Node3D
## Кадр узла со ВСЕМИ объектами и пронумерованными подписями (запрос Game, П8): вид сверху и вид с входа, справа легенда.
## Метки ставятся проекцией мировых координат объектов (раскладка + узлы NodeView) через камеру кадра; нет объекта в сцене — метки нет,
## а в легенду он попадает строкой «в сцене нет». Только разметка для разбора: игровых цветов не задаёт (подписи — свои, на кадре видны как плашки).
## Запуск: netrun/tools/dev.sh shot res://tests/p8_frame_preview.tscn [--layout=server_room_hard10]  → top.png, entry.png

var _out := "/tmp/p8_shots"
var _layout_name := "server_room"
var _scene: Node3D
var _cam: Camera3D
var _layer: CanvasLayer
var _marks: Array = []   # {n: int, text: String, pos: Vector3, off: Vector2}
var _legend: Array = []  # строки легенды


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--layout="):
			_layout_name = a.substr(9)
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = preload("res://client/rig_test_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame
	var ld := LayoutData.cached(_layout_name)
	_scene.apply_node(_node_info(ld))
	var now := Time.get_ticks_msec() / 1000.0
	_scene.apply_state({"k": now, "trace": 0.0, "level": 0, "cd": [], "ice": _guards(ld),
		"bk": _beacons(ld), "sn": _sensors(ld), "bo": _booths(ld),
		"tk": {"n": 4, "at": now - 1.0, "win": 5.0, "inh": 0, "mv": 0}})
	_collect(ld)
	_cam = Camera3D.new()
	add_child(_cam)
	_layer = CanvasLayer.new()
	add_child(_layer)
	var sized: LayoutData = null if ld.cols == NodeLayout.GRID and ld.rows == NodeLayout.GRID else ld
	var top := EyePresets.get_preset("top", sized)
	_hide_ceilings()
	var k := EyePresets.top_scale(sized)
	var shift := 7.0 * k  # комната — в левой части кадра, справа место под легенду
	_cam.fov = top["fov"]
	var look: Vector3 = top["look"] + Vector3(shift, 0.0, 0.0)
	_cam.look_at_from_position(Vector3(look.x, 19.5 * k, look.z), look, Vector3(0.0, 0.0, -1.0))
	await _shot("top", true)
	var e := EyePresets.get_preset("entry", sized)
	_cam.fov = 75.0
	_cam.look_at_from_position(e["pos"], e["look"], Vector3.UP)
	await _shot("entry", true)
	# Вид от северной стены на юг: кресло, вход S, выход и порталы за спиной входа (с входа их не видно)
	var c: Vector3 = top["look"]
	_cam.fov = 70.0
	_cam.look_at_from_position(Vector3(c.x, 4.5 * k, NodeLayout.ROOM_MIN.y + 1.0), Vector3(c.x, 0.0, ld.spawn.z + 1.0), Vector3.UP)
	await _shot("back", true)
	get_tree().quit()


func _node_info(ld: LayoutData) -> Dictionary:
	var shards: Array = []
	for k in ld.vaults.size():
		var p: Vector3 = ld.vaults[k]["slot"]
		shards.append({"id": "v%d" % k, "p": [p.x, p.y, p.z], "ready": true, "vault": "open"})
	var portals: Array = []
	for k in ld.portals.size():
		var q: Vector3 = ld.portals[k]
		if q != Vector3.INF:
			portals.append({"to": "n%d" % k, "title": "Узел %d" % (k + 1), "tier": "BASE", "p": [q.x, q.z], "open": true})
	return {"kind": "node", "node": "p8", "title": "П8", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS,
		"shards": shards, "portals": portals, "layout": ld.name}


func _guards(ld: LayoutData) -> Array:
	var out: Array = []
	for s: Dictionary in ld.sentries:
		var r: Array = s["route"]
		var c: Vector2i = r[0]["cell"]
		var nc: Vector2i = r[1]["cell"]
		var g := NodeGrid.center(c)
		var d: Vector2i = r[0].get("look", Vector2i(0, 1))
		out.append({"id": s["id"], "p": [g.x, 0.0, g.z], "f": [float(d.x), float(d.y)], "s": 1, "b": 0, "c": [c.x, c.y], "d": [d.x, d.y],
			"st": 2, "nc": [nc.x, nc.y], "nd": [d.x, d.y], "aw": 3, "sc": 6})
	return out


func _beacons(ld: LayoutData) -> Array:
	var out: Array = []
	for bd: Dictionary in ld.beacons:
		var c: Vector2i = bd["cell"]
		var d: Vector2i = bd["start"]
		var i := TickBeacon.DIRS.find(d)
		var nd: Vector2i = TickBeacon.DIRS[posmod(i + 1, TickBeacon.DIRS.size())]
		out.append({"id": bd["id"], "c": [c.x, c.y], "d": [d.x, d.y], "nd": [nd.x, nd.y], "aw": 0, "r": float(TickBeacon.DEFAULTS["sight_cells"])})
	return out


func _sensors(ld: LayoutData) -> Array:
	var out: Array = []
	for sd: Dictionary in ld.sensors:
		var cells: Array = []
		for c: Vector2i in sd["cells"]:
			cells.append([c.x, c.y])
		out.append({"id": sd["id"], "c": cells, "on": 1, "bl": 0, "l": 2})
	return out


func _booths(ld: LayoutData) -> Array:
	var out: Array = []
	for i in ld.booths.size():
		out.append({"id": "b%d" % (i + 1), "c": [ld.booths[i].x, ld.booths[i].y], "open": 0})
	return out


func _hide_ceilings() -> void:
	for c in _scene.view.get_node("Room").get_children():
		var n := str(c.name) + str(c.get_meta("asset", ""))
		if "ceiling" in n or "far_" in n or str(c.name) == "Horizon":
			(c as Node3D).visible = false


## Список меток по данным сцены (позиции читаются у самих узлов и у раскладки, а не выдумываются).
func _collect(ld: LayoutData) -> void:
	var view: NodeView = _scene.view
	var n := 0
	# 1–2 хранилища по кольцу, 3 площадки, 4 панели
	var has_outer := false
	var has_inner := false
	for v: Dictionary in ld.vaults:
		if str(v["ring"]) == "outer":
			has_outer = true
			_marks.append({"n": 1, "pos": v["slot"] + Vector3(0, 0.6, 0), "off": Vector2.ZERO})
		else:
			has_inner = true
			_marks.append({"n": 2, "pos": v["slot"] + Vector3(0, 0.6, 0), "off": Vector2.ZERO})
		_marks.append({"n": 3, "pos": v["pad"] + Vector3(0, 0.05, 0), "off": Vector2.ZERO})
	_legend.append("1  хранилище, кольцо outer (внешнее)" if has_outer else "1  хранилище outer — в раскладке нет")
	_legend.append("2  хранилище, кольцо inner (внутреннее)" if has_inner else "2  хранилище inner — в этой раскладке нет")
	_legend.append("3  площадка хранилища (hack_pad)")
	for id: String in view._panels:
		_marks.append({"n": 4, "pos": (view._panels[id] as Node3D).global_position + Vector3(0, 0.3, 0), "off": Vector2(0, 0)})
	_legend.append("4  корпус панели взлома (hack_panel)")
	for b: Dictionary in ld.beacons:
		_marks.append({"n": 5, "pos": NodeGrid.center(b["cell"]) + Vector3(0, 0.5, 0), "off": Vector2.ZERO})
	_legend.append("5  тумба Маяка (lighthouse_ice, 'O')" if not ld.beacons.is_empty() else "5  Маяк — в раскладке нет")
	for s: Dictionary in ld.sensors:
		var cells: Array = s["cells"]
		_marks.append({"n": 6, "pos": NodeGrid.center(cells[0]) + Vector3(0, 0.5, 0), "off": Vector2.ZERO})
		_marks.append({"n": 7, "pos": NodeGrid.center(cells[cells.size() - 1]) + Vector3(0, 0.1, 0), "off": Vector2(0, 26)})
	_legend.append("6  излучатель Датчика (sensor_ice)" if not ld.sensors.is_empty() else "6  Датчик — в раскладке нет")
	_legend.append("7  дальний конец луча Датчика (второй излучатель)")
	# 8 кресло (props/seat.glb) на входе, 9 вход S
	var seat: Node3D = view.seat_node() if view.has_method("seat_node") else null
	if seat != null and seat.visible:
		_marks.append({"n": 8, "pos": seat.global_position + Vector3(0, 0.9, 0), "off": Vector2(-18, 0)})
		_legend.append("8  кресло (props/seat.glb) на входе S")
	else:
		_legend.append("8  кресло — в сцене нет")
	_marks.append({"n": 9, "pos": ld.spawn + Vector3(0, 0.05, 0), "off": Vector2(18, 10)})
	_legend.append("9  вход S (спавн игрока; символ карты)")
	var sensor_prop: Node3D = view._sensor
	if sensor_prop != null and sensor_prop.visible:
		_marks.append({"n": 10, "pos": sensor_prop.global_position + Vector3(0, 1.0, 0), "off": Vector2.ZERO})
		_legend.append("10 колонна-датчик узла (props/sensor.glb)")
	else:
		_legend.append("10 колонна-датчик узла — в сцене нет (скрыта при раскладке)")
	for p in view.pillar_positions():
		_marks.append({"n": 11, "pos": p + Vector3(0, 1.2, 0), "off": Vector2.ZERO})
	_legend.append("11 одиночная колонна-укрытие (env/pillar, '#')")
	for r in view.solid_obstacles():
		var c := Vector3.ZERO
		for b: Vector2i in r.blocks:
			c += NodeLayout.cell_center(b.x, b.y)
		_marks.append({"n": 12, "pos": c / float(r.blocks.size()) + Vector3(0, 1.0, 0), "off": Vector2.ZERO})
	_legend.append("12 составное укрытие из 2+ блоков '#' (ObstacleBody)")
	for c in ld.booths:
		_marks.append({"n": 13, "pos": NodeGrid.center(c) + Vector3(0, 1.2, 0), "off": Vector2.ZERO})
	_legend.append("13 будка запасного Стража (guard_booth, 'b')" if not ld.booths.is_empty() else "13 будка — в раскладке нет")
	_legend.append("   запасной Страж внутри будки до тревоги 2 в сцене не рисуется")
	for s: Dictionary in ld.sentries:
		_marks.append({"n": 14, "pos": NodeGrid.center((s["route"] as Array)[0]["cell"]) + Vector3(0, 1.3, 0), "off": Vector2.ZERO})
	_legend.append("14 Страж, старт маршрута (sentry)")
	_marks.append({"n": 15, "pos": view.exit_pos() + Vector3(0, 0.05, 0), "off": Vector2.ZERO})
	_legend.append("15 площадка выхода ('E', помосты платформ)")
	for q in ld.portals:
		if q != Vector3.INF:
			_marks.append({"n": 16, "pos": q + Vector3(0, 1.4, 0), "off": Vector2.ZERO})
	_legend.append("16 портал ('1' '2' '3')")
	_legend.append("")
	_legend.append("без номера: синяя заливка занятых клеток пола, свет зрения")
	_legend.append("Стража на полу, стрелка его следующей клетки, веер Маяка")


func _shot(name_: String, with_legend: bool) -> void:
	for old in _layer.get_children():
		old.queue_free()
	var drawn := {}
	var cam := _cam
	cam.current = true
	var vp := get_viewport().get_visible_rect().size
	for m: Dictionary in _marks:
		var pos: Vector3 = m["pos"]
		if cam.is_position_behind(pos):
			continue
		var sp := cam.unproject_position(pos) + (m["off"] as Vector2)
		if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y:
			continue
		var l := Label.new()
		l.text = str(m["n"])
		drawn[int(m["n"])] = true
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color.BLACK)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.9, 0.2, 0.95)
		sb.set_corner_radius_all(9)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		l.add_theme_stylebox_override("normal", sb)
		l.position = sp - Vector2(12, 10)
		_layer.add_child(l)
	if with_legend:
		var t := Label.new()
		var lines: Array = []
		for line: String in _legend:
			var head := line.split(" ")[0]
			if name_ == "top" or not head.is_valid_int() or drawn.has(int(head)):
				lines.append(line)
		t.text = "\n".join(lines)
		t.add_theme_font_size_override("font_size", 14)
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0, 0, 0, 0.82)
		sb2.content_margin_left = 8
		sb2.content_margin_right = 8
		sb2.content_margin_top = 6
		sb2.content_margin_bottom = 6
		t.add_theme_stylebox_override("normal", sb2)
		t.position = Vector2(vp.x - 500, 10) if name_ == "top" else Vector2(10, vp.y - t.get_minimum_size().y - 10)
		_layer.add_child(t)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name_])

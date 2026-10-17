extends SceneTree
## Цена вида узла по размеру карты (П9: Серверная 8×8 против 10×10) без очков: сколько узлов, MultiMesh-инстансов и треугольников собирает клиент для раскладки.
## Запуск (нужен дисплей — иначе нет счётчиков отрисовки; на devbox как кадры dev.sh shot):
##   godot --display-driver wayland --path netrun --resolution 1280x720 -s res://tools/p9_cost.gd -- --layout=server_room_hard10 [--frames=30]
## Печатает строку `p9_cost layout=… nodes=… mesh_inst=… multimesh=… mm_instances=… tris_static=… draw_calls=… prims=… frame_ms=…`.
## Это стоимость сцены на настольной видеокарте в окне 1280×720 для СРАВНЕНИЯ раскладок, а не кадр Pico 4 (2160×2160 на глаз, мобильный GPU): абсолютные мс с очками не сравнивать.

var _layout_name := "server_room"
var _frames := 30


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			_layout_name = a.substr(9)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	root.add_child(scene)
	await process_frame
	var ld := LayoutData.cached(_layout_name)
	var shards: Array = []
	for k in ld.vaults.size():
		var p: Vector3 = ld.vaults[k]["slot"]
		shards.append({"id": "n_pk%d" % k, "p": [p.x, p.y, p.z], "ready": true, "vault": "open"})
	var portals: Array = []
	for k in ld.portals.size():
		var q: Vector3 = ld.portals[k]
		portals.append({"to": "n%d" % k, "title": "Узел %d" % (k + 1), "tier": "HARD", "p": [q.x, q.z], "open": true})
	scene.apply_node({"kind": "node", "node": "p9", "title": "Серверная", "tier": "HARD", "r": NodeLayout.PORTAL_RADIUS, "shards": shards, "portals": portals, "layout": ld.name})
	for i in _frames:
		await process_frame
	var vp := root.get_viewport().get_viewport_rid()
	var nodes := 0
	var mesh_inst := 0
	var mm := 0
	var mm_inst := 0
	var tris := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			var c: int = n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else n.multimesh.instance_count
			mm += 1
			mm_inst += c
			tris += c * (n.multimesh.mesh.get_faces().size() / 3)
		elif n is MeshInstance3D and n.mesh != null:
			mesh_inst += 1
			tris += n.mesh.get_faces().size() / 3
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	var frame_ms := (Time.get_ticks_usec() - t0) / 60000.0
	print("p9_cost layout=%s cells=%dx%d nodes=%d mesh_inst=%d multimesh=%d mm_instances=%d tris_static=%d draw_calls=%d prims=%d frame_ms=%.2f" % [
		_layout_name, ld.cols, ld.rows, nodes, mesh_inst, mm, mm_inst, tris,
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME), frame_ms])
	quit()

extends Node
## Одноразовая сверка (Blender, П7-3): вершины ObstacleBody одиночного блока против pillar_block/pillar_base из glb. Не коммитить.

func _round(v: float, k: float) -> float:
	var r := roundf(v * k) / k
	return 0.0 if absf(r) < 0.5 / k else r


func _key(p: Vector3, n: Vector3, c: Color) -> String:
	return "%.3f,%.3f,%.3f|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f" % [_round(p.x, 1000.0), _round(p.y, 1000.0), _round(p.z, 1000.0),
		_round(n.x, 100.0), _round(n.y, 100.0), _round(n.z, 100.0), _round(c.r, 100.0), _round(c.g, 100.0), _round(c.b, 100.0)]


func _collect(mesh: Mesh, offset: Vector3) -> Dictionary:
	var out := {}
	var tris := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx = a[Mesh.ARRAY_INDEX]
		tris += (idx.size() if idx != null and idx.size() > 0 else vs.size()) / 3
		for i in vs.size():
			var c: Color = cs[i] if i < cs.size() else Color(-1, -1, -1)
			out[_key(vs[i] - offset, ns[i], c)] = true
	out["__tris"] = tris
	return out


func _ready() -> void:
	var f := FileAccess.open("/tmp/obstacle_dump.txt", FileAccess.WRITE)
	var sc := (load("res://assets/models/env/pillar.glb") as PackedScene).instantiate()
	var ref := {}
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		ref[String(mi.name)] = _collect((mi as MeshInstance3D).mesh, Vector3.ZERO)
		f.store_line("glb %s verts=%d tris=%d" % [mi.name, ref[String(mi.name)].size() - 1, ref[String(mi.name)]["__tris"]])
	var rows: Array[String] = ["........", "..#.....", "........", "........", "........", "........", "........", "........"]
	var regions := ObstacleRegions.from_blocks(rows)
	var b: Vector2i = regions[0].blocks[0]
	var center := Vector3(NodeLayout.ROOM_MIN.x + NodeLayout.CELL * (b.x + 0.5), 0, NodeLayout.ROOM_MIN.y + NodeLayout.CELL * (b.y + 0.5))
	var built := ObstacleBody.build(regions)
	for pair in [["body", "pillar_block"], ["frame", "pillar_base"]]:
		var mine := _collect(built[pair[0]], center)
		var theirs: Dictionary = ref[pair[1]]
		f.store_line("godot %s verts=%d tris=%d" % [pair[0], mine.size() - 1, mine["__tris"]])
		var only_g := []
		var only_b := []
		for k in mine:
			if k != "__tris" and not theirs.has(k):
				only_g.append(k)
		for k in theirs:
			if k != "__tris" and not mine.has(k):
				only_b.append(k)
		f.store_line("%s: только Godot %d, только glb %d" % [pair[0], only_g.size(), only_b.size()])
		only_g.sort()
		only_b.sort()
		for k in only_g.slice(0, 25):
			f.store_line("  G " + k)
		for k in only_b.slice(0, 25):
			f.store_line("  B " + k)
	f.close()
	get_tree().quit()

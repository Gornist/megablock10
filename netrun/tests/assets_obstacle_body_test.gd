extends GdUnitTestSuite
## Охрана вида цельного препятствия (П7-2/П7-3): корпус ObstacleBody для ОДНОГО блока совпадает с модулем `pillar` из glb (env.py, `_cover_parts`) по позициям и цветам вершин.
## Константы корпуса живут в двух местах (INSET/BAND/RISE/HEIGHT в client/obstacle_body.gd и 1,9/0,03/0,3/2,2 в assets/src/env.py): правка одной без другой даёт
## «одиночная колонна одного вида, склеенное препятствие другого» — этот тест краснеет. Нормали не сверяем: у glb они сглажены к верху и низу, на кадре разницы нет
## (сверка 17.10: 0,03–0,04 % пикселей при шуме 0,09–0,25 %).

const BLOCK := Vector2i(3, 3)


func _keys(mesh: Mesh, center: Vector3, skip_underside: bool) -> Dictionary:
	var out := {}
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for i in vs.size():
			var p := vs[i] - center
			# Нижняя грань glb (пол прячет её) в корпус рантайма не входит: внутренние вершины основания пропускаем.
			if skip_underside and absf(p.y) < 1e-4 and absf(p.x) < 0.94 and absf(p.z) < 0.94:
				continue
			out["%.3f,%.3f,%.3f|%.2f,%.2f,%.2f" % [_z(p.x), _z(p.y), _z(p.z), _z(cs[i].r, 100.0), _z(cs[i].g, 100.0), _z(cs[i].b, 100.0)]] = true
	return out


func _z(v: float, k := 1000.0) -> float:
	var r := roundf(v * k) / k
	return 0.0 if absf(r) < 0.5 / k else r


func _glb_part(name_: String) -> Mesh:
	var root := (load("res://assets/models/env/pillar.glb") as PackedScene).instantiate()
	var mesh: Mesh = null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == name_:
			mesh = (mi as MeshInstance3D).mesh
	root.free()
	return mesh


func _built() -> Dictionary:
	var rows: Array[String] = []
	for z in LayoutData.SIZE:
		var row := ""
		for x in LayoutData.SIZE:
			row += "#" if Vector2i(x, z) == BLOCK else "."
		rows.append(row)
	var regions := ObstacleRegions.from_blocks(rows)
	var center := Vector3(NodeLayout.ROOM_MIN.x + NodeLayout.CELL * (BLOCK.x + 0.5), 0.0, NodeLayout.ROOM_MIN.y + NodeLayout.CELL * (BLOCK.y + 0.5))
	return {"meshes": ObstacleBody.build(regions), "center": center}


func _same(mine: Dictionary, theirs: Dictionary, what: String) -> void:
	assert_int(mine.size()).override_failure_message("%s: пустой набор вершин" % what).is_greater(7)
	var only_mine: Array = []
	var only_glb: Array = []
	for k in mine:
		if not theirs.has(k):
			only_mine.append(k)
	for k in theirs:
		if not mine.has(k):
			only_glb.append(k)
	assert_bool(only_mine.is_empty() and only_glb.is_empty()).override_failure_message(
		"%s: только у ObstacleBody %d (%s), только у pillar.glb %d (%s)" % [what, only_mine.size(), only_mine.slice(0, 3), only_glb.size(), only_glb.slice(0, 3)]).is_true()


func test_корпус_одного_блока_совпадает_с_модулем_pillar() -> void:
	var b := _built()
	_same(_keys(b["meshes"]["body"], b["center"], false), _keys(_glb_part("pillar_block"), Vector3.ZERO, true), "корпус")


func test_рамка_одного_блока_совпадает_с_модулем_pillar() -> void:
	var b := _built()
	_same(_keys(b["meshes"]["frame"], b["center"], false), _keys(_glb_part("pillar_base"), Vector3.ZERO, false), "рамка")

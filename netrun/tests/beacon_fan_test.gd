extends GdUnitTestSuite
## Веер Маяка строится по клеткам, которые видит TickVision (Game 16.10: «что видно, то и работает»): колонны и укрытия обрезают его, как обрезают зрение.

func _view(cell: Vector2i, dir: Vector2i, r: float) -> Dictionary:
	return {"id": "o1", "c": [cell.x, cell.y], "d": [dir.x, dir.y], "nd": [dir.x, dir.y], "aw": 0, "r": r}


func _beacon() -> BeaconView:
	var b := BeaconView.new()
	add_child(b)
	return auto_free(b)


func _grid_with(blocked: Array) -> NodeGrid:
	var g := NodeGrid.new()
	for c: Vector2i in blocked:
		g.occ[c] = true
	return g


func test_без_препятствий_веер_равен_зрению() -> void:
	var b := _beacon()
	var cell := Vector2i(8, 8)
	var g := _grid_with([])
	b.apply_view(_view(cell, Vector2i(1, 0), 10.0), g)
	var want := TickVision.visible_cells(g, cell, Vector2i(1, 0), 10.0, BeaconView.FOCUS_DEG, BeaconView.FOCUS_DEG).size()
	assert_int(b.fan_cell_count()).is_equal(want)
	assert_int(want).is_greater(10)


func test_колонна_на_пути_уменьшает_веер() -> void:
	var cell := Vector2i(2, 8)
	var open := _beacon()
	open.apply_view(_view(cell, Vector2i(1, 0), 10.0), _grid_with([]))
	var shut := _beacon()
	shut.apply_view(_view(cell, Vector2i(1, 0), 10.0), _grid_with([Vector2i(5, 8), Vector2i(5, 9), Vector2i(6, 8), Vector2i(6, 9)]))
	assert_int(shut.fan_cell_count()).is_less(open.fan_cell_count())


func test_веер_не_содержит_клеток_за_колонной_и_самой_колонны() -> void:
	var cell := Vector2i(2, 8)
	var wall := [Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9)]
	var g := _grid_with(wall)
	var seen := TickVision.visible_cells(g, cell, Vector2i(1, 0), 10.0, BeaconView.FOCUS_DEG, BeaconView.FOCUS_DEG)
	assert_bool(seen.has(Vector2i(5, 8))).is_false()
	assert_bool(seen.has(Vector2i(8, 8))).is_false()   # за стеной в её тени
	var b := _beacon()
	b.apply_view(_view(cell, Vector2i(1, 0), 10.0), g)
	assert_int(b.fan_cell_count()).is_equal(seen.size())


func test_смена_угла_перестраивает_веер() -> void:
	var b := _beacon()
	var g := _grid_with([Vector2i(5, 8), Vector2i(5, 9), Vector2i(6, 8), Vector2i(6, 9)])
	b.apply_view(_view(Vector2i(2, 8), Vector2i(1, 0), 10.0), g)
	var east := b.fan_cell_count()
	b.apply_view(_view(Vector2i(2, 8), Vector2i(0, -1), 10.0), g)
	assert_int(b.fan_cell_count()).is_not_equal(0)
	assert_int(b.fan_cell_count()).is_greater(east)   # на север колонны нет — веер полный


func test_без_сетки_остаётся_веер_модели() -> void:
	var b := _beacon()
	b.apply_view(_view(Vector2i(8, 8), Vector2i(1, 0), 6.0))
	assert_int(b.fan_cell_count()).is_equal(-1)
	var beam := b.find_child("Beam", true, false) as Node3D
	assert_bool(beam.visible).is_true()


func test_веер_по_клеткам_прячет_веер_модели_и_имеет_геометрию() -> void:
	var b := _beacon()
	b.apply_view(_view(Vector2i(8, 8), Vector2i(1, 0), 6.0), _grid_with([]))
	var beam := b.find_child("Beam", true, false) as Node3D
	assert_bool(beam.visible).is_false()
	var fan := b.find_child("FanCells", true, false) as MeshInstance3D
	assert_object(fan).is_not_null()
	assert_object(fan.mesh).is_not_null()
	assert_object(fan.get_surface_override_material(0)).is_not_null()

extends GdUnitTestSuite
## Подсветка занятых клеток (OccupiedFloor) и положение плиты пола относительно сетки 1 м: укрытия видны, пол строго по клеткам.


func test_края_плиты_пола_совпадают_с_границами_клеток_сетки() -> void:
	var slab := String(NodeView.VARIANTS["floor"][0])
	var side := float(slab.get_slice("_", slab.get_slice_count("_") - 1))   # floor_slab_16 → 16 м
	assert_float(side).is_equal(float(NodeGrid.cols()) * NodeGrid.CELL_M)
	assert_float(side).is_equal(float(NodeGrid.rows()) * NodeGrid.CELL_M)
	var half := side * 0.5
	var west := NodeLayout.ROOM_CENTER.x - half
	var east := NodeLayout.ROOM_CENTER.x + half
	var north := NodeLayout.ROOM_CENTER.z - half
	var south := NodeLayout.ROOM_CENTER.z + half
	assert_float(west).is_equal(NodeLayout.ROOM_MIN.x)
	assert_float(east).is_equal(NodeLayout.ROOM_MAX.x)
	assert_float(north).is_equal(NodeLayout.ROOM_MIN.y)
	assert_float(south).is_equal(NodeLayout.ROOM_MAX.y)
	# края — на целых метрах, то есть на границах клеток; центр крайних клеток — на полметра внутрь
	for e in [west, east, north, south]:
		assert_float(float(e) - floorf(float(e))).is_equal(0.0)
	assert_float(NodeGrid.center(Vector2i(0, 0)).x - 0.5 * NodeGrid.CELL_M).is_equal(west)
	assert_float(NodeGrid.center(Vector2i(0, 0)).z - 0.5 * NodeGrid.CELL_M).is_equal(north)
	assert_float(NodeGrid.center(Vector2i(NodeGrid.cols() - 1, NodeGrid.rows() - 1)).x + 0.5 * NodeGrid.CELL_M).is_equal(east)
	assert_float(NodeGrid.center(Vector2i(NodeGrid.cols() - 1, NodeGrid.rows() - 1)).z + 0.5 * NodeGrid.CELL_M).is_equal(south)


func test_подсвечено_столько_клеток_сколько_занято_в_фойе() -> void:
	var ld := LayoutData.load_named("foyer")
	assert_str(ld.error).is_empty()
	var f: OccupiedFloor = auto_free(OccupiedFloor.new(ld.grid()))
	add_child(f)
	assert_int(f.cell_count()).is_equal(ld.occupied.size())
	assert_int(f.cell_count()).is_equal(4 * 4 + 2 * 4)   # четыре колонны и два хранилища, по блоку 2×2 клетки


func test_отметки_лежат_в_центрах_занятых_клеток() -> void:
	var ld := LayoutData.load_named("foyer")
	var f: OccupiedFloor = auto_free(OccupiedFloor.new(ld.grid()))
	add_child(f)
	var seen: Dictionary = {}
	for i in f.cell_count():
		var p := f.cell_position(i)
		var c := NodeGrid.cell_of(p)
		assert_bool(ld.occupied.has(c)).override_failure_message("отметка %d вне занятой клетки %s" % [i, c]).is_true()
		assert_float(p.x).is_equal(NodeGrid.center(c).x)
		assert_float(p.z).is_equal(NodeGrid.center(c).z)
		assert_float(p.y).is_less(TickFloor.FUTURE_LIFT)   # под светом зрения ICE
		seen[c] = true
	assert_int(seen.size()).is_equal(ld.occupied.size())   # без повторов


func test_пустая_сетка_без_отметок_а_смена_сетки_перестраивает() -> void:
	var f: OccupiedFloor = auto_free(OccupiedFloor.new(NodeGrid.new()))
	add_child(f)
	assert_int(f.cell_count()).is_equal(0)
	f.set_grid(LayoutData.load_named("foyer").grid())
	assert_int(f.cell_count()).is_equal(24)
	f.set_grid(NodeGrid.new())
	assert_int(f.cell_count()).is_equal(0)

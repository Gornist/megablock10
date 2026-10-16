extends GdUnitTestSuite
## Барьер объясняет себя (П6-3, ice.md §5): полоса у барьера — куда ведёт, предупреждение «РЯДОМ ЛОГОВО», цена силового вскрытия до удержания курка.

var _scene: Node3D


func before_test() -> void:
	_scene = preload("res://client/rig_test_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame


func after_test() -> void:
	_scene.queue_free()


func _near_cells() -> Array:
	var mine := NodeGrid.cell_of(_scene.rig.global_position)
	return [[mine.x + 1, mine.y], [mine.x + 2, mine.y], [mine.x + 1, mine.y + 1], [mine.x + 2, mine.y + 1]]


func _state(cells: Array) -> Dictionary:
	return {"k": 1.0, "trace": 0.0, "level": 0, "cd": [], "ice": [], "br": [{"id": "bar1", "c": cells, "open": 0}]}


func test_текст_подсказки_куда_ведёт_и_цена_силы() -> void:
	var t := HudLogic.barrier_hint_text(false)
	assert_str(t).contains("внутреннее хранилище")
	assert_str(t).contains("СИЛОЙ: trace +10, тревога +10")
	assert_str(t).not_contains("ЛОГОВО")


func test_текст_подсказки_предупреждает_о_логове() -> void:
	assert_str(HudLogic.barrier_hint_text(true)).contains("РЯДОМ ЛОГОВО BLACK ICE")


func test_рядом_с_логовом_это_две_клетки_карты_по_чебышёву() -> void:
	var lair := [Vector2i(6, 6), Vector2i(7, 7)]
	assert_bool(HudLogic.barrier_near_lair([Vector2i(6, 2)], lair)).is_true()    # 4 клетки = 2 клетки карты
	assert_bool(HudLogic.barrier_near_lair([Vector2i(6, 1)], lair)).is_false()   # 5 клеток — далеко
	assert_bool(HudLogic.barrier_near_lair([Vector2i(2, 2), Vector2i(8, 9)], lair)).is_true()   # любая клетка барьера


func test_полоса_барьера_без_логова_показывает_общую_подсказку() -> void:
	_scene.apply_state(_state(_near_cells()))
	var deck: DeckPanel = _scene.world_ui.deck
	assert_str(deck._barrier_label.text).contains("внутреннее хранилище")
	assert_str(deck._barrier_label.text).not_contains("ЛОГОВО")


func test_полоса_барьера_в_ядре_рядом_с_логовом_предупреждает() -> void:
	_scene.apply_layout(LayoutData.load_named("core"), "NIGHTMARE")
	var lair_cell: Vector2i = LayoutData.load_named("core").lair["cells"][0]
	_scene.rig.global_position = NodeGrid.center(lair_cell) + Vector3(-3.0, 0.0, -3.0)
	var mine := NodeGrid.cell_of(_scene.rig.global_position)
	_scene.apply_state(_state([[mine.x + 1, mine.y], [mine.x + 2, mine.y], [mine.x + 1, mine.y + 1], [mine.x + 2, mine.y + 1]]))
	assert_str(_scene.world_ui.deck._barrier_label.text).contains("ЛОГОВО")
	_scene.apply_state(_state([[40, 40], [41, 40], [40, 41], [41, 41]]))

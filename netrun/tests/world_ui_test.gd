extends GdUnitTestSuite


func test_deck_panel_uses_viewport_surface() -> void:
	var d: DeckPanel = auto_free(DeckPanel.new())
	add_child(d)
	d.set_deck({"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 0.0}], "selected": "x"})
	assert_bool(d.has_viewport_surface()).is_true()
	assert_str(d.row_texts()[1]).is_equal("> Взлом  готово")


func test_trace_indicator_text() -> void:
	var t: TraceIndicator = auto_free(TraceIndicator.new())
	add_child(t)
	t.set_trace(80.0)
	assert_str(t.shown_text()).is_equal("блокировка 80")


func test_scene_applies_server_state() -> void:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	scene.apply_state({
		"trace": 55.0, "level": 2, "ghost": false,
		"ice": [{"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [1.0, 0.0], "s": 1}],
		"cd": [{"id": "ghost_1", "name": "Призрак", "left": 0.0}, {"id": "jitter_1", "name": "Дрожь", "left": 30.0}],
	})
	assert_str(scene.world_ui.trace.shown_text()).is_equal("трассировка 55")
	assert_str(scene.world_ui.deck.row_texts()[1]).is_equal("> 1 Призрак  готово")
	assert_str(scene.world_ui.deck.row_texts()[2]).is_equal("  2 Дрожь  30 с")
	assert_object(scene.ice_node("ice_1")).is_not_null()
	var used: Array[String] = []
	scene.daemon_use_requested.connect(func(id): used.append(id))
	scene.use_slot(1)
	assert_array(used).is_equal(["jitter_1"])
	scene.select_next()
	scene.use_selected()
	assert_array(used).is_equal(["jitter_1", "ghost_1"])

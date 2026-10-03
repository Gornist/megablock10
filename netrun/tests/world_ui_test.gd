extends GdUnitTestSuite


func test_deck_panel_uses_viewport_surface() -> void:
	var d: DeckPanel = auto_free(DeckPanel.new())
	add_child(d)
	d.set_deck({"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 0.0}], "selected": "x"})
	assert_bool(d.has_viewport_surface()).is_true()
	assert_str(d.row_texts()[1]).is_equal("> Взлом  готово")


func test_deck_redraws_only_on_change_and_not_faster_than_cap() -> void:
	var d: DeckPanel = auto_free(DeckPanel.new())
	add_child(d)
	var deck := {"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 0.0}], "selected": "x"}
	d.set_deck(deck)
	d._process(1.0)
	assert_int(d.redraw_count).is_equal(1)
	# То же состояние ещё раз: ничего не рисуем и не перестраиваем.
	d.set_deck(deck.duplicate(true))
	d._process(0.001)
	assert_int(d.redraw_count).is_equal(1)
	# Изменение, но с прошлой перерисовки прошло меньше 1/30 с: ждём.
	d.set_deck({"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 5.0}], "selected": "x"})
	d._process(0.001)
	assert_int(d.redraw_count).is_equal(1)
	d._process(1.0 / DeckPanel.MAX_FPS)
	assert_int(d.redraw_count).is_equal(2)
	assert_str(d.row_texts()[1]).contains("5")


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


func test_flatline_screen_fades_without_moving_camera() -> void:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	var cam_before: Vector3 = scene.rig.camera.position
	scene.show_ended("flatline")
	assert_bool(scene.flatline_shown).is_true()
	assert_object(scene.rig.camera.get_node_or_null("FlatlineVeil")).is_not_null()
	assert_str((scene.rig.camera.get_node("FlatlineText") as Label3D).text).is_equal("ФЛЭТЛАЙН")
	assert_vector(scene.rig.camera.position).is_equal(cam_before)  # камеру подача не трогает
	await get_tree().create_timer(1.0).timeout
	var mat := ((scene.rig.camera.get_node("FlatlineVeil") as MeshInstance3D).mesh as QuadMesh).material as StandardMaterial3D
	assert_float(mat.albedo_color.a).is_equal(1.0)


func test_clean_exit_has_no_flatline_screen() -> void:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	scene.show_ended("clean")
	assert_bool(scene.flatline_shown).is_false()


func test_black_ice_has_its_own_model_and_hunt_state_is_accepted() -> void:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	scene.apply_state({"trace": 0.0, "level": 0, "ghost": false,
		"ice": [{"id": "black_1", "p": [0.0, 0.0, -9.0], "f": [1.0, 0.0], "s": 3, "b": 1},
			{"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [1.0, 0.0], "s": 2, "b": 0}], "cd": []})
	var black: IceView = scene.ice_node("black_1")
	var soft: IceView = scene.ice_node("ice_1")
	assert_str(black.asset).is_not_equal(soft.asset)  # у Soft и Black ICE разные модели
	assert_bool(black.black).is_true()
	assert_bool(soft.black).is_false()
	assert_str(black.current_clip()).is_equal("hunt")  # охота (s = 3), игрок далеко
	assert_str(soft.current_clip()).is_equal("patrol")  # поиск (s = 2): Soft ICE идёт

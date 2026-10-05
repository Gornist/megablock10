extends GdUnitTestSuite
## Указатель деки (DeckPointer): луч правого контроллера (в плоской сборке — мышь) -> события мыши в SubViewport деки -> подсветка и
## нажатия кнопок. Риг плоский (xr_active = false), луч подаётся готовый (update_ray), как делает _process по позе контроллера.

const T0 := 1_700_000_000.0

var _rig: XRRig
var _ui: WorldUI
var _link: FakePhoneLink


func _setup_ui(with_phone: bool = true) -> void:
	_rig = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	add_child(_rig)
	_ui = auto_free(WorldUI.new())
	add_child(_ui)
	_ui.attach(_rig)
	_link = FakePhoneLink.new(T0, false)
	_link.auto_reply = false
	if with_phone:
		_ui.set_phone(_link)
	for i in 4:
		await get_tree().process_frame


## Луч из точки перед панелью ровно в пиксель panel_px (координаты SubViewport).
func _ray_at(panel_px: Vector2) -> Dictionary:
	var panel := _ui.deck.surface_transform()
	var world := DeckPointerMath.view_to_world(panel_px, panel, _ui.deck.panel_size_m(), Vector2(DeckPanel.VIEW_SIZE))
	var normal := (panel.basis * Vector3(0, 0, 1)).normalized()
	var origin := world + normal * 0.45
	return {"origin": origin, "dir": (world - origin).normalized()}


func _aim_at(panel_px: Vector2) -> void:
	var r := _ray_at(panel_px)
	_ui.pointer.update_ray(r["origin"], r["dir"])


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _click_at(panel_px: Vector2) -> void:
	_aim_at(panel_px)
	_ui.pointer.set_trigger(true)
	_ui.pointer.set_trigger(false)


func test_aiming_at_a_chip_highlights_it_and_leaving_clears_it() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_VOBLA)
	for i in 3:
		await get_tree().process_frame
	var chip: MbButton = _ui.deck.chat().chip_buttons()[0]
	assert_bool(chip.is_hovered_now()).is_false()
	_aim_at(_center(chip))
	assert_bool(_ui.pointer.hovering).is_true()
	assert_bool(chip.is_hovered_now()).is_true()
	# Луч уходит мимо панели: подсветка гаснет, «мышь» вышла.
	_ui.pointer.update_ray(Vector3(0, 5, 5), Vector3(0, 0, -1))
	assert_bool(_ui.pointer.hovering).is_false()
	assert_bool(chip.is_hovered_now()).is_false()


func test_trigger_on_a_chip_sends_the_quick_reply() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	for i in 3:
		await get_tree().process_frame
	var chip: MbButton = _ui.deck.chat().chip_buttons()[2]   # «Позже»
	_click_at(_center(chip))
	assert_str(_link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]["text"]).is_equal("Позже")
	assert_int(_ui.pointer.button_events).is_equal(2)


func test_trigger_off_the_panel_does_nothing() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	var before := _link.messages(FakePhoneLink.ID_SHERSHEN, 20).size()
	_ui.pointer.update_ray(Vector3(0, 5, 5), Vector3(0, 0, -1))
	_ui.pointer.set_trigger(true)
	_ui.pointer.set_trigger(false)
	assert_int(_ui.pointer.button_events).is_equal(0)
	assert_int(_link.messages(FakePhoneLink.ID_SHERSHEN, 20).size()).is_equal(before)


func test_pressing_on_one_button_and_releasing_on_another_is_not_a_click() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	for i in 3:
		await get_tree().process_frame
	var a: MbButton = _ui.deck.chat().chip_buttons()[0]
	var b: MbButton = _ui.deck.chat().chip_buttons()[1]
	_aim_at(_center(a))
	_ui.pointer.set_trigger(true)
	_aim_at(_center(b))
	_ui.pointer.set_trigger(false)
	var last: Dictionary = _link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]
	assert_bool(last["mine"] and last["text"] in ["Да", "Нет"]).is_false()


func test_tabs_are_clickable_by_the_pointer() -> void:
	await _setup_ui()
	var tabs := _ui.deck.tabs()
	var calls_rect := tabs.tab_rect(2)
	_click_at(tabs.get_global_rect().position + calls_rect.get_center())
	assert_str(_ui.deck.active_tab()).is_equal(DeckPanel.TAB_CALLS)


func test_incoming_call_can_be_answered_with_the_pointer() -> void:
	await _setup_ui()
	_link.incoming_call("ВОБЛА")
	for i in 4:
		await get_tree().process_frame
	var accept := _ui.deck.calls().find_button("ПРИНЯТЬ")
	_click_at(_center(accept))
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_IN_CALL)


func test_pointer_works_on_a_turned_panel() -> void:
	await _setup_ui()
	_rig.rotate_y(deg_to_rad(40.0))   # игрок повернулся: дека на камере поворачивается вместе с ним
	await get_tree().process_frame
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_VOBLA)
	for i in 3:
		await get_tree().process_frame
	var chip: MbButton = _ui.deck.chat().chip_buttons()[5]   # «Увидимся»
	_click_at(_center(chip))
	assert_str(_link.messages(FakePhoneLink.ID_VOBLA, 1)[0]["text"]).is_equal("Увидимся")


func test_pointer_hits_a_deck_scaled_down_for_the_wrist() -> void:
	await _setup_ui()
	_ui.deck.scale = Vector3.ONE * 0.75   # как WorldUI.WRIST_DECK_SCALE: трансформация поверхности несёт масштаб
	await get_tree().process_frame
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_VOBLA)
	for i in 3:
		await get_tree().process_frame
	assert_float(_ui.deck.panel_world_size_m().x).is_equal_approx(DeckPanel.PANEL_WIDTH_M * 0.75, 0.0001)
	var chip: MbButton = _ui.deck.chat().chip_buttons()[4]   # «Привет»
	_click_at(_center(chip))
	assert_str(_link.messages(FakePhoneLink.ID_VOBLA, 1)[0]["text"]).is_equal("Привет")


func test_pointer_ignores_a_hidden_deck() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	var r := _ray_at(Vector2(256, 192))
	_ui.pointer.update_ray(r["origin"], r["dir"])
	assert_bool(_ui.pointer.hovering).is_true()
	_ui._anchor.visible = false   # у руки нет позы — дека на запястье скрыта
	assert_bool(_ui.deck.is_interactive()).is_false()
	_ui.pointer._process(0.016)
	assert_bool(_ui.pointer.hovering).is_false()


func test_pointer_clicks_the_deck_worn_on_the_wrist_and_lets_go_when_the_hand_is_lost() -> void:
	# Как в VR с руками: якорь деки — на запястье (HandView.wrist_anchor), дека уменьшена, пока у руки нет позы, она скрыта.
	_rig = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	add_child(_rig)
	_ui = auto_free(WorldUI.new())
	add_child(_ui)
	_ui.attach(_rig)
	_link = FakePhoneLink.new(T0, false)
	_link.auto_reply = false
	_ui.set_phone(_link)
	_rig.xr_active = true
	_rig.left_hand_view.pose_source = func(): return HandSkeleton.pose({}, true)
	_rig.left_hand_view.update_hand()
	_ui._place()
	assert_float(_ui.deck.scale.x).is_equal_approx(WorldUI.WRIST_DECK_SCALE, 0.0001)
	assert_float(rad_to_deg(_ui.deck.rotation.z)).is_equal_approx(90.0, 0.001)   # повёрнута на 90° против часовой, глядя на панель
	assert_vector(_ui.deck.position).is_equal_approx(WorldUI.WRIST_DECK_POS, Vector3.ONE * 0.0001)
	assert_bool(_ui.deck.is_interactive()).is_true()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	for i in 4:
		await get_tree().process_frame
	_ui.deck.set_process(false)
	var chip: MbButton = _ui.deck.chat().chip_buttons()[0]
	var r := _ray_at(_center(chip))
	_ui.pointer.update_ray(r["origin"], r["dir"])
	_ui.pointer.set_trigger(true)
	_ui.pointer.set_trigger(false)
	assert_str(_link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]["text"]).is_equal("Да")
	_rig.left_hand_view.pose_source = Callable()
	_rig.left_hand_view.update_hand()
	_ui._place()
	assert_bool(_ui.deck.is_interactive()).is_false()


func test_pointer_is_silent_when_the_phone_is_off() -> void:
	await _setup_ui(false)
	assert_bool(_ui.deck.is_interactive()).is_false()
	var r := _ray_at(Vector2(256, 192))
	_ui.pointer.update_ray(r["origin"], r["dir"])   # попасть можно, но...
	_ui.pointer._process(0.016)                       # ...процесс указателя без телефона всё отпускает и скрывает
	assert_bool(_ui.pointer.hovering).is_false()


func test_mouse_click_on_the_panel_is_taken_by_the_deck_and_not_passed_on() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	for i in 3:
		await get_tree().process_frame
	var chip: MbButton = _ui.deck.chat().chip_buttons()[3]   # «Перезвоню»
	var world := DeckPointerMath.view_to_world(_center(chip), _ui.deck.surface_transform(), _ui.deck.panel_size_m(), Vector2(DeckPanel.VIEW_SIZE))
	var screen := _rig.camera.unproject_position(world)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen
	_ui.pointer._input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen
	_ui.pointer._input(up)
	assert_str(_link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]["text"]).is_equal("Перезвоню")


func test_mouse_wheel_over_the_panel_scrolls_the_messages() -> void:
	await _setup_ui()
	for i in 10:
		_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "длинное сообщение номер %d, чтобы список точно не поместился" % i)
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_VOBLA)
	for i in 6:
		await get_tree().process_frame
	var sc := _ui.deck.chat().message_scroll()
	var at_end := sc.scroll_vertical
	assert_int(at_end).is_greater(0)   # переписка длиннее окна, открыта на конце
	var world := DeckPointerMath.view_to_world(_center(sc), _ui.deck.surface_transform(), _ui.deck.panel_size_m(), Vector2(DeckPanel.VIEW_SIZE))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = _rig.camera.unproject_position(world)
	_ui.pointer._input(wheel)
	assert_int(sc.scroll_vertical).is_less(at_end)


func test_hover_on_a_button_marks_the_deck_for_redraw() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_VOBLA)
	for i in 3:
		await get_tree().process_frame
	_ui.deck.set_process(false)
	_ui.deck._process(1.0)   # дорисовали накопленное
	for i in 3:
		await get_tree().process_frame
	_ui.deck._process(1.0)
	var before := _ui.deck.redraw_count
	var chip: MbButton = _ui.deck.chat().chip_buttons()[0]
	_aim_at(_center(chip))
	await get_tree().process_frame   # подсветка кнопки запросила перерисовку
	_ui.deck._process(1.0)
	assert_int(_ui.deck.redraw_count).is_equal(before + 1)

extends GdUnitTestSuite
## Панель взлома (BreachPanel, К3) без сервера: выбор демонов в пределах RAM, сетка и подсветка, итог, размеры для рук, нажатие указателем правой руки.

var _rig: XRRig
var _ui: WorldUI
var _panel: BreachPanel

const DAEMONS := [
	{"id": "d1", "name": "Извлечение", "effect": "EXTRACT_SHARD", "tier": 2, "cells": ["1C", "BD"]},
	{"id": "d2", "name": "Призрак", "effect": "GHOST", "tier": 1, "cells": ["55", "7A", "FF"]},
]


func _setup_ui(ram: int = 6) -> void:
	_rig = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	add_child(_rig)
	_ui = auto_free(WorldUI.new())
	add_child(_ui)
	_ui.attach(_rig)
	_panel = _ui.breach_panel
	_panel.set_context("Серверная", "HARD", DAEMONS, ram)
	for i in 3:
		await get_tree().process_frame


func _start_run(tier: String = "HARD", ram: int = 6) -> BreachMirror:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event(tier, 77, ram))
	_panel.place(BreachPanelLayout.pose(Vector3(0, 1.2, 0), Vector3(0, 1, -1.5)))
	_panel.begin(m)
	for i in 3:
		await get_tree().process_frame
	return m


func _ray_at(px: Vector2) -> Dictionary:
	var t := _panel.surface_transform()
	var world := DeckPointerMath.view_to_world(px, t, _panel.panel_size_m(), Vector2(BreachPanel.VIEW_SIZE))
	var normal := (t.basis * Vector3(0, 0, 1)).normalized()
	var origin := world + normal * 0.45
	return {"origin": origin, "dir": (world - origin).normalized()}


func _click_control(c: Control) -> void:
	var r := _ray_at(c.get_global_rect().get_center())
	_ui.breach_pointer.update_ray(r["origin"], r["dir"])
	_ui.breach_pointer.set_trigger(true)
	_ui.breach_pointer.set_trigger(false)


func test_panel_is_hidden_until_shown_and_not_interactive() -> void:
	await _setup_ui()
	assert_str(_panel.mode()).is_equal(BreachPanel.MODE_HIDDEN)
	assert_bool(_panel.is_interactive()).is_false()
	assert_bool(_panel.has_viewport_surface()).is_true()
	assert_float(_panel.panel_size_m().x).is_equal_approx(0.48, 0.0001)
	assert_float(_panel.panel_size_m().y).is_equal_approx(0.32, 0.0001)
	assert_float(BreachPanel.VIEW_SIZE.x * 1.0 / BreachPanel.VIEW_SIZE.y).is_equal_approx(BreachPanelLayout.WIDTH_M / BreachPanelLayout.HEIGHT_M, 0.001)


func test_idle_lists_daemons_with_all_picked_that_fit_the_ram() -> void:
	await _setup_ui(7)
	_panel.show_idle("v1", {"access": "ok"})
	await get_tree().process_frame
	var all := "\n".join(_panel.texts())
	assert_str(all).contains("ВЗЛОМ · Серверная").contains("тир HARD").contains("Извлечение").contains("Призрак")
	assert_str(all).contains("1C BD").contains("55 7A FF")
	# замок HARD 2 + 2 + 3 = 7 ячеек помещаются в RAM 7: отмечены оба
	assert_array(_panel.picked_ids()).is_equal(["d1", "d2"])
	assert_int(_panel.picked_cells()).is_equal(5)
	assert_str(all).contains("замок 2 + 5 / RAM 7")


func test_default_pick_counts_the_lock_and_shows_overflow_in_red() -> void:
	await _setup_ui(6)   # замок 2 + 2 + 3 = 7 > 6: по умолчанию влезает только Извлечение
	_panel.show_idle("v1", {"access": "ok"})
	await get_tree().process_frame
	assert_array(_panel.picked_ids()).is_equal(["d1"])
	assert_str("\n".join(_panel.texts())).contains("замок 2 + 2 / RAM 6")
	assert_bool(_panel.fits_ram()).is_true()
	_panel.toggle_daemon("d2")   # игрок добавил лишнего: счётчик краснеет, «НАЧАТЬ» недоступна
	await get_tree().process_frame
	assert_bool(_panel.fits_ram()).is_false()
	assert_str("\n".join(_panel.texts())).contains("замок 2 + 5 / RAM 6").contains("НЕ ХВАТАЕТ RAM")
	assert_bool(_panel.request_start()).is_false()
	var bad := _panel._frame.find_children("*", "Label", true, false).filter(func(l: Label): return l.text.begins_with("замок"))
	assert_int(bad.size()).is_equal(1)
	assert_str(str((bad[0] as Label).theme_type_variation)).is_equal(str(DeckTheme.V_BAD))


func test_default_picks_prefers_vault_tier_extraction_then_rest() -> void:
	var ds := [
		{"id": "g", "effect": "GHOST", "tier": 1, "cells": ["55", "7A"]},
		{"id": "e1", "effect": "EXTRACT_SHARD", "tier": 1, "cells": ["1C", "BD"]},
		{"id": "e3", "effect": "EXTRACT_SHARD", "tier": 3, "cells": ["1C", "BD", "E9"]},
		{"id": "e2", "effect": "EXTRACT_DAEMON", "tier": 2, "cells": ["1C", "BD", "FF"]},
		{"id": "j", "effect": "JITTER", "tier": 1, "cells": ["7A", "FF"]},
	]
	# NIGHTMARE (уровень 3, замок 3), RAM 12: сначала Извлечение тира 3, потом 2, потом 1 (3+3+3+2=11), защитные — по месту: Призрак (2) не влезает
	var p := BreachPanel.default_picks(ds, 3, 3, 12)
	assert_array(p.keys()).contains_exactly_in_any_order(["e3", "e2", "e1"])
	# RAM 14: влезает и Призрак, и Дрожь (11 + 2 = 13, ещё 2 — нет)
	p = BreachPanel.default_picks(ds, 3, 3, 14)
	assert_array(p.keys()).contains_exactly_in_any_order(["e3", "e2", "e1", "g"])
	# HARD (уровень 2): Извлечение тира 3 выше тира хранилища — берётся после тира 2 и 1
	p = BreachPanel.default_picks(ds, 2, 2, 8)
	assert_array(p.keys()).contains_exactly_in_any_order(["e2", "e1"])   # 2 + 3 + 2 = 7; тир 3 (3 яч.) не влезает
	# ничего не влезает — пусто, а не нарушение RAM
	assert_dict(BreachPanel.default_picks(ds, 3, 3, 4)).is_empty()


func test_default_pick_drops_what_does_not_fit_the_ram() -> void:
	await _setup_ui(4)
	_panel.show_idle("v1", {"access": "ok"})
	assert_array(_panel.picked_ids()).is_equal(["d1"])   # 2 влезают, ещё 3 — нет
	_panel.toggle_daemon("d1")
	assert_array(_panel.picked_ids()).is_equal([])
	assert_bool(_panel.request_start()).is_false()        # ничего не выбрано


func test_start_button_sends_the_picked_daemons() -> void:
	await _setup_ui(7)
	var got := []
	_panel.start_requested.connect(func(v: String, ids: Array): got.append([v, ids]))
	_panel.show_idle("v1", {"access": "ok"})
	await get_tree().process_frame
	_panel.toggle_daemon("d2")   # снять Призрака: цепочка короче — сетка проще
	await get_tree().process_frame
	var start: MbButton = DeckUi.buttons(_panel._frame).filter(func(b: MbButton): return b.text.begins_with("НАЧАТЬ"))[0]
	assert_bool(start.disabled).is_false()
	_click_control(start)
	assert_array(got).is_equal([["v1", ["d1"]]])


func test_start_is_blocked_unless_access_is_ok() -> void:
	await _setup_ui(6)
	for acc in [{"access": "empty", "left": 300}, {"access": "cooldown", "left": 1500}, {"access": "busy"}, {"access": "open"}]:
		_panel.show_idle("v1", acc)
		await get_tree().process_frame
		assert_bool(_panel.request_start()).is_false()
	_panel.show_idle("v1", {"access": "empty", "left": 300})
	assert_str("\n".join(_panel.texts())).contains("ПУСТО · пополнение через 5 мин")
	_panel.show_idle("v1", {"access": "cooldown", "left": 1500})
	assert_str("\n".join(_panel.texts())).contains("ОСТЫВАЕТ · 25 мин")
	_panel.show_idle("v1", {"access": "busy"})
	assert_str("\n".join(_panel.texts())).contains("взламывает другой нетраннер")


func test_denied_reason_is_shown_in_words() -> void:
	await _setup_ui(6)
	_panel.show_idle("v1", {"access": "ok"})
	_panel.show_denied("bad_daemons")
	assert_str("\n".join(_panel.texts())).contains("цепочки должны влезать в RAM")
	assert_str(BreachPanel.denied_text("cooldown", 90)).is_equal("ОСТЫВАЕТ · 2 мин")
	assert_str(BreachPanel.denied_text("empty", 40)).is_equal("ПУСТО · пополнение через 40 с")
	assert_str(BreachPanel.denied_text("whatever")).is_equal("Сейчас нельзя (whatever)")
	assert_str(BreachPanel.denied_text("")).is_equal("Сейчас нельзя")
	# остальные причины — словами, не молча
	for reason in ["busy", "far", "open", "active", "bridge", "charging", "not_ready"]:
		assert_str(BreachPanel.denied_text(reason)).is_not_equal("Сейчас нельзя (%s)" % reason)


func test_denied_bad_daemons_with_numbers_explains_the_ram() -> void:
	await _setup_ui(12)
	_panel.show_idle("v1", {"access": "ok"})
	_panel.show_denied("bad_daemons", 0, {"lock": 3, "need": 15, "ram": 12})
	assert_str("\n".join(_panel.texts())).contains("НЕ ХВАТАЕТ RAM: замок 3 + цепочки 12 > 12 — снимите демона")


func test_idle_redraws_only_on_change() -> void:
	await _setup_ui(6)
	_panel.show_idle("v1", {"access": "ok"})
	await get_tree().process_frame
	var kids := _panel._right.get_child_count()
	var first: Node = _panel._right.get_child(0)
	for i in 5:
		_panel.show_idle("v1", {"access": "ok"})   # так зовёт сцена каждый кадр
	assert_object(_panel._right.get_child(0)).is_same(first)
	assert_int(_panel._right.get_child_count()).is_equal(kids)


func test_grid_shows_cells_of_a_readable_size() -> void:
	await _setup_ui()
	var m := await _start_run("HARD", 6)
	assert_str(_panel.mode()).is_equal(BreachPanel.MODE_RUN)
	assert_int(_panel.cell_nodes().size()).is_equal(36)
	var cell: BreachCell = _panel.cell_nodes()[Vector2i(0, 0)]
	# клетка ≥ 2 см даже на 7×7: размер в пикселях × мм на пиксель
	var cm := cell.custom_minimum_size.x * BreachPanelLayout.WIDTH_M / BreachPanel.VIEW_SIZE.x * 100.0
	assert_float(cm).is_greater(3.0)
	assert_object(m).is_not_null()


func test_seven_by_seven_cell_is_about_three_and_a_half_cm() -> void:
	await _setup_ui()
	await _start_run("NIGHTMARE", 6)
	assert_int(_panel.cell_nodes().size()).is_equal(49)
	var cell: BreachCell = _panel.cell_nodes()[Vector2i(0, 0)]
	var cm := cell.custom_minimum_size.x * BreachPanelLayout.WIDTH_M / BreachPanel.VIEW_SIZE.x * 100.0
	assert_float(cm).is_between(3.4, 3.7)


func test_only_first_row_is_highlighted_at_the_start_then_the_column() -> void:
	await _setup_ui()
	var m := await _start_run()
	var avail := _panel.cell_nodes().values().filter(func(c: BreachCell): return c.is_available())
	assert_int(avail.size()).is_equal(6)
	for c in avail:
		assert_int(c.cell.x).is_equal(0)
	assert_bool(_panel.tap_cell(Vector2i(3, 3))).is_false()   # не подсвечена — не уходит
	var taps := []
	_panel.cell_tapped.connect(func(c: Vector2i): taps.append(c))
	assert_bool(_panel.tap_cell(Vector2i(0, 4))).is_true()
	assert_array(taps).is_equal([Vector2i(0, 4)])
	assert_int(m.selected().size()).is_equal(1)
	# пока сервер не ответил — клетка занята у нас, доступных нет
	assert_int(_panel.cell_nodes().values().filter(func(c: BreachCell): return c.is_available()).size()).is_equal(0)
	_panel.apply_tick({"cell": [0, 4], "ok": true, "left": 59, "matched": []})
	var col := _panel.cell_nodes().values().filter(func(c: BreachCell): return c.is_available())
	assert_int(col.size()).is_equal(5)
	for c in col:
		assert_int(c.cell.y).is_equal(4)


func test_trap_reply_flashes_the_frame_and_marks_the_cell() -> void:
	await _setup_ui()
	await _start_run()
	var felt := [0]
	_panel.trap_felt.connect(func(): felt[0] += 1)
	_panel.tap_cell(Vector2i(0, 0))
	_panel.apply_tick({"cell": [0, 0], "ok": true, "trap": true, "left": 58, "matched": [], "ice": "ICE: ловушка"})
	assert_int(felt[0]).is_equal(1)
	assert_int((_panel.cell_nodes()[Vector2i(0, 0)] as BreachCell).state).is_equal(BreachCell.State.TRAP)
	assert_float(_panel._flash).is_greater(0.0)
	assert_str("\n".join(_panel.texts())).contains("ICE: ловушка")


func test_panel_does_not_shake_it_stays_where_it_was_placed() -> void:
	await _setup_ui()
	await _start_run()
	var at := _panel.global_transform
	_panel.tap_cell(Vector2i(0, 0))
	_panel.apply_tick({"cell": [0, 0], "ok": true, "trap": true, "left": 58, "matched": []})
	for i in 10:
		await get_tree().process_frame
	assert_bool(_panel.global_transform.is_equal_approx(at)).is_true()


func test_trace_colours_the_frame_and_shows_in_the_column() -> void:
	await _setup_ui()
	await _start_run()
	_panel.set_trace(60.0)
	assert_bool(_panel._frame.edge == DeckTheme.BAD).is_true()
	_panel.set_trace(30.0)
	assert_bool(_panel._frame.edge == DeckTheme.WARN).is_true()
	_panel.set_trace(0.0)
	assert_bool(_panel._frame.edge == DeckTheme.ACC).is_true()


func test_targets_show_match_and_timer_counts_down_from_server() -> void:
	await _setup_ui()
	await _start_run()
	assert_str("\n".join(_panel.texts())).contains("1:30")   # таймер HARD в Взломе 2.0: 90 с (был 60)
	_panel.apply_tick({"left": 9, "matched": ["d1"]})
	var all := "\n".join(_panel.texts())
	assert_str(all).contains("0:09").contains("✓")


func test_result_screen_says_what_happened() -> void:
	await _setup_ui()
	await _start_run()
	_panel.apply_end({"outcome": "PARTIAL", "matched": ["d1"], "opened": ["v1"], "eddies": 5, "alert": "СБ получит сигнал через 2 мин", "cooldown": 1800, "early": "teleport"})
	assert_str(_panel.mode()).is_equal(BreachPanel.MODE_RESULT)
	var all := "\n".join(_panel.texts())
	assert_str(all).contains("ВЗЛОМ ЧАСТИЧНО").contains("Хранилище открыто").contains("Эдди +5").contains("СБ получит сигнал через 2 мин").contains("досрочно").contains("30 мин")
	_panel.apply_end({"outcome": "FAIL", "matched": [], "opened": [], "error": "cooldown"})
	all = "\n".join(_panel.texts())
	assert_str(all).contains("ВЗЛОМ ПРОВАЛЕН").contains("Хранилище не открылось").contains("Мост не принял итог")


func test_cell_tap_by_the_right_hand_pointer() -> void:
	await _setup_ui()
	var m := await _start_run()
	var taps := []
	_panel.cell_tapped.connect(func(c: Vector2i): taps.append(c))
	var target: BreachCell = _panel.cell_nodes()[Vector2i(0, 2)]
	_click_control(target)
	assert_array(taps).is_equal([Vector2i(0, 2)])
	assert_int(m.selected().size()).is_equal(1)
	# недоступная клетка указкой не нажимается
	var far: BreachCell = _panel.cell_nodes()[Vector2i(4, 4)]
	_click_control(far)
	assert_array(taps).is_equal([Vector2i(0, 2)])


func test_cancel_button_asks_to_finish() -> void:
	await _setup_ui()
	await _start_run()
	var got := [0]
	_panel.cancel_requested.connect(func(): got[0] += 1)
	var stop: MbButton = DeckUi.buttons(_panel._frame).filter(func(b: MbButton): return b.text == "ЗАВЕРШИТЬ")[0]
	assert_bool(stop.button_height >= 46).is_true()
	_click_control(stop)
	assert_int(got[0]).is_equal(1)


func test_close_button_hides_the_result() -> void:
	await _setup_ui()
	await _start_run()
	_panel.apply_end({"outcome": "FAIL", "matched": [], "opened": []})
	var close: MbButton = DeckUi.buttons(_panel._frame).filter(func(b: MbButton): return b.text == "ЗАКРЫТЬ")[0]
	_click_control(close)
	assert_str(_panel.mode()).is_equal(BreachPanel.MODE_HIDDEN)


func test_deck_pointer_and_breach_pointer_do_not_fight() -> void:
	await _setup_ui()
	await _start_run()
	# луч в панель взлома: деке события не идут
	var r := _ray_at(Vector2(400, 200))
	_ui.breach_pointer.update_ray(r["origin"], r["dir"])
	assert_bool(_ui.breach_pointer.hovering).is_true()
	_ui.pointer.update_ray(r["origin"], r["dir"])
	assert_bool(_ui.pointer.hovering).is_false()


func test_итог_называет_причину_провала_замок_и_совпал_до_вскрытия() -> void:
	await _setup_ui()
	var m := await _start_run()   # HARD: у хранилища есть замок
	assert_int(m.lock.size()).is_greater(0)
	m.trap_hits[Vector2i(0, 0)] = true
	m.trap_hits[Vector2i(0, 1)] = true
	_panel.apply_end({"outcome": "FAIL", "matched": [], "opened": [], "lock_opened": false, "matched_before_lock": ["d1"]})
	var all := "\n".join(_panel.texts())
	assert_str(all).contains("ЗАМОК: 2 ловушки из 2 нажатий — провал").contains("совпал до вскрытия — не засчитан")
	assert_array(BreachPanel.reason_lines({"outcome": "SUCCESS"}, m)).is_empty()
	assert_array(BreachPanel.reason_lines({"outcome": "FAIL"}, null)).is_empty()   # без копии попытки о замке сказать нечего

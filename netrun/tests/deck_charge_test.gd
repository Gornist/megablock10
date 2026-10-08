extends GdUnitTestSuite
## Заряд на деке запястья (К6): кнопка «ЗАРЯДИТЬ», сетка вместо списка, подсветка доступных клеток клиентом, итог, возврат к вкладкам; размер клетки не мельче
## ~2 см на деке в масштабе 1 (на время сетки WorldUI увеличивает деку); вспомогательная математика WorldUI.

var _d: DeckPanel


func _panel() -> void:
	_d = auto_free(DeckPanel.new())
	add_child(_d)
	await get_tree().process_frame


func _deck(st: String = "ready") -> Dictionary:
	return {"daemons": [
		{"id": "g", "name": "1 Призрак", "cooldown_left": 0.0, "st": st, "chargeable": true, "tier": 1, "cells": ["1C", "BD"], "effect": "GHOST"},
		{"id": "x", "name": "2 Извлечение", "cooldown_left": 0.0, "st": "ready", "chargeable": false, "tier": 1, "cells": ["55", "7A"], "effect": "EXTRACT_SHARD"}],
		"selected": "g"}


func _bk(daemon_tier: int = 1, seed_value: int = 5) -> Dictionary:
	var d := BreachDaemon.make("g", ["1C", "BD"], "GHOST", daemon_tier, "Призрак")
	var run := BreachRun.for_charge(d, seed_value)
	return {"kind": WorldMsg.EV_BK, "mode": "charge", "daemon": "g", "vault": "", "n": 0, "tier": run.tier, "grid": VaultBreach.public_grid(run.attempt.grid),
		"targets": [{"id": "g", "name": "Призрак", "effect": "GHOST", "cells": ["1C", "BD"]}], "buffer": run.attempt.buffer_size, "sec": run.timer_sec}


func _buttons_texts() -> Array:
	return DeckUi.buttons(_d).map(func(b: MbButton) -> String: return b.text)


func test_charge_button_is_on_the_chargeable_program_only_and_asks_the_server() -> void:
	await _panel()
	_d.set_deck(_deck())
	await get_tree().process_frame
	var charge_buttons: Array = DeckUi.buttons(_d).filter(func(b: MbButton) -> bool: return b.text == "ЗАРЯДИТЬ")
	assert_int(charge_buttons.size()).is_equal(1)   # у Извлечения кнопки нет
	assert_bool(_d.is_interactive()).is_true()       # деку есть чем нажимать
	var asked := []
	_d.charge_requested.connect(func(id: String): asked.append(id))
	(charge_buttons[0] as MbButton).click()
	assert_array(asked).is_equal(["g"])


func test_a_charged_program_shows_ready_to_launch_and_the_hint_instead_of_the_button() -> void:
	await _panel()
	_d.set_deck(_deck("charged"))
	await get_tree().process_frame
	assert_array(_buttons_texts()).not_contains(["ЗАРЯДИТЬ"])
	assert_str("\n".join(_d.row_texts())).contains("1 Призрак  ГОТОВ К ЗАПУСКУ")
	assert_str("\n".join(_d.row_texts())).contains(HudLogic.LAUNCH_HINT)
	# плашка «ЗАРЯЖЕН · включить: левый X» — первой в списке, видна без прокрутки; не заряженному её нет
	assert_str("\n".join(DeckUi.texts(_d._list.get_child(0)))).contains("ЗАРЯЖЕН · включить: левый X")
	_d.set_deck(_deck("ready"))
	await get_tree().process_frame
	assert_str("\n".join(DeckUi.texts(_d))).not_contains("включить: левый X")


func test_cooldown_and_active_programs_have_no_charge_button() -> void:
	await _panel()
	for st in ["cooldown", "active"]:
		_d.set_deck(_deck(st))
		await get_tree().process_frame
		assert_array(_buttons_texts()).not_contains(["ЗАРЯДИТЬ"])


func test_the_grid_replaces_the_tabs_and_the_list_then_the_result_brings_them_back() -> void:
	await _panel()
	_d.set_deck(_deck())
	assert_bool(_d.begin_charge(BreachMirror.from_event(_bk()))).is_true()
	await get_tree().process_frame
	assert_bool(_d.is_charging()).is_true()
	assert_bool(_d.tabs().visible).is_false()
	assert_bool(_d.charge_view().visible).is_true()
	assert_int(_d.charge_view().cell_nodes().size()).is_equal(25)   # тир 1 → 5×5
	assert_str("\n".join(_d.charge_view().texts())).contains("ЗАРЯД").contains("Призрак").contains("0:45")
	# Входящее сообщение или звонок не должны вернуть вкладки посреди сетки.
	_d.select_tab(DeckPanel.TAB_DECK)
	assert_bool(_d.charge_view().visible).is_true()
	_d.apply_charge_end({"kind": WorldMsg.EV_BK_END, "mode": "charge", "daemon": "g", "outcome": "SUCCESS", "charged": true})
	assert_str("\n".join(_d.charge_view().texts())).contains("ЗАРЯЖЕН")
	_d._process(DeckCharge.RESULT_SEC + 0.1)
	_d.charge_view()._process(DeckCharge.RESULT_SEC + 0.1)
	await get_tree().process_frame
	assert_bool(_d.is_charging()).is_false()
	assert_bool(_d.tabs().visible).is_true()
	assert_bool(_d.active_tab() == DeckPanel.TAB_DECK).is_true()


func test_available_cells_light_up_on_the_client_and_a_tap_goes_out_once() -> void:
	await _panel()
	var m := BreachMirror.from_event(_bk())
	_d.begin_charge(m)
	var cv := _d.charge_view()
	var taps := []
	_d.charge_cell_tapped.connect(func(c: Vector2i): taps.append(c))
	# Первый тап — любая клетка верхней строки; остальные недоступны.
	for c in cv.cell_nodes():
		var cell: BreachCell = cv.cell_nodes()[c]
		assert_bool(cell.is_available()).is_equal(c.x == 0)
	assert_bool(cv.tap_cell(Vector2i(2, 2))).is_false()   # недоступная клетка ничего не шлёт
	assert_bool(cv.tap_cell(Vector2i(0, 3))).is_true()
	assert_array(taps).is_equal([Vector2i(0, 3)])
	assert_bool(cv.tap_cell(Vector2i(1, 3))).is_false()   # подтверждения сервера ещё нет: второй тап не уходит
	_d.apply_charge_tick({"kind": WorldMsg.EV_BK_TICK, "mode": "charge", "cell": [0, 3], "ok": true, "trap": false, "matched": [], "left": 44})
	var avail := 0
	for c in cv.cell_nodes():
		if (cv.cell_nodes()[c] as BreachCell).is_available():
			avail += 1
	assert_int(avail).is_greater(0)   # после подтверждения открылся столбец
	assert_str("\n".join(cv.texts())).contains("0:44")


func test_cancel_button_asks_the_server_to_stop() -> void:
	await _panel()
	_d.begin_charge(BreachMirror.from_event(_bk()))
	var stops := []
	_d.charge_cancel_requested.connect(func(): stops.append(1))
	var cancel: Array = DeckUi.buttons(_d).filter(func(b: MbButton) -> bool: return b.text == "ОТМЕНА")
	assert_int(cancel.size()).is_equal(1)
	(cancel[0] as MbButton).click()
	assert_int(stops.size()).is_equal(1)


func test_a_denial_shows_a_notice_that_goes_away() -> void:
	await _panel()
	_d.show_charge_denied("cooldown", 42)
	assert_str(_d.notice_text()).is_equal("Перезарядка: 42 с")
	_d._process(DeckPanel.NOTICE_SEC + 0.1)
	assert_str(_d.notice_text()).is_empty()


func test_a_cell_is_at_least_2_cm_on_a_deck_at_scale_1_for_every_tier() -> void:
	for size in [5, 6, 7]:
		var px := DeckCharge.cell_px(size)
		assert_float(DeckPanel.px_to_cm(px, WorldUI.CHARGE_DECK_SCALE)).is_greater_equal(2.0)
		# Сетка с промежутками влезает в отведённую ширину, справа остаётся место для таймера и цепочки.
		assert_int(px * size + DeckCharge.GRID_GAP * (size - 1)).is_less_equal(DeckCharge.GRID_MAX_W)
	# Без увеличения (дека на запястье в 0,75) 7×7 было бы мельче — поэтому дека растёт на время сетки.
	assert_float(DeckPanel.px_to_cm(DeckCharge.cell_px(7), WorldUI.WRIST_DECK_SCALE)).is_greater_equal(2.0)


func test_wrist_deck_pos_keeps_the_near_edge_at_the_gap_for_any_scale() -> void:
	assert_vector(WorldUI.wrist_deck_pos(WorldUI.WRIST_DECK_SCALE)).is_equal_approx(WorldUI.WRIST_DECK_POS, Vector3(0.0001, 0.0001, 0.0001))
	assert_vector(WorldUI.wrist_trace_pos(WorldUI.WRIST_DECK_SCALE)).is_equal_approx(WorldUI.WRIST_TRACE_POS, Vector3(0.0001, 0.0001, 0.0001))
	for sc in [0.75, 1.0]:
		var length: float = DeckPanel.PANEL_WIDTH_M * sc
		var near_edge := WorldUI.wrist_deck_pos(sc).y + length * 0.5   # ближний к кисти край (Y якоря — к пальцам)
		assert_float(near_edge).is_equal_approx(HandView.WRIST_ANCHOR_ELBOW * 1.0 - WorldUI.WRIST_DECK_GAP, 0.0001)


func test_кольцо_такта_на_запястье_над_верхним_краем_деки_и_меньше_прежнего() -> void:
	for sc in [WorldUI.WRIST_DECK_SCALE, WorldUI.CHARGE_DECK_SCALE]:
		# в осях якоря: позиция кольца = trace.position + wrist_ring_pos; «верх» деки — локальный +Y, повёрнутый на WRIST_DECK_ROLL_DEG вокруг Z
		var ring: Vector3 = WorldUI.wrist_trace_pos(sc) + WorldUI.wrist_ring_pos(sc)
		var rel := ring - WorldUI.wrist_deck_pos(sc)
		var up_axis := Basis(Vector3.BACK, deg_to_rad(WorldUI.WRIST_DECK_ROLL_DEG)) * Vector3.UP
		assert_float(rel.dot(up_axis)).is_greater(DeckPanel.PANEL_HEIGHT_M * sc * 0.5)   # за верхним краем, а не поверх панели
		assert_float(rel.dot(up_axis)).is_less(DeckPanel.PANEL_HEIGHT_M * sc * 0.5 + 0.06)
		assert_float(rel.z).is_greater(0.0)   # чуть выше плоскости деки
	assert_float(TickRing.R_OUT).is_less(0.02)


func test_a_grid_the_server_stopped_ticking_for_is_dropped() -> void:
	await _panel()
	_d.begin_charge(BreachMirror.from_event(_bk()))
	_d.charge_view()._process(DeckCharge.STALE_SEC - 1.0)
	assert_bool(_d.is_charging()).is_true()
	_d.apply_charge_tick({"kind": WorldMsg.EV_BK_TICK, "mode": "charge", "left": 40})   # весть от сервера сбрасывает отсчёт
	_d.charge_view()._process(DeckCharge.STALE_SEC - 1.0)
	assert_bool(_d.is_charging()).is_true()
	_d.charge_view()._process(2.0)   # тишина дольше STALE_SEC: рестарт сервера или обрыв — попытки уже нет
	await get_tree().process_frame
	assert_bool(_d.is_charging()).is_false()
	assert_bool(_d.tabs().visible).is_true()

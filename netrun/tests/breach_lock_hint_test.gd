extends GdUnitTestSuite
## Подсказка замка на панели взлома (П7, 16.10: владелец набрал демона до замка и не понял, почему «не срабатывает»): замок первым в списке целей,
## «1. ЗАМОК → 2. демоны», после вскрытия — «замок вскрыт», демон, совпавший до замка, помечен «не засчитан»; правило видно и до старта.

var _rig: XRRig
var _ui: WorldUI
var _panel: BreachPanel

const DAEMONS := [
	{"id": "d1", "name": "Извлечение", "effect": "EXTRACT_SHARD", "tier": 2, "cells": ["1C", "BD"]},
	{"id": "d2", "name": "Призрак", "effect": "GHOST", "tier": 1, "cells": ["55", "7A", "FF"]},
]


func _setup_ui(ram: int = 12) -> void:
	_rig = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	add_child(_rig)
	_ui = auto_free(WorldUI.new())
	add_child(_ui)
	_ui.attach(_rig)
	_panel = _ui.breach_panel
	_panel.set_context("Серверная", "HARD", DAEMONS, ram)
	for i in 3:
		await get_tree().process_frame


func _start_run() -> BreachMirror:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event("HARD", 77, 12))
	_panel.place(BreachPanelLayout.pose(Vector3(0, 1.2, 0), Vector3(0, 1, -1.5)))
	_panel.begin(m)
	for i in 3:
		await get_tree().process_frame
	return m


func _all() -> String:
	return "\n".join(_panel.texts())


func test_замок_первым_и_подсказка_пока_он_закрыт() -> void:
	await _setup_ui()
	var m := await _start_run()
	assert_int(m.lock.size()).is_greater(0)
	var all := _all()
	assert_str(all).contains(BreachPanel.lock_row_text(false))
	assert_str(all).contains(BreachPanel.lock_hint_text())
	assert_str(all).contains(" ".join(m.lock))   # коды замка перечислены


func test_после_вскрытия_замок_вскрыт_и_подсказки_нет() -> void:
	await _setup_ui()
	var m := await _start_run()
	m.lock_opened = true
	_panel._refresh_run()
	await get_tree().process_frame
	var all := _all()
	assert_str(all).contains(BreachPanel.lock_row_text(true))
	assert_str(all).not_contains(BreachPanel.lock_hint_text())


func test_демон_совпавший_до_замка_помечен_не_засчитанным() -> void:
	await _setup_ui()
	var m := await _start_run()
	m.matched = ["d1"]
	_panel._refresh_run()
	await get_tree().process_frame
	assert_str(_all()).contains("до замка, не засчитан")
	m.lock_opened = true
	_panel._refresh_run()
	await get_tree().process_frame
	assert_str(_all()).not_contains("до замка, не засчитан")


func test_правило_видно_до_старта() -> void:
	await _setup_ui()
	_panel.show_idle("v1", {"access": "ok"})
	await get_tree().process_frame
	assert_str(_all()).contains("сначала наберите его цепочку")


func test_тексты_замка() -> void:
	assert_str(BreachPanel.lock_row_text(false)).contains("1. ЗАМОК")
	assert_str(BreachPanel.lock_hint_text()).contains("2. ДЕМОНЫ")
	assert_str(BreachPanel.lock_row_text(true)).contains("ЗАМОК ВСКРЫТ")

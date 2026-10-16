extends GdUnitTestSuite
## Клиент вскрытия барьера Soft ICE (ice.md §5): полоса «ВСКРЫТЬ» / «СИЛОЙ» на деке рядом с закрытым барьером, мини-игра режима barrier на деке запястья,
## строка удержания силового вскрытия, итог; вид барьера по полю br state; тексты отказов.

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


func _state(open: int, cells: Array) -> Dictionary:
	return {"k": 1.0, "trace": 0.0, "level": 0, "cd": [], "ice": [], "br": [{"id": "bar1", "c": cells, "open": open}]}


func test_тексты_отказов_и_удержания() -> void:
	assert_str(HudLogic.barrier_denied_text("far")).contains("вплотную")
	assert_str(HudLogic.barrier_denied_text("open")).contains("вскрыт")
	assert_str(HudLogic.barrier_denied_text("active")).contains("мини-игра")
	assert_str(HudLogic.barrier_force_text(2)).contains("2 такта")
	assert_str(HudLogic.barrier_force_text(1)).contains("1 такт")
	assert_str(HudLogic.barrier_force_text(0)).contains("вскрыт")


func test_барьер_рядом_закрыт_полоса_на_деке_далеко_или_открыт_нет() -> void:
	_scene.apply_state(_state(0, _near_cells()))
	assert_bool(_scene.world_ui.deck.barrier_row_visible()).is_true()
	assert_object(_scene.barrier_view_of("bar1")).is_not_null()
	_scene.apply_state(_state(1, _near_cells()))   # вскрыт
	assert_bool(_scene.world_ui.deck.barrier_row_visible()).is_false()
	var far := [[40, 40], [41, 40], [40, 41], [41, 41]]
	_scene.apply_state(_state(0, far))
	assert_bool(_scene.world_ui.deck.barrier_row_visible()).is_false()
	_scene.apply_state({"k": 2.0, "trace": 0.0, "level": 0, "cd": [], "ice": []})   # поля br нет — вид убран
	assert_object(_scene.barrier_view_of("bar1")).is_null()


func test_вид_барьера_центр_блока_и_видимое_состояние() -> void:
	var cells := [[6, 4], [7, 4], [6, 5], [7, 5]]
	assert_object(BarrierView.center_of(cells)).is_equal(Vector3((NodeGrid.center(Vector2i(6, 4)).x + NodeGrid.center(Vector2i(7, 4)).x) / 2.0, 0.0, (NodeGrid.center(Vector2i(6, 4)).z + NodeGrid.center(Vector2i(6, 5)).z) / 2.0))
	assert_str(BarrierView.state_node_of(0)).is_equal("State_closed")
	assert_str(BarrierView.state_node_of(1)).is_equal("State_open")
	_scene.apply_state(_state(0, cells))
	var v := _scene.barrier_view_of("bar1") as BarrierView
	assert_bool((v.find_child("State_closed", true, false) as Node3D).visible).is_true()
	assert_bool((v.find_child("State_open", true, false) as Node3D).visible).is_false()
	_scene.apply_state(_state(1, cells))
	assert_bool((v.find_child("State_open", true, false) as Node3D).visible).is_true()
	assert_bool((v.find_child("State_closed", true, false) as Node3D).visible).is_false()


func test_нажатия_на_деке_просят_вскрыть_обоими_способами() -> void:
	_scene.apply_state(_state(0, _near_cells()))
	var got: Array = []
	_scene.barrier_requested.connect(func(id: String, how: String): got.append([id, how]))
	_scene.world_ui.deck._barrier_open_btn.pressed.emit()
	_scene.world_ui.deck._barrier_force_btn.pressed.emit()
	assert_array(got).is_equal([["bar1", "charge"], ["bar1", "force"]])


func test_силовое_вскрытие_строка_удержания_и_итог() -> void:
	var deck: DeckPanel = _scene.world_ui.deck
	_scene.apply_breach_event({"kind": WorldMsg.EV_BK, "mode": "barrier", "how": "force", "barrier": "bar1", "ticks": 2})
	assert_bool(deck.barrier_force_active()).is_true()
	assert_bool(deck.barrier_row_visible()).is_true()
	_scene.apply_breach_event({"kind": WorldMsg.EV_BK_TICK, "mode": "barrier", "left_ticks": 1})
	assert_str(deck._barrier_label.text).contains("1 такт")
	_scene.apply_breach_event({"kind": WorldMsg.EV_BK_END, "mode": "barrier", "how": "force", "barrier": "bar1", "outcome": "SUCCESS", "opened": true})
	assert_bool(deck.barrier_force_active()).is_false()
	assert_str(deck.notice_text()).contains("вскрыт")


func test_мини_игра_барьера_идёт_на_деке_как_заряд_и_даёт_итог() -> void:
	var deck: DeckPanel = _scene.world_ui.deck
	var run := BreachRun.for_barrier("NIGHTMARE", 7)
	var target: BreachDaemon = run.attempt.daemons[0]
	var ev := {"kind": WorldMsg.EV_BK, "mode": "barrier", "how": "charge", "barrier": "bar1", "vault": "", "n": 0, "tier": run.tier,
		"grid": VaultBreach.public_grid(run.attempt.grid),
		"targets": [{"id": target.id, "name": target.display_name, "effect": target.effect, "cells": target.sequence.duplicate()}],
		"buffer": run.attempt.buffer_size, "sec": run.timer_sec}
	_scene.apply_breach_event(ev)
	assert_bool(deck.is_charging()).is_true()
	assert_str(deck.charge_view().mode).is_equal("barrier")
	assert_str(DeckCharge.head_text("barrier")).is_equal("БАРЬЕР")
	_scene.apply_breach_event({"kind": WorldMsg.EV_BK_END, "mode": "barrier", "how": "charge", "barrier": "bar1", "outcome": "SUCCESS", "opened": true, "left": 10})
	assert_bool(deck.charge_view().charged).is_true()


func test_отказ_сервера_строка_на_деке() -> void:
	_scene.apply_breach_event({"kind": WorldMsg.EV_BK_NO, "mode": "barrier", "reason": "far"})
	assert_str(_scene.world_ui.deck.notice_text()).contains("вплотную")

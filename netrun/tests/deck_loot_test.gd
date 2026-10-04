extends GdUnitTestSuite
## Деки: полоса RAM, плашки ПРОГРАММ (цепочка моноширинным ≥ 19 px) и вкладка ДОБЫЧА — вид и пустые состояния. Без сервера: данные подаёт тест.

const T0 := 1_700_000_000.0

var _d: DeckPanel


func _setup_panel() -> void:
	_d = auto_free(DeckPanel.new())
	add_child(_d)
	await _settle()


func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _program(id: String, name: String, st: String = "ready", cells: Array = ["1C", "BD", "E9"]) -> Dictionary:
	return {"id": id, "name": name, "cooldown_left": 0.0, "st": st, "tier": 2, "cells": cells, "effect": "GHOST"}


func _all_texts() -> String:
	return "\n".join(DeckUi.texts(_d))


func test_loot_tab_is_absent_until_the_server_sends_the_deck() -> void:
	await _setup_panel()
	assert_array(_d.tab_ids()).is_equal([DeckPanel.TAB_DECK])
	assert_bool(_d.has_loot_tab()).is_false()
	assert_bool(_d.is_interactive()).is_false()
	_d.select_tab(DeckPanel.TAB_LOOT)   # вкладки нет — выбор молча игнорируется
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_DECK)


func test_loot_tab_appears_between_deck_and_chat() -> void:
	await _setup_panel()
	_d.set_phone(FakePhoneLink.new(T0, false))
	_d.set_loot([], 0)
	assert_array(_d.tab_ids()).is_equal([DeckPanel.TAB_DECK, DeckPanel.TAB_LOOT, DeckPanel.TAB_CHAT, DeckPanel.TAB_CALLS])
	assert_bool(_d.is_interactive()).is_true()
	_d.set_phone(null)   # без телефона ДОБЫЧА остаётся: это не телефонная вкладка
	assert_array(_d.tab_ids()).is_equal([DeckPanel.TAB_DECK, DeckPanel.TAB_LOOT])
	assert_bool(_d.is_interactive()).is_true()


func test_loot_tab_shows_empty_state() -> void:
	await _setup_panel()
	_d.set_loot([], 0)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	assert_str(_all_texts()).contains("Добычи пока нет")
	assert_str(_d.loot_texts()[1]).is_equal("Эдди  0")
	assert_bool(_d.has_viewport_surface()).is_true()


func test_loot_tab_lists_shards_daemons_and_eddies_without_actions() -> void:
	await _setup_panel()
	_d.set_loot([
		{"id": "1", "kind": "shard", "tier": 2, "title": "Чертежи склада", "enc": true},
		{"id": "2", "kind": "shard", "tier": 1, "title": "Накладная", "enc": false},
		{"id": "3", "kind": "daemon", "tier": 3, "title": "Дрожь", "enc": false},
	], 120)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	var t := _all_texts()
	assert_str(t).contains("Чертежи склада").contains("ЗАШИФРОВАН").contains("Накладная").contains("ОТКРЫТ").contains("Дрожь").contains("120")
	assert_array(DeckUi.buttons(_d._loot_scroll)).is_empty()   # действий пока нет
	assert_int(_d.loot_texts().size()).is_equal(5)   # заголовок, эдди, три строки


func test_loot_update_changes_the_rows_and_does_not_redraw_when_same() -> void:
	await _setup_panel()
	var loot := [{"id": "1", "kind": "shard", "tier": 1, "title": "Один", "enc": false}]
	_d.set_loot(loot, 0)
	_d._process(1.0)
	var n := _d.redraw_count
	_d.set_loot(loot.duplicate(true), 0)
	_d._process(1.0)
	assert_int(_d.redraw_count).is_equal(n)
	loot.append({"id": "2", "kind": "shard", "tier": 1, "title": "Два", "enc": true})
	_d.set_loot(loot, 0)
	_d._process(1.0)
	assert_int(_d.redraw_count).is_equal(n + 1)
	assert_int(_d.loot_texts().size()).is_equal(4)


func test_loot_tab_scrolls_with_the_stick() -> void:
	await _setup_panel()
	var loot := []
	for i in 12:
		loot.append({"id": str(i), "kind": "shard", "tier": 1, "title": "Шард %d" % i, "enc": i % 2 == 0})
	_d.set_loot(loot, 0)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	_d.scroll_by(120.0)
	await _settle()
	assert_int(_d._loot_scroll.scroll_vertical).is_greater(0)


func test_ram_bar_shows_used_over_capacity_and_marks_the_default() -> void:
	await _setup_panel()
	_d.set_deck({"daemons": [_program("a", "Призрак")], "selected": "a", "ram": 6, "used": 4, "ram_default": true})
	await _settle()
	var t := _all_texts()
	assert_str(t).contains("RAM").contains("4/6").contains("ПО УМОЛЧАНИЮ")
	_d.set_deck({"daemons": [_program("a", "Призрак")], "selected": "a", "ram": 8, "used": 5, "ram_default": false})
	await _settle()
	t = _all_texts()
	assert_str(t).contains("5/8")
	assert_str(t).not_contains("ПО УМОЛЧАНИЮ")
	assert_str(_d.row_texts()[0]).is_equal("ПРОГРАММЫ")


func test_no_ram_bar_for_a_plain_deck() -> void:
	await _setup_panel()
	_d.set_deck({"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 0.0}], "selected": "x"})
	await _settle()
	assert_str(_all_texts()).not_contains("RAM")
	assert_str(_d.row_texts()[1]).is_equal("> Взлом  готово")


func test_program_plate_shows_tier_chain_effect_and_state() -> void:
	await _setup_panel()
	_d.set_deck({"daemons": [_program("a", "1 Призрак"), _program("b", "2 Дрожь", "unsupported", [])], "selected": "a"})
	await _settle()
	var t := _all_texts()
	assert_str(t).contains("тир 2").contains("1C BD E9").contains("невидим для ICE").contains("готов").contains("не работает в Сети")


func test_chain_uses_a_monospace_font_of_at_least_19_px() -> void:
	var th := DeckTheme.theme()
	assert_int(th.get_font_size("font_size", DeckTheme.V_CODE)).is_greater_equal(19)
	assert_object(th.get_font("font", DeckTheme.V_CODE)).is_same(DeckTheme.font_mono())
	await _setup_panel()
	_d.set_deck({"daemons": [_program("a", "Призрак")], "selected": "a"})
	await _settle()
	var found := false
	for l in _labels(_d):
		if l.text == "1C BD E9":
			found = true
			assert_str(String(l.theme_type_variation)).is_equal(String(DeckTheme.V_CODE))
	assert_bool(found).is_true()


func test_program_states_active_and_cooldown_are_visible() -> void:
	await _setup_panel()
	var a := _program("a", "1 Призрак", "active")
	a["active_left"] = 12.0
	var b := _program("b", "2 Дрожь", "cooldown")
	b["cooldown_left"] = 41.0
	_d.set_deck({"daemons": [a, b], "selected": "a"})
	await _settle()
	assert_str(_d.row_texts()[1]).is_equal("> 1 Призрак  активен 12 с")
	assert_str(_d.row_texts()[2]).is_equal("  2 Дрожь  перезарядка 41 с")


func test_empty_deck_says_so() -> void:
	await _setup_panel()
	_d.set_deck({"daemons": [], "selected": "", "ram": 6, "used": 0, "ram_default": true})
	await _settle()
	assert_str(_all_texts()).contains("Программ нет").contains("0/6")


func test_long_names_do_not_widen_the_panel() -> void:
	await _setup_panel()
	var long_name := "Очень длинное название демона которое не помещается в строку деки"
	_d.set_deck({"daemons": [_program("a", "1 " + long_name, "cooldown", ["1C", "BD", "E9", "A7", "55", "7A"])], "selected": "a", "ram": 6, "used": 6})
	_d.set_loot([{"id": "1", "kind": "shard", "tier": 1, "title": long_name, "enc": true}], 123456)
	await _settle()
	var scroll_w := _d._deck_scroll.size.x
	assert_float(_d._list.size.x).is_less_equal(scroll_w)
	assert_float(_d._deck_scroll.get_h_scroll_bar().max_value).is_less_equal(scroll_w + 1.0)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	assert_float(_d._loot_list.size.x).is_less_equal(_d._loot_scroll.size.x)


func test_tab_switch_shows_only_that_screen_with_loot() -> void:
	await _setup_panel()
	_d.set_loot([], 0)
	_d.select_tab(DeckPanel.TAB_LOOT)
	assert_bool(_d._loot_scroll.visible).is_true()
	assert_bool(_d._deck_scroll.visible).is_false()
	_d.select_tab(DeckPanel.TAB_DECK)
	assert_bool(_d._loot_scroll.visible).is_false()
	assert_bool(_d._deck_scroll.visible).is_true()


func _labels(node: Node) -> Array:
	var out := []
	for c in DeckUi.live_children(node):
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out


func test_loot_tab_shows_a_carried_daemon_with_effect_and_chain() -> void:
	await _setup_panel()
	_d.set_loot([{"id": "9", "kind": "daemon", "tier": 2, "title": "Жнец", "enc": false, "give": false, "effect": "EXTRACT_SHARD", "cells": ["BD", "E9", "1C"]}], 0)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	assert_str(_d.loot_texts()[2]).is_equal("ДЕМОН  Жнец  тир 2  достать шард")
	assert_str(_all_texts()).contains("BD E9 1C").contains("В ГРУЗЕ").contains("достать шард")

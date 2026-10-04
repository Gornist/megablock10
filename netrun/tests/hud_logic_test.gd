extends GdUnitTestSuite


func test_level_from_value() -> void:
	assert_int(HudLogic.level_from_value(0.0)).is_equal(HudLogic.LEVEL_NORMAL)
	assert_int(HudLogic.level_from_value(25.0)).is_equal(HudLogic.LEVEL_SUSPICIOUS)
	assert_int(HudLogic.level_from_value(50.0)).is_equal(HudLogic.LEVEL_TRACE)
	assert_int(HudLogic.level_from_value(75.0)).is_equal(HudLogic.LEVEL_LOCKDOWN)
	assert_int(HudLogic.level_from_value(100.0)).is_equal(HudLogic.LEVEL_FLATLINE)


func test_colors_differ_and_text() -> void:
	assert_bool(HudLogic.level_color(0) != HudLogic.level_color(3)).is_true()
	assert_str(HudLogic.trace_text(42.4, HudLogic.LEVEL_SUSPICIOUS)).is_equal("подозрение 42")
	assert_float(HudLogic.trace_fraction(150.0)).is_equal(1.0)
	assert_float(HudLogic.trace_fraction(25.0)).is_equal(0.25)


func test_cooldown_text() -> void:
	assert_str(HudLogic.cooldown_text(0.0)).is_equal("готово")
	assert_str(HudLogic.cooldown_text(-3.0)).is_equal("готово")
	assert_str(HudLogic.cooldown_text(0.2)).is_equal("1 с")
	assert_str(HudLogic.cooldown_text(12.4)).is_equal("13 с")
	assert_str(HudLogic.cooldown_text(75.0)).is_equal("1:15")


func test_point_visibility() -> void:
	var cam := Transform3D.IDENTITY  # смотрит в -Z
	assert_bool(HudLogic.is_point_visible(cam, Vector3(0, 0, -5), 90.0, 1.0)).is_true()
	assert_bool(HudLogic.is_point_visible(cam, Vector3(0, 0, 5), 90.0, 1.0)).is_false()
	assert_bool(HudLogic.is_point_visible(cam, Vector3(6, 0, -5), 90.0, 1.0)).is_false()
	assert_bool(HudLogic.is_point_visible(cam, Vector3(4, 0, -5), 90.0, 1.0)).is_true()
	# Шире кадр — то же смещение по X уже видно.
	assert_bool(HudLogic.is_point_visible(cam, Vector3(8, 0, -5), 90.0, 2.0)).is_true()
	# Камера повернута вправо на 90° — точка по -Z уже слева за краем.
	var turned := Transform3D(Basis.from_euler(Vector3(0, -PI / 2, 0)), Vector3.ZERO)
	assert_bool(HudLogic.is_point_visible(turned, Vector3(0, 0, -5), 90.0, 1.0)).is_false()
	assert_bool(HudLogic.is_point_visible(turned, Vector3(5, 0, 0), 90.0, 1.0)).is_true()


func test_edge_direction() -> void:
	var cam := Transform3D.IDENTITY
	assert_vector(HudLogic.edge_direction(cam, Vector3(5, 0, 0))).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	assert_vector(HudLogic.edge_direction(cam, Vector3(0, -3, 2))).is_equal_approx(Vector2(0, -1), Vector2(0.001, 0.001))
	assert_vector(HudLogic.edge_direction(cam, Vector3(0, 0, 5))).is_equal(Vector2.UP)


func test_deck_rows() -> void:
	var rows := HudLogic.deck_rows({
		"daemons": [{"id": "a", "name": "А", "cooldown_left": 0.0}, {"id": "b", "name": "Б", "cooldown_left": 5.0}],
		"selected": "b",
	})
	assert_int(rows.size()).is_equal(2)
	assert_bool(rows[0]["ready"]).is_true()
	assert_bool(rows[1]["selected"]).is_true()
	assert_str(rows[1]["text"]).is_equal("Б  5 с")


func test_state_text_covers_every_program_state() -> void:
	assert_str(HudLogic.state_text("ready", 0.0)).is_equal("готов")
	assert_str(HudLogic.state_text("cooldown", 42.0)).is_equal("перезарядка 42 с")
	assert_str(HudLogic.state_text("cooldown", 75.0)).is_equal("перезарядка 1:15")
	assert_str(HudLogic.state_text("active", 0.0, 12.2)).is_equal("активен 13 с")
	assert_str(HudLogic.state_text("unsupported", 0.0)).is_equal("не работает в Сети")
	assert_str(HudLogic.state_text("", 0.0)).is_equal("готово")   # старый снимок без st
	assert_str(HudLogic.state_text("", 5.0)).is_equal("5 с")


func test_state_tone() -> void:
	assert_str(HudLogic.state_tone("ready", 0.0)).is_equal("ok")
	assert_str(HudLogic.state_tone("cooldown", 5.0)).is_equal("warn")
	assert_str(HudLogic.state_tone("active", 0.0)).is_equal("acc")
	assert_str(HudLogic.state_tone("unsupported", 0.0)).is_equal("dim")
	assert_str(HudLogic.state_tone("", 3.0)).is_equal("warn")


func test_ram_view() -> void:
	assert_object(HudLogic.ram_view(0, 0)).is_null()
	var v: Dictionary = HudLogic.ram_view(6, 4, true)
	assert_str(v["text"]).is_equal("4/6")
	assert_float(v["fraction"]).is_equal_approx(0.6667, 0.001)
	assert_bool(v["over"]).is_false()
	assert_bool(v["default"]).is_true()
	var over: Dictionary = HudLogic.ram_view(6, 9)
	assert_float(over["fraction"]).is_equal(1.0)
	assert_bool(over["over"]).is_true()
	assert_bool(over["default"]).is_false()


func test_chain_text() -> void:
	assert_str(HudLogic.chain_text(["1C", "BD", "E9"])).is_equal("1C BD E9")
	assert_str(HudLogic.chain_text([])).is_empty()


func test_program_entries_merge_the_snapshot_with_deck_info() -> void:
	var cd := [
		{"id": "a", "name": "Призрак", "left": 0.0, "st": "active", "until": 130.0},
		{"id": "b", "name": "Дрожь", "left": 20.0, "st": "cooldown", "until": 150.0},
		{"id": "c", "name": "Старый", "left": 0.0},
	]
	var info := [
		{"id": "a", "tier": 2, "cells": ["1C", "BD"], "effect": "GHOST", "loaded": true},
		{"id": "b", "tier": 1, "cells": ["55"], "effect": "JITTER", "unsupported": "нет"},
	]
	var out := HudLogic.program_entries(cd, info, 100.0)
	assert_int(out.size()).is_equal(3)
	assert_float(out[0]["active_left"]).is_equal(30.0)
	assert_str(out[0]["st"]).is_equal("active")
	assert_int(out[0]["tier"]).is_equal(2)
	assert_array(out[0]["cells"]).is_equal(["1C", "BD"])
	assert_float(out[1]["cooldown_left"]).is_equal(20.0)
	assert_bool(out[1].has("active_left")).is_false()
	assert_str(out[1]["unsupported"]).is_equal("нет")
	assert_bool(out[2].has("st")).is_false()      # демон без свойств и без st — как раньше
	assert_bool(out[2].has("tier")).is_false()


func test_a_looted_daemon_is_never_a_program() -> void:
	var out := HudLogic.program_entries([{"id": "x", "name": "Добытый", "left": 0.0}], [{"id": "x", "loaded": false, "tier": 3}], 0.0)
	assert_array(out).is_empty()


func test_deck_rows_with_properties() -> void:
	var rows := HudLogic.deck_rows({"daemons": [{"id": "a", "name": "1 Призрак", "cooldown_left": 0.0, "st": "ready", "tier": 2, "cells": ["1C", "BD"], "effect": "GHOST"},
		{"id": "b", "name": "2 Х", "cooldown_left": 0.0, "st": "unsupported", "effect": "BLACKOUT"}], "selected": "a"})
	assert_str(rows[0]["text"]).is_equal("1 Призрак  готов")
	assert_str(rows[0]["chain"]).is_equal("1C BD")
	assert_str(rows[0]["effect"]).is_equal("невидим для ICE")
	assert_int(rows[0]["tier"]).is_equal(2)
	assert_bool(rows[1]["ready"]).is_false()   # не работает в Сети — не «готов»
	assert_str(rows[1]["text"]).is_equal("2 Х  не работает в Сети")


func test_loot_rows() -> void:
	var rows := HudLogic.loot_rows([
		{"id": "1", "kind": "shard", "tier": 2, "title": "Чертежи", "enc": true},
		{"id": "2", "kind": "shard", "tier": 1, "title": "Накладная", "enc": false},
		{"id": "3", "kind": "daemon", "tier": 3, "title": "Дрожь", "enc": false},
	])
	assert_str(rows[0]["text"]).is_equal("ШАРД  Чертежи  тир 2  ЗАШИФРОВАН")
	assert_str(rows[1]["text"]).is_equal("ШАРД  Накладная  тир 1  ОТКРЫТ")
	assert_str(rows[2]["text"]).is_equal("ДЕМОН  Дрожь  тир 3  ОТКРЫТ")
	assert_array(HudLogic.loot_rows([])).is_empty()


# ---------------------------------------------------------------- заряд (К6)

func test_state_text_and_tone_for_chargeable_daemons() -> void:
	assert_str(HudLogic.state_text("ready", 0.0, 0.0, true)).is_equal("не заряжен")
	assert_str(HudLogic.state_text("ready", 0.0)).is_equal("готов")   # не защитный (EXTRACT_SHARD): как раньше
	assert_str(HudLogic.state_text("charged", 0.0)).is_equal("ГОТОВ К ЗАПУСКУ")
	assert_str(HudLogic.state_text("active", 0.0, 12.0, true)).is_equal("активен 12 с")
	assert_str(HudLogic.state_text("cooldown", 38.0, 0.0, true)).is_equal("перезарядка 38 с")
	assert_str(HudLogic.state_tone("charged", 0.0, true)).is_equal("ok")
	assert_str(HudLogic.state_tone("ready", 0.0, true)).is_equal("dim")
	assert_str(HudLogic.state_tone("ready", 0.0, false)).is_equal("ok")


func test_charge_button_only_for_a_ready_chargeable_program() -> void:
	assert_bool(HudLogic.can_charge("ready", true)).is_true()
	for st in ["charged", "cooldown", "active", "unsupported", ""]:
		assert_bool(HudLogic.can_charge(st, true)).is_false()
	assert_bool(HudLogic.can_charge("ready", false)).is_false()   # EXTRACT_SHARD заряда не имеет
	var rows := HudLogic.deck_rows({"daemons": [
		{"id": "a", "name": "1 Призрак", "cooldown_left": 0.0, "st": "ready", "chargeable": true, "cells": ["1C", "BD"]},
		{"id": "b", "name": "2 Сдвиг", "cooldown_left": 0.0, "st": "charged", "chargeable": true},
		{"id": "c", "name": "3 Извлечение", "cooldown_left": 0.0, "st": "ready", "chargeable": false}], "selected": "a"})
	assert_bool(rows[0]["can_charge"]).is_true()
	assert_str(rows[0]["text"]).is_equal("1 Призрак  не заряжен")
	assert_bool(rows[1]["can_charge"]).is_false()
	assert_bool(rows[1]["charged"]).is_true()
	assert_str(rows[1]["text"]).is_equal("2 Сдвиг  ГОТОВ К ЗАПУСКУ")
	assert_bool(rows[2]["can_charge"]).is_false()
	assert_str(rows[2]["text"]).is_equal("3 Извлечение  готов")


func test_program_entries_carry_the_chargeable_flag() -> void:
	var e := HudLogic.program_entries([{"id": "a", "name": "П", "left": 0.0, "st": "ready"}], [{"id": "a", "chargeable": true, "loaded": true}], 0.0)
	assert_bool(e[0]["chargeable"]).is_true()


func test_launch_and_charge_denial_texts_are_in_words() -> void:
	assert_str(HudLogic.launch_error_text("not_charged")).contains("ЗАРЯДИТЬ")
	assert_str(HudLogic.launch_error_text("zzz")).is_equal("Нельзя запустить")
	assert_str(HudLogic.charge_denied_text("cooldown", 42)).is_equal("Перезарядка: 42 с")
	assert_str(HudLogic.charge_denied_text("charged")).is_equal("Уже заряжен")
	assert_str(HudLogic.charge_denied_text("active")).contains("мини-игра")

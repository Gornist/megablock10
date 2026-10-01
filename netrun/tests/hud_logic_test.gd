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

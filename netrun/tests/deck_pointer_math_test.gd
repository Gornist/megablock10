extends GdUnitTestSuite
## Пересчёт «попадание луча -> пиксель SubViewport» (DeckPointerMath): центр, края, промахи, поворот и сдвиг панели (как на руке).

const SIZE := Vector2(0.4, 0.3)    # панель 40 × 30 см
const VIEW := Vector2(512, 384)


func _front() -> Transform3D:
	return Transform3D.IDENTITY   # лицом к +Z, центр в нуле


func test_ray_at_center_hits_the_middle_pixel() -> void:
	var r := DeckPointerMath.ray_to_view(Vector3(0, 0, 1), Vector3(0, 0, -1), _front(), SIZE, VIEW)
	assert_bool(r["hit"]).is_true()
	assert_vector(r["pos"]).is_equal_approx(Vector2(256, 192), Vector2(0.01, 0.01))
	assert_float(r["dist"]).is_equal_approx(1.0, 0.0001)
	assert_vector(r["point"]).is_equal_approx(Vector3.ZERO, Vector3(0.0001, 0.0001, 0.0001))


func test_panel_corners_map_to_viewport_corners_with_y_down() -> void:
	# Левый верхний угол панели (x = -w/2, y = +h/2) — пиксель (0, 0).
	var tl := DeckPointerMath.ray_to_view(Vector3(-0.2, 0.15, 1), Vector3(0, 0, -1), _front(), SIZE, VIEW)
	assert_bool(tl["hit"]).is_true()
	assert_vector(tl["pos"]).is_equal_approx(Vector2(0, 0), Vector2(0.01, 0.01))
	# Правый нижний: зажимается в последний пиксель.
	var br := DeckPointerMath.ray_to_view(Vector3(0.2, -0.15, 1), Vector3(0, 0, -1), _front(), SIZE, VIEW)
	assert_bool(br["hit"]).is_true()
	assert_vector(br["pos"]).is_equal_approx(Vector2(511, 383), Vector2(0.01, 0.01))
	# Четверть ширины вправо, четверть высоты вверх.
	var q := DeckPointerMath.ray_to_view(Vector3(0.1, 0.075, 1), Vector3(0, 0, -1), _front(), SIZE, VIEW)
	assert_vector(q["pos"]).is_equal_approx(Vector2(384, 96), Vector2(0.01, 0.01))


func test_just_outside_the_edge_misses() -> void:
	for p in [Vector3(0.2011, 0, 1), Vector3(-0.2011, 0, 1), Vector3(0, 0.1511, 1), Vector3(0, -0.1511, 1)]:
		var r := DeckPointerMath.ray_to_view(p, Vector3(0, 0, -1), _front(), SIZE, VIEW)
		assert_bool(r["hit"]).is_false()
		assert_str(r["reason"]).is_equal(DeckPointerMath.MISS_OUTSIDE)


func test_ray_pointing_away_or_from_behind_or_parallel_misses() -> void:
	var away := DeckPointerMath.ray_to_view(Vector3(0, 0, 1), Vector3(0, 0, 1), _front(), SIZE, VIEW)
	assert_str(away["reason"]).is_equal(DeckPointerMath.MISS_BEHIND)
	var back := DeckPointerMath.ray_to_view(Vector3(0, 0, -1), Vector3(0, 0, 1), _front(), SIZE, VIEW)
	assert_str(back["reason"]).is_equal(DeckPointerMath.MISS_BACK)   # изнанку панели не видно, по ней не целимся
	var par := DeckPointerMath.ray_to_view(Vector3(0, 0, 1), Vector3(1, 0, 0), _front(), SIZE, VIEW)
	assert_str(par["reason"]).is_equal(DeckPointerMath.MISS_PARALLEL)


func test_ray_beyond_reach_misses() -> void:
	var r := DeckPointerMath.ray_to_view(Vector3(0, 0, 5), Vector3(0, 0, -1), _front(), SIZE, VIEW)
	assert_str(r["reason"]).is_equal(DeckPointerMath.MISS_FAR)
	assert_bool(DeckPointerMath.ray_to_view(Vector3(0, 0, 5), Vector3(0, 0, -1), _front(), SIZE, VIEW, 6.0)["hit"]).is_true()


func test_oblique_ray_lands_where_geometry_says() -> void:
	# Из точки (0, 0, 1) под 45° вправо: в плоскости z = 0 это x = +1 — за краем; под меньшим углом — внутри.
	var dir := Vector3(0.1, 0, -1)   # x на плоскости = 0.1
	var r := DeckPointerMath.ray_to_view(Vector3(0, 0, 1), dir, _front(), SIZE, VIEW)
	assert_bool(r["hit"]).is_true()
	assert_vector(r["pos"]).is_equal_approx(Vector2((0.1 / 0.4 + 0.5) * 512, 192), Vector2(0.01, 0.01))
	assert_float(r["dist"]).is_equal_approx(1.0 * Vector3(0.1, 0, -1).length(), 0.0001)   # dir нормируется: t в метрах вдоль луча


func test_rotated_panel_yaw_30() -> void:
	# Панель повернута вокруг Y на 30°, центр сдвинут: луч прямо в её центр попадает в середину, в сторону на 10 см вдоль её X — смещает пиксель.
	var panel := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(0.5, 0.2, -0.6))
	var origin := Vector3(0.5, 0.2, 0.4)
	var normal := panel.basis * Vector3(0, 0, 1)
	var center := DeckPointerMath.ray_to_view(panel.origin + normal * 0.7, -normal, panel, SIZE, VIEW)
	assert_bool(center["hit"]).is_true()
	assert_vector(center["pos"]).is_equal_approx(Vector2(256, 192), Vector2(0.01, 0.01))
	var x_axis := panel.basis * Vector3(1, 0, 0)
	var aim_at := panel.origin + x_axis * 0.1
	var right := DeckPointerMath.ray_to_view(origin, (aim_at - origin).normalized(), panel, SIZE, VIEW)
	assert_bool(right["hit"]).is_true()
	assert_vector(right["pos"]).is_equal_approx(Vector2((0.1 / 0.4 + 0.5) * 512, 192), Vector2(0.01, 0.01))
	assert_vector(right["point"]).is_equal_approx(aim_at, Vector3(0.0005, 0.0005, 0.0005))


func test_deck_tilted_like_on_the_wrist() -> void:
	# Как на левой руке: панель наклонена на -60° вокруг X и смотрит вверх-назад, на глаза; луч из точки «над рукой».
	var panel := Transform3D(Basis.from_euler(Vector3(-PI / 3, 0, 0)), Vector3(0, 1.0, -0.4))
	var normal := panel.basis * Vector3(0, 0, 1)
	assert_float(normal.y).is_greater(0.8)   # смотрит вверх
	var eye := panel.origin + normal * 0.45
	var hit := DeckPointerMath.ray_to_view(eye, -normal, panel, SIZE, VIEW)
	assert_bool(hit["hit"]).is_true()
	assert_vector(hit["pos"]).is_equal_approx(Vector2(256, 192), Vector2(0.01, 0.01))
	# Панель вверх (+Y её системы) в мире — «вверх по наклону»: пиксель выше центра.
	var up_point := panel.origin + (panel.basis * Vector3(0, 1, 0)) * 0.05
	var h2 := DeckPointerMath.ray_to_view(eye, (up_point - eye).normalized(), panel, SIZE, VIEW)
	assert_float(h2["pos"].y).is_less(192.0)


func test_scaled_deck_like_on_the_wrist() -> void:
	# Дека на запястье уменьшена (WorldUI.WRIST_DECK_SCALE = 0,75): в трансформации панели есть масштаб, size_m — размер до масштаба.
	var s := 0.75
	var panel := Transform3D(Basis.from_euler(Vector3(-PI / 3, 0, 0)).scaled(Vector3.ONE * s), Vector3(0, 1.0, -0.4))
	var normal: Vector3 = panel.basis.orthonormalized() * Vector3(0, 0, 1)
	var x_axis: Vector3 = panel.basis.orthonormalized() * Vector3(1, 0, 0)
	var eye := panel.origin + normal * 0.45
	var mid := DeckPointerMath.ray_to_view(eye, -normal, panel, SIZE, VIEW)
	assert_bool(mid["hit"]).is_true()
	assert_vector(mid["pos"]).is_equal_approx(Vector2(256, 192), Vector2(0.01, 0.01))
	assert_float(mid["dist"]).is_equal_approx(0.45, 0.0001)   # расстояние — в метрах мира, масштаб его не искажает
	# 7,5 см в мире от центра вправо — это 10 см на панели до масштаба: четверть ширины.
	var quarter := DeckPointerMath.ray_to_view(eye, (panel.origin + x_axis * 0.075 - eye).normalized(), panel, SIZE, VIEW)
	assert_vector(quarter["pos"]).is_equal_approx(Vector2(384, 192), Vector2(0.05, 0.05))
	# Край панели в мире — на 0,75 · 20 см = 15 см от центра: 16 см уже мимо, 14 см ещё внутри.
	assert_bool(DeckPointerMath.ray_to_view(eye, (panel.origin + x_axis * 0.16 - eye).normalized(), panel, SIZE, VIEW)["hit"]).is_false()
	assert_bool(DeckPointerMath.ray_to_view(eye, (panel.origin + x_axis * 0.14 - eye).normalized(), panel, SIZE, VIEW)["hit"]).is_true()
	# Обратное преобразование даёт точку в мире, уже с масштабом.
	var w := DeckPointerMath.view_to_world(Vector2(384, 192), panel, SIZE, VIEW)
	assert_vector(w).is_equal_approx(panel.origin + x_axis * 0.075, Vector3(0.0005, 0.0005, 0.0005))


func test_view_to_world_is_inverse_of_ray_to_view() -> void:
	var panel := Transform3D(Basis(Vector3(0, 1, 0), 0.4) * Basis(Vector3(1, 0, 0), -0.7), Vector3(0.3, 1.1, -0.5))
	for px in [Vector2(10, 10), Vector2(256, 192), Vector2(500, 370), Vector2(100, 300)]:
		var w := DeckPointerMath.view_to_world(px, panel, SIZE, VIEW)
		var n := panel.basis * Vector3(0, 0, 1)
		var back := DeckPointerMath.ray_to_view(w + n * 0.5, -n, panel, SIZE, VIEW)
		assert_bool(back["hit"]).is_true()
		assert_vector(back["pos"]).is_equal_approx(px, Vector2(0.05, 0.05))


func test_scroll_step_deadzone_direction_and_speed() -> void:
	assert_float(DeckPointerMath.scroll_step(0.2, 0.1)).is_equal(0.0)      # в мёртвой зоне
	assert_float(DeckPointerMath.scroll_step(-0.25, 0.1)).is_equal(0.0)    # ровно на границе
	assert_float(DeckPointerMath.scroll_step(1.0, 1.0, 500.0)).is_equal_approx(-500.0, 0.01)   # вверх — к началу списка
	assert_float(DeckPointerMath.scroll_step(-1.0, 0.5, 500.0)).is_equal_approx(250.0, 0.01)
	var half := absf(DeckPointerMath.scroll_step(0.625, 1.0, 500.0))
	assert_float(half).is_equal_approx(250.0, 0.01)   # посреди хода — половинная скорость

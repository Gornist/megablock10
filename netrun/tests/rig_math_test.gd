extends GdUnitTestSuite

func test_deadzone_zeroes_small_input() -> void:
	assert_vector(RigMath.apply_deadzone(Vector2(0.1, 0.1))).is_equal(Vector2.ZERO)


func test_deadzone_full_deflection_is_one() -> void:
	assert_float(RigMath.apply_deadzone(Vector2(1, 0)).length()).is_equal_approx(1.0, 0.001)


func test_snap_turn_right_is_negative_step_once() -> void:
	var r := RigMath.snap_turn(1.0, true)
	assert_float(r["delta_deg"]).is_equal(-RigMath.SNAP_STEP_DEG)
	assert_bool(r["armed"]).is_false()
	var r2 := RigMath.snap_turn(1.0, r["armed"])
	assert_float(r2["delta_deg"]).is_equal(0.0)


func test_snap_turn_rearms_after_release() -> void:
	var r := RigMath.snap_turn(0.0, false)
	assert_bool(r["armed"]).is_true()
	assert_float(RigMath.snap_turn(-1.0, r["armed"])["delta_deg"]).is_equal(RigMath.SNAP_STEP_DEG)


func test_snap_turn_below_threshold_does_nothing() -> void:
	assert_float(RigMath.snap_turn(0.5, true)["delta_deg"]).is_equal(0.0)


func test_smooth_turn_scales_with_delta_and_ignores_deadzone() -> void:
	assert_float(RigMath.smooth_turn(0.1, 0.1)).is_equal(0.0)
	assert_float(RigMath.smooth_turn(1.0, 0.5, 90.0)).is_equal_approx(-45.0, 0.001)


func test_move_forward_follows_yaw() -> void:
	var v := RigMath.move_velocity(Vector2(0, 1), 0.0, 2.0)
	assert_vector(v).is_equal_approx(Vector3(0, 0, -2), Vector3.ONE * 0.001)
	var v2 := RigMath.move_velocity(Vector2(0, 1), PI / 2.0, 2.0)
	assert_vector(v2).is_equal_approx(Vector3(-2, 0, 0), Vector3.ONE * 0.001)


func test_move_speed_is_capped() -> void:
	assert_float(RigMath.move_velocity(Vector2(0, 1), 0.0, 99.0).length()).is_equal_approx(RigMath.MAX_MOVE_SPEED, 0.001)


func test_recenter_moves_origin_horizontally_only() -> void:
	var p := RigMath.recenter_origin(Vector3(1, 0, 1), Vector3(3, 1.2, 0), Vector3(1, 0, 1))
	assert_vector(p).is_equal_approx(Vector3(-1, 0, 2), Vector3.ONE * 0.001)


# ---------------------------------------------------------------- плавный поворот

func test_default_turn_is_none_the_stick_does_not_rotate_the_world() -> void:
	assert_str(RigMath.TURN_MODE_DEFAULT).is_equal(RigMath.TURN_MODE_NONE)
	assert_float(RigMath.TURN_SPEED_DEG_S).is_equal(60.0)
	assert_float(RigMath.TURN_SPEED_DEG_S).is_less(RigMath.TURN_SPEED_MAX_DEG_S)
	assert_float(RigMath.TURN_SPEED_MAX_DEG_S).is_equal(120.0)


func test_turn_target_rate_follows_stick_with_deadzone() -> void:
	assert_float(RigMath.turn_target_rate(1.0, 60.0)).is_equal_approx(-60.0, 0.001)   # вправо — минус
	assert_float(RigMath.turn_target_rate(-1.0, 60.0)).is_equal_approx(60.0, 0.001)
	assert_float(RigMath.turn_target_rate(0.1, 60.0)).is_equal(0.0)                   # мёртвая зона
	assert_float(RigMath.turn_target_rate(0.6, 60.0)).is_equal_approx(-30.0, 0.001)   # (0,6 - 0,2) / 0,8 = 0,5


func test_turn_target_rate_never_exceeds_hard_ceiling() -> void:
	assert_float(RigMath.turn_target_rate(1.0, 999.0)).is_equal_approx(-RigMath.TURN_SPEED_MAX_DEG_S, 0.001)


func test_turn_rate_ramps_up_over_ramp_time() -> void:
	var r := 0.0
	r = RigMath.turn_rate_step(r, -60.0, 0.1, 60.0, 0.25, 0.2)
	assert_float(r).is_equal_approx(-24.0, 0.001)         # 60 / 0,25 = 240 °/с² -> за 0,1 с -24
	r = RigMath.turn_rate_step(r, -60.0, 0.15, 60.0, 0.25, 0.2)
	assert_float(r).is_equal_approx(-60.0, 0.001)         # разгон кончился ровно за 0,25 с
	r = RigMath.turn_rate_step(r, -60.0, 1.0, 60.0, 0.25, 0.2)
	assert_float(r).is_equal_approx(-60.0, 0.001)         # выше цели не уходит


func test_turn_rate_decays_to_zero_over_ramp_down() -> void:
	var r := RigMath.turn_rate_step(-60.0, 0.0, 0.1, 60.0, 0.25, 0.2)
	assert_float(r).is_equal_approx(-30.0, 0.001)         # 60 / 0,2 = 300 °/с²
	r = RigMath.turn_rate_step(r, 0.0, 0.1, 60.0, 0.25, 0.2)
	assert_float(r).is_equal_approx(0.0, 0.001)


func test_turn_rate_reversal_passes_through_zero_without_overshoot() -> void:
	var r := -60.0
	var seen_zero := false
	for i in 120:
		r = RigMath.turn_rate_step(r, 60.0, 1.0 / 72.0, 60.0, 0.25, 0.2)
		assert_float(absf(r)).is_less_equal(60.0 + 0.001)
		if absf(r) < 2.0:
			seen_zero = true
	assert_bool(seen_zero).is_true()
	assert_float(r).is_equal_approx(60.0, 0.001)


func test_turn_rate_has_no_jump_per_frame() -> void:
	# Ни один кадр при 72 Гц не меняет скорость больше, чем speed / ramp * dt (и поворот за кадр — не больше speed * dt).
	var dt := 1.0 / 72.0
	var r := 0.0
	var worst := 0.0
	for i in 200:
		var target := -60.0 if i < 100 else 0.0
		var next := RigMath.turn_rate_step(r, target, dt, 60.0, 0.25, 0.2)
		worst = maxf(worst, absf(next - r))
		r = next
	assert_float(worst).is_less_equal(60.0 / 0.2 * dt + 0.0001)


func test_turn_rate_step_clamps_speed_to_ceiling() -> void:
	var r := RigMath.turn_rate_step(0.0, -999.0, 10.0, 999.0, 0.25, 0.2)
	assert_float(r).is_equal_approx(-RigMath.TURN_SPEED_MAX_DEG_S, 0.001)


func test_vignette_target_is_proportional_to_speed() -> void:
	var m := RigMath.TURN_VIGNETTE_MAX
	assert_float(RigMath.vignette_target(0.0)).is_equal(0.0)
	assert_float(RigMath.vignette_target(30.0)).is_equal_approx(m * 0.5, 0.0001)
	assert_float(RigMath.vignette_target(-30.0)).is_equal_approx(m * 0.5, 0.0001)
	assert_float(RigMath.vignette_target(60.0)).is_equal_approx(m, 0.0001)
	assert_float(RigMath.vignette_target(120.0)).is_equal_approx(m, 0.0001)   # выше полной скорости не темнее
	assert_float(RigMath.vignette_target(60.0, 0.3)).is_equal_approx(0.3, 0.0001)


func test_vignette_default_closes_about_45_percent() -> void:
	assert_float(RigMath.TURN_VIGNETTE_MAX).is_equal_approx(0.45, 0.0001)
	assert_float(RigMath.TURN_VIGNETTE_LIMIT).is_greater_equal(RigMath.TURN_VIGNETTE_MAX)


func test_vignette_step_eases_in_and_out() -> void:
	var v := RigMath.vignette_step(0.0, 0.45, 0.075, 0.45)
	assert_float(v).is_equal_approx(0.225, 0.001)    # вход 0,15 с: полпути за 0,075 с
	v = RigMath.vignette_step(v, 0.45, 0.075, 0.45)
	assert_float(v).is_equal_approx(0.45, 0.001)
	v = RigMath.vignette_step(v, 0.0, 0.1, 0.45)
	assert_float(v).is_equal_approx(0.225, 0.001)    # выход 0,2 с: полпути за 0,1 с
	v = RigMath.vignette_step(v, 0.0, 0.5, 0.45)
	assert_float(v).is_equal(0.0)


# ---------------------------------------------------------------- телепорт: прицел

const FROM := Vector3(0, 0, -6)   # центр комнаты


func test_teleport_constants() -> void:
	assert_float(RigMath.TELEPORT_RANGE).is_equal(4.0)
	assert_float(RigMath.TELEPORT_COOLDOWN).is_equal(1.2)
	assert_float(RigMath.TELEPORT_BLINK_SEC).is_equal(0.1)
	assert_float(RigMath.TELEPORT_TRACE).is_equal(0.0)
	assert_float(RigMath.TELEPORT_RANGE_LIMIT).is_greater_equal(RigMath.TELEPORT_RANGE)
	assert_float(RigMath.TELEPORT_COOLDOWN_LIMIT).is_less_equal(RigMath.TELEPORT_COOLDOWN)


func test_aim_down_hits_floor_at_the_pointed_spot() -> void:
	var a := RigMath.teleport_aim(Vector3(0, 1.0, -6), Vector3(0, -1, -1).normalized(), FROM)
	assert_bool(a["valid"]).is_true()
	assert_vector(a["p"]).is_equal_approx(Vector3(0, 0, -7), Vector3.ONE * 0.001)
	assert_bool(a["clamped_range"]).is_false()
	assert_bool(a["clamped_room"]).is_false()


func test_aim_follows_yaw_of_the_hand() -> void:
	var dir := Vector3(0, -1, -1).normalized().rotated(Vector3.UP, PI / 2.0)   # налево (-Z повернули на +90°)
	var a := RigMath.teleport_aim(Vector3(0, 1.0, -6), dir, FROM)
	assert_vector(a["p"]).is_equal_approx(Vector3(-1, 0, -6), Vector3.ONE * 0.001)


func test_aim_beyond_range_is_cut_along_the_line() -> void:
	var a := RigMath.teleport_aim(Vector3(0, 1.0, -6), Vector3(0, -0.1, -1).normalized(), FROM)
	assert_bool(a["clamped_range"]).is_true()
	assert_vector(a["p"]).is_equal_approx(Vector3(0, 0, -10), Vector3.ONE * 0.001)   # 4 м вперёд от FROM
	assert_float(NodeLayout.flat_distance(a["p"], FROM)).is_equal_approx(RigMath.TELEPORT_RANGE, 0.001)


func test_aim_horizontal_or_up_goes_to_max_range() -> void:
	var level := RigMath.teleport_aim(Vector3(0, 1.0, -6), Vector3(0, 0, -1), FROM)
	assert_vector(level["p"]).is_equal_approx(Vector3(0, 0, -10), Vector3.ONE * 0.001)
	var up := RigMath.teleport_aim(Vector3(0, 1.0, -6), Vector3(1, 0.5, 0).normalized(), FROM)
	assert_bool(up["valid"]).is_true()
	assert_vector(up["p"]).is_equal_approx(Vector3(4, 0, -6), Vector3.ONE * 0.001)


func test_aim_straight_up_is_invalid() -> void:
	assert_bool(RigMath.teleport_aim(Vector3(0, 1.0, -6), Vector3.UP, FROM)["valid"]).is_false()


func test_aim_with_hand_near_floor_does_not_divide_by_nothing() -> void:
	# Рука ниже порога над полом (например, пол в очках на уровне головы): луч в пол не считаем, идём по горизонтали.
	var a := RigMath.teleport_aim(Vector3(0, 0.05, -6), Vector3(0, -1, -1).normalized(), FROM)
	assert_bool(a["valid"]).is_true()
	assert_vector(a["p"]).is_equal_approx(Vector3(0, 0, -10), Vector3.ONE * 0.001)


func test_aim_is_cut_to_the_room() -> void:
	var a := RigMath.teleport_aim(Vector3(7, 1.0, -6), Vector3(1, 0, 0), Vector3(7, 0, -6))
	assert_bool(a["clamped_room"]).is_true()
	assert_vector(a["p"]).is_equal_approx(Vector3(8, 0, -6), Vector3.ONE * 0.001)
	assert_bool(NodeLayout.in_room(a["p"])).is_true()


func test_aim_result_never_farther_than_range_even_after_room_cut() -> void:
	for yaw in 12:
		var dir := Vector3(0, -0.05, -1).rotated(Vector3.UP, yaw * TAU / 12.0)
		var a := RigMath.teleport_aim(Vector3(7.5, 1.0, 1.5), dir, Vector3(7.5, 0, 1.5))
		assert_float(NodeLayout.flat_distance(a["p"], Vector3(7.5, 0, 1.5))).is_less_equal(RigMath.TELEPORT_RANGE + 0.0001)
		assert_bool(NodeLayout.in_room(a["p"])).is_true()


func test_arc_points_start_at_hand_end_at_target_and_rise() -> void:
	var pts := RigMath.arc_points(Vector3(0, 1.0, 0), Vector3(0, 0, -3), 12)
	assert_int(pts.size()).is_equal(12)
	assert_vector(pts[0]).is_equal_approx(Vector3(0, 1.0, 0), Vector3.ONE * 0.001)
	assert_vector(pts[11]).is_equal_approx(Vector3(0, 0, -3), Vector3.ONE * 0.001)
	var top := 0.0
	for p in pts:
		top = maxf(top, p.y)
	assert_float(top).is_greater(1.0)   # дуга выше начала


# ---------------------------------------------------------------- телепорт: вердикт (общее для клиента и сервера)

func test_verdict_ok_inside_range_room_and_cooldown() -> void:
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(3, 0, 0), 5.0, false)).is_equal("")
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(3, 0, 0), INF, false)).is_equal("")   # первый телепорт


func test_verdict_reasons() -> void:
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(1, 0, 0), 5.0, true)).is_equal(WorldMsg.REASON_TUNNEL)
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(1, 0, 0), 0.1, false)).is_equal(WorldMsg.REASON_COOLDOWN)
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(7, 0, 0), 5.0, false, 4.5)).is_equal(WorldMsg.REASON_RANGE)
	assert_str(RigMath.teleport_verdict(Vector3(7, 0, -6), Vector3(9, 0, -6), 5.0, false)).is_equal(WorldMsg.REASON_ROOM)


func test_verdict_range_and_cooldown_are_inclusive_and_use_given_slack() -> void:
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(4.5, 0, 0), 5.0, false, 4.5, 1.0)).is_equal("")
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(1, 0, 0), 1.0, false, 4.5, 1.0)).is_equal("")
	assert_str(RigMath.teleport_verdict(FROM, FROM + Vector3(1, 0, 0), 0.99, false, 4.5, 1.0)).is_equal(WorldMsg.REASON_COOLDOWN)


func test_cooldown_left_counts_down_and_stops_at_zero() -> void:
	assert_float(RigMath.cooldown_left(0.0, 1.2)).is_equal_approx(1.2, 0.0001)
	assert_float(RigMath.cooldown_left(0.3, 1.2)).is_equal_approx(0.9, 0.0001)
	assert_float(RigMath.cooldown_left(5.0, 1.2)).is_equal(0.0)
	assert_float(RigMath.cooldown_left(INF, 1.2)).is_equal(0.0)


# ---------------------------------------------------------------- телепорт: стик

func _aim(state: Dictionary, stick: Vector2, dt: float = 0.014, clicked: bool = false) -> Dictionary:
	return RigMath.aim_step(state, stick, clicked, dt)


func test_aim_starts_when_stick_is_pushed_in_any_direction() -> void:
	var s := _aim(RigMath.aim_new(), Vector2(0, 0.5))
	assert_bool(s["aiming"]).is_false()
	s = _aim(s, Vector2(0, 0.9))
	assert_bool(s["aiming"]).is_true()
	assert_str(s["event"]).is_equal(RigMath.AIM_START)
	s = _aim(s, Vector2(0, 0.9))
	assert_str(s["event"]).is_equal("")      # событие — один раз
	for dir in [Vector2(-0.9, 0), Vector2(0.9, 0), Vector2(0, -0.9), Vector2(0.65, 0.65), Vector2(-0.5, -0.5)]:
		assert_bool(_aim(RigMath.aim_new(), dir)["aiming"]).is_true()


func test_a_weak_push_does_not_start_the_aim() -> void:
	assert_bool(_aim(RigMath.aim_new(), Vector2(0.6, 0.0))["aiming"]).is_false()
	assert_bool(_aim(RigMath.aim_new(), Vector2(-0.4, -0.4))["aiming"]).is_false()


func test_aim_fires_when_stick_is_released_for_a_moment() -> void:
	for dir in [Vector2(0, 1), Vector2(-1, 0), Vector2(0.7, -0.7)]:
		var s := _aim(RigMath.aim_new(), dir)
		s = _aim(s, dir * 0.1, 0.02)
		assert_bool(s["aiming"]).is_true()        # ещё не отпущен по-настоящему: пружина стика качнулась
		s = _aim(s, Vector2.ZERO, 0.04)
		assert_bool(s["aiming"]).is_false()
		assert_str(s["event"]).is_equal(RigMath.AIM_FIRE)


func test_aim_stick_dip_that_recovers_does_not_fire() -> void:
	var s := _aim(RigMath.aim_new(), Vector2(0, 1))
	s = _aim(s, Vector2(0, 0.1), 0.02)
	s = _aim(s, Vector2(0, 0.8), 0.02)         # вернул
	s = _aim(s, Vector2(0, 0.1), 0.02)
	assert_bool(s["aiming"]).is_true()
	assert_str(s["event"]).is_equal("")


func test_pulling_the_stick_back_is_a_turn_around_not_a_cancel() -> void:
	var s := _aim(RigMath.aim_new(), Vector2(0, 1))
	s = _aim(s, Vector2(0, -1), 0.014)
	assert_bool(s["aiming"]).is_true()
	assert_str(s["event"]).is_equal("")


func test_aim_is_cancelled_only_by_clicking_the_stick() -> void:
	var s := _aim(RigMath.aim_new(), Vector2(-1, 0))
	s = _aim(s, Vector2(-1, 0), 0.014, true)
	assert_str(s["event"]).is_equal(RigMath.AIM_CANCEL)
	assert_bool(s["aiming"]).is_false()


func test_aim_click_without_aiming_does_nothing() -> void:
	var s := _aim(RigMath.aim_new(), Vector2.ZERO, 0.014, true)
	assert_str(s["event"]).is_equal("")


# ---------------------------------------------------------------- моргание

func test_blink_timeline_dark_move_clear() -> void:
	var b := RigMath.blink_start()
	assert_int(b["phase"]).is_equal(1)
	b = RigMath.blink_step(b, 0.05, 0.1)
	assert_float(b["alpha"]).is_equal_approx(0.5, 0.001)
	assert_bool(b["moved"]).is_false()
	b = RigMath.blink_step(b, 0.05, 0.1)
	assert_float(b["alpha"]).is_equal_approx(1.0, 0.001)
	assert_bool(b["moved"]).is_true()        # перенос — в самой тёмной точке, один раз
	b = RigMath.blink_step(b, 0.05, 0.1)
	assert_bool(b["moved"]).is_false()
	assert_float(b["alpha"]).is_equal_approx(0.5, 0.001)
	b = RigMath.blink_step(b, 0.05, 0.1)
	assert_float(b["alpha"]).is_equal(0.0)
	assert_int(b["phase"]).is_equal(0)


func test_blink_idle_stays_clear() -> void:
	var b := RigMath.blink_step(RigMath.blink_new(), 0.5, 0.1)
	assert_float(b["alpha"]).is_equal(0.0)
	assert_bool(b["moved"]).is_false()


func test_blink_survives_a_long_frame() -> void:
	var b := RigMath.blink_step(RigMath.blink_start(), 1.0, 0.1)   # кадр длиннее всего моргания
	assert_bool(b["moved"]).is_true()
	b = RigMath.blink_step(b, 1.0, 0.1)
	assert_int(b["phase"]).is_equal(0)


# ---------------------------------------------------------------- поворот при телепорте

func test_facing_follows_the_stick_angle() -> void:
	assert_float(RigMath.facing_deg(Vector2(0, 1))).is_equal(0.0)        # вверх — не поворачивать
	assert_float(RigMath.facing_deg(Vector2(1, 0))).is_equal_approx(90.0, 0.001)     # вправо — ровно 90° вправо
	assert_float(RigMath.facing_deg(Vector2(-1, 0))).is_equal_approx(-90.0, 0.001)   # влево
	assert_float(absf(RigMath.facing_deg(Vector2(0, -1)))).is_equal_approx(180.0, 0.001)   # вниз — развернуться
	assert_float(RigMath.facing_deg(Vector2(0.75, -0.75))).is_equal_approx(135.0, 0.001)
	assert_float(RigMath.facing_deg(Vector2(-0.75, -0.75))).is_equal_approx(-135.0, 0.001)


func test_facing_is_smooth_not_stepped() -> void:
	var prev := 0.0
	for deg in range(0, 181):
		var a := deg_to_rad(float(deg))
		var f := RigMath.facing_deg(Vector2(sin(a), cos(a)))
		assert_float(f).is_greater_equal(prev - 0.0001)               # не убывает
		assert_float(f - prev).is_less_equal(1.2)                      # нет скачков: шаг в 1° стика — не больше ~1,1°
		prev = f
	assert_float(prev).is_equal_approx(180.0, 0.001)
	var distinct := {}
	for deg in range(10, 90):
		var a := deg_to_rad(float(deg))
		distinct[snappedf(RigMath.facing_deg(Vector2(sin(a), cos(a))), 0.01)] = true
	assert_int(distinct.size()).is_greater(70)                         # на одном угле стика — свой угол поворота, не ступеньки


func test_facing_dead_cone_and_weak_stick_do_not_turn() -> void:
	assert_float(RigMath.facing_deg(Vector2.ZERO)).is_equal(0.0)
	assert_float(RigMath.facing_deg(Vector2(0.5, 0.0))).is_equal(0.0)           # слабее FACING_STICK_MIN
	assert_float(RigMath.facing_deg(Vector2(0.1, 0.99))).is_equal(0.0)          # ~5,8° от «вверх»: в мёртвом секторе
	assert_float(RigMath.facing_deg(Vector2(-0.1, 0.99))).is_equal(0.0)

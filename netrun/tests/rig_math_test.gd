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

extends GdUnitTestSuite
## Управление в клиенте: телепорт (стик вперёд — прицел, отпустил — переместился, моргание), плавный поворот с виньеткой,
## ходьба выключена. Ввод подаётся прямо в XRRig.drive (в тестах нет ни очков, ни клавиатуры); кадр — 1/72 с.

const DT := 1.0 / 72.0
var _attempts: Array = []


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	_attempts = []
	scene.rig.teleport_attempted.connect(func(from: Vector3, to: Vector3, ok: bool, reason: String):
		_attempts.append({"from": from, "to": to, "ok": ok, "reason": reason}))
	return scene


func _frames(rig: XRRig, n: int, turn_x: float = 0.0, stick: Vector2 = Vector2.ZERO, clicked: bool = false) -> void:
	for i in n:
		rig.drive(turn_x, stick, clicked and i == 0, DT)


## Прицелиться вперёд и отпустить стик; ждёт, пока моргание кончится.
func _teleport_forward(rig: XRRig) -> void:
	_frames(rig, 3, 0.0, Vector2(0, 1))
	_frames(rig, 8)      # отпущен: задержка отпускания + моргание (0,1 + 0,1 с = 15 кадров)
	_frames(rig, 12)


func test_defaults_are_smooth_turn_and_no_walking() -> void:
	var rig: XRRig = _scene().rig
	assert_str(rig.turn_mode).is_equal(RigMath.TURN_MODE_SMOOTH)
	assert_float(rig.turn_speed_deg_s).is_equal(RigMath.TURN_SPEED_DEG_S)
	assert_bool(rig.walk_enabled).is_false()
	assert_float(rig.teleport_range).is_equal(RigMath.TELEPORT_RANGE)
	assert_float(rig.teleport_cooldown).is_equal(RigMath.TELEPORT_COOLDOWN)


func test_stick_forward_shows_aim_without_moving() -> void:
	var rig: XRRig = _scene().rig
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	assert_bool(rig.is_aiming()).is_true()
	assert_vector(rig.aim_target()).is_equal_approx(start + Vector3(0, 0, -RigMath.TELEPORT_RANGE), Vector3.ONE * 0.01)
	assert_bool(rig.aim_visual.visible).is_true()
	assert_bool(rig.aim_visual.is_ok()).is_true()        # зелёное
	assert_vector(rig.global_position).is_equal(start)   # камера не двигалась


func test_aim_follows_where_the_view_points() -> void:
	var rig: XRRig = _scene().rig
	rig.camera.rotation = Vector3(-deg_to_rad(40.0), 0.0, 0.0)   # плоская сборка: прицел по взгляду, вниз на 40°
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	var reach := rig.camera.global_position.y / tan(deg_to_rad(40.0))
	assert_vector(rig.aim_target()).is_equal_approx(start + Vector3(0, 0, -reach), Vector3.ONE * 0.02)


func test_release_teleports_once_after_the_blink_without_sliding() -> void:
	var rig: XRRig = _scene().rig
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	var target := rig.aim_target()
	var positions := {}
	var darkest := 0.0
	for i in 40:
		rig.drive(0.0, Vector2.ZERO, false, DT)
		positions[rig.global_position] = true
		darkest = maxf(darkest, rig.blink_alpha())
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_true()
	assert_vector(_attempts[0]["from"]).is_equal_approx(start, Vector3.ONE * 0.001)
	assert_vector(_attempts[0]["to"]).is_equal_approx(target, Vector3.ONE * 0.001)
	assert_vector(rig.global_position).is_equal_approx(target, Vector3.ONE * 0.001)
	assert_int(positions.size()).is_equal(2)          # было одно место, стало другое — без промежуточных точек
	assert_float(darkest).is_equal_approx(1.0, 0.001) # перенос произошёл под полным затемнением
	assert_float(rig.blink_alpha()).is_equal(0.0)     # и экран открылся
	assert_bool(rig.aim_visual.visible).is_false()
	assert_bool(rig.is_aiming()).is_false()


func test_rig_moves_only_when_the_screen_is_dark() -> void:
	var rig: XRRig = _scene().rig
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	var moved_at_alpha := -1.0
	for i in 40:
		rig.drive(0.0, Vector2.ZERO, false, DT)
		if moved_at_alpha < 0.0 and rig.global_position.distance_to(start) > 0.01:
			moved_at_alpha = rig.blink_alpha()
	assert_float(moved_at_alpha).is_greater_equal(0.99)


func test_cooldown_blocks_the_next_teleport_and_shows_red() -> void:
	var rig: XRRig = _scene().rig
	_teleport_forward(rig)
	var after_first := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	assert_bool(rig.is_aiming()).is_true()
	assert_bool(rig.aim_visual.is_ok()).is_false()       # красное: перезарядка
	assert_float(rig.teleport_cooldown_left()).is_greater(0.0)
	_frames(rig, 8)
	assert_int(_attempts.size()).is_equal(2)
	assert_bool(_attempts[1]["ok"]).is_false()
	assert_str(_attempts[1]["reason"]).is_equal(WorldMsg.REASON_COOLDOWN)
	_frames(rig, 20)
	assert_vector(rig.global_position).is_equal(after_first)
	# когда перезарядка прошла — снова можно
	_frames(rig, int(RigMath.TELEPORT_COOLDOWN / DT) + 2)
	assert_float(rig.teleport_cooldown_left()).is_equal(0.0)
	_frames(rig, 3, 0.0, Vector2(0, 1))
	assert_bool(rig.aim_visual.is_ok()).is_true()


func test_pulling_the_stick_back_cancels() -> void:
	var rig: XRRig = _scene().rig
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	_frames(rig, 2, 0.0, Vector2(0, -1))
	_frames(rig, 30)
	assert_bool(rig.is_aiming()).is_false()
	assert_bool(rig.aim_visual.visible).is_false()
	assert_array(_attempts).is_empty()
	assert_vector(rig.global_position).is_equal(start)


func test_clicking_the_stick_cancels() -> void:
	var rig: XRRig = _scene().rig
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	_frames(rig, 1, 0.0, Vector2(0, 1), true)
	_frames(rig, 30)
	assert_array(_attempts).is_empty()
	assert_vector(rig.global_position).is_equal(start)


func test_no_aim_while_tunnel_locks_movement() -> void:
	var scene := _scene()
	scene.begin_tunnel("Архив", 2.0)
	_frames(scene.rig, 3, 0.0, Vector2(0, 1))
	assert_bool(scene.rig.is_aiming()).is_false()
	_frames(scene.rig, 30)
	assert_array(_attempts).is_empty()


func test_tunnel_starting_during_aim_cancels_it() -> void:
	var scene := _scene()
	_frames(scene.rig, 3, 0.0, Vector2(0, 1))
	scene.begin_tunnel("Архив", 2.0)
	_frames(scene.rig, 3, 0.0, Vector2(0, 1))
	assert_bool(scene.rig.is_aiming()).is_false()
	_frames(scene.rig, 30)
	assert_array(_attempts).is_empty()


func test_server_denial_sends_the_rig_back() -> void:
	var rig: XRRig = _scene().rig
	var home := rig.global_position
	_teleport_forward(rig)
	assert_float(NodeLayout.flat_distance(rig.global_position, home)).is_greater(3.0)
	rig.apply_teleport_denial(WorldMsg.REASON_RANGE, home, 0.0)
	_frames(rig, 30)
	assert_vector(rig.global_position).is_equal_approx(home, Vector3.ONE * 0.001)
	assert_float(rig.blink_alpha()).is_equal(0.0)


func test_denial_before_the_move_cancels_it() -> void:
	# Сервер отказал раньше, чем кончилось затемнение: риг так и не уходит с места, перезарядка — как сказал сервер.
	var rig: XRRig = _scene().rig
	var home := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	_frames(rig, 6)     # отпущен, идёт затемнение
	rig.apply_teleport_denial(WorldMsg.REASON_COOLDOWN, home, 0.7)
	_frames(rig, 40)
	assert_vector(rig.global_position).is_equal_approx(home, Vector3.ONE * 0.001)
	assert_float(rig.teleport_cooldown_left()).is_greater(0.0)


func test_walking_is_off_by_default_and_on_with_the_flag() -> void:
	var rig: XRRig = _scene().rig
	var start := rig.global_position
	for i in 36:
		rig.drive(0.0, Vector2.ZERO, false, DT, Vector2(0, 1))
	assert_vector(rig.global_position).is_equal(start)
	rig.walk_enabled = true
	for i in 36:
		rig.drive(0.0, Vector2.ZERO, false, DT, Vector2(0, 1))
	assert_float(start.distance_to(rig.global_position)).is_greater(0.5)


func test_walking_stays_locked_in_tunnel_even_with_the_flag() -> void:
	var scene := _scene()
	scene.rig.walk_enabled = true
	scene.begin_tunnel("Архив", 2.0)
	var start: Vector3 = scene.rig.global_position
	for i in 36:
		scene.rig.drive(0.0, Vector2.ZERO, false, DT, Vector2(0, 1))
	assert_vector(scene.rig.global_position).is_equal(start)


# ---------------------------------------------------------------- поворот

func _yaw(rig: XRRig) -> float:
	return rig.camera.global_rotation.y


func test_stick_turns_smoothly_without_a_jump_per_frame() -> void:
	var rig: XRRig = _scene().rig
	var yaw := _yaw(rig)
	var worst := 0.0
	var head := rig.camera.global_position
	for i in 72:
		rig.drive(1.0, Vector2.ZERO, false, DT)
		var now := _yaw(rig)
		worst = maxf(worst, absf(angle_difference(yaw, now)))
		yaw = now
		assert_vector(rig.camera.global_position).is_equal_approx(head, Vector3.ONE * 0.0001)   # вокруг головы: игрок на месте
	assert_float(rad_to_deg(worst)).is_less_equal(RigMath.TURN_SPEED_DEG_S * DT + 0.001)   # не больше скорости за кадр
	assert_float(rad_to_deg(worst)).is_greater(0.5)


func test_turn_right_is_clockwise_and_reaches_full_speed_after_ramp() -> void:
	var rig: XRRig = _scene().rig
	var yaw0 := _yaw(rig)
	for i in 72:   # секунда на полном стике: 0,25 с разгона (7,5°) + 0,75 с по 60°/с
		rig.drive(1.0, Vector2.ZERO, false, DT)
	var turned := rad_to_deg(angle_difference(yaw0, _yaw(rig)))
	assert_float(turned).is_less(0.0)                       # вправо — по часовой, yaw уменьшается
	assert_float(absf(turned)).is_between(50.0, 55.0)


func test_turn_coasts_to_a_stop_after_release() -> void:
	var rig: XRRig = _scene().rig
	for i in 72:
		rig.drive(-1.0, Vector2.ZERO, false, DT)
	var yaw_release := _yaw(rig)
	for i in 60:
		rig.drive(0.0, Vector2.ZERO, false, DT)
	var coast := rad_to_deg(angle_difference(yaw_release, _yaw(rig)))
	assert_float(coast).is_between(4.0, 8.0)                # 60 °/с гасятся за 0,2 с: около 6°
	var yaw_stop := _yaw(rig)
	rig.drive(0.0, Vector2.ZERO, false, DT)
	assert_float(_yaw(rig)).is_equal(yaw_stop)


func test_vignette_follows_turn_speed() -> void:
	var rig: XRRig = _scene().rig
	assert_float(rig.vignette_amount()).is_equal(0.0)
	for i in 72:
		rig.drive(1.0, Vector2.ZERO, false, DT)
	assert_float(rig.vignette_amount()).is_equal_approx(RigMath.TURN_VIGNETTE_MAX, 0.01)
	for i in 72:
		rig.drive(0.0, Vector2.ZERO, false, DT)
	assert_float(rig.vignette_amount()).is_equal(0.0)


func test_vignette_respects_the_configured_strength() -> void:
	var rig: XRRig = _scene().rig
	rig.turn_vignette = 0.2
	for i in 72:
		rig.drive(1.0, Vector2.ZERO, false, DT)
	assert_float(rig.vignette_amount()).is_equal_approx(0.2, 0.01)
	rig.turn_vignette = 0.0
	for i in 72:
		rig.drive(1.0, Vector2.ZERO, false, DT)
	assert_float(rig.vignette_amount()).is_equal(0.0)


func test_turn_keeps_working_in_tunnel() -> void:
	var scene := _scene()
	scene.begin_tunnel("Архив", 2.0)
	var yaw0 := _yaw(scene.rig)
	for i in 36:
		scene.rig.drive(1.0, Vector2.ZERO, false, DT)
	assert_float(absf(angle_difference(yaw0, _yaw(scene.rig)))).is_greater(0.1)


func test_snap_mode_turns_by_one_step_per_push() -> void:
	var rig: XRRig = _scene().rig
	rig.turn_mode = RigMath.TURN_MODE_SNAP
	var yaw0 := _yaw(rig)
	rig.drive(1.0, Vector2.ZERO, false, DT)
	assert_float(rad_to_deg(angle_difference(yaw0, _yaw(rig)))).is_equal_approx(-RigMath.SNAP_STEP_DEG, 0.01)
	rig.drive(1.0, Vector2.ZERO, false, DT)
	assert_float(rad_to_deg(angle_difference(yaw0, _yaw(rig)))).is_equal_approx(-RigMath.SNAP_STEP_DEG, 0.01)   # держим — второго рывка нет
	assert_float(rig.vignette_amount()).is_equal(0.0)


func test_aim_stays_where_the_player_looks_after_turning() -> void:
	var rig: XRRig = _scene().rig
	for i in 36:
		rig.drive(-1.0, Vector2.ZERO, false, DT)   # влево
	_frames(rig, 20)
	_frames(rig, 3, 0.0, Vector2(0, 1))
	var t := rig.aim_target() - rig.global_position
	assert_float(t.x).is_less(-1.0)   # прицел ушёл влево вместе со взглядом

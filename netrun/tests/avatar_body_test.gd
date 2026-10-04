extends GdUnitTestSuite
## Тело чужого нетраннера — светящаяся голова и две руки (shared/avatar_pose.gd, client/head_cloud.gd, client/avatar_body.gd, замена runner.glb в AvatarView):
## кодек позы, облако головы, чужие руки с проверкой глубины и цветом игрока, показ вместо модели и возврат к ней.

func _pose(with_left: bool = true, with_right: bool = true) -> AvatarPose:
	var p := AvatarPose.new()
	p.head = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 1.6, -0.2))
	if with_left:
		p.set_hand(AvatarPose.LEFT, Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-0.25, 1.1, -0.45)), 0.3, 0.8)
	if with_right:
		p.set_hand(AvatarPose.RIGHT, Transform3D(Basis(Vector3.UP, -0.3), Vector3(0.3, 1.2, -0.5)), 1.0, 0.0)
	return p


func _body() -> AvatarBody:
	var b := AvatarBody.new()
	add_child(b)
	return auto_free(b)


# ---------------------------------------------------------------- кодек позы

func test_pose_round_trips_through_json_within_the_quantization() -> void:
	var p := _pose()
	var back := AvatarPose.decode(JSON.parse_string(JSON.stringify(p.encode())))
	assert_object(back).is_not_null()
	assert_float(back.head.origin.distance_to(p.head.origin)).is_less(0.002)
	assert_float(Quaternion(back.head.basis).angle_to(Quaternion(p.head.basis))).is_less(0.005)
	for side in 2:
		assert_bool(back.has_hand[side]).is_true()
		assert_float(back.palm[side].origin.distance_to(p.palm[side].origin)).is_less(0.002)
		assert_float(back.trigger[side]).is_equal_approx(p.trigger[side], 0.006)
		assert_float(back.hold[side]).is_equal_approx(p.hold[side], 0.006)


func test_missing_hand_has_no_key_and_decodes_as_absent() -> void:
	var d := _pose(false, true).encode()
	assert_bool(d.has("l")).is_false()
	assert_bool(d.has("r")).is_true()
	var back := AvatarPose.decode(d)
	assert_bool(back.has_hand[AvatarPose.LEFT]).is_false()
	assert_bool(back.has_hand[AvatarPose.RIGHT]).is_true()


func test_wire_size_is_small() -> void:
	assert_int(JSON.stringify(_pose().encode()).length()).is_less(320)


func test_garbage_poses_are_rejected() -> void:
	assert_object(AvatarPose.decode(null)).is_null()
	assert_object(AvatarPose.decode({})).is_null()
	assert_object(AvatarPose.decode({"h": [0, 1, 2]})).is_null()  # не хватает чисел
	assert_object(AvatarPose.decode({"h": [0, 1, 0, 0, 0, 0, 0]})).is_null()  # нулевой кватернион
	assert_object(AvatarPose.decode({"h": [0, 99, 0, 0, 0, 0, 1]})).is_null()  # далеко от пола аватара
	assert_object(AvatarPose.decode({"h": [0, 1, 0, 0, 0, 0, 1.0 / 0.0]})).is_null()
	assert_object(AvatarPose.decode({"h": [0, 1, 0, 0, 0, 0, "x"]})).is_null()


func test_broken_hand_drops_out_but_the_head_stays() -> void:
	var d := _pose().encode()
	d["l"] = [0, 0, 0]
	var back := AvatarPose.decode(d)
	assert_object(back).is_not_null()
	assert_bool(back.has_hand[AvatarPose.LEFT]).is_false()
	assert_bool(back.has_hand[AvatarPose.RIGHT]).is_true()


func test_decoded_basis_is_orthonormal() -> void:
	var d := _pose().encode()
	d["h"] = [0, 1.5, 0, 0.0, 2.0, 0.0, 0.0]  # кватернион не единичный
	var back := AvatarPose.decode(d)
	assert_float(back.head.basis.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(back.head.basis.y.length()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- голова

func test_head_cloud_count_and_budget() -> void:
	var h: HeadCloud = auto_free(HeadCloud.new())
	assert_int(h.particle_count()).is_between(420, 540)  # сопоставимо с рукой (≈ 480 точек), иначе лицо не читается
	assert_int(h.multimesh().instance_count).is_equal(h.particle_count())
	assert_int(h.multimesh().buffer.size()).is_equal(h.particle_count() * HeadCloud.STRIDE)


func test_head_particles_sit_around_the_skull() -> void:
	var h: HeadCloud = auto_free(HeadCloud.new())
	for i in h.particle_count():
		assert_float(h.particle_position(i).distance_to(HeadCloud.CENTER)).is_less(0.2)


func test_face_mask_looks_forward_and_is_brighter_than_the_back_of_the_head() -> void:
	var tpl := HeadCloud.template()
	var face_z := 0.0
	var face_w := 0.0
	for i in HeadCloud.FACE_POINTS:
		face_z += (tpl[i][0] as Vector3).z
		face_w += float(tpl[i][3])
	assert_float(face_z / HeadCloud.FACE_POINTS).is_less(HeadCloud.CENTER.z - 0.05)  # маска спереди: -Z от центра головы
	var shell_w := 0.0
	for i in range(HeadCloud.FACE_POINTS, HeadCloud.FACE_POINTS + HeadCloud.SHELL_POINTS):
		shell_w += float(tpl[i][3])
	assert_float(face_w / HeadCloud.FACE_POINTS).is_greater(shell_w / HeadCloud.SHELL_POINTS + 0.15)


func test_face_is_symmetric_with_two_eyes_at_eye_level() -> void:
	var tpl := HeadCloud.template()
	var left := 0
	var right := 0
	var eyes := 0
	var eye_n := 2 * (HeadCloud.EYE_LINE_POINTS + HeadCloud.EYE_PUPIL_POINTS)
	for i in HeadCloud.OUTLINE_POINTS + eye_n:  # контур и глаза
		var q: Vector3 = tpl[i][0]
		if absf(q.x) > 0.005:
			if q.x > 0.0:
				right += 1
			else:
				left += 1
	for i in range(HeadCloud.OUTLINE_POINTS, HeadCloud.OUTLINE_POINTS + eye_n):  # глаза: на высоте глаз (начало координат) и по обе стороны носа
		var q: Vector3 = tpl[i][0]
		assert_float(absf(q.y)).is_less(0.012)
		assert_float(absf(q.x)).is_between(0.015, 0.06)
		eyes += 1
	assert_int(eyes).is_equal(eye_n)
	assert_int(absi(left - right)).is_less(4)


func test_nose_and_mouth_are_on_the_midline_below_the_eyes() -> void:
	var tpl := HeadCloud.template()
	var nose_start := HeadCloud.OUTLINE_POINTS + 2 * (HeadCloud.EYE_LINE_POINTS + HeadCloud.EYE_PUPIL_POINTS) + 2 * HeadCloud.BROW_POINTS
	var nose_tip: Vector3 = tpl[nose_start + HeadCloud.NOSE_POINTS - 1][0]
	var nose_bridge: Vector3 = tpl[nose_start][0]
	assert_float(absf(nose_tip.x)).is_less(0.002)
	assert_float(nose_tip.y).is_less(nose_bridge.y - 0.03)
	assert_float(nose_tip.z).is_less(nose_bridge.z)  # кончик носа выступает вперёд
	var mouth_start := nose_start + HeadCloud.NOSE_POINTS + HeadCloud.NOSTRIL_POINTS
	for i in HeadCloud.MOUTH_POINTS:
		assert_float((tpl[mouth_start + i][0] as Vector3).y).is_less(nose_tip.y)  # рот ниже кончика носа


func test_head_tint_colours_points_and_lightens_sparks() -> void:
	var h: HeadCloud = auto_free(HeadCloud.new())
	h.set_tint(Color(1.0, 0.0, 0.2))
	var buf := h.multimesh().buffer
	assert_float(buf[12]).is_equal_approx(1.0, 0.001)
	assert_float(buf[13]).is_equal_approx(0.0, 0.001)
	var last := (h.particle_count() - 1) * HeadCloud.STRIDE
	assert_float(buf[last + 13]).is_greater(0.3)  # искра светлее


func test_head_is_depth_tested_hands_of_the_owner_are_not() -> void:
	var h: HeadCloud = auto_free(HeadCloud.new())
	assert_bool(h.material().shader.code.contains("depth_test_disabled")).is_false()
	var own := HandView.new(false)
	add_child(own)
	auto_free(own)
	assert_bool(own.material().shader.code.contains("depth_test_disabled")).is_true()


# ---------------------------------------------------------------- тело

func test_body_has_three_draw_calls() -> void:
	var b := _body()
	assert_int(b.find_children("*", "MultiMeshInstance3D", true, false).size()).is_equal(3)


func test_body_is_hidden_without_a_pose() -> void:
	var b := _body()
	assert_bool(b.has_pose()).is_false()
	b._process(0.016)
	assert_bool(b.head_cloud.visible).is_false()
	assert_bool(b.left_hand.visible).is_false()
	assert_bool(b.right_hand.visible).is_false()


func test_body_shows_head_and_both_hands_at_once_for_a_new_pose() -> void:
	var b := _body()
	b.apply_pose(_pose())
	b._process(0.016)
	assert_bool(b.has_pose()).is_true()
	assert_bool(b.head_cloud.visible).is_true()
	assert_bool(b.left_hand.visible).is_true()
	assert_bool(b.right_hand.visible).is_true()
	assert_float(b.head_cloud.position.distance_to(Vector3(0.1, 1.6, -0.2))).is_less(0.001)  # без плавного подлёта из нуля
	var wrist := b.right_hand.last_pose()[HandSkeleton.WRIST]
	assert_float(wrist.distance_to(Vector3(0.3, 1.2, -0.5))).is_less(0.2)  # рука у присланной рамки ладони


func test_missing_hand_is_hidden_and_returns_without_flying_in() -> void:
	var b := _body()
	b.apply_pose(_pose(false, true))
	b._process(0.016)
	assert_bool(b.left_hand.visible).is_false()
	b.apply_pose(_pose(true, true))
	b._process(0.016)
	b.left_hand.update_hand()
	assert_bool(b.left_hand.visible).is_true()
	var palm := b.left_hand.last_pose()[HandSkeleton.PALM]
	assert_float(palm.distance_to(Vector3(-0.25, 1.1, -0.45))).is_less(0.12)


func test_body_follows_smoothly_toward_a_new_pose() -> void:
	var b := _body()
	b.apply_pose(_pose())
	b._process(0.016)
	var moved := _pose()
	moved.head.origin += Vector3(0.5, 0, 0)
	b.apply_pose(moved)
	b._process(0.016)
	var x := b.head_cloud.position.x
	assert_float(x).is_greater(0.1)
	assert_float(x).is_less(0.6)  # ещё не дошла
	for i in 60:
		b._process(0.016)
	assert_float(b.head_cloud.position.x).is_equal_approx(0.6, 0.01)


func test_body_hides_when_the_pose_goes_stale() -> void:
	var b := _body()
	b.apply_pose(_pose())
	b._process(0.016)
	b._process(AvatarBody.STALE_SEC + 0.1)
	assert_bool(b.has_pose()).is_false()
	assert_bool(b.head_cloud.visible).is_false()


func test_body_is_coloured_for_the_player() -> void:
	var b := _body()
	b.set_color(Color(0.2, 1.0, 0.3))
	assert_float(b.right_hand.buffer()[12]).is_equal_approx(0.2, 0.001)
	assert_float(b.left_hand.buffer()[13]).is_equal_approx(1.0, 0.001)
	assert_float(b.head_cloud.multimesh().buffer[14]).is_equal_approx(0.3, 0.001)


func test_remote_hands_are_depth_tested() -> void:
	var b := _body()
	assert_bool(b.right_hand.material().shader.code.contains("depth_test_disabled")).is_false()


func test_hand_pose_can_be_rebuilt_from_frame_and_curls() -> void:
	var v := HandView.new(false)
	add_child(v)
	auto_free(v)
	var grip := Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.2, 1.0, -0.4))
	var direct := v.controller_pose(grip, 0.4, 0.7)
	var rebuilt := v.pose_at(v.palm_frame(grip), 0.4, 0.7)
	for j in HandSkeleton.COUNT:
		assert_float(direct[j].distance_to(rebuilt[j])).is_less(0.0001)


# ---------------------------------------------------------------- AvatarView

func test_avatar_view_swaps_the_runner_for_the_body_and_back() -> void:
	var av := AvatarView.new()
	add_child(av)
	auto_free(av)
	av.setup(3)
	var model := av.get_node("Model") as Node3D
	assert_bool(model.visible).is_true()
	av.apply_pose(_pose())
	av.body._process(0.016)
	av._process(0.016)
	assert_bool(model.visible).is_false()
	assert_bool(av.body.head_cloud.visible).is_true()
	av.body._process(AvatarBody.STALE_SEC + 0.1)
	av._process(0.016)
	assert_bool(model.visible).is_true()  # поза пропала: снова runner.glb


func test_avatar_view_body_uses_the_players_colour_and_floor_point() -> void:
	var av := AvatarView.new()
	add_child(av)
	auto_free(av)
	av.setup(2)
	av.position = Vector3(3, 0, -2)
	av.rotation.y = 1.0  # лицо по ходу: на тело в осях мира не влияет
	av.apply_pose(_pose())
	av._process(0.016)
	av.body._process(0.016)
	assert_float(av.body.global_position.distance_to(Vector3(3, 0, -2))).is_less(0.001)
	assert_float(av.body.head_cloud.global_position.distance_to(Vector3(3.1, 1.6, -2.2))).is_less(0.001)
	assert_float(av.body.color.r).is_equal_approx(AvatarView.color_for(2).r, 0.001)

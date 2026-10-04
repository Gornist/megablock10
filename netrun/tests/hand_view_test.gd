extends GdUnitTestSuite
## Руки игрока (shared/hand_skeleton.gd, client/hand_view.gd): скелет из 26 суставов в порядке OpenXR, сгиб пальцев по курку и хвату, облако частиц на костях и ладони,
## три источника позы (для тестов, трекинг рук, контроллер), буфер экземпляров MultiMesh. Как рука выглядит — кадры assets/preview_hands.tscn.

const COUNT := 26


func _view(left: bool = false, pose: PackedVector3Array = PackedVector3Array()) -> HandView:
	var v := HandView.new(left)
	if pose.size() == COUNT:
		v.pose_source = func(): return pose
	add_child(v)
	return auto_free(v)


func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------- скелет

func test_joint_indices_follow_openxr() -> void:
	assert_int(HandSkeleton.COUNT).is_equal(XRHandTracker.HAND_JOINT_MAX)
	assert_int(HandSkeleton.PALM).is_equal(XRHandTracker.HAND_JOINT_PALM)
	assert_int(HandSkeleton.WRIST).is_equal(XRHandTracker.HAND_JOINT_WRIST)
	assert_int(HandSkeleton.THUMB_META).is_equal(XRHandTracker.HAND_JOINT_THUMB_METACARPAL)
	assert_int(HandSkeleton.THUMB_TIP).is_equal(XRHandTracker.HAND_JOINT_THUMB_TIP)
	assert_int(HandSkeleton.INDEX_META).is_equal(XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL)
	assert_int(HandSkeleton.INDEX_PROX).is_equal(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL)
	assert_int(HandSkeleton.INDEX_INTER).is_equal(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE)
	assert_int(HandSkeleton.INDEX_DIST).is_equal(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL)
	assert_int(HandSkeleton.INDEX_TIP).is_equal(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	assert_int(HandSkeleton.MIDDLE_TIP).is_equal(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP)
	assert_int(HandSkeleton.RING_TIP).is_equal(XRHandTracker.HAND_JOINT_RING_FINGER_TIP)
	assert_int(HandSkeleton.LITTLE_META).is_equal(XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL)
	assert_int(HandSkeleton.LITTLE_TIP).is_equal(XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP)
	assert_int(HandSkeleton.REST.size()).is_equal(COUNT)


func test_open_hand_has_human_proportions() -> void:
	var p := HandSkeleton.pose({})
	var hand_len := p[HandSkeleton.MIDDLE_TIP].distance_to(p[HandSkeleton.WRIST])
	assert_float(hand_len).override_failure_message("рука %.3f м" % hand_len).is_between(0.17, 0.21)
	var width := p[HandSkeleton.INDEX_PROX].distance_to(p[HandSkeleton.LITTLE_PROX])
	assert_float(width).override_failure_message("ладонь %.3f м" % width).is_between(0.055, 0.075)
	# средний палец длиннее остальных, мизинец короче всех
	var reach := func(tip: int) -> float: return p[tip].distance_to(p[HandSkeleton.WRIST])
	assert_bool(reach.call(HandSkeleton.MIDDLE_TIP) > reach.call(HandSkeleton.INDEX_TIP)).is_true()
	assert_bool(reach.call(HandSkeleton.INDEX_TIP) > reach.call(HandSkeleton.LITTLE_TIP)).is_true()
	# пальцы смотрят вперёд (-Z), запястье позади ладони
	assert_bool(p[HandSkeleton.WRIST].z > 0.0).is_true()
	assert_bool(p[HandSkeleton.MIDDLE_TIP].z < -0.1).is_true()


func test_fist_pulls_the_fingertips_into_the_palm() -> void:
	var open := HandSkeleton.pose({})
	var fist := HandSkeleton.pose({"thumb": 1.0, "index": 1.0, "middle": 1.0, "ring": 1.0, "little": 1.0})
	for tip in [HandSkeleton.INDEX_TIP, HandSkeleton.MIDDLE_TIP, HandSkeleton.RING_TIP, HandSkeleton.LITTLE_TIP]:
		var d_open: float = open[tip].distance_to(open[HandSkeleton.PALM])
		var d_fist: float = fist[tip].distance_to(fist[HandSkeleton.PALM])
		assert_float(d_fist).override_failure_message("кончик %d: кулак %.3f, ладонь %.3f" % [tip, d_fist, d_open]).is_less(d_open * 0.7)
		assert_bool(fist[tip].y < -0.01).override_failure_message("кончик сжатого пальца к ладонной стороне (-Y)").is_true()
	assert_float(fist[HandSkeleton.THUMB_TIP].distance_to(open[HandSkeleton.THUMB_TIP])).is_greater(0.02)


func test_curl_keeps_the_bone_lengths() -> void:
	var open := HandSkeleton.pose({})
	var bent := HandSkeleton.pose({"thumb": 0.7, "index": 0.5, "middle": 1.0, "ring": 0.3, "little": 0.8})
	for chain in HandSkeleton.FINGERS.values():
		for k in range(1, chain.size() - 1):
			var l0: float = open[chain[k]].distance_to(open[chain[k + 1]])
			var l1: float = bent[chain[k]].distance_to(bent[chain[k + 1]])
			assert_float(l1).override_failure_message("кость %d→%d: %.4f вместо %.4f" % [chain[k], chain[k + 1], l1, l0]).is_equal_approx(l0, 0.0005)


func test_left_hand_is_the_mirror_of_the_right() -> void:
	var curls := {"index": 0.6, "thumb": 0.4}
	var r := HandSkeleton.pose(curls, false)
	var l := HandSkeleton.pose(curls, true)
	for i in COUNT:
		assert_float(l[i].x).is_equal_approx(-r[i].x, 0.00001)
		assert_float(l[i].y).is_equal_approx(r[i].y, 0.00001)
		assert_float(l[i].z).is_equal_approx(r[i].z, 0.00001)


func test_trigger_bends_the_index_and_grip_the_rest() -> void:
	var relaxed := HandSkeleton.curls_from_inputs(0.0, 0.0)
	var trig := HandSkeleton.curls_from_inputs(1.0, 0.0)
	var grip := HandSkeleton.curls_from_inputs(0.0, 1.0)
	assert_float(relaxed["index"]).is_equal_approx(HandSkeleton.RELAXED_CURL, 0.0001)  # пустая рука — не струна
	assert_float(trig["index"]).is_equal_approx(1.0, 0.0001)
	assert_float(trig["middle"]).is_equal_approx(HandSkeleton.RELAXED_CURL, 0.0001)
	assert_float(grip["middle"]).is_equal_approx(1.0, 0.0001)
	assert_float(grip["little"]).is_equal_approx(1.0, 0.0001)
	assert_float(grip["index"]).is_equal_approx(HandSkeleton.RELAXED_CURL, 0.0001)
	var wild := HandSkeleton.curls_from_inputs(5.0, -3.0)  # входы за пределами 0…1 зажаты
	assert_float(wild["index"]).is_equal_approx(1.0, 0.0001)
	assert_float(wild["middle"]).is_equal_approx(HandSkeleton.RELAXED_CURL, 0.0001)


func test_palm_basis_is_orthonormal_and_follows_the_hand() -> void:
	var pose := HandSkeleton.pose({})
	var b := HandSkeleton.palm_basis(pose)
	assert_float(b.x.length()).is_equal_approx(1.0, 0.0001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.0001)
	assert_float(b.z.length()).is_equal_approx(1.0, 0.0001)
	assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 0.0001)
	assert_float(b.x.dot(b.z)).is_equal_approx(0.0, 0.0001)
	assert_bool(b.z.z > 0.9).override_failure_message("ось Z — назад к запястью").is_true()
	# рука повёрнута: система ладони повернулась вместе с ней
	var turn := Basis(Vector3.UP, deg_to_rad(90.0))
	var rotated := PackedVector3Array()
	for p in pose:
		rotated.append(turn * p)
	assert_float(HandSkeleton.palm_basis(rotated).z.dot(turn * b.z)).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- шаблон частиц

func test_template_is_deterministic_and_has_every_group() -> void:
	var a := HandSkeleton.template(5)
	var b := HandSkeleton.template(5)
	var c := HandSkeleton.template(6)
	assert_int(a.size()).is_equal(HandSkeleton.particle_count())
	assert_bool(a == b).is_true()
	assert_bool(a != c).is_true()
	var palm := 0
	var bone := 0
	var wrist := 0
	var spark := 0
	for p in a:
		if float(p[0]) > 0.5:
			spark += 1
		elif int(p[1]) == -1:
			palm += 1
		elif int(p[1]) == -2:
			wrist += 1
		else:
			bone += 1
		assert_float(float(p[6])).is_between(0.0, 0.006)  # полуразмер, м
		assert_float(float(p[7])).is_between(0.0, 1.0)    # яркость
		assert_float(float(p[8])).is_between(0.0, 1.0)    # фаза вдоль руки
	assert_int(palm).is_equal(HandSkeleton.PALM_POINTS)
	assert_int(bone).is_equal(HandSkeleton.BONES.size() * HandSkeleton.BONE_POINTS)
	assert_int(wrist).is_equal(HandSkeleton.WRIST_POINTS)
	assert_int(spark).is_equal(HandSkeleton.SPARK_COUNT)


# ---------------------------------------------------------------- вид руки

func test_without_any_pose_the_hand_is_hidden() -> void:
	var v := _view()
	v.update_hand()
	assert_bool(v.visible).is_false()
	assert_int(v.mode).is_equal(HandView.Mode.NONE)


func test_pose_fills_the_instance_buffer() -> void:
	var pose := HandSkeleton.pose({})
	var v := _view(false, pose)
	v.update_hand()
	assert_bool(v.visible).is_true()
	assert_int(v.mode).is_equal(HandView.Mode.POSE_SOURCE)
	assert_int(v.buffer().size()).is_equal(v.particle_count() * HandView.STRIDE)
	assert_int(v.multimesh().instance_count).is_equal(v.particle_count())
	assert_bool(v.multimesh().use_colors and v.multimesh().use_custom_data).is_true()
	assert_int(v.particle_count()).is_equal(HandSkeleton.particle_count())


func test_particles_stay_on_the_hand() -> void:
	var pose := HandSkeleton.pose({"index": 0.6, "middle": 0.9, "thumb": 0.3})
	var v := _view(false, pose)
	v.update_hand()
	var tpl := HandSkeleton.template(17)
	var palm_c := pose[HandSkeleton.PALM]
	for i in tpl.size():
		var p: Array = tpl[i]
		var q := v.particle_position(i)
		if float(p[0]) > 0.5:  # искра стартует на кончике пальца
			assert_float(q.distance_to(pose[int(p[1])])).is_less(0.001)
		elif int(p[1]) == -1:  # ладонь: рядом с центром ладони, в пределах эллипса и толщины
			assert_float(q.distance_to(palm_c)).override_failure_message("ладонная точка %d далеко: %.3f" % [i, q.distance_to(palm_c)]).is_less(0.08)
		elif int(p[1]) == -2:  # запястье
			assert_float(q.distance_to(pose[HandSkeleton.WRIST])).is_less(0.04)
		else:  # на кости: не дальше радиуса (с запасом) от отрезка кости
			var d := _dist_to_segment(q, pose[int(p[1])], pose[int(p[2])])
			assert_float(d).override_failure_message("частица %d в %.4f м от кости %d→%d" % [i, d, p[1], p[2]]).is_less(0.013)


func test_particles_follow_the_pose() -> void:
	var offset := Vector3(0.4, 1.1, -0.3)
	var pose := HandSkeleton.pose({})
	var moved := PackedVector3Array()
	for p in pose:
		moved.append(p + offset)
	var a := _view(false, pose)
	a.update_hand()
	var b := _view(false, moved)
	b.update_hand()
	for i in [0, 10, 70, a.particle_count() - 1]:
		assert_float(b.particle_position(i).distance_to(a.particle_position(i) + offset)).is_less(0.0001)


func test_instance_data_is_in_range_and_the_hand_is_not_red() -> void:
	var v := _view(false, HandSkeleton.pose({}))
	v.update_hand()
	var buf := v.buffer()
	var sparks := 0
	for i in v.particle_count():
		var o := i * HandView.STRIDE
		assert_float(buf[o + 12]).is_less_equal(buf[o + 14])  # красная составляющая не сильнее синей: красный — другие люди и угроза
		assert_float(buf[o + 16]).is_between(0.0005, 0.006)   # полуразмер
		assert_float(buf[o + 19]).is_between(0.0, 1.0)        # яркость
		if buf[o + 18] > 0.5:
			sparks += 1
	assert_int(sparks).is_equal(HandSkeleton.SPARK_COUNT)


func test_left_view_mirrors_the_right() -> void:
	var right_pose := HandSkeleton.pose({"index": 0.5})
	var left_pose := HandSkeleton.pose({"index": 0.5}, true)
	var r := _view(false, right_pose)
	var l := _view(true, left_pose)
	r.update_hand()
	l.update_hand()
	assert_str(String(r.name)).is_equal("RightHandView")
	assert_str(String(l.name)).is_equal("LeftHandView")
	# палец «указательный» у правой руки слева (x < 0), у левой — справа
	assert_bool(r.last_pose()[HandSkeleton.INDEX_TIP].x < 0.0).is_true()
	assert_bool(l.last_pose()[HandSkeleton.INDEX_TIP].x > 0.0).is_true()


func test_shader_is_the_hand_shader_with_the_voxel_lattice() -> void:
	var v := _view()
	var m := v.material()
	assert_bool(m != null and m.shader != null).is_true()
	assert_float(float(m.get_shader_parameter("lattice")) if m.get_shader_parameter("lattice") != null else 0.008).is_between(0.0, 0.02)
	assert_bool(m.shader.get_shader_uniform_list().any(func(u): return u["name"] == "lattice")).is_true()


# ---------------------------------------------------------------- источники позы

func test_controller_pose_puts_the_palm_on_the_grip_and_follows_it() -> void:
	var v := _view()
	var grip := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(0.25, 0.9, -0.35))
	var p := v.controller_pose(grip, 0.0, 0.0)
	assert_int(p.size()).is_equal(COUNT)
	var seat := Transform3D(Basis(Vector3(0, 0, -1), deg_to_rad(HandView.HAND_ROLL_DEG)).scaled(Vector3.ONE * HandView.HAND_SCALE), Vector3.ZERO)
	var palm := grip * Transform3D(Basis.IDENTITY, Vector3(0, 0, HandView.HAND_TOWARD_VIEWER)) * seat
	assert_float(p[HandSkeleton.PALM].distance_to(palm.origin)).is_less(0.0001)
	var local := HandSkeleton.pose(HandSkeleton.curls_from_inputs(0.0, 0.0), false)
	assert_float(p[HandSkeleton.MIDDLE_TIP].distance_to(palm * local[HandSkeleton.MIDDLE_TIP])).is_less(0.0001)


func test_seat_enlarges_turns_and_brings_the_hand_to_the_viewer() -> void:
	var v := _view()
	var p := v.controller_pose(Transform3D.IDENTITY, 0.0, 0.0)
	var local := HandSkeleton.pose(HandSkeleton.curls_from_inputs(0.0, 0.0), false)
	var len0: float = (local[HandSkeleton.MIDDLE_TIP] - local[HandSkeleton.PALM]).length()
	assert_float((p[HandSkeleton.MIDDLE_TIP] - p[HandSkeleton.PALM]).length()).is_equal_approx(len0 * 1.1, 0.0005)
	assert_float(p[HandSkeleton.PALM].z).is_equal_approx(0.04, 0.0001)  # к зрителю (+Z контроллера)
	var back0 := HandSkeleton.back_direction(local, false)
	var back1 := HandSkeleton.back_direction(p, false)
	assert_float(back0.angle_to(back1)).is_equal_approx(PI / 2.0, 0.05)


func test_controller_pose_bends_with_the_trigger() -> void:
	var v := _view()
	var open := v.controller_pose(Transform3D.IDENTITY, 0.0, 0.0)
	var pulled := v.controller_pose(Transform3D.IDENTITY, 1.0, 0.0)
	assert_float(pulled[HandSkeleton.INDEX_TIP].distance_to(pulled[HandSkeleton.PALM])).is_less(open[HandSkeleton.INDEX_TIP].distance_to(open[HandSkeleton.PALM]) * 0.7)
	assert_float(pulled[HandSkeleton.MIDDLE_TIP].distance_to(open[HandSkeleton.MIDDLE_TIP])).is_less(0.001)  # курок остальные пальцы не двигает


func test_grip_calibration_turns_and_shifts_the_hand() -> void:
	var v := _view()
	var base := v.controller_pose(Transform3D.IDENTITY, 0.0, 0.0)
	v.grip_offset = Vector3(0.0, 0.0, 0.05)
	var shifted := v.controller_pose(Transform3D.IDENTITY, 0.0, 0.0)
	assert_float(shifted[HandSkeleton.PALM].z - base[HandSkeleton.PALM].z).is_equal_approx(0.05, 0.0001)
	v.grip_offset = Vector3.ZERO
	v.grip_pitch_deg = 90.0
	var pitched := v.controller_pose(Transform3D.IDENTITY, 0.0, 0.0)
	assert_bool(absf(pitched[HandSkeleton.MIDDLE_TIP].y) > 0.1).override_failure_message("тангаж 90°: пальцы смотрят вверх, не вперёд").is_true()


func test_hand_tracker_overrides_the_controller() -> void:
	var tracker := XRHandTracker.new()
	tracker.name = HandView.TRACKER_RIGHT
	tracker.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	var shift := Vector3(0.1, 1.0, -0.4)
	for j in COUNT:
		tracker.set_hand_joint_transform(j, Transform3D(Basis.IDENTITY, HandSkeleton.REST[j] + shift))
		tracker.set_hand_joint_flags(j, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
	tracker.has_tracking_data = true
	XRServer.add_tracker(tracker)
	var v := _view(false)
	v.update_hand()
	XRServer.remove_tracker(tracker)
	assert_int(v.mode).is_equal(HandView.Mode.TRACKED)
	assert_bool(v.visible).is_true()
	assert_float(v.last_pose()[HandSkeleton.MIDDLE_TIP].distance_to(HandSkeleton.REST[HandSkeleton.MIDDLE_TIP] + shift)).is_less(0.0001)


func test_hand_tracker_without_enough_valid_joints_is_ignored() -> void:
	var tracker := XRHandTracker.new()
	tracker.name = HandView.TRACKER_LEFT
	tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	for j in COUNT:
		tracker.set_hand_joint_transform(j, Transform3D.IDENTITY)
		tracker.set_hand_joint_flags(j, 0 if j > 8 else XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	tracker.has_tracking_data = true
	XRServer.add_tracker(tracker)
	var v := _view(true)
	v.update_hand()
	XRServer.remove_tracker(tracker)
	assert_int(v.mode).is_equal(HandView.Mode.NONE)
	assert_bool(v.visible).is_false()


# ---------------------------------------------------------------- риг и калибровка

func test_rig_has_a_view_for_each_hand_bound_to_its_controller() -> void:
	var rig := auto_free(preload("res://client/xr_rig.tscn").instantiate()) as XRRig
	add_child(rig)
	assert_bool(rig.left_hand_view != null and rig.right_hand_view != null).is_true()
	assert_bool(rig.left_hand_view.left).is_true()
	assert_bool(rig.right_hand_view.left).is_false()
	assert_object(rig.left_hand_view.controller).is_same(rig.left_hand)
	assert_object(rig.right_hand_view.controller).is_same(rig.right_hand)
	assert_object(rig.left_hand_view.get_parent()).is_same(rig)  # позы суставов — в системе рига
	# без очков и данных позы руки скрыты
	rig.left_hand_view.update_hand()
	assert_bool(rig.left_hand_view.visible).is_false()


func test_comfort_calibrates_the_hands_with_limits() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("comfort", "hand_pitch_deg", 200.0)
	cfg.set_value("comfort", "hand_offset_x", 0.05)
	cfg.set_value("comfort", "hand_offset_z", -1.0)
	var c := ComfortConfig.from_config(cfg)
	assert_float(c.hand_pitch_deg).is_equal(90.0)
	assert_float(c.hand_offset_x).is_equal_approx(0.05, 0.0001)
	assert_float(c.hand_offset_z).is_equal_approx(-0.15, 0.0001)
	assert_int(c.warnings.size()).is_equal(2)  # угол и смещение Z вне пределов
	var rig := auto_free(preload("res://client/xr_rig.tscn").instantiate()) as XRRig
	add_child(rig)
	c.apply_to(rig)
	assert_float(rig.right_hand_view.grip_pitch_deg).is_equal(90.0)
	assert_float(rig.right_hand_view.grip_offset.x).is_equal_approx(0.05, 0.0001)
	assert_float(rig.left_hand_view.grip_offset.x).is_equal_approx(-0.05, 0.0001)  # у левой руки X зеркальный
	assert_float(rig.left_hand_view.grip_offset.z).is_equal_approx(-0.15, 0.0001)
	assert_str(String(c.log_fields()["hand"])).is_equal("90,0.05,0,-0.15")


# ---------------------------------------------------------------- якорь запястья и дека

func test_wrist_anchor_sits_on_the_back_of_the_wrist_for_both_hands() -> void:
	for left in [false, true]:
		var pose := HandSkeleton.pose({}, left)
		var v := _view(left, pose)
		v.update_hand()
		var a := v.wrist_anchor
		var back := HandSkeleton.back_direction(pose, left)
		assert_float(back.y).override_failure_message("тыл руки смотрит вверх (рука ладонью вниз), left=%s" % left).is_greater(0.9)
		# над тылом запястья и ближе к локтю: ни на пальцах, ни на ладони
		var pb := HandSkeleton.palm_basis(pose)
		var want := pose[HandSkeleton.WRIST] + back * HandView.WRIST_ANCHOR_BACK + pb.z * HandView.WRIST_ANCHOR_ELBOW  # вдоль кисти к локтю
		assert_float(a.position.distance_to(want)).is_less(0.0005)
		assert_bool(a.position.z > pose[HandSkeleton.WRIST].z).override_failure_message("якорь ближе к локтю, чем запястье").is_true()
		assert_float(a.basis.z.dot(back)).is_greater(0.99)                     # панель смотрит от тыла руки
		assert_float(a.basis.y.dot(-pb.z)).is_greater(0.99)                    # верх панели — к пальцам
		assert_float(a.basis.y.dot(Vector3(0, 0, -1))).is_greater(0.9)         # а пальцы смотрят вперёд
		assert_float(a.basis.determinant()).is_greater(0.99)                   # без зеркала: текст не вывернут


func test_wrist_anchor_follows_the_hand() -> void:
	var pose := HandSkeleton.pose({})
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(40.0)), Vector3(0.3, 1.0, -0.5))
	var moved := PackedVector3Array()
	for p in pose:
		moved.append(turn * p)
	var v := _view(false, moved)
	v.update_hand()
	var home := _view(false, pose)
	home.update_hand()
	assert_float(v.wrist_anchor.position.distance_to(turn * home.wrist_anchor.position)).is_less(0.0005)


func test_deck_is_worn_on_the_wrist_in_vr_and_not_on_the_fingers() -> void:
	var rig := auto_free(preload("res://client/xr_rig.tscn").instantiate()) as XRRig
	add_child(rig)
	var ui := auto_free(WorldUI.new()) as WorldUI
	add_child(ui)
	ui.attach(rig)
	rig.xr_active = true
	rig.left_hand_view.pose_source = func(): return HandSkeleton.pose({}, true)
	rig.left_hand_view.update_hand()
	ui._place()
	assert_object(ui.deck.get_parent().get_parent()).is_same(rig.left_hand_view.wrist_anchor)  # HudAnchor внутри якоря запястья
	assert_float(ui.deck.global_position.distance_to(rig.left_hand_view.wrist_anchor.global_position)).is_less(0.001)
	assert_float(ui.deck.scale.x).is_equal_approx(WorldUI.WRIST_DECK_SCALE, 0.0001)
	# деку не видно у кончиков пальцев: от кисти она дальше, чем лежит ладонь
	var pose: PackedVector3Array = rig.left_hand_view.last_pose()
	assert_float(ui.deck.global_position.z).is_greater(pose[HandSkeleton.WRIST].z)
	assert_float(ui.trace.position.y).is_less(0.0)  # trace ниже деки, к локтю: над кистью его нет
	# нет позы руки — дека скрыта, а не висит в начале рига
	rig.left_hand_view.pose_source = Callable()
	rig.left_hand_view.update_hand()
	ui._place()
	assert_bool(ui.deck.is_visible_in_tree()).is_false()


func test_flat_build_keeps_the_deck_on_the_camera() -> void:
	var rig := auto_free(preload("res://client/xr_rig.tscn").instantiate()) as XRRig
	add_child(rig)
	var ui := auto_free(WorldUI.new()) as WorldUI
	add_child(ui)
	ui.attach(rig)
	assert_object(ui.deck.get_parent().get_parent()).is_same(rig.camera)
	assert_float(ui.deck.scale.x).is_equal(1.0)
	assert_float(ui.trace.position.y).is_equal_approx(0.14, 0.0001)

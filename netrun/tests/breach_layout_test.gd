extends GdUnitTestSuite
## Где стоит панель взлома в мире и как телепорт привязывается к площадке у хранилища (К3, docs/netrun-deck-design.md §7.1).

const VAULT := Vector3(-1.5, 1.0, -9.5)   # NodeLayout.SHARD_SLOTS[0]
const HEAD := Vector3(-1.5, 1.2, -8.5)    # стоя на площадке (1 м к центру комнаты от хранилища)


func test_pose_is_65_cm_from_the_head_12_degrees_below_and_faces_the_head() -> void:
	var head := HEAD
	var t := BreachPanelLayout.pose(head, VAULT)
	var to_panel := t.origin - head
	assert_float(to_panel.length()).is_equal_approx(BreachPanelLayout.DIST_M / cos(deg_to_rad(BreachPanelLayout.DROP_DEG)), 0.001)
	var flat := Vector2(to_panel.x, to_panel.z).length()
	assert_float(flat).is_equal_approx(BreachPanelLayout.DIST_M, 0.001)
	assert_float(rad_to_deg(atan2(-to_panel.y, flat))).is_equal_approx(BreachPanelLayout.DROP_DEG, 0.01)
	# +Z панели (лицо Sprite3D) смотрит на голову
	var normal := t.basis * Vector3(0, 0, 1)
	var back := (head - t.origin).normalized()
	assert_float(normal.dot(back)).is_greater(0.999)
	# и стоит в сторону хранилища (к -Z)
	assert_float(to_panel.z).is_less(0.0)


func test_pose_is_fixed_in_the_world_it_does_not_follow_the_head() -> void:
	var t := BreachPanelLayout.pose(HEAD, VAULT)
	# поза — значение: считается один раз при появлении; другая голова даёт другую позу, но сама панель за головой не ходит (проверка в breach_panel_test)
	var t2 := BreachPanelLayout.pose(HEAD + Vector3(-0.3, 0.0, 0.0), VAULT)
	assert_bool(t.origin.is_equal_approx(t2.origin)).is_false()


func test_panel_size_matches_the_design() -> void:
	assert_float(BreachPanelLayout.WIDTH_M).is_equal(0.48)
	assert_float(BreachPanelLayout.HEIGHT_M).is_equal(0.32)


func test_target_vault_has_hysteresis() -> void:
	var vaults := [{"id": "a", "p": Vector3(0, 1, 0)}, {"id": "b", "p": Vector3(6, 1, 0)}]
	assert_str(BreachPanelLayout.target_vault(Vector3(1.5, 0, 0), vaults)).is_equal("a")
	assert_str(BreachPanelLayout.target_vault(Vector3(2.5, 0, 0), vaults)).is_equal("")                  # дальше SHOW_DIST — панель не появляется
	assert_str(BreachPanelLayout.target_vault(Vector3(2.5, 0, 0), vaults, "a")).is_equal("a")            # но уже стоящая держится до HIDE_DIST
	assert_str(BreachPanelLayout.target_vault(Vector3(3.0, 0, 0), vaults, "a")).is_equal("")
	assert_str(BreachPanelLayout.target_vault(Vector3(5.0, 0, 0), vaults)).is_equal("b")


func test_vault_pad_is_in_front_of_the_vault_and_inside_the_room() -> void:
	for slot in NodeLayout.SHARD_SLOTS:
		var pad := NodeLayout.vault_pad(slot)
		assert_float(NodeLayout.flat_distance(pad, slot)).is_equal_approx(NodeLayout.VAULT_PAD_DIST, 0.001)
		assert_bool(NodeLayout.in_room(pad)).is_true()
		# с той стороны, куда смотрит модель хранилища (к центру комнаты)
		assert_float(NodeLayout.flat_distance(pad, NodeLayout.ROOM_CENTER)).is_less(NodeLayout.flat_distance(slot, NodeLayout.ROOM_CENTER))


func test_snap_puts_the_player_on_the_pad_and_looks_at_the_vault() -> void:
	var near := VAULT + Vector3(0.3, 0, 0.4)   # в клетке хранилища (радиус привязки 0,75 м, П5)
	var s := NodeLayout.snap_to_vault_pad(near, NodeLayout.SHARD_SLOTS)
	assert_float(NodeLayout.flat_distance(s["p"], NodeLayout.vault_pad(VAULT))).is_less(0.001)
	assert_float((s["look"] as Vector3).x).is_equal(VAULT.x)
	assert_float((s["look"] as Vector3).y).is_equal(0.0)
	# идемпотентно: площадка вне радиуса привязки (соседняя клетка), повторная привязка точку не двигает
	assert_object(NodeLayout.snap_to_vault_pad(near + Vector3(1.0, 0, 0), NodeLayout.SHARD_SLOTS)["look"]).is_null()   # соседняя клетка не привязывается
	var again := NodeLayout.snap_to_vault_pad(s["p"], NodeLayout.SHARD_SLOTS)
	assert_float(NodeLayout.flat_distance(again["p"], s["p"])).is_less(0.001)


func test_snap_leaves_far_targets_alone() -> void:
	var far := Vector3(4, 0, -3)
	var s := NodeLayout.snap_to_vault_pad(far, NodeLayout.SHARD_SLOTS)
	assert_bool(s["look"] == null).is_true()
	assert_bool((s["p"] as Vector3).is_equal_approx(far)).is_true()


func test_snap_takes_the_nearest_of_several_vaults() -> void:
	var s := NodeLayout.snap_to_vault_pad(Vector3(-5.2, 0, -12.6), NodeLayout.SHARD_SLOTS)   # в клетке хранилища (-5,5; -12,5)
	assert_float(NodeLayout.flat_distance(s["p"], NodeLayout.vault_pad(NodeLayout.SHARD_SLOTS[1]))).is_less(0.001)

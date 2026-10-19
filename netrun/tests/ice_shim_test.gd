extends GdUnitTestSuite
## Шим ICE (server/ice/ice_brain.gd, ice_node.gd): думает TickIce / TickBlack, а шим несёт то, что читают узел, журнал и снимок состояния —
## код состояния, имя состояния, позицию и взгляд, сигналы ejected / state_changed, множитель тревоги.

const S := IceBrain.State
const LAIR: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)]


func _ctx(trace: float) -> Dictionary:
	return {"targets": {"s1": Vector2i(13, 7)}, "traces": {"s1": trace}, "hidden": {}, "alarm_level": 0, "immune": {}}


func test_state_names_for_the_journal() -> void:
	assert_str(IceBrain.state_name(S.PATROL)).is_equal("PATROL")
	assert_str(IceBrain.state_name(S.SUSPICIOUS)).is_equal("SUSPICIOUS")
	assert_str(IceBrain.state_name(S.SEARCH)).is_equal("SEARCH")
	assert_str(IceBrain.state_name(S.HUNT)).is_equal("HUNT")
	assert_str(IceBrain.state_name(99)).is_equal("?")


func test_fresh_shim_is_quiet_patrol_without_alert() -> void:
	var b := IceBrain.new(false, Vector3(1, 0, 2))
	assert_int(b.state()).is_equal(S.PATROL)
	assert_float(b.awareness()).is_equal(0.0)
	assert_str(b.target()).is_equal("")
	assert_bool(b.is_black()).is_false()
	assert_bool(b.is_hunting("s1")).is_false()
	assert_float(b.alert_scale).is_equal(1.0)
	assert_vector(b.position).is_equal(Vector3(1, 0, 2))


func test_forgetting_a_stranger_changes_nothing() -> void:
	var b := IceBrain.new()
	var changes: Array = []
	b.state_changed.connect(func(o: int, n: int) -> void: changes.append([o, n]))
	b.forget("nobody")
	assert_array(changes).is_empty()
	assert_int(b.state()).is_equal(S.PATROL)


func test_node_setup_looks_along_the_route_and_forwards_ejected() -> void:
	var n: IceNode = auto_free(IceNode.new())
	var wps: Array[Vector3] = [Vector3(1, 0, 1), Vector3(5, 0, 1)]
	n.position = wps[0]
	n.setup(false, wps)
	assert_vector(n.brain.facing).is_equal(Vector3.RIGHT)
	assert_vector(n.brain.position).is_equal(wps[0])
	var got: Array = []
	n.ejected.connect(func(s: String, r: String) -> void: got.append([s, r]))
	n.brain.ejected.emit("s1", "caught")
	assert_array(got).is_equal([["s1", "caught"]])


func test_node_setup_marks_black() -> void:
	var n: IceNode = auto_free(IceNode.new())
	n.setup(true)
	assert_bool(n.brain.is_black()).is_true()


func test_black_brain_mirrors_tick_black_phase_in_state_and_signals() -> void:
	var tb := TickBlack.new(LAIR, Vector2i(7, 7), NodeGrid.new(), {}, {})
	var b := TickBlackBrain.new(tb)
	var changes: Array = []
	b.state_changed.connect(func(o: int, n: int) -> void: changes.append([o, n]))
	assert_bool(b.is_black()).is_true()
	b.tick_step(_ctx(10.0))   # trace ниже порога: сон
	assert_int(b.state()).is_equal(S.PATROL)
	b.tick_step(_ctx(55.0))   # пробуждение
	assert_int(b.state()).is_equal(S.SUSPICIOUS)
	assert_bool(b.is_hunting("s1")).is_false()
	for i in 6:
		b.tick_step(_ctx(55.0))
	assert_int(b.state()).is_equal(S.HUNT)
	assert_bool(b.is_hunting("anyone")).is_true()   # под охотой порталы закрыты для всех
	assert_array(changes).is_equal([[S.PATROL, S.SUSPICIOUS], [S.SUSPICIOUS, S.HUNT]])

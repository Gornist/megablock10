extends GdUnitTestSuite
## Журнал ICE на сервере (карточка 1б, шаг 1): строка на переход состояния и на выброс — время, id ICE, состояние, awareness, alert,
## расстояние до игрока. Без строки на кадр. Узел без Моста; мозг ICE шагаем руками, как это делает IceNode.

static var _next_port := 18591
const SESSION := "s_fake000000000001"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _lines: Array[String] = []


func before_test() -> void:
	_root = Node.new()
	_root.name = "JournalRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	cfg.token = "t03:token-t03"
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new({}))).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.start(_server, null)
	_lines = []
	_node.ice_logged.connect(func(l: String) -> void: _lines.append(l))


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


## Игрок стоит в 3 м перед ICE (тот смотрит вдоль -Z): шагаем мозг до выброса или limit секунд.
func _watch_until_eject(limit: float) -> float:
	var ice: IceNode = _node.ices()[0]
	ice.brain.facing = Vector3.FORWARD  # маршрут идёт вдоль X; игрок стоит строго по взгляду
	ice.targets = {SESSION: ice.brain.position + Vector3(0, 0, -3)}
	var t := 0.0
	while t < limit and not _lines.any(func(l: String) -> bool: return "ВЫБРОС" in l):
		t += 0.1
		ice.brain.step(t, ice.targets, {})
	return t


func test_journal_has_a_line_per_transition_and_eject() -> void:
	_watch_until_eject(30.0)
	assert_bool(_lines.size() >= 3).is_true()
	assert_bool("PATROL→SUSPICIOUS" in _lines[0]).is_true()
	assert_bool("ice_1" in _lines[0]).is_true()
	assert_bool(_lines.any(func(l: String) -> bool: return "SUSPICIOUS→SEARCH" in l and "aw=1.00" in l)).is_true()
	assert_bool("ВЫБРОС caught" in _lines[_lines.size() - 1]).is_true()


func test_journal_line_has_time_alert_distance_and_session() -> void:
	_watch_until_eject(30.0)
	var first := _lines[0]
	for part in ["[ice] t=", "alert=0.00", "d=3.0", SESSION]:
		assert_bool(part in first).is_true()
	# в строке выброса расстояние уже печатается, а awareness нет (мозг сброшен выбросом)
	var last := _lines[_lines.size() - 1]
	assert_bool("d=" in last and not "aw=" in last).is_true()


func test_journal_is_silent_without_transitions() -> void:
	var ice: IceNode = _node.ices()[0]
	for i in 100:
		ice.brain.step(0.1 * (i + 1), {}, {})  # никого в узле: патруль, ни одной строки
	assert_array(_lines).is_empty()

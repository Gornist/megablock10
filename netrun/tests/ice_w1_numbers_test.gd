extends GdUnitTestSuite
## W1-Ч1, приёмка «на плоском стенде» без очков: ICE с числами из настоящего graph.json (тир узла) против нетраннера на модели
## IceBrain — без сцены и сети, шаг 0,1 с, как у IceNode. Неподвижного игрока на виду ICE ловит не мгновенно, ушедшего из конуса
## за несколько секунд — не ловит. Числа времени печатаются в журнал (строки «[w1-замер]»).

const STEP := 0.1

var _ejects: Array = []
var _eject_t := -1.0


func before_test() -> void:
	_ejects = []
	_eject_t = -1.0


## Мозг ICE с числами узла из graph.json: общие (graph.settings["ice"], в графе пусто) и ice_settings узла поверх умолчаний.
func _brain_of(node_id: String) -> IceBrain:
	var g := NodeGraph.load_file()
	var s: Dictionary = {}
	if g.settings.get("ice") is Dictionary:
		s.merge(g.settings["ice"], true)
	s.merge(g.nodes[node_id].get("ice_settings", {}), true)
	var b := IceBrain.new(s)  # ICE в нуле, смотрит вдоль -Z
	b.ejected.connect(func(session: String, reason: String) -> void: _ejects.append([session, reason]))
	return b


func _meter() -> TraceMeter:
	var g := NodeGraph.load_file()
	var m := TraceMeter.new(g.settings["trace"])
	m.reset(0.0)
	return m


## Игрок стоит на месте at до limit секунд. Возвращает время поимки (с) или -1.
func _catch_time(b: IceBrain, at: Vector3, limit: float) -> float:
	var t := 0.0
	var meters := {"p": _meter()}
	while t < limit:
		t += STEP
		b.step(t, {} if not _ejects.is_empty() else {"p": at}, meters)
		if not _ejects.is_empty():
			_eject_t = t
			return t
	return -1.0


func test_still_player_in_view_is_caught_not_before_about_ten_seconds() -> void:
	var rows: Array[String] = []
	var cases := [["node_01", 3.0], ["node_01", 4.0], ["node_01", 5.0], ["node_01", 5.9], ["node_05", 5.0], ["node_05", 7.9]]
	for c in cases:
		_ejects = []
		var b := _brain_of(c[0])
		var t := _catch_time(b, Vector3(0, 0, -float(c[1])), 30.0)
		rows.append("%s на %.1f м: %.1f с" % [c[0], c[1], t])
		assert_array(_ejects).is_equal([["p", "caught"]])
		# внимание 0,15/с: до поиска ≥ 6,7 с; плюс дорога до игрока (бег 1,5 м/с) — не мгновенно, как было (~2 с)
		assert_float(t).is_greater_equal(7.5)
	print("[w1-замер] BASE notice=0.15 chase=1.5 sight=6, HARD sight=8. Поимка неподвижного: ", "; ".join(rows))


func test_player_leaving_the_cone_after_five_seconds_is_not_caught() -> void:
	var b := _brain_of("node_01")
	var meter := _meter()
	var meters := {"p": meter}
	var t := 0.0
	while t < 5.0 - 0.0001:  # 5 с на виду на 5 м
		t += STEP
		b.step(t, {"p": Vector3(0, 0, -5)}, meters)
	assert_int(b.state()).is_equal(IceBrain.State.SUSPICIOUS)  # ещё не поиск
	var aware := b.awareness()
	var trace_seen := meter.value()
	while t < 25.0 - 0.0001:  # ушёл за спину ICE
		t += STEP
		b.step(t, {"p": Vector3(0, 0, 5)}, meters)
	assert_array(_ejects).is_empty()
	assert_int(b.state()).is_equal(IceBrain.State.PATROL)
	assert_float(trace_seen).is_less(25.0)  # 5 с на виду < «подозрительно» (25): вес seen_by_ice 2
	print("[w1-замер] 5 с на виду на 5 м: осведомлённость %.2f, trace %.1f; ушёл из конуса — не поймали, ICE снова на патруле" % [aware, trace_seen])


## Black ICE видит теми же числами, что и обычный ICE узла, поэтому смягчение NIGHTMARE-узлов его бы ослабило: graph.json фиксирует его зрение и скорость прежними (умолчания ICE).
func test_black_ice_keeps_the_old_perception_numbers() -> void:
	var g := NodeGraph.load_file()
	var b: Dictionary = g.settings.get("black_ice", {})
	assert_float(float(b.get("sight_range", -1.0))).is_equal(IceBrain.DEFAULT_SETTINGS["sight_range"])
	assert_float(float(b.get("notice_per_sec", -1.0))).is_equal(IceBrain.DEFAULT_SETTINGS["notice_per_sec"])
	assert_float(float(b.get("chase_speed", -1.0))).is_equal(IceBrain.DEFAULT_SETTINGS["chase_speed"])


## Карточка 1б, шаг 2: «!» не ловит сразу — graph.json даёт тревогу 2 с и касание с 1 м; Black ICE ловит как прежде (охота, а не тревога).
func test_graph_gives_soft_ice_an_alarm_and_black_ice_keeps_old_catch() -> void:
	var g := NodeGraph.load_file()
	assert_float(float(g.settings["ice"]["catch_grace_sec"])).is_equal(2.0)
	assert_float(float(g.settings["ice"]["catch_range"])).is_equal(1.0)
	assert_float(float(g.settings["black_ice"]["catch_grace_sec"])).is_equal(0.0)
	assert_float(float(g.settings["black_ice"]["catch_range"])).is_equal(IceBrain.DEFAULT_SETTINGS["catch_range"])

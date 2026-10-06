extends GdUnitTestSuite
## Прицел телепорта в тактовом режиме: цвет рамки по прогнозу (зелёный / жёлтый / красный), «ХОД ПРИНЯТ», «ЖДАТЬ · ОКНО ЧЕРЕЗ N»,
## залипание красной (0,4 с), отказ сервера «moved», прыжок без клиентской перезарядки. Без tk (realtime) — всё как раньше.
## Ввод подаётся прямо в XRRig.drive; кадр — 1/72 с.

const DT := 1.0 / 72.0
var _attempts: Array = []


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	_attempts = []
	scene.rig.teleport_attempted.connect(func(from: Vector3, to: Vector3, ok: bool, reason: String):
		_attempts.append({"from": from, "to": to, "ok": ok, "reason": reason}))
	return scene


func _frames(rig: XRRig, n: int, stick: Vector2 = Vector2.ZERO) -> void:
	for i in n:
		rig.drive(0.0, stick, false, DT)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Снимок тактового узла: ICE по списку намерений, tk с номером такта n.
func _feed(scene: Node3D, intents: Array, n: int = 1, mv: int = 0, at_ago: float = 1.0) -> void:
	var now := _now()
	var ice: Array = []
	for i in intents.size():
		var it: Dictionary = intents[i]
		var c: Vector2i = it["c"]
		var p := NodeGrid.center(c)
		ice.append({"id": "ice_%d" % i, "p": [p.x, 0.0, p.z], "f": [float(it["d"].x), float(it["d"].y)], "s": 0, "b": 0,
			"c": [c.x, c.y], "d": [it["d"].x, it["d"].y], "st": it.get("st", 0), "nc": [it["nc"].x, it["nc"].y], "nd": [it["d"].x, it["d"].y], "aw": 0, "sc": 6})
	scene.remote.on_state({"k": now, "ice": ice, "tk": {"n": n, "at": now - at_ago, "win": 5.0, "inh": 0, "mv": mv}}, now)


## ICE, смотрящий в клетку `target` в упор (красная), и ICE далеко (зелёная).
func _red_intent(target: Vector2i) -> Dictionary:
	return {"c": target + Vector2i(1, 0), "d": Vector2i(-1, 0), "st": 0, "nc": target + Vector2i(1, 0)}


## Намерение, при котором клетка `target` на периферии (ищем по соседям в сетке риг-а).
func _yellow_intent(grid: NodeGrid, target: Vector2i) -> Dictionary:
	for dx in range(-5, 6):
		for dy in range(-5, 6):
			var c := target + Vector2i(dx, dy)
			if not NodeGrid.in_bounds(c) or grid.is_occupied(c):
				continue
			for d: Vector2i in NodeGrid.DIRS8:
				var it := {"c": c, "d": d, "st": 0, "nc": c, "nd": d, "sc": 6.0}
				if TickForecast.threat(grid, [it], target) == TickForecast.YELLOW:
					return it
	return {}


## Прицелиться вперёд (стик держим) и вернуть клетку под рамкой.
func _aim_cell(rig: XRRig) -> Vector2i:
	_frames(rig, 3, Vector2(0, 1))
	return NodeGrid.cell_of(rig.aim_target())


func test_рамка_зелёная_когда_ICE_далеко() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	var target := _aim_cell(rig)
	_feed(scene, [{"c": Vector2i(0, 0), "d": Vector2i(1, 0), "st": 0, "nc": Vector2i(0, 0)}])
	_frames(rig, 2, Vector2(0, 1))
	assert_str(rig.aim_visual.kind()).is_equal("hop")
	assert_int(rig.last_threat()).is_equal(TickForecast.GREEN)
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.OK_COLOR)
	assert_bool(target == Vector2i(0, 0)).is_false()


func test_рамка_красная_в_фокусе_ICE() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	var target := _aim_cell(rig)
	_feed(scene, [_red_intent(target)])
	_frames(rig, 2, Vector2(0, 1))
	assert_int(rig.last_threat()).is_equal(TickForecast.RED)
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.NO_COLOR)


func test_рамка_жёлтая_на_периферии() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	var target := _aim_cell(rig)
	var it := _yellow_intent(rig.grid, target)
	assert_bool(it.is_empty()).is_false()
	_feed(scene, [it])
	_frames(rig, 2, Vector2(0, 1))
	assert_int(rig.last_threat()).is_equal(TickForecast.YELLOW)
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.WARN_COLOR)
	assert_bool(rig.aim_visual.label_visible()).is_false()


func test_ход_принят_нейтральная_рамка_метка_и_отказ_без_запроса() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	_aim_cell(rig)
	_feed(scene, [], 3, 1)   # mv = 1
	_frames(rig, 2, Vector2(0, 1))
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.WAIT_COLOR)
	assert_bool(rig.aim_visual.label_visible()).is_true()
	assert_str(rig.aim_visual.label_text()).is_equal("ХОД ПРИНЯТ")
	assert_bool(rig.aim_visual.is_ok()).is_false()
	_frames(rig, 40)   # отпустили
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_false()
	assert_str(_attempts[0]["reason"]).is_equal(WorldMsg.REASON_MOVED)
	assert_float(rig.global_position.distance_to(NodeLayout.SPAWN)).is_less(0.01)   # не сдвинулись


func test_ждать_на_своей_клетке_метка_с_секундами_и_запрос_центра_клетки() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	rig.global_position = NodeGrid.center(Vector2i(2, 12))
	rig.teleport_range = 0.2
	_feed(scene, [], 5, 0, 1.0)   # такт был секунду назад, окно 5 с: до такта 4
	_frames(rig, 3, Vector2(0, 1))
	assert_str(rig.aim_visual.kind()).is_equal("wait")
	assert_str(rig.aim_visual.label_text()).is_equal("ЖДАТЬ · ОКНО ЧЕРЕЗ 4")
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.WAIT_COLOR)
	_frames(rig, 40)
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_true()
	assert_str(_attempts[0]["reason"]).is_equal("wait")
	assert_vector(rig.last_pick()).is_equal(Vector3(NodeGrid.center(Vector2i(2, 12)).x, rig.global_position.y, NodeGrid.center(Vector2i(2, 12)).z))
	assert_float(rig.global_position.distance_to(NodeGrid.center(Vector2i(2, 12)))).is_less(0.01)   # риг на месте


func test_красная_залипает_быстрый_отпуск_отмена_без_запроса() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	var target := _aim_cell(rig)
	_feed(scene, [_red_intent(target)])
	_frames(rig, 1, Vector2(0, 1))
	assert_float(rig.aim_hold_sec()).is_less(TickForecast.RED_HOLD_SEC)
	_frames(rig, 40)   # отпустили сразу
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_false()
	assert_str(_attempts[0]["reason"]).is_equal("hold")


func test_красная_после_залипания_прыжок_уходит() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	var target := _aim_cell(rig)
	_feed(scene, [_red_intent(target)])
	_frames(rig, 40, Vector2(0, 1))   # 0,55 с на одной клетке
	assert_float(rig.aim_hold_sec()).is_greater_equal(TickForecast.RED_HOLD_SEC)
	_frames(rig, 40)
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_true()


func test_зелёная_и_жёлтая_без_залипания() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	_aim_cell(rig)
	_feed(scene, [{"c": Vector2i(0, 0), "d": Vector2i(1, 0), "st": 0, "nc": Vector2i(0, 0)}])
	_frames(rig, 1, Vector2(0, 1))
	_frames(rig, 40)
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_true()


func test_отказ_сервера_moved_рисует_ход_принят_до_следующего_такта() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	_feed(scene, [], 7, 0)
	rig.apply_teleport_denial(WorldMsg.REASON_MOVED, rig.global_position, 0.0)
	_frames(rig, 3, Vector2(0, 1))
	assert_str(rig.aim_visual.label_text()).is_equal("ХОД ПРИНЯТ")
	_feed(scene, [], 8, 0)   # такт прошёл
	_frames(rig, 2, Vector2(0, 1))
	assert_bool(rig.aim_visual.label_visible()).is_false()
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.OK_COLOR)


func test_без_перезарядки_на_клиенте_в_тактовом_режиме() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	_feed(scene, [{"c": Vector2i(0, 0), "d": Vector2i(1, 0), "st": 0, "nc": Vector2i(0, 0)}])
	_aim_cell(rig)
	_frames(rig, 40)
	assert_bool(_attempts[0]["ok"]).is_true()
	_frames(rig, 20)   # моргание кончилось
	_feed(scene, [{"c": Vector2i(0, 0), "d": Vector2i(1, 0), "st": 0, "nc": Vector2i(0, 0)}], 2, 0)
	_frames(rig, 3, Vector2(0, 1))
	assert_bool(rig.aim_visual.is_ok()).is_true()   # перезарядка секунды не держит: следующий ход решает сервер
	assert_bool(rig.aim_visual.is_ok() and rig.teleport_cooldown_left() > 0.0).is_true()   # а клиентская перезарядка при этом ещё «идёт»


func test_realtime_без_tk_прежний_вид() -> void:
	var scene := _scene()
	var rig: XRRig = scene.rig
	_aim_cell(rig)
	_frames(rig, 2, Vector2(0, 1))
	assert_int(rig.last_threat()).is_equal(-1)
	assert_object(rig.aim_visual.frame_color()).is_equal(TeleportAim.OK_COLOR)
	assert_bool(rig.aim_visual.label_visible()).is_false()


func test_show_at_цвета_по_прогнозу_и_подпись() -> void:
	var aim := TeleportAim.new()
	auto_free(aim)
	add_child(aim)
	var t := NodeGrid.center(Vector2i(4, 4))
	aim.show_at(Vector3(0, 1, 0), t, true, 1.0, "hop", "", 0)
	assert_object(aim.frame_color()).is_equal(TeleportAim.OK_COLOR)
	aim.show_at(Vector3(0, 1, 0), t, true, 1.0, "hop", "", 1)
	assert_object(aim.frame_color()).is_equal(TeleportAim.WARN_COLOR)
	aim.show_at(Vector3(0, 1, 0), t, true, 1.0, "hop", "", 2)
	assert_object(aim.frame_color()).is_equal(TeleportAim.NO_COLOR)
	aim.show_at(Vector3(0, 1, 0), t, false, 1.0, "hop", "", 0, "ХОД ПРИНЯТ")
	assert_object(aim.frame_color()).is_equal(TeleportAim.WAIT_COLOR)
	assert_str(aim.label_text()).is_equal("ХОД ПРИНЯТ")
	aim.show_at(Vector3(0, 1, 0), t, false, 1.0, "denied", "occupied", -1, "ХОД ПРИНЯТ")
	assert_object(aim.frame_color()).is_equal(TeleportAim.DENIED_COLOR)
	assert_str(aim.label_text()).is_equal("ЗАНЯТО")

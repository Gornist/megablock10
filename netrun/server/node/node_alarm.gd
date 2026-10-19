class_name NodeAlarm
extends RefCounted
## Тревога узла и локдаун на сервере мира (ice.md §4). Вынесено из GrayNode (рефакторинг, поведение то же): шкала 0…100, уровни 0…4 и их эффекты
## (датчики, зрение ICE, Black ICE, запасные Стражи из будок, закрытие порталов), остывание в пустом узле, локдаун (сервера мира и Моста).
## Держит ссылку на узел (как LayoutDevices): сессии, часы, ICE, события и запись узла остаются там — здесь только состояние тревоги и её правила.
## Публичные имена GrayNode (raise_alarm, alarm_event, lock_for, is_locked_down …) — тонкие делегаты сюда.

var node: GrayNode
var alarm := 0.0                    # тревога узла 0…100: растёт от присутствия нетраннера (за такт) и событий, остывает только в пустом узле
var alarm_level := 0                # уровень 0…4 (alarm_level_for)
var sensors_armed := false          # уровень ≥ 1: «спящие» датчики раскладки включены (флаг)
var lockdown_until := 0             # конец локдауна узла (мс Unix, время Моста; 0 — нет) — из документа node
var local_lock_until := 0.0         # локдаун узла от сервера мира (время узла), когда Моста нет
var lockdown_ticks_left := -1       # тактов до закрытия порталов (уровень 4); −1 — отсчёт не идёт
var alert_t := 0.0                  # время узла последнего шага остывания
var reserve_out: Array[IceNode] = []   # запасные Стражи, вышедшие из будок на тревоге 2 (раскладка: reserves); пусто — будки закрыты


func _init(owner_node: GrayNode) -> void:
	node = owner_node


## Уровень тревоги 0…4 по значению шкалы 0…100 (ice.md §4: 25 / 50 / 75 / 100).
static func level_for(value: float) -> int:
	return AlarmLevels.level_for(value)   # пороги общие с клиентом (shared/alarm_levels.gd)


## Тревога из прошлого процесса: остывала по alert_cool_sec с момента записи (alert_at, мс Unix), пока сервера мира не было.
func restore(saved_world: Dictionary) -> void:
	var a := float(saved_world.get("alert", 0.0))
	if a <= 0.0 or not saved_world.has("alert_at"):
		return
	var elapsed := maxf(Time.get_unix_time_from_system() - float(saved_world["alert_at"]) / 1000.0, 0.0)
	# сервера мира не было — в узле никого не было: остывание по alert_cool_sec_per_point секунд за пункт шкалы 0…100
	alarm = clampf(a * GrayNode.ALARM_MAX - elapsed / maxf(float(node.settings["alert_cool_sec_per_point"]), 0.001), 0.0, GrayNode.ALARM_MAX)
	apply()


## Тревога растёт на points пунктов шкалы 0…100; событие и запись узла — когда целое значение или уровень изменились.
func raise_points(points: float) -> void:
	if points <= 0.0:
		return
	change(minf(alarm + points, GrayNode.ALARM_MAX))


## Событие из alert_events (поиск, выброс, FAIL, датчик, барьер, Трассировщик); только в узле графа.
func on_event(event_name: String) -> void:
	raise_points(float((node.settings.get("alert_events", {}) as Dictionary).get(event_name, 0.0)))


func change(new_value: float) -> void:
	var before := alarm
	alarm = clampf(new_value, 0.0, GrayNode.ALARM_MAX)
	if alarm == before:
		return
	var level_before := alarm_level
	apply()
	if snappedf(alarm, 1.0) != snappedf(before, 1.0) or alarm_level != level_before:
		node.event.emit({"kind": "alert", "node": node.node_id, "value": alarm / GrayNode.ALARM_MAX})
		node._write_node_state()  # тревога переживает рестарт сервера мира (node.data.world.alert + alert_at)


## Запасные Стражи (ice.md §4, «тревога 2»; решение владельца 16.10): на тревоге ≥ 2 из будок раскладки выходят запасные — один раз за забег узла, по маршруту записи
## `kind: reserve` (первая точка — клетка будки). Падение тревоги ниже 2 их не убирает; уходят, когда узел остыл до нуля (alarm == 0) — следующий забег снова с будкой.
func reserve_sync(level: int) -> void:
	if node.layout == null or node.layout.reserves.is_empty():
		return
	if level >= 2 and reserve_out.is_empty():
		for rd: Dictionary in node.layout.reserves:
			node._add_layout_sentry(rd)
			reserve_out.append(node._ices.back())
			print("[reserve] %s вышел из будки tick=%d" % [str(rd["id"]), node.tick_clock.tick_no])
		node.event.emit({"kind": "reserve_out", "node": node.node_id})
	elif alarm <= 0.0 and not reserve_out.is_empty():
		for ice in reserve_out:
			node._ices.erase(ice)
			node._tick_ices.erase(ice)
			node._intents.erase(ice)
			node.remove_child(ice)   # сразу из дерева: queue_free убирает позже, и имя запасного занято, когда он выходит снова
			ice.queue_free()
		reserve_out.clear()
		print("[reserve] остыл до нуля: запасные ушли в будки")


## Будки запасных Стражей для state (поле `bo`): [{id, c: [x, z] клетка 1 м, open 0/1 — запасной вышел (створка сдвинута)}].
func booth_view() -> Array:
	var out: Array = []
	if node.layout == null:
		return out
	for i in node.layout.booths.size():
		var c: Vector2i = node.layout.booths[i]
		out.append({"id": "b%d" % (i + 1), "c": [c.x, c.y], "open": 0 if reserve_out.is_empty() else 1})
	return out


## Уровни тревоги и их эффекты (ice.md §4), прежний множитель внимания непошаговых ICE по alert.
func apply() -> void:
	var k := 1.0 + alarm / GrayNode.ALARM_MAX * float(node.settings["alert_boost"])
	var level := level_for(alarm)
	var changed := level != alarm_level
	alarm_level = level
	sensors_armed = level >= 1   # «спящие» датчики раскладки включены (самих датчиков пока нет — только флаг)
	reserve_sync(level)   # до цикла по ICE: вышедший запасной сразу получает бонус зрения ниже
	for ice in node._ices:
		if ice.brain != null:
			ice.brain.alert_scale = k
		if node._tick_ices.has(ice):
			(node._tick_ices[ice] as TickIce).set_sight_bonus(GrayNode.ALARM_SIGHT_BONUS if level >= 2 else 0.0)   # уровень 2: зрение всех ICE +1 клетка карты
	node.devices.set_sight_bonus(GrayNode.ALARM_SIGHT_BONUS if level >= 2 else 0.0)   # и Маяков: 5 клеток карты (10 м), на тревоге 2+ — 6 (12 м)
	if not changed:
		return
	node.log_line("alarm.level", {"node": node.node_id, "level": level, "alarm": snappedf(alarm, 1.0)})   # разбор забегов (p9_report.sh): уровня тревоги в журнале сервера иначе нет
	node.event.emit({"kind": "alarm_level", "node": node.node_id, "level": level})
	send_level(level)
	if level >= 4:
		if lockdown_ticks_left == -1:
			lockdown_ticks_left = int(node.settings.get("alert_lockdown_ticks", 10))
	else:
		lockdown_ticks_left = -1   # тревога упала ниже 100 до закрытия (или после него): отсчёт сброшен, закрытие не повторяется


## Уровень тревоги сменился — сказать нетраннерам узла (клиент: вид тревоги, аккорд уровня, строка деки). Т3b.
func send_level(level: int) -> void:
	var fields := {"kind": WorldMsg.EV_ALARM, "node": node.node_id, "level": level, "alarm": snappedf(alarm, 1.0)}
	for session in node._live_sessions():
		node.net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, fields))


## Есть ли в узле нетраннер (сессия узла с аватаром; в тоннеле между узлами — нет).
func occupied() -> bool:
	for s in node._sessions.keys():
		if node.net.node_of(s) == node.node_id and node.net.has_avatar(s):
			return true
	return false


## Такт сервера: тревога растёт от присутствия нетраннера и ведёт отсчёт до закрытия порталов (тактовый узел).
func on_tick() -> void:
	if not node.is_graph_node():
		return
	if occupied():
		raise_points(float(node.settings["alert_per_tick"]))
	if lockdown_ticks_left > 0:
		lockdown_ticks_left -= 1
		if lockdown_ticks_left == 0:
			lock_for(float(node.settings["lockdown_sec"]))
			lockdown_ticks_left = -2   # закрытие уже сработало: до падения ниже уровня 4 не повторять


## По общим часам: остывание — только в пустом узле, −1 за alert_cool_sec_per_point секунд (рост и закрытие считают такты).
func cool_tick() -> void:
	var dt := node._now - alert_t
	alert_t = node._now
	if dt <= 0.0 or not node.is_graph_node():
		return
	if not occupied() and alarm > 0.0:
		change(alarm - dt / maxf(float(node.settings["alert_cool_sec_per_point"]), 0.001))


## Закрыть узел сервером мира на sec секунд (когда Моста нет; с Мостом локдаун — lockdown_until узла).
func lock_for(sec: float) -> void:
	local_lock_until = maxf(local_lock_until, node._now + sec)
	node.event.emit({"kind": "lockdown", "node": node.node_id, "sec": sec})


## Сколько секунд узел ещё закрыт (0 — открыт): большее из локдауна сервера мира и lockdown_until Моста (мс Unix).
func lockdown_left_sec() -> float:
	var left := maxf(local_lock_until - node._now, 0.0)
	var ms := lockdown_until - int(Time.get_unix_time_from_system() * 1000.0)
	if ms > 0:
		left = maxf(left, ms / 1000.0)
	return left


func is_locked_down() -> bool:
	return lockdown_left_sec() > 0.0

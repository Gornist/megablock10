class_name LayoutDevices
extends RefCounted
## Устройства раскладки узла на сервере: Маяки, Датчики, Барьеры (тактовый режим; ice.md §5). Вынесено из GrayNode (рефакторинг, поведение то же):
## узел создаёт их из раскладки в `start()`, шагает на такте, рассылает в state (поля `bk`, `sn`, `sf`, `br`) и вскрывает барьеры. Держит ссылку на узел
## (как VaultBreach / ChargeBreach): сессии, часы тактов, сетка, тревога, trace и события остаются там — здесь только состояние устройств и их правила.
## Публичные имена GrayNode (sensor_view, barrier_closed, beacons …) — тонкие делегаты сюда.

var node: GrayNode
var beacons: Array[TickBeacon] = []   # Маяки раскладки: вращаются каждый такт, без IceNode
var beacon_ids: Dictionary = {}       # TickBeacon -> id маяка из раскладки (журнал, state)
var sensors: Array[TickSensor] = []   # Датчики раскладки: луч, вкл/выкл по тиру
var sensor_ids: Dictionary = {}       # TickSensor -> id датчика из раскладки
var sensor_hit: Dictionary = {}       # TickSensor -> {сессия: true}: уже сработал на неё в этом включении (повторно — после выключения)
var sensor_fired: Dictionary = {}     # сессия -> [{id, a}]: срабатывания, о которых игроку ещё не сказали (поле `sf` ближайшего state)
var barriers: Array = []              # Барьеры раскладки: {id, cells: Array[Vector2i], open: bool}; закрытый занимает клетки ice_grid


func _init(owner_node: GrayNode) -> void:
	node = owner_node


## Собрать устройства из раскладки узла (не legacy). Клетки барьеров уже заняты в ice_grid (блок «B»).
func build(layout: LayoutData, tier: String) -> void:
	for bd: Dictionary in layout.beacons:   # Маяки раскладки: отдельный вид Soft ICE — стоят на тумбе и вращаются
		var tb := TickBeacon.new(bd["cell"], bd["start"], node.ice_grid, {"step_deg": bd["step_deg"], "sweep_steps": bd["sweep_steps"]})
		beacons.append(tb)
		beacon_ids[tb] = str(bd["id"])
	var program := TickSensor.program_of(tier)   # вкл/выкл по тиру узла; раскладка может задать свои числа
	for sd: Dictionary in layout.sensors:
		var ts := TickSensor.for_layout(sd, program)   # старт в фазе «выключен»: вход в узел не застаёт луч включённым (П6-4)
		sensors.append(ts)
		sensor_ids[ts] = str(sd["id"])
	for kd: Dictionary in layout.barriers:
		barriers.append({"id": str(kd["id"]), "cells": kd["cells"], "open": false})


## Маяки на такте: поворот, зрение только фокусом; «Поиск» маяка — как Поиск Стража (trace +10 цели, тревога узла +10).
func beacons_tick(pos: Dictionary, hidden: Dictionary, immune: Dictionary, suspicious: Dictionary) -> void:
	for tb: TickBeacon in beacons:
		for bev: Dictionary in tb.tick(pos, hidden, immune, suspicious):
			if str(bev["kind"]) == "search_started":
				var seen_by := str(bev.get("session", ""))
				print("[beacon] %s SEARCH_STARTED %s" % [beacon_ids.get(tb, "?"), seen_by])
				if seen_by != "":
					node.add_trace_event(seen_by, "search")
				node.alarm_event("search")


## Прибавка к зрению всех Маяков (тревога 2+).
func set_sight_bonus(bonus: float) -> void:
	for tb: TickBeacon in beacons:
		tb.set_sight_bonus(bonus)


## Датчики на такте: цикл вперёд, затем те, кто стоит под включённым лучом (скрытые и неуязвимые — нет: Призрак обходит датчик).
func sensors_tick(pos: Dictionary, hidden: Dictionary, immune: Dictionary) -> void:
	for ts: TickSensor in sensors:
		ts.tick()
		if not ts.is_on():
			sensor_hit.erase(ts)
			continue
		var standing := {}
		for s in pos:
			if not hidden.get(s, false) and not immune.get(s, false):
				standing[s] = pos[s]
		var hits := ts.hit_by(standing)
		for s in hits:
			sensor_fire(ts, str(s), hits[s])


## Прыжок игрока: отрезок пересекает включённый луч — «луч видит перенос». Скрытый (Призрак, вход) и неуязвимый невидимы датчику.
func sensors_hop(session: String, from: Vector3, to: Vector3) -> void:
	if sensors.is_empty() or not node._sessions.has(session):
		return
	var n := node.tick_clock.tick_no
	var ds: DaemonSession = node._sessions[session]
	if ds.is_ghost(node._now) or n - int(node._entered_tick.get(session, -1000000)) <= int(node.settings.get("entry_hidden_ticks", 2)) or node._arrival_immune(session, n):
		return
	for ts: TickSensor in sensors:
		var c := ts.crossed_by(from, to)
		if c != Vector2i.MAX:
			sensor_fire(ts, session, c)


## Сработал датчик: trace +5, тревога узла +5, ближайший Страж — в Проверку к клетке (раз за включение на сессию).
func sensor_fire(ts: TickSensor, session: String, cell: Vector2i) -> void:
	var fired: Dictionary = sensor_hit.get(ts, {})
	if fired.has(session):
		return
	fired[session] = true
	sensor_hit[ts] = fired
	print("[sensor] %s TRIGGERED %s cell=%d,%d" % [sensor_ids.get(ts, "?"), session, cell.x, cell.y])
	var pending: Array = sensor_fired.get(session, [])
	pending.append({"id": str(sensor_ids.get(ts, "")), "a": sensor_alarm()})
	sensor_fired[session] = pending
	node.add_trace_event(session, "sensor")
	node.alarm_event("sensor")
	var nearest: TickIce = null
	var best := INF
	var at := NodeGrid.center(cell)
	for ice: IceNode in node._tick_ices:
		var d := Vector2(ice.position.x - at.x, ice.position.z - at.z).length()
		if d < best:
			best = d
			nearest = node._tick_ices[ice]
	if nearest != null:
		nearest.investigate(session, cell)


## Датчики узла для state (поле `sn`): [{id, c: [[x, z], …] клетки луча, on 0/1, bl 1 — мигает перед включением, l — тактов до смены}].
func sensor_view() -> Array:
	var out: Array = []
	for ts: TickSensor in sensors:
		var it := ts.intent()
		var cells: Array = []
		for c: Vector2i in it["cells"]:
			cells.append([c.x, c.y])
		out.append({"id": str(sensor_ids.get(ts, "")), "c": cells, "on": 1 if it["on"] else 0, "bl": 1 if it["blink"] else 0, "l": int(it["left"]), "al": sensor_alarm()})
	return out


## Сколько тревоги даёт срабатывание Датчика (`alert_events.sensor` узла): клиент пишет «ЛУЧ → ТРЕВОГА +5» на прицеле до прыжка.
func sensor_alarm() -> int:
	return int((node.settings.get("alert_events", {}) as Dictionary).get("sensor", 0.0))


## Срабатывания Датчика на эту сессию с прошлого вызова (и сразу забыть): [{id, a}] — для поля `sf` state. Пусто — ничего не срабатывало.
func take_sensor_fired(session: String) -> Array:
	var out: Array = sensor_fired.get(session, [])
	sensor_fired.erase(session)
	return out


## Барьеры узла для state (поле `br`): [{id, c: [[x, z], …] клетки блока, open 0/1}].
func barrier_view() -> Array:
	var out: Array = []
	for b: Dictionary in barriers:
		var cells: Array = []
		for c: Vector2i in b["cells"]:
			cells.append([c.x, c.y])
		out.append({"id": b["id"], "c": cells, "open": 1 if b["open"] else 0})
	return out


## Закрыт ли барьер (нет такого — false).
func barrier_closed(id: String) -> bool:
	for b: Dictionary in barriers:
		if b["id"] == id:
			return not bool(b["open"])
	return false


## Вскрыть барьер (ice.md §5). how: "charge" — мини-игра заряда (панель), «force» — силой (2 такта курка): trace +10 и тревога +10 на сессию,
## "pick" — Отмычка, тихо. Клетки блока освобождаются в сетке узла — через них можно прыгать и ходят ICE. Возвращает false, если такого барьера
## нет или он уже открыт. Ввод (мини-игра, удержание курка) — не здесь: узел принимает уже готовое решение.
func open_barrier(id: String, how: String, session: String = "") -> bool:
	for b: Dictionary in barriers:
		if b["id"] != id:
			continue
		if bool(b["open"]):
			return false
		b["open"] = true
		for c: Vector2i in b["cells"]:
			node.ice_grid.occ.erase(c)
		if how == "force":
			if session != "":
				node.add_trace_event(session, "barrier")
			node.alarm_event("barrier")
		node.event.emit({"kind": "barrier_open", "node": node.node_id, "barrier": id, "how": how, "session": session})
		return true
	return false


## Барьер с таким id есть в узле (открытый или закрытый).
func has_barrier(id: String) -> bool:
	for b: Dictionary in barriers:
		if b["id"] == id:
			return true
	return false


## Клетка `cell` — соседняя (по восьми направлениям) с блоком барьера и сама свободна: оттуда барьер вскрывают.
func barrier_adjacent(id: String, cell: Vector2i) -> bool:
	for b: Dictionary in barriers:
		if b["id"] != id:
			continue
		for c: Vector2i in b["cells"]:
			if maxi(absi(c.x - cell.x), absi(c.y - cell.y)) <= 1:
				return true
	return false


## Маяки узла для state (поле `bk`): [{id, c: [x, z], d: [dx, dz] — угол сейчас, nd — после следующего такта, aw 0..6, r — дальность, клеток}].
func beacon_view() -> Array:
	var out: Array = []
	for tb: TickBeacon in beacons:
		var it := tb.intent()
		var c: Vector2i = it["cell"]
		var d: Vector2i = it["dir"]
		var nd: Vector2i = it["next_dir"]
		out.append({"id": str(beacon_ids.get(tb, "")), "c": [c.x, c.y], "d": [d.x, d.y], "nd": [nd.x, nd.y], "aw": int(it["aware"]), "r": float(it["range"])})
	return out

class_name LayoutBots
extends RefCounted
## Боты раскладки (docs/gamedesign/levels.md, 8): детерминированные прогоны по тактам без сети и графики. Узел — те же TickIce, TickBeacon и
## TickSensor, что в игре; игрок — клетка и прыжки по NodeGrid (дальность REACH_M, один прыжок за такт).
##  • «патрульный» (windows) — окно у каждой площадки: наибольшая серия тактов цикла, когда клетку площадки не видит ни Страж, ни Маяк и не жжёт луч;
##  • «вор» (thief) — от входа до площадки хранилища, взлом `dwell` тактов, до выхода или портала; сколько тактов под взглядом при лучшем маршруте
##    (0 — путь без обнаружений есть) и сколько всего тактов; прогон с нескольких фаз цикла патруля (фаза 0 — первый вход в узел);
##  • «бегун» (runner) — нетраннера увидели у площадки: от первого Поиска он бежит кратчайшим путём к выходу или порталу; ушёл или взят.
## Модель вора: ICE не знает о нём (патруль идёт по маршруту), первые `ENTRY_HIDDEN_TICKS` тактов он скрыт. Прыжок через включённый луч Датчика
## считается обнаружением (ice.md §5). Legacy-раскладка не проверяется.

const ENTRY_HIDDEN_TICKS := 2
const THIEF_DWELL := 2       # тактов на площадке (взлом по тактам условный: в реальном времени он идёт мини-игрой)
const LEG_HORIZON := 90      # дольше этого не ждём на одном отрезке пути, тактов
const MAX_CYCLE := 720
const _NONE := 255

var layout: LayoutData
var tier := "BASE"
var grid: NodeGrid
var cycle := 1
var _skip := 0   # тактов «разгона» патруля до петли маршрута (в таблицу не входят)
var error := ""
var _cols := 16
var _exposed := PackedByteArray()   # [(t − 1) mod cycle] * cells + idx → 0/1 под взглядом или лучом
var _sensor_on: Array = []          # по датчикам: PackedByteArray по (t − 1) mod cycle
var _sensor_cells: Array = []       # по датчикам: Array[Vector2i]
var _reach: Dictionary = {}         # idx → Array[int] клеток, куда можно прыгнуть
var _cross: Dictionary = {}         # a * 100000 + b → Array[int] индексов датчиков, чей луч пересекает прыжок


func _init(l: LayoutData, tier_name: String = "BASE") -> void:
	layout = l
	tier = tier_name
	grid = l.grid()
	_cols = NodeGrid.cols()
	if l.is_legacy():
		return
	_build()


func _idx(c: Vector2i) -> int:
	return c.y * _cols + c.x


func _cell(i: int) -> Vector2i:
	return Vector2i(i % _cols, i / _cols)


static func _lcm(a: int, b: int) -> int:
	var x := a
	var y := b
	while y != 0:
		var t := y
		y = x % y
		x = t
	return a / x * b


## Период последовательности keys, начиная с такта 1 (сам ряд — состояния после 1, 2, … тактов).
static func _period(keys: Array, skip: int = 0) -> int:
	for p in range(1, (keys.size() - skip) / 2 + 1):
		var ok := true
		for i in range(skip, keys.size() - p):
			if keys[i] != keys[i + p]:
				ok = false
				break
		if ok:
			return p
	return 0


## Период с допуском на разгон: наименьший skip из SKIPS, с которого ряд периодичен. {skip, period}; period 0 — не нашёлся.
static func _period_skip(keys: Array) -> Dictionary:
	for skip in [0, 4, 8, 16, 32, 64]:
		var p := _period(keys, skip)
		if p > 0:
			return {"skip": skip, "period": p}
	return {"skip": 0, "period": 0}


func _program() -> Vector2i:
	return TickSensor.program_of(tier)


func _make_guards() -> Array[TickIce]:
	var out: Array[TickIce] = []
	for s: Dictionary in layout.sentries:
		out.append(TickIce.new({"sight_cells": layout.sight_cells}, s["route"], grid))
	return out


func _make_beacons() -> Array[TickBeacon]:
	var out: Array[TickBeacon] = []
	for b: Dictionary in layout.beacons:
		out.append(TickBeacon.new(b["cell"], b["start"], grid, {"step_deg": b["step_deg"], "sweep_steps": b["sweep_steps"]}))
	return out


func _make_sensors() -> Array[TickSensor]:
	var out: Array[TickSensor] = []
	var prog := _program()
	for sd: Dictionary in layout.sensors:
		out.append(TickSensor.new(sd["cells"], int(sd["on"]) if int(sd["on"]) > 0 else prog.x, int(sd["off"]) if int(sd["off"]) > 0 else prog.y, int(sd["phase"])))
	return out


## Цикл узла и таблица «под взглядом» на весь цикл.
func _build() -> void:
	# период: наименьший общий кратный периодов Стражей (по состояниям вместе), Маяков и Датчиков
	var probe := 4 * LayoutCheck.MAX_CYCLE
	var guards := _make_guards()
	var beacons := _make_beacons()
	var sensors := _make_sensors()
	var gkeys: Array = []
	var bkeys: Array = []
	for t in probe:
		var gk := ""
		for g in guards:
			g.tick({})
			gk += "%s%s;" % [str(g.cell()), str(g.dir())]
		gkeys.append(gk)
	for t in 64:
		var bk := ""
		for b in beacons:
			b.tick({})
			bk += str(b.dir())
		bkeys.append(bk)
	var c := 1
	if not guards.is_empty():
		var gps := _period_skip(gkeys)
		if int(gps["period"]) == 0:
			error = "цикл патруля не найден за %d тактов" % probe
			return
		_skip = int(gps["skip"])   # первые такты — «разгон» (старт не на петле маршрута): они в таблицу не входят
		c = _lcm(c, int(gps["period"]))
	if not beacons.is_empty():
		var bp := _period(bkeys)
		c = _lcm(c, maxi(bp, 1))
	for s in sensors:
		c = _lcm(c, s.program().x + s.program().y)
	if c > MAX_CYCLE:
		error = "общий цикл %d тактов длиннее %d" % [c, MAX_CYCLE]
		return
	cycle = c
	# таблица: заново, с такта _skip + 1 по _skip + cycle (разгон пропущен)
	guards = _make_guards()
	beacons = _make_beacons()
	sensors = _make_sensors()
	var rows := _skip + cycle   # такты разгона как есть, дальше один цикл
	var n := _cols * NodeGrid.rows()
	_exposed.resize(rows * n)
	_exposed.fill(0)
	_sensor_on.clear()
	_sensor_cells.clear()
	for s in sensors:
		var arr := PackedByteArray()
		arr.resize(rows)
		_sensor_on.append(arr)
		_sensor_cells.append(s.cells())
	var half := float(TickIce.DEFAULTS["half_angle_deg"])
	var focus := float(TickIce.DEFAULTS["focus_deg"])
	for t in rows:
		for g in guards:
			g.tick({})
		for b in beacons:
			b.tick({})
		for s in sensors:
			s.tick()
		for k in sensors.size():
			(_sensor_on[k] as PackedByteArray)[t] = 1 if sensors[k].is_on() else 0
		for i in n:
			var cc := _cell(i)
			if grid.is_occupied(cc):
				continue
			var seen := false
			for g in guards:
				if TickVision.classify(grid, g.cell(), g.dir(), cc, layout.sight_cells, half, focus) != TickVision.NONE:
					seen = true
					break
			if not seen:
				for b in beacons:
					if b.covers_cell(cc):
						seen = true
						break
			if not seen:
				for k in sensors.size():
					if (_sensor_on[k] as PackedByteArray)[t] == 1 and sensors[k].covers(cc):
						seen = true
						break
			if seen:
				_exposed[t * n + i] = 1


## Под взглядом или лучом клетка i в такт t (состояние после t тактов).
func exposed(t: int, i: int) -> bool:
	return _exposed[_ti(t) * _cols * NodeGrid.rows() + i] == 1


## Строка таблицы для такта t (состояние после t тактов).
func _ti(t: int) -> int:
	if t - 1 < _skip:
		return maxi(t - 1, 0)
	return _skip + posmod(t - 1 - _skip, cycle)


func _reach_of(i: int) -> Array:
	if not _reach.has(i):
		var out: Array = []
		for c in grid.reach_cells(_cell(i)):
			out.append(_idx(c))
		_reach[i] = out
	return _reach[i]


## Индексы датчиков, чей луч пересекает прыжок a → b (не зависит от времени).
func _crossed(a: int, b: int) -> Array:
	var key := a * 100000 + b
	if not _cross.has(key):
		var out: Array = []
		for k in _sensor_cells.size():
			var s := TickSensor.new(_sensor_cells[k], 1000, 1)   # всегда включён: здесь важна только геометрия
			if s.crossed_by(NodeGrid.center(_cell(a)), NodeGrid.center(_cell(b))) != Vector2i.MAX:
				out.append(k)
		_cross[key] = out
	return _cross[key]


# --- патрульный ---

## Окно клетки: наибольшая серия подряд тактов цикла (по кольцу), когда её не видят. −1 — раскладка не считается.
func window_of(c: Vector2i) -> int:
	if error != "" or layout.is_legacy():
		return -1
	var i := _idx(c)
	var best := 0
	var run := 0
	for t in range(_skip, _skip + cycle * 2):
		if exposed(t + 1, i):
			run = 0
		else:
			run += 1
			best = maxi(best, run)
	return mini(best, cycle)


# --- вор ---

## Один отрезок: от клетки `from` в такт t0 до любой клетки из targets (set индексов), `dwell` тактов стоит на ней. Минимум (обнаружений,
## тактов). {cost, ticks, path: Array[int]} или {} — не дошёл за LEG_HORIZON. Первые ENTRY_HIDDEN_TICKS тактов отсчёта скрыты (flag hidden).
func _leg(from: int, t0: int, targets: Dictionary, dwell: int, hidden_ticks: int) -> Dictionary:
	var n := _cols * NodeGrid.rows()
	var cur := {from: 0}
	var parents: Array = []
	var best := {}
	for k in LEG_HORIZON:
		var T := t0 + k
		var nxt := {}
		var par := {}
		for i: int in cur:
			var base: int = cur[i]
			var opts: Array = [i] + _reach_of(i)
			for j: int in opts:
				var cost := base
				if k + 1 > hidden_ticks:
					if exposed(T + 1, j):
						cost += 1
					if j != i:
						for s: int in _crossed(i, j):
							if (_sensor_on[s] as PackedByteArray)[_ti(T)] == 1:
								cost += 1
								break
				if not nxt.has(j) or cost < nxt[j]:
					nxt[j] = cost
					par[j] = i
		parents.append(par)
		cur = nxt
		for j: int in cur:
			if targets.has(j):
				var cost: int = cur[j]
				for d in dwell:
					if exposed(T + 2 + d, j):
						cost += 1
				if best.is_empty() or cost < best["cost"] or (cost == best["cost"] and k + 1 < best["ticks"]):
					var path: Array = [j]
					var node: int = j
					for layer in range(parents.size() - 1, -1, -1):
						node = parents[layer][node]
						path.push_front(node)
					best = {"cost": cost, "ticks": k + 1, "path": path}
		if not best.is_empty() and best["cost"] == 0:
			break
	if n == 0:
		return {}
	return best


func _exit_targets() -> Dictionary:
	var out := {}
	for ec: Vector3 in layout.exit_cells:
		for c in LayoutData.block_cells(LayoutData.block_of(NodeGrid.cell_of(ec))):
			if not grid.is_occupied(c):
				out[_idx(c)] = true
	for p: Vector3 in layout.portals:
		if p != Vector3.INF:
			out[_idx(NodeGrid.cell_of(p))] = true
	return out


## Вор от входа до площадки хранилища v и до выхода/портала с фазы `phase`. {ok_stealth, cost, ticks} или {} — путь не найден.
func thief_run(vault: Dictionary, phase: int) -> Dictionary:
	var start := _idx(NodeGrid.cell_of(layout.spawn))
	var pad := _idx(vault["pad1"])
	var a := _leg(start, phase, {pad: true}, THIEF_DWELL, ENTRY_HIDDEN_TICKS)
	if a.is_empty():
		return {}
	var t1 := phase + int(a["ticks"]) + THIEF_DWELL
	var b := _leg(pad, t1, _exit_targets(), 0, 0)
	if b.is_empty():
		return {}
	var path: Array = a["path"] + (b["path"] as Array).slice(1)
	return {"cost": int(a["cost"]) + int(b["cost"]), "ticks": int(a["ticks"]) + THIEF_DWELL + int(b["ticks"]), "path": path}


## Фазы, с которых запускаем воров: равномерно по циклу, первая — 0 (первый вход в узел).
func phases(count: int = 6) -> Array[int]:
	var out: Array[int] = []
	for k in mini(count, cycle):
		out.append(k * cycle / mini(count, cycle))
	return out


## Все воры по хранилищам: [{vault: Vector2i (cell1), ring, window, runs: [{phase, cost, ticks}], ok: сколько фаз без обнаружений}].
func thief_report(phase_count: int = 6) -> Array:
	var out: Array = []
	if error != "" or layout.is_legacy():
		return out
	for v: Dictionary in layout.vaults:
		var runs: Array = []
		var clean := 0
		for ph in phases(phase_count):
			var r := thief_run(v, ph)
			if r.is_empty():
				runs.append({"phase": ph, "cost": -1, "ticks": -1})
				continue
			runs.append({"phase": ph, "cost": r["cost"], "ticks": r["ticks"]})
			if int(r["cost"]) == 0:
				clean += 1
		out.append({"vault": v["cell1"], "ring": v["ring"], "window": window_of(v["pad1"]), "runs": runs, "clean": clean})
	return out


# --- бегун ---

## Кратчайший путь по прыжкам от a до ближайшей цели; пустой массив — нет. Без учёта ICE.
func _shortest(a: int, targets: Dictionary) -> Array:
	var prev := {a: -1}
	var queue: Array = [a]
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		if targets.has(i):
			var path: Array = []
			var node := i
			while node != -1:
				path.push_front(node)
				node = prev[node]
			return path
		for j: int in _reach_of(i):
			if not prev.has(j):
				prev[j] = i
				queue.append(j)
	return []


## Бегун у площадки vault: ICE идут `phase` тактов без игрока, затем он появляется на площадке и стоит, пока кто-то не войдёт в Поиск
## (не дольше max_wait тактов), потом бежит кратчайшим путём к выходу или порталу. {result: "no_search" | "escaped" | "caught", ticks}.
func runner_run(vault: Dictionary, phase: int, max_wait: int = 60) -> Dictionary:
	var guards := _make_guards()
	var beacons := _make_beacons()
	var sensors := _make_sensors()
	for t in phase:
		for g in guards:
			g.tick({})
		for b in beacons:
			b.tick({})
		for s in sensors:
			s.tick()
	var pad: int = _idx(vault["pad1"])
	var flee := _shortest(pad, _exit_targets())
	if flee.is_empty():
		return {"result": "caught", "ticks": 0}
	var at := pad
	var step := 0     # сколько прыжков побега уже сделано
	var fleeing := false
	var waited := 0
	var searching_seen := false
	for tick in max_wait + flee.size() + 4:
		var from_c := NodeGrid.center(_cell(at))
		# ход игрока: после Поиска — следующий прыжок побега
		if fleeing and step + 1 < flee.size():
			var nxt: int = flee[step + 1]
			for s in sensors:
				if s.crossed_by(from_c, NodeGrid.center(_cell(nxt))) != Vector2i.MAX:
					_wake_nearest(guards, "bot", s.cells()[0])
			step += 1
			at = nxt
		var pos := NodeGrid.center(_cell(at))
		var caught := false
		for g in guards:
			for ev: Dictionary in g.tick({"bot": pos}):
				if str(ev["kind"]) == "capture":
					caught = true
		for b in beacons:
			b.tick({"bot": pos})
		for s in sensors:
			s.tick()
			if s.is_on():
				for sc in s.cells():
					if sc == _cell(at):
						_wake_nearest(guards, "bot", sc)
		if caught:
			return {"result": "caught", "ticks": tick + 1}
		if fleeing and step >= flee.size() - 1:
			return {"result": "escaped", "ticks": tick + 1}
		if not fleeing:
			for g in guards:
				if g.state() == TickIce.Mode.SEARCH:
					fleeing = true
					searching_seen = true
			waited += 1
			if not fleeing and waited >= max_wait:
				return {"result": "no_search", "ticks": waited}
	return {"result": "caught" if searching_seen else "no_search", "ticks": max_wait}


func _wake_nearest(guards: Array[TickIce], session: String, cell: Vector2i) -> void:
	var best: TickIce = null
	var bd := INF
	for g in guards:
		var d := Vector2(g.cell() - cell).length()
		if d < bd:
			bd = d
			best = g
	if best != null:
		best.investigate(session, cell)


## Бегуны по хранилищам: [{vault, escaped, caught, no_search}] по фазам.
func runner_report(phase_count: int = 6) -> Array:
	var out: Array = []
	if error != "" or layout.is_legacy():
		return out
	for v: Dictionary in layout.vaults:
		var row := {"vault": v["cell1"], "escaped": 0, "caught": 0, "no_search": 0}
		for ph in phases(phase_count):
			row[str(runner_run(v, ph)["result"])] += 1
		out.append(row)
	return out


# --- проверки раскладки ---

## Периоды маршрутов Стражей: ни один не делит другой нацело (levels.md §2, п. 6). Один Страж — нормально.
static func check_periods(l: LayoutData) -> Dictionary:
	if l.sentries.size() < 2:
		return {"ok": true, "detail": "Стражей %d: периоды не сравниваются" % l.sentries.size()}
	var grid := l.grid()
	var periods: Array[int] = []
	for s: Dictionary in l.sentries:
		var g := TickIce.new({"sight_cells": l.sight_cells}, s["route"], grid)
		var keys: Array = []
		for t in 4 * LayoutCheck.MAX_CYCLE:
			g.tick({})
			keys.append("%s%s" % [str(g.cell()), str(g.dir())])
		periods.append(int(_period_skip(keys)["period"]))
	for i in periods.size():
		if periods[i] == 0:
			return {"ok": false, "detail": "период Стража %s не найден" % str(l.sentries[i]["id"])}
		for j in range(i + 1, periods.size()):
			if periods[i] % periods[j] == 0 or periods[j] % periods[i] == 0:
				return {"ok": false, "detail": "периоды %d и %d кратны (Стражи %s и %s)" % [periods[i], periods[j], str(l.sentries[i]["id"]), str(l.sentries[j]["id"])]}
	return {"ok": true, "detail": "периоды Стражей: %s" % str(periods)}


## К каждому хранилищу ≥ 2 непересекающихся пути по клеткам (шаг на 8 соседей, без общих промежуточных клеток) от входа (п. 3).
static func check_paths(l: LayoutData) -> Dictionary:
	if l.is_legacy() or l.vaults.is_empty():
		return {"ok": true, "detail": "legacy или без хранилищ"}
	var grid := l.grid()
	var src := NodeGrid.cell_of(l.spawn)
	var bad: Array[String] = []
	var worst := 99
	for v: Dictionary in l.vaults:
		var k := _disjoint_paths(grid, src, v["pad1"], 2)
		worst = mini(worst, k)
		if k < 2:
			bad.append("хранилище %s: путей %d" % [str(v["cell"]), k])
	if bad.is_empty():
		return {"ok": true, "detail": "к каждому хранилищу не меньше 2 путей"}
	return {"ok": false, "detail": "; ".join(bad)}


## Число непересекающихся по промежуточным клеткам путей (до limit) — поток с разбиением клеток на вход и выход.
static func _disjoint_paths(grid: NodeGrid, a: Vector2i, b: Vector2i, limit: int) -> int:
	var cols := NodeGrid.cols()
	var n := cols * NodeGrid.rows()
	var cap := {}   # u * 2n + v → остаточная ёмкость
	var adj: Array = []
	adj.resize(2 * n)
	for i in 2 * n:
		adj[i] = []
	var add := func(u: int, v: int, c: int) -> void:
		cap[u * 2 * n + v] = int(cap.get(u * 2 * n + v, 0)) + c
		cap[v * 2 * n + u] = int(cap.get(v * 2 * n + u, 0))
		if not (adj[u] as Array).has(v):
			(adj[u] as Array).append(v)
		if not (adj[v] as Array).has(u):
			(adj[v] as Array).append(u)
	for y in NodeGrid.rows():
		for x in cols:
			var c := Vector2i(x, y)
			if grid.is_occupied(c):
				continue
			var i := y * cols + x
			add.call(2 * i, 2 * i + 1, limit if (c == a or c == b) else 1)
			for d: Vector2i in NodeGrid.DIRS8:
				if grid.can_step(c, d):
					var j := (y + d.y) * cols + x + d.x
					add.call(2 * i + 1, 2 * j, 1)
	var s := 2 * (a.y * cols + a.x)
	var t := 2 * (b.y * cols + b.x) + 1
	var flow := 0
	while flow < limit:
		var prev := {s: -1}
		var queue: Array = [s]
		var head := 0
		while head < queue.size() and not prev.has(t):
			var u: int = queue[head]
			head += 1
			for v: int in adj[u]:
				if not prev.has(v) and int(cap[u * 2 * n + v]) > 0:
					prev[v] = u
					queue.append(v)
		if not prev.has(t):
			break
		var node := t
		while prev[node] != -1:
			var p: int = prev[node]
			cap[p * 2 * n + node] = int(cap[p * 2 * n + node]) - 1
			cap[node * 2 * n + p] = int(cap[node * 2 * n + p]) + 1
			node = p
		flow += 1
	return flow


## Итог ботов одной строкой на раскладку: цикл, окна, воры (фаз без обнаружений / всего, наименьшие такты), бегуны.
static func report_line(l: LayoutData, tier_name: String = "BASE", phase_count: int = 6) -> String:
	var b := LayoutBots.new(l, tier_name)
	if l.is_legacy():
		return "%s %s: legacy — не проверяется" % [l.name, tier_name]
	if b.error != "":
		return "%s %s: %s" % [l.name, tier_name, b.error]
	var parts: Array[String] = []
	var thief := b.thief_report(phase_count)
	var runner := b.runner_report(phase_count)
	for k in thief.size():
		var t: Dictionary = thief[k]
		var ticks: Array[int] = []
		var cost_min := 999
		for r: Dictionary in t["runs"]:
			if int(r["ticks"]) >= 0:
				ticks.append(int(r["ticks"]))
				cost_min = mini(cost_min, int(r["cost"]))
		ticks.sort()
		var r2: Dictionary = runner[k]
		parts.append("хр%s[%s] окно %d, вор чистых %d/%d%s, бегун ушёл %d поймали %d без Поиска %d" % [str(t["vault"]), t["ring"], t["window"], t["clean"], (t["runs"] as Array).size(),
			(", такты %d–%d, мин. обнаружений %d" % [ticks[0], ticks[-1], cost_min]) if not ticks.is_empty() else ", пути нет", r2["escaped"], r2["caught"], r2["no_search"]])
	return "%s %s: цикл %d; %s" % [l.name, tier_name, b.cycle, " | ".join(parts)]


## Боты как проверка раскладки: вор без обнаружений с каждой выбранной фазы к каждому хранилищу и обратно, бегун у площадки не пойман.
static func check_bots(l: LayoutData, tier_name: String = "BASE", phase_count: int = 6) -> Dictionary:
	if l.is_legacy():
		return {"ok": true, "detail": "legacy — боты не запускаются"}
	var b := LayoutBots.new(l, tier_name)
	if b.error != "":
		return {"ok": false, "detail": b.error}
	var bad: Array[String] = []
	for t: Dictionary in b.thief_report(phase_count):
		var runs: Array = t["runs"]
		if int(t["clean"]) < runs.size():
			bad.append("вор к хранилищу %s: без обнаружений %d из %d фаз" % [str(t["vault"]), t["clean"], runs.size()])
	for r: Dictionary in b.runner_report(phase_count):
		if int(r["caught"]) > 0:
			bad.append("бегун у хранилища %s: поймали %d раз" % [str(r["vault"]), r["caught"]])
	if bad.is_empty():
		return {"ok": true, "detail": "вор чист на всех фазах, бегун уходит; цикл %d" % b.cycle}
	return {"ok": false, "detail": "; ".join(bad)}

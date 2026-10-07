class_name LayoutCheck
extends RefCounted
## Автоматическая проверка правил раскладки (docs/gamedesign/levels.md, 2) по данным LayoutData и тактовому мозгу TickIce.
## Каждая проверка возвращает {ok: bool, detail: String}; detail — одна строка: что не так (или числа, если всё в порядке).
## Маршруты Стражей прогоняются самим TickIce (ожидание, взгляд, шаги по 2 клетки): проверка видит то же, что игрок.
## Не проверяется здесь: ≥ 2 пути к хранилищу, уход (правило 7), периоды Стражей, Маяк и датчики — следующие карточки.

## Первые такты в узле, когда нетраннера не видно (time-and-movement.md, 3.7).
const ENTRY_HIDDEN_TICKS := 2
## Окно площадки внешнего хранилища: наибольшая серия подряд тактов цикла вне зрения; BASE ≥ 12 (HARD ≥ 8), любая площадка — не меньше 3.
const OUTER_WINDOW_MIN := 12
const ANY_WINDOW_MIN := 3
## Площадка «видит» ближайший маршрут и дальше зрения Стража: укрытие ищем среди клеток маршрута не дальше sight_cells + этого запаса.
const COVER_RANGE_EXTRA := 2.0
## Тупик — цепочка блоков карты с единственным выходом; длиннее — ошибка (в блоках карты, как «клетки» документа).
const MAX_DEAD_END := 2
const MAX_CYCLE := 120
const _SIM_TICKS := MAX_CYCLE * 4


static func _res(ok: bool, detail: String) -> Dictionary:
	return {"ok": ok, "detail": detail}


## Все проверки: имя → {ok, detail}.
static func run_all(layout: LayoutData) -> Dictionary:
	return {
		"reachable": check_reachable(layout),
		"vault_distance": check_vault_distance(layout),
		"entry_hidden": check_entry_hidden(layout),
		"windows": check_windows(layout),
		"cover": check_cover(layout),
		"dead_ends": check_dead_ends(layout),
		"vault_grid": check_vault_grid(layout),
	}


## Имена проверок, которые не прошли (пустой массив — раскладка проходит всё).
static func failures(layout: LayoutData) -> Array[String]:
	var out: Array[String] = []
	var all := run_all(layout)
	for k: String in all:
		if not bool(all[k]["ok"]):
			out.append("%s: %s" % [k, all[k]["detail"]])
	return out


# --- Прогон Стражей ---

## Состояния Стражей по тактам: states[t] — массив {cell, dir} по Стражам раскладки, t = 0 (старт) … ticks.
static func simulate(layout: LayoutData, ticks: int) -> Array:
	var grid := layout.grid()
	var ices: Array[TickIce] = []
	for s: Dictionary in layout.sentries:
		ices.append(TickIce.new({"sight_cells": layout.sight_cells}, s["route"], grid))
	var states: Array = []
	for t in ticks + 1:
		if t > 0:
			for ice in ices:
				ice.tick({})
		var row: Array = []
		for ice in ices:
			row.append({"cell": ice.cell(), "dir": ice.dir()})
		states.append(row)
	return states


## Длина цикла патруля в тактах: наименьший период, с которого (такт 1 и дальше) состояния всех Стражей повторяются. 0 — не нашёлся за MAX_CYCLE.
static func cycle_ticks(layout: LayoutData) -> int:
	if layout.sentries.is_empty():
		return 1
	var states := simulate(layout, _SIM_TICKS)
	var keys: Array[String] = []
	for row: Array in states:
		keys.append(str(row))
	for period in range(1, MAX_CYCLE + 1):
		var same := true
		for t in range(1, _SIM_TICKS + 1 - period):
			if keys[t] != keys[t + period]:
				same = false
				break
		if same:
			return period
	return 0


## Видна ли хоть одна из клеток cells хоть одному Стражу в состоянии row (по TickVision, как у ICE в игре).
static func _seen_by_any(layout: LayoutData, grid: NodeGrid, row: Array, cells: Array[Vector2i]) -> bool:
	var half := float(TickIce.DEFAULTS["half_angle_deg"])
	var focus := float(TickIce.DEFAULTS["focus_deg"])
	for st: Dictionary in row:
		for c in cells:
			if TickVision.classify(grid, st["cell"], st["dir"], c, layout.sight_cells, half, focus) != TickVision.NONE:
				return true
	return false


## Окно площадки: наибольшая серия подряд тактов цикла патруля (по кольцу), когда ни одна клетка площадки (блок карты pad_cell) не видна
## ни одному Стражу. cycle — длина цикла (cycle_ticks). Нет Стражей — весь цикл; цикл 0 (не нашёлся) — -1.
static func window_ticks(layout: LayoutData, pad_cell: Vector2i, cycle: int) -> int:
	if cycle <= 0:
		return -1
	var states := simulate(layout, cycle)
	var grid := layout.grid()
	var pad := LayoutData.block_cells(pad_cell)
	var unseen: Array[bool] = []
	for t in range(1, cycle + 1):
		unseen.append(not _seen_by_any(layout, grid, states[t], pad))
	var best := 0
	var run := 0
	for i in cycle * 2:   # по кольцу: серия может перешагнуть конец цикла
		if unseen[i % cycle]:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return mini(best, cycle)


## Клетки 1 м, по которым ходят Стражи за цикл (позиции по тактам и клетки между ними по кратчайшему пути).
static func _route_cells(layout: LayoutData, cycle: int) -> Dictionary:
	var out: Dictionary = {}
	var states := simulate(layout, maxi(cycle, 1))
	var grid := layout.grid()
	for t in states.size():
		var row: Array = states[t]
		for i in row.size():
			var c: Vector2i = row[i]["cell"]
			out[c] = true
			if t > 0:
				var prev: Vector2i = states[t - 1][i]["cell"]
				for m in grid.path(prev, c):
					out[m] = true
	return out


# --- Проверки ---

## (а) Всё достижимо: из клетки входа по свободным клеткам есть путь до площадки каждого хранилища, до площадки выхода и до каждого портала.
static func check_reachable(layout: LayoutData) -> Dictionary:
	var grid := layout.grid()
	var start := NodeGrid.cell_of(layout.spawn)
	if grid.is_occupied(start):
		return _res(false, "клетка входа занята")
	var targets: Array = []
	for v: Dictionary in layout.vaults:
		var pc: Vector2i = v["pad_cell"]
		targets.append({"label": "площадка хранилища %s" % str(v["cell"]), "cells": LayoutData.block_cells(pc)})
	for ec in layout.exit_cells:
		var b := LayoutData.block_of(NodeGrid.cell_of(ec))
		targets.append({"label": "выход %s" % str(b), "cells": LayoutData.block_cells(b)})
	for i in layout.portals.size():
		var p: Vector3 = layout.portals[i]
		if p.is_finite():
			targets.append({"label": "портал %d" % (i + 1), "cells": LayoutData.block_cells(LayoutData.block_of(NodeGrid.cell_of(p)))})
	var lost: Array[String] = []
	for t: Dictionary in targets:
		var ok := false
		for c: Vector2i in t["cells"]:
			if grid.is_occupied(c):
				continue
			if c == start or not grid.path(start, c).is_empty():
				ok = true
				break
		if not ok:
			lost.append(str(t["label"]))
	if lost.is_empty():
		return _res(true, "достижимо всё (%d целей)" % targets.size())
	return _res(false, "недостижимо из входа: " + ", ".join(lost))


## (б) Хранилища не ближе NodeLayout.MIN_VAULT_TO_ROUTE (4 м) к любой клетке маршрута Стража.
static func check_vault_distance(layout: LayoutData) -> Dictionary:
	var cycle := cycle_ticks(layout)
	var cells := _route_cells(layout, cycle)
	var bad: Array[String] = []
	var closest := INF
	for v: Dictionary in layout.vaults:
		var slot: Vector3 = v["slot"]
		var best := INF
		for c: Vector2i in cells:
			best = minf(best, NodeLayout.flat_distance(NodeGrid.center(c), slot))
		closest = minf(closest, best)
		if best < NodeLayout.MIN_VAULT_TO_ROUTE - 0.0001:
			bad.append("хранилище %s: %.1f м" % [str(v["cell"]), best])
	if bad.is_empty():
		return _res(true, "ближайшая клетка маршрута — %.1f м (нужно ≥ %.0f)" % [closest, NodeLayout.MIN_VAULT_TO_ROUTE])
	return _res(false, "ближе %.0f м к маршруту: %s" % [NodeLayout.MIN_VAULT_TO_ROUTE, ", ".join(bad)])


## (в) Вход и порталы вне зрения Стражей на старте: клетки их блоков не видны ни на старте, ни в первые ticks тактов.
static func check_entry_hidden(layout: LayoutData, ticks: int = ENTRY_HIDDEN_TICKS) -> Dictionary:
	var states := simulate(layout, ticks)
	var grid := layout.grid()
	var spots: Array = [{"label": "вход", "cells": LayoutData.block_cells(LayoutData.block_of(NodeGrid.cell_of(layout.spawn)))}]
	for i in layout.portals.size():
		var p: Vector3 = layout.portals[i]
		if p.is_finite():
			spots.append({"label": "портал %d" % (i + 1), "cells": LayoutData.block_cells(LayoutData.block_of(NodeGrid.cell_of(p)))})
	var seen: Array[String] = []
	for s: Dictionary in spots:
		for t in ticks + 1:
			if _seen_by_any(layout, grid, states[t], s["cells"]):
				seen.append("%s (такт %d)" % [str(s["label"]), t])
				break
	if seen.is_empty():
		return _res(true, "вход и порталы вне зрения первые %d такта" % ticks)
	return _res(false, "видно Стражу: " + ", ".join(seen))


## (г) Окна: у внешнего хранилища — не меньше OUTER_WINDOW_MIN подряд тактов цикла, у любой площадки — не меньше ANY_WINDOW_MIN.
static func check_windows(layout: LayoutData, outer_min: int = OUTER_WINDOW_MIN, any_min: int = ANY_WINDOW_MIN) -> Dictionary:
	var cycle := cycle_ticks(layout)
	if cycle <= 0:
		return _res(false, "цикл патруля не найден за %d тактов" % MAX_CYCLE)
	var bad: Array[String] = []
	var report: Array[String] = []
	for v: Dictionary in layout.vaults:
		var w := window_ticks(layout, v["pad_cell"], cycle)
		var need := any_min
		if str(v["ring"]) == "outer":
			need = maxi(outer_min, any_min)
		report.append("%s: %d из %d" % [str(v["cell"]), w, cycle])
		if w < need:
			bad.append("хранилище %s: окно %d из %d, нужно ≥ %d" % [str(v["cell"]), w, cycle, need])
	if bad.is_empty():
		return _res(true, "окна (подряд тактов из цикла): " + "; ".join(report))
	return _res(false, "; ".join(bad))


## (д) Укрытие у площадки: у каждого хранилища есть клетка площадки и клетка маршрута Стража в пределах sight_cells + COVER_RANGE_EXTRA,
## линия между которыми закрыта (колонна, хранилище или стена): с этой стороны Страж площадку не видит.
static func check_cover(layout: LayoutData) -> Dictionary:
	var cycle := cycle_ticks(layout)
	var route := _route_cells(layout, cycle)
	var grid := layout.grid()
	var reach := layout.sight_cells + COVER_RANGE_EXTRA
	var bad: Array[String] = []
	for v: Dictionary in layout.vaults:
		var covered := false
		for pc in LayoutData.block_cells(v["pad_cell"]):
			if grid.is_occupied(pc):
				continue
			for q: Vector2i in route:
				if Vector2(q - pc).length() <= reach and not grid.line_clear(pc, q):
					covered = true
					break
			if covered:
				break
		if not covered:
			bad.append("хранилище %s" % str(v["cell"]))
	if bad.is_empty():
		return _res(true, "у каждой площадки есть закрытая линия к маршруту")
	return _res(false, "нет укрытия у площадки: " + ", ".join(bad))


## (е) Тупики не длиннее MAX_DEAD_END блоков карты: блок с единственным выходом и цепочка блоков с двумя соседями за ним.
static func check_dead_ends(layout: LayoutData) -> Dictionary:
	var bad: Array[String] = []
	var worst := 0
	for sz in LayoutData.SIZE:
		for sx in LayoutData.SIZE:
			var b := Vector2i(sx, sz)
			if _block_free(layout, b) and _free_neighbors(layout, b).size() <= 1:
				var length := _dead_end_length(layout, b)
				worst = maxi(worst, length)
				if length > MAX_DEAD_END:
					bad.append("%s (%d)" % [str(b), length])
	if bad.is_empty():
		return _res(true, "тупиков длиннее %d нет (самый длинный — %d)" % [MAX_DEAD_END, worst])
	return _res(false, "тупик длиннее %d блоков: %s" % [MAX_DEAD_END, ", ".join(bad)])


## (ж) Хранилище по сетке: slot — центр клетки 1 м (не угол блока), эта клетка не колонна; pad — центр свободной клетки 1 м, соседней с клеткой хранилища
## (по восьми направлениям), в блоке pad_cell. Legacy (константы NodeLayout, предметы на углах модулей) не проверяется.
static func check_vault_grid(layout: LayoutData) -> Dictionary:
	if layout.is_legacy():
		return _res(true, "legacy: хранилища на прежних слотах, не проверяется")
	var grid := layout.grid()
	var bad: Array[String] = []
	for v: Dictionary in layout.vaults:
		var label := "хранилище %s" % str(v["cell"])
		var slot: Vector3 = v["slot"]
		var pad: Vector3 = v["pad"]
		if not _on_cell_center(slot):
			bad.append("%s: slot %s не в центре клетки 1 м" % [label, str(slot)])
			continue
		var vc := NodeGrid.cell_of(slot)
		var vb := LayoutData.block_of(vc)
		if layout.blocks[vb.y][vb.x] == "#":
			bad.append("%s: клетка %s — колонна" % [label, str(vc)])
		if not _on_cell_center(pad):
			bad.append("%s: pad %s не в центре клетки 1 м" % [label, str(pad)])
			continue
		var pc := NodeGrid.cell_of(pad)
		if LayoutData.block_of(pc) != v["pad_cell"]:
			bad.append("%s: площадка %s вне блока %s" % [label, str(pc), str(v["pad_cell"])])
		if grid.is_occupied(pc):
			bad.append("%s: площадка %s занята" % [label, str(pc)])
		if maxi(absi(pc.x - vc.x), absi(pc.y - vc.y)) != 1:
			bad.append("%s: площадка %s не соседняя с клеткой %s" % [label, str(pc), str(vc)])
	if bad.is_empty():
		return _res(true, "хранилища и площадки по клеткам 1 м (%d)" % layout.vaults.size())
	return _res(false, "; ".join(bad))


## Центр клетки 1 м: обе координаты на полклетки от целой границы.
static func _on_cell_center(p: Vector3) -> bool:
	var fx := fposmod(p.x - NodeLayout.ROOM_MIN.x, NodeGrid.CELL_M)
	var fz := fposmod(p.z - NodeLayout.ROOM_MIN.y, NodeGrid.CELL_M)
	return absf(fx - NodeGrid.CELL_M * 0.5) < 0.0001 and absf(fz - NodeGrid.CELL_M * 0.5) < 0.0001


static func _block_free(layout: LayoutData, b: Vector2i) -> bool:
	if b.x < 0 or b.y < 0 or b.x >= LayoutData.SIZE or b.y >= LayoutData.SIZE:
		return false
	return not LayoutData.OCCUPIED_SYMBOLS.contains(layout.blocks[b.y][b.x])


static func _free_neighbors(layout: LayoutData, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		if _block_free(layout, b + d):
			out.append(b + d)
	return out


## Длина тупика от блока `end` (у которого не больше одного свободного соседа): сам блок плюс цепочка блоков ровно с двумя соседями.
static func _dead_end_length(layout: LayoutData, end: Vector2i) -> int:
	var length := 1
	var prev := end
	var cur := end
	for _i in LayoutData.SIZE * LayoutData.SIZE:
		var next: Array[Vector2i] = []
		for n in _free_neighbors(layout, cur):
			if n != prev:
				next.append(n)
		if next.size() != 1 or _free_neighbors(layout, next[0]).size() != 2:
			break
		prev = cur
		cur = next[0]
		length += 1
	return length

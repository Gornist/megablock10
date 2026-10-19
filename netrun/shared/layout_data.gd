class_name LayoutData
extends RefCounted
## Раскладка узла как данные (docs/gamedesign/levels.md, 3 и 7): карта W×H символов (1..12 по стороне; 8×8 — прежняя комната), хранилища, маршруты Стражей, подсказки.
## Символ карты = блок 2×2 клетки сетки 1 м (NodeGrid): клетка карты (sx, sz) ↔ клетки (2sx..2sx+1, 2sz..2sz+1); центр блока = центр модуля
## NodeLayout.cell_center(sx, sz) — туда ставятся предметы. Чистые данные: без сцены и сети; сервер и клиент подключат её следующей карточкой.
## Файл — res://data/layouts/<имя>.json; разбор не падает: при ошибке `error` не пусто (остальные поля тогда не годятся).
##
## Точка маршрута Стража в JSON: {cell: [sx, sz]} — клетка карты (в данных получает юго-восточную клетку центра блока, как у игрока) либо
## {cell1: [cx, cz]} — клетка сетки 1 м напрямую (нужна `legacy`: старые маршруты идут по вершинам модулей); плюс wait (тактов стоять) и look
## ("N"/"NE"/…/"NW" или список имён — берётся первое).

const DIR := "res://data/layouts/"
## Сторона карты по умолчанию (8×8: legacy, Фойе, учебный) — константы NodeLayout.ROOM_MAX/GRID и тесты. Размер раскладки — её `cols`/`rows`.
const SIZE := 8
## Предел стороны карты, блоков (1..MAX_SIDE по каждой стороне); предел площади по тиру — LayoutCheck.
const MAX_SIDE := 12
## Занятые символы: колонна, хранилище, Маяк, барьер, логово Black ICE. Остальные (. S 1 2 3 E b v =) — свободные клетки (часть — метки).
const OCCUPIED_SYMBOLS := "#VOBL"
const FREE_SYMBOLS := ".S123Ebv="
const DEFAULT_SIGHT_CELLS := 6.0

var name := ""
var error := ""
## Карта: `rows` строк по `cols` символов (1..MAX_SIDE; не обязательно квадрат).
var blocks: Array[String] = []
## Размер карты в блоках: столбцов (запад → восток) и строк (север → юг). Комната растёт от NodeLayout.ROOM_MIN на юг и восток. До разбора — SIZE.
var cols := SIZE
var rows := SIZE
## Занятые клетки 1 м: Vector2i → true (как NodeGrid.occ).
var occupied: Dictionary = {}
## Вход (центр блока S, y = 0), как NodeLayout.SPAWN.
var spawn := Vector3.ZERO
## Центры блоков площадки выхода E (как NodeLayout.exit_platform_cells()) и центр площадки (как NodeLayout.EXIT_POS).
var exit_cells: Array[Vector3] = []
var exit_pos := Vector3.ZERO
## Порталы по номеру связи: portals[0] — «1», portals[1] — «2», portals[2] — «3»; массив до наибольшего номера на карте, пропуск — Vector3.INF.
var portals: Array[Vector3] = []
## Хранилища: {cell: Vector2i (клетка карты), cell1: Vector2i (клетка 1 м хранилища), slot: Vector3 (центр клетки cell1, y = 1,0), pad_cell: Vector2i (клетка карты
## площадки), pad1: Vector2i (клетка 1 м площадки: свободная клетка блока pad_cell, ближайшая к хранилищу), pad: Vector3 (центр клетки pad1), ring: String}.
## Хранилище и площадка стоят ровно по сетке 1 м, а не на углу блока 2×2. В legacy — как раньше (центры блоков, pad = центр блока pad).
var vaults: Array = []
## Стражи: {id: String, route: Array of {cell: Vector2i (клетка 1 м), wait: int, look: Vector2i (dir8, ZERO — не задан)}} — формат маршрута TickIce.
var sentries: Array = []
## Будки запасного Стража (блоки «b»): клетка 1 м у стены — юго-восточная клетка блока (block_center_cell), её рисует клиент (ice/guard_booth.glb).
var booths: Array[Vector2i] = []
## Запасные Стражи (`kind: reserve`): {id, route} — формат Стража; первая точка маршрута — клетка будки. Выходят из будки на тревоге 2 (ice.md §4), один раз за забег узла.
var reserves: Array = []
## Маяки (`kind: beacon`): {id, cell: Vector2i (клетка 1 м; клетка-тумба «O»), start: Vector2i (dir8), step_deg: float, sweep_steps: int}.
var beacons: Array = []
## Барьеры (`kind: barrier`, `cell: [bx, bz]` — блок «B»): {id, block: Vector2i (блок карты), cells: Array[Vector2i] (4 клетки 1 м, заняты, пока барьер закрыт)}.
var barriers: Array = []
## Датчики (`kind: sensor`): {id, cells: Array[Vector2i] (луч, 2–12 клеток 1 м), on: int, off: int (0 — по тиру узла), phase: int (сколько выключенных тактов цикла уже прошло на входе в узел: старт всегда в фазе «выключен», TickSensor.for_layout; по модулю `off`)}.
var sensors: Array = []
## Логово Black ICE (`black: {id, kind, cell: [bx, bz]}` — левый верхний блок 2×2 блоков карты «L»): {id, kind: String (вид, "" — базовый),
## cells: Array[Vector2i] (16 клеток 1 м), home: Vector2i (клетка, где спит ICE)} или пусто. Black ICE живёт только в логове: `black: null` — без него.
var lair: Dictionary = {}
## Подсказки: {cell: Vector2i (клетка 1 м), text: String, pos: Vector3 (место в мире, y = 0)}.
var signs: Array = []
## Источники света облака, заданные раскладкой (`lights` в файле, необязательно): {pos: Vector3 (мир, y = 1), r: float (м), s: float (сила), threat: bool (красный — угроза)}.
## Есть хоть один — клиент берёт только их; пусто — набор по умолчанию из самой раскладки (CloudLightPlan).
var lights: Array = []
## Дальность зрения Стражей этой раскладки, клеток (meta.sight_cells; по умолчанию как TickIce.DEFAULTS).
var sight_cells := DEFAULT_SIGHT_CELLS
## Дальность зрения задана в файле (meta.sight_cells); иначе сервер берёт её по тиру узла.
var has_sight := false

const LEGACY := "legacy"
## Раскладки по имени: файл читается один раз на процесс (в том числе неудачная загрузка — с error). Только для чтения: grid() отдаёт копию.
static var _cache: Dictionary = {}


## Раскладка по имени из кэша; пустое имя — legacy.
static func cached(layout_name: String) -> LayoutData:
	var key := LEGACY if layout_name.is_empty() else layout_name
	if not _cache.has(key):
		_cache[key] = load_named(key)
	return _cache[key]


## Прежняя комната (константы NodeLayout) — не Фойе: у неё площадка у хранилища считается прежней функцией, а не клеткой pad.
func is_legacy() -> bool:
	return name == LEGACY


static func load_named(layout_name: String) -> LayoutData:
	var path := DIR + layout_name + ".json"
	if not FileAccess.file_exists(path):
		var missing := LayoutData.new()
		missing.name = layout_name
		missing.error = "нет файла " + path
		return missing
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		var bad := LayoutData.new()
		bad.name = layout_name
		bad.error = "файл " + path + " не JSON-объект"
		return bad
	return parse(parsed)


static func parse(d: Dictionary) -> LayoutData:
	var ld := LayoutData.new()
	ld.name = str(d.get("name", ""))
	ld.error = ld._fill(d)
	return ld


## Клетка сетки 1 м → клетка карты (блок 2×2).
static func block_of(c: Vector2i) -> Vector2i:
	return Vector2i(c.x >> 1, c.y >> 1)


## Четыре клетки 1 м блока карты (sx, sz).
static func block_cells(b: Vector2i) -> Array[Vector2i]:
	return [Vector2i(2 * b.x, 2 * b.y), Vector2i(2 * b.x + 1, 2 * b.y), Vector2i(2 * b.x, 2 * b.y + 1), Vector2i(2 * b.x + 1, 2 * b.y + 1)]


## Клетка 1 м блока карты, как её видит игрок и Страж в центре блока: юго-восточная клетка (NodeGrid.cell_of центра).
static func block_center_cell(b: Vector2i) -> Vector2i:
	return Vector2i(2 * b.x + 1, 2 * b.y + 1)


## Клетки 1 м блока хранилища, занятые укрытием env/cover. После П5 их нет: хранилище занимает одну клетку (cell1), остальные три клетки блока свободны
## для шага (владелец на очках: «занятыми должны быть ровно 2 видимые клетки», хранилище и площадка). Функция осталась для клиента (что рисовать)
## и LayoutCheck.check_occupied_visible — оба получают пустой список.
func cover_cells() -> Array[Vector2i]:
	return []


## Юго-восточный угол комнаты (x, z), м: ROOM_MIN + CELL · (cols, rows). Для 8×8 — NodeLayout.ROOM_MAX.
func room_max() -> Vector2:
	return NodeLayout.ROOM_MIN + NodeLayout.CELL * Vector2(cols, rows)


## Центр комнаты (y = 0), куда «смотрит внутрь» вход от портала. Для 8×8 — NodeLayout.ROOM_CENTER.
func room_center() -> Vector3:
	var c := NodeLayout.ROOM_MIN + room_max()
	return Vector3(c.x * 0.5, 0.0, c.y * 0.5)


## Клетка карты (блок) внутри карты.
func has_block(b: Vector2i) -> bool:
	return b.x >= 0 and b.y >= 0 and b.x < cols and b.y < rows


func grid() -> NodeGrid:
	var g := NodeGrid.new()
	g.size = Vector2i(cols * 2, rows * 2)
	g.occ = occupied.duplicate()
	if not is_legacy():
		# Прыжок на клетку самого хранилища (она занята) ставит на площадку перед ним; соседние клетки блока свободны и остаются как есть.
		for v: Dictionary in vaults:
			g.landing[v["cell1"]] = v["pad1"]
	return g


func _fill(d: Dictionary) -> String:
	var cells: Variant = d.get("cells")
	if not (cells is Array) or (cells as Array).is_empty() or (cells as Array).size() > MAX_SIDE:
		return "cells: нужно от 1 до %d строк" % MAX_SIDE
	rows = (cells as Array).size()
	var first: Variant = (cells as Array)[0]
	if not (first is String) or (first as String).is_empty() or (first as String).length() > MAX_SIDE:
		return "cells[0]: нужна строка из 1–%d символов" % MAX_SIDE
	cols = (first as String).length()
	var spawn_blocks: Array[Vector2i] = []
	var exit_blocks: Array[Vector2i] = []
	var portal_at: Dictionary = {}
	for sz in rows:
		var row: Variant = (cells as Array)[sz]
		if not (row is String) or (row as String).length() != cols:
			return "cells[%d]: нужна строка из %d символов (как в первой)" % [sz, cols]
		var line: String = row
		blocks.append(line)
		for sx in cols:
			var ch := line[sx]
			var b := Vector2i(sx, sz)
			if OCCUPIED_SYMBOLS.contains(ch):
				if ch == "V" or ch == "O":   # «O» — Маяк: тумбу (одну клетку) отмечает _fill_ice по записи kind: beacon
					pass   # хранилище занимает одну клетку 1 м (её отмечает _fill_vaults), остальные три клетки блока свободны для шага (П5)
				else:
					for c in block_cells(b):
						occupied[c] = true
			elif not FREE_SYMBOLS.contains(ch):
				return "cells[%d][%d]: неизвестный символ '%s'" % [sz, sx, ch]
			if ch == "b":
				booths.append(block_center_cell(b))
			if ch == "S":
				spawn_blocks.append(b)
			elif ch == "E":
				exit_blocks.append(b)
			elif ch == "1" or ch == "2" or ch == "3":
				portal_at[int(ch)] = b
	if spawn_blocks.size() != 1:
		return "cells: нужен ровно один вход S, найдено %d" % spawn_blocks.size()
	if exit_blocks.is_empty():
		return "cells: нет площадки выхода E"
	spawn = NodeLayout.cell_center(spawn_blocks[0].x, spawn_blocks[0].y)
	var sum := Vector3.ZERO
	for eb in exit_blocks:
		var ec := NodeLayout.cell_center(eb.x, eb.y)
		exit_cells.append(ec)
		sum += ec
	exit_pos = sum / float(exit_blocks.size())
	var max_portal := 0
	for n: int in portal_at:
		max_portal = maxi(max_portal, n)
	for n in range(1, max_portal + 1):
		if portal_at.has(n):
			var pb: Vector2i = portal_at[n]
			portals.append(NodeLayout.cell_center(pb.x, pb.y))
		else:
			portals.append(Vector3.INF)
	var err := _fill_vaults(d.get("vaults", []))
	if err != "":
		return err
	err = _fill_ice(d.get("ice", []))
	if err != "":
		return err
	var bk: Variant = d.get("black")
	if bk is Dictionary:
		var bd: Dictionary = bk
		if not bd.has("cell"):
			return "black: нужен cell [bx, bz] логова (Black ICE без логова не бывает)"
		var lerr := _fill_lair(bd)
		if lerr != "":
			return lerr
	elif bk != null:
		return "black: нужен объект или null"
	err = _fill_signs(d.get("signs", []))
	if err != "":
		return err
	err = _fill_lights(d.get("lights", []))
	if err != "":
		return err
	var meta: Variant = d.get("meta", {})
	if meta is Dictionary:
		has_sight = (meta as Dictionary).has("sight_cells")
		sight_cells = float((meta as Dictionary).get("sight_cells", DEFAULT_SIGHT_CELLS))
	return ""


func _fill_vaults(src: Variant) -> String:
	if not (src is Array):
		return "vaults: нужен массив"
	for v: Variant in src:
		if not (v is Dictionary):
			return "vaults: запись не объект"
		var vd: Dictionary = v
		var cell: Variant = _map_cell(vd.get("cell"))
		var pad: Variant = _map_cell(vd.get("pad"))
		if cell == null or pad == null:
			return "vaults: cell и pad — клетки карты [x, z] в пределах карты %d×%d" % [cols, rows]
		var cc: Vector2i = cell
		var pc: Vector2i = pad
		var pair := _vault_pair(cc, pc)
		var cell1 := pair[0]
		var pad1 := pair[1]
		var slot := NodeLayout.cell_center(cc.x, cc.y)
		var pad_pos := NodeLayout.cell_center(pc.x, pc.y)
		if not is_legacy():
			slot = NodeGrid.center(cell1)
			pad_pos = NodeGrid.center(pad1)
		else:
			# legacy: хранилище в клетке 1 м своего блока (те же SHARD_SLOTS, что у сервера и клиента), а не на вершине блока 2×2;
			# площадка — прежней формулой на VAULT_PAD_DIST к центру комнаты. Порядок vaults в legacy.json = порядок SHARD_SLOTS.
			var k := vaults.size()
			if k < NodeLayout.SHARD_SLOTS.size():
				slot = NodeLayout.SHARD_SLOTS[k]
				cell1 = NodeGrid.cell_of(slot)
			pad_pos = NodeLayout.vault_pad(slot)
		slot.y = 1.0
		if not is_legacy():
			occupied[cell1] = true   # занята ровно клетка хранилища; площадка — соседняя клетка другого блока, на ней стоят
		vaults.append({
			"cell": cc, "cell1": cell1, "slot": slot, "pad_cell": pc, "pad1": pad1,
			"pad": pad_pos, "ring": str(vd.get("ring", "outer")),
		})
	return ""


## Пара клеток 1 м [клетка хранилища, клетка площадки]: ближайшие друг к другу клетка блока хранилища и свободная клетка блока площадки.
## При равенстве — юго-восточная клетка блока хранилища (block_center_cell: так стоят игрок и Страж «в центре блока»), потом порядок block_cells.
## Хранилище — клетка своего блока, а не всегда юго-восточная: площадка с западной стороны иначе оказалась бы в двух клетках от него.
## Свободных клеток у площадки нет (раскладка испорчена) — берётся ближайшая любая: LayoutCheck.check_vault_grid назовёт ошибку.
func _vault_pair(vault_block: Vector2i, pad_block: Vector2i) -> Array[Vector2i]:
	var se := block_center_cell(vault_block)
	var vault_cells: Array[Vector2i] = [se, se + Vector2i(-1, 0), se + Vector2i(0, -1), se + Vector2i(-1, -1)]
	var best: Array[Vector2i] = [se, se]
	var best_d := INF
	for only_free in [true, false]:
		for vc in vault_cells:
			for pc in block_cells(pad_block):
				if only_free and _cell_is_occupied(pc):
					continue
				var d := Vector2(pc - vc).length()
				if d < best_d - 0.0001:
					best_d = d
					best = [vc, pc]
		if best_d < INF:
			break
	return best


## Клетка 1 м занята по карте (колонна, хранилище, Маяк, барьер, логово): символ её блока в OCCUPIED_SYMBOLS.
func _cell_is_occupied(c: Vector2i) -> bool:
	var b := block_of(c)
	var ch := blocks[b.y][b.x]
	if ch == "O":
		return occupied.has(c)   # Маяк занимает одну клетку блока (тумба), остальные свободны
	return OCCUPIED_SYMBOLS.contains(ch)


func _fill_ice(src: Variant) -> String:
	if not (src is Array):
		return "ice: нужен массив"
	for e: Variant in src:
		if not (e is Dictionary):
			return "ice: запись не объект"
		var ed: Dictionary = e
		if str(ed.get("kind", "")) == "beacon":
			var bc: Variant = _point_cell(ed)
			if bc == null:
				return "ice %s: маяк без клетки в пределах карты" % str(ed.get("id", "?"))
			var start := NodeGrid.look_dir(ed.get("start", "N"))
			if start == Vector2i.ZERO:
				return "ice %s: маяку нужно направление start (N, NE, E…)" % str(ed.get("id", "?"))
			occupied[bc] = true   # тумба занимает свою клетку 1 м
			beacons.append({"id": str(ed.get("id", "o%d" % (beacons.size() + 1))), "cell": bc, "start": start,
				"step_deg": clampf(float(ed.get("step_deg", 45.0)), 45.0, 180.0), "sweep_steps": maxi(int(ed.get("sweep_steps", 0)), 0)})
			continue
		if str(ed.get("kind", "")) == "barrier":
			# Барьер (ice.md §5): закрывает проход — блок карты «B» (4 клетки 1 м), занятый, пока не вскрыт.
			var bb: Variant = _map_cell(ed.get("cell"))
			if bb == null:
				return "ice %s: барьеру нужна клетка карты cell [bx, bz]" % str(ed.get("id", "?"))
			var bbk: Vector2i = bb
			if blocks[bbk.y][bbk.x] != "B":
				return "ice %s: барьер стоит не на блоке «B» карты" % str(ed.get("id", "?"))
			barriers.append({"id": str(ed.get("id", "k%d" % (barriers.size() + 1))), "block": bbk, "cells": block_cells(bbk)})
			continue
		if str(ed.get("kind", "")) == "sensor":
			var sc: Variant = _point_cell(ed)
			if sc == null:
				return "ice %s: датчик без клетки в пределах карты" % str(ed.get("id", "?"))
			var cells := NodeGrid.beam_cells(sc, NodeGrid.look_dir(ed.get("dir", "")), int(ed.get("len", 0)))
			if cells.is_empty():
				return "ice %s: датчику нужны dir по ряду или столбцу (N, E, S, W) и len 2–12" % str(ed.get("id", "?"))
			for bc2 in cells:
				if not _in_grid(bc2):
					return "ice %s: луч датчика выходит за карту" % str(ed.get("id", "?"))
			sensors.append({"id": str(ed.get("id", "d%d" % (sensors.size() + 1))), "cells": cells,
				"on": maxi(int(ed.get("on", 0)), 0), "off": maxi(int(ed.get("off", 0)), 0), "phase": maxi(int(ed.get("phase", 0)), 0)})
			continue
		if str(ed.get("kind", "")) == "reserve":
			var rr := _route(ed.get("route", []))
			if rr.has("error"):
				return "ice %s: %s" % [str(ed.get("id", "?")), str(rr["error"])]
			var first: Vector2i = (rr["route"] as Array)[0]["cell"]
			if not booths.has(first):
				return "ice %s: запасной Страж должен начинать маршрут в будке (блок «b» карты)" % str(ed.get("id", "?"))
			reserves.append({"id": str(ed.get("id", "r%d" % (reserves.size() + 1))), "route": rr["route"]})
			continue
		if str(ed.get("kind", "")) != "sentry":
			continue
		var r := _route(ed.get("route", []))
		if r.has("error"):
			return "ice %s: %s" % [str(ed.get("id", "?")), str(r["error"])]
		sentries.append({"id": str(ed.get("id", "g%d" % (sentries.size() + 1))), "route": r["route"]})
	return _trim_sensor_beams()


## Луч Датчика обрывается на первой занятой клетке (колонна, укрытие, тумба Маяка, хранилище, барьер): «что видно, то и работает» (Game 16.10, правило без
## исключений) — и рисуется, и срабатывает только до неё. Занятость известна только после разбора всех записей (тумба Маяка), поэтому обрезаем в конце. Клетка
## самого датчика остаётся, даже если занята; луч короче BEAM_MIN_LEN клеток — ошибка раскладки.
func _trim_sensor_beams() -> String:
	for s: Dictionary in sensors:
		var out: Array[Vector2i] = []
		for c: Vector2i in s["cells"]:
			if not out.is_empty() and occupied.has(c):
				break
			out.append(c)
		if out.size() < NodeGrid.BEAM_MIN_LEN:
			return "ice %s: луч датчика упирается в занятую клетку сразу (меньше %d клеток)" % [str(s["id"]), NodeGrid.BEAM_MIN_LEN]
		s["cells"] = out
	return ""


## Логово: `cell` — левый верхний из четырёх блоков карты, все четыре — «L» (4×4 м, 2×2 клетки карты по 2 м).
func _fill_lair(bd: Dictionary) -> String:
	var b: Variant = _map_cell(bd.get("cell"))
	if b == null:
		return "black: cell [bx, bz] вне карты"
	var tl: Vector2i = b
	var cells: Array[Vector2i] = []
	for dx in 2:
		for dy in 2:
			var bb := Vector2i(tl.x + dx, tl.y + dy)
			if not has_block(bb) or blocks[bb.y][bb.x] != "L":
				return "black: логову нужны четыре блока «L» (2×2) от блока %s" % str(tl)
			cells.append_array(block_cells(bb))
	lair = {"id": str(bd.get("id", "black_1")), "kind": str(bd.get("kind", "")), "cells": cells,
		"home": Vector2i(2 * tl.x + 2, 2 * tl.y + 2)}
	return ""


## Источники света облака: `lights: [{cell | cell1: [x, z], r: 1..12, s: 0.1..3 (по умолчанию 1), threat: bool}]`; cell — центр блока карты, cell1 — клетка 1 м.
func _fill_lights(src: Variant) -> String:
	if not (src is Array):
		return "lights: нужен массив"
	for l: Variant in src:
		if not (l is Dictionary):
			return "lights: запись не объект"
		var ld: Dictionary = l
		var c: Variant = _point_cell(ld)
		if c == null:
			return "lights: нужна клетка cell [x, z] или cell1"
		var cc: Vector2i = c
		var pos := NodeGrid.center(cc)
		if not ld.has("cell1"):
			var b := block_of(cc)
			pos = NodeLayout.cell_center(b.x, b.y)
		pos.y = 1.0
		var r := float(ld.get("r", 3.0))
		var s := float(ld.get("s", 1.0))
		if r < 1.0 or r > 12.0 or s < 0.1 or s > 3.0:
			return "lights: r в 1..12 м, s в 0,1..3"
		lights.append({"pos": pos, "r": r, "s": s, "threat": bool(ld.get("threat", false))})
	return ""


func _fill_signs(src: Variant) -> String:
	if not (src is Array):
		return "signs: нужен массив"
	for s: Variant in src:
		if not (s is Dictionary):
			return "signs: запись не объект"
		var sd: Dictionary = s
		var c: Variant = _point_cell(sd)
		if c == null:
			return "signs: нужна клетка cell [x, z] или cell1"
		var cc: Vector2i = c
		# pos — где подпись стоит в мире: cell — центр модуля блока карты, cell1 — центр клетки 1 м.
		var pos := NodeGrid.center(cc)
		if not sd.has("cell1"):
			var b := block_of(cc)
			pos = NodeLayout.cell_center(b.x, b.y)
		signs.append({"cell": cc, "text": str(sd.get("text", "")), "pos": pos})
	return ""


## {route: Array} или {error: String}.
func _route(src: Variant) -> Dictionary:
	if not (src is Array) or (src as Array).is_empty():
		return {"error": "route: нужен непустой массив точек"}
	var out: Array = []
	for p: Variant in src:
		if not (p is Dictionary):
			return {"error": "route: точка не объект"}
		var pd: Dictionary = p
		var c: Variant = _point_cell(pd)
		if c == null:
			return {"error": "route: точка без клетки в пределах карты"}
		out.append({"cell": c, "wait": maxi(int(pd.get("wait", 0)), 0), "look": NodeGrid.look_dir(pd.get("look"))})
	return {"route": out}


## Клетка 1 м точки: cell1 — как есть, cell — юго-восточная клетка центра блока карты; null — нет или вне карты.
func _point_cell(pd: Dictionary) -> Variant:
	if pd.has("cell1"):
		var a: Variant = pd["cell1"]
		if a is Array and (a as Array).size() == 2:
			var c := Vector2i(int((a as Array)[0]), int((a as Array)[1]))
			if _in_grid(c):
				return c
		return null
	var b: Variant = _map_cell(pd.get("cell"))
	if b == null:
		return null
	return block_center_cell(b)


## Клетка карты [sx, sz] → Vector2i; null — не пара чисел или вне карты (0..cols-1, 0..rows-1).
func _map_cell(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() != 2:
		return null
	var c := Vector2i(int((v as Array)[0]), int((v as Array)[1]))
	if not has_block(c):
		return null
	return c


## Клетка 1 м внутри комнаты этой раскладки.
func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols * 2 and c.y < rows * 2

class_name LayoutData
extends RefCounted
## Раскладка узла как данные (docs/gamedesign/levels.md, 3 и 7): карта 8×8 символов, хранилища, маршруты Стражей, подсказки.
## Символ карты = блок 2×2 клетки сетки 1 м (NodeGrid): клетка карты (sx, sz) ↔ клетки (2sx..2sx+1, 2sz..2sz+1); центр блока = центр модуля
## NodeLayout.cell_center(sx, sz) — туда ставятся предметы. Чистые данные: без сцены и сети; сервер и клиент подключат её следующей карточкой.
## Файл — res://data/layouts/<имя>.json; разбор не падает: при ошибке `error` не пусто (остальные поля тогда не годятся).
##
## Точка маршрута Стража в JSON: {cell: [sx, sz]} — клетка карты (в данных получает юго-восточную клетку центра блока, как у игрока) либо
## {cell1: [cx, cz]} — клетка сетки 1 м напрямую (нужна `legacy`: старые маршруты идут по вершинам модулей); плюс wait (тактов стоять) и look
## ("N"/"NE"/…/"NW" или список имён — берётся первое).

const DIR := "res://data/layouts/"
const SIZE := 8
## Занятые символы: колонна, хранилище, Маяк, барьер, логово Black ICE. Остальные (. S 1 2 3 E b v =) — свободные клетки (часть — метки).
const OCCUPIED_SYMBOLS := "#VOBL"
const FREE_SYMBOLS := ".S123Ebv="
const DEFAULT_SIGHT_CELLS := 6.0

var name := ""
var error := ""
## Карта: 8 строк по 8 символов.
var blocks: Array[String] = []
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
## Black ICE (`black` в файле): {id, route} или пусто.
var black: Dictionary = {}
## Подсказки: {cell: Vector2i (клетка 1 м), text: String, pos: Vector3 (место в мире, y = 0)}.
var signs: Array = []
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


## Клетки 1 м блока хранилища, занятые укрытием env/cover: три клетки блока, кроме клетки самого хранилища (cell1). Одно правило
## для клиента (что рисовать) и LayoutCheck.check_occupied_visible (что покрыто моделью). У legacy укрытий нет.
func cover_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_legacy():
		return out
	for v: Dictionary in vaults:
		for c in block_cells(v["cell"]):
			if c != v["cell1"]:
				out.append(c)
	return out


func grid() -> NodeGrid:
	var g := NodeGrid.new()
	g.occ = occupied.duplicate()
	if not is_legacy():
		# Прыжок на любую клетку блока хранилища (он занят) ставит на площадку перед ним.
		for v: Dictionary in vaults:
			for c in block_cells(v["cell"]):
				g.landing[c] = v["pad1"]
	return g


func _fill(d: Dictionary) -> String:
	var cells: Variant = d.get("cells")
	if not (cells is Array) or (cells as Array).size() != SIZE:
		return "cells: нужно %d строк" % SIZE
	var spawn_blocks: Array[Vector2i] = []
	var exit_blocks: Array[Vector2i] = []
	var portal_at: Dictionary = {}
	for sz in SIZE:
		var row: Variant = (cells as Array)[sz]
		if not (row is String) or (row as String).length() != SIZE:
			return "cells[%d]: нужна строка из %d символов" % [sz, SIZE]
		var line: String = row
		blocks.append(line)
		for sx in SIZE:
			var ch := line[sx]
			var b := Vector2i(sx, sz)
			if OCCUPIED_SYMBOLS.contains(ch):
				for c in block_cells(b):
					occupied[c] = true
			elif not FREE_SYMBOLS.contains(ch):
				return "cells[%d][%d]: неизвестный символ '%s'" % [sz, sx, ch]
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
		var broute := _route(bd.get("route", []))
		if broute.has("error"):
			return "black: " + str(broute["error"])
		black = {"id": str(bd.get("id", "black_1")), "route": broute["route"]}
	elif bk != null:
		return "black: нужен объект или null"
	err = _fill_signs(d.get("signs", []))
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
			return "vaults: cell и pad — клетки карты [x, z] в пределах 0..%d" % (SIZE - 1)
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
		slot.y = 1.0
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
	return OCCUPIED_SYMBOLS.contains(blocks[b.y][b.x])


func _fill_ice(src: Variant) -> String:
	if not (src is Array):
		return "ice: нужен массив"
	for e: Variant in src:
		if not (e is Dictionary):
			return "ice: запись не объект"
		var ed: Dictionary = e
		if str(ed.get("kind", "")) != "sentry":
			continue   # Маяк, датчик и запасной Страж — следующие карточки
		var r := _route(ed.get("route", []))
		if r.has("error"):
			return "ice %s: %s" % [str(ed.get("id", "?")), str(r["error"])]
		sentries.append({"id": str(ed.get("id", "g%d" % (sentries.size() + 1))), "route": r["route"]})
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
			if NodeGrid.in_bounds(c):
				return c
		return null
	var b: Variant = _map_cell(pd.get("cell"))
	if b == null:
		return null
	return block_center_cell(b)


## Клетка карты [sx, sz] → Vector2i; null — не пара чисел или вне 0..7.
func _map_cell(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() != 2:
		return null
	var c := Vector2i(int((v as Array)[0]), int((v as Array)[1]))
	if c.x < 0 or c.y < 0 or c.x >= SIZE or c.y >= SIZE:
		return null
	return c

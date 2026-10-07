class_name TickForecast
extends RefCounted
## Прогноз такта для клиента (docs/gamedesign/time-and-movement.md 2.2, 3.4): что увидят ICE на следующем такте. Чистые функции без сцены:
## цвет рамки прицела и свет зрения на полу считаются по «намерениям» ICE из сообщения state (клетка, направление, следующий шаг).
## Зрение — тот же код, что у сервера (TickVision). Конус и фокус — как у TickIce по умолчанию (50° / 25°); дальность приходит в `sc`.

const GREEN := 0
const YELLOW := 1
const RED := 2

const HALF_DEG := 50.0
const FOCUS_DEG := 25.0
## Дальность зрения, если сервер не прислал `sc` (старый сервер): стартовое значение ice.md.
const DEFAULT_SIGHT := 6.0
## Поиск, чей следующий шаг не дальше этого от клетки (м), — предзахват: смерть не бывает внезапной (решение владельца).
const PRECAPTURE_M := 2.0
## Красная рамка «залипает» (stealth.md С9): прыжок, только если рамка простояла на клетке не меньше (с).
const RED_HOLD_SEC := 0.4

## Состояние TickIce «Поиск» (server/ice/tick_ice.gd: Mode.SEARCH); клиент server/ не читает, номер продублирован.
const ST_SEARCH := 3


## Угроза клетке после следующего такта: 0 зелёный, 1 жёлтый (периферия), 2 красный (фокус или предзахват).
static func threat(grid: NodeGrid, intents: Array, cell: Vector2i) -> int:
	var worst := GREEN
	for it: Dictionary in intents:
		var level := _threat_one(grid, it, cell)
		if level > worst:
			worst = level
			if worst == RED:
				break
	return worst


static func _threat_one(grid: NodeGrid, it: Dictionary, cell: Vector2i) -> int:
	var nc: Vector2i = it.get("nc", it["c"])
	var nd: Vector2i = it.get("nd", it.get("d", Vector2i.ZERO))
	var sc := float(it.get("sc", DEFAULT_SIGHT))
	if bool(it.get("black", false)):
		return _classify_to_threat(TickVision.classify(grid, nc, nd, cell, sc, HALF_DEG, FOCUS_DEG))
	if cell == nc:
		return RED   # ICE встанет в эту клетку: игрок в фокусе
	if int(it.get("st", 0)) == ST_SEARCH and (NodeGrid.center(nc) - NodeGrid.center(cell)).length() <= PRECAPTURE_M + 0.001:
		return RED   # предзахват: Поиск рядом
	return _classify_to_threat(TickVision.classify(grid, nc, nd, cell, sc, HALF_DEG, FOCUS_DEG))


static func _classify_to_threat(vision: int) -> int:
	match vision:
		TickVision.FOCUS:
			return RED
		TickVision.PERIPHERY:
			return YELLOW
	return GREEN


## Предзахват: этот ICE в Поиске и его следующий шаг рядом с клеткой `cell` (красная стрелка на игрока).
static func is_precapture(it: Dictionary, cell: Vector2i) -> bool:
	if bool(it.get("black", false)) or int(it.get("st", 0)) != ST_SEARCH:
		return false
	var nc: Vector2i = it.get("nc", it["c"])
	return (NodeGrid.center(nc) - NodeGrid.center(cell)).length() <= PRECAPTURE_M + 0.001


## Намерения из поля `ice` сообщения state: {c, d, st, nc, nd, sc, black, rt?} (клетки Vector2i; rt — клетки следующих шагов, если сервер прислал). Записи без `c` (realtime) пропускаются;
## Black ICE (`b` = 1) — по c / d, без намерения (nc = c).
static func parse_intents(ice_list: Array) -> Array:
	var out: Array = []
	for e in ice_list:
		if not (e is Dictionary) or not (e as Dictionary).has("c"):
			continue
		var d: Dictionary = e
		var c := _cell(d["c"])
		var dir := _cell(d.get("d", [0, 0]))
		var black := int(d.get("b", 0)) == 1
		var it := {
			"c": c,
			"d": dir,
			"st": int(d.get("st", d.get("s", 0))),
			"nc": c if black else _cell(d.get("nc", d["c"])),
			"nd": dir if black else _cell(d.get("nd", d.get("d", [0, 0]))),
			"sc": float(d.get("sc", DEFAULT_SIGHT)),
			"black": black,
		}
		var rt: Variant = d.get("rt")
		if not black and rt is Array:
			var cells: Array[Vector2i] = []
			for p in rt:
				cells.append(_cell(p))
			it["rt"] = cells   # след маршрута на 3 шага (первая клетка = nc); старый сервер его не шлёт — тогда ключа нет
		out.append(it)
	return out


static func _cell(a: Variant) -> Vector2i:
	if a is Array and (a as Array).size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i.ZERO


## Красную рамку можно отпустить в прыжок, только если она простояла на клетке `held_sec` секунд (С9).
static func red_hold_ok(held_sec: float) -> bool:
	return held_sec >= RED_HOLD_SEC - 0.0001

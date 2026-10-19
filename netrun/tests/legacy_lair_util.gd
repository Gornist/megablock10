extends RefCounted
## Прежняя комната (legacy) с логовом Black ICE: для тестов отдельного GrayNode (без графа), где Black ICE нужен, а геометрия — прежняя
## (шард NodeLayout.SHARD_POS, площадка выхода, вход). Black ICE живёт только в логове (решение владельца 19.10), поэтому «Black ICE на legacy»
## в тестах — это legacy.json + `black` с логовом в углу карты, далеко от шарда, выхода и маршрутов Стражей.
## Раскладка в кэш LayoutData не кладётся: узлу её отдают напрямую (apply() до GrayNode.start).

## Клетка 1 м, откуда Black ICE ещё «далеко» от всех: цель в углу карты (до логова 11 клеток).
const FAR := Vector2i(13, 2)
## Куда «спрятанный» игрок отступает, пока Black ICE идёт к последней засечённой клетке (FAR): не по пути, касание не вернёт след.
const AWAY := Vector2i(2, 15)
## Номер такта пробуждения + первого такта охоты: trace ≥ 50 — 6 тактов пробуждения, на 7-м такте охота (TickBlack.DEFAULTS.wake_ticks).
const TICKS_TO_HUNT := 7


## legacy.json с логовом (блоки 0–1 × 3–4 карты, дом ICE — клетка (2, 8)); kind — вид Black ICE ("" — базовый).
static func parse(kind: String = "") -> LayoutData:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LayoutData.DIR + "legacy.json"))
	var cells: Array = d["cells"]
	cells[3] = "LL......"
	cells[4] = "LL#..#.."
	d["cells"] = cells
	d["black"] = {"id": "b1", "kind": kind, "cell": [0, 3]}
	return LayoutData.parse(d)


## Отдать узлу раскладку с логовом. frozen — часы тактов узла сами не тикают: такты Black ICE даёт тест (GrayNode._step_tick_black) —
## в реальном времени пробуждение + охота (7 тактов по окну 5 с) шли бы десятки секунд, а число тактов в тесте нужно знать точно.
## Тесту, где бот должен ходить (по одному ходу за такт), нужны живые часы: frozen = false, а потом freeze(node), когда ходить уже не надо.
## Вызывать до GrayNode.start.
static func apply(node: GrayNode, kind: String = "", frozen: bool = true) -> LayoutData:
	var ld := parse(kind)
	assert(ld.error == "", "legacy+логово: " + ld.error)
	node.layout = ld
	node.ice_grid = ld.grid()
	if frozen:
		var s := NodeGraph.DEFAULT_SETTINGS.duplicate(true)
		s["tick_window_sec"] = 3600.0
		s["tick_min_interval_sec"] = 3600.0
		node.settings = s
	return ld


## Остановить часы тактов запущенного узла: дальше Black ICE тикает только по вызовам теста.
static func freeze(node: GrayNode) -> void:
	node.tick_clock.window_sec = 3600.0
	node.tick_clock.min_interval_sec = 3600.0

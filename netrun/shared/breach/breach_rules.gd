class_name BreachRules
extends RefCounted
## Правила взлома без состояния (порт app/.../breach/BreachRules.kt, BreachEngine.kt, BreachResult): чередование строка/столбец,
## совпадение демонов в буфере, исход попытки. ЕДИНСТВЕННОЕ место, где определена связка строка/столбец: и генератор сетки
## (BreachGrid.generate), и попытка (BreachAttempt.selectable_cells) берут её отсюда. Иначе решаемость молча ломается:
## генератор проложит путь по одному правилу, игрок будет ограничен другим.
##
## Клетка — Vector2i(x = строка, y = столбец): как Pair(row, col) в Kotlin и пары [строка, столбец] в golden-наборах.

const ROW := "ROW"
const COLUMN := "COLUMN"

const SUCCESS := "SUCCESS"
const PARTIAL := "PARTIAL"
const FAIL := "FAIL"


## selected_count — сколько клеток уже выбрано (>= 1). Возвращает ограничение для СЛЕДУЮЩЕЙ: вторая клетка — в том же столбце,
## что первая, третья — в той же строке, что вторая, и так далее. Первая клетка — всегда из верхней строки (это решает вызывающий).
static func next_link_dimension(selected_count: int) -> String:
	return COLUMN if (selected_count - 1) % 2 == 0 else ROW


## Ещё не посещённые клетки той же строки/столбца, что `from`, кроме самой `from`. visited — множество: Dictionary Vector2i -> true.
static func candidates_for(from: Vector2i, dimension: String, grid_size: int, visited: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(grid_size):
		var cell := Vector2i(i, from.y) if dimension == COLUMN else Vector2i(from.x, i)
		if cell != from and not visited.has(cell):
			out.append(cell)
	return out


## Множество клеток (Dictionary Vector2i -> true) из списка.
static func cell_set(cells: Array) -> Dictionary:
	var out := {}
	for c in cells:
		out[c] = true
	return out


## Цепочка `needle` встречается в `buffer` подряд и по порядку.
static func contains_contiguous(buffer: Array, needle: Array) -> bool:
	return index_of_contiguous(buffer, needle) >= 0


## Эффекты добычи: их цепочка засчитывается только после замка хранилища (breach.md 2.2). Остальные — где угодно в буфере.
const LOOT_EFFECTS: Array = ["EXTRACT_SHARD", "EXTRACT_DAEMON", "MINER"]


static func is_loot(effect: String) -> bool:
	return effect in LOOT_EFFECTS


## Индекс первого вхождения `needle` в `buffer` подряд и по порядку, начиная с `from`; -1 — нет (и для пустой цепочки).
static func index_of_contiguous(buffer: Array, needle: Array, from: int = 0) -> int:
	if needle.is_empty() or needle.size() > buffer.size():
		return -1
	for start in range(maxi(from, 0), buffer.size() - needle.size() + 1):
		var same := true
		for i in range(needle.size()):
			if buffer[start + i] != needle[i]:
				same = false
				break
		if same:
			return start
	return -1


## Индекс в `buffer`, с которого начинается «после замка»: конец первого полного совпадения замка; 0, если замка нет;
## -1, если замок не вскрыт. Ловушка в буфере (TRAP_SENTINEL) рвёт и цепочку замка.
static func lock_opened_at(buffer: Array, lock: Array) -> int:
	if lock.is_empty():
		return 0
	var start := index_of_contiguous(buffer, lock)
	return -1 if start < 0 else start + lock.size()


## Демоны (BreachDaemon), чья цепочка встретилась в буфере подряд и по порядку; id в порядке списка демонов.
## С замком (lock не пуст, breach.md 2.2) добычу (is_loot) засчитывает только цепочка, целиком лежащая после первого полного
## совпадения замка; остальные демоны (следы, Дрожь, дешифратор) — где угодно. Замок не вскрыт — добыча не засчитана.
## Без замка (умолчание) — как раньше: любая цепочка, где угодно.
static func resolve_daemons(buffer: Array, daemons: Array, lock: Array = []) -> Array[String]:
	var after_lock := lock_opened_at(buffer, lock)
	var out: Array[String] = []
	for d in daemons:
		var from := 0
		if is_loot(d.effect):
			if after_lock < 0:
				continue
			from = after_lock
		if index_of_contiguous(buffer, d.sequence, from) >= 0 and not out.has(d.id):
			out.append(d.id)
	return out


## SUCCESS — совпали все демоны (и они есть), PARTIAL — часть, FAIL — ни одного. matched_ids — множество id совпавших.
static func outcome(daemons: Array, matched_ids: Array) -> String:
	if not daemons.is_empty() and matched_ids.size() == daemons.size():
		return SUCCESS
	if not matched_ids.is_empty():
		return PARTIAL
	return FAIL

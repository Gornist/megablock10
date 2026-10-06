class_name BreachAutoSolver
extends RefCounted
## Перебор сетки для ботов и тестов (порт BreachAutoSolver): находит цепочку клеток, на которой совпадает как можно больше демонов
## (при равенстве — короче). Результат не мутирует попытку; уже выбранные клетки остаются началом пути.
##
## Отличия от Kotlin (там перебор в лоб с бюджетом 200 тыс. узлов — на GDScript на сетке 7x7 он не укладывается):
##  1. Сначала быстрый проход «точная цепочка»: сетка, которую построил генератор, содержит путь, на котором цепочки демонов идут подряд
##     без вставок, поэтому достаточно перебрать порядок демонов (и подмножества) и для каждого искать путь, где каждая клетка несёт
##     следующий нужный код. Ветвление там ~1, находит за миллисекунды. Ловушки в этом проходе не используются вовсе —
##     бот не поднимает trace зря. Работает, когда в попытке ещё ничего не выбрано.
##  2. Если полного набора так не собрать (буфер больше суммы цепочек и нужны вставки, частично выбранная попытка, демонов больше
##     пяти) — обычный перебор в глубину с бюджетом узлов: соседи упорядочены «сначала продолжающие цепочку демона», совпадения считаются
##     инкрементально, ветви отсекаются по верхней оценке. Лучшее из обоих проходов и возвращается.

const NODE_BUDGET := 200000
const MAX_EXACT_DAEMONS := 5


## Клетки по порядку, которые нужно тапнуть (вместе с уже выбранными в `start`). allow_traps=false — только пути без ловушек.
static func solve(start: BreachAttempt, allow_traps: bool = true) -> Array[Vector2i]:
	var best: Array[Vector2i] = start.selected.duplicate()
	var best_score := _score(start, best)
	var exact := _exact_chain(start)
	if not exact.is_empty():
		best = exact
		best_score = _score(start, exact)
		if _matched_count(start, exact) == start.daemons.size():
			return best
	var has_traps := not start.grid.trap_cells.is_empty()
	var passes: Array[bool] = [has_traps]  # true — обходить ловушки
	if has_traps and allow_traps:
		passes.append(false)
	for avoid in passes:
		var s := _Search.run(start, avoid)
		if s.best_score > best_score:
			best = s.best_path
			best_score = s.best_score
		if s.full:
			break
	return best


## Счёт пути как в Kotlin: совпавшие * 100 - длина.
static func _score(start: BreachAttempt, path: Array[Vector2i]) -> int:
	return _matched_count(start, path) * 100 - path.size()


static func _matched_count(start: BreachAttempt, path: Array[Vector2i]) -> int:
	var a := start.duplicate_attempt()
	a.selected = []
	for cell in path:
		a.selected.append(cell)
	return a.matched_daemon_ids().size()


# --- быстрый проход: точная цепочка ---

## Путь, на котором подряд идут цепочки демонов (все, а если не выходит — лучшее подмножество) и нет ловушек. Пусто — не нашли.
static func _exact_chain(start: BreachAttempt) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var n := start.daemons.size()
	if not start.selected.is_empty() or n == 0 or n > MAX_EXACT_DAEMONS:
		return none
	for size in range(n, 0, -1):
		var orders: Array = []
		_orders(range(n), size, [], orders)
		# Короче — раньше: при равном числе совпадений лучше меньший путь.
		var lengths: Dictionary = {}
		for o in orders:
			var total := start.grid.lock.size()   # замок хранилища идёт первой цепочкой пути (breach.md 2.1); без замка 0
			for i in o:
				total += start.daemons[i].length()
			lengths[o] = total
		orders.sort_custom(func(a, b): return lengths[a] < lengths[b])
		for o in orders:
			if lengths[o] > start.buffer_size:
				continue
			var req: Array[String] = []
			req.append_array(start.grid.lock)
			for i in o:
				req.append_array(start.daemons[i].sequence)
			var path: Array[Vector2i] = []
			if _chain(start.grid, req, path, {}):
				return path
	return none


## Все упорядоченные выборки по `size` индексов из `pool`.
static func _orders(pool: Array, size: int, current: Array, out: Array) -> void:
	if current.size() == size:
		out.append(current.duplicate())
		return
	for i in pool:
		if current.has(i):
			continue
		current.append(i)
		_orders(pool, size, current, out)
		current.pop_back()


static func _chain(grid: BreachGrid, req: Array, path: Array[Vector2i], visited: Dictionary) -> bool:
	var i := path.size()
	if i == req.size():
		return true
	var cands: Array[Vector2i] = []
	if i == 0:
		for c in range(grid.size):
			cands.append(Vector2i(0, c))
	else:
		cands = BreachRules.candidates_for(path[i - 1], BreachRules.next_link_dimension(i), grid.size, visited)
	for cell in cands:
		if grid.is_trap(cell) or grid.code_at(cell) != req[i]:
			continue
		path.append(cell)
		visited[cell] = true
		if _chain(grid, req, path, visited):
			return true
		visited.erase(cell)
		path.pop_back()
	return false


# --- общий перебор в глубину ---

## Один проход перебора.
class _Search:
	var attempt: BreachAttempt
	var avoid_traps := false
	var nodes := 0
	var best_path: Array[Vector2i] = []
	var best_score := -1
	var full := false
	var path: Array[Vector2i] = []
	var visited := {}
	var codes: Array[String] = []   # коды пути, на месте ловушек — маркер
	var matched := {}               # id -> true

	static func run(start: BreachAttempt, avoid_traps_: bool) -> _Search:
		var s := _Search.new()
		s.attempt = start
		s.avoid_traps = avoid_traps_
		s.path = start.selected.duplicate()
		s.visited = BreachRules.cell_set(start.selected)
		s.codes = start.match_codes()
		for id in start.matched_daemon_ids():
			s.matched[id] = true
		s._record()
		s._dfs()
		return s

	func _record() -> void:
		var sc := matched.size() * 100 - path.size()
		if sc > best_score:
			best_score = sc
			best_path = path.duplicate()
		full = not attempt.daemons.is_empty() and matched.size() == attempt.daemons.size()

	func _dfs() -> void:
		nodes += 1
		if nodes > BreachAutoSolver.NODE_BUDGET or full or path.size() >= attempt.buffer_size:
			return
		# Верхняя оценка: сколько ещё демонов можно успеть собрать в оставшиеся ячейки; хуже лучшего найденного — ветку не идём.
		var rem := attempt.buffer_size - path.size()
		var reachable := matched.size()
		for d in attempt.daemons:
			if not matched.has(d.id) and d.length() - _tail_progress(d) <= rem:
				reachable += 1
		if reachable * 100 - path.size() <= best_score:
			return
		var cands: Array[Vector2i]
		if path.is_empty():
			cands = []
			for c in range(attempt.grid.size):
				cands.append(Vector2i(0, c))
		else:
			cands = BreachRules.candidates_for(path[path.size() - 1], BreachRules.next_link_dimension(path.size()), attempt.grid.size, visited)
		var scored: Array = []
		for i in range(cands.size()):
			var cell: Vector2i = cands[i]
			if avoid_traps and attempt.grid.is_trap(cell):
				continue
			scored.append([_progress(cell), i, cell])
		scored.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
		for entry in scored:
			var cell: Vector2i = entry[2]
			var newly := _push(cell)
			_record()
			_dfs()
			_pop(cell, newly)
			if full or nodes > BreachAutoSolver.NODE_BUDGET:
				return

	## Длина самого длинного префикса цепочки демона (короче самой цепочки), которым заканчивается буфер.
	func _tail_progress(d: BreachDaemon) -> int:
		var seq: Array = d.sequence
		for k in range(mini(seq.size() - 1, codes.size()), 0, -1):
			var ok := true
			for j in range(k):
				if codes[codes.size() - k + j] != seq[j]:
					ok = false
					break
			if ok:
				return k
		return 0

	## Насколько клетка продвигает ближайшее несовпавшее: длина префикса цепочки демона, на которую заканчивается буфер с этой клеткой.
	## Ловушка рвёт цепочку — продвижения нет (-1, идёт последней).
	func _progress(cell: Vector2i) -> int:
		if attempt.grid.is_trap(cell):
			return -1
		var code := attempt.grid.code_at(cell)
		var best := 0
		for d in attempt.daemons:
			if matched.has(d.id):
				continue
			var seq: Array = d.sequence
			for k in range(mini(seq.size(), codes.size() + 1), best, -1):
				if seq[k - 1] != code:
					continue
				var ok := true
				for j in range(k - 1):
					if codes[codes.size() - (k - 1) + j] != seq[j]:
						ok = false
						break
				if ok:
					best = k
					break
		return best

	## Выбрать клетку; возвращает id демонов, совпавших именно этим шагом (для отката).
	func _push(cell: Vector2i) -> Array[String]:
		path.append(cell)
		visited[cell] = true
		codes.append(attempt.trap_sentinel() if attempt.grid.is_trap(cell) else attempt.grid.code_at(cell))
		var newly: Array[String] = []
		for d in attempt.daemons:
			if matched.has(d.id):
				continue
			var n: int = d.sequence.size()
			if n > codes.size():
				continue
			var same := true
			for j in range(n):
				if codes[codes.size() - n + j] != d.sequence[j]:
					same = false
					break
			if same:
				matched[d.id] = true
				newly.append(d.id)
		return newly

	func _pop(cell: Vector2i, newly: Array[String]) -> void:
		for id in newly:
			matched.erase(id)
		codes.pop_back()
		visited.erase(cell)
		path.pop_back()

extends GdUnitTestSuite
## Щуп сложности Взлома 2.0 на порте (breach.md, разделы 4 и 5): эталонная дека тира × SEEDS зёрен. Решатель берёт добычу всегда, «жадный» бот
## (смотрит на ход вперёд) и бот «3 хода» — в коридоре ниже. Приманки боты не замечают (видят только мёртвые клетки), так что бот «3 хода»
## слабее внимательного человека. Те же коридоры и боты, что у Kotlin-щупа `BreachDifficultyProbeTest` (:rules, 1000 зёрен); генераторы у
## Kotlin и Godot разные, поэтому доли совпадают не до единицы, а в пределах коридора. Правка параметров тира без правки коридора — красный
## щуп. Отдельный набор: 1000 зёрен на тир — около 20 с на devbox (200 зёрен — 4 с; карточка допускала до +60 с).
## Доля — «добыча засчитана по правилам замка» (вскрытие, потом цепочка).

const SEEDS := 1000
const DEPTH := 3
const LOOT_WEIGHT := 10000
const CHAIN_WEIGHT := 100
const TIERS := ["BASE", "HARD", "NIGHTMARE"]
## Коридор в процентах (breach.md, раздел 4): [мин, макс] доли успеха жадного бота и бота «3 хода».
const CORRIDOR := {
	"BASE": {"greedy": [65, 100], "thinker": [85, 100]},
	"HARD": {"greedy": [30, 60], "thinker": [60, 100]},
	"NIGHTMARE": {"greedy": [0, 30], "thinker": [40, 100]},
}

var _data: BreachData


func before_test() -> void:
	BreachData.reset_shared()
	_data = BreachData.shared()


func after_test() -> void:
	BreachData.reset_shared()


## Эталонная дека тира — один демон Извлечения с цепочкой 2 / 3 / 4 (breach.md 6.1); буфер — «замок + демон + запас тира».
func _reference_rates(tier: String, with_lock: bool = true) -> Dictionary:
	var p := _data.tier_params(tier)
	var length := 1 + TIERS.find(tier) + 1   # 1 + уровень тира: цепочка 2 / 3 / 4
	var lock_length := int(p["lock_length"]) if with_lock else 0
	var buffer := _data.buffer_size(tier, 99, lock_length, length)
	return _probe(p, length, lock_length, buffer)


func _probe(p: Dictionary, daemon_len: int, lock_length: int, buffer_size: int) -> Dictionary:
	var solver := 0
	var greedy := 0
	var thinker := 0
	var traps := {"dead_cells": p["dead_cells"], "corrupted_codes": p["corrupted_codes"], "lock_traps": p["lock_traps"]}
	for seed_value in range(1, SEEDS + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var seq: Array = []
		for _i in range(daemon_len):
			seq.append(_data.alphabet[rng.randi_range(0, _data.alphabet.size() - 1)])
		var loot := BreachDaemon.make("d0", seq, "EXTRACT_SHARD", 1, "d0")
		var daemons: Array = [loot]
		var grid := BreachGrid.generate(int(p["grid_size"]), daemons, rng, _data, traps, lock_length)
		var start := BreachAttempt.make(grid, daemons, buffer_size, _data)
		var targets: Array = []
		if not grid.lock.is_empty():
			targets.append(grid.lock)
		targets.append(seq)
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = seed_value + 7000003

		var solved := BreachAttempt.make(grid, daemons, buffer_size, _data)
		for c in BreachAutoSolver.solve(start):
			solved.select(c)
		if solved.matched_daemon_ids().size() == daemons.size():
			solver += 1
		if loot.id in _greedy_bot(start.duplicate_attempt(), targets, bot_rng).matched_daemon_ids():
			greedy += 1
		if loot.id in _thinker_bot(start.duplicate_attempt(), targets, loot, bot_rng).matched_daemon_ids():
			thinker += 1
	return {"solver": solver * 100 / SEEDS, "greedy": greedy * 100 / SEEDS, "thinker": thinker * 100 / SEEDS}


## Где доля вышла из коридора тира: пустой список — в коридоре. Решатель обязан быть 100 % (если его запускали: solver >= 0).
func _violations(tier: String, r: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var c: Dictionary = CORRIDOR[tier]
	if int(r["solver"]) in range(0, 100):
		out.append("решатель %d %% вместо 100 %%" % int(r["solver"]))
	for bot in ["greedy", "thinker"]:
		var lo := int((c[bot] as Array)[0])
		var hi := int((c[bot] as Array)[1])
		if int(r[bot]) < lo or int(r[bot]) > hi:
			out.append("%s %d %% вне %d..%d" % [bot, int(r[bot]), lo, hi])
	return out


func test_reference_decks_stay_in_the_corridor() -> void:
	var t0 := Time.get_ticks_msec()
	var broken: Array[String] = []
	for tier in TIERS:
		var r := _reference_rates(tier)
		print("щуп %s: решатель %d %%, жадный %d %%, «3 хода» %d %% (зёрен %d)" % [tier, r["solver"], r["greedy"], r["thinker"], SEEDS])
		for v in _violations(tier, r):
			broken.append("%s: %s" % [tier, v])
	print("щуп: %d мс" % (Time.get_ticks_msec() - t0))
	assert_array(broken).override_failure_message("сложность вне коридора breach.md 4: %s" % [broken]).is_empty()


## Только замок снимаем с новых параметров тира: без него жадный бот снова берёт добычу слишком часто — замок и есть рычаг.
func test_new_tier_params_without_the_lock_break_the_corridor() -> void:
	var broken: Array[String] = []
	for tier in ["HARD", "NIGHTMARE"]:
		var r := _reference_rates(tier, false)
		print("щуп без замка %s: решатель %d %%, жадный %d %%, «3 хода» %d %%" % [tier, r["solver"], r["greedy"], r["thinker"]])
		if not _violations(tier, r).is_empty():
			broken.append(tier)
	assert_array(broken).override_failure_message("без замка должны краснеть HARD и NIGHTMARE, красные: %s" % [broken]).is_equal(["HARD", "NIGHTMARE"])


# --- боты ---

## Клетки, которые видит игрок как допустимые: мёртвые (××) обходит, приманки от обычных кодов не отличает.
func _visible_moves(a: BreachAttempt) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in a.selectable_cells():
		if a.grid.code_at(c) != _data.dead_marker:
			out.append(c)
	return out


## Цели, ещё не лежащие в буфере подряд.
func _todo(buffer: Array, targets: Array) -> Array:
	var out: Array = []
	for t in targets:
		if not BreachRules.contains_contiguous(buffer, t):
			out.append(t)
	return out


## Длина самого длинного хвоста буфера, который является началом цепочки (но не ею целиком).
func _tail_progress(buffer: Array, chain: Array) -> int:
	for n in range(mini(chain.size() - 1, buffer.size()), 0, -1):
		var ok := true
		for i in range(n):
			if buffer[buffer.size() - n + i] != chain[i]:
				ok = false
				break
		if ok:
			return n
	return 0


## Жадный: ближайшая несобранная цель, клетка со следующим нужным кодом (иначе — с её первым кодом, иначе любая).
func _greedy_bot(a: BreachAttempt, targets: Array, rng: RandomNumberGenerator) -> BreachAttempt:
	while not a.is_full():
		var moves := _visible_moves(a)
		var buffer := a.match_codes()
		var todo := _todo(buffer, targets)
		if moves.is_empty() or todo.is_empty():
			break
		var target: Array = todo[0]
		var k := _tail_progress(buffer, target)
		var good: Array[Vector2i] = []
		for m in moves:
			if a.grid.code_at(m) == target[k]:
				good.append(m)
		if good.is_empty() and k > 0:
			for m in moves:
				if a.grid.code_at(m) == target[0]:
					good.append(m)
		var pool: Array[Vector2i] = good if not good.is_empty() else moves
		a.select(pool[rng.randi_range(0, pool.size() - 1)])
	return a


## Думающий: перебирает DEPTH хода вперёд, приманок не замечает (в расчёте код приманки — обычный код).
func _thinker_bot(a: BreachAttempt, targets: Array, loot: BreachDaemon, rng: RandomNumberGenerator) -> BreachAttempt:
	var grid := a.grid
	while not a.is_full() and not (_loot_ok(a.match_codes(), loot, grid) and _todo(a.match_codes(), targets).is_empty()):
		var path := a.selected.duplicate()
		var visited := BreachRules.cell_set(path)
		var base := a.match_codes()
		var pick := Vector2i(-1, -1)
		var pick_score := -1.0
		for m in _think_moves(path, visited, grid):
			var next_buffer := base.duplicate()
			next_buffer.append(grid.code_at(m))
			var next_path := path.duplicate()
			next_path.append(m)
			var next_visited := visited.duplicate()
			next_visited[m] = true
			var sc := float(_best(next_path, next_visited, next_buffer, DEPTH - 1, a.buffer_size, targets, loot, grid)) + rng.randf()
			if sc > pick_score:
				pick_score = sc
				pick = m
		if pick.x < 0:
			break
		a.select(pick)
	return a


func _loot_ok(buffer: Array, loot: BreachDaemon, grid: BreachGrid) -> bool:
	return loot.id in BreachRules.resolve_daemons(buffer, [loot], grid.lock)


func _score(buffer: Array, targets: Array, loot: BreachDaemon, grid: BreachGrid) -> int:
	var todo := _todo(buffer, targets)
	var progress := 0 if todo.is_empty() else _tail_progress(buffer, todo[0])
	return (LOOT_WEIGHT if _loot_ok(buffer, loot, grid) else 0) + (targets.size() - todo.size()) * CHAIN_WEIGHT + progress


func _think_moves(path: Array, visited: Dictionary, grid: BreachGrid) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if path.is_empty():
		for c in range(grid.size):
			cells.append(Vector2i(0, c))
	else:
		cells = BreachRules.candidates_for(path[path.size() - 1], BreachRules.next_link_dimension(path.size()), grid.size, visited)
	var out: Array[Vector2i] = []
	for c in cells:
		if grid.code_at(c) != _data.dead_marker:
			out.append(c)
	return out


func _best(path: Array, visited: Dictionary, buffer: Array, depth: int, buffer_size: int, targets: Array, loot: BreachDaemon, grid: BreachGrid) -> int:
	var sc := _score(buffer, targets, loot, grid)
	if depth == 0 or buffer.size() >= buffer_size or sc >= LOOT_WEIGHT:
		return sc
	var top := sc
	for m in _think_moves(path, visited, grid):
		var next_buffer := buffer.duplicate()
		next_buffer.append(grid.code_at(m))
		var next_path := path.duplicate()
		next_path.append(m)
		var next_visited := visited.duplicate()
		next_visited[m] = true
		top = maxi(top, _best(next_path, next_visited, next_buffer, depth - 1, buffer_size, targets, loot, grid))
	return top

extends GdUnitTestSuite
## Проигрыватель golden-набора поведения (docs/netrun-deck-design.md, §10.4): Kotlin-тест :rules (BreachGoldenTest, задача К0) выгружает
## tests/fixtures/breach_golden.json — правила телефона, а этот тест проигрывает их порту. Разошлись — красный gdUnit; файл меняет
## только Kotlin (UPDATE_NETRUN_JSON=1), руками не править.
##
## Формат (format 1), клетка — [строка, столбец]:
##   link_rule:     [{selected_count, next}]                     — чередование строка/столбец
##   resolve_cases: [{buffer: [код], daemons: [{id, name, sequence, tier, effect}], matched: [id]}]
##   timer_cases:   [{timer_sec, events: [{seconds_left, event}]}] — события реплик на каждой секунде таймера (time_event)
##   attempts:      [{name, mode: breach|decrypt, tier, grid_size, timer_sec, buffer_size, daemons, cells, trap_cells, start_selectable,
##                    steps: [{cell, selectable_before, hit_trap, matched_new, matched_ids, buffer_codes, is_full, selectable_after}],
##                    outcome, matched_ids, selectable_after_resolve}]
## Сетки в golden готовые (генераторы Kotlin и Godot разные): проверяются правила, а не случайные числа.

const GOLDEN_PATH := "res://tests/fixtures/breach_golden.json"

var _golden: Dictionary


func before_test() -> void:
	BreachData.reset_shared()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	_golden = parsed if parsed is Dictionary else {}


func after_test() -> void:
	BreachData.reset_shared()


func test_golden_file_is_present_and_parsed() -> void:
	assert_bool(FileAccess.file_exists(GOLDEN_PATH)).is_true()
	assert_int(int(_golden.get("format", 0))).is_equal(1)
	assert_bool((_golden["attempts"] as Array).size() > 0).is_true()


func test_port_replays_kotlin_golden() -> void:
	var errors := _play(_golden)
	assert_array(errors).override_failure_message("golden разошёлся с портом:\n" + "\n".join(errors)).is_empty()


func test_player_catches_a_wrong_expectation() -> void:
	# Проигрыватель сам должен краснеть на расхождении, иначе golden ничего не охраняет.
	for key in ["link_rule", "resolve_cases", "timer_cases", "attempts"]:
		var broken: Dictionary = _golden.duplicate(true)
		match key:
			"link_rule":
				broken[key][0]["next"] = "ROW"
			"resolve_cases":
				broken[key][0]["matched"] = ["нет_такого"]
			"timer_cases":
				broken[key][3]["events"][0]["event"] = "TRAP"
			"attempts":
				broken[key][0]["outcome"] = "FAIL"
		assert_bool(_play(broken).size() > 0).override_failure_message("правка раздела %s не замечена" % key).is_true()


# --- проигрыватель ---

## Проигрывает набор, возвращает список расхождений (пусто — совпало).
func _play(golden: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var data := BreachData.shared()
	for row in golden.get("link_rule", []):
		var got := BreachRules.next_link_dimension(int(row["selected_count"]))
		if got != str(row["next"]):
			errors.append("link_rule(%s): %s, ожидалось %s" % [row["selected_count"], got, row["next"]])
	for row in golden.get("resolve_cases", []):
		var ds := _daemons(row["daemons"])
		var got := BreachRules.resolve_daemons(_strings(row["buffer"]), ds)
		got.sort()
		if got != _sorted(_strings(row["matched"])):
			errors.append("resolve(%s): %s, ожидалось %s" % [row["buffer"], got, row["matched"]])
	for row in golden.get("timer_cases", []):
		errors.append_array(_play_timer(row, data))
	for a in golden.get("attempts", []):
		errors.append_array(_play_attempt(a, data))
	return errors


func _play_timer(row: Dictionary, data: BreachData) -> Array[String]:
	var errors: Array[String] = []
	var timer := int(row["timer_sec"])
	var expected := {}
	for e in row["events"]:
		expected[int(e["seconds_left"])] = str(e["event"])
	var actual := {}
	var attempt := BreachAttempt.make(BreachGrid.new(), [], 0, data)
	var run := BreachRun.from_attempt(attempt, timer, "BASE", BreachRun.MODE_STORAGE, 0, data)
	for left in range(timer, -1, -1):
		run.seconds_left = left
		var ev := run.time_event()
		if ev != "":
			actual[left] = ev
	if actual != expected:
		errors.append("timer %d: события %s, ожидалось %s" % [timer, actual, expected])
	return errors


func _play_attempt(a: Dictionary, data: BreachData) -> Array[String]:
	var errors: Array[String] = []
	var name := str(a["name"])
	var grid := BreachGrid.new()
	grid.size = int(a["grid_size"])
	grid.dead_marker = data.dead_marker
	for row in a["cells"]:
		grid.cells.append(_strings(row))
	for c in _cells(a["trap_cells"]):
		grid.trap_cells[c] = true
	var ds := _daemons(a["daemons"])
	var run := BreachRun.from_attempt(BreachAttempt.make(grid, ds, int(a["buffer_size"]), data), int(a["timer_sec"]), str(a["tier"]),
			BreachRun.MODE_DECRYPT if a["mode"] == "decrypt" else BreachRun.MODE_STORAGE, 0, data)
	if _keys(run.selectable()) != _keys(_cells(a["start_selectable"])):
		errors.append("%s: старт — доступно %s, ожидалось %s" % [name, _keys(run.selectable()), _keys(_cells(a["start_selectable"]))])
	var i := 0
	for st in a["steps"]:
		var at := "%s, шаг %d %s" % [name, i, st["cell"]]
		i += 1
		if _keys(run.selectable()) != _keys(_cells(st["selectable_before"])):
			errors.append("%s: до шага доступно %s, ожидалось %s" % [at, _keys(run.selectable()), _keys(_cells(st["selectable_before"]))])
		var tap := run.tap(_cell(st["cell"]))
		if not tap["ok"]:
			errors.append("%s: шаг не принят портом" % at)
			continue
		if tap["hit_trap"] != bool(st["hit_trap"]):
			errors.append("%s: ловушка=%s, ожидалось %s" % [at, tap["hit_trap"], st["hit_trap"]])
		if tap["matched"] != bool(st["matched_new"]):
			errors.append("%s: matched_new=%s, ожидалось %s" % [at, tap["matched"], st["matched_new"]])
		var ids := run.attempt.matched_daemon_ids()
		ids.sort()
		if ids != _sorted(_strings(st["matched_ids"])):
			errors.append("%s: совпало %s, ожидалось %s" % [at, ids, st["matched_ids"]])
		if run.attempt.buffer_codes() != _strings(st["buffer_codes"]):
			errors.append("%s: буфер %s, ожидалось %s" % [at, run.attempt.buffer_codes(), st["buffer_codes"]])
		if run.attempt.is_full() != bool(st["is_full"]):
			errors.append("%s: is_full=%s, ожидалось %s" % [at, run.attempt.is_full(), st["is_full"]])
		if _keys(run.selectable()) != _keys(_cells(st["selectable_after"])):
			errors.append("%s: после шага доступно %s, ожидалось %s" % [at, _keys(run.selectable()), _keys(_cells(st["selectable_after"]))])
	run.resolve()  # по таймеру или досрочно; если буфер уже полон, итог поставлен самим тапом
	var info := run.result_info()
	if str(info["outcome"]) != str(a["outcome"]):
		errors.append("%s: исход %s, ожидалось %s" % [name, info["outcome"], a["outcome"]])
	var matched: Array = info["matched"]
	matched.sort()
	if matched != _sorted(_strings(a["matched_ids"])):
		errors.append("%s: итог — совпало %s, ожидалось %s" % [name, matched, a["matched_ids"]])
	if _keys(run.selectable()) != _keys(_cells(a["selectable_after_resolve"])):
		errors.append("%s: после итога доступно %s, ожидалось %s" % [name, _keys(run.selectable()), _keys(_cells(a["selectable_after_resolve"]))])
	return errors


static func _daemons(list: Variant) -> Array:
	var out: Array = []
	for d in list:
		out.append(BreachDaemon.from_dict(d))
	return out


static func _cell(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


static func _cells(list: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a in list:
		out.append(_cell(a))
	return out


## Клетки как отсортированные строки «r,c» — для сравнения без учёта порядка.
static func _keys(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append("%03d,%03d" % [c.x, c.y])
	out.sort()
	return out


static func _strings(list: Variant) -> Array[String]:
	var out: Array[String] = []
	for x in list:
		out.append(str(x))
	return out


static func _sorted(list: Array) -> Array:
	var out := list.duplicate()
	out.sort()
	return out

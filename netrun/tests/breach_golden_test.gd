extends GdUnitTestSuite
## Проигрыватель golden-наборов поведения (docs/netrun-deck-design.md, §10.4): Kotlin-тест :rules (задача К0) выгружает
## tests/fixtures/breach_golden.json, этот тест проигрывает его порту. Файла нет — проверка файла молча пропускается и включится
## сама, когда он появится; сам проигрыватель всё это время проверяется встроенным мини-набором (_MINI), посчитанным вручную.
##
## Формат (version 1), все разделы необязательны. Клетка — [строка, столбец], списки клеток сравниваются без учёта порядка:
##   "link_dimension": [{"selected_count": 1, "dimension": "COLUMN"}, ...]
##   "candidates":     [{"from": [r, c], "dimension": "ROW", "size": 5, "visited": [[r, c], ...], "candidates": [[r, c], ...]}]
##   "outcomes":       [{"daemons": 2, "matched": 1, "outcome": "PARTIAL"}]
##   "timer_events":   [{"timer_sec": 60, "seconds_left": 30, "event": "HALF_TIME" | null, "low_time": false, "warning": false}]
##   "cases":          [{"name": "...",
##                       "grid": {"size": 3, "cells": [[...]], "traps": [[r, c]]},
##                       "daemons": [{"id": "a", "sequence": ["55", "7A"], "name"?, "effect"?, "tier"?}],
##                       "buffer": 6,
##                       "steps": [{"cell": [r, c], "selectable_before": [[r, c]...], "accepted": true,
##                                  "hit_trap": false, "matched": ["a"], "selectable_after"?: [[r, c]...]}],
##                       "final": {"outcome": "SUCCESS", "matched": ["a"]}}]
## accepted=false — шаг, который порт обязан отвергнуть (клетка недоступна); тогда hit_trap/matched не проверяются.

const GOLDEN_PATH := "res://tests/fixtures/breach_golden.json"

const _MINI := {
	"version": 1,
	"link_dimension": [
		{"selected_count": 1, "dimension": "COLUMN"},
		{"selected_count": 2, "dimension": "ROW"},
		{"selected_count": 3, "dimension": "COLUMN"},
	],
	"candidates": [
		{"from": [3, 2], "dimension": "COLUMN", "size": 4, "visited": [[0, 2], [3, 2]], "candidates": [[1, 2], [2, 2]]},
		{"from": [1, 1], "dimension": "ROW", "size": 3, "visited": [[1, 1]], "candidates": [[1, 0], [1, 2]]},
	],
	"outcomes": [
		{"daemons": 2, "matched": 2, "outcome": "SUCCESS"},
		{"daemons": 2, "matched": 1, "outcome": "PARTIAL"},
		{"daemons": 2, "matched": 0, "outcome": "FAIL"},
		{"daemons": 0, "matched": 0, "outcome": "FAIL"},
	],
	"timer_events": [
		{"timer_sec": 60, "seconds_left": 30, "event": "HALF_TIME", "low_time": false, "warning": false},
		{"timer_sec": 60, "seconds_left": 10, "event": "LOW_TIME", "low_time": true, "warning": false},
		{"timer_sec": 60, "seconds_left": 29, "event": null, "low_time": false, "warning": false},
		{"timer_sec": 60, "seconds_left": 5, "event": null, "low_time": true, "warning": true},
		{"timer_sec": 60, "seconds_left": 0, "event": null, "low_time": false, "warning": false},
		{"timer_sec": 20, "seconds_left": 10, "event": null, "low_time": true, "warning": false},
		{"timer_sec": 21, "seconds_left": 10, "event": "LOW_TIME", "low_time": true, "warning": false},
	],
	# Сетка 3x3, ловушка в (2,1):  1C 55 BD / E9 7A FF / 1C 55 BD
	"cases": [
		{
			"name": "мини: два шага собирают демона, третий недоступен",
			"grid": {"size": 3, "cells": [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]], "traps": [[2, 1]]},
			"daemons": [{"id": "a", "sequence": ["55", "7A"]}],
			"buffer": 6,
			"steps": [
				{"cell": [1, 1], "accepted": false, "selectable_before": [[0, 0], [0, 1], [0, 2]]},
				{"cell": [0, 1], "accepted": true, "selectable_before": [[0, 0], [0, 1], [0, 2]], "hit_trap": false, "matched": [], "selectable_after": [[1, 1], [2, 1]]},
				{"cell": [1, 1], "accepted": true, "selectable_before": [[1, 1], [2, 1]], "hit_trap": false, "matched": ["a"], "selectable_after": [[1, 0], [1, 2]]},
				{"cell": [2, 2], "accepted": false, "selectable_before": [[1, 0], [1, 2]]},
			],
			"final": {"outcome": "SUCCESS", "matched": ["a"]},
		},
		{
			"name": "мини: ловушка рвёт цепочку, хотя код подходит",
			"grid": {"size": 3, "cells": [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]], "traps": [[2, 1]]},
			"daemons": [{"id": "a", "sequence": ["55", "55"]}],
			"buffer": 6,
			"steps": [
				{"cell": [0, 1], "accepted": true, "matched": []},
				{"cell": [2, 1], "accepted": true, "hit_trap": true, "matched": [], "selectable_after": [[2, 0], [2, 2]]},
			],
			"final": {"outcome": "FAIL", "matched": []},
		},
		{
			"name": "мини: полный буфер, часть демонов",
			"grid": {"size": 3, "cells": [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]], "traps": []},
			"daemons": [{"id": "a", "sequence": ["55", "7A"]}, {"id": "b", "sequence": ["FF", "1C"]}],
			"buffer": 2,
			"steps": [
				{"cell": [0, 1], "accepted": true, "matched": []},
				{"cell": [1, 1], "accepted": true, "matched": ["a"], "selectable_after": []},
			],
			"final": {"outcome": "PARTIAL", "matched": ["a"]},
		},
	],
}


func before_test() -> void:
	BreachData.reset_shared()


func after_test() -> void:
	BreachData.reset_shared()


func test_player_runs_the_builtin_mini_golden() -> void:
	var errors := _play(_MINI)
	assert_array(errors).is_empty()


func test_player_catches_a_wrong_expectation() -> void:
	# Проигрыватель сам должен краснеть на расхождении, иначе golden ничего не охраняет.
	var broken: Dictionary = _MINI.duplicate(true)
	broken["cases"][0]["final"]["outcome"] = "FAIL"
	broken["outcomes"][1]["outcome"] = "SUCCESS"
	broken["timer_events"][0]["event"] = "LOW_TIME"
	assert_bool(_play(broken).size() >= 3).is_true()


## Настоящий golden от Kotlin (К0). Нет файла — пропуск; появился — включается без правок.
func test_kotlin_golden_file() -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		print("[breach_golden] пропуск: нет %s (его выгрузит задача К0)" % GOLDEN_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	assert_bool(parsed is Dictionary).override_failure_message("golden: не разобрать JSON").is_true()
	var errors := _play(parsed)
	assert_array(errors).override_failure_message("golden разошёлся с портом:\n" + "\n".join(errors)).is_empty()


# --- проигрыватель ---

## Проигрывает набор, возвращает список расхождений (пусто — совпало).
func _play(golden: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var data := BreachData.shared()
	for row in golden.get("link_dimension", []):
		var got := BreachRules.next_link_dimension(int(row["selected_count"]))
		if got != str(row["dimension"]):
			errors.append("link_dimension(%s): %s, ожидалось %s" % [row["selected_count"], got, row["dimension"]])
	for row in golden.get("candidates", []):
		var visited := BreachRules.cell_set(_cells(row["visited"]))
		var got := BreachRules.candidates_for(_cell(row["from"]), str(row["dimension"]), int(row["size"]), visited)
		if _key_list(got) != _key_list(_cells(row["candidates"])):
			errors.append("candidates(from=%s %s): %s, ожидалось %s" % [row["from"], row["dimension"], _key_list(got), _key_list(_cells(row["candidates"]))])
	for row in golden.get("outcomes", []):
		var ds: Array = []
		var ids: Array = []
		for i in range(int(row["daemons"])):
			ds.append(BreachDaemon.make("d%d" % i, ["1C"]))
		for i in range(int(row["matched"])):
			ids.append("d%d" % i)
		var got := BreachRules.outcome(ds, ids)
		if got != str(row["outcome"]):
			errors.append("outcome(%s из %s): %s, ожидалось %s" % [row["matched"], row["daemons"], got, row["outcome"]])
	for row in golden.get("timer_events", []):
		var run := _timer_run(int(row["timer_sec"]), data)
		run.seconds_left = int(row["seconds_left"])
		var want_event := "" if row.get("event") == null else str(row["event"])
		if run.time_event() != want_event:
			errors.append("timer %s/%s: событие «%s», ожидалось «%s»" % [row["seconds_left"], row["timer_sec"], run.time_event(), want_event])
		if run.is_low_time() != bool(row["low_time"]) or run.is_warning() != bool(row["warning"]):
			errors.append("timer %s/%s: low=%s warning=%s, ожидалось %s/%s" % [row["seconds_left"], row["timer_sec"], run.is_low_time(), run.is_warning(), row["low_time"], row["warning"]])
	for c in golden.get("cases", []):
		errors.append_array(_play_case(c, data))
	return errors


func _timer_run(timer_sec: int, data: BreachData) -> BreachRun:
	var run := BreachRun.for_storage("BASE", [BreachDaemon.make("t", ["1C", "55"])], 6, 1, data)
	run.timer_sec = timer_sec
	run.seconds_left = timer_sec
	return run


func _play_case(c: Dictionary, data: BreachData) -> Array[String]:
	var errors: Array[String] = []
	var case_name := str(c.get("name", "?"))
	var grid := BreachGrid.from_dict(c["grid"])
	var daemons: Array = []
	for d in c["daemons"]:
		daemons.append(BreachDaemon.from_dict(d))
	var attempt := BreachAttempt.make(grid, daemons, int(c["buffer"]), data)
	var step_no := 0
	for st in c.get("steps", []):
		step_no += 1
		var where := "%s, шаг %d %s" % [case_name, step_no, st["cell"]]
		if st.has("selectable_before") and _key_list(attempt.selectable_cells()) != _key_list(_cells(st["selectable_before"])):
			errors.append("%s: доступно %s, ожидалось %s" % [where, _key_list(attempt.selectable_cells()), _key_list(_cells(st["selectable_before"]))])
		var accepted := attempt.select(_cell(st["cell"]))
		if accepted != bool(st.get("accepted", true)):
			errors.append("%s: принят=%s, ожидалось %s" % [where, accepted, st.get("accepted", true)])
			continue
		if not accepted:
			continue
		if st.has("hit_trap") and grid.is_trap(_cell(st["cell"])) != bool(st["hit_trap"]):
			errors.append("%s: ловушка=%s, ожидалось %s" % [where, grid.is_trap(_cell(st["cell"])), st["hit_trap"]])
		if st.has("matched") and _sorted(attempt.matched_daemon_ids()) != _sorted(_strings(st["matched"])):
			errors.append("%s: совпало %s, ожидалось %s" % [where, attempt.matched_daemon_ids(), st["matched"]])
		if st.has("selectable_after") and _key_list(attempt.selectable_cells()) != _key_list(_cells(st["selectable_after"])):
			errors.append("%s: после шага доступно %s, ожидалось %s" % [where, _key_list(attempt.selectable_cells()), _key_list(_cells(st["selectable_after"]))])
	var fin: Dictionary = c.get("final", {})
	var matched := attempt.matched_daemon_ids()
	if fin.has("matched") and _sorted(matched) != _sorted(_strings(fin["matched"])):
		errors.append("%s: итог — совпало %s, ожидалось %s" % [case_name, matched, fin["matched"]])
	if fin.has("outcome"):
		var got := BreachRules.outcome(daemons, matched)
		if got != str(fin["outcome"]):
			errors.append("%s: исход %s, ожидалось %s" % [case_name, got, fin["outcome"]])
	return errors


static func _cell(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


static func _cells(list: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a in list:
		out.append(_cell(a))
	return out


## Клетки как отсортированные строки «r,c» — для сравнения без учёта порядка.
static func _key_list(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append("%d,%d" % [c.x, c.y])
	out.sort()
	return out


static func _strings(list: Variant) -> Array:
	var out: Array = []
	for x in list:
		out.append(str(x))
	return out


static func _sorted(list: Array) -> Array:
	var out := list.duplicate()
	out.sort()
	return out

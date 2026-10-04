class_name BreachMirror
extends RefCounted
## Клиентская копия попытки взлома хранилища (К3): та же сетка и то же правило строка/столбец, что у сервера (shared/breach), поэтому доступные клетки
## подсвечиваются сразу, без ожидания ответа. Сервер подтверждает каждый тап: принятый остаётся, отклонённый откатывается. Чистые данные, без сцены.
## Что сервер не выдаёт: порченые коды (ловушки среди обычных кодов) — клиент о них не знает, пока сервер не скажет `trap` в ответе на тап.

var vault := ""
var n := 0
var tier := "BASE"
var mode := BreachRun.MODE_STORAGE
var grid: BreachGrid
var attempt: BreachAttempt
## Цели: [{id, name, effect, cells}] — демоны, выбранные во взлом.
var targets: Array = []
var buffer_size := 0
var timer_sec := 0
var left := 0
## id совпавших демонов по последнему ответу сервера.
var matched: Array = []
## Клетки, о которых сервер сказал «ловушка» (включая порченые, которых в сетке нет).
var trap_hits: Dictionary = {}
## Тап, отправленный и ещё не подтверждённый (Vector2i), или null.
var pending: Variant = null
var ice_line := ""
var finished := false
var result: Dictionary = {}


## Из события `bk` сервера. null — событие негодное (нет сетки или целей).
static func from_event(ev: Dictionary) -> BreachMirror:
	var g_raw: Variant = ev.get("grid")
	if not (g_raw is Dictionary):
		return null
	var m := BreachMirror.new()
	m.vault = str(ev.get("vault", ""))
	m.n = int(ev.get("n", 0))
	m.tier = str(ev.get("tier", "BASE"))
	m.mode = str(ev.get("mode", BreachRun.MODE_STORAGE))
	m.buffer_size = int(ev.get("buffer", 0))
	m.timer_sec = int(ev.get("sec", 0))
	m.left = m.timer_sec
	m.ice_line = str(ev.get("ice", ""))
	m.grid = BreachGrid.from_dict(g_raw)
	var daemons: Array = []
	for t in ev.get("targets", []):
		var d := BreachDaemon.from_dict({"id": t.get("id", ""), "cells": t.get("cells", []), "effect": t.get("effect", ""), "name": t.get("name", "")})
		if d == null:
			continue
		daemons.append(d)
		m.targets.append({"id": d.id, "name": d.display_name, "effect": d.effect, "cells": d.sequence.duplicate()})
	if m.grid.size < 2 or daemons.is_empty():
		return null
	m.attempt = BreachAttempt.make(m.grid, daemons, m.buffer_size, BreachData.shared())
	return m


## Клетки, которые можно нажать сейчас: нет итога и нет неподтверждённого тапа (пока сервер не ответил, второй не отправляем).
func selectable() -> Array[Vector2i]:
	if finished or pending != null:
		var none: Array[Vector2i] = []
		return none
	return attempt.selectable_cells()


func can_tap(cell: Vector2i) -> bool:
	return selectable().has(cell)


## Нажать клетку: если можно — выбрана у нас сразу и ждёт подтверждения. false — нельзя (ничего не изменилось, серверу не слать).
func tap(cell: Vector2i) -> bool:
	if not can_tap(cell):
		return false
	attempt.select(cell)
	pending = cell
	return true


func selected() -> Array[Vector2i]:
	return attempt.selected


## Код выбранной клетки в буфере (для показа).
func buffer_codes() -> Array[String]:
	return attempt.buffer_codes()


## Ответ сервера `bk_tick`: с cell — подтверждение или отказ тапа; без cell — только время и реплика.
func apply_tick(ev: Dictionary) -> void:
	left = int(ev.get("left", left))
	if ev.has("matched"):
		matched.clear()
		for id in ev["matched"]:
			matched.append(str(id))
	if str(ev.get("ice", "")) != "":
		ice_line = str(ev["ice"])
	var c: Variant = ev.get("cell")
	if c is Array and (c as Array).size() == 2 and pending != null:
		var cell := Vector2i(int(c[0]), int(c[1]))
		if cell == pending:
			pending = null
			if not bool(ev.get("ok", false)):
				attempt.selected.pop_back()   # сервер не принял: подсветка возвращается
			elif bool(ev.get("trap", false)):
				trap_hits[cell] = true


## Итог (`bk_end`): после него нажимать нечего.
func apply_end(ev: Dictionary) -> void:
	finished = true
	pending = null
	result = ev
	if ev.has("matched"):
		matched.clear()
		for id in ev["matched"]:
			matched.append(str(id))


func is_matched(id: String) -> bool:
	return matched.has(id)

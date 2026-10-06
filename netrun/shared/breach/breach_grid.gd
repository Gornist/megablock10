class_name BreachGrid
extends RefCounted
## Сетка кодов и её генератор (порт BreachGrid и generateGrid из app/.../breach/BreachEngine.kt).
##
## generate строит ГАРАНТИРОВАННО решаемую сетку: сначала прокладывает допустимый путь (по BreachRules, от верхней строки) длиной ровно
## в сумму цепочек демонов, вписывает их коды подряд вдоль пути и только остальные клетки заполняет случайно. Пройти этим путём
## значит собрать в буфере все цепочки одну за другой. Ловушки (мёртвые клетки и порченые коды) кладутся только ВНЕ пути, поэтому
## решаемость от них не зависит. Конкретные сетки с Kotlin не совпадают (другой генератор случайных чисел) — совпадают правила.
## Взлом 2.0 (docs/gamedesign/breach.md, 2.1 и 2.4): с замком (lock_length > 0) путь = замок, затем цепочки демонов; приманки
## ставятся по lock_traps на клетки с кодом из целей, сначала на строках и столбцах пути. Без замка — всё как раньше.
##
## Клетка — Vector2i(x = строка, y = столбец).

var size := 0
## Замок хранилища: цепочка кодов, после которой засчитывается добыча (BreachRules.resolve_daemons). Пусто — без замка.
## Замок открыт клиенту (он его показывает), поэтому в to_dict он есть, в отличие от пути решения.
var lock: Array = []
var cells: Array = []         # cells[строка][столбец] -> код (строка)
var trap_cells: Dictionary = {}  # Vector2i -> true: мёртвые клетки и порченые коды
## Путь, по которому сетка построена (клетки по порядку). Знание сервера и тестов: клиенту и ботам его не отдавать,
## в to_dict его нет. У сетки из from_dict пусто.
var solution_path: Array[Vector2i] = []
var dead_marker := ""         # код мёртвой клетки: по нему клиент рисует её иначе; порченый код выглядит обычным — в этом ловушка


func code_at(cell: Vector2i) -> String:
	return cells[cell.x][cell.y]


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size


func is_trap(cell: Vector2i) -> bool:
	return trap_cells.has(cell)


func is_dead(cell: Vector2i) -> bool:
	return dead_marker != "" and code_at(cell) == dead_marker


## Для сети: клиент получает размер, коды и ловушки как есть (мёртвые видны по маркеру). Путь решения не передаётся.
func to_dict() -> Dictionary:
	var rows: Array = []
	for r in cells:
		rows.append((r as Array).duplicate())
	var traps: Array = []
	for c in trap_cells:
		traps.append([c.x, c.y])
	traps.sort()
	return {"size": size, "cells": rows, "traps": traps, "dead_marker": dead_marker, "lock": lock.duplicate()}


static func from_dict(d: Dictionary) -> BreachGrid:
	var g := BreachGrid.new()
	g.size = int(d.get("size", 0))
	g.dead_marker = str(d.get("dead_marker", ""))
	for c in d.get("lock", []):
		g.lock.append(str(c))
	for r in d.get("cells", []):
		var row: Array = []
		for c in r:
			row.append(str(c))
		g.cells.append(row)
	for t in d.get("traps", []):
		g.trap_cells[Vector2i(int(t[0]), int(t[1]))] = true
	return g


## Сетка size x size под список демонов (BreachDaemon). params — {dead_cells, corrupted_codes, lock_traps: Vector2i(мин, макс)}
## из BreachData.tier_params; пустой — ловушек нет (заряд и расшифровка). rng — случайность попытки (seed задаёт вызывающий).
## lock_length — длина замка (0 — без замка, путь, клетки и расход rng как раньше); коды замка берутся из алфавита до всего остального.
## С замком приманок столько, сколько в lock_traps (нет ключа — corrupted_codes); без замка — corrupted_codes, случайно.
## Цену провала (надбавку к замку и приманкам) вызывающий передаёт длиной замка и копией params со сдвинутым lock_traps.
## null, если цепочки (с замком) не влезают в сетку, их нет вовсе или путь не построился.
static func generate(grid_size: int, daemons: Array, rng: RandomNumberGenerator, data: BreachData, params: Dictionary = {}, lock_length: int = 0) -> BreachGrid:
	var lock_codes: Array = []
	for _i in range(maxi(lock_length, 0)):
		lock_codes.append(data.alphabet[rng.randi_range(0, data.alphabet.size() - 1)])
	var solution_codes: Array = lock_codes.duplicate()
	for d in daemons:
		solution_codes.append_array(d.sequence)
	if solution_codes.is_empty() or solution_codes.size() > grid_size * grid_size:
		return null
	var path := _build_path(grid_size, solution_codes.size(), rng)
	if path.is_empty():
		return null

	var g := BreachGrid.new()
	g.size = grid_size
	g.dead_marker = data.dead_marker
	g.solution_path = path
	g.lock = lock_codes
	for _r in range(grid_size):
		var row: Array = []
		row.resize(grid_size)
		g.cells.append(row)
	var on_path := {}
	for i in range(path.size()):
		g.cells[path[i].x][path[i].y] = solution_codes[i]
		on_path[path[i]] = true
	for r in range(grid_size):
		for c in range(grid_size):
			if g.cells[r][c] == null:
				g.cells[r][c] = data.alphabet[rng.randi_range(0, data.alphabet.size() - 1)]

	if not params.is_empty():
		var free: Array[Vector2i] = []
		for r in range(grid_size):
			for c in range(grid_size):
				if not on_path.has(Vector2i(r, c)):
					free.append(Vector2i(r, c))
		_shuffle(free, rng)
		var dead_count := mini(_pick(params.get("dead_cells", Vector2i.ZERO), rng), free.size())
		for i in range(dead_count):
			g.cells[free[i].x][free[i].y] = data.dead_marker
			g.trap_cells[free[i]] = true
		var corrupted_key := "corrupted_codes" if lock_codes.is_empty() else "lock_traps"
		var corrupted_range: Vector2i = params.get(corrupted_key, params.get("corrupted_codes", Vector2i.ZERO))
		var corrupted_count := mini(_pick(corrupted_range, rng), free.size() - dead_count)
		var remaining: Array[Vector2i] = free.slice(dead_count)
		var decoy_pool: Array[Vector2i] = remaining if lock_codes.is_empty() else _decoys_near_path(remaining, g.cells, path, solution_codes)
		for i in range(corrupted_count):
			g.trap_cells[decoy_pool[i]] = true
	return g


## Свободные клетки в порядке пригодности под приманку (breach.md 2.4): сначала те, где лежит код из целей, потом остальные; внутри —
## сначала на строках и столбцах пути-решения. Порядок уже перемешанных клеток внутри группы сохраняется (как устойчивая сортировка в :rules).
static func _decoys_near_path(free: Array[Vector2i], cells: Array, path: Array[Vector2i], goal_codes: Array) -> Array[Vector2i]:
	var rows := {}
	var cols := {}
	for p in path:
		rows[p.x] = true
		cols[p.y] = true
	var buckets: Array = [[], [], [], []]
	for cell in free:
		var off_goal := 0 if goal_codes.has(cells[cell.x][cell.y]) else 2
		var off_path := 0 if (rows.has(cell.x) or cols.has(cell.y)) else 1
		buckets[off_goal + off_path].append(cell)
	var out: Array[Vector2i] = []
	for b in buckets:
		out.append_array(b)
	return out


## Случайное число из диапазона Vector2i(мин, макс) включительно; пустой диапазон (макс < мин) — 0.
static func _pick(range_: Vector2i, rng: RandomNumberGenerator) -> int:
	return 0 if range_.y < range_.x else rng.randi_range(range_.x, range_.y)


## Тасование Фишера-Йейтса на своём rng (Array.shuffle берёт общий генератор и под seed попытки не годится).
static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func _build_path(grid_size: int, length: int, rng: RandomNumberGenerator, max_attempts: int = 500) -> Array[Vector2i]:
	for _i in range(max_attempts):
		var p := _try_build_path(grid_size, length, rng)
		if not p.is_empty():
			return p
	return []


static func _try_build_path(grid_size: int, length: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var visited := {}
	# Первый выбор — всегда из верхней строки, как в оригинале.
	var start := Vector2i(0, rng.randi_range(0, grid_size - 1))
	path.append(start)
	visited[start] = true
	while path.size() < length:
		var candidates := BreachRules.candidates_for(path[path.size() - 1], BreachRules.next_link_dimension(path.size()), grid_size, visited)
		if candidates.is_empty():
			return []
		var next: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		path.append(next)
		visited[next] = true
	return path

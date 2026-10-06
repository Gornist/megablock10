class_name BreachAttempt
extends RefCounted
## Состояние одной попытки: сетка, демоны, размер буфера и выбранные клетки (порт BreachAttemptState). Решает, какие клетки доступны
## дальше, что совпало и не попала ли ловушка. Сервер проверяет по нему каждый тап клиента: select не бросает исключений на чужом
## вводе, а возвращает false.

var grid: BreachGrid
var daemons: Array = []     # BreachDaemon
var buffer_size := 0
var selected: Array[Vector2i] = []
var _trap_sentinel := ""


static func make(grid_: BreachGrid, daemons_: Array, buffer_size_: int, data: BreachData) -> BreachAttempt:
	var a := BreachAttempt.new()
	a.grid = grid_
	a.daemons = daemons_
	a.buffer_size = buffer_size_
	a._trap_sentinel = data.trap_sentinel
	return a


func duplicate_attempt() -> BreachAttempt:
	var a := BreachAttempt.new()
	a.grid = grid
	a.daemons = daemons
	a.buffer_size = buffer_size
	a.selected = selected.duplicate()
	a._trap_sentinel = _trap_sentinel
	return a


func buffer_codes() -> Array[String]:
	var out: Array[String] = []
	for c in selected:
		out.append(grid.code_at(c))
	return out


## Маркер ловушки в match_codes (из BreachData.trap_sentinel).
func trap_sentinel() -> String:
	return _trap_sentinel


func is_full() -> bool:
	return selected.size() >= buffer_size


## Коды для сверки с цепочками демонов: клетка-ловушка подменена маркером, который не равен ни одному коду,
## поэтому ловушка рвёт любую цепочку и не может войти в совпадение.
func match_codes() -> Array[String]:
	var out: Array[String] = []
	for c in selected:
		out.append(_trap_sentinel if grid.is_trap(c) else grid.code_at(c))
	return out


## Замок хранилища этой попытки (пусто — без замка, правила как раньше): он живёт в сетке, чтобы его нельзя было забыть передать попытке.
func lock() -> Array:
	return grid.lock


## Замок вскрыт: его цепочка целиком совпала в буфере (ловушка рвёт её, как любую). Без замка — всегда false.
func lock_opened() -> bool:
	return not grid.lock.is_empty() and BreachRules.lock_opened_at(match_codes(), grid.lock) >= 0


## Засчитанные демоны с правилом замка (breach.md 2.2): добыча только после вскрытия, остальные где угодно.
func matched_daemon_ids() -> Array[String]:
	return BreachRules.resolve_daemons(match_codes(), daemons, grid.lock)


## Совпали бы без замка, но добыча легла до вскрытия (или замок так и не вскрыт) — не засчитаны. Без замка — пусто.
func matched_before_lock_ids() -> Array[String]:
	var out: Array[String] = []
	if grid.lock.is_empty():
		return out
	var counted := matched_daemon_ids()
	for id in BreachRules.resolve_daemons(match_codes(), daemons):
		if not counted.has(id):
			out.append(id)
	return out


## Клетки, доступные для СЛЕДУЮЩЕГО тапа, по тому же правилу, что у генератора. Буфер полон — пусто.
func selectable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_full():
		return out
	if selected.is_empty():
		for c in range(grid.size):
			out.append(Vector2i(0, c))
		return out
	return BreachRules.candidates_for(selected[selected.size() - 1], BreachRules.next_link_dimension(selected.size()), grid.size, BreachRules.cell_set(selected))


func can_select(cell: Vector2i) -> bool:
	return selectable_cells().has(cell)


## Выбрать клетку. false — клетка недоступна на этом шаге, ничего не изменилось.
func select(cell: Vector2i) -> bool:
	if not can_select(cell):
		return false
	selected.append(cell)
	return true

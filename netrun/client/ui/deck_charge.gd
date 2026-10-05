class_name DeckCharge
extends VBoxContainer
## Заряд демона на запястье (К6, docs/netrun-deck-design.md §3.3, §7.1): сетка короткой мини-игры вместо списка на деке. Слева сетка (клетки BreachCell,
## те же, что на панели взлома), справа таймер, цепочка-цель, буфер и «ОТМЕНА». Доступные клетки подсвечивает клиент сам (BreachMirror, тот же код, что у
## сервера), сервер подтверждает каждый тап. Ловушек нет: клетка либо подходит правилу строка/столбец, либо недоступна.
## На время сетки дека увеличивается до масштаба 1 (WorldUI), клетка не мельче ~2,9 см (CELL_MAX_PX…): 7×7 помещается в 340 px по ширине.
## Состояния: пусто (скрыт) → идёт попытка → итог (ЗАРЯЖЕН / НЕ УДАЛОСЬ, RESULT_SEC секунд) → скрыт.

signal cell_tapped(cell: Vector2i)
signal cancel_requested
## Итог показан достаточно долго: деке пора вернуться к вкладкам.
signal finished

## Сетка с промежутками не шире (px): справа остаётся место для таймера и цепочки.
const GRID_MAX_W := 340
const CELL_MAX_PX := 56
const GRID_GAP := 2
const RESULT_SEC := 1.8
## Попытка без вестей от сервера дольше стольких секунд считается потерянной.
const STALE_SEC := 6.0

var mirror: BreachMirror
var daemon_name := ""
var charged := false
## Что идёт на запястье: заряд демона (charge) или расшифровка шарда (decrypt, К7) — сетка и ввод те же, отличаются подписи.
var mode := WorldMsg.MODE_CHARGE

var _cells: Dictionary = {}              # Vector2i -> BreachCell
var _grid_box: Control
var _side: VBoxContainer
var _timer_label: Label
var _target_flow: HFlowContainer
var _buffer_flow: HFlowContainer
var _result_left := 0.0
var _result_shown := false
var _idle := 0.0   # сколько секунд нет вестей от сервера во время попытки


func _init() -> void:
	add_theme_constant_override("separation", DeckTheme.GAP)
	visible = false


func _process(delta: float) -> void:
	if is_running():
		_idle += delta
		if _idle > STALE_SEC:   # сервер тикает раз в секунду: тишина дольше — попытки уже нет (рестарт сервера, обрыв), сетку не держим
			mirror = null
			finished.emit()
			return
	if _result_shown and _result_left > 0.0:
		_result_left -= delta
		if _result_left <= 0.0:
			_result_shown = false
			finished.emit()


## Размер клетки для сетки size×size, px: влезает в GRID_MAX_W и не больше CELL_MAX_PX. Чистая функция — проверяется тестом (≥ 2 см на деке масштаба 1).
static func cell_px(size: int) -> int:
	if size < 1:
		return CELL_MAX_PX
	return mini(CELL_MAX_PX, (GRID_MAX_W - GRID_GAP * (size - 1)) / size)


## Идёт ли попытка (сетка на экране и ещё не итог).
func is_running() -> bool:
	return mirror != null and not mirror.finished


## Видна ли хоть что-то: сетка или итог.
func is_shown() -> bool:
	return visible


## Начало попытки (`bk` с mode = charge). false — событие негодное.
func begin(m: BreachMirror, name_: String, mode_: String = WorldMsg.MODE_CHARGE) -> bool:
	if m == null:
		return false
	mirror = m
	mode = mode_
	daemon_name = name_
	charged = false
	_result_shown = false
	_result_left = 0.0
	_idle = 0.0
	_build_run()
	visible = true
	return true


## Ответ сервера на тап или шаг времени (`bk_tick`).
func apply_tick(ev: Dictionary) -> void:
	if mirror == null:
		return
	_idle = 0.0
	mirror.apply_tick(ev)
	_refresh_run()


## Игрок нажал клетку: true — тап ушёл (подсветка обновилась сразу).
func tap_cell(cell: Vector2i) -> bool:
	if mirror == null or mirror.finished or not mirror.tap(cell):
		return false
	_refresh_run()
	cell_tapped.emit(cell)
	return true


## Итог (`bk_end`): заряжен или нет. Показывается RESULT_SEC секунд.
func apply_end(ev: Dictionary) -> void:
	if mirror != null:
		mirror.apply_end(ev)
	charged = bool(ev.get("decrypted", false)) if mode == WorldMsg.MODE_DECRYPT else bool(ev.get("charged", false))
	_build_result(ev)
	_result_shown = true
	_result_left = RESULT_SEC
	visible = true


## Убрать всё (попытка брошена без итога, например, дека сменилась).
func hide_all() -> void:
	mirror = null
	_result_shown = false
	_cells.clear()
	visible = false
	DeckUi.clear(self)


func cell_nodes() -> Dictionary:
	return _cells


## Тексты (для проверок): всё, что игрок видит словами.
func texts() -> PackedStringArray:
	return DeckUi.texts(self)


# ---------------------------------------------------------------- построение

func _clear_all() -> void:
	DeckUi.clear(self)
	_cells.clear()
	_timer_label = null
	_target_flow = null
	_buffer_flow = null


func _build_run() -> void:
	_clear_all()
	var cols := DeckUi.hbox(14)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DeckUi.expand(cols, true)
	add_child(cols)
	var size := mirror.grid.size
	var px := cell_px(size)
	var grid := GridContainer.new()
	grid.columns = size
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(grid)
	for r in range(size):
		for c in range(size):
			var cell := BreachCell.new()
			cell.setup(Vector2i(r, c), mirror.grid.cells[r][c], mirror.grid.is_dead(Vector2i(r, c)), px)
			cell.tapped.connect(tap_cell)
			grid.add_child(cell)
			_cells[Vector2i(r, c)] = cell
	_grid_box = grid
	_side = DeckUi.vbox(DeckTheme.GAP)
	DeckUi.expand(_side, true)
	cols.add_child(_side)
	_side.add_child(DeckUi.label("РАСШИФРОВКА" if mode == WorldMsg.MODE_DECRYPT else "ЗАРЯД", DeckTheme.V_HEAD, false))
	_side.add_child(DeckUi.label(daemon_name, DeckTheme.V_NAME))
	_timer_label = DeckUi.label("", DeckTheme.V_TIMER, false)
	_side.add_child(_timer_label)
	_side.add_child(DeckUi.label("ЦЕПОЧКА", DeckTheme.V_DIM, false))
	_target_flow = _flow()
	_side.add_child(_target_flow)
	_side.add_child(DeckUi.label("БУФЕР", DeckTheme.V_DIM, false))
	_buffer_flow = _flow()
	_side.add_child(_buffer_flow)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(spacer)
	var stop := MbButton.new("ОТМЕНА", "danger")
	stop.button_height = DeckTheme.BTN_SMALL_H
	stop.pressed.connect(func(): cancel_requested.emit())
	_side.add_child(stop)
	_refresh_run()


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 3)
	f.add_theme_constant_override("v_separation", 3)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _code_box(code: String, lit: bool, edge_lit: bool) -> Control:
	var f := MbFrame.make(DeckTheme.PLATE, DeckTheme.ACC if edge_lit else DeckTheme.PLATE_EDGE, MbShape.Form.TAB, 3.0, 4, 2)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.custom_minimum_size = Vector2(40, 32)
	var l := DeckUi.label(code, DeckTheme.V_CODE if lit else DeckTheme.V_DIM, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.add_child(l)
	return f


func _refresh_run() -> void:
	if mirror == null or _timer_label == null or mirror.finished:
		return
	var avail := {}
	for c in mirror.selectable():
		avail[c] = true
	var taken := {}
	for c in mirror.selected():
		taken[c] = true
	for c in _cells:
		var cell: BreachCell = _cells[c]
		if taken.has(c):
			cell.state = BreachCell.State.TAKEN
			cell.pending = mirror.pending != null and mirror.pending == c
		elif avail.has(c):
			cell.state = BreachCell.State.AVAILABLE
			cell.pending = false
		else:
			cell.state = BreachCell.State.IDLE
			cell.pending = false
	_timer_label.text = BreachPanel.timer_text(mirror.left)
	_timer_label.theme_type_variation = DeckTheme.V_BAD if mirror.left <= BreachData.shared().low_time_sec else DeckTheme.V_TIMER
	DeckUi.clear(_target_flow)
	var chain: Array = mirror.targets[0]["cells"]
	for code in chain:
		_target_flow.add_child(_code_box(str(code), true, true))
	DeckUi.clear(_buffer_flow)
	var codes := mirror.buffer_codes()
	for i in range(mirror.buffer_size):
		_buffer_flow.add_child(_code_box(codes[i] if i < codes.size() else "··", i < codes.size(), i < codes.size()))


func _build_result(ev: Dictionary) -> void:
	_clear_all()
	var decrypting := mode == WorldMsg.MODE_DECRYPT
	var headline := ("ОТКРЫТ" if charged else "НЕ РАСШИФРОВАН") if decrypting else ("ЗАРЯЖЕН" if charged else "ЗАРЯД НЕ УДАЛСЯ")
	var title := DeckUi.label(headline, DeckTheme.V_BIG, false)
	title.add_theme_color_override("font_color", DeckTheme.tone_color("ok" if charged else "bad"))
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := ""
	if decrypting:
		sub = HudLogic.decrypt_result_sub(ev)
	elif charged:
		sub = "%s · левый X — запуск" % daemon_name
	elif str(ev.get("early", "")) != "":
		sub = "Прервано"
	else:
		sub = "Время вышло — можно снова"
	var l := DeckUi.label(sub, DeckTheme.V_DIM, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)

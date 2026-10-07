class_name BreachPanel
extends Node3D
## Панель взлома хранилища в мире (К3, docs/netrun-deck-design.md §7.1): ≈ 48 × 32 см, привязана к миру (позу ставит снаружи BreachPanelLayout.pose один раз,
## когда панель появилась; сама она не следит ни за головой, ни за рукой), 2D-содержимое рисуется в SubViewport 768 × 512 и показано на поверхности (Sprite3D),
## как дека. Нажимает указатель правого контроллера (DeckPointer, второй экземпляр) — события мыши идут прямо во вьюпорт.
## Четыре состояния: HIDDEN; IDLE — «ВЗЛОМ · узел · тир», выбор демонов в пределах RAM и «НАЧАТЬ» (или надпись «ПУСТО / ОСТЫВАЕТ / ЗАНЯТО / ОТКРЫТО»);
## RUN — сетка слева, справа таймер, trace, буфер, цели (совпавшая отмечена), реплика ICE и «ЗАВЕРШИТЬ»; RESULT — итог и «ЗАКРЫТЬ».
## Сетка 7 × 7 — клетка 56 px ≈ 3,5 см. Ловушка — вспышка рамки (без тряски панели: дрожащий объект в мире в VR неприятен).
## Перерисовка по требованию, не чаще 30 к/с, как у деки.

## Игрок выбрал демонов и нажал «НАЧАТЬ» / нажал клетку / «ЗАВЕРШИТЬ».
signal start_requested(vault: String, daemon_ids: Array)
signal cell_tapped(cell: Vector2i)
signal cancel_requested
## Ловушка во взломе: игра отвечает вспышкой и импульсом контроллера.
signal trap_felt

const VIEW_SIZE := Vector2i(768, 512)
const MAX_FPS := 30.0
const FLASH_SEC := 0.45
## Итог остаётся на панели столько секунд, если игрок его не закрыл.
const RESULT_SEC := 14.0
const GRID_PX := 420
const CELL_MAX_PX := 64
const GRID_GAP := 3

const MODE_HIDDEN := "hidden"
const MODE_IDLE := "idle"
const MODE_RUN := "run"
const MODE_RESULT := "result"

var redraw_count := 0
var mirror: BreachMirror

var _viewport: SubViewport
var _surface: Sprite3D
## Слой композитора OpenXR вместо квада (если включён в конфиге и поддержан); иначе остаётся Sprite3D.
var _layer: XrLayerHost
var _frame: MbFrame
var _left: VBoxContainer
var _right: VBoxContainer
var _mode := MODE_HIDDEN
var _dirty := true
var _since_draw := 0.0
var _flash := 0.0
var _result_left := 0.0
var _trace := 0.0
# контекст узла и деки (idle)
var _node_title := ""
var _node_tier := "BASE"
var _vault := ""
var _access: Dictionary = {"access": "ok"}
var _notice := ""
var _daemons: Array = []                 # подходящие для взлома: [{id, name, effect, tier, cells}]
var _ram := 6
var _picked: Dictionary = {}             # id -> bool
var _known_ids: Dictionary = {}
var _pick_sig: Variant = null            # [ids, ram, тир], для которых посчитаны отметки по умолчанию
var _ctx_key: Variant = null
# виджеты состояния «run»
var _cells: Dictionary = {}              # Vector2i -> BreachCell
var _timer_label: Label
var _ice_label: Label
var _trace_box: VBoxContainer
var _buffer_flow: HFlowContainer
var _targets_box: VBoxContainer
var _pick_scroll: ScrollContainer
var _texts := PackedStringArray()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_frame = MbFrame.make(Color(DeckTheme.BG, 0.97), DeckTheme.ACC, MbShape.Form.DLG, 16.0, 12, 10)
	_frame.border = 3.0
	_frame.theme = DeckTheme.theme()
	_frame.size = Vector2(VIEW_SIZE)
	_viewport.add_child(_frame)
	var cols := DeckUi.hbox(14)
	_frame.add_child(cols)
	_left = DeckUi.vbox(DeckTheme.GAP)
	_left.custom_minimum_size.x = GRID_PX
	cols.add_child(_left)
	_right = DeckUi.vbox(DeckTheme.GAP)
	DeckUi.expand(_right, true)
	cols.add_child(_right)
	_surface = Sprite3D.new()
	_surface.texture = _viewport.get_texture()
	_surface.pixel_size = BreachPanelLayout.WIDTH_M / VIEW_SIZE.x
	_surface.shaded = false
	_surface.double_sided = false
	add_child(_surface)
	_layer = XrLayerHost.new()
	add_child(_layer)
	_layer.setup(_viewport, panel_size_m(), _surface, self)
	visible = false


func _process(delta: float) -> void:
	if _layer.is_active():
		# Слою композитора нужны свежие буферы каждый кадр (см. DeckPanel._process); скрытую панель не рисуем.
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() and _mode != MODE_HIDDEN else SubViewport.UPDATE_DISABLED
	if _mode == MODE_HIDDEN:
		return
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_update_edge()
	if _mode == MODE_RESULT and _result_left > 0.0:
		_result_left -= delta
		if _result_left <= 0.0:
			hide_panel()
	_since_draw += delta
	if not _layer.is_active() and _dirty and _since_draw >= 1.0 / MAX_FPS:
		_dirty = false
		_since_draw = 0.0
		redraw_count += 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func mark_dirty() -> void:
	_dirty = true


func _on_node_added(n: Node) -> void:
	if _viewport != null and n is CanvasItem and _viewport.is_ancestor_of(n):
		var ci := n as CanvasItem
		if not ci.draw.is_connected(mark_dirty):
			ci.draw.connect(mark_dirty)


# ---------------------------------------------------------------- указатель (тот же набор, что у DeckPanel)

func view_size() -> Vector2i:
	return VIEW_SIZE


func surface_transform() -> Transform3D:
	return _surface.global_transform


func panel_size_m() -> Vector2:
	return Vector2(VIEW_SIZE) * _surface.pixel_size


func push_pointer_event(event: InputEvent) -> void:
	_viewport.push_input(event, true)


## Есть ли что нажимать: панель видна и не спрятана.
func is_interactive() -> bool:
	return _mode != MODE_HIDDEN and is_visible_in_tree()


func scroll_by(px: float) -> void:
	if _pick_scroll != null and is_instance_valid(_pick_scroll) and _mode == MODE_IDLE:
		_pick_scroll.scroll_vertical += roundi(px)
		_dirty = true


func has_viewport_surface() -> bool:
	return _surface.texture == _viewport.get_texture()


func mode() -> String:
	return _mode


func vault_id() -> String:
	return _vault


## Тексты панели (для проверок): всё, что игрок видит словами.
func texts() -> PackedStringArray:
	return DeckUi.texts(_frame)


func cell_nodes() -> Dictionary:
	return _cells


# ---------------------------------------------------------------- состояния

## Поставить панель в мир (поза из BreachPanelLayout.pose) и показать. Дальше она стоит на месте.
func place(xform: Transform3D) -> void:
	global_transform = xform


func hide_panel() -> void:
	_mode = MODE_HIDDEN
	visible = false
	mirror = null
	_vault = ""
	_cells.clear()
	_flash = 0.0
	DeckUi.clear(_left)
	DeckUi.clear(_right)


## Данные для выбора демонов: узел, тир, подходящие демоны ([{id, name, effect, tier, cells}]) и RAM. Не перерисовывает чужое состояние (взлом идёт).
func set_context(node_title: String, tier: String, daemons: Array, ram: int) -> void:
	var key := [node_title, tier, daemons, ram]
	if key == _ctx_key:
		return
	_ctx_key = key
	_node_title = node_title
	_node_tier = tier if tier != "" else "BASE"
	_ram = ram
	_daemons = []
	var fresh := {}
	for d in daemons:
		if d is Dictionary and not (d.get("cells", []) as Array).is_empty():
			_daemons.append(d)
			fresh[str(d["id"])] = true
	_known_ids = fresh
	# Отметки по умолчанию — только то, что влезает; пересчитываем, когда сменился набор демонов, RAM или тир (выбор игрока в остальном не трогаем).
	var ids := fresh.keys()
	ids.sort()
	var sig := [ids, _ram, _node_tier]
	if sig != _pick_sig:
		_pick_sig = sig
		_picked = default_picks(_daemons, tier_level(_node_tier), lock_length(), _ram)
	if _mode == MODE_IDLE:
		_build_idle()


## Показать панель до начала взлома у хранилища vault. access — запись слота из `shards` ({access, left}).
func show_idle(vault: String, access: Dictionary) -> void:
	if _mode == MODE_RUN or _mode == MODE_RESULT:
		return
	if _mode == MODE_IDLE and vault == _vault and access == _access:
		return   # то же самое: не перестраиваем (вызывают каждый кадр)
	if _mode == MODE_HIDDEN or vault != _vault:
		_notice = ""
	_vault = vault
	_access = access
	_mode = MODE_IDLE
	visible = true
	_build_idle()


## Сервер не начал взлом (`bk_no`): причина словами на панели.
func show_denied(reason: String, left: int = 0, info: Dictionary = {}) -> void:
	_notice = denied_text(reason, left, info)
	if _mode == MODE_IDLE:
		_build_idle()


## Начался взлом (`bk`): сетка, цели, таймер.
func begin(m: BreachMirror) -> void:
	mirror = m
	_vault = m.vault
	_mode = MODE_RUN
	visible = true
	_notice = ""
	_build_run()


func apply_tick(ev: Dictionary) -> void:
	if mirror == null:
		return
	if ev.has("cell") and not bool(ev.get("ok", true)):
		pass   # отказ: подсветка вернётся при обновлении ниже
	elif bool(ev.get("trap", false)):
		_flash = FLASH_SEC
		trap_felt.emit()
	mirror.apply_tick(ev)
	_refresh_run()


## Пользователь нажал клетку: возвращает true, если тап ушёл (подсветка обновилась сразу).
func tap_cell(cell: Vector2i) -> bool:
	if mirror == null or _mode != MODE_RUN or not mirror.tap(cell):
		return false
	_refresh_run()
	cell_tapped.emit(cell)
	return true


func apply_end(ev: Dictionary) -> void:
	if mirror != null:
		mirror.apply_end(ev)
	_mode = MODE_RESULT
	visible = true
	_result_left = RESULT_SEC
	_build_result(ev)


func set_trace(value: float) -> void:
	if int(value) == int(_trace):
		_trace = value
		return
	_trace = value
	_update_edge()
	if _mode == MODE_RUN:
		_refresh_trace()


# ---------------------------------------------------------------- тексты (чистые, для тестов)

## info — числа отказа из `bk_no` (lock, need, ram): при «bad_daemons» из-за RAM объясняют, сколько не хватает.
static func denied_text(reason: String, left: int = 0, info: Dictionary = {}) -> String:
	match reason:
		"busy":
			return "Хранилище взламывает другой нетраннер"
		"far":
			return "Подойдите ближе к хранилищу"
		"empty":
			return "ПУСТО · пополнение через %s" % wait_text(left)
		"cooldown":
			return "ОСТЫВАЕТ · %s" % wait_text(left)
		"open":
			return "Хранилище уже открыто"
		"bad_daemons":
			if info.has("need") and info.has("ram"):
				var lock := int(info.get("lock", 0))
				return "НЕ ХВАТАЕТ RAM: замок %d + цепочки %d > %d — снимите демона" % [lock, int(info["need"]) - lock, int(info["ram"])]
			return "Выберите демонов: цепочки должны влезать в RAM"
		"active":
			return "Взлом уже идёт"
		"bridge":
			return "Нет связи с Мостом"
		"charging":
			return "Идёт заряд или расшифровка — сначала закончите"
		"not_ready":
			return "Узел ещё не готов — подождите секунду"
	return "Сейчас нельзя (%s)" % reason if reason != "" else "Сейчас нельзя"


## «замок 3 + 9 / RAM 12» — счётчик выбора перед стартом.
static func ram_counter_text(lock: int, chains: int, ram: int) -> String:
	return "замок %d + %d / RAM %d" % [lock, chains, ram]


## «5 мин» для минут и дольше, «40 с» для меньше минуты.
static func wait_text(sec: int) -> String:
	if sec >= 60:
		return "%d мин" % ceili(sec / 60.0)
	return "%d с" % maxi(sec, 0)


static func timer_text(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]


static func outcome_title(outcome: String) -> String:
	match outcome:
		BreachRules.SUCCESS:
			return "ВЗЛОМ УДАЛСЯ"
		BreachRules.PARTIAL:
			return "ВЗЛОМ ЧАСТИЧНО"
	return "ВЗЛОМ ПРОВАЛЕН"


## Причина провала или частичного итога (BreachReason) по итогу `bk_end` и клиентской копии попытки: число ловушек — по ответам сервера `bk_tick`
## (mirror.trap_hits), нажатий — по выбранным клеткам. Нет копии (итог пришёл без неё) — без чисел о ловушках.
static func reason_lines(ev: Dictionary, m: BreachMirror) -> Array[String]:
	var lock_len := m.lock.size() if m != null else 0
	var traps := m.trap_hits.size() if m != null else 0
	var taps := m.attempt.selected.size() if m != null and m.attempt != null else 0
	var before: Array = ev.get("matched_before_lock", [])
	return BreachReason.lines(str(ev.get("outcome", BreachRules.FAIL)), lock_len, bool(ev.get("lock_opened", false)), traps, taps, before)


static func early_text(reason: String) -> String:
	match reason:
		"cancel":
			return "Завершено досрочно"
		"teleport":
			return "Вы ушли — взлом завершён досрочно"
		"transit", "avatar_removed", "session_lost":
			return "Связь прервана — взлом завершён досрочно"
	return ""


# ---------------------------------------------------------------- idle

## Выбранные демоны по порядку списка.
func picked_ids() -> Array:
	var out: Array = []
	for d in _daemons:
		if _picked.get(str(d["id"]), false):
			out.append(str(d["id"]))
	return out


func picked_cells() -> int:
	var n := 0
	for d in _daemons:
		if _picked.get(str(d["id"]), false):
			n += (d["cells"] as Array).size()
	return n


## Длина замка хранилища этого тира (как у сервера: неизвестный тир — параметры BASE).
func lock_length() -> int:
	return int(BreachData.shared().tier_params(_node_tier)["lock_length"])


## Сколько RAM занимает выбор: замок + цепочки отмеченных.
func ram_needed() -> int:
	return lock_length() + picked_cells()


func fits_ram() -> bool:
	return BreachData.fits_ram(_ram, lock_length(), picked_cells())


## Уровень тира 1/2/3 по имени (неизвестное — 1, как BASE).
static func tier_level(tier: String) -> int:
	return maxi(BreachData.TIER_NAMES.find(tier), 0) + 1


## Отметки по умолчанию, id -> true: только то, что влезает («замок + Σ ≤ RAM»). Порядок: Извлечение тира хранилища или ближайшего ниже,
## остальные Извлечения (ниже тира — по убыванию, выше — по возрастанию), затем прочие (защитные) в порядке списка; каждое — если ещё влезает.
static func default_picks(daemons: Array, vault_level: int, lock: int, ram: int) -> Dictionary:
	var extracts: Array = []
	var rest: Array = []
	for d in daemons:
		if str(d.get("effect", "")).begins_with("EXTRACT_"):
			extracts.append(d)
		else:
			rest.append(d)
	# sort_custom нестабилен: порядок списка держим индексом.
	var idx := {}
	for i in daemons.size():
		idx[str(daemons[i]["id"])] = i
	extracts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a.get("tier", 1))
		var tb := int(b.get("tier", 1))
		var a_low := ta <= vault_level
		var b_low := tb <= vault_level
		if a_low != b_low:
			return a_low
		if ta != tb:
			return ta > tb if a_low else ta < tb
		return idx[str(a["id"])] < idx[str(b["id"])])
	var picked := {}
	var total := lock
	for d in extracts + rest:
		var n := (d["cells"] as Array).size()
		if total + n <= ram:
			picked[str(d["id"])] = true
			total += n
	return picked


func toggle_daemon(id: String) -> void:
	if _mode != MODE_IDLE or not _known_ids.has(id):
		return
	_picked[id] = not _picked.get(id, false)
	_build_idle()


func request_start() -> bool:
	if _mode != MODE_IDLE or str(_access.get("access", "")) != "ok":
		return false
	var ids := picked_ids()
	if ids.is_empty() or not fits_ram():
		return false
	start_requested.emit(_vault, ids)
	return true


func _clear_all() -> void:
	DeckUi.clear(_left)
	DeckUi.clear(_right)
	_cells.clear()
	_pick_scroll = null
	_timer_label = null
	_ice_label = null
	_trace_box = null
	_buffer_flow = null
	_targets_box = null
	_dirty = true


func _build_idle() -> void:
	_clear_all()
	_update_edge()
	var access := str(_access.get("access", "ok"))
	_left.add_child(DeckUi.section_title("ДЕМОНЫ ДЛЯ ВЗЛОМА", "%d" % _daemons.size()))
	_pick_scroll = ScrollContainer.new()
	_pick_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(_pick_scroll, true)
	var list := DeckUi.vbox(4)
	DeckUi.expand(list)
	_pick_scroll.add_child(list)
	_left.add_child(_pick_scroll)
	for d in _daemons:
		list.add_child(_pick_row(d))
	if _daemons.is_empty():
		list.add_child(DeckUi.label("Нет программ с цепочкой: взлом невозможен", DeckTheme.V_DIM, false))
	var head := DeckUi.vbox(2)
	head.add_child(DeckUi.label("ВЗЛОМ · %s" % _node_title if _node_title != "" else "ВЗЛОМ", DeckTheme.V_HEAD))
	head.add_child(DeckUi.label("тир %s · сетка %d×%d · %d с" % [_node_tier, _grid_size_of(_node_tier), _grid_size_of(_node_tier), _timer_of(_node_tier)], DeckTheme.V_DIM))
	_right.add_child(head)
	var status := _access_text(access)
	_right.add_child(DeckUi.label(status, DeckTheme.V_NAME if access == "ok" else DeckTheme.V_DIM, false))
	if _notice != "":
		_right.add_child(DeckUi.label(_notice, DeckTheme.V_WARN, false))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(spacer)
	var used := picked_cells()
	var over := not fits_ram()
	var row := DeckUi.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if over:
		_right.add_child(DeckUi.label("НЕ ХВАТАЕТ RAM — снимите демона", DeckTheme.V_BAD, false))
	row.add_child(DeckUi.meter(float(ram_needed()) / maxf(float(_ram), 1.0), DeckTheme.BAD if over else DeckTheme.ACC, 16))
	row.add_child(DeckUi.label(ram_counter_text(lock_length(), used, _ram), DeckTheme.V_BAD if over else DeckTheme.V_NAME, false))
	_right.add_child(row)
	var start := MbButton.new("НАЧАТЬ ВЗЛОМ", "primary")
	start.disabled = not (access == "ok" and not picked_ids().is_empty() and not over)
	start.pressed.connect(request_start)
	_right.add_child(start)


func _access_text(access: String) -> String:
	var left := int(_access.get("left", 0))
	match access:
		"empty":
			return denied_text("empty", left)
		"cooldown":
			return denied_text("cooldown", left)
		"busy":
			return denied_text("busy")
		"open":
			return "ОТКРЫТО · возьмите шард рукой"
	return "Отметьте демонов и начните"


func _pick_row(d: Dictionary) -> Control:
	var id := str(d["id"])
	var on: bool = _picked.get(id, false)
	var row := MbRow.new()
	var h := DeckUi.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(DeckUi.label("[x]" if on else "[ ]", DeckTheme.V_CODE if on else DeckTheme.V_DIM, false))
	var col := DeckUi.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DeckUi.expand(col)
	col.add_child(DeckUi.label(str(d.get("name", id)), DeckTheme.V_NAME))
	col.add_child(DeckUi.label(" ".join((d["cells"] as Array).map(func(c): return str(c))), DeckTheme.V_CODE, false))
	h.add_child(col)
	# JITTER, выбранный во взлом, даёт таймеру +N с (как на телефоне) — выбором, а не совпадением.
	var bonus := " · +%d с" % BreachData.shared().jitter_bonus_sec if str(d.get("effect", "")) == "JITTER" else ""
	h.add_child(DeckUi.label("%d яч.%s" % [(d["cells"] as Array).size(), bonus], DeckTheme.V_DIM, false))
	row.add_child(h)
	row.pressed.connect(toggle_daemon.bind(id))
	return row


func _grid_size_of(tier: String) -> int:
	return int(BreachData.shared().tier_params(tier)["grid_size"])


func _timer_of(tier: String) -> int:
	return int(BreachData.shared().tier_params(tier)["timer_sec"])


# ---------------------------------------------------------------- run

func _build_run() -> void:
	_clear_all()
	var size := mirror.grid.size
	var px := mini(CELL_MAX_PX, (GRID_PX - GRID_GAP * (size - 1)) / size)   # сетка вместе с промежутками влезает в левую колонку
	var grid := GridContainer.new()
	grid.columns = size
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	_left.add_child(grid)
	for r in range(size):
		for c in range(size):
			var cell := BreachCell.new()
			cell.setup(Vector2i(r, c), mirror.grid.cells[r][c], mirror.grid.is_dead(Vector2i(r, c)), px)
			cell.tapped.connect(tap_cell)
			grid.add_child(cell)
			_cells[Vector2i(r, c)] = cell
	var head := DeckUi.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(DeckUi.expand(DeckUi.label("ВЗЛОМ · %s" % _node_title if _node_title != "" else "ВЗЛОМ", DeckTheme.V_HEAD)))
	head.add_child(DeckUi.label(mirror.tier, DeckTheme.V_META, false))
	_right.add_child(head)
	_timer_label = DeckUi.label("", DeckTheme.V_TIMER, false)
	_right.add_child(_timer_label)
	_trace_box = DeckUi.vbox(0)
	_right.add_child(_trace_box)
	_right.add_child(DeckUi.section_title("БУФЕР", "%d" % mirror.buffer_size))
	_buffer_flow = HFlowContainer.new()
	_buffer_flow.add_theme_constant_override("h_separation", 3)
	_buffer_flow.add_theme_constant_override("v_separation", 3)
	_right.add_child(_buffer_flow)
	_right.add_child(DeckUi.section_title("ЦЕЛИ", "%d" % mirror.targets.size()))
	_targets_box = DeckUi.vbox(2)
	_right.add_child(_targets_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(spacer)
	_ice_label = DeckUi.label("", DeckTheme.V_DIM, false)
	_ice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ice_label.custom_minimum_size.y = 40
	_right.add_child(_ice_label)
	var stop := MbButton.new("ЗАВЕРШИТЬ", "danger")
	stop.button_height = DeckTheme.BTN_SMALL_H
	stop.pressed.connect(func(): cancel_requested.emit())
	_right.add_child(stop)
	_refresh_run()
	_update_edge()


func _refresh_run() -> void:
	if mirror == null or _mode != MODE_RUN or _timer_label == null:
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
			cell.state = BreachCell.State.TRAP if mirror.trap_hits.has(c) else BreachCell.State.TAKEN
			cell.pending = mirror.pending != null and mirror.pending == c
		elif avail.has(c):
			cell.state = BreachCell.State.AVAILABLE
			cell.pending = false
		else:
			cell.state = BreachCell.State.IDLE
			cell.pending = false
	_timer_label.text = timer_text(mirror.left)
	_timer_label.theme_type_variation = DeckTheme.V_BAD if mirror.left <= BreachData.shared().low_time_sec else DeckTheme.V_TIMER
	_ice_label.text = mirror.ice_line
	DeckUi.clear(_buffer_flow)
	var codes := mirror.buffer_codes()
	for i in range(mirror.buffer_size):
		var f := MbFrame.make(DeckTheme.PLATE, DeckTheme.ACC if i < codes.size() else DeckTheme.PLATE_EDGE, MbShape.Form.TAB, 3.0, 4, 2)
		f.custom_minimum_size = Vector2(40, 32)
		var l := DeckUi.label(codes[i] if i < codes.size() else "··", DeckTheme.V_CODE if i < codes.size() else DeckTheme.V_DIM, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.add_child(l)
		_buffer_flow.add_child(f)
	DeckUi.clear(_targets_box)
	for t in mirror.targets:
		var done := mirror.is_matched(str(t["id"]))
		var row := DeckUi.hbox(6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(DeckUi.label("✓" if done else "·", DeckTheme.V_OK if done else DeckTheme.V_DIM, false))
		row.add_child(DeckUi.label(" ".join((t["cells"] as Array).map(func(c): return str(c))), DeckTheme.V_DIM if done else DeckTheme.V_CODE, false))
		var name_l := DeckUi.label(str(t["name"]), DeckTheme.V_DIM)
		DeckUi.expand(name_l)
		row.add_child(name_l)
		_targets_box.add_child(row)
	_refresh_trace()


func _refresh_trace() -> void:
	if _trace_box == null:
		return
	DeckUi.clear(_trace_box)
	var level := HudLogic.level_from_value(_trace)
	var row := DeckUi.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(DeckUi.label("TRACE", DeckTheme.V_NAME, false))
	row.add_child(DeckUi.meter(HudLogic.trace_fraction(_trace), HudLogic.level_color(level), 16))
	row.add_child(DeckUi.label(str(roundi(_trace)), DeckTheme.V_NAME, false))
	_trace_box.add_child(row)


## Рамка панели: цвет по уровню trace (бирюзовая — спокойно, жёлтая — подозрение, красная — трассировка) и вспышка при ловушке.
func _update_edge() -> void:
	if _frame == null:
		return
	var level := HudLogic.level_from_value(_trace)
	var c := DeckTheme.ACC if level == HudLogic.LEVEL_NORMAL else (DeckTheme.WARN if level == HudLogic.LEVEL_SUSPICIOUS else DeckTheme.BAD)
	if _flash > 0.0:
		c = Color.WHITE.lerp(DeckTheme.BAD, 1.0 - _flash / FLASH_SEC)
	_frame.edge = c
	_frame.border = 6.0 if _flash > 0.0 else 3.0


# ---------------------------------------------------------------- result

func _build_result(ev: Dictionary) -> void:
	_clear_all()
	_update_edge()
	var outcome := str(ev.get("outcome", BreachRules.FAIL))
	var tone := "ok" if outcome == BreachRules.SUCCESS else ("warn" if outcome == BreachRules.PARTIAL else "bad")
	var title := DeckUi.label(outcome_title(outcome), DeckTheme.V_BIG, false)
	title.add_theme_color_override("font_color", DeckTheme.tone_color(tone))
	_left.add_child(title)
	var reason := reason_lines(ev, mirror)
	for i in reason.size():   # причина провала / частичного итога: первая строка крупно
		var line := DeckUi.label(reason[i], DeckTheme.V_BIG if i == 0 else DeckTheme.V_WARN, false)
		if i == 0:
			line.add_theme_color_override("font_color", DeckTheme.tone_color(tone))
		_left.add_child(line)
	var early := early_text(str(ev.get("early", "")))
	if early != "":
		_left.add_child(DeckUi.label(early, DeckTheme.V_WARN, false))
	var opened: Array = ev.get("opened", [])
	_left.add_child(DeckUi.label("Хранилище открыто — возьмите шард рукой" if not opened.is_empty() else "Хранилище не открылось", DeckTheme.V_NAME if not opened.is_empty() else DeckTheme.V_DIM, false))
	if bool(ev.get("exhausted", false)):
		_left.add_child(DeckUi.label("КЭШ ОЧИЩЕН: подходящих предметов нет", DeckTheme.V_WARN, false))
	if int(ev.get("eddies", 0)) > 0:
		_left.add_child(DeckUi.label("Эдди +%d · выплата при чистом выходе" % int(ev["eddies"]), DeckTheme.V_CODE, false))
	if str(ev.get("alert", "")) != "":
		_left.add_child(DeckUi.label(str(ev["alert"]), DeckTheme.V_DIM, false))
	if ev.has("cooldown"):
		_left.add_child(DeckUi.label("Узел остывает: %s" % wait_text(int(ev["cooldown"])), DeckTheme.V_DIM, false))
	if str(ev.get("error", "")) != "":
		_left.add_child(DeckUi.label("Мост не принял итог (%s): награды нет" % str(ev["error"]), DeckTheme.V_BAD, false))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(spacer)
	var close := MbButton.new("ЗАКРЫТЬ", "primary")
	close.pressed.connect(hide_panel)
	_right.add_child(close)

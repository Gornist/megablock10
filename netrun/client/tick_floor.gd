class_name TickFloor
extends Node3D
## Телеграф такта на полу узла (time-and-movement.md 3.4, 3.1 Т6): зрение каждого Soft ICE светом на клетках (фокус ярче, периферия тусклее; цвет — по состоянию
## ICE: белый / жёлтый / оранжевый / красный), тусклое «зрение после шага» другого оттенка, стрелка к следующей клетке ICE (при предзахвате — красная,
## в клетку игрока) и «вдох»: когда сервер сообщил tk.inh, свет один раз пульсирует (яркость ×1,6 и обратно за 0,5 с).
## Клетки — один MultiMesh из плоских квадратов (не узел на клетку). Только в тактовом режиме: в realtime сцена эту ноду не создаёт.
## Black ICE света не даёт: его зрение не клеточное (нет намерения), он виден пингом.

const CAPACITY := 768
const MAX_ARROWS := 8
## Высота света и стрелок над полом, м (чтобы не мерцать в одной плоскости с ним); «после шага» чуть ниже текущего.
const LIFT := 0.015
const FUTURE_LIFT := 0.008
const ARROW_LIFT := 0.03
const FOCUS_ALPHA := 0.35
const PERIPHERY_ALPHA := 0.15
## Зрение после шага: прозрачность относительно текущего и подмешанный оттенок.
const FUTURE_ALPHA := 0.5
const FUTURE_TINT := Color(0.45, 0.8, 1.0)
const FUTURE_TINT_MIX := 0.55
## Цвет по состоянию TickIce (Патруль, Взгляд, Проверка, Поиск); совпадает с глазом ICE (IceView.EYE_COLOR).
const STATE_COLORS := [Color(1.0, 1.0, 1.0), Color(1.0, 0.86, 0.25), Color(1.0, 0.55, 0.15), Color(1.0, 0.2, 0.18)]
const PRECAPTURE_COLOR := Color(1.0, 0.1, 0.1)
const PULSE_SEC := 0.5
const PULSE_GAIN := 1.6
## Квадрат клетки чуть меньше клетки: соседние не слипаются.
const QUAD_INSET := 0.06
## Стрелка: ширина, м; хвост отступает от центра клетки ICE, чтобы не лежать под ним.
const ARROW_WIDTH := 0.34
const ARROW_TAIL := 0.4
const ARROW_MIN_LEN := 0.5
const TURN_ARROW_LEN := 0.9

var _grid: NodeGrid
var _mm: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _arrows: Array[MeshInstance3D] = []
var _arrow_specs: Array = []
var _key := 0
var _count := 0
## То же, что записано в MultiMesh (положение и цвет квадратов): под headless-рендером MultiMesh ничего не хранит, а тестам нужно проверить.
var _cell_pos := PackedVector3Array()
var _cell_col := PackedColorArray()
var _inhale := false
var _pulse_left := 0.0


## Сетка другого узла (переход между узлами с разной раскладкой): свет зрения считается по ней. Сброс кэша — следующий apply перерисует всё.
func set_grid(grid: NodeGrid) -> void:
	_grid = grid if grid != null else NodeGrid.for_layout()
	_key = 0


func _init(grid: NodeGrid = null) -> void:
	name = "TickFloor"
	_grid = grid if grid != null else NodeGrid.for_layout()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * (NodeGrid.CELL_M - QUAD_INSET)
	quad.material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Cells"
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)


func _process(delta: float) -> void:
	step(delta)


## Продвинуть вдох на delta секунд (сцена зовёт каждый кадр; в тестах — вручную).
func step(delta: float) -> void:
	if _pulse_left > 0.0:
		_pulse_left = maxf(_pulse_left - delta, 0.0)
	var m := brightness()
	_mat.albedo_color = Color(m, m, m, m)


## Снимок: намерения ICE (TickForecast.parse_intents), tk сообщения, клетка игрока (куда целится стрелка предзахвата).
func apply(intents: Array, info: Dictionary, player_cell: Vector2i) -> void:
	var inh := int(info.get("inh", 0)) == 1
	if inh and not _inhale:
		_pulse_left = PULSE_SEC   # вдох начался: один раз пульсируем, пока tk.inh держится, повторов нет
	_inhale = inh
	var key := hash([intents, player_cell])
	if key == _key:
		return
	_key = key
	_rebuild(intents, player_cell)


## Яркость света сейчас: 1, во вдохе — до PULSE_GAIN в середине пульса.
func brightness() -> float:
	if _pulse_left <= 0.0:
		return 1.0
	var phase := 1.0 - _pulse_left / PULSE_SEC
	return 1.0 + (PULSE_GAIN - 1.0) * sin(PI * phase)


func pulsing() -> bool:
	return _pulse_left > 0.0


## Сколько квадратов света нарисовано.
func cell_count() -> int:
	return _count


func arrow_count() -> int:
	return _arrow_specs.size()


## Стрелка i: {from, to, color, precapture}.
func arrow_spec(i: int) -> Dictionary:
	return _arrow_specs[i]


## Цвет и прозрачность квадрата i (для тестов).
func cell_color(i: int) -> Color:
	return _cell_col[i]


func cell_position(i: int) -> Vector3:
	return _cell_pos[i]


func _rebuild(intents: Array, player_cell: Vector2i) -> void:
	var n := 0
	_arrow_specs.clear()
	_cell_pos.clear()
	_cell_col.clear()
	for it: Dictionary in intents:
		if bool(it.get("black", false)):
			continue
		var base: Color = STATE_COLORS[clampi(int(it.get("st", 0)), 0, STATE_COLORS.size() - 1)]
		var c: Vector2i = it["c"]
		var d: Vector2i = it.get("d", Vector2i.ZERO)
		var nc: Vector2i = it.get("nc", c)
		var nd: Vector2i = it.get("nd", d)
		var sc := float(it.get("sc", TickForecast.DEFAULT_SIGHT))
		n = _put(TickVision.visible_cells(_grid, c, d, sc, TickForecast.HALF_DEG, TickForecast.FOCUS_DEG), base, 1.0, LIFT, n)
		var moves := nc != c or nd != d
		if moves:
			var tint := base.lerp(FUTURE_TINT, FUTURE_TINT_MIX)
			n = _put(TickVision.visible_cells(_grid, nc, nd, sc, TickForecast.HALF_DEG, TickForecast.FOCUS_DEG), tint, FUTURE_ALPHA, FUTURE_LIFT, n)
		var spec := _arrow_for(it, c, d, nc, nd, base, player_cell)
		if not spec.is_empty() and _arrow_specs.size() < MAX_ARROWS:
			_arrow_specs.append(spec)
	_count = n
	_mm.multimesh.visible_instance_count = n
	_sync_arrows()


func _put(cells: Dictionary, color: Color, alpha_scale: float, lift: float, n: int) -> int:
	var mm := _mm.multimesh
	for cell: Vector2i in cells:
		if n >= CAPACITY:
			break
		var a := (FOCUS_ALPHA if int(cells[cell]) == TickVision.FOCUS else PERIPHERY_ALPHA) * alpha_scale
		var p := NodeGrid.center(cell)
		var pos := Vector3(p.x, lift, p.z)
		var col := Color(color.r, color.g, color.b, a)
		mm.set_instance_transform(n, Transform3D(Basis(), pos))
		mm.set_instance_color(n, col)
		_cell_pos.append(pos)
		_cell_col.append(col)
		n += 1
	return n


## Стрелка ICE: предзахват — красная в клетку игрока; шаг — к следующей клетке; поворот на месте — короткая в новую сторону; стоит — нет.
func _arrow_for(it: Dictionary, c: Vector2i, _d: Vector2i, nc: Vector2i, nd: Vector2i, base: Color, player_cell: Vector2i) -> Dictionary:
	if TickForecast.is_precapture(it, player_cell):
		return {"from": NodeGrid.center(nc), "to": NodeGrid.center(player_cell), "color": PRECAPTURE_COLOR, "precapture": true}
	if nc != c:
		return {"from": NodeGrid.center(c), "to": NodeGrid.center(nc), "color": base, "precapture": false}
	if nd != it.get("d", Vector2i.ZERO) and nd != Vector2i.ZERO:
		var from := NodeGrid.center(c)
		return {"from": from, "to": from + Vector3(nd.x, 0.0, nd.y).normalized() * TURN_ARROW_LEN, "color": base, "precapture": false}
	return {}


func _sync_arrows() -> void:
	while _arrows.size() < _arrow_specs.size():
		_arrows.append(_make_arrow())
	for i in _arrows.size():
		var m := _arrows[i]
		m.visible = i < _arrow_specs.size()
		if not m.visible:
			continue
		var spec: Dictionary = _arrow_specs[i]
		var from: Vector3 = spec["from"]
		var to: Vector3 = spec["to"]
		var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
		var dist := flat.length()
		if dist < 0.001:
			m.visible = false
			continue
		flat /= dist
		var length := maxf(dist - ARROW_TAIL, ARROW_MIN_LEN)
		var tip := Vector3(to.x, ARROW_LIFT, to.z)
		var mid := tip - flat * (length * 0.5)
		m.position = mid
		m.basis = Basis(Vector3.UP, atan2(-flat.x, -flat.z)) * Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(1.0, length, 1.0))
		var col: Color = spec["color"]
		(m.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.9)


func _make_arrow() -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(ARROW_WIDTH, 1.0, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var m := MeshInstance3D.new()
	m.name = "Arrow%d" % _arrows.size()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m

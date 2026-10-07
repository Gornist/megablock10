class_name TickFloor
extends Node3D
## Телеграф такта на полу узла (time-and-movement.md 3.4, 3.1 Т6): зрение каждого Soft ICE светом на клетках (фокус ярче, периферия тусклее; цвет — по состоянию
## ICE: стадии палитры от ледяного белого к красному), тусклое «зрение после шага» другого оттенка, стрелка к следующей клетке ICE (при предзахвате — красная,
## в клетку игрока) и «вдох»: когда сервер сообщил tk.inh, свет один раз пульсирует (яркость ×1,6 и обратно за 0,5 с).
## Клетка света — контур по границе (слой cell_vision_edge, четыре полосы) и почти прозрачная заливка (cell_vision_fill) цвета стадии ICE; фокус отличается
## от периферии яркостью контура. Клетки — два MultiMesh (заливка и контур), не узел на клетку. Только в тактовом режиме: в realtime сцена эту ноду не создаёт.
## Black ICE света не даёт: его зрение не клеточное (нет намерения), он виден пингом.

const CAPACITY := 768
const MAX_ARROWS := 8
## Высота света и стрелок над полом, м (чтобы не мерцать в одной плоскости с ним); «после шага» чуть ниже текущего.
const LIFT := 0.015
const FUTURE_LIFT := 0.008
const ARROW_LIFT := 0.03
const FOCUS_ALPHA := 0.35
const PERIPHERY_ALPHA := 0.15
## Зрение после шага: прозрачность относительно текущего и подмешанный оттенок (слой cell_future палитры Blender, берётся без его альфы).
## Цвета света — только из палитры клиентских слоёв (AssetMaterials.layer): по состоянию TickIce (Патруль, Взгляд, Проверка, Поиск) — стадии ICE
## (IceView.stage_color, как глаз ICE), стрелки — слой arrow, предзахват — ice_precapture, отпечатки шагов — trail_step / trail_dim.
const FUTURE_ALPHA := 0.5
const FUTURE_TINT_MIX := 0.55
## Отпечатки шагов (2-й и 3-й шаг ICE по state.rt): прозрачность по номеру шага, высота — между светом «после шага» и стрелкой.
const FOOT_ALPHAS := [0.30, 0.16]
const FOOT_LIFT := 0.012
## Отпечаток ICE (state.fp): яркая клетка и «?» на ней, лежащий на полу; цвет — по состоянию ICE.
const MARK_ALPHA_SCALE := 1.6
const MARK_LIFT := 0.02
const MARK_TEXT := "?"
const MARK_FONT_SIZE := 96
const MARK_PIXEL_SIZE := 0.006
const MARK_LABEL_LIFT := 0.035
const PULSE_SEC := 0.5
const PULSE_GAIN := 1.6
## Квадрат клетки чуть меньше клетки: соседние не слипаются.
const QUAD_INSET := 0.06
## Контур клетки света зрения: ширина полосы, м (как у контура OccupiedFloor) и подъём над заливкой.
const EDGE_W := 0.05
const EDGE_LIFT := 0.0005
## Стрелка: ширина, м; хвост отступает от центра клетки ICE, чтобы не лежать под ним.
const ARROW_WIDTH := 0.34
const ARROW_TAIL := 0.4
const ARROW_MIN_LEN := 0.5
const TURN_ARROW_LEN := 0.9

var _grid: NodeGrid
var _mm: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _edge: MultiMeshInstance3D
var _edge_mat: StandardMaterial3D
var _arrows: Array[MeshInstance3D] = []
var _arrow_specs: Array = []
var _foot_specs: Array = []
var _marker_specs: Array = []
var _markers: Array[Label3D] = []
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
	_mat = _vertex_color_material()
	_edge_mat = _vertex_color_material()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * (NodeGrid.CELL_M - QUAD_INSET)
	quad.material = _mat
	_mm = _multimesh("Cells", quad, CAPACITY)
	# Контур клетки: четыре полосы на клетку по границе квадрата (две вдоль X, две вдоль Z), чуть выше заливки.
	var strip := PlaneMesh.new()
	strip.size = Vector2(NodeGrid.CELL_M - QUAD_INSET, EDGE_W)
	strip.material = _edge_mat
	_edge = _multimesh("Edges", strip, CAPACITY * 4)


static func _vertex_color_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _multimesh(node_name: String, mesh: Mesh, capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


## Записать клетку n: заливка и контур одного цвета; col — логический цвет (альфа = прежняя «сила» света: фокус FOCUS_ALPHA, периферия слабее),
## на экран идут слои палитры cell_vision_fill / cell_vision_edge, умноженные на силу относительно фокуса.
func _write_cell(n: int, pos: Vector3, col: Color) -> void:
	var k := col.a / FOCUS_ALPHA
	var fill := Color(col, minf(AssetMaterials.layer("cell_vision_fill").a * k, 1.0))
	var edge := Color(col, minf(AssetMaterials.layer("cell_vision_edge").a * k, 1.0))
	var mm := _mm.multimesh
	mm.set_instance_transform(n, Transform3D(Basis(), pos))
	mm.set_instance_color(n, fill)
	var em := _edge.multimesh
	var half := (NodeGrid.CELL_M - QUAD_INSET) * 0.5 - EDGE_W * 0.5   # центр полосы от центра клетки
	var turn := Basis(Vector3.UP, PI * 0.5)   # полоса вдоль Z
	var e := pos + Vector3(0.0, EDGE_LIFT, 0.0)
	em.set_instance_transform(n * 4, Transform3D(Basis(), e + Vector3(0.0, 0.0, -half)))
	em.set_instance_transform(n * 4 + 1, Transform3D(Basis(), e + Vector3(0.0, 0.0, half)))
	em.set_instance_transform(n * 4 + 2, Transform3D(turn, e + Vector3(-half, 0.0, 0.0)))
	em.set_instance_transform(n * 4 + 3, Transform3D(turn, e + Vector3(half, 0.0, 0.0)))
	for j in 4:
		em.set_instance_color(n * 4 + j, edge)


func _process(delta: float) -> void:
	step(delta)


## Продвинуть вдох на delta секунд (сцена зовёт каждый кадр; в тестах — вручную).
func step(delta: float) -> void:
	if _pulse_left > 0.0:
		_pulse_left = maxf(_pulse_left - delta, 0.0)
	var m := brightness()
	_mat.albedo_color = Color(m, m, m, m)
	_edge_mat.albedo_color = Color(m, m, m, m)


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


## Сколько полос контура нарисовано (четыре на клетку света).
func edge_count() -> int:
	return _count * 4


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
	_foot_specs.clear()
	_marker_specs.clear()
	_cell_pos.clear()
	_cell_col.clear()
	for it: Dictionary in intents:
		if bool(it.get("black", false)):
			continue
		var base := IceView.stage_color(int(it.get("st", 0)))
		var c: Vector2i = it["c"]
		var d: Vector2i = it.get("d", Vector2i.ZERO)
		var nc: Vector2i = it.get("nc", c)
		var nd: Vector2i = it.get("nd", d)
		var sc := float(it.get("sc", TickForecast.DEFAULT_SIGHT))
		n = _put(TickVision.visible_cells(_grid, c, d, sc, TickForecast.HALF_DEG, TickForecast.FOCUS_DEG), base, 1.0, LIFT, n)
		var moves := nc != c or nd != d
		if moves:
			var tint := base.lerp(AssetMaterials.layer("cell_future", 1.0), FUTURE_TINT_MIX)
			n = _put(TickVision.visible_cells(_grid, nc, nd, sc, TickForecast.HALF_DEG, TickForecast.FOCUS_DEG), tint, FUTURE_ALPHA, FUTURE_LIFT, n)
		var spec := _arrow_for(it, c, d, nc, nd, player_cell)
		if not spec.is_empty() and _arrow_specs.size() < MAX_ARROWS:
			_arrow_specs.append(spec)
		if not TickForecast.is_precapture(it, player_cell):   # красная стрелка предзахвата приоритетнее следа
			n = _put_footprints(it, c, n)
		if it.has("fp") and _marker_specs.size() < MAX_ARROWS:   # отпечаток: клетка, где ICE заметил нетраннера (Взгляд / Проверка идёт к ней)
			var fp: Vector2i = it["fp"]
			_marker_specs.append({"cell": fp, "color": base})
			n = _put({fp: TickVision.FOCUS}, base, MARK_ALPHA_SCALE, MARK_LIFT, n)
	_count = n
	_mm.multimesh.visible_instance_count = n
	_edge.multimesh.visible_instance_count = n * 4
	_sync_arrows()
	_sync_markers()


## «Отпечатки шагов»: клетки 2-го и 3-го шага из rt (1-й — стрелка), тусклее и бледнее с каждым шагом, цвет — слои следа (trail_step, затем trail_dim).
## Стоянка (клетка повторяется или это снова клетка ICE) отпечатка не даёт. Без rt (старый сервер) — ничего.
func _put_footprints(it: Dictionary, c: Vector2i, n: int) -> int:
	var rt: Variant = it.get("rt")
	if not (rt is Array):
		return n
	var cells: Array = rt
	for i in range(1, mini(cells.size(), FOOT_ALPHAS.size() + 1)):
		var cell: Vector2i = cells[i]
		if cell == cells[i - 1] or cell == c or n >= CAPACITY:
			continue
		var a: float = FOOT_ALPHAS[i - 1]
		var p := NodeGrid.center(cell)
		var pos := Vector3(p.x, FOOT_LIFT, p.z)
		var col := AssetMaterials.layer("trail_step" if i == 1 else "trail_dim", a)
		_write_cell(n, pos, col)
		_cell_pos.append(pos)
		_cell_col.append(col)
		_foot_specs.append({"cell": cell, "step": i + 1, "alpha": a})
		n += 1
	return n


func marker_count() -> int:
	return _marker_specs.size()


## Маркер отпечатка i: {cell, color}.
func marker_spec(i: int) -> Dictionary:
	return _marker_specs[i]


func _sync_markers() -> void:
	while _markers.size() < _marker_specs.size():
		var l := Label3D.new()
		l.name = "Mark%d" % _markers.size()
		l.text = MARK_TEXT
		l.font_size = MARK_FONT_SIZE
		l.pixel_size = MARK_PIXEL_SIZE
		l.outline_size = 8
		l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # лежит на полу, читается сверху
		l.shaded = false
		Label3DSharp.apply(l)
		add_child(l)
		_markers.append(l)
	for i in _markers.size():
		var l := _markers[i]
		l.visible = i < _marker_specs.size()
		if l.visible:
			var p := NodeGrid.center(_marker_specs[i]["cell"])
			l.position = Vector3(p.x, MARK_LABEL_LIFT, p.z)
			l.modulate = _marker_specs[i]["color"]


func footprint_count() -> int:
	return _foot_specs.size()


## Отпечаток i: {cell, step (2 или 3), alpha}.
func footprint_spec(i: int) -> Dictionary:
	return _foot_specs[i]


func _put(cells: Dictionary, color: Color, alpha_scale: float, lift: float, n: int) -> int:
	for cell: Vector2i in cells:
		if n >= CAPACITY:
			break
		var a := (FOCUS_ALPHA if int(cells[cell]) == TickVision.FOCUS else PERIPHERY_ALPHA) * alpha_scale
		var p := NodeGrid.center(cell)
		var pos := Vector3(p.x, lift, p.z)
		var col := Color(color.r, color.g, color.b, a)
		_write_cell(n, pos, col)
		_cell_pos.append(pos)
		_cell_col.append(col)
		n += 1
	return n


## Стрелка ICE: предзахват — красная в клетку игрока; шаг — к следующей клетке; поворот на месте — короткая в новую сторону; стоит — нет.
func _arrow_for(it: Dictionary, c: Vector2i, _d: Vector2i, nc: Vector2i, nd: Vector2i, player_cell: Vector2i) -> Dictionary:
	if TickForecast.is_precapture(it, player_cell):
		return {"from": NodeGrid.center(nc), "to": NodeGrid.center(player_cell), "color": AssetMaterials.layer("ice_precapture"), "precapture": true}
	if nc != c:
		return {"from": NodeGrid.center(c), "to": NodeGrid.center(nc), "color": AssetMaterials.layer("arrow"), "precapture": false}
	if nd != it.get("d", Vector2i.ZERO) and nd != Vector2i.ZERO:
		var from := NodeGrid.center(c)
		return {"from": from, "to": from + Vector3(nd.x, 0.0, nd.y).normalized() * TURN_ARROW_LEN, "color": AssetMaterials.layer("arrow"), "precapture": false}
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

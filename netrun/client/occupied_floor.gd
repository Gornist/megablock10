class_name OccupiedFloor
extends Node3D
## Подсветка занятых клеток на полу (укрытия видны): каждая занятая клетка сетки 1 м (колонна, хранилище — всё, что NodeGrid.occ) получает тонкую
## светящуюся заливку приглушённого голубого. Один MultiMesh (по образцу TickFloor), не мерцает; лежит ниже света зрения ICE (TickFloor.FUTURE_LIFT),
## чтобы не перекрывать телеграф такта. Клетки берутся из сетки узла: другая раскладка — set_grid.

const CAPACITY := 256
## Высота над полом, м: под светом зрения (TickFloor.FUTURE_LIFT = 0,008), над плитой пола.
const LIFT := 0.004
## Цвета — только из палитры клиентских слоёв Blender: заливка cell_occupied_fill и контур клетки cell_occupied_edge (AssetMaterials.layer).
## Квадрат чуть меньше клетки: соседние занятые клетки не слипаются в одно пятно, видна сетка.
const QUAD_INSET := 0.08
## Контур клетки: четыре узкие полосы по краю квадрата (ширина, м) — второй MultiMesh, чуть выше заливки.
const EDGE_W := 0.03
const EDGE_LIFT := 0.0005

var _grid: NodeGrid
var _mm: MultiMeshInstance3D
var _edge: MultiMeshInstance3D
var _count := 0
## То же, что записано в MultiMesh: под headless-рендером MultiMesh ничего не хранит, а тестам нужно проверить положение.
var _cell_pos := PackedVector3Array()


func _init(grid: NodeGrid = null) -> void:
	name = "OccupiedFloor"
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * (NodeGrid.CELL_M - QUAD_INSET)
	quad.material = _material("cell_occupied_fill")
	_mm = _multimesh("Cells", quad, CAPACITY)
	# Контур: четыре полосы на клетку (две вдоль X, две вдоль Z), сторона квадрата — как у заливки.
	var strip := PlaneMesh.new()
	strip.size = Vector2(NodeGrid.CELL_M - QUAD_INSET, EDGE_W)
	strip.material = _material("cell_occupied_edge")
	_edge = _multimesh("Edges", strip, CAPACITY * 4)
	set_grid(grid if grid != null else NodeGrid.for_layout())


## Материал слоя палитры: без освещения, с прозрачностью (альфа слоя уже в цвете).
static func _material(layer: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = AssetMaterials.layer(layer)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _multimesh(node_name: String, mesh: Mesh, capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


## Занятые клетки другой сетки (переход между узлами с разной раскладкой): заливка перестраивается сразу.
func set_grid(grid: NodeGrid) -> void:
	_grid = grid if grid != null else NodeGrid.for_layout()
	_rebuild()


## Сколько клеток подсвечено.
func cell_count() -> int:
	return _count


## Цвет заливки и контура, как их видит рендер (для тестов: должны совпадать со слоями палитры).
func fill_color() -> Color:
	return ((_mm.multimesh.mesh as PlaneMesh).material as StandardMaterial3D).albedo_color


func edge_color() -> Color:
	return ((_edge.multimesh.mesh as PlaneMesh).material as StandardMaterial3D).albedo_color


## Сколько полос контура нарисовано (четыре на клетку).
func edge_count() -> int:
	return _count * 4


## Центр отметки i (для тестов).
func cell_position(i: int) -> Vector3:
	return _cell_pos[i]


func _rebuild() -> void:
	var cells: Array[Vector2i] = []
	for c: Vector2i in _grid.occ:
		if NodeGrid.in_bounds(c):
			cells.append(c)
	cells.sort()   # порядок не зависит от порядка вставки: тест и кадр одинаковы
	_cell_pos.clear()
	var mm := _mm.multimesh
	var em := _edge.multimesh
	var half := (NodeGrid.CELL_M - QUAD_INSET) * 0.5 - EDGE_W * 0.5   # центр полосы от центра клетки
	var turn := Basis(Vector3.UP, PI * 0.5)   # полоса вдоль Z
	var n := 0
	for c in cells:
		if n >= CAPACITY:
			break
		var p := NodeGrid.center(c)
		var pos := Vector3(p.x, LIFT, p.z)
		mm.set_instance_transform(n, Transform3D(Basis(), pos))
		var e := pos + Vector3(0.0, EDGE_LIFT, 0.0)
		em.set_instance_transform(n * 4, Transform3D(Basis(), e + Vector3(0.0, 0.0, -half)))
		em.set_instance_transform(n * 4 + 1, Transform3D(Basis(), e + Vector3(0.0, 0.0, half)))
		em.set_instance_transform(n * 4 + 2, Transform3D(turn, e + Vector3(-half, 0.0, 0.0)))
		em.set_instance_transform(n * 4 + 3, Transform3D(turn, e + Vector3(half, 0.0, 0.0)))
		_cell_pos.append(pos)
		n += 1
	_count = n
	mm.visible_instance_count = n
	em.visible_instance_count = n * 4

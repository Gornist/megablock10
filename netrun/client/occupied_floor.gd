class_name OccupiedFloor
extends Node3D
## Подсветка занятых клеток на полу (укрытия видны): каждая занятая клетка сетки 1 м (колонна, хранилище — всё, что NodeGrid.occ) получает тонкую
## светящуюся заливку приглушённого голубого. Один MultiMesh (по образцу TickFloor), не мерцает; лежит ниже света зрения ICE (TickFloor.FUTURE_LIFT),
## чтобы не перекрывать телеграф такта. Клетки берутся из сетки узла: другая раскладка — set_grid.

const CAPACITY := 256
## Высота над полом, м: под светом зрения (TickFloor.FUTURE_LIFT = 0,008), над плитой пола.
const LIFT := 0.004
## Приглушённый голубой (тон рук и интерфейса клиента, HandView.COLOR_HAND) и прозрачность заливки.
const COLOR := Color(0.18, 0.55, 0.7, 0.22)
## Квадрат чуть меньше клетки: соседние занятые клетки не слипаются в одно пятно, видна сетка.
const QUAD_INSET := 0.08

var _grid: NodeGrid
var _mm: MultiMeshInstance3D
var _count := 0
## То же, что записано в MultiMesh: под headless-рендером MultiMesh ничего не хранит, а тестам нужно проверить положение.
var _cell_pos := PackedVector3Array()


func _init(grid: NodeGrid = null) -> void:
	name = "OccupiedFloor"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * (NodeGrid.CELL_M - QUAD_INSET)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Cells"
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	set_grid(grid if grid != null else NodeGrid.for_layout())


## Занятые клетки другой сетки (переход между узлами с разной раскладкой): заливка перестраивается сразу.
func set_grid(grid: NodeGrid) -> void:
	_grid = grid if grid != null else NodeGrid.for_layout()
	_rebuild()


## Сколько клеток подсвечено.
func cell_count() -> int:
	return _count


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
	var n := 0
	for c in cells:
		if n >= CAPACITY:
			break
		var p := NodeGrid.center(c)
		var pos := Vector3(p.x, LIFT, p.z)
		mm.set_instance_transform(n, Transform3D(Basis(), pos))
		_cell_pos.append(pos)
		n += 1
	_count = n
	mm.visible_instance_count = n

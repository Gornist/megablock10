class_name BarrierView
extends Node3D
## Барьер Soft ICE (ice/barrier_ice.glb, docs/gamedesign/ice.md §5): стена кода на блоке 2×2 карты. Состояния модели — узлы State_closed / State_opening / State_open
## (видим ровно один; без явного выключения видны все). Данные — элемент поля `br` state: {id, c: [[x, z], …] клетки блока, open 0/1}.

const ASSET := NodeAssets.ROOT + "ice/barrier_ice.glb"
const STATES := ["State_closed", "State_opening", "State_open"]

var _model: Node3D
var _open := -1


func _init() -> void:
	_model = NodeAssets.instance(ASSET)
	_model.name = "Model"
	add_child(_model)


## Центр блока по его клеткам 1 м: среднее центров клеток.
static func center_of(cells: Array) -> Vector3:
	var sum := Vector3.ZERO
	for c: Variant in cells:
		sum += NodeGrid.center(Vector2i(int((c as Array)[0]), int((c as Array)[1])))
	return sum / float(maxi(cells.size(), 1))


## Имя видимого узла состояния: открыт — State_open, иначе State_closed.
static func state_node_of(open: int) -> String:
	return "State_open" if open == 1 else "State_closed"


func apply_view(v: Dictionary) -> void:
	position = center_of(v["c"])
	var open := int(v.get("open", 0))
	if open == _open:
		return
	_open = open
	var shown := state_node_of(open)
	for s: String in STATES:
		var n := _model.find_child(s, true, false) as Node3D
		if n != null:
			n.visible = (s == shown)

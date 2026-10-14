class_name SensorView
extends Node3D
## Датчик Soft ICE (ice/sensor_ice.glb, docs/gamedesign/ice.md §5): пара излучателей лицом друг к другу по краям луча, один `Beam` на пару
## (масштаб по Z — длина в клетках). Состояние луча — AssetMaterials.set_beam: горит / мигает за такт до включения / погашен.
## Данные — элемент поля `sn` state: {id, c: [[x, z], …] клетки луча по порядку, on 0/1, bl 0/1, l тактов до смены}.

const ASSET := NodeAssets.ROOT + "ice/sensor_ice.glb"

var _a: Node3D
var _b: Node3D
var _beam: Node3D
var _cells: Array = []
var _state := -1


func _init() -> void:
	_a = NodeAssets.instance(ASSET)
	_a.name = "EmitterA"
	add_child(_a)
	_b = NodeAssets.instance(ASSET)
	_b.name = "EmitterB"
	add_child(_b)
	_beam = _a.find_child("Beam", true, false) as Node3D
	var b_beam := _b.find_child("Beam", true, false) as Node3D
	if b_beam != null:
		b_beam.visible = false   # луч один на пару


## Состояние луча по полям снимка: 1 — горит, мигает перед включением, иначе погашен.
static func beam_state_of(v: Dictionary) -> int:
	if int(v.get("on", 0)) == 1:
		return AssetMaterials.BEAM_ON
	return AssetMaterials.BEAM_BLINK if int(v.get("bl", 0)) == 1 else AssetMaterials.BEAM_OFF


func apply_view(v: Dictionary) -> void:
	var cells: Array = v["c"]
	if cells != _cells and cells.size() >= 2:
		_cells = cells
		var first := Vector2i(int(cells[0][0]), int(cells[0][1]))
		var last := Vector2i(int(cells[cells.size() - 1][0]), int(cells[cells.size() - 1][1]))
		var d := Vector2i(signi(last.x - first.x), signi(last.y - first.y))
		var yaw := BeaconView.yaw_of(d)
		var dir3 := Vector3(d.x, 0.0, d.y)
		_a.position = NodeGrid.center(first) - dir3 * 0.5   # излучатели на краях луча, на границах клеток
		_a.rotation.y = yaw
		_b.position = NodeGrid.center(last) + dir3 * 0.5
		_b.rotation.y = yaw + PI
		if _beam != null:
			_beam.scale = Vector3(1.0, 1.0, float(cells.size()))
	var st := beam_state_of(v)
	if st != _state:
		_state = st
		AssetMaterials.set_beam(_a, st)

class_name BeaconView
extends Node3D
## Маяк Soft ICE (ice/lighthouse_ice.glb, docs/gamedesign/ice.md §5): тумба на клетке, голова `Head` поворачивается за такт к следующему углу
## (плавно, TURN_SEC), веер `Beam` под головой — дальность зрения в клетках (равномерный масштаб: радиус веера в модели 1 м).
## Данные — элемент поля `bk` state: {id, c: [x, z], d: [dx, dz], nd: [dx, dz], aw, r}. Угол 0 — на север (−z), +45° — на северо-восток.

const ASSET := NodeAssets.ROOT + "ice/lighthouse_ice.glb"
const TURN_SEC := 0.4

var _model: Node3D
var _head: Node3D
var _beam: Node3D
var _dir := Vector2i.ZERO
var _tween: Tween


func _init() -> void:
	_model = NodeAssets.instance(ASSET)
	_model.name = "Model"
	add_child(_model)
	_head = _model.find_child("Head", true, false) as Node3D
	_beam = _model.find_child("Beam", true, false) as Node3D
	AssetMaterials.set_beam(_model, AssetMaterials.BEAM_ON)


## Угол поворота головы вокруг Y для направления клетки (dx, dz): север (0, −1) — 0, восток (1, 0) — −90°.
static func yaw_of(d: Vector2i) -> float:
	return atan2(-float(d.x), -float(d.y))


func apply_view(v: Dictionary) -> void:
	var c: Array = v["c"]
	position = NodeGrid.center(Vector2i(int(c[0]), int(c[1])))
	var d: Array = v["d"]
	var dir := Vector2i(int(d[0]), int(d[1]))
	if _beam != null:
		_beam.scale = Vector3.ONE * float(v.get("r", 5.0))
	if dir == _dir:
		return
	var first := _dir == Vector2i.ZERO
	_dir = dir
	if _head == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var to := yaw_of(dir)
	if first:
		_head.rotation.y = to
		return
	var from := _head.rotation.y
	_tween = create_tween()
	_tween.tween_method(func(t: float): _head.rotation.y = lerp_angle(from, to, t), 0.0, 1.0, TURN_SEC)


## Угол головы сейчас (для тестов), радианы.
func head_yaw() -> float:
	return _head.rotation.y if _head != null else 0.0

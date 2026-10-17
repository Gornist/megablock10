class_name BeaconView
extends Node3D
## Маяк Soft ICE (ice/lighthouse_ice.glb, docs/gamedesign/ice.md §5): тумба на клетке, голова `Head` поворачивается за такт к следующему углу
## (плавно, TURN_SEC), веер `Beam` под головой — дальность зрения в клетках (равномерный масштаб: радиус веера в модели 1 м).
## Данные — элемент поля `bk` state: {id, c: [x, z], d: [dx, dz], nd: [dx, dz], aw, r}. Угол 0 — на север (−z), +45° — на северо-восток.

const ASSET := NodeAssets.ROOT + "ice/lighthouse_ice.glb"
const TURN_SEC := 0.4
const FOCUS_DEG := 25.0   ## угол зрения Маяка (TickBeacon.DEFAULTS focus_deg; клиент каталога server/ не читает)
const FAN_Y := 0.03       ## высота веера над полом, м

var _fan: MeshInstance3D
var _fan_key := ""
var _fan_cells := -1
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


## grid — сетка узла с занятыми клетками: веер строится по клеткам, которые Маяк видит (TickVision, закрыты колоннами и укрытиями), а не фиксированным
## мешем, который шёл бы сквозь колонны (Game 16.10: «что видно, то и работает»). Без сетки (тесты, превью) остаётся веер модели.
func apply_view(v: Dictionary, grid: NodeGrid = null) -> void:
	var c: Array = v["c"]
	var cell := Vector2i(int(c[0]), int(c[1]))
	position = NodeGrid.center(cell)
	var d: Array = v["d"]
	var dir := Vector2i(int(d[0]), int(d[1]))
	var r := float(v.get("r", 5.0))
	if _beam != null:
		_beam.scale = Vector3.ONE * r
	if grid != null:
		_build_fan(grid, cell, dir, r)
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


## Веер по клеткам зрения: клетки, видимые из тумбы по направлению dir на дальность r (TickVision, фокус как у сервера), — квады на полу с UV веера
## (u — доля радиуса, v — угол от края до края), материал веера модели; веер модели скрыт. Свой блок тумбы не загораживает взгляд — как на сервере (TickBeacon).
func _build_fan(grid: NodeGrid, cell: Vector2i, dir: Vector2i, r: float) -> void:
	var key := "%s|%s|%s|%d" % [cell, dir, r, grid.occ.size()]
	if key == _fan_key:
		return
	_fan_key = key
	var mat := _fan_material()
	if mat == null or dir == Vector2i.ZERO:
		return
	var g := grid.duplicate_grid()
	var bx := cell.x - posmod(cell.x, 2)
	var by := cell.y - posmod(cell.y, 2)
	for dx in 2:
		for dy in 2:
			g.occ.erase(Vector2i(bx + dx, by + dy))
	var cells := TickVision.visible_cells(g, cell, dir, r, FOCUS_DEG, FOCUS_DEG)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var origin := NodeGrid.center(cell)
	var dirv := Vector2(dir.x, dir.y).normalized()
	for c: Vector2i in cells:
		var mid := NodeGrid.center(c) - origin
		var base := verts.size()
		for k in 4:
			var p := Vector2(mid.x + (0.5 if k % 2 == 1 else -0.5), mid.z + (0.5 if k >= 2 else -0.5))
			verts.append(Vector3(p.x, FAN_Y, p.y))
			var ang := atan2(dirv.x * p.y - dirv.y * p.x, dirv.dot(p))
			uvs.append(Vector2(clampf(p.length() / maxf(r, 0.001), 0.0, 1.0), clampf(0.5 + ang / (2.0 * deg_to_rad(FOCUS_DEG)), 0.0, 1.0)))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	if _fan == null:
		_fan = MeshInstance3D.new()
		_fan.name = "FanCells"
		_fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model.add_child(_fan)
	if idx.is_empty():
		_fan.mesh = null
	else:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_fan.mesh = mesh
		_fan.set_surface_override_material(0, mat)
	_fan_cells = cells.size()
	if _beam != null:
		_beam.visible = false


## Число клеток веера (для тестов); -1 — веер модели.
func fan_cell_count() -> int:
	return _fan_cells


## Материал веера из модели: у меша под узлом Beam; общий с ним, чтобы состояния (set_beam) действовали и на веер по клеткам.
func _fan_material() -> Material:
	if _beam == null:
		return null
	for n in _beam.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var m := mi.get_surface_override_material(0)
			if m != null:
				return m
	return null


## Угол головы сейчас (для тестов), радианы.
func head_yaw() -> float:
	return _head.rotation.y if _head != null else 0.0

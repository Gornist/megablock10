extends Node3D
## Витрина: все модели клиента (res://assets/models/**.glb) в одной сцене сеткой с подписями; облако (Б) включено у моделей с файлом `.points`
## (рядом с обычной моделью — копия «+ облако»). Вид — умолчания клиента: окружение и свет как в rig_test_scene, msaa 2.
## Снимает КЛИЕНТОМ (не очки: кадр VR с устройства снять нельзя — XrDiag и screencap пустые): `netrun/tools/dev.sh shot res://tests/showcase_preview.tscn`.
## Кадры: overview (вся витрина), затем по группам по два ряда — env_1.., props_1.., ice_1, deck_1.., avatar_1 — и cloud (облако крупно).
## Размеры: крупные модели уменьшены до MAX_SIZE, мелкие увеличены до MIN_SIZE — масштаб в подписи (×k). Размер кадра — SHOT_SIZE.

const SHOT_SIZE := 1024
const CELL := Vector3(2.7, 0.0, 3.6)   # шаг сетки: x — между моделями, z — между рядами
const COLUMNS := 5
const MAX_SIZE := 2.2
const MIN_SIZE := 0.8
const CLOUD_MIN_SIZE := 1.6   # в ряду «облако крупно» мелкое (шард 13 см) растим сильнее
const MODELS_DIR := "res://assets/models"
const GROUPS := ["env", "props", "ice", "deck", "avatar"]
const ROWS_PER_FRAME := 2
## Колонка блока на общем плане (0 — слева, 1 — справа) и расстояние между колонками по x.
const COLUMN_OF := {"env": 0, "ice": 0, "avatar": 0, "props": 1, "deck": 1}
const COLUMN_GAP := 15.0

var _out := "/tmp/showcase_shots"
var _frames: Array[Dictionary] = []   # {name, min: Vector3, max: Vector3} — центры ячеек блока кадра


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	VolumeRegistry.configure("all")
	_build_world()
	# две колонки блоков рядом: так общий план ближе к квадрату и подписи крупнее
	var col_z := [0.0, 0.0]
	for g: String in GROUPS:
		var col: int = COLUMN_OF[g]
		col_z[col] = _build_group(g, col * COLUMN_GAP, col_z[col])
	_build_cloud_row(maxf(col_z[0], col_z[1]))
	_add_floor()
	await get_tree().process_frame
	await _shoot_all()
	get_tree().quit()


func _build_world() -> void:
	var rig_script := preload("res://client/rig_test_scene.gd")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.024, 0.03)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = rig_script.AMBIENT_COLOR
	env.environment.ambient_light_energy = rig_script.AMBIENT_ENERGY
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 0.6
	add_child(sun)


## Пути моделей группы (по алфавиту; имена берём и из `.glb.import`, если сам `.glb` в экспорте переименован).
func _paths_of(group: String) -> Array[String]:
	var paths: Array[String] = []
	var d := DirAccess.open("%s/%s" % [MODELS_DIR, group])
	if d == null:
		return paths
	for f in d.get_files():
		var n := f.trim_suffix(".import")
		var p := "%s/%s/%s" % [MODELS_DIR, group, n]
		if n.ends_with(".glb") and not paths.has(p):
			paths.append(p)
	paths.sort()
	return paths


## Ряды группы; на каждые ROWS_PER_FRAME ряда — кадр. Возвращает следующий z.
func _build_group(group: String, x0: float, z0: float) -> float:
	var cells: Array = []
	for p in _paths_of(group):
		cells.append({"path": p, "cloud": false})
		if FileAccess.file_exists(VolumeRegistry.points_path(p)):
			cells.append({"path": p, "cloud": true})
	var rows := int(ceil(float(cells.size()) / COLUMNS))
	for i in cells.size():
		var c: Dictionary = cells[i]
		var pos := Vector3(x0 + (i % COLUMNS) * CELL.x, 0.0, z0 + (i / COLUMNS) * CELL.z)
		_place_model(c["path"], bool(c["cloud"]), pos, MIN_SIZE)
	var frame_no := 0
	var r := 0
	while r < rows:
		var last := mini(r + ROWS_PER_FRAME, rows) - 1
		var width := mini(cells.size() - r * COLUMNS, COLUMNS)   # ячеек в первом ряду кадра (≥ ширины последнего)
		frame_no += 1
		_frames.append({"name": "%s_%d" % [group, frame_no],
			"min": Vector3(x0, 0, z0 + r * CELL.z),
			"max": Vector3(x0 + (width - 1) * CELL.x, 0, z0 + last * CELL.z)})
		r += ROWS_PER_FRAME
	return z0 + (rows + 0.5) * CELL.z


## Ряд «облако крупно»: у каждой модели с `.points` — обычная и с облаком, крупнее.
func _build_cloud_row(z0: float) -> void:
	var paths: Array[String] = []
	for g: String in GROUPS:
		for p in _paths_of(g):
			if FileAccess.file_exists(VolumeRegistry.points_path(p)):
				paths.append(p)
	var i := 0
	for p in paths:
		for with_cloud in [false, true]:
			_place_model(p, with_cloud, Vector3((i % 6) * CELL.x * 1.1, 0.0, z0 + (i / 6) * CELL.z * 1.3), CLOUD_MIN_SIZE)
			i += 1
	var rows := int(ceil(float(i) / 6.0))
	_frames.append({"name": "cloud", "min": Vector3(0, 0, z0), "max": Vector3(5 * CELL.x * 1.1, 0, z0 + (rows - 1) * CELL.z * 1.3)})


func _place_model(path: String, with_cloud: bool, pos: Vector3, min_size: float) -> void:
	var node := NodeAssets.instance(path)
	var box := _aabb_of(path)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var k := 1.0
	if longest > MAX_SIZE:
		k = MAX_SIZE / longest
	elif longest > 0.0 and longest < min_size:
		k = min_size / longest
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	node.scale = Vector3.ONE * k
	var c := box.get_center()
	node.position = Vector3(-c.x * k, -box.position.y * k, -c.z * k)   # центр основания — в центр ячейки, низ на полу
	holder.add_child(node)
	if with_cloud:
		var cloud := VolumeRegistry.spawn(path.get_file().get_basename(), path, AssetMaterials.layer("hud_ok"), AABB())
		if cloud != null:
			node.add_child(cloud)
	var label := Label3D.new()
	var name_ := path.get_file().get_basename() + ("\n+ облако" if with_cloud else "")
	label.text = name_ if is_equal_approx(k, 1.0) else "%s\n×%.2f" % [name_, k]
	label.font_size = 44
	label.pixel_size = 0.0065
	label.outline_size = 8
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.width = 330
	label.modulate = Color(0.75, 0.95, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, -0.05, 1.05)
	holder.add_child(label)


## Габарит модели по её мешам (NodeAssets.mesh_parts: меш + поза).
func _aabb_of(path: String) -> AABB:
	var out := AABB()
	var first := true
	for part in NodeAssets.mesh_parts(path):
		var mesh := part["mesh"] as Mesh
		if mesh == null:
			continue
		var xf: Transform3D = part["xform"]
		var b := xf * mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	if first:
		return AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return out


func _add_floor() -> void:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	m.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.04, 0.05)
	mat.roughness = 1.0
	m.material_override = mat
	m.position = Vector3(COLUMN_GAP, -0.02, 40)
	add_child(m)


func _shoot_all() -> void:
	var render := RenderConfig.new()
	var vp := SubViewport.new()
	vp.size = Vector2i(SHOT_SIZE, SHOT_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render.apply_msaa(vp)
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for f in _frames:
		mn = Vector3(minf(mn.x, f["min"].x), 0, minf(mn.z, f["min"].z))
		mx = Vector3(maxf(mx.x, f["max"].x), 0, maxf(mx.z, f["max"].z))
	await _snap(cam, vp, "overview", mn, mx, 60.0)
	for f in _frames:
		await _snap(cam, vp, str(f["name"]), f["min"], f["max"], 50.0)


## Камера впереди-сверху блока: видно ряды и подписи (billboard); дистанция по половине большей стороны блока.
func _snap(cam: Camera3D, vp: SubViewport, name_: String, mn: Vector3, mx: Vector3, fov: float) -> void:
	var center := (mn + mx) * 0.5
	var half := maxf((mx.x - mn.x) * 0.5, (mx.z - mn.z) * 0.55) + 4.5   # запас: подписи и модели выходят за центры ячеек, ближний ряд шире кадра из-за перспективы
	var dist := half / tan(deg_to_rad(fov * 0.5))
	cam.fov = fov
	cam.look_at_from_position(center + Vector3(0, dist * 0.7, dist * 0.7), center + Vector3(0, 0.4, 0), Vector3.UP)
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s.png" % [_out, name_])

extends GdUnitTestSuite
## Облако по мешам модели на лету (client/volume_sampler.gd) и его подключение в VolumeRegistry и NodeView.


## Квадрат со стороной s на плоскости y = 0 из двух треугольников (6 вершин).
func _quad(s: float, at: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	return PackedVector3Array([
		at + Vector3(0, 0, 0), at + Vector3(s, 0, 0), at + Vector3(s, 0, s),
		at + Vector3(0, 0, 0), at + Vector3(s, 0, s), at + Vector3(0, 0, s)])


func test_число_точек_и_запись_как_в_файле_points() -> void:
	var pts := VolumeSampler.sample_triangles(_quad(2.0), 200, 1)
	assert_int(VolumeCloud.points_in(pts)).is_equal(200)
	assert_int(pts.size()).is_equal(200 * VolumeCloud.POINT_FLOATS)
	for i in 200:
		var o := i * VolumeCloud.POINT_FLOATS
		assert_float(pts[o]).is_between(0.0, 2.0)
		assert_float(pts[o + 1]).is_equal(0.0)
		assert_float(pts[o + 2]).is_between(0.0, 2.0)
		assert_float(pts[o + 3]).is_equal_approx(VolumeSampler.HALF_SIZE, 0.0001)
		assert_float(pts[o + 4]).is_between(0.0, 1.0)
		assert_bool(pts[o + 5] == 0.0 or pts[o + 5] == 1.0).is_true()
		assert_float(pts[o + 6]).is_between(VolumeSampler.BODY_WEIGHT - 0.001, 1.001)


func test_детерминировано_по_зерну_и_зерно_меняет_результат() -> void:
	var a := VolumeSampler.sample_triangles(_quad(1.0), 50, 7)
	var b := VolumeSampler.sample_triangles(_quad(1.0), 50, 7)
	var c := VolumeSampler.sample_triangles(_quad(1.0), 50, 8)
	assert_bool(a == b).is_true()
	assert_bool(a == c).is_false()


func test_точки_распределены_по_площади_а_не_по_числу_треугольников() -> void:
	# большой квадрат 3×3 (9 м²) и маленький 1×1 (1 м²) в стороне: в маленьком ≈ 10% точек
	var tris := _quad(3.0)
	tris.append_array(_quad(1.0, Vector3(10, 0, 0)))
	var pts := VolumeSampler.sample_triangles(tris, 4000, 3)
	var small := 0
	for i in 4000:
		if pts[i * VolumeCloud.POINT_FLOATS] > 5.0:
			small += 1
	assert_int(small).is_between(300, 500)


func test_префикс_равномерная_выборка_для_лод() -> void:
	# первая восьмая часть точек покрывает тот же квадрат, а не его уголок: среднее ≈ центр
	var pts := VolumeSampler.sample_triangles(_quad(2.0), 2000, 5)
	var n := 250
	var sx := 0.0
	var sz := 0.0
	for i in n:
		sx += pts[i * VolumeCloud.POINT_FLOATS]
		sz += pts[i * VolumeCloud.POINT_FLOATS + 2]
	assert_float(sx / n).is_between(0.8, 1.2)
	assert_float(sz / n).is_between(0.8, 1.2)


func test_пустые_и_вырожденные_входы_дают_пустой_массив() -> void:
	assert_bool(VolumeSampler.sample_triangles(PackedVector3Array(), 10, 1).is_empty()).is_true()
	assert_bool(VolumeSampler.sample_triangles(_quad(1.0), 0, 1).is_empty()).is_true()
	var flat := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])   # нулевая площадь
	assert_bool(VolumeSampler.sample_triangles(flat, 10, 1).is_empty()).is_true()
	assert_bool(VolumeSampler.sample_parts([], 10, 1).is_empty()).is_true()


func test_части_модели_берут_позу_xform() -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _quad(1.0)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var parts := [{"mesh": mesh, "xform": Transform3D(Basis.IDENTITY, Vector3(5, 2, 0))}]
	var pts := VolumeSampler.sample_parts(parts, 100, 2)
	for i in 100:
		assert_float(pts[i * VolumeCloud.POINT_FLOATS]).is_between(5.0, 6.0)
		assert_float(pts[i * VolumeCloud.POINT_FLOATS + 1]).is_equal(2.0)


func test_габарит_охватывает_точки_с_запасом() -> void:
	var pts := VolumeSampler.sample_triangles(_quad(2.0), 300, 4)
	var box := VolumeSampler.bounds_of(pts)
	assert_bool(box.has_point(Vector3(1, 0, 1))).is_true()
	assert_float(box.size.x).is_between(2.0, 2.0 + 4.0 * VolumeSampler.HALF_SIZE)
	assert_vector(VolumeSampler.bounds_of(PackedFloat32Array()).size).is_equal(Vector3.ZERO)


## Модель, у которой рядом нет `.points` (генератор Blender пишет файлы только для vault/portal/shard…): на ней проверяется запасной путь
## «сэмплировать поверхность на лету». Появится файл у обеих — тест скажет прямо, а не упадёт на чужом условии.
func _model_without_points() -> String:
	for name in ["sensor", "portal_locked"]:
		var path := "res://assets/models/props/%s.glb" % name
		if not FileAccess.file_exists(VolumeRegistry.points_path(path)):
			return path
	return ""


func test_spawn_без_файла_сэмплирует_модель_и_число_по_модулю() -> void:
	var model := _model_without_points()
	assert_str(model).override_failure_message("нет модели без .points среди sensor/portal_locked — запасной путь не на чем проверить").is_not_empty()
	if model == "":
		return
	VolumeRegistry.configure("portal")
	var c := VolumeRegistry.spawn("portal", model, Color.WHITE, AABB())
	assert_object(c).is_not_null()
	if c != null:
		assert_int(c.point_count()).is_equal(int(VolumeRegistry.SAMPLE_COUNTS["portal"]))
		c.free()
	VolumeRegistry.configure("off")
	assert_object(VolumeRegistry.spawn("portal", model, Color.WHITE, AABB())).is_null()


func _node_info() -> Dictionary:
	var sp: Vector3 = NodeLayout.SHARD_SLOTS[0]
	var pp: Vector3 = NodeLayout.PORTAL_SLOTS[0]
	return {"kind": "node", "node": "node_x", "title": "Тест", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS,
		"shards": [{"id": "node_x_pk0", "p": [sp.x, sp.y, sp.z], "ready": true}],
		"portals": [{"to": "n2", "title": "n2", "tier": "BASE", "p": [pp.x, pp.z], "open": true}]}


func test_nodeview_без_volumetric_облаков_нет_с_ним_у_хранилища_и_портала() -> void:
	VolumeRegistry.configure("off")
	var scene: Node3D = auto_free(preload("res://client/world_scene.gd").new())
	add_child(scene)
	scene.apply_node(_node_info())
	assert_int(scene.view.find_children("Cloud_*", "Node3D", true, false).size()).is_equal(0)
	VolumeRegistry.configure("vault,portal")
	scene.apply_node(_node_info())
	assert_int(scene.view.find_children("Cloud_vault", "Node3D", true, false).size()).is_equal(1)
	assert_int(scene.view.find_children("Cloud_portal", "Node3D", true, false).size()).is_equal(1)
	VolumeRegistry.configure("off")

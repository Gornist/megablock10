extends GdUnitTestSuite
## Дальность прорисовки (`[render] far_cull_m`, владелец 19.10): дальше предела модели и облака не рисуются — вдали они были сплошным чёрным телом.


func after_test() -> void:
	NodeAssets.far_cull_m = 0.0


func test_без_предела_видимость_не_ограничена() -> void:
	NodeAssets.far_cull_m = 0.0
	var m := auto_free(MeshInstance3D.new()) as MeshInstance3D
	NodeAssets.limit_range(m)
	assert_float(m.visibility_range_end).is_equal(0.0)


func test_предел_ставится_на_все_меши_под_узлом() -> void:
	NodeAssets.far_cull_m = 12.0
	var root := auto_free(Node3D.new()) as Node3D
	var a := MeshInstance3D.new()
	var inner := Node3D.new()
	var b := MeshInstance3D.new()
	root.add_child(a)
	root.add_child(inner)
	inner.add_child(b)
	NodeAssets.limit_range(root)
	assert_float(a.visibility_range_end).is_equal(12.0)
	assert_float(b.visibility_range_end).is_equal(12.0)


func test_модель_из_instance_получает_предел() -> void:
	NodeAssets.far_cull_m = 9.0
	var n := auto_free(NodeAssets.instance(NodeAssets.prop_path("vault"))) as Node3D
	var meshes := n.find_children("*", "GeometryInstance3D", true, false)
	assert_bool(meshes.is_empty()).is_false()
	for g in meshes:
		assert_float((g as GeometryInstance3D).visibility_range_end).is_equal(9.0)


func test_облако_не_рисуется_дальше_предела() -> void:
	NodeAssets.far_cull_m = 7.0
	var c := auto_free(VolumeCloud.new()) as VolumeCloud
	add_child(c)
	var pts := PackedFloat32Array()
	for i in 4:
		pts.append_array(PackedFloat32Array([float(i) * 0.1, 0.0, 0.0, 0.02, 0.0, 0.0, 1.0]))
	c.setup(pts, Color.WHITE, AABB(Vector3.ZERO, Vector3.ONE))
	var mmi := c.find_child("Particles", true, false) as MultiMeshInstance3D
	assert_object(mmi).is_not_null()
	assert_float(mmi.visibility_range_end).is_equal(7.0)

extends GdUnitTestSuite
## Проводка облаков (Б) на клиенте (Blender, PR 346): каждый кадр — дыхание по такту хода и отклик на руки и чужие аватары.

var _scene: Node3D


func before_test() -> void:
	_scene = preload("res://client/rig_test_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame


func after_test() -> void:
	_scene.queue_free()


func _cloud() -> ShaderMaterial:
	var host := Node3D.new()
	host.add_to_group("volume_clouds")
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	quad.material = mat
	mm.mesh = quad
	mmi.multimesh = mm
	host.add_child(mmi)
	_scene.add_child(host)
	return mat


func test_без_рук_и_аватаров_источников_нет() -> void:
	assert_array(_scene.cloud_touch_sources()).is_empty()


func test_чужие_аватары_становятся_источниками_с_радиусом_и_высотой() -> void:
	var a := Node3D.new()
	_scene.add_child(a)
	a.global_position = Vector3(2.0, 0.0, 3.0)
	_scene._avatar_nodes["a1"] = a
	var s: Array = _scene.cloud_touch_sources()
	assert_int(s.size()).is_equal(1)
	assert_float((s[0] as Vector4).w).is_equal_approx(_scene.CLOUD_TOUCH_AVATAR_R, 0.0001)
	assert_float((s[0] as Vector4).y).is_equal_approx(_scene.CLOUD_TOUCH_AVATAR_Y, 0.001)
	assert_float((s[0] as Vector4).x).is_equal_approx(2.0, 0.001)
	_scene._avatar_nodes.erase("a1")
	a.queue_free()


func test_источников_не_больше_четырёх() -> void:
	for i in 6:
		var a := Node3D.new()
		_scene.add_child(a)
		_scene._avatar_nodes["a%d" % i] = a
	assert_int(_scene.cloud_touch_sources().size()).is_equal(_scene.CLOUD_TOUCH_MAX)
	for id in _scene._avatar_nodes.keys():
		(_scene._avatar_nodes[id] as Node).queue_free()
	_scene._avatar_nodes.clear()


func test_кадр_передаёт_облакам_дыхание_и_отклик() -> void:
	var mat := _cloud()
	var a := Node3D.new()
	_scene.add_child(a)
	a.global_position = Vector3(1.0, 0.0, 1.0)
	_scene._avatar_nodes["a1"] = a
	_scene._update_cloud(Time.get_ticks_msec() / 1000.0)
	assert_float(float(mat.get_shader_parameter("breath_phase"))).is_between(0.0, 1.0)
	var touch: Vector4 = mat.get_shader_parameter("touch_a")
	assert_float(touch.w).is_equal_approx(_scene.CLOUD_TOUCH_AVATAR_R, 0.0001)
	_scene._avatar_nodes.erase("a1")
	a.queue_free()
	_scene._update_cloud(Time.get_ticks_msec() / 1000.0)
	assert_object(mat.get_shader_parameter("touch_a")).is_equal(Vector4.ZERO)   # источник ушёл — слот погашен, следа нет


func test_без_облаков_кадр_ничего_не_ломает() -> void:
	_scene._update_cloud(1.0)
	assert_bool(true).is_true()

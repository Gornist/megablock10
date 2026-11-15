extends GdUnitTestSuite
## Прогрев шейдеров (client/shader_warmup.gd): образцы материалов мира и чёрный экран перед камерой на N кадров, потом всё освобождается.

var _cam: Camera3D
var _warm: ShaderWarmup


func before_test() -> void:
	ShaderWarmup.enabled = true
	_cam = auto_free(Camera3D.new())
	add_child(_cam)
	_warm = auto_free(ShaderWarmup.new())
	add_child(_warm)


func after_test() -> void:
	ShaderWarmup.enabled = false


func test_по_умолчанию_выключен() -> void:
	ShaderWarmup.enabled = false
	assert_bool(_warm.start(_cam)).is_false()
	assert_int(_cam.get_child_count()).is_equal(0)
	assert_int(_warm.meshes).is_equal(0)
	assert_bool(_warm.finished).is_false()


func test_после_start_созданы_образцы_каждого_материала() -> void:
	assert_bool(_warm.start(_cam, 3)).is_true()
	assert_int(_warm.warmed.size()).is_greater_equal(20)
	assert_int(_warm.meshes).is_greater_equal(_warm.warmed.size())
	for must in ["props/vault", "props/portal", "props/shard", "ice/soft_ice", "ice/black_ice", "env/pillar", "env/floor_slab_16", "avatar/runner",
			"volume_cloud", "hand_view", "hand_view_remote", "head_cloud","label3d", "tunnel_fx", "burn_flash", "std_alpha"]:
		assert_bool(_warm.warmed.has(must)).override_failure_message("нет образца " + must).is_true()
	assert_array(_warm.skipped).is_empty()   # все модели есть в клиенте
	# образцы стоят перед камерой на DISTANCE м и мелкие
	assert_vector(_warm.anchor.position).is_equal(Vector3(0.0, 0.0, -ShaderWarmup.DISTANCE))
	assert_object(_warm.anchor.get_parent()).is_same(_cam)
	await _warm.done
	await get_tree().process_frame   # queue_free доделан


func test_экран_ребёнок_камеры_ближе_всех_и_освобождается() -> void:
	_warm.start(_cam, 2)
	var screen := _warm.screen
	assert_object(screen.get_parent()).is_same(_cam)
	assert_float(-screen.position.z).is_equal_approx(ShaderWarmup.SCREEN_DISTANCE, 0.0001)
	assert_float(-screen.position.z).is_less(ShaderWarmup.DISTANCE)
	var mat := (screen.mesh as QuadMesh).material as StandardMaterial3D
	assert_object(mat.albedo_color).is_equal(Color.BLACK)
	await _warm.done
	await get_tree().process_frame
	assert_bool(is_instance_valid(screen)).is_false()
	assert_int(_cam.get_child_count()).is_equal(0)


func test_через_frames_кадров_всё_освобождено_и_пришёл_done() -> void:
	var info: Array = []
	_warm.done.connect(func(i: Dictionary): info.append(i))
	_warm.start(_cam, 3)
	var anchor := _warm.anchor
	var items: Array[Node] = anchor.get_children()
	assert_int(items.size()).is_greater(10)
	await get_tree().process_frame
	assert_bool(_warm.finished).is_false()   # на втором-третьем кадре ещё держится
	assert_bool(is_instance_valid(anchor)).is_true()
	await _warm.done
	assert_bool(_warm.finished).is_true()
	assert_int(info.size()).is_equal(1)
	assert_int(int(info[0]["frames"])).is_equal(3)
	assert_int(int(info[0]["meshes"])).is_equal(_warm.meshes)
	assert_int(int(info[0]["ms"])).is_greater_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(anchor)).is_false()
	for n in items:
		assert_bool(is_instance_valid(n)).is_false()


func test_второй_вызов_ничего_не_делает() -> void:
	assert_bool(_warm.start(_cam, 1)).is_true()
	var children := _cam.get_child_count()
	var warmed := _warm.warmed.size()
	assert_bool(_warm.start(_cam, 1)).is_false()
	assert_int(_cam.get_child_count()).is_equal(children)
	assert_int(_warm.warmed.size()).is_equal(warmed)
	await _warm.done
	await get_tree().process_frame   # queue_free доделан
	assert_bool(_warm.start(_cam, 1)).is_false()   # и после завершения
	assert_int(_cam.get_child_count()).is_equal(0)   # образцы и экран убраны


func test_камера_вне_дерева_не_запускает() -> void:
	var lone: Camera3D = auto_free(Camera3D.new())
	assert_bool(_warm.start(lone)).is_false()
	assert_bool(_warm.start(null)).is_false()

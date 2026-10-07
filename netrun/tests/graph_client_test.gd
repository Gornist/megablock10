extends GdUnitTestSuite
## Клиент графа узлов (W1): сцена по описанию узла от сервера, тоннель без движения камеры, шард в руке идёт с игроком.

func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	return scene


func _node_info(node: String, shard_ids: Array, arrive: Variant = null) -> Dictionary:
	var shards: Array = []
	for i in shard_ids.size():
		var slot: Vector3 = NodeLayout.SHARD_SLOTS[i]
		shards.append({"id": shard_ids[i], "p": [slot.x, slot.y, slot.z], "ready": true})
	var info := {
		"kind": "node", "node": node, "title": "Архив", "tier": "HARD", "r": 1.5, "shards": shards,
		"portals": [{"to": "node_02", "title": "Бухгалтерия", "tier": "BASE", "p": [NodeLayout.PORTAL_SLOTS[0].x, NodeLayout.PORTAL_SLOTS[0].z], "open": true},
			{"to": "node_03", "title": "Архив", "tier": "NIGHTMARE", "p": [NodeLayout.PORTAL_SLOTS[1].x, NodeLayout.PORTAL_SLOTS[1].z], "open": false}],
	}
	if arrive != null:
		info["arrive"] = arrive
	return info


func test_apply_node_builds_shards_and_portals() -> void:
	var scene := _scene()
	scene.apply_node(_node_info("node_05", ["node_05_pk0", "node_05_pk1"]))
	assert_str(scene.current_node).is_equal("node_05")
	assert_bool(scene._pickups.has("node_05_pk0")).is_true()
	assert_bool(scene._pickups.has("node_05_pk1")).is_true()
	assert_bool(scene.pickup.visible).is_false()  # одиночный pickup_01 в этом узле не показывается
	# порталы: площадка и подпись на каждый
	var labels := 0
	for n in scene._node_props:
		if n is Label3D:
			labels += 1
	assert_int(labels).is_equal(2)


func test_arrive_moves_rig_and_closes_tunnel_without_turning_camera() -> void:
	var scene := _scene()
	var yaw_before: float = scene.rig.camera.global_rotation.y
	scene.begin_tunnel("Архив", 2.0)
	assert_bool(scene.rig.movement_locked).is_true()
	scene.apply_node(_node_info("node_02", ["node_02_pk0"], [-3.7, -2.9]))
	assert_bool(scene.rig.movement_locked).is_false()
	assert_float(scene.rig.global_position.x).is_equal_approx(-3.7, 0.001)
	assert_float(scene.rig.global_position.z).is_equal_approx(-2.9, 0.001)
	assert_float(scene.rig.camera.global_rotation.y).is_equal(yaw_before)  # камера не поворачивалась


func test_grabbed_shard_stays_in_hand_across_nodes() -> void:
	var scene := _scene()
	scene.apply_node(_node_info("node_05", ["node_05_pk0"]))
	var m: Node3D = scene._pickups["node_05_pk0"]
	assert_bool(scene.try_grab(m.global_position, 0.4, scene.rig.camera)).is_true()
	scene.confirm_grab()
	assert_object(m.get_parent()).is_same(scene.rig.camera)
	scene.apply_node(_node_info("node_06", ["node_06_pk0"], [2.5, -10.4]))
	assert_object(m.get_parent()).is_same(scene.rig.camera)  # шард в руке не пропал и не остался в прошлом узле
	assert_bool(m.is_inside_tree()).is_true()
	assert_bool(scene._pickups.has("node_06_pk0")).is_true()


func test_shards_event_hides_taken_slot() -> void:
	var scene := _scene()
	scene.apply_node(_node_info("node_05", ["node_05_pk0", "node_05_pk1"]))
	scene.apply_shards([{"id": "node_05_pk0", "ready": false}, {"id": "node_05_pk1", "ready": true}])
	assert_bool((scene._pickups["node_05_pk0"] as Node3D).visible).is_false()
	assert_bool((scene._pickups["node_05_pk1"] as Node3D).visible).is_true()
	# пустой слот не берётся
	var near: Vector3 = (scene._pickups["node_05_pk0"] as Node3D).global_position
	assert_bool(scene.try_grab(near, 0.4, scene.rig.camera)).is_false()


## Длина замка в панели берётся по тиру ТЕКУЩЕГО узла сразу после его описания, а не по тиру, который панель получила в прошлый раз (до деки / взлома):
## иначе `breach.request lock=` расходился с сервером (он считает по тиру узла).
func test_длина_замка_панели_по_тиру_узла_сразу_после_описания_узла() -> void:
	var scene := _scene()
	var panel: BreachPanel = scene.world_ui.breach_panel
	scene.apply_node(_node_info("node_05", ["node_05_pk0"]))   # тир HARD, колоды ещё нет
	assert_int(panel.lock_length()).is_equal(int(BreachData.shared().tier_params("HARD")["lock_length"]))
	var info := _node_info("node_01", ["node_01_pk0"])
	info["tier"] = "BASE"
	scene.apply_node(info)   # другой узел — другой замок
	assert_int(panel.lock_length()).is_equal(int(BreachData.shared().tier_params("BASE")["lock_length"]))
	assert_int(panel.lock_length()).is_less(int(BreachData.shared().tier_params("HARD")["lock_length"]))

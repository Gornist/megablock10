extends GdUnitTestSuite
## К5: шард в руку и в деку. grip у открытого хранилища берёт шард; правая рука с шардом у деки + grip — шард втягивается; взятый левой
## рукой сразу уходит в деку; закрытое хранилище не берётся. Виды хранилища и шарда по состоянию. Сцена без сервера: подтверждения даёт тест.

const SLOT := "node_05_pk0"
const SLOT2 := "node_05_pk1"


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	return scene


func _shard(id: String, slot: int, extra: Dictionary = {}) -> Dictionary:
	var p: Vector3 = NodeLayout.SHARD_SLOTS[slot]
	var sh := {"id": id, "p": [p.x, p.y, p.z], "ready": true, "vault": "open"}
	sh.merge(extra, true)
	return sh


func _node_info(shards: Array) -> Dictionary:
	return {"kind": "node", "node": "node_05", "title": "Архив", "tier": "HARD", "r": 1.5, "shards": shards, "portals": []}


func _grab_with(scene: Node3D, hand: Node3D, id: String) -> bool:
	hand.global_position = (scene._pickups[id] as Node3D).global_position
	var ok: bool = scene.try_grab(hand.global_position, 0.4, hand)
	if ok:
		scene.confirm_grab()
	return ok


func _settle(sec: float = 0.5) -> void:
	await get_tree().create_timer(sec).timeout


func test_grip_next_to_open_vault_takes_shard_into_the_right_hand() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	var requested: Array[String] = []
	scene.grab_requested.connect(func(id): requested.append(id))
	var m: Node3D = scene._pickups[SLOT]
	scene.rig.right_hand.global_position = m.global_position
	scene.on_grip(scene.rig.right_hand)
	assert_array(requested).is_equal([SLOT])
	scene.confirm_grab()
	assert_str(scene.held_in(scene.rig.right_hand)).is_equal(SLOT)
	assert_object(m.get_parent()).is_same(scene.rig.right_hand)
	assert_bool(scene.held).is_true()


func test_right_hand_far_from_the_deck_keeps_the_shard() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	assert_bool(_grab_with(scene, scene.rig.right_hand, SLOT)).is_true()
	scene.rig.right_hand.global_position = scene.world_ui.deck.global_position + Vector3(1, 0, 0)
	assert_bool(scene.can_stow_from(scene.rig.right_hand)).is_false()
	var misses: Array = []
	scene.grab_missed.connect(func(info: Dictionary): misses.append(info))
	scene.on_grip(scene.rig.right_hand)   # вдали от деки grip ничего не делает: бросать нельзя
	assert_str(scene.held_in(scene.rig.right_hand)).is_equal(SLOT)
	assert_bool(scene.held).is_true()
	# но промах уходит в журнал: рука, шард, расстояние до деки (на очках правой рукой шард не уложили ни разу)
	assert_int(misses.size()).is_equal(1)
	assert_str(misses[0]["reason"]).is_equal("stow_far")
	assert_str(misses[0]["hand"]).is_equal("right")
	assert_float(float(misses[0]["d"])).is_greater(0.9)


func test_shard_in_the_right_hand_shows_a_stow_hint_and_the_stow_reach_is_wider() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	assert_bool(_grab_with(scene, scene.rig.right_hand, SLOT)).is_true()
	var m: Node3D = scene._pickups[SLOT]
	assert_bool(m.get_node_or_null("StowHint") != null).override_failure_message("нет подсказки у шарда в правой руке").is_true()
	# ближе нового STOW_REACH 0,3, но дальше старого 0,2: шард укладывается
	scene.rig.right_hand.global_position = scene.world_ui.deck.global_position + Vector3(0.25, 0, 0)
	assert_bool(scene.can_stow_from(scene.rig.right_hand)).is_true()
	scene.on_grip(scene.rig.right_hand)
	assert_bool(scene.held).is_false()


func test_shard_taken_by_the_left_hand_has_no_stow_hint() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	var m: Node3D = scene._pickups[SLOT]
	assert_bool(_grab_with(scene, scene.rig.left_hand, SLOT)).is_true()
	assert_bool(m.get_node_or_null("StowHint") == null).is_true()  # левой сразу в деку: подсказка не нужна


func test_right_hand_near_the_deck_stows_the_shard() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	var stowed: Array[String] = []
	scene.shard_stowed.connect(func(id): stowed.append(id))
	assert_bool(_grab_with(scene, scene.rig.right_hand, SLOT)).is_true()
	scene.rig.right_hand.global_position = scene.world_ui.deck.global_position + Vector3(0.05, 0.0, 0.0)
	scene._process(0.016)
	assert_bool(scene.world_ui.deck.is_receiving()).is_true()   # дека подсвечивает приёмник
	scene.on_grip(scene.rig.right_hand)
	assert_array(stowed).is_equal([SLOT])
	assert_str(scene.held_in(scene.rig.right_hand)).is_empty()
	assert_bool(scene.held).is_false()
	assert_bool(scene._held_ids.has(SLOT)).is_false()
	await _settle(scene.STOW_SEC + 0.3)
	assert_bool(scene._pickups.has(SLOT)).is_false()   # модель втянулась и исчезла


func test_receiving_highlight_follows_the_hand() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	_grab_with(scene, scene.rig.right_hand, SLOT)
	scene.rig.right_hand.global_position = scene.world_ui.deck.global_position + Vector3(1, 0, 0)
	scene._process(0.016)
	assert_bool(scene.world_ui.deck.is_receiving()).is_false()
	scene.rig.right_hand.global_position = scene.world_ui.deck.global_position
	scene._process(0.016)
	assert_bool(scene.world_ui.deck.is_receiving()).is_true()
	scene.rig.right_hand.global_position = scene.world_ui.deck.global_position + Vector3(1, 0, 0)
	scene._process(0.016)
	assert_bool(scene.world_ui.deck.is_receiving()).is_false()


func test_shard_taken_by_the_left_hand_goes_straight_to_the_deck() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	var stowed: Array[String] = []
	scene.shard_stowed.connect(func(id): stowed.append(id))
	assert_bool(_grab_with(scene, scene.rig.left_hand, SLOT)).is_true()
	assert_array(stowed).is_equal([SLOT])
	assert_bool(scene.held).is_false()
	assert_str(scene.held_in(scene.rig.left_hand)).is_empty()


func test_hand_with_a_shard_does_not_take_a_second_one() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0), _shard(SLOT2, 1)]))
	assert_bool(_grab_with(scene, scene.rig.right_hand, SLOT)).is_true()
	scene.rig.right_hand.global_position = (scene._pickups[SLOT2] as Node3D).global_position
	assert_bool(scene.try_grab(scene.rig.right_hand.global_position, 0.4, scene.rig.right_hand)).is_false()


func test_closed_vault_is_not_grabbable_and_shard_is_dim() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0, {"vault": "closed", "tier": 2, "enc": true})]))
	var m: Node3D = scene._pickups[SLOT]
	assert_bool(m.visible).is_true()                       # шард внутри виден, но тусклый
	assert_float(m.scale.x).is_less(1.0)
	assert_bool(scene.view.vault_open(SLOT)).is_false()    # хранилище закрыто
	assert_bool(scene.try_grab(m.global_position, 0.4, scene.rig.right_hand)).is_false()
	# открылось для нас: вид меняется, шард обычный и берётся
	scene.apply_shards([_shard(SLOT, 0, {"vault": "open", "tier": 2, "enc": true})])
	assert_bool(scene.view.vault_open(SLOT)).is_true()
	assert_float(m.scale.x).is_equal(1.0)
	assert_bool(scene.try_grab(m.global_position, 0.4, scene.rig.right_hand)).is_true()


func test_empty_vault_looks_closed_without_a_shard() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0, {"vault": "empty", "ready": false})]))
	assert_bool(scene.view.vault_open(SLOT)).is_false()
	assert_bool((scene._pickups[SLOT] as Node3D).visible).is_false()


func test_shard_model_follows_encryption_and_shows_the_tier() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0, {"tier": 3, "enc": true})]))
	var m: Node3D = scene._pickups[SLOT]
	assert_str(str(m.get_meta("asset"))).is_equal(NodeAssets.prop_path("shard_encrypted"))
	assert_str((m.get_node("TierLabel") as Label3D).text).contains("3")
	scene.apply_shards([_shard(SLOT, 0, {"tier": 3, "enc": false})])   # расшифровали: другая модель
	var m2: Node3D = scene._pickups[SLOT]
	assert_str(str(m2.get_meta("asset"))).is_equal(NodeAssets.prop_path("shard"))
	# описание без enc (старый сервер, тесты) модель не меняет
	scene.apply_shards([{"id": SLOT, "ready": true}])
	assert_str(str((scene._pickups[SLOT] as Node3D).get_meta("asset"))).is_equal(NodeAssets.prop_path("shard"))


func test_refilled_slot_gets_a_new_model_after_the_old_shard_went_into_the_deck() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	assert_bool(_grab_with(scene, scene.rig.left_hand, SLOT)).is_true()
	await _settle(scene.STOW_SEC + 0.3)
	scene.apply_shards([_shard(SLOT, 0, {"vault": "empty", "ready": false})])
	assert_bool(scene._pickups.has(SLOT)).is_false()
	scene.apply_shards([_shard(SLOT, 0)])   # слот пополнился
	assert_bool(scene._pickups.has(SLOT)).is_true()
	assert_bool((scene._pickups[SLOT] as Node3D).visible).is_true()
	assert_bool(scene.view.vault_open(SLOT)).is_true()


func test_flat_build_stows_from_the_camera_holder() -> void:
	var scene := _scene()
	scene.apply_node(_node_info([_shard(SLOT, 0)]))
	var m: Node3D = scene._pickups[SLOT]
	assert_bool(scene.try_grab(m.global_position, 0.4, scene.rig.camera)).is_true()
	scene.confirm_grab()
	assert_object(m.get_parent()).is_same(scene.rig.camera)   # плоская сборка: шард перед камерой, как раньше
	assert_bool(scene.can_stow_from(scene.rig.camera)).is_true()
	assert_bool(scene.stow(scene.rig.camera)).is_true()
	assert_bool(scene.held).is_false()


# ---------------------------------------------------------------- вкладка ДОБЫЧА: новое мигает, бейдж до просмотра

func _loot(ids: Array) -> Array:
	return ids.map(func(id): return {"id": id, "kind": "shard", "tier": 2, "title": "Шард " + id, "enc": true})


func test_new_loot_blinks_and_marks_the_tab_until_viewed() -> void:
	var deck: DeckPanel = auto_free(DeckPanel.new())
	add_child(deck)
	deck.set_loot(_loot(["a"]), 0)   # первый набор — старое
	assert_int(deck.tab_badge(DeckPanel.TAB_LOOT)).is_equal(0)
	assert_bool(deck.is_blinking()).is_false()
	deck.set_loot(_loot(["a", "b"]), 0)
	assert_bool(deck.is_blinking()).is_true()
	assert_int(deck.tab_badge(DeckPanel.TAB_LOOT)).is_equal(1)
	assert_array(deck.new_loot_ids()).is_equal(["b"])
	assert_str(deck.loot_texts()[3]).starts_with("НОВОЕ")   # заголовок, эдди, a, b
	deck.set_loot(_loot(["a", "b"]), 0)   # то же самое снова: не новое
	assert_int(deck.tab_badge(DeckPanel.TAB_LOOT)).is_equal(1)
	deck.select_tab(DeckPanel.TAB_LOOT)   # открыли — увидели
	assert_int(deck.tab_badge(DeckPanel.TAB_LOOT)).is_equal(0)
	assert_array(deck.new_loot_ids()).is_empty()
	assert_str(deck.loot_texts()[3]).not_contains("НОВОЕ")


func test_loot_added_while_the_tab_is_open_blinks_without_a_badge() -> void:
	var deck: DeckPanel = auto_free(DeckPanel.new())
	add_child(deck)
	deck.set_loot(_loot([]), 0)
	deck.select_tab(DeckPanel.TAB_LOOT)
	deck.set_loot(_loot(["z"]), 0)
	assert_bool(deck.is_blinking()).is_true()
	assert_int(deck.tab_badge(DeckPanel.TAB_LOOT)).is_equal(0)


func test_blink_ends_by_itself() -> void:
	var deck: DeckPanel = auto_free(DeckPanel.new())
	add_child(deck)
	deck.set_loot(_loot(["a"]), 0)
	deck.set_loot(_loot(["a", "b"]), 0)
	await get_tree().create_timer(DeckPanel.BLINK_SEC + 0.3).timeout
	assert_bool(deck.is_blinking()).is_false()
	assert_int(deck.tab_badge(DeckPanel.TAB_LOOT)).is_equal(1)   # бейдж держится до просмотра


func test_receiving_frame_toggles_with_the_hand() -> void:
	var deck: DeckPanel = auto_free(DeckPanel.new())
	add_child(deck)
	assert_bool(deck.is_receiving()).is_false()
	deck.set_receiving(true)
	assert_bool(deck.is_receiving()).is_true()
	deck.set_receiving(false)
	assert_bool(deck.is_receiving()).is_false()

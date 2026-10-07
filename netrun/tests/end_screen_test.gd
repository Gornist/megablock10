extends GdUnitTestSuite
## Конец забега на очках (`ended`): экран с причиной и «снимите очки», затемнение за секунду, мир спрятан и не обновляется, телепорт, захват,
## дека и панель взлома не реагируют; повторный `ended` безвреден. Часть проверок — на настоящем клиенте и сервере (запрос телепорта не уходит).

static var _next_port := 19391
const DT := 1.0 / 72.0
const SESSION := "alice"

var _root: Node


func after_test() -> void:
	if _root != null:
		_root.queue_free()
		_root = null


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	return scene


func _title(scene: Node3D) -> String:
	return (scene.rig.camera.get_node("EndScreen/EndTitle") as Label3D).text


func _hint(scene: Node3D) -> String:
	return (scene.rig.camera.get_node("EndScreen/EndHint") as Label3D).text


func test_texts_for_every_reason() -> void:
	assert_str(EndScreen.title_text(ExitLogic.REASON_EJECTED)).is_equal("ICE ВЫБРОСИЛ ВАС · добыча осталась в узле")
	assert_str(EndScreen.title_text(ExitLogic.REASON_FLATLINE)).starts_with("ФЛЭТЛАЙН ·")
	assert_str(EndScreen.title_text(ExitLogic.REASON_CLEAN)).is_equal("ВЫХОД")
	assert_str(EndScreen.title_text("weird")).is_equal("ВЫХОД: weird")


func test_title_colors_come_from_palette_layers() -> void:
	assert_object(EndScreen.title_color(ExitLogic.REASON_CLEAN)).is_equal(AssetMaterials.layer("end_win"))
	assert_object(EndScreen.title_color(ExitLogic.REASON_FLATLINE)).is_equal(AssetMaterials.layer("end_lose"))
	assert_object(EndScreen.title_color(ExitLogic.REASON_EJECTED)).is_equal(AssetMaterials.layer("end_lose"))


func test_hint_is_take_off_the_headset_without_a_pause_in_the_event() -> void:
	assert_str(EndScreen.hint_text({"kind": "ended", "reason": "ejected"})).is_equal("снимите очки")
	assert_str(EndScreen.hint_text({"reentry_sec": 0})).is_equal("снимите очки")


func test_hint_shows_the_pause_when_the_event_has_it() -> void:
	assert_str(EndScreen.hint_text({"reentry_sec": 180})).is_equal("вход снова через 3:00")
	assert_str(EndScreen.hint_text({"reentry_sec": 65.2})).is_equal("вход снова через 1:06")
	assert_str(EndScreen.hint_text({"reentry_sec": 9})).is_equal("вход снова через 0:09")


func test_ejected_screen_fades_in_one_second_and_keeps_the_camera_still() -> void:
	var scene := _scene()
	var cam_before: Vector3 = scene.rig.camera.position
	scene.show_ended("ejected")
	assert_bool(scene.ended).is_true()
	assert_bool(scene.flatline_shown).is_false()
	assert_str(_title(scene)).is_equal("ICE ВЫБРОСИЛ ВАС · добыча осталась в узле")
	assert_str(_hint(scene)).is_equal("снимите очки")
	assert_vector(scene.rig.camera.position).is_equal(cam_before)
	assert_float(scene.end_screen.veil_alpha()).is_less(0.5)  # затемнение только началось
	await get_tree().create_timer(EndScreen.FADE_SEC + 0.3).timeout
	assert_float(scene.end_screen.veil_alpha()).is_equal(1.0)
	assert_float((scene.rig.camera.get_node("EndScreen/EndTitle") as Label3D).modulate.a).is_equal(1.0)


func test_flatline_uses_the_same_screen_with_its_own_text() -> void:
	var scene := _scene()
	scene.show_ended("flatline")
	assert_bool(scene.flatline_shown).is_true()
	assert_str(_title(scene)).starts_with("ФЛЭТЛАЙН")
	assert_str(_hint(scene)).is_equal("снимите очки")


func test_the_pause_from_the_event_reaches_the_screen() -> void:
	var scene := _scene()
	scene.show_ended("ejected", {"kind": "ended", "reason": "ejected", "reentry_sec": 180})
	assert_str(_hint(scene)).is_equal("вход снова через 3:00")


func test_second_ended_changes_nothing() -> void:
	var scene := _scene()
	scene.show_ended("ejected")
	var screen: Node = scene.end_screen
	var kids: int = scene.rig.camera.get_child_count()
	scene.show_ended("flatline", {"reentry_sec": 60})
	scene.show_ended("ejected")
	assert_object(scene.end_screen).is_same(screen)
	assert_int(scene.rig.camera.get_child_count()).is_equal(kids)
	assert_str(_title(scene)).is_equal("ICE ВЫБРОСИЛ ВАС · добыча осталась в узле")
	assert_str(_hint(scene)).is_equal("снимите очки")
	assert_bool(scene.flatline_shown).is_false()


func test_the_world_is_hidden_and_stops_updating() -> void:
	var scene := _scene()
	scene.apply_state({"trace": 10.0, "level": 0, "ghost": false,
		"ice": [{"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [1.0, 0.0], "s": 1}], "cd": []})
	assert_bool((scene.ice_node("ice_1") as Node3D).is_visible_in_tree()).is_true()
	assert_bool(scene.view.is_visible_in_tree()).is_true()
	scene.show_ended("ejected")
	assert_bool((scene.ice_node("ice_1") as Node3D).is_visible_in_tree()).is_false()
	assert_bool(scene.view.is_visible_in_tree()).is_false()
	assert_bool(scene.pickup.is_visible_in_tree()).is_false()
	assert_bool(scene.is_processing()).is_false()
	# Запоздавший снимок: новый ICE не появляется, trace не меняется.
	scene.apply_state({"trace": 99.0, "level": 2, "ghost": false,
		"ice": [{"id": "ice_2", "p": [0.0, 0.0, -3.0], "f": [1.0, 0.0], "s": 3}], "cd": []})
	assert_object(scene.ice_node("ice_2")).is_null()
	assert_str(scene.world_ui.trace.shown_text()).contains("10").not_contains("99")


func test_teleport_is_locked_and_nothing_goes_out() -> void:
	var scene := _scene()
	var attempts: Array = []
	scene.rig.teleport_attempted.connect(func(from: Vector3, to: Vector3, ok: bool, reason: String): attempts.append([ok, reason]))
	scene.show_ended("ejected")
	var before: Vector3 = scene.rig.global_position
	for i in 6:
		scene.rig.drive(0.0, Vector2(0, 1), false, DT)  # прицел вперёд
	for i in 3:
		scene.rig.drive(0.0, Vector2.ZERO, false, DT)   # отпустил: раньше здесь был прыжок
	await get_tree().create_timer(0.3).timeout
	assert_array(attempts).is_empty()
	assert_vector(scene.rig.global_position).is_equal(before)
	assert_bool(scene.rig.movement_locked).is_true()


func test_deck_actions_capture_and_panels_do_not_react() -> void:
	var scene := _scene()
	scene.apply_state({"trace": 0.0, "level": 0, "ghost": false, "ice": [],
		"cd": [{"id": "ghost_1", "name": "Призрак", "left": 0.0, "st": "charged"}]})
	scene.apply_node({"title": "Узел", "tier": "T1"})
	scene.apply_shards([{"id": "vault_a", "p": [0.0, 0.0, -2.0], "ready": true}])
	var emitted: Array = []
	scene.daemon_use_requested.connect(func(id: String): emitted.append("use " + id))
	scene.charge_requested.connect(func(id: String): emitted.append("charge " + id))
	scene.grab_requested.connect(func(id: String): emitted.append("grab " + id))
	scene.breach_start_requested.connect(func(v: String, ids: Array): emitted.append("breach " + v))
	scene.show_ended("ejected")
	scene.use_slot(0)
	scene.use_selected()
	scene.charge_selected()
	scene.select_next()
	assert_bool(scene.try_grab(scene.rig.camera.global_position, 99.0, scene.rig.camera)).is_false()
	assert_bool(scene.stow(scene.rig.camera)).is_false()
	scene.on_grip(scene.rig.right_hand)
	assert_array(emitted).is_empty()
	assert_bool(scene.world_ui.is_off()).is_true()
	assert_bool(scene.world_ui.pointer.enabled).is_false()
	assert_bool(scene.world_ui.breach_pointer.enabled).is_false()
	assert_bool(scene.world_ui.breach_panel.visible).is_false()
	assert_bool(scene.world_ui.deck.is_visible_in_tree()).is_false()
	scene.begin_tunnel("куда-то", 2.0)   # запоздавший тоннель экран не трогает
	assert_object(scene.rig.camera.get_node_or_null("EndScreen")).is_not_null()


func test_real_client_ended_event_stops_teleport_requests() -> void:
	_root = Node.new()
	_root.name = "EndRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(sroot)
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	var server := NetServer.new()
	sroot.add_child(server)
	assert_int(server.start(cfg, DictTokenVerifier.new({"tok-a": SESSION}))).is_equal(OK)
	var proto := ProtoClient.new()
	croot.add_child(proto)
	proto.start(PackedStringArray(["--token=tok-a", "--port=%d" % cfg.port]), "flat", false)
	assert_bool(await _wait_for(func(): return proto.net.is_connected_to_world and server.has_avatar(SESSION))).is_true()
	server.end_session(SESSION, ExitLogic.REASON_EJECTED)
	assert_bool(await _wait_for(func(): return proto.scene.ended)).is_true()
	assert_str(_title(proto.scene)).starts_with("ICE ВЫБРОСИЛ ВАС")
	var rig: XRRig = proto.scene.rig
	for i in 6:
		rig.drive(0.0, Vector2(0, 1), false, DT)
	for i in 3:
		rig.drive(0.0, Vector2.ZERO, false, DT)
	await get_tree().create_timer(0.2).timeout
	assert_int(server.teleport_count(SESSION)).is_equal(0)
	assert_str(FileAccess.get_file_as_string(proto.log_file.path)).not_contains("rig.teleport")
	await proto.net.drop()
	server.stop_net()


func _wait_for(cond: Callable, sec: float = 5.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()

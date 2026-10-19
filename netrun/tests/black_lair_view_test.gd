extends GdUnitTestSuite
## Black ICE на клиенте (П6-1): модель вида (ice.md §6.2) и логово 4×4 м (§6.1) с состояниями сон / пробуждение / пусто — по фазе Black ICE (bp).

var _scene: Node3D


func before_test() -> void:
	_scene = preload("res://client/world_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame


func after_test() -> void:
	_scene.queue_free()


func _black(kind: String, phase: int) -> Dictionary:
	var e := {"id": "b1", "p": [1.0, 0.0, 1.0], "f": [0.0, 1.0], "s": 0, "b": 1, "bp": phase, "bw": 0, "pg": 0, "c": [6, 6]}
	if kind != "":
		e["kd"] = kind
	return e


func _state(ice: Array) -> Dictionary:
	return {"k": 1.0, "trace": 0.0, "level": 0, "cd": [], "ice": ice}


func test_путь_модели_по_виду_и_запасной_базовый() -> void:
	assert_str(NodeAssets.black_ice_path("hound")).ends_with("ice/black_ice_hound.glb")
	assert_str(NodeAssets.black_ice_path("lich")).ends_with("ice/black_ice_lich.glb")
	assert_str(NodeAssets.black_ice_path("")).is_equal(NodeAssets.BLACK_ICE)
	assert_str(NodeAssets.black_ice_path("dragon")).is_equal(NodeAssets.BLACK_ICE)
	for k: String in NodeAssets.BLACK_KINDS:
		assert_bool(ResourceLoader.exists(NodeAssets.black_ice_path(k))).override_failure_message("нет модели вида " + k).is_true()


func test_ice_view_берёт_модель_вида_а_soft_ice_её_не_берёт() -> void:
	var h := IceView.new(true, "hound")
	assert_str(h.asset).ends_with("black_ice_hound.glb")
	assert_str(h.kind).is_equal("hound")
	var plain := IceView.new(true, "")
	assert_str(plain.asset).is_equal(NodeAssets.BLACK_ICE)
	var soft := IceView.new(false, "hound")
	assert_str(soft.asset).is_equal(NodeAssets.SOFT_ICE)
	assert_str(soft.kind).is_equal("")
	h.free()
	plain.free()
	soft.free()


func test_снимок_с_kd_создаёт_black_ice_нужного_вида() -> void:
	_scene.apply_state(_state([_black("kraken", 0)]))
	var n: IceView = _scene._ice_nodes["b1"]
	assert_bool(n.black).is_true()
	assert_str(n.kind).is_equal("kraken")
	assert_str(n.asset).ends_with("black_ice_kraken.glb")


func test_снимок_без_kd_рисует_базовый_black_ice() -> void:
	_scene.apply_state(_state([_black("", 0)]))
	assert_str((_scene._ice_nodes["b1"] as IceView).asset).is_equal(NodeAssets.BLACK_ICE)


func test_центр_логова_середина_четырёх_блоков() -> void:
	var ld := LayoutData.load_named("core")
	assert_bool(ld.lair.is_empty()).is_false()
	var c := NodeView.lair_center(ld.lair)
	var home: Vector2i = ld.lair["home"]
	# home — клетка в центре 4×4 (нижняя правая из четырёх средних); центр логова лежит на углу между четырьмя средними клетками
	var corner := NodeGrid.center(home) - Vector3(0.5, 0.0, 0.5)
	assert_float(c.x).is_equal_approx(corner.x, 0.001)
	assert_float(c.z).is_equal_approx(corner.z, 0.001)


func test_логово_стоит_в_ядре_и_меняет_состояние_по_фазе() -> void:
	_scene.apply_layout(LayoutData.load_named("core"), "NIGHTMARE")
	var lair: Node3D = _scene.view.lair_node()
	assert_object(lair).is_not_null()
	var sleep := lair.find_child("State_sleep", true, false) as Node3D
	var waking := lair.find_child("State_waking", true, false) as Node3D
	var empty := lair.find_child("State_empty", true, false) as Node3D
	assert_bool(sleep.visible).is_true()
	assert_bool(waking.visible).is_false()
	_scene.apply_state(_state([_black("", 1)]))
	assert_bool(sleep.visible).is_false()
	assert_bool(waking.visible).is_true()
	_scene.apply_state(_state([_black("", 2)]))
	assert_bool(waking.visible).is_false()
	assert_bool(empty.visible).is_true()
	_scene.apply_state(_state([_black("", 0)]))   # вернулся и уснул
	assert_bool(sleep.visible).is_true()
	assert_bool(empty.visible).is_false()


func test_узел_без_логова_логова_не_имеет() -> void:
	_scene.apply_layout(LayoutData.load_named("server_room"), "HARD")
	assert_object(_scene.view.lair_node()).is_null()
	_scene.apply_layout(LayoutData.load_named("core"), "NIGHTMARE")
	assert_object(_scene.view.lair_node()).is_not_null()
	_scene.apply_layout(LayoutData.load_named("server_room"), "HARD")
	assert_object(_scene.view.lair_node()).is_null()

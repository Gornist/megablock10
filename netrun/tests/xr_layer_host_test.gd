extends GdUnitTestSuite
## Хост слоя композитора OpenXR (client/ui/xr_layer_host.gd): логика выбора и то, что без XR / при выключенном конфиге ничего не меняется.


func after_test() -> void:
	XrLayerHost.layers_requested = false


func test_выбор_слоя_только_при_всех_условиях() -> void:
	assert_bool(XrLayerHost.should_use_layer(true, true, true)).is_true()
	assert_bool(XrLayerHost.should_use_layer(false, true, true)).is_false()
	assert_bool(XrLayerHost.should_use_layer(true, false, true)).is_false()
	assert_bool(XrLayerHost.should_use_layer(true, true, false)).is_false()
	assert_bool(XrLayerHost.should_use_layer(false, false, false)).is_false()


func _make(face_parent: Node3D) -> Array:
	var vp: SubViewport = auto_free(SubViewport.new())
	var face := Sprite3D.new()
	face_parent.add_child(face)
	var host := XrLayerHost.new()
	face_parent.add_child(host)
	host.setup(vp, Vector2(0.32, 0.24), face)
	return [host, face]


func test_без_xr_слой_не_создаётся_и_квад_виден() -> void:
	XrLayerHost.layers_requested = true   # конфиг просит, но OpenXR в тестах не поднят
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	var made := _make(parent)
	var host: XrLayerHost = made[0]
	var face: Sprite3D = made[1]
	host._process(0.0)
	assert_bool(host.is_active()).is_false()
	assert_bool(face.visible).is_true()
	assert_int(host.get_child_count()).is_equal(0)


func test_конфиг_выкл_слой_не_создаётся() -> void:
	XrLayerHost.layers_requested = false
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	var made := _make(parent)
	var host: XrLayerHost = made[0]
	host._process(0.0)
	assert_bool(host.is_active()).is_false()
	assert_bool((made[1] as Sprite3D).visible).is_true()


func test_по_умолчанию_слои_не_запрошены() -> void:
	assert_bool(XrLayerHost.layers_requested).is_false()
	assert_bool(RenderConfig.layers_enabled(RenderConfig.new().layers)).is_false()

extends GdUnitTestSuite
## Хост слоя композитора OpenXR (client/ui/xr_layer_host.gd): логика выбора и то, что без XR / при выключенном конфиге ничего не меняется.


func after_test() -> void:
	XrLayerHost.layers_requested = false
	XrLayerHost.layers_behind = false


func test_порядок_слоя_позади_или_поверх() -> void:
	assert_int(XrLayerHost.sort_order_for(true)).is_less(0)      # позади основного вида (вырез в альфе, руки и луч над панелью)
	assert_int(XrLayerHost.sort_order_for(false)).is_greater(0)  # поверх сцены
	assert_bool(XrLayerHost.layers_behind).is_false()            # по умолчанию — «поверх»


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


func test_дека_и_взлом_без_xr_остаются_квадами() -> void:
	XrLayerHost.layers_requested = true
	var deck: DeckPanel = auto_free(DeckPanel.new())
	var breach: BreachPanel = auto_free(BreachPanel.new())
	add_child(deck)
	add_child(breach)
	for p: Node3D in [deck, breach]:
		var hosts := p.get_children().filter(func(n: Node) -> bool: return n is XrLayerHost)
		assert_int(hosts.size()).is_equal(1)
		(hosts[0] as XrLayerHost)._process(0.0)
		assert_bool((hosts[0] as XrLayerHost).is_active()).is_false()
		var sprites := p.get_children().filter(func(n: Node) -> bool: return n is Sprite3D)
		assert_bool((sprites[0] as Sprite3D).visible).is_true()
	# Поза поверхности для указателя не зависит от слоя.
	assert_vector(deck.panel_size_m()).is_equal(Vector2(DeckPanel.PANEL_WIDTH_M, DeckPanel.PANEL_WIDTH_M * 384.0 / 512.0))

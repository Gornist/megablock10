extends GdUnitTestSuite
## Видимые светящиеся источники V11 (client/glow_source.gd): два билборд-квада, аддитивный ореол без записи глубины; подключение к порталу, хранилищу, выходу.


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/world_scene.gd").new())
	add_child(scene)
	return scene


func _info(portals: Array, shards: Array) -> Dictionary:
	return {"kind": "node", "node": "node_x", "title": "Тест", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": shards, "portals": portals}


func _portal(open: bool) -> Dictionary:
	var p: Vector3 = NodeLayout.PORTAL_SLOTS[0]
	return {"to": "node_y", "title": "y", "tier": "BASE", "p": [p.x, p.z], "open": open}


func _shard(ready: bool) -> Dictionary:
	var p: Vector3 = NodeLayout.SHARD_SLOTS[0]
	return {"id": "node_x_pk0", "p": [p.x, p.y, p.z], "ready": ready}


func test_для_трёх_видов_два_квада() -> void:
	for kind in GlowSource.KINDS:
		var g: GlowSource = auto_free(GlowSource.new().setup(kind))
		assert_int(g.get_child_count()).is_equal(2)
		assert_object(g.core.mesh).is_instanceof(QuadMesh)
		assert_object(g.halo.mesh).is_instanceof(QuadMesh)
		assert_float((g.core.mesh as QuadMesh).size.x).is_equal_approx(GlowSource.CORE_SIZE, 0.0001)


func test_размеры_и_высоты_по_виду() -> void:
	var want := {"portal": [1.2, 1.6], "vault": [1.0, 1.2], "exit": [1.2, 2.0]}
	for kind in want:
		var g: GlowSource = auto_free(GlowSource.new().setup(kind))
		assert_float(g.position.y).is_equal_approx(want[kind][0], 0.0001)
		assert_float((g.halo.mesh as QuadMesh).size.x).is_equal_approx(want[kind][1], 0.0001)


func test_заглушка_ореола_аддитивна_без_записи_глубины() -> void:
	var script: GDScript = AssetMaterials
	if script.has_method("halo_material"):
		return   # материал уже от Blender: ветка заглушки не используется
	for kind in GlowSource.KINDS:
		var g: GlowSource = auto_free(GlowSource.new().setup(kind))
		assert_bool(g.halo_from_assets).is_false()
		for q in [g.core, g.halo]:
			var m := (q as MeshInstance3D).material_override as ShaderMaterial
			assert_str(m.shader.code).contains("blend_add")
			assert_str(m.shader.code).contains("depth_draw_never")
			assert_str(m.shader.code).contains("INV_VIEW_MATRIX")
			assert_int(m.render_priority).is_greater(0)


func test_has_method_проверка_не_падает_без_halo_material() -> void:
	var g: GlowSource = auto_free(GlowSource.new().setup("portal"))
	assert_object(g.halo.material_override).is_not_null()


func test_открытый_портал_светится_закрытый_нет() -> void:
	var scene := _scene()
	scene.apply_node(_info([_portal(true)], [_shard(true)]))
	var v: NodeView = scene.view
	var g := v.portal_node(0).get_node("Glow_portal") as GlowSource
	assert_object(g).is_not_null()
	assert_bool(g.is_visible_in_tree()).is_true()
	v.close_portal("node_y")
	assert_bool(g.is_visible_in_tree()).is_false()


func test_хранилище_светится_только_открытым() -> void:
	var scene := _scene()
	scene.apply_node(_info([], [_shard(true)]))
	var v: NodeView = scene.view
	var g := v._vaults["node_x_pk0"].get_node("Glow_vault") as GlowSource
	assert_bool(g.is_visible_in_tree()).is_true()
	v.set_vault_state("node_x_pk0", NodeView.VAULT_EMPTY)
	assert_bool(g.is_visible_in_tree()).is_false()
	v.set_vault_state("node_x_pk0", NodeView.VAULT_CLOSED)
	assert_bool(g.is_visible_in_tree()).is_false()


func test_выход_светится_пока_открыт() -> void:
	var scene := _scene()
	scene.apply_node(_info([], [_shard(true)]))
	var v: NodeView = scene.view
	var g := v._exit_glow.get_node("Glow_exit") as GlowSource
	assert_bool(g.is_visible_in_tree()).is_true()
	v.set_exit_locked(true)
	assert_bool(g.is_visible_in_tree()).is_false()

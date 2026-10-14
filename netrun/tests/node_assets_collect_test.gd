extends GdUnitTestSuite
## NodeAssets._collect: скрытые узлы (visible = false) не попадают в части MultiMesh — иначе погашенная AssetMaterials дымка рисуется (клин у края комнаты).


func _mesh_node(name_: String, visible_: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = BoxMesh.new()
	mi.visible = visible_
	return mi


func test_скрытый_меш_не_собирается() -> void:
	var root: Node3D = auto_free(Node3D.new())
	root.add_child(_mesh_node("plate", true))
	root.add_child(_mesh_node("edge_mist", false))
	var out: Array = []
	NodeAssets._collect(root, Transform3D.IDENTITY, out)
	assert_int(out.size()).is_equal(1)
	assert_str(out[0]["name"]).is_equal("plate")


func test_меш_под_скрытым_родителем_не_собирается() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var state := Node3D.new()
	state.name = "State_closed"
	state.visible = false
	state.add_child(_mesh_node("bars", true))
	root.add_child(state)
	root.add_child(_mesh_node("body", true))
	var out: Array = []
	NodeAssets._collect(root, Transform3D.IDENTITY, out)
	assert_int(out.size()).is_equal(1)
	assert_str(out[0]["name"]).is_equal("body")

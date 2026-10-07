extends GdUnitTestSuite
## Клиент рисует именно те ассеты, что принимаются в Blender-проекте: каждый модуль и вариант окружения из NodeView.MODULES/VARIANTS
## есть файлом env/<имя>.glb (путь — через NodeAssets.env_path, как у клиента), пол — один тайл floor_slab_16, а материалы клиент
## не трогает: всё идёт через AssetMaterials (assets/ARCHITECTURE.md, п. 18).

const NODE_VIEW := "res://client/node_view.gd"
## Горизонт клиент берёт отдельно от MODULES (NodeView._horizon).
const EXTRA := ["horizon_band"]


## Имена файлов окружения, которые клиент реально просит: варианты модуля или сам модуль, если вариантов нет.
func _client_env_names() -> Array[String]:
	var out: Array[String] = []
	for module: String in NodeView.MODULES:
		var vars: Array = NodeView.VARIANTS.get(module, [module])
		for v: Variant in vars:
			out.append(str(v))
	for e: String in EXTRA:
		out.append(e)
	return out


func test_каждый_модуль_и_вариант_клиента_есть_файлом() -> void:
	var names := _client_env_names()
	assert_int(names.size()).is_greater(NodeView.MODULES.size() - 1)
	for n in names:
		var path := NodeAssets.env_path(n)
		assert_str(path).is_equal("res://assets/models/env/%s.glb" % n)
		assert_bool(ResourceLoader.exists(path)).override_failure_message("нет ассета окружения: %s" % path).is_true()
		assert_bool(FileAccess.file_exists(path + ".import")).override_failure_message("нет %s.import" % path).is_true()


func test_варианты_относятся_только_к_модулям_клиента() -> void:
	for module: String in NodeView.VARIANTS:
		assert_bool(NodeView.MODULES.has(module)).override_failure_message("варианты у модуля вне MODULES: %s" % module).is_true()


func test_пол_в_клиенте_один_тайл_floor_slab_16() -> void:
	assert_array(NodeView.VARIANTS["floor"]).is_equal(["floor_slab_16"])
	assert_str(NodeAssets.env_path("floor_slab_16")).ends_with("env/floor_slab_16.glb")


func test_клиент_не_красит_материалы_сам() -> void:
	var src := FileAccess.get_file_as_string(NODE_VIEW)
	assert_str(src).is_not_empty()
	for banned in ["set_shader_parameter", "StandardMaterial3D.new", "ShaderMaterial.new", "material_override"]:
		assert_bool(src.contains(banned)).override_failure_message("node_view.gd красит материалы мимо AssetMaterials: %s" % banned).is_false()

extends GdUnitTestSuite
## Вид узла для карты W×H блоков (G1, 1..12 по стороне): пол, потолок и дальний план по размеру карты, центр комнаты по раскладке,
## OccupiedFloor не рисует вне карты, пресеты кадра (EyePresets.for_layout). Карта 8×8 — прежний вид бит-в-бит.
## Стен и дверей в комнате клиента нет (V10: на принятом виде невидимы) — границу показывает кромка плиты пола, поэтому «стены на периметре» здесь = пол по краю карты
## и потолок ровно над ячейками карты.

const ROOM_MIN := Vector2(-8.0, -14.0)


## Синтетическая раскладка c×r блоков: открытое поле, вход S в (0,0), порталы 1 и 2 в юго-западном и северо-восточном углах, выход E на `exit_row`
## (0 — на севере посередине, r − 1 — на юге), хранилище V в юго-восточном углу.
func _dict(c: int, r: int, exit_row: int = 0) -> Dictionary:
	var rows: Array = []
	for z in r:
		var line := ""
		for x in c:
			var ch := "."
			if x == 0 and z == 0:
				ch = "S"
			elif x == 0 and z == r - 1:
				ch = "1"
			elif x == c - 1 and z == 0:
				ch = "2"
			elif exit_row == 0 and x == c / 2 and z == 0:
				ch = "E"
			elif exit_row > 0 and (x == c / 2 - 1 or x == c / 2) and z >= r - 2:   # южный выход — площадка 2×2 блока, как в Фойе
				ch = "E"
			elif x == c - 1 and z == r - 1:
				ch = "V"
			line += ch
		rows.append(line)
	return {"name": "view_%dx%d_%d" % [c, r, exit_row], "cells": rows, "vaults": [{"cell": [c - 1, r - 1], "pad": [c - 2, r - 1], "ring": "outer"}],
		"ice": [], "black": null, "meta": {"sight_cells": 6}}


func _parse(c: int, r: int, exit_row: int = 0) -> LayoutData:
	var ld := LayoutData.parse(_dict(c, r, exit_row))
	assert_str(ld.error).override_failure_message("%dx%d: %s" % [c, r, ld.error]).is_empty()
	return ld


func _view(ld: LayoutData) -> NodeView:
	var v: NodeView = auto_free(NodeView.new())
	add_child(v)
	v.set_layout(ld)
	return v


func _room_rect(ld: LayoutData) -> Rect2:
	return Rect2(ROOM_MIN, ld.room_max() - ROOM_MIN)


# ---------------------------------------------------------------- пол и потолок

func test_пол_покрывает_ровно_карту_10x10_6x9_12x12() -> void:
	for dim in [Vector2i(10, 10), Vector2i(6, 9), Vector2i(12, 12), Vector2i(5, 7)]:
		var ld := _parse(dim.x, dim.y)
		var v := _view(ld)
		assert_int(int(v.module_counts()["floor"])).is_equal(1)   # по-прежнему один тайл
		var rect := v.floor_rect()
		var want := _room_rect(ld)
		assert_vector(rect.position).is_equal_approx(want.position, Vector2.ONE * 0.001)
		assert_vector(rect.size).is_equal_approx(want.size, Vector2.ONE * 0.001)
		# и плита в самом MultiMesh: масштаб по осям X и Z, толщина (Y) прежняя, центр — центр комнаты
		var xf: Transform3D = v._room_transforms()["floor"][0]
		assert_vector(xf.origin).is_equal_approx(ld.room_center(), Vector3.ONE * 0.001)
		assert_vector(xf.basis.get_scale()).is_equal_approx(Vector3(dim.x * 2.0 / 16.0, 1.0, dim.y * 2.0 / 16.0), Vector3.ONE * 0.001)


func test_потолка_и_дальних_пластов_нет_в_комнате_любого_размера() -> void:
	# решение владельца 18.10 («убери плиты сверху и снизу вообще, оставим только горизонт»): горизонт - купол, пол остаётся
	for dim in [Vector2i(8, 8), Vector2i(10, 10), Vector2i(6, 9), Vector2i(12, 12)]:
		var v := _view(_parse(dim.x, dim.y))
		var xforms: Dictionary = v._room_transforms()
		for module: String in ["ceiling", "far_floor", "far_ceiling"]:
			assert_bool(xforms.has(module)).override_failure_message("%s в %s" % [module, str(dim)]).is_false()
		assert_int(int(v.module_counts()["floor"])).is_equal(1)


func test_ворота_локдауна_стоят_в_южной_стене_карты() -> void:
	# выход на южной стороне 10×10: ворота — в последнем ряду ячеек (z = 2 · 9 + ... = южный край − 1 м), две створки по сторонам площадки
	var ld := _parse(10, 10, 9)
	var v := _view(ld)
	assert_int(int(v.module_counts()["lockdown_gate"])).is_equal(2)
	for xf: Transform3D in v._room_transforms()["lockdown_gate"]:
		var south_cell_z := NodeLayout.cell_center(0, 9).z
		assert_float(xf.origin.z).is_equal_approx(south_cell_z + NodeView.WALL_EDGE, 0.001)   # наружный край ячейки: у южной границы карты
		assert_float(xf.origin.z).is_less_equal(ld.room_max().y + 0.001)


func test_центр_комнаты_и_размер_по_раскладке() -> void:
	var v := _view(_parse(10, 10))
	assert_vector(v.room_cells()).is_equal(Vector2i(10, 10))
	assert_vector(v.room_center()).is_equal(Vector3(2.0, 0.0, -4.0))
	assert_vector(v.room_max()).is_equal(Vector2(12.0, 6.0))
	var w := _view(_parse(6, 9))
	assert_vector(w.room_center()).is_equal(Vector3(-2.0, 0.0, -5.0))
	assert_vector(w.room_max()).is_equal(Vector2(4.0, 4.0))


func test_8x8_раскладка_и_прежняя_комната_дают_одни_и_те_же_преобразования() -> void:
	var old := _view(null)
	var same := _view(_parse(8, 8))
	var a: Dictionary = old._room_transforms()
	var b: Dictionary = same._room_transforms()
	for module: String in ["floor"]:
		assert_array(b[module]).override_failure_message(module).is_equal(a[module])
	var floor_xf: Transform3D = a["floor"][0]
	assert_bool(floor_xf.basis == Basis.IDENTITY).is_true()
	assert_vector(floor_xf.origin).is_equal(NodeLayout.ROOM_CENTER)


# ---------------------------------------------------------------- подсветка занятых клеток

func test_занятые_вне_карты_не_рисуются() -> void:
	# карта 6×9 блоков = 12×18 клеток: (13; 5) вне по X, (5; 19) вне по Z, (11; 17) — последняя внутри
	var g := _parse(6, 9).grid()
	g.occ = {Vector2i(2, 2): true, Vector2i(11, 17): true, Vector2i(13, 5): true, Vector2i(5, 19): true, Vector2i(-1, 0): true}
	var f: OccupiedFloor = auto_free(OccupiedFloor.new(g))
	add_child(f)
	assert_int(f.cell_count()).is_equal(2)
	assert_vector(f.cell_position(1)).is_equal_approx(Vector3(NodeGrid.center(Vector2i(11, 17)).x, OccupiedFloor.LIFT, NodeGrid.center(Vector2i(11, 17)).z), Vector3.ONE * 0.001)


func test_занятые_за_16_клетками_рисуются_на_большой_карте() -> void:
	# 10×10 блоков = 20×20 клеток: клетка (18; 19) в карте, хотя и дальше прежних 16×16
	var g := _parse(10, 10).grid()
	g.occ = {Vector2i(18, 19): true, Vector2i(20, 3): true}
	var f: OccupiedFloor = auto_free(OccupiedFloor.new(g))
	add_child(f)
	assert_int(f.cell_count()).is_equal(1)


func test_запас_отметок_хватает_на_все_клетки_12x12() -> void:
	var g := _parse(12, 12).grid()
	g.occ = {}
	for x in 24:
		for y in 24:
			g.occ[Vector2i(x, y)] = true
	var f: OccupiedFloor = auto_free(OccupiedFloor.new(g))
	add_child(f)
	assert_int(f.cell_count()).is_equal(24 * 24)


# ---------------------------------------------------------------- пресеты кадра

func test_пресеты_без_раскладки_прежние() -> void:
	for n: String in EyePresets.names():
		assert_dict(EyePresets.get_preset(n, null)).is_equal(EyePresets.get_preset(n))
	assert_float(EyePresets.top_scale(null)).is_equal(1.0)


func test_пресеты_8x8_раскладки_сверху_как_у_фойе() -> void:
	var ld := _parse(8, 8)
	for n in ["top", "top_north", "top_south"]:
		assert_dict(EyePresets.get_preset(n, ld)).is_equal(EyePresets.get_preset(n))


func test_пресеты_центр_и_края_по_раскладке() -> void:
	for dim in [Vector2i(10, 10), Vector2i(6, 9), Vector2i(12, 12)]:
		var ld := _parse(dim.x, dim.y)
		var top := EyePresets.get_preset("top", ld)
		var c := ld.room_center()
		assert_float((top["look"] as Vector3).x).is_equal_approx(c.x, 0.001)
		assert_float((top["look"] as Vector3).z).is_equal_approx(c.z, 0.001)
		assert_float((top["pos"] as Vector3).y).is_equal_approx(EyePresets.TOP_HEIGHT * maxf(1.0, maxi(dim.x, dim.y) / 8.0), 0.001)
		var south := EyePresets.get_preset("top_south", ld)
		assert_float((south["look"] as Vector3).z).is_equal_approx(ld.room_max().y - EyePresets.TOP_HALF_OFFSET, 0.001)
		# обзор сверху вмещает комнату: половина вертикального fov · высота ≥ половины большей стороны
		var half_view := tan(deg_to_rad(EyePresets.TOP_FOV_DEG * 0.5)) * (top["pos"] as Vector3).y
		assert_float(half_view).is_greater(maxi(dim.x, dim.y) * 1.0)
		# вход — на входе раскладки, глаза и взгляд внутри комнаты
		var entry := EyePresets.get_preset("entry", ld)
		assert_float(NodeLayout.flat_distance(entry["pos"], ld.spawn)).is_less(0.001)
		for n: String in EyePresets.names():
			var p := EyePresets.get_preset(n, ld)
			assert_bool(NodeLayout.in_room(p["pos"], ld.room_max())).override_failure_message("%s %s pos" % [dim, n]).is_true()
			if n != "entry" and n != "wedge":   # у них look — направление на 10 м вперёд (вход синтетической карты у северной стены: взгляд уходит за неё)
				assert_bool(NodeLayout.in_room(p["look"], ld.room_max())).override_failure_message("%s %s look" % [dim, n]).is_true()


func test_cardinal_yaw_с_центром_раскладки() -> void:
	var p := Vector3(10.0, 0.0, -4.0)
	assert_float(NodeLayout.cardinal_yaw(p)).is_equal(-PI / 2.0)   # к центру 8×8 (0; −6): dx = −10, dz = −2 — на запад
	assert_float(NodeLayout.cardinal_yaw(p, Vector3(4.0, 0.0, 4.0))).is_equal(0.0)   # к другому центру (4; 4): dx = −6, dz = 8 — на юг

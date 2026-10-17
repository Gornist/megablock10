extends Node3D
## Цельное препятствие (П7-3) глазами клиента: сравнение модуля pillar из glb и корпуса ObstacleBody — тот же блок, те же материалы, те же ракурсы.
## --mode=glb | rt  — одна колонна (модуль или рантайм-меш из одного блока), кадры eye / top / base: пара кадров сверяется числом (tools/solid_diff.py);
## --mode=shape    — формы Г, П, ряд (рантайм): кадры shape_eye, shape_top, shape_low.
## Запуск: netrun/tools/dev.sh shot res://assets/preview_solid.tscn --mode=rt

var _out := "/tmp/solid_shots"
var _mode := "rt"
const P := Vector3(0.0, 0.0, -3.0)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--mode="):
			_mode = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = AssetMaterials.alarm_background(0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var room := Node3D.new()
	add_child(room)
	room.add_child(NodeAssets.instance(NodeAssets.env_path("floor_slab_16"), "BASE"))
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	if _mode == "shape":
		_shapes(room)
		cam.fov = 55.0
		await _view(cam, Vector3(-3.0, 1.7, -0.5), Vector3(-3.0, 1.0, -6.0), "a_eye_pi")                 # П открытой стороной к зрителю
		await _view(cam, Vector3(6.0, 1.6, -3.0), Vector3(4.0, 1.0, -6.0), "b_eye_l_corner")             # вогнутый угол Г
		cam.fov = 60.0
		await _view(cam, Vector3(0.0, 12.0, -6.0), Vector3(0.0, 0.0, -6.0), "c_top", Vector3(0, 0, -1)) # сверху обе формы
		cam.fov = 70.0
		await _view(cam, Vector3(-3.0, 0.45, -1.8), Vector3(-3.0, 0.5, -6.0), "d_low_base")              # основание и рамка у ног П
	else:
		_single(room)
		await _view(cam, P + Vector3(0.0, 1.6, 3.2), P + Vector3(0.0, 1.2, 0.0), "eye")
		await _view(cam, P + Vector3(1.6, 3.4, 1.8), P + Vector3(0.0, 2.0, 0.0), "top")
		await _view(cam, P + Vector3(0.9, 0.5, 2.0), P + Vector3(0.0, 0.1, 0.0), "base")
	get_tree().quit()


func _single(parent: Node3D) -> void:
	var rows: Array[String] = ["........", "........", "........", "...#....", "........", "........", "........", "........"]
	if _mode == "glb":
		_instances(parent, [], P)
	else:
		var regions := ObstacleRegions.from_blocks(rows)
		var b: Vector2i = regions[0].blocks[0]
		var c := Vector3(NodeLayout.ROOM_MIN.x + NodeLayout.CELL * (b.x + 0.5), 0.0, NodeLayout.ROOM_MIN.y + NodeLayout.CELL * (b.y + 0.5))
		_instances(parent, regions, P - c)


func _shapes(parent: Node3D) -> void:
	var rows: Array[String] = ["........", "........", "........", ".###.##.", ".#.#.#..", "........", "........", "........"]
	_instances(parent, ObstacleRegions.from_blocks(rows), Vector3.ZERO)


## Как NodeView._add_obstacles: части pillar_block/pillar_base с материалами модуля, меши билдера. regions пуст — прямой модуль pillar в точке shift.
func _instances(parent: Node3D, regions: Array, shift: Vector3) -> void:
	var path := NodeAssets.env_path("pillar", "BASE")
	var built := ObstacleBody.build(regions) if not regions.is_empty() else {}
	for part in NodeAssets.mesh_parts(path, "BASE"):
		var mi := MeshInstance3D.new()
		mi.name = part["name"]
		if regions.is_empty():
			mi.mesh = part["mesh"]
			mi.transform = Transform3D(Basis.IDENTITY, shift) * (part["xform"] as Transform3D)
		else:
			var key := "body" if part["name"] == "pillar_block" else ("frame" if part["name"] == "pillar_base" else "")
			if key == "":
				continue
			var mesh := (built[key] as ArrayMesh).duplicate() as ArrayMesh
			mesh.surface_set_material(0, (part["mesh"] as Mesh).surface_get_material(0))
			mi.mesh = mesh
			mi.transform = Transform3D(Basis.IDENTITY, shift) * (part["xform"] as Transform3D)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


func _view(cam: Camera3D, from: Vector3, to: Vector3, label: String, up := Vector3.UP) -> void:
	cam.look_at_from_position(from, to, up)
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])

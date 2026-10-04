extends SceneTree
## Бюджет собранной комнаты по модулям: экземпляров, поверхностей (вызовов отрисовки), треугольников.
## Запуск: godot --headless --path netrun -s res://assets/tools/budget.gd

func _init() -> void:
	var view := NodeView.new()
	root.add_child(view)
	view.set_tier("BASE")
	var rows := {}
	for n in view.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		var label := str(n.get_meta("asset", "?")).get_file().get_basename()
		var r: Dictionary = rows.get(label, {"inst": 0, "draws": 0, "tris": 0})
		r["inst"] += mm.instance_count
		r["draws"] += mm.mesh.get_surface_count()
		r["tris"] += NodeView._mesh_triangles(mm.mesh) * mm.instance_count
		rows[label] = r
	var total_t := 0
	var total_d := 0
	for k in rows:
		print("%-16s экз=%4d  вызовов=%3d  треугольников=%7d" % [k, rows[k]["inst"], rows[k]["draws"], rows[k]["tris"]])
		total_t += rows[k]["tris"]
		total_d += rows[k]["draws"]
	print("ИТОГО: вызовов=%d треугольников=%d" % [total_d, total_t])
	quit()

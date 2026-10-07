class_name AssetBatch
extends RefCounted
## Склейка одинаковых ассетов в MultiMesh: один вызов отрисовки на меш вместо одного на каждую копию.
## Нужна для повторяющегося окружения (дальние пласты данных: десятки одинаковых участков пола, потолка и башен).
## Порядок: у каждой группы один прототип — ассет, у которого уже подменены материалы (AssetMaterials.apply, затухание, яркость).
## Копии группы — только трансформации. flush() создаёт по MultiMeshInstance3D на каждый меш прототипа.
## Ограничения: у группы один общий ограничивающий объём (отсечение по кадру на уровне группы, не копии),
## поэтому группы стоит делить по зонам (в сцене просмотра — по пластам); общее у всех копий — материал, то есть тир, яркость, шрам и затухание.

var _groups: Dictionary = {}  # ключ -> {"proto": Node3D, "xf": Array[Transform3D]}


func has(key: String) -> bool:
	return _groups.has(key)


func register(key: String, proto: Node3D) -> void:
	_groups[key] = {"proto": proto, "xf": []}


func add(key: String, xf: Transform3D) -> void:
	(_groups[key]["xf"] as Array).append(xf)


## Трансформация меша относительно корня прототипа (прототип вне дерева, поэтому global_transform недоступен).
static func _local_to_root(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func flush(parent: Node) -> int:
	var made := 0
	for key in _groups:
		var g: Dictionary = _groups[key]
		var proto: Node3D = g["proto"]
		var xfs: Array = g["xf"]
		if xfs.is_empty():
			continue
		for n in proto.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.visible:  # скрытые меши (например slab_seams при floor_grid) в батч не идут
				continue
			var mesh: Mesh = mi.mesh.duplicate()  # материалы-переопределения копируем в сам меш: у MultiMeshInstance3D своих по поверхностям нет
			for s in mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m != null:
					mesh.surface_set_material(s, m)
			var local := _local_to_root(mi, proto)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xfs.size()
			var box := AABB()
			for i in xfs.size():
				var t: Transform3D = (xfs[i] as Transform3D) * local
				mm.set_instance_transform(i, t)
				box = (t * mesh.get_aabb()) if i == 0 else box.merge(t * mesh.get_aabb())
			mm.custom_aabb = box.grow(2.0)  # запас на дыхание и покачивание штрихов, которые считает вершинный шейдер
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			parent.add_child(mmi)
			made += 1
	_groups.clear()
	return made

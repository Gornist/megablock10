extends Node3D
## Тестовая сцена для V1: пол с сеткой и несколько ориентиров, по которым ходит риг.
## Общая для плоской и VR-сборок; не игровой мир (его даёт сервер).

var rig: XRRig


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.03, 0.06)
	add_child(env)
	_add_box(Vector3(40, 0.1, 40), Vector3(0, -0.05, 0), Color(0.1, 0.12, 0.18))
	for i in 8:
		var a := TAU * i / 8.0
		_add_box(Vector3(0.6, 1.5 + i * 0.2, 0.6), Vector3(sin(a), 0, -cos(a)) * 6.0 + Vector3(0, 0.75, 0), Color.from_hsv(i / 8.0, 0.8, 0.9))
	rig = preload("res://client/xr_rig.tscn").instantiate()
	add_child(rig)


func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	b.material = mat
	m.mesh = b
	m.position = pos
	add_child(m)

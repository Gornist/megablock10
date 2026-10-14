extends Node3D
## Кадры Маяка и Датчика Soft ICE (ice/lighthouse_ice, ice/sensor_ice) на плите пола: веер маяка на дальность 5 клеток в четырёх поворотах головы, луч датчика на 4 клетки
## в четырёх состояниях (погашен, горит, мигает, вспышка). Запуск: netrun/tools/dev.sh shot res://assets/preview_ice_gear.tscn  (кадры — на devbox; сетка на Mac)
## Состояния и масштаб — как их ставит игра: узел Beam масштабируется (Z Godot — длина), узел Head поворачивается, AssetMaterials.set_beam — состояние.

var _out := "/tmp/ice_gear_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = AssetMaterials.VOID_BG
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var floor_slab := NodeAssets.instance(NodeAssets.env_path("floor_slab_16"), "BASE")
	add_child(floor_slab)
	floor_slab.position = Vector3(0, 0, 0)
	# маяки: поворот головы 0, 45, 90, 135° — за такт 45° (ice.md §5), дальность 5 клеток
	for i in 4:
		var m := NodeAssets.instance("res://assets/models/ice/lighthouse_ice.glb")
		m.position = Vector3(-4.5 + 3.0 * i, 0, -2.0)
		var head := m.find_child("Head", true, false) as Node3D
		head.rotation.y = deg_to_rad(-45.0 * i)
		var beam := m.find_child("Beam", true, false) as Node3D
		beam.scale = Vector3.ONE * 2.5   # 2,5 м: кадр компактнее; игра ставит 5 (дальность в клетках)
		add_child(m)
	# датчики: пара излучателей лицом друг к другу, луч на 4 клетки, четыре состояния
	var states := [[AssetMaterials.BEAM_OFF, 0.0], [AssetMaterials.BEAM_ON, 0.0], [AssetMaterials.BEAM_BLINK, 0.0], [AssetMaterials.BEAM_ON, 1.0]]
	for i in 4:
		var x := -4.5 + 3.0 * i
		var a := NodeAssets.instance("res://assets/models/ice/sensor_ice.glb")
		a.position = Vector3(x, 0, 1.0)
		(a.find_child("Beam", true, false) as Node3D).scale = Vector3(1, 1, 4.0)
		var b := NodeAssets.instance("res://assets/models/ice/sensor_ice.glb")
		b.position = Vector3(x, 0, 1.0 - 4.0)
		b.rotation.y = PI
		var b_beam := b.find_child("Beam", true, false) as Node3D
		b_beam.visible = false   # луч один на пару
		AssetMaterials.set_beam(a, states[i][0], states[i][1])
		add_child(a)
		add_child(b)
	# барьеры в трёх состояниях (закрыт, вскрывается, открыт) и Трассировщик с хвостом из 3 клеток — ряд позади (z = −6)
	for i in 3:
		var bar := NodeAssets.instance("res://assets/models/ice/barrier_ice.glb")
		bar.position = Vector3(-4.5 + 3.0 * i, 0, -6.0)
		for s in ["State_closed", "State_opening", "State_open"]:
			(bar.find_child(s, true, false) as Node3D).visible = (s == ["State_closed", "State_opening", "State_open"][i])
		for k in range(1, 6):
			(bar.find_child("Code_%d" % k, true, false) as Node3D).visible = k <= 5 - i * 2   # осталось вскрыть 5 / 3 / 1 кодов
		add_child(bar)
	var tr := NodeAssets.instance("res://assets/models/ice/tracer_ice.glb")
	tr.position = Vector3(4.5, 0, -6.0)
	for k in range(1, 5):
		(tr.find_child("Tail_%d" % k, true, false) as Node3D).visible = k <= 3
	add_child(tr)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.current = true
	add_child(cam)
	var shots := [
		["barriers", Vector3(-3.0, 1.4, -2.5), Vector3(-3.0, 0.8, -6.0)],        # со спины (+Z Godot)
		["barriers_front", Vector3(-3.0, 1.4, -9.5), Vector3(-3.0, 0.8, -6.0)],  # с лица (−Z Godot): код читается с обеих сторон
		["tracer", Vector3(7.0, 1.2, -3.5), Vector3(4.5, 0.3, -6.5)],
		["overview", Vector3(0.0, 4.2, 5.0), Vector3(0.0, 0.0, -1.0)],
		["lighthouses", Vector3(0.0, 2.2, 1.0), Vector3(0.0, 0.2, -2.5)],
		["sensors_close", Vector3(-1.0, 1.0, 2.6), Vector3(-3.0, 0.2, -0.5)],
		["sensors_eye", Vector3(0.0, 1.2, 4.0), Vector3(0.0, 0.2, -1.5)],
		["lighthouse_close", Vector3(-3.0, 1.1, -0.2), Vector3(-4.5, 0.6, -2.0)],
		["emitter_close", Vector3(-3.4, 0.7, 2.2), Vector3(-4.5, 0.3, 1.0)],
	]
	for sh in shots:
		cam.look_at_from_position(sh[1], sh[2])
		for k in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, sh[0]])
		print("кадр ", sh[0])
	get_tree().quit()

extends Node3D
## Снимки ассетов «Сети» для приёмки: расставляет ассеты, применяет шейдеры (AssetMaterials) и сохраняет PNG.
## Запуск на devbox в окне (нужен GPU): godot --path <проект> --resolution 1280x720 -- --out=<каталог для PNG>
## Вид проверяем только здесь: вьюпорт Blender аддитивные материалы не показывает. Частота кадров на Pico 4 не проверяется.

const AM := preload("res://assets/asset_materials.gd")
const BG := Color(0.004, 0.008, 0.016)

## Кадры. Предмет: путь, позиция, поворот Y (°), тир, масштаб. corrupt — [мировая точка, радиус] красного «шрама» на стенах;
## fade — [начало, конец] затухания по расстоянию. Композиция намеренно не по центру: диагональ и несколько планов глубины.
const SHOTS := [
	{"name": "scene_a", "cam": Vector3(1.6, 1.3, 3.4), "look": Vector3(-0.3, 1.0, -3.0), "fade": [10.0, 34.0],
		"corrupt": [Vector3(1.0, 1.0, -1.7), 4.6],
		"items": [
			["ice/soft_ice", Vector3(1.0, 0, -1.7), -28.0, "", 1.0],
			["env/wall", Vector3(-1.3, 0, -3.2), 14.0, "BASE", 1.0], ["env/wall", Vector3(0.9, 0, -3.8), -8.0, "BASE", 1.0],
			["env/wall", Vector3(3.0, 0, -1.4), -50.0, "BASE", 1.0],
			["env/wall", Vector3(-5.5, 0, -9.0), 20.0, "BASE", 3.0], ["env/wall", Vector3(6.0, 0, -14.0), -15.0, "HARD", 4.5],
			["env/wall", Vector3(-12.0, 0, -22.0), 8.0, "HARD", 7.0],
			["env/dust", Vector3(0.6, 1.4, -0.2), 0.0, "", 1.0], ["env/dust", Vector3(-1.5, 1.5, -2.0), 40.0, "", 1.6],
			["env/dust", Vector3(2.0, 2.0, -7.0), 0.0, "", 3.0], ["env/dust", Vector3(-3.0, 2.5, -14.0), 0.0, "", 5.0]]},
	{"name": "ice_close", "cam": Vector3(2.4, 1.0, 2.6), "look": Vector3(0.0, 1.0, -0.4), "fade": [10.0, 34.0],
		"corrupt": [Vector3(0.0, 1.0, -0.4), 4.0],
		"items": [
			["ice/soft_ice", Vector3(0, 0, 0), -35.0, "", 1.0],
			["env/wall", Vector3(-1.0, 0, -1.7), 10.0, "BASE", 1.0], ["env/wall", Vector3(1.9, 0, -1.2), -55.0, "BASE", 1.0],
			["env/dust", Vector3(0.0, 1.4, -0.6), 0.0, "", 1.0]]},
	{"name": "wall_close", "cam": Vector3(1.6, 1.2, 2.6), "look": Vector3(0.0, 1.0, 0.0), "fade": [10.0, 34.0], "corrupt": [Vector3(0, 0, 0), 0.0],
		"items": [["env/wall", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/dust", Vector3(0.0, 1.3, 0.8), 0.0, "", 1.0]]},
]

var out_dir := "/tmp/shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for shot in SHOTS:
		var root := Node3D.new()
		add_child(root)
		for it in shot["items"]:
			var scene: PackedScene = load("res://assets/models/%s.glb" % it[0])
			var inst: Node3D = scene.instantiate()
			inst.position = it[1]
			inst.rotation_degrees.y = it[2]
			inst.scale = Vector3.ONE * it[4]
			root.add_child(inst)
			AM.apply(inst, it[3])
			AM.set_distance_fade(inst, shot["fade"][0], shot["fade"][1])
			if String(it[0]).begins_with("env/wall"):
				AM.set_corruption(inst, shot["corrupt"][0], shot["corrupt"][1])
		cam.look_at_from_position(shot["cam"], shot["look"])
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, shot["name"]])
		print("SHOT ", shot["name"], " ", img.get_size())
		root.queue_free()
		await get_tree().process_frame
	get_tree().quit()

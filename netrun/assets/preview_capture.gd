extends Node3D
## Снимки ассетов «Сети» для приёмки: расставляет ассеты, применяет шейдеры (AssetMaterials) и сохраняет PNG.
## Запуск на devbox в окне (нужен GPU): godot --path <проект> --resolution 1280x720 -- --out=<каталог для PNG>
## Вид проверяем только здесь: вьюпорт Blender аддитивные материалы не показывает. Частота кадров на Pico 4 не проверяется.

const AM := preload("res://assets/asset_materials.gd")
const BG := Color(0.004, 0.008, 0.016)

## Кадры: имя, список предметов (путь, позиция, поворот Y в градусах, тир), позиция камеры, куда смотрит.
const SHOTS := [
	{"name": "shard", "items": [["props/shard", Vector3(0, 0, 0), 0.0, ""]], "cam": Vector3(0.0, 0.05, 0.45), "look": Vector3(0, 0, 0)},
	{"name": "wall_tiers", "items": [
		["env/wall", Vector3(-2.2, 0, 0), 0.0, "BASE"], ["env/wall", Vector3(0, 0, 0), 0.0, "HARD"], ["env/wall", Vector3(2.2, 0, 0), 0.0, "NIGHTMARE"]],
		"cam": Vector3(0.0, 1.3, 5.2), "look": Vector3(0, 1.0, 0)},
	{"name": "soft_ice", "items": [["ice/soft_ice", Vector3(0, 0, 0), 0.0, ""]], "cam": Vector3(0.0, 1.3, 3.2), "look": Vector3(0, 1.0, 0)},
	{"name": "scene", "items": [
		["env/wall", Vector3(-2.0, 0, -3.0), 0.0, "BASE"], ["env/wall", Vector3(0.0, 0, -3.0), 0.0, "BASE"], ["env/wall", Vector3(2.0, 0, -3.0), 0.0, "BASE"],
		["env/wall", Vector3(-3.0, 0, -2.0), 90.0, "BASE"], ["env/wall", Vector3(3.0, 0, -2.0), 90.0, "BASE"],
		["ice/soft_ice", Vector3(0.6, 0, -1.2), 0.0, ""], ["props/shard", Vector3(-0.5, 1.0, -0.6), 0.0, ""]],
		"cam": Vector3(0.0, 1.2, 2.4), "look": Vector3(0, 1.1, -2.0)},
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
			root.add_child(inst)
			AM.apply(inst, it[3])
		cam.look_at_from_position(shot["cam"], shot["look"])
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, shot["name"]])
		print("SHOT ", shot["name"], " ", img.get_size())
		root.queue_free()
		await get_tree().process_frame
	get_tree().quit()

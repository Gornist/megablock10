extends Node3D
## Снимки ассетов «Сети» для приёмки: расставляет ассеты, применяет шейдеры (AssetMaterials) и сохраняет PNG.
## Запуск на devbox в окне (нужен GPU): godot --path <проект> --resolution 1280x720 -- --out=<каталог для PNG>
## Вид проверяем только здесь: вьюпорт Blender аддитивные материалы не показывает. Частота кадров на Pico 4 не проверяется.

const AM := preload("res://assets/asset_materials.gd")
const BG := Color(0.004, 0.008, 0.016)

## Комната 6×6 м из модулей 2×2 м: пол 3×3, стены по периметру, колонны в углах, вход с юга (z=+3), выход на север (z=-3),
## в центре шард, у выхода ICE. Предмет: [путь, позиция, поворот Y (°), тир, масштаб].
const REFLECT := ["env/wall", "env/doorway", "env/pillar", "ice/soft_ice"]
const ICE_POS := Vector3(0.75, 0.0, -2.0)


func _room() -> Array:
	var items: Array = []
	var variants := ["env/floor", "env/floor_b", "env/floor_c"]
	var n := 0
	for x in [-2.0, 0.0, 2.0]:
		for z in [-2.0, 0.0, 2.0]:
			items.append([variants[n % 3], Vector3(x, 0, z), 90.0 * (n % 4), "BASE", 1.0])  # вариант и поворот по кругу: узор не повторяется
			n += 1
	for x in [-2.0, 2.0]:
		items.append(["env/wall", Vector3(x, 0, -3.0), 0.0, "BASE", 1.0])
		items.append(["env/wall", Vector3(x, 0, 3.0), 0.0, "BASE", 1.0])
	for z in [-2.0, 0.0, 2.0]:
		items.append(["env/wall", Vector3(-3.0, 0, z), 90.0, "BASE", 1.0])
		items.append(["env/wall", Vector3(3.0, 0, z), 90.0, "BASE", 1.0])
	items.append(["env/doorway", Vector3(0.0, 0, 3.0), 0.0, "BASE", 1.0])   # вход
	items.append(["env/doorway", Vector3(0.0, 0, -3.0), 0.0, "HARD", 1.0])  # выход
	for x in [-3.0, 3.0]:
		for z in [-3.0, 3.0]:
			items.append(["env/pillar", Vector3(x, 0, z), 0.0, "BASE", 1.0])
	items.append(["env/pillar", Vector3(0.0, 0, 0.0), 0.0, "BASE", 0.4])  # подставка: колонна ×0.4, высота ≈ 0,9 м
	items.append(["props/shard", Vector3(0.0, 1.2, 0.0), 0.0, "", 3.5])  # ×3,5: на 6 м шард в 8 см иначе не разглядеть
	items.append(["ice/soft_ice", ICE_POS, 15.0, "", 1.0])
	items.append(["env/wall", Vector3(-6.0, 0, -14.0), 0.0, "HARD", 4.0])
	items.append(["env/wall", Vector3(7.0, 0, -19.0), 0.0, "HARD", 5.0])
	return items


func _shots() -> Array:
	var room := _room()
	var scar := [ICE_POS + Vector3(0, 1.0, -0.6), 4.2]
	return [
		{"name": "room_entrance", "cam": Vector3(0.0, 1.25, 6.4), "look": Vector3(0.0, 1.0, -2.0), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
		{"name": "room_overview", "cam": Vector3(8.5, 8.0, 8.5), "look": Vector3(0.0, 0.4, -0.5), "fov": 50.0, "fade": [30.0, 80.0], "corrupt": scar, "items": room},
		{"name": "room_inside", "cam": Vector3(-2.2, 1.25, 2.3), "look": Vector3(0.3, 0.9, -2.4), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
	]


var out_dir := "/tmp/shots"


var _movie := false
var _static := false
var _t := 0.0
var _cam: Camera3D
var _insts: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a == "--movie":
			_movie = true
		if a == "--static":  # камера неподвижна: нужно, чтобы по разнице кадров проверять движение штрихов
			_static = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	if _movie:
		# Видео: godot --write-movie <файл.avi> --fixed-fps 24 --quit-after 160 -- --movie. Камера идёт ко входу и в комнату,
		# на 2,5 с «касание» стены у выхода: прогиб штрихов и красная полоса расходятся (как в референсе «contact»).
		var shot: Dictionary = _shots()[0]
		_build(shot, add_child_ret(Node3D.new()))
		set_process(true)
		return
	set_process(false)
	for shot in _shots():
		var root := Node3D.new()
		add_child(root)
		_build(shot, root)
		_cam.fov = shot["fov"]
		_cam.look_at_from_position(shot["cam"], shot["look"])
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, shot["name"]])
		print("SHOT ", shot["name"], " ", img.get_size())
		root.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func add_child_ret(n: Node) -> Node:
	add_child(n)
	return n


func _build(shot: Dictionary, root: Node) -> void:
	_insts.clear()
	for it in shot["items"]:
		var scene: PackedScene = load("res://assets/models/%s.glb" % it[0])
		var inst: Node3D = scene.instantiate()
		inst.position = it[1]
		inst.rotation_degrees.y = it[2]
		inst.scale = Vector3.ONE * it[4]
		root.add_child(inst)
		_setup(inst, it, shot, 1.0)
		if String(it[0]) in REFLECT:  # отражение в полу: зеркальная копия, тусклая (в референсе Blackwall пол — мутное зеркало)
			var mir: Node3D = scene.instantiate()
			mir.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3.ZERO) * inst.transform
			root.add_child(mir)
			_setup(mir, it, shot, 0.18)


func _process(delta: float) -> void:
	_t += delta
	if _static:
		_cam.look_at_from_position(Vector3(0.0, 1.25, 6.4), Vector3(0.0, 1.0, -2.0))
		return
	var p: Vector3
	var look: Vector3
	if _t < 2.0:
		p = Vector3(0.0, 1.25, 6.4).lerp(Vector3(0.0, 1.25, 3.6), _t / 2.0)
		look = Vector3(0.0, 1.0, -2.0)
	else:
		var u: float = clampf((_t - 2.0) / 4.0, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		p = Vector3(0.0, 1.25, 3.6).lerp(Vector3(-1.4, 1.25, 1.0), u)
		look = Vector3(0.0, 1.0, -2.0).lerp(Vector3(1.0, 1.0, -2.6), u)
	_cam.look_at_from_position(p, look)
	# касание: радиус растёт 0 → 2,8 м за 2 с, держится, затухает
	var r := 0.0
	if _t > 2.5 and _t < 6.5:
		var k: float = clampf((_t - 2.5) / 2.0, 0.0, 1.0)
		r = 2.8 * k * (1.0 - clampf((_t - 5.5) / 1.0, 0.0, 1.0))
	for inst in _insts:
		AM.set_param(inst, "touch_pos", Vector3(1.2, 1.0, -2.9))
		AM.set_param(inst, "touch_radius", r)


func _setup(inst: Node3D, it: Array, shot: Dictionary, intensity: float) -> void:
	_insts.append(inst)
	AM.apply(inst, it[3])
	if String(it[0]).begins_with("ice/"):
		AM.set_param(inst, "breathe", 0.12)  # существа «дышат»: длина штрихов медленно плывёт
	AM.set_distance_fade(inst, shot["fade"][0], shot["fade"][1])
	if String(it[0]).begins_with("env/"):
		AM.set_corruption(inst, shot["corrupt"][0], shot["corrupt"][1])
	if intensity != 1.0:
		AM.set_intensity(inst, intensity)

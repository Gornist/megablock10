class_name ShaderWarmup
extends Node3D
## Прогрев шейдеров при старте клиента. Godot компилирует пайплайн материала при первой отправке draw, а не при загрузке сцены, и отсекает невидимое по
## фрустуму, поэтому «первый показ» материала посреди игры даёт долгий кадр (на очках первые ~70 с кадр в среднем 16,5 мс против 11,4 потом, 184 долгих кадра —
## подозрение на компиляцию, не доказано). Здесь по одному экземпляру каждого материала мира ставится ПЕРЕД камерой в её фрустум (2,5 м, 5 см), на `frames`
## кадров; чтобы игрок этого не видел, ближе всех (0,3 м) стоит непрозрачный чёрный квад-экран. Потом всё освобождается, приходит `done`.
##
## Вызов: `ShaderWarmup.enabled = true` (по умолчанию выкл., чтобы не менять порядок кадров в тестах мира; клиент включает его из `[render] warmup`),
## узел в дерево, `start(camera)` — камера уже в дереве. Второй вызов — no-op. Материалы Blender (AssetMaterials, шейдеры, BackdropDome) не меняются:
## берутся готовыми через NodeAssets.instance / конструкторы классов клиента.

## Прогрев закончен: frames (сколько кадров прождали), meshes (сколько мешей/меток/мультимешей показали), ms (сколько заняло от start).
signal done(info: Dictionary)

## Включён ли прогрев вообще (клиент ставит из RenderConfig.warmup).
static var enabled := false

const DISTANCE := 2.5          ## от камеры до мелочи прогрева, м
const SCREEN_DISTANCE := 0.3   ## от камеры до чёрного экрана, м (ближе всего)
const SCREEN_SIZE := 6.0       ## сторона экрана, м: перекрывает любое поле зрения на 0,3 м
const ITEM_SIZE := 0.05        ## наибольший размер каждого экземпляра, м
const SPACING := 0.1           ## шаг сетки, м
const COLUMNS := 8
const DEFAULT_FRAMES := 3

## Модули окружения: (имя, путь) — тир BASE. exit_frame клиент сплошным не ставит (рамка выхода — облако), floor/floor_b/floor_c не используются (пол — floor_slab_16).
const ENV_MODULES := ["floor_slab_16", "pillar", "cover", "platform", "lockdown_gate"]
## Реквизит узла (props/*.glb).
const PROPS := ["vault", "portal", "portal_locked", "shard", "shard_encrypted", "hack_pad", "hack_panel", "seat", "dead_deck", "daemon_token"]
## ICE и вспомогательные существа (путь от NodeAssets.ROOT): базовая и Black ICE, логово, Датчик, Барьер, Маяк, аватар-запасной.
const CREATURES := ["ice/soft_ice.glb", "ice/black_ice.glb", "ice/black_lair.glb", "ice/sensor_ice.glb", "ice/barrier_ice.glb", "ice/lighthouse_ice.glb", "avatar/runner.glb"]
## Строки для Label3D: кириллица и цифры (глифы шрифта по умолчанию растеризуются при первом показе).
const LABEL_TEXT := "Мегаблок №10 · взлом 0123456789 ЖЩЯёй"

## Что показано (имена) и что пропущено (нет файла) — для журнала и отчёта.
var warmed: Array[String] = []
var skipped: Array[String] = []
var meshes := 0
var frames_run := 0
var finished := false

var anchor: Node3D        ## родитель образцов, ребёнок камеры
var screen: MeshInstance3D   ## чёрный экран, ребёнок камеры

var _started := false
var _slot := 0


## Начать прогрев перед камерой (она уже в дереве). false — не начат (выключен, уже запускался, камеры нет).
func start(camera: Camera3D, frames := DEFAULT_FRAMES) -> bool:
	if not enabled or _started or camera == null or not camera.is_inside_tree() or not is_inside_tree():
		return false
	_started = true
	var t0 := Time.get_ticks_msec()
	anchor = Node3D.new()
	anchor.name = "WarmupItems"
	anchor.position = Vector3(0.0, 0.0, -DISTANCE)
	camera.add_child(anchor)
	screen = _make_screen()
	camera.add_child(screen)
	_populate()
	meshes = _count_renderables()
	_wait(maxi(frames, 1), t0)
	return true


func _wait(frames: int, t0: int) -> void:
	for i in frames:
		await get_tree().process_frame
		frames_run += 1
		if not is_inside_tree():   # узел убрали (смена сцены): просто прибрать
			break
	_cleanup()
	finished = true
	done.emit({"frames": frames_run, "meshes": meshes, "ms": Time.get_ticks_msec() - t0})


func _cleanup() -> void:
	for n: Node in [anchor, screen]:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()


func _make_screen() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(SCREEN_SIZE, SCREEN_SIZE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "WarmupScreen"
	mi.mesh = quad
	mi.position = Vector3(0.0, 0.0, -SCREEN_DISTANCE)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _populate() -> void:
	for m in ENV_MODULES:
		_model(NodeAssets.env_path(m), "env/" + m, "BASE")
	for p in PROPS:
		_model(NodeAssets.prop_path(p), "props/" + p)
	for c in CREATURES:
		_model(NodeAssets.ROOT + c, c.get_basename())
	# Облако частиц (VolumeCloud: body_particles.gdshader — им же рисуются руки/голова чужих аватаров), без файла точек: 4 точки разного вида.
	var cloud := VolumeCloud.new()
	cloud.auto_lod = false
	cloud.setup(PackedFloat32Array([
		-1.0, 0.0, 0.0, 0.3, 0.1, 0.0, 1.0,
		1.0, 0.0, 0.0, 0.3, 0.4, 1.0, 1.0,
		0.0, 1.0, 0.0, 0.3, 0.7, 0.0, 0.5,
		0.0, -1.0, 0.0, 0.3, 0.9, 1.0, 0.5]), AssetMaterials.layer("hud_ok"), AABB())
	_put(cloud, "volume_cloud")
	# Руки и голова: свои шейдеры частиц (hand_particles — своя рука, body_particles — чужая с проверкой глубины).
	var hand := HandView.new(false)
	hand.set_process(false)
	hand.visible = true
	_put(hand, "hand_view")
	var hand_remote := HandView.new(true)
	hand_remote.set_occluded(true)
	hand_remote.set_process(false)
	hand_remote.visible = true
	_put(hand_remote, "hand_view_remote")
	var head := HeadCloud.new()
	head.set_process(false)
	_put(head, "head_cloud")
	# Тоннель перехода (шейдер на сфере) и вспышка ожога (шейдер Blender, strength 0).
	var tunnel := TunnelFx.new()
	tunnel.visible = true
	_put(tunnel, "tunnel_fx")
	var flash := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2.ONE
	fq.material = AssetMaterials.burn_flash_material()
	flash.mesh = fq
	_put(flash, "burn_flash")
	# Метки Label3D (шрифт глифов, Label3DSharp), как в мире: кириллица и цифры.
	var label := Label3D.new()
	label.text = LABEL_TEXT
	label.font_size = 48
	label.pixel_size = 0.004
	label.outline_size = 8
	label.modulate = AssetMaterials.layer("label")
	Label3DSharp.apply(label)
	_put(label, "label3d")
	var billboard := Label3D.new()
	billboard.text = "0123456789"
	billboard.font_size = 32
	billboard.pixel_size = 0.004
	billboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	billboard.modulate = AssetMaterials.layer("label")
	Label3DSharp.apply(billboard)
	_put(billboard, "label3d_billboard")
	# Стандартные материалы указок, пола тактов, колец, глаза ICE: без освещения, прозрачные/непрозрачные, обычные и по цвету вершин (мультимеш).
	_put(_std_mesh(QuadMesh.new(), true, false), "std_alpha")
	_put(_std_mesh(QuadMesh.new(), true, true), "std_alpha_vertex_color")
	_put(_std_multimesh(), "std_multimesh_colors")
	_put(_std_mesh(SphereMesh.new(), false, false), "std_opaque")


## Модель из ассетов (пропуск, если файла нет в клиенте).
func _model(path: String, label: String, tier := "") -> void:
	if not ResourceLoader.exists(path):
		skipped.append(label)
		return
	_put(NodeAssets.instance(path, tier), label)


## Поставить образец в следующий слот сетки и ужать до ITEM_SIZE.
func _put(n: Node3D, label: String) -> void:
	anchor.add_child(n)
	var col := _slot % COLUMNS
	var row := floori(float(_slot) / COLUMNS)
	n.position = Vector3((col - (COLUMNS - 1) * 0.5) * SPACING, -row * SPACING, 0.0)
	n.scale = Vector3.ONE * _fit_scale(n)
	_slot += 1
	warmed.append(label)


## Масштаб, при котором наибольшая сторона мешей узла равна ITEM_SIZE; у узлов без MeshInstance3D (мультимеши) — ITEM_SIZE как есть.
func _fit_scale(n: Node3D) -> float:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := inv * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var ext := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if first or ext < 0.0001:
		return ITEM_SIZE
	return ITEM_SIZE / ext


func _count_renderables() -> int:
	var n := 0
	for cls in ["MeshInstance3D", "MultiMeshInstance3D", "Label3D"]:
		n += anchor.find_children("*", cls, true, false).size()
	return n


func _std_material(alpha: bool, vertex_color: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if vertex_color:
		mat.vertex_color_use_as_albedo = true
	return mat


func _std_mesh(mesh: PrimitiveMesh, alpha: bool, vertex_color: bool) -> MeshInstance3D:
	mesh.material = _std_material(alpha, vertex_color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _std_multimesh() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.material = _std_material(true, true)
	mm.mesh = quad
	mm.instance_count = 1
	mm.set_instance_color(0, Color(1, 1, 1, 0.5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi

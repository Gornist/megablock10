class_name BackdropDome
extends MeshInstance3D
## Фон-купол Сети (решение владельца 18.10, шаг B): внутренняя сторона сферы вокруг головы вместо дальней геометрии с частицами — почти-чёрная пустота, дымка у горизонта и
## неподвижные пылинки (shaders/backdrop.gdshader). Клиент добавляет его ребёнком любого Node3D (позиция не важна: шейдер берёт из вида только поворот), цвет пустоты по
## тревоге — set_alarm(level, tick_phase), как Environment.background_color. Рисуется первым, глубину не читает и не пишет; на дальности ничего не значит (радиус 1).

const SHADER := preload("res://assets/shaders/backdrop.gdshader")
const DUST_SIZE := Vector2i(4096, 2048)   # 360°×180°: ≈ 11 текселей на градус, на Pico ≈ 15 px/° — пылинки не мельче пикселя, mip не нужен (шва по ∂uv нет)
const DUST_COUNT := 4200
const DUST_SEED := 1018

static var _dust: ImageTexture


func _init() -> void:
	name = "BackdropDome"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	mesh = sphere
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = -128
	m.set_shader_parameter("dust_tex", dust_texture())
	material_override = m
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))   # не отсекается по положению: вершины пересчитываются в вершинном шейдере
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Цвет пустоты по уровню тревоги (0…4) и доле такта — тот же, что у `AssetMaterials.alarm_background` для Environment.
func set_alarm(level: int, tick_phase := 0.0) -> void:
	var c := AssetMaterials.alarm_background(level, tick_phase)
	(material_override as ShaderMaterial).set_shader_parameter("void_color", c)


## Равнопромежуточная текстура пылинок (один раз на процесс): ~DUST_COUNT мягких точек 2–3 текселя, у полюсов шире по x (развёртка растягивает), яркость разная; чёрный фон.
static func dust_texture() -> ImageTexture:
	if _dust != null:
		return _dust
	var img := Image.create_empty(DUST_SIZE.x, DUST_SIZE.y, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = DUST_SEED
	for i in DUST_COUNT:
		var y := rng.randf_range(0.04, 0.96)   # не у самих полюсов
		var x := rng.randf() * DUST_SIZE.x
		var py := y * DUST_SIZE.y
		var stretch := 1.0 / maxf(sin(y * PI), 0.15)   # у полюса градус по x мельче: точка шире, чтобы не стать полоской-иглой
		var b := pow(rng.randf(), 2.0) * 0.9 + 0.1
		var rx := 1.3 * stretch
		for dy in range(-2, 3):
			for dx in range(int(-ceil(rx * 1.6)), int(ceil(rx * 1.6)) + 1):
				var d := sqrt(float(dx) * float(dx) / (stretch * stretch) + float(dy) * float(dy))
				var k := clampf(1.0 - d / 1.6, 0.0, 1.0)
				if k <= 0.0:
					continue
				var px := posmod(int(x) + dx, DUST_SIZE.x)
				var qy := clampi(int(py) + dy, 0, DUST_SIZE.y - 1)
				var cur := img.get_pixel(px, qy).r
				img.set_pixel(px, qy, Color(maxf(cur, b * k * k), 0.0, 0.0))
	_dust = ImageTexture.create_from_image(img)
	return _dust

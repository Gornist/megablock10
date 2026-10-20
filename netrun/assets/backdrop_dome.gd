class_name BackdropDome
extends MultiMeshInstance3D
## Фон Сети (решение владельца 18.10, шаг B): дальний план — только «звёзды»: STAR_COUNT мелких светящихся точек на сфере радиуса STAR_RADIUS вокруг начала мира (shaders/stars.gdshader).
## Это мировые частицы, а не небо-шейдер: звезда стоит на месте при любом повороте головы и рига (20.10: пылинки «тянулись за гарнитурой», небо в пикселе стоило +2 мс на Pico).
## Клиент добавляет узел ребёнком мира (положение — начало мира; поворот родителя не нужен, но и не мешает звёздам: они просто часть мира).
## Цвет пустоты по тревоге — set_alarm(level, tick_phase): передаётся просветам граней облака (AssetMaterials.set_sky_void), как Environment.background_color.

const SHADER := preload("res://assets/shaders/stars.gdshader")
const STAR_COUNT := 2400
const STAR_RADIUS := 55.0   # м: дальше комнаты (≈20 м), ближе дальности камеры; параллакс при сдвиге головы на 0,3 м ≈ 0,3°
const STAR_SEED := 1018

## Позиции звёзд (мир, м): то же, что записано в MultiMesh — под headless-рендером он ничего не хранит, а тестам нужно проверить положение.
var star_positions := PackedVector3Array()


func _init() -> void:
	name = "BackdropDome"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = STAR_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for i in STAR_COUNT:
		var z := rng.randf_range(-1.0, 1.0)
		var a := rng.randf() * TAU
		var r := sqrt(1.0 - z * z)
		var dir := Vector3(r * cos(a), z, r * sin(a))
		star_positions.append(dir * STAR_RADIUS)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, dir * STAR_RADIUS))
		mm.set_instance_custom_data(i, Color(pow(rng.randf(), 2.0) * 0.65 + 0.35, 0.0, 0.0, 0.0))   # яркость 0,35…1: все видны, редкие ярче
	multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = -128
	m.set_shader_parameter("star_gain", float(AssetMaterials.knob("backdrop_dust")))
	material_override = m
	visible = float(AssetMaterials.knob("backdrop")) > 0.0   # 0 — звёзд нет (A/B на очках без пересборки)
	custom_aabb = AABB(Vector3(-1e3, -1e3, -1e3), Vector3(2e3, 2e3, 2e3))   # не отсекается по положению камеры
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Свет пустоты по уровню тревоги (0…4) и доле такта: просветам граней облака (звёзды его не используют). Спокойный узел — ноль, тревога — красный сдвиг фона.
func set_alarm(level: int, tick_phase := 0.0) -> void:
	AssetMaterials.set_sky_void(get_tree(), void_for(level, tick_phase))


## Свет пустоты по уровню тревоги: alarm_background(level) − alarm_background(0), без отрицательных каналов (сам фон рисует Environment клиента).
static func void_for(level: int, tick_phase := 0.0) -> Color:
	var c := AssetMaterials.alarm_background(level, tick_phase)
	var calm := AssetMaterials.alarm_background(0)
	return Color(maxf(c.r - calm.r, 0.0), maxf(c.g - calm.g, 0.0), maxf(c.b - calm.b, 0.0))

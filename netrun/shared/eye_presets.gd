class_name EyePresets
extends RefCounted
## Общие пресеты камеры: поза глаз игрока в Фойе и обзорные кадры сверху. Чистые данные, без сцены.
## По ним снимает приёмочные кадры tests/foyer_preview.tscn (dev.sh shot) и сверяется вид окружения с тем, что рисует клиент
## (assets/ARCHITECTURE.md, п. 18): раньше кадры Blender-проекта брались по своим камерам и принимали то, чего нет в клиенте.
## Пресет: {pos: Vector3, look: Vector3, fov: float (вертикальный, градусы), up: Vector3, eye: bool}. eye = true — камера в позе глаз игрока.

## Высота глаз: камера риг-а в кресле узла (client/xr_rig.tscn, XRCamera3D y = 1,2 над полом); риг стоит на SPAWN с y = 0.
## Не 1,6 м «стоя»: в Сети игрок сидит (props/seat.glb), тест eye_presets_test сверяет число с xr_rig.tscn.
const EYE_HEIGHT := 1.2
## Вертикальный fov кадров «глазами»: у Pico 4 ≈ 90–100°, в клиенте его задаёт гарнитура (xr_rig.gd fov не ставит), на очках не замерен.
const FOV_DEG := 90.0
## Обзорные кадры сверху: узкий fov, чтобы перспектива не искажала план.
const TOP_FOV_DEG := 50.0
## Наклон взгляда у входа: так смотрела плоская камера прежнего кадра eye.
const ENTRY_PITCH_DEG := -12.0
## Высота точки, на которую смотрят «глаза» при взгляде на предметы (метка шарда у хранилища, props/vault_*.glb).
const LOOK_Y := 1.0
## Высота камеры обзора на всю комнату и на половину (северную, южную).
const TOP_HEIGHT := 21.0
const TOP_HALF_HEIGHT := 11.0
## Центр кадра половины комнаты — в метрах от соответствующей стены.
const TOP_HALF_OFFSET := 4.5

static var PRESETS: Dictionary = _build()


## Имена пресетов в порядке кадров.
static func names() -> Array:
	return PRESETS.keys()


## Копия пресета по имени; пустой словарь, если такого нет.
static func get_preset(name_: String) -> Dictionary:
	if not PRESETS.has(name_):
		return {}
	return (PRESETS[name_] as Dictionary).duplicate()


static func _eye(pos_floor: Vector3, look: Vector3) -> Dictionary:
	return {"pos": pos_floor + Vector3(0.0, EYE_HEIGHT, 0.0), "look": look, "fov": FOV_DEG, "up": Vector3.UP, "eye": true}


## Сверху: «вверх» кадра — север (−Z), потолок и дальние пласты кадр прячет сам.
static func _top(center: Vector3, height: float) -> Dictionary:
	return {"pos": center + Vector3(0.0, height, 0.0), "look": center, "fov": TOP_FOV_DEG, "up": Vector3(0.0, 0.0, -1.0), "eye": false}


static func _build() -> Dictionary:
	var spawn := NodeLayout.SPAWN
	var pitch := deg_to_rad(ENTRY_PITCH_DEG)
	var entry_look := spawn + Vector3(0.0, EYE_HEIGHT, 0.0) + Vector3(0.0, sin(pitch), -cos(pitch)) * 10.0   # на север, как вход в Фойе
	# Хранилища Фойе — углы северной стены (блоки (0; 0) и (7; 0)), порталы между ними; у западного — площадка в блоке (0; 1).
	var north_eye := NodeLayout.cell_center(3, 4)
	var north_look := NodeLayout.cell_center(3, 0) + Vector3(0.0, LOOK_Y, 0.0)
	var south_eye := NodeLayout.cell_center(3, 2)
	var south_look := (NodeLayout.SPAWN + NodeLayout.EXIT_POS) * 0.5 + Vector3(0.0, 0.5, 0.0)   # между входом и площадкой выхода
	# Западное хранилище и его площадка — по раскладке (центры клеток 1 м), а не по центрам блоков 2×2.
	var west: Dictionary = LayoutData.cached("foyer").vaults[0]
	var west_slot: Vector3 = west["slot"]
	var vault := Vector3(west_slot.x, LOOK_Y, west_slot.z)
	var vault_pad: Vector3 = west["pad"]
	var center := Vector3(NodeLayout.ROOM_CENTER.x, 0.0, NodeLayout.ROOM_CENTER.z)
	var north_c := Vector3(center.x, 0.0, NodeLayout.ROOM_MIN.y + TOP_HALF_OFFSET)
	var south_c := Vector3(center.x, 0.0, NodeLayout.ROOM_MAX.y - TOP_HALF_OFFSET)
	return {
		"entry": _eye(spawn, entry_look),
		"north": _eye(north_eye, north_look),
		"south": _eye(south_eye, south_look),
		"vault_w": _eye(vault_pad, vault),
		"top": _top(center, TOP_HEIGHT),
		"top_north": _top(north_c, TOP_HALF_HEIGHT),
		"top_south": _top(south_c, TOP_HALF_HEIGHT),
	}

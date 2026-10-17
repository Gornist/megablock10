class_name EyePresets
extends RefCounted
## Общие пресеты камеры: поза глаз игрока в Фойе и обзорные кадры сверху. Чистые данные, без сцены.
## По ним снимает приёмочные кадры tests/foyer_preview.tscn (dev.sh shot) и сверяется вид окружения с тем, что рисует клиент
## (assets/ARCHITECTURE.md, п. 18): раньше кадры Blender-проекта брались по своим камерам и принимали то, чего нет в клиенте.
## Пресет: {pos: Vector3, look: Vector3, fov: float (вертикальный, градусы), up: Vector3, eye: bool}. eye = true — камера в позе глаз игрока.

## Высота глаз: камера риг-а в кресле узла (client/xr_rig.tscn, XRCamera3D y = 1,2 над полом); риг стоит на SPAWN с y = 0.
## Не 1,6 м «стоя»: в Сети игрок сидит (props/seat.glb), тест eye_presets_test сверяет число с xr_rig.tscn.
const EYE_HEIGHT := 1.2
## Вертикальный fov кадров «глазами»: у Pico 4 ≈ 100°, в клиенте его задаёт гарнитура (xr_rig.gd fov не ставит), на очках не замерен.
const FOV_DEG := 100.0
## Размер кадра на один глаз у Pico 4 (2160×2160): кадры «глазами» снимаются Viewport'ом такого размера, а не окном 1280×720,
## иначе видна «лесенка» другого масштаба, чем в очках (tests/foyer_preview.gd).
const EYE_VIEWPORT := Vector2i(2160, 2160)
## Обзорные кадры сверху: узкий fov, чтобы перспектива не искажала план.
const TOP_FOV_DEG := 50.0
## Наклон взгляда у входа: так смотрела плоская камера прежнего кадра eye.
const ENTRY_PITCH_DEG := -12.0
## Поза «клина» (кадр с очков v10.jpeg, 12.10): от входа, взгляд на 35° вправо (на восток) и на 30° вверх — у пола справа за последним рядом клеток видна
## яркая плоскость, уходящая клином в нижний угол. Приближение по кадру: точную позу уточняют в сеансе очков.
const WEDGE_YAW_DEG := 35.0
const WEDGE_PITCH_DEG := 30.0
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


## Копия пресета по имени; пустой словарь, если такого нет. `ld` — раскладка другого размера (не 8×8): центр, края и высота обзора по ней
## (см. for_layout); без неё — пресеты Фойе 8×8, как прежде.
static func get_preset(name_: String, ld: LayoutData = null) -> Dictionary:
	var all: Dictionary = PRESETS if ld == null else for_layout(ld)
	if not all.has(name_):
		return {}
	return (all[name_] as Dictionary).duplicate()


## Все пресеты для раскладки: вход, хранилище и выход — её; центр кадров сверху — центр её комнаты, края половин — её стены, высота обзора растёт
## с большей стороной (fov сверху узкий, 12×12 не влезла бы в 21 м). У 8×8 высота ровно TOP_HEIGHT.
static func for_layout(ld: LayoutData) -> Dictionary:
	return _build(ld)


## Во сколько раз обзор сверху выше, чем для комнаты 16×16 м: по большей стороне, не ниже 1.
static func top_scale(ld: LayoutData) -> float:
	if ld == null:
		return 1.0
	return maxf(1.0, float(maxi(ld.cols, ld.rows)) / float(NodeLayout.GRID))


static func _eye(pos_floor: Vector3, look: Vector3) -> Dictionary:
	return {"pos": pos_floor + Vector3(0.0, EYE_HEIGHT, 0.0), "look": look, "fov": FOV_DEG, "up": Vector3.UP, "eye": true}


## Сверху: «вверх» кадра — север (−Z), потолок и дальние пласты кадр прячет сам.
static func _top(center: Vector3, height: float) -> Dictionary:
	return {"pos": center + Vector3(0.0, height, 0.0), "look": center, "fov": TOP_FOV_DEG, "up": Vector3(0.0, 0.0, -1.0), "eye": false}


static func _build(ld: LayoutData = null) -> Dictionary:
	var spawn := NodeLayout.SPAWN if ld == null else ld.spawn
	var cols := NodeLayout.GRID if ld == null else ld.cols
	var rows := NodeLayout.GRID if ld == null else ld.rows
	var room_max := NodeLayout.ROOM_MAX if ld == null else ld.room_max()
	var room_center := NodeLayout.ROOM_CENTER if ld == null else ld.room_center()
	var exit_pos := NodeLayout.EXIT_POS if ld == null else ld.exit_pos
	var pitch := deg_to_rad(ENTRY_PITCH_DEG)
	var entry_look := spawn + Vector3(0.0, EYE_HEIGHT, 0.0) + Vector3(0.0, sin(pitch), -cos(pitch)) * 10.0   # на север, как вход в Фойе
	# Хранилища Фойе — углы северной стены (блоки (0; 0) и (7; 0)), порталы между ними; у западного — площадка в блоке (0; 1).
	# Для другой раскладки та же схема на оси (cols/2 − 1) — у 8×8 это 3; ряды не дальше последнего.
	var axis := maxi((cols >> 1) - 1, 0)
	var north_eye := NodeLayout.cell_center(axis, mini(4, rows - 1))
	var north_look := NodeLayout.cell_center(axis, 0) + Vector3(0.0, LOOK_Y, 0.0)
	var south_eye := NodeLayout.cell_center(axis, mini(2, rows - 1))
	var south_look := (spawn + exit_pos) * 0.5 + Vector3(0.0, 0.5, 0.0)   # между входом и площадкой выхода
	# Западное хранилище и его площадка — по раскладке (центры клеток 1 м), а не по центрам блоков 2×2.
	var wy := deg_to_rad(WEDGE_YAW_DEG)
	var wp := deg_to_rad(WEDGE_PITCH_DEG)
	var wedge_look := spawn + Vector3(0.0, EYE_HEIGHT, 0.0) + Vector3(sin(wy) * cos(wp), sin(wp), -cos(wy) * cos(wp)) * 10.0
	var vaults: Array = LayoutData.cached("foyer").vaults if ld == null or ld.vaults.is_empty() else ld.vaults
	var west: Dictionary = vaults[0]
	var west_slot: Vector3 = west["slot"]
	var vault := Vector3(west_slot.x, LOOK_Y, west_slot.z)
	var vault_pad: Vector3 = west["pad"]
	var center := Vector3(room_center.x, 0.0, room_center.z)
	var north_c := Vector3(center.x, 0.0, NodeLayout.ROOM_MIN.y + TOP_HALF_OFFSET)
	var south_c := Vector3(center.x, 0.0, room_max.y - TOP_HALF_OFFSET)
	var k := top_scale(ld)
	return {
		"entry": _eye(spawn, entry_look),
		"north": _eye(north_eye, north_look),
		"south": _eye(south_eye, south_look),
		"vault_w": _eye(vault_pad, vault),
		"wedge": _eye(spawn, wedge_look),
		"top": _top(center, TOP_HEIGHT * k),
		"top_north": _top(north_c, TOP_HALF_HEIGHT * k),
		"top_south": _top(south_c, TOP_HALF_HEIGHT * k),
	}

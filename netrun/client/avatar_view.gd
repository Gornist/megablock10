class_name AvatarView
extends Node3D
## Другой нетраннер в узле: модель avatar/runner.glb (человек из облака штрихов: голова, торс, руки, без ног). Свечение красится под игрока —
## до девяти аватаров различаются цветом. Сервер шлёт только позицию, поэтому лицо (-Z) поворачивается туда, куда аватар идёт;
## на месте он стоит как стоял. Показывает сцена по буферу состояний (RemoteTracks).

const TURN_SPEED := 8.0  # 1/с: сглаживание поворота
const MOVE_EPS := 0.01   # м за кадр: меньше — стоит
const HUES := 9
const TINT_AMOUNT := 0.6  # доля оттенка игрока в свечении аватара (остальное — красный по стилю)

var asset := NodeAssets.RUNNER
var player_id := 0

var _color := Color.BLACK


## Цвет неона игрока: девять равных ступеней по кругу оттенков, номер аватара по модулю девяти.
static func color_for(id: int) -> Color:
	return Color.from_hsv(float(posmod(id, HUES)) / float(HUES), 0.75, 1.0)


func setup(id: int) -> void:
	player_id = id
	var model := NodeAssets.instance(asset)
	model.name = "Model"
	add_child(model)
	# Фигура красная (люди, ИИ и угроза — красные по стилю), но девять игроков должны различаться: оттенок игрока подмешан в свечение (60%),
	# белые акценты и «горячая» голова остаются светлыми. Цвет — параметр шейдера штрихов и точек на всех материалах модели, включая отражение.
	_color = color_for(id)
	AssetMaterials.set_param(model, "tint", _color)
	AssetMaterials.set_param(model, "tint_amount", TINT_AMOUNT)


func neon_color() -> Color:
	return _color


## Поставить в точку; если сдвинулся — повернуть лицо по ходу (плавно).
func move_to(p: Vector3, delta: float) -> void:
	var d := p - position
	d.y = 0.0
	position = p
	if d.length() > MOVE_EPS:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(delta * TURN_SPEED, 0.0, 1.0))

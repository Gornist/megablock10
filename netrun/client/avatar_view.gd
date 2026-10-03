class_name AvatarView
extends Node3D
## Другой нетраннер в узле: модель avatar/runner.glb (голова в гарнитуре, торс, руки, без ног). Неон (поверхность 1) красится под игрока —
## до девяти аватаров различаются цветом. Сервер шлёт только позицию, поэтому лицо (-Z) поворачивается туда, куда аватар идёт;
## на месте он стоит как стоял. Показывает сцена по буферу состояний (RemoteTracks).

const TURN_SPEED := 8.0  # 1/с: сглаживание поворота
const MOVE_EPS := 0.01   # м за кадр: меньше — стоит
const HUES := 9

var asset := NodeAssets.RUNNER
var player_id := 0

var _mat: BaseMaterial3D


## Цвет неона игрока: девять равных ступеней по кругу оттенков, номер аватара по модулю девяти.
static func color_for(id: int) -> Color:
	return Color.from_hsv(float(posmod(id, HUES)) / float(HUES), 0.75, 1.0)


func setup(id: int) -> void:
	player_id = id
	var model := NodeAssets.instance(asset)
	model.name = "Model"
	add_child(model)
	var mesh := model.find_child("Mesh", true, false) as MeshInstance3D
	if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() < 2:
		return
	var base := mesh.mesh.surface_get_material(1) as BaseMaterial3D  # неон: свой материал на каждого игрока
	if base == null:
		return
	_mat = base.duplicate() as BaseMaterial3D
	var c := color_for(id)
	_mat.albedo_color = c
	if _mat.emission_enabled:
		_mat.emission = c
	mesh.set_surface_override_material(1, _mat)


func neon_color() -> Color:
	return _mat.albedo_color if _mat != null else Color.BLACK


## Поставить в точку; если сдвинулся — повернуть лицо по ходу (плавно).
func move_to(p: Vector3, delta: float) -> void:
	var d := p - position
	d.y = 0.0
	position = p
	if d.length() > MOVE_EPS:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(delta * TURN_SPEED, 0.0, 1.0))

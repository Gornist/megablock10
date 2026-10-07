class_name EndScreen
extends Node3D
## Экран конца забега перед глазами (вешается на камеру): чёрная завеса гаснет за FADE_SEC, поверх — причина и строка про очки.
## Камеру не двигает и ничего не мигает: в VR резкая подача рядом с головой хуже, чем тишина. Мир вокруг прячет и замораживает сцена
## (RigTestScene.show_ended), здесь — только то, что нарисовано на лице.

const FADE_SEC := 1.0
const TEXT_DELAY_SEC := 0.5
const VEIL_Z := -0.25
const TEXT_Z := -0.9
const TITLE_WIDTH_PX := 900.0
const HINT_NO_PAUSE := "снимите очки"

var veil: MeshInstance3D
var title: Label3D
var hint: Label3D
var _mat: StandardMaterial3D


## Заголовок по причине выхода (reason из `ended`): выброс и флэтлайн говорят, что осталось в узле.
static func title_text(reason: String) -> String:
	match reason:
		ExitLogic.REASON_EJECTED:
			return "ICE ВЫБРОСИЛ ВАС · добыча осталась в узле"
		ExitLogic.REASON_FLATLINE:
			return "ФЛЭТЛАЙН · дека осталась в узле"
		ExitLogic.REASON_CLEAN:
			return "ВЫХОД"
	return "ВЫХОД: " + reason


## Вторая строка. Клиент паузы сам не знает: если сервер положил её в событие (`reentry_sec`) — «вход снова через M:SS», иначе «снимите очки».
static func hint_text(ev: Dictionary) -> String:
	var sec := int(ceil(float(ev.get("reentry_sec", 0.0))))
	if sec <= 0:
		return HINT_NO_PAUSE
	return "вход снова через %d:%02d" % [int(sec / 60.0), sec % 60]


static func title_color(reason: String) -> Color:
	if reason == ExitLogic.REASON_CLEAN:
		return AssetMaterials.layer("end_win")
	return AssetMaterials.layer("end_lose")   # обрыв и все остальные причины — один цвет проигрыша


func _init(reason: String = "", ev: Dictionary = {}) -> void:
	name = "EndScreen"
	veil = MeshInstance3D.new()
	veil.name = "EndVeil"
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = AssetMaterials.layer("end_veil", 0.0)   # цвет завесы — слой палитры, фейд идёт по альфе
	_mat.no_depth_test = true
	_mat.render_priority = 100
	quad.material = _mat
	veil.mesh = quad
	veil.position = Vector3(0, 0, VEIL_Z)
	add_child(veil)
	title = _make_label("EndTitle", title_text(reason), 64, Vector3(0, 0.06, TEXT_Z))
	title.modulate = title_color(reason)
	title.modulate.a = 0.0
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.width = TITLE_WIDTH_PX
	hint = _make_label("EndHint", hint_text(ev), 44, Vector3(0, -0.2, TEXT_Z))
	hint.modulate = AssetMaterials.layer("label_dim", 0.0)


func _make_label(label_name: String, text: String, size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = label_name
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0008
	l.no_depth_test = true
	l.render_priority = 101
	l.position = pos
	Label3DSharp.apply(l)
	add_child(l)
	return l


## Запустить затемнение: завеса — за FADE_SEC, надписи — следом.
func start() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_mat, "albedo_color:a", 1.0, FADE_SEC)
	tw.tween_property(title, "modulate:a", 1.0, FADE_SEC - TEXT_DELAY_SEC).set_delay(TEXT_DELAY_SEC)
	tw.tween_property(hint, "modulate:a", 1.0, FADE_SEC - TEXT_DELAY_SEC).set_delay(TEXT_DELAY_SEC)


func veil_alpha() -> float:
	return _mat.albedo_color.a

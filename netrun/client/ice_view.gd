class_name IceView
extends Node3D
## ICE в узле: модель из ассетов (ice/soft_ice.glb, ice/black_ice.glb) со скелетом и клипами. Клип выбирается по состоянию ICE из
## снимка сервера (WorldMsg.STATE, поле s — IceBrain.State; b = 1 — Black ICE): клиент server/ не читает, номера состояний
## продублированы ниже. Позу и поворот двигает сцена по буферу состояний (RemoteTracks).
##
## Soft ICE (клипы idle, patrol): патруль — patrol; подозрение — стоит и смотрит (idle); поиск идёт к последней точке (patrol, быстрее).
## Black ICE (idle, hunt, catch): парит (idle), пока не вышел на цель; поиск и охота — hunt; охота вплотную к игроку — catch.
## «Что изменилось» читается и без цвета: над головой знак (AlertAnchor) — «?» подозревает, «!» ищет, «!!» охотится.

const STATE_PATROL := 0
const STATE_SUSPICIOUS := 1
const STATE_SEARCH := 2
const STATE_HUNT := 3
## Охота вплотную: ближе этого до игрока Black ICE показывает catch (сервер ловит с 1,5 м — IceBrain catch_range).
const CATCH_NEAR := 2.0
const SEARCH_SPEED := 1.6
const ALERT_TEXT := ["", "?", "!", "!!"]
const ALERT_COLOR := [Color.WHITE, Color(1.0, 0.62, 0.26), Color(1.0, 0.35, 0.31), Color(1.0, 0.35, 0.31)]
## Глаз тактового режима (time-and-movement.md 3.4): светящаяся точка спереди у головы; цвет — по состоянию TickIce (Патруль, Взгляд, Проверка, Поиск):
## белый, жёлтый, оранжевый, красный — те же цвета, что у света зрения на полу.
const EYE_COLOR := [Color(1.0, 1.0, 1.0), Color(1.0, 0.86, 0.25), Color(1.0, 0.55, 0.15), Color(1.0, 0.2, 0.18)]
const EYE_RADIUS := 0.09
## Положение глаза: спереди (−Z — куда смотрит ICE) на высоте головы; у Black ICE выше и дальше (модель ×2).
const EYE_POS_SOFT := Vector3(0.0, 1.7, -0.45)
const EYE_POS_BLACK := Vector3(0.0, 2.3, -0.6)

var black := false
var asset := ""
var state := STATE_PATROL
var near_target := false

var _model: Node3D
var _player: AnimationPlayer
var _alert: Label3D
var _clip := ""
var _eye: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _eye_state := -1


func _init(is_black: bool = false) -> void:
	black = is_black
	asset = NodeAssets.BLACK_ICE if black else NodeAssets.SOFT_ICE
	_model = NodeAssets.instance(asset)
	_model.name = "Model"
	add_child(_model)
	_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_alert = Label3D.new()
	_alert.name = "Alert"
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.font_size = 96
	_alert.pixel_size = 0.006
	_alert.outline_size = 12
	var anchor := _model.find_child("AlertAnchor", true, false) as Node3D  # метка модели (внутри корневого узла клипов Rig): над головой
	_alert.position = anchor.position + Vector3(0, 0.25, 0) if anchor != null else Vector3(0, 2.4, 0)
	_alert.visible = false
	add_child(_alert)
	_choose(false)


func _ready() -> void:
	_start_clip()


## Состояние ICE с сервера; near — рядом с игроком (для catch). Повтор того же состояния ничего не перезапускает.
func apply_state(new_state: int, near: bool = false) -> void:
	state = new_state
	near_target = near
	_choose(true)


## Глаз по состоянию TickIce (0..3, поле st снимка): создаётся при первом вызове, дальше только красит. Зовёт сцена только в тактовом режиме.
func set_eye_state(st: int) -> void:
	var s := clampi(st, 0, EYE_COLOR.size() - 1)
	if _eye == null:
		var mesh := SphereMesh.new()
		mesh.radius = EYE_RADIUS
		mesh.height = EYE_RADIUS * 2.0
		mesh.radial_segments = 12
		mesh.rings = 6
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = _eye_mat
		_eye = MeshInstance3D.new()
		_eye.name = "Eye"
		_eye.mesh = mesh
		_eye.position = EYE_POS_BLACK if black else EYE_POS_SOFT
		_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_eye)
	_eye_state = s
	_eye_mat.albedo_color = EYE_COLOR[s]


## Состояние глаза (-1 — не создан, realtime) и его цвет — для тестов.
func eye_state() -> int:
	return _eye_state


func eye_color() -> Color:
	return _eye_mat.albedo_color if _eye_mat != null else Color(0, 0, 0, 0)


## Клип, который сейчас выбран (играет, когда ICE в дереве).
func current_clip() -> String:
	return _clip


func alert_visible() -> bool:
	return _alert.visible


func _choose(play: bool) -> void:
	var clip := clip_for(black, state, near_target)
	var s := clampi(state, 0, ALERT_TEXT.size() - 1)
	_alert.visible = s >= STATE_SUSPICIOUS
	_alert.text = ALERT_TEXT[s]
	_alert.modulate = ALERT_COLOR[s]
	if _player != null:
		_player.speed_scale = speed_for(black, state)
	if clip != _clip:
		_clip = clip
		if play:
			_start_clip()


func _start_clip() -> void:
	if _player != null and is_inside_tree() and _player.has_animation(_clip) and _player.current_animation != _clip:
		_player.play(_clip, 0.2)


static func clip_for(is_black: bool, ice_state: int, near: bool) -> String:
	if is_black:
		if ice_state == STATE_HUNT:
			return "catch" if near else "hunt"
		return "hunt" if ice_state == STATE_SEARCH else "idle"
	return "idle" if ice_state == STATE_SUSPICIOUS else "patrol"


static func speed_for(is_black: bool, ice_state: int) -> float:
	return SEARCH_SPEED if not is_black and ice_state == STATE_SEARCH else 1.0

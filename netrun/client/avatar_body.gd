class_name AvatarBody
extends Node3D
## Тело другого нетраннера: светящаяся голова (HeadCloud) и две руки (HandView, чужие — цвет игрока, с проверкой глубины). Корпуса нет.
## Поза приходит как AvatarPose (положения от точки пола аватара, в осях мира): apply_pose ставит голову и рамки ладоней, дальше узел сглаживает движение
## (кадры приходят ~20 раз/с). Узел top_level: поворот AvatarView (лицо по ходу) на тело не действует — поза уже в осях мира; позицию пола ставит AvatarView.
## Нет позы (ещё не пришла или давно не обновлялась) — тело скрыто; AvatarView тогда рисует прежнюю модель runner.glb.

## Сглаживание положения и поворота, 1/с (чем больше — тем резче следует за присланной позой).
const SMOOTH := 22.0
## Нет новой позы дольше этого — тело скрыть (пакеты потеряны или клиент завис).
const STALE_SEC := 1.5

var head_cloud: HeadCloud
var left_hand: HandView
var right_hand: HandView
var color := HandView.COLOR_HAND

var _target: AvatarPose
var _head := Transform3D.IDENTITY
var _frames: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _shown: Array[bool] = [false, false]
var _age := 0.0
var _fresh := true  # после первой позы или пропуска положение берётся сразу, без плавного «подлёта»


func _init() -> void:
	name = "AvatarBody"
	top_level = true
	head_cloud = HeadCloud.new()
	add_child(head_cloud)
	left_hand = _make_hand(true)
	right_hand = _make_hand(false)
	add_child(left_hand)
	add_child(right_hand)
	head_cloud.visible = false


func _make_hand(is_left: bool) -> HandView:
	var h := HandView.new(is_left)
	h.name = "RemoteLeftHand" if is_left else "RemoteRightHand"
	h.set_occluded(true)
	var side := AvatarPose.LEFT if is_left else AvatarPose.RIGHT
	h.pose_source = func() -> PackedVector3Array:
		if not _shown[side] or _target == null:
			return PackedVector3Array()
		return h.pose_at(_frames[side], _target.trigger[side], _target.hold[side])
	return h


## Цвет игрока (AvatarView.color_for): голова и обе руки.
func set_color(c: Color) -> void:
	color = c
	head_cloud.set_tint(c)
	left_hand.set_tint(c)
	right_hand.set_tint(c)


## Новая поза (null — позы нет). Само сглаживание идёт в _process.
func apply_pose(pose: AvatarPose) -> void:
	_target = pose
	_age = 0.0
	if pose == null:
		_fresh = true
	elif _fresh:
		_snap()
		_fresh = false


func has_pose() -> bool:
	return _target != null and _age < STALE_SEC


func _process(delta: float) -> void:
	_age += delta
	var live := has_pose()
	head_cloud.visible = live
	if not live:
		_shown = [false, false]
		_fresh = true
		return
	var k := 1.0 - exp(-SMOOTH * delta)
	_head = _head.interpolate_with(_target.head, k)
	head_cloud.transform = _head
	for side in 2:
		var was: bool = _shown[side]
		_shown[side] = _target.has_hand[side]
		if _shown[side]:
			_frames[side] = _frames[side].interpolate_with(_target.palm[side], k) if was else _target.palm[side]


func _snap() -> void:
	_head = _target.head
	head_cloud.transform = _head
	for side in 2:
		_frames[side] = _target.palm[side]
		_shown[side] = _target.has_hand[side]
	left_hand.update_hand()
	right_hand.update_hand()

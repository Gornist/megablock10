class_name AvatarPose
extends RefCounted
## Поза «тела» нетраннера для других игроков: голова и две кисти (корпуса нет — аватар это светящаяся голова и руки, client/avatar_body.gd).
## Все положения — в осях узла (мира), от точки пола аватара (x, 0, z), которую сервер уже шлёт в `av`: так поза не зависит от того, где игрок стоит,
## и телепорт её не ломает. Кисть — рамка ладони без масштаба (HandView.palm_frame) и два числа сгиба: курок и хват (пальцы раскладывает приёмник,
## HandSkeleton.pose). Чистые данные и кодек, без узлов: считается и проверяется в тестах (tests/avatar_body_test.gd).
##
## Формат на проводе (поле `b` записи аватара или отдельное сообщение — решает сеть): {h: [px, py, pz, qx, qy, qz, qw], l: [..7.., trigger, grip], r: [..9..]};
## нет руки (контроллер потерян) — нет и ключа. Положения с точностью 1 мм, кватернион 0,001, сгиб 0,01: ≈ 90–120 байт JSON на аватара.

const LEFT := 0
const RIGHT := 1
## Дальше этого от точки пола запись считаем мусором (рука над головой — 2,5 м, с запасом).
const REACH_LIMIT := 4.0

var head := Transform3D.IDENTITY
## Рамка ладони каждой руки и признак «рука есть».
var palm: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var has_hand: Array[bool] = [false, false]
var trigger: Array[float] = [0.0, 0.0]
var hold: Array[float] = [0.0, 0.0]


## Поза из мировых рамок: head_world — камера в осях мира, floor_pt — точка пола аватара (та же (x, 0, z), что клиент шлёт в `pos`),
## hands — по стороне (LEFT, RIGHT) либо null (контроллера нет — руку не добавляем), либо {frame: Transform3D в осях мира, trigger, hold}.
static func from_world(head_world: Transform3D, floor_pt: Vector3, hands: Array) -> AvatarPose:
	var pose := AvatarPose.new()
	pose.head = Transform3D(head_world.basis.orthonormalized(), head_world.origin - floor_pt)
	for side in [LEFT, RIGHT]:
		var h: Variant = hands[side] if side < hands.size() else null
		if h is Dictionary:
			var f: Transform3D = h["frame"]
			pose.set_hand(side, Transform3D(f.basis.orthonormalized(), f.origin - floor_pt), float(h["trigger"]), float(h["hold"]))
	return pose


func set_hand(side: int, frame: Transform3D, trig: float, grip_hold: float) -> void:
	palm[side] = frame
	has_hand[side] = true
	trigger[side] = clampf(trig, 0.0, 1.0)
	hold[side] = clampf(grip_hold, 0.0, 1.0)


func encode() -> Dictionary:
	var out := {"h": _tf(head)}
	if has_hand[LEFT]:
		out["l"] = _tf(palm[LEFT]) + [snappedf(trigger[LEFT], 0.01), snappedf(hold[LEFT], 0.01)]
	if has_hand[RIGHT]:
		out["r"] = _tf(palm[RIGHT]) + [snappedf(trigger[RIGHT], 0.01), snappedf(hold[RIGHT], 0.01)]
	return out


## Из присланного словаря; мусор (нет головы, не числа, далеко, нулевой кватернион) — null. Битая кисть просто выпадает, голова остаётся.
static func decode(v: Variant) -> AvatarPose:
	if not (v is Dictionary):
		return null
	var h: Variant = _untf(v.get("h"), 7)
	if h == null:
		return null
	var pose := AvatarPose.new()
	pose.head = h
	for side in [LEFT, RIGHT]:
		var a: Variant = v.get("l" if side == LEFT else "r")
		var f: Variant = _untf(a, 9)
		if f != null:
			pose.set_hand(side, f, float(a[7]), float(a[8]))
	return pose


static func _tf(t: Transform3D) -> Array:
	var q := Quaternion(t.basis.orthonormalized())
	return [snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001),
		snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)]


## Массив ровно из n чисел (первые семь — положение и кватернион) -> Transform3D; иначе null.
static func _untf(a: Variant, n: int) -> Variant:
	if not (a is Array) or a.size() != n:
		return null
	for x in a:
		if not (x is float or x is int) or not is_finite(float(x)):
			return null
	var p := Vector3(float(a[0]), float(a[1]), float(a[2]))
	var q := Quaternion(float(a[3]), float(a[4]), float(a[5]), float(a[6]))
	if p.length() > REACH_LIMIT or q.length() < 0.5:
		return null
	return Transform3D(Basis(q.normalized()), p)

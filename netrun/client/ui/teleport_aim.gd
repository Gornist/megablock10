class_name TeleportAim
extends Node3D
## Прицел телепорта: дуга точек от руки (в плоской сборке — от взгляда) до рамки клетки 1×1 м на полу в точке посадки.
## Три вида клетки (NodeGrid.pick): "hop" — зелёная рамка (можно; красная, пока идёт перезарядка — на ней растёт диск, сколько
## перезарядки прошло), "wait" — нейтральная рамка своей клетки (остаться на месте), "denied" — серая рамка и над ней короткая
## причина («ЗАНЯТО», «ЗА УКРЫТИЕМ», «ДАЛЬНО»). Всё в мировых координатах (top_level), дёшево для Mobile: MultiMesh из 14 кубиков,
## четыре узкие полосы рамки и тонкий диск без теней.

const DOTS := 14
const DOT_SIZE := 0.035
## Рамка клетки: сторона — NodeGrid.CELL_M (внутрь на FRAME_INSET, чтобы рамки соседних клеток не слипались), ширина полосы.
const FRAME_INSET := 0.02
const FRAME_W := 0.04
const FRAME_H := 0.012
const DISC_RADIUS := 0.27
const OK_COLOR := Color(0.25, 1.0, 0.45)
const NO_COLOR := Color(1.0, 0.25, 0.2)
const WAIT_COLOR := Color(0.75, 0.9, 1.0)
const DENIED_COLOR := Color(0.5, 0.5, 0.52)
## Рамка чуть выше пола, чтобы не мерцать в одной плоскости с ним.
const RING_LIFT := 0.02
const LABEL_LIFT := 0.45   ## метка причины над полом, м

const ARROW_SIZE := Vector3(0.26, 0.3, 0.012)
const ARROW_OFFSET := 0.62   ## от центра клетки до центра стрелки вдоль взгляда после прыжка

## Короткие причины отказа (NodeGrid.pick → reason).
const REASON_TEXT := {"occupied": "ЗАНЯТО", "room": "СТЕНА", "blocked": "ЗА УКРЫТИЕМ", "range": "ДАЛЬНО"}

var _ok := true
var _kind := "hop"
var _reason := ""
var _arrow: MeshInstance3D
var _dots: MultiMeshInstance3D
var _frame: Node3D
var _label: Label3D
var _disc: MeshInstance3D
var _mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D


func _init() -> void:
	name = "TeleportAim"
	top_level = true
	visible = false
	_mat = _unshaded(OK_COLOR)
	_disc_mat = _unshaded(NO_COLOR)
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.albedo_color.a = 0.45
	var dot := BoxMesh.new()
	dot.size = Vector3.ONE * DOT_SIZE
	dot.material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = DOTS
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = mm
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)
	# Рамка клетки: четыре узкие полосы по краям квадрата со стороной CELL_M.
	_frame = Node3D.new()
	_frame.name = "CellFrame"
	add_child(_frame)
	var side := frame_side()
	var half := side * 0.5 - FRAME_W * 0.5
	for strip in [[Vector3(side, FRAME_H, FRAME_W), Vector3(0.0, 0.0, -half)], [Vector3(side, FRAME_H, FRAME_W), Vector3(0.0, 0.0, half)],
			[Vector3(FRAME_W, FRAME_H, side), Vector3(-half, 0.0, 0.0)], [Vector3(FRAME_W, FRAME_H, side), Vector3(half, 0.0, 0.0)]]:
		var box := BoxMesh.new()
		box.size = strip[0]
		box.material = _mat
		var m := MeshInstance3D.new()
		m.mesh = box
		m.position = strip[1]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame.add_child(m)
	var cyl := CylinderMesh.new()
	cyl.top_radius = DISC_RADIUS
	cyl.bottom_radius = DISC_RADIUS
	cyl.height = 0.01
	cyl.radial_segments = 24
	cyl.rings = 1
	cyl.material = _disc_mat
	_disc = MeshInstance3D.new()
	_disc.mesh = cyl
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	# Причина отказа: метка над серой рамкой, всегда лицом к игроку.
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.shaded = false
	_label.no_depth_test = true
	_label.pixel_size = 0.004
	_label.font_size = 56
	_label.outline_size = 12
	_label.modulate = Color(0.85, 0.85, 0.88)
	_label.visible = false
	add_child(_label)
	# Стрелка «куда смотреть после прыжка»: плоский треугольник на полу, остриём вдоль взгляда (призма лежит остриём на -Z).
	var tri := PrismMesh.new()
	tri.size = ARROW_SIZE
	tri.material = _mat
	_arrow = MeshInstance3D.new()
	_arrow.mesh = tri
	_arrow.rotation.x = -PI / 2.0
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.visible = false
	add_child(_arrow)


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## Показать прицел: дуга от start к центру клетки target; ok — можно ли прыгнуть сейчас (hop и перезарядка прошла); charge — доля
## готовности перезарядки 0…1 (меньше 1 — на рамке растёт диск); kind — "hop" / "wait" / "denied" (NodeGrid.pick), reason — причина
## отказа для серой рамки. Без kind (старые вызовы) вид клетки берётся по ok.
func show_at(start: Vector3, target: Vector3, ok: bool, charge: float = 1.0, kind: String = "", reason: String = "") -> void:
	_ok = ok
	_kind = kind if not kind.is_empty() else "hop"
	_reason = reason
	var c := OK_COLOR if ok else NO_COLOR
	if _kind == "wait":
		c = WAIT_COLOR
	elif _kind == "denied":
		c = DENIED_COLOR
	_mat.albedo_color = c
	_disc_mat.albedo_color = Color(NO_COLOR.r, NO_COLOR.g, NO_COLOR.b, 0.45)
	var pts := RigMath.arc_points(start, target + Vector3(0.0, RING_LIFT, 0.0), DOTS)
	var mm := _dots.multimesh
	for i in DOTS:
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var frame_pos := target + Vector3(0.0, RING_LIFT, 0.0)
	_frame.position = frame_pos
	_disc.position = frame_pos + Vector3(0.0, 0.005, 0.0)
	var r := clampf(charge, 0.0, 1.0)
	_disc.visible = _kind == "hop" and r < 1.0
	_disc.scale = Vector3(maxf(r, 0.001), 1.0, maxf(r, 0.001))
	_label.visible = _kind == "denied"
	_label.text = REASON_TEXT.get(reason, "НЕЛЬЗЯ")
	_label.position = target + Vector3(0.0, LABEL_LIFT, 0.0)
	visible = true


## Стрелка над рамкой: куда смотреть после прыжка (горизонтальный вектор, нулевой — спрятать). Зовут после show_at.
func set_heading(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	_arrow.visible = flat.length() >= 0.001
	if not _arrow.visible:
		return
	flat = flat.normalized()
	_arrow.position = _frame.position + flat * ARROW_OFFSET + Vector3(0.0, 0.004, 0.0)
	_arrow.basis = Basis(Vector3.UP, atan2(-flat.x, -flat.z)) * Basis(Vector3.RIGHT, -PI / 2.0)


func arrow_visible() -> bool:
	return _arrow.visible


## Куда смотрит остриё стрелки (единичный вектор; остриё призмы — её +Y) — для тестов.
func arrow_heading() -> Vector3:
	return _arrow.global_basis * Vector3.UP


func hide_aim() -> void:
	visible = false


func is_ok() -> bool:
	return _ok


## Вид клетки под прицелом ("hop" / "wait" / "denied") и причина отказа — для тестов и журнала.
func kind() -> String:
	return _kind


func reason() -> String:
	return _reason


## Рамка клетки на полу показана (прицел виден).
func frame_visible() -> bool:
	return visible and _frame.visible


## Сторона рамки по внешнему краю, м — по NodeGrid.CELL_M.
static func frame_side() -> float:
	return NodeGrid.CELL_M - FRAME_INSET * 2.0


func frame_center() -> Vector3:
	return _frame.position


func frame_color() -> Color:
	return _mat.albedo_color


func label_visible() -> bool:
	return _label.visible


func label_text() -> String:
	return _label.text

class_name TeleportAim
extends Node3D
## Прицел телепорта: дуга точек от руки (в плоской сборке — от взгляда) до кольца на полу в точке посадки. Зелёное — можно,
## красное — нельзя (цель в себя, тоннель) или идёт перезарядка; на красном кольце растёт диск — сколько перезарядки прошло.
## Всё в мировых координатах (top_level), дёшево для Mobile: MultiMesh из 14 кубиков, тор и тонкий диск без теней.

const DOTS := 14
const DOT_SIZE := 0.035
const RING_INNER := 0.27
const RING_OUTER := 0.33
const OK_COLOR := Color(0.25, 1.0, 0.45)
const NO_COLOR := Color(1.0, 0.25, 0.2)
## Кольцо чуть выше пола, чтобы не мерцать в одной плоскости с ним.
const RING_LIFT := 0.02

var _ok := true
var _dots: MultiMeshInstance3D
var _ring: MeshInstance3D
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
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	torus.rings = 24
	torus.ring_segments = 6
	torus.material = _mat
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var cyl := CylinderMesh.new()
	cyl.top_radius = RING_INNER
	cyl.bottom_radius = RING_INNER
	cyl.height = 0.01
	cyl.radial_segments = 24
	cyl.rings = 1
	cyl.material = _disc_mat
	_disc = MeshInstance3D.new()
	_disc.mesh = cyl
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## Показать прицел: дуга от start к target; ok — цвет; charge — доля готовности перезарядки 0…1 (меньше 1 — на кольце растёт диск).
func show_at(start: Vector3, target: Vector3, ok: bool, charge: float = 1.0) -> void:
	_ok = ok
	var c := OK_COLOR if ok else NO_COLOR
	_mat.albedo_color = c
	_disc_mat.albedo_color = Color(NO_COLOR.r, NO_COLOR.g, NO_COLOR.b, 0.45)
	var pts := RigMath.arc_points(start, target + Vector3(0.0, RING_LIFT, 0.0), DOTS)
	var mm := _dots.multimesh
	for i in DOTS:
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var ring_pos := target + Vector3(0.0, RING_LIFT, 0.0)
	_ring.position = ring_pos
	_disc.position = ring_pos + Vector3(0.0, 0.005, 0.0)
	var r := clampf(charge, 0.0, 1.0)
	_disc.visible = r < 1.0
	_disc.scale = Vector3(maxf(r, 0.001), 1.0, maxf(r, 0.001))
	visible = true


func hide_aim() -> void:
	visible = false


func is_ok() -> bool:
	return _ok

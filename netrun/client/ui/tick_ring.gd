class_name TickRing
extends Node3D
## Кольцо-таймер окна такта на руке (рядом с индикатором trace): заполняется по часовой от tk.at до tk.at + tk.win, на такте вспыхивает и
## опустошается. Данные берёт у RemoteTracks сам; доля окна и смена такта — TickBeat. В realtime (нет tk) кольцо скрыто.

const SEGMENTS := 40
const R_OUT := 0.022
const R_IN := 0.015
## Вспышка на такте: столько секунд гаснет, и во сколько раз кольцо ярче в её начале.
const FLASH_SEC := 0.25
const FLASH_GAIN := 2.0
## Цвета — слои палитры клиента (AssetMaterials.layer): tick_track (фон), tick_fill (заполнено), tick_warn (последняя треть окна — сейчас ICE сходит).
const WARN_FROM := 0.7

var fraction := 0.0
var flash_left := 0.0
var beat := TickBeat.new()

var _remote: RemoteTracks
var _mesh := ImmediateMesh.new()
var _mi: MeshInstance3D
var _drawn := -1.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_mi = MeshInstance3D.new()
	_mi.name = "Ring"
	_mi.mesh = _mesh
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	visible = false


func bind(remote: RemoteTracks) -> void:
	_remote = remote


func _process(delta: float) -> void:
	if _remote != null:
		poll(delta, Time.get_ticks_msec() / 1000.0)


## Один кадр: доля окна и вспышка по снимку RemoteTracks (в тестах — вручную).
func poll(delta: float, local_now: float) -> void:
	var tk := _remote.tick_info()
	if tk.is_empty():
		visible = false
		beat.reset()
		return
	visible = true
	if beat.observe(tk):
		flash_left = FLASH_SEC
	apply(TickBeat.window_fraction(tk, _remote.clock.server_time(local_now)), delta)


## Выставить долю окна 0..1 и продвинуть вспышку на delta.
func apply(frac: float, delta: float) -> void:
	fraction = clampf(frac, 0.0, 1.0)
	if flash_left > 0.0:
		flash_left = maxf(flash_left - delta, 0.0)
	_redraw()


## Яркость кольца сейчас: 1, на вспышке — до FLASH_GAIN.
func brightness() -> float:
	return 1.0 + (FLASH_GAIN - 1.0) * (flash_left / FLASH_SEC)


## Сколько сегментов кольца залито (для теста; 0..SEGMENTS).
func filled_segments() -> int:
	return int(round(fraction * SEGMENTS))


func fill_color() -> Color:
	return AssetMaterials.layer("tick_warn" if fraction >= WARN_FROM else "tick_fill")


func _redraw() -> void:
	var key := fraction + flash_left * 10.0
	if _mi == null or is_equal_approx(key, _drawn):
		return
	_drawn = key
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var filled := filled_segments()
	var gain := brightness()
	var fill := fill_color()
	fill = Color(minf(fill.r * gain, 1.0), minf(fill.g * gain, 1.0), minf(fill.b * gain, 1.0), fill.a)
	var track := AssetMaterials.layer("tick_track")
	for i in SEGMENTS:
		var col := fill if i < filled else track
		var a0 := TAU * float(i) / SEGMENTS
		var a1 := TAU * float(i + 1) / SEGMENTS
		# Отсчёт от верха по часовой стрелке (глядя на кольцо).
		var o0 := Vector3(sin(a0) * R_OUT, cos(a0) * R_OUT, 0.0)
		var o1 := Vector3(sin(a1) * R_OUT, cos(a1) * R_OUT, 0.0)
		var i0 := Vector3(sin(a0) * R_IN, cos(a0) * R_IN, 0.0)
		var i1 := Vector3(sin(a1) * R_IN, cos(a1) * R_IN, 0.0)
		for v: Vector3 in [o0, o1, i0, o1, i1, i0]:
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(v)
	_mesh.surface_end()

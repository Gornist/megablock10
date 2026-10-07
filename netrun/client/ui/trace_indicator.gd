class_name TraceIndicator
extends Node3D
## Индикатор trace в мире: полоса (заливка меняет длину и цвет по уровню) и надпись с уровнем и значением.

const BAR_W := 0.2
const BAR_H := 0.02

var _fill: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D


func _ready() -> void:
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(BAR_W, BAR_H, 0.002)
	bm.material = _unshaded(Color(0.05, 0.07, 0.1))
	back.mesh = bm
	add_child(back)
	_fill = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(BAR_W, BAR_H, 0.002)
	_mat = _unshaded(HudLogic.level_color(0))
	fm.material = _mat
	_fill.mesh = fm
	_fill.position.z = 0.002
	add_child(_fill)
	_label = Label3D.new()
	_label.pixel_size = 0.0006
	_label.font_size = 36
	_label.position = Vector3(0, 0.025, 0.002)
	_label.no_depth_test = true
	Label3DSharp.apply(_label)
	add_child(_label)
	set_trace(0.0)


func set_trace(value: float, thresholds: Dictionary = HudLogic.DEFAULT_THRESHOLDS) -> void:
	var level := HudLogic.level_from_value(value, thresholds)
	var f := HudLogic.trace_fraction(value, float(thresholds.get("max", 100.0)))
	_fill.scale.x = maxf(f, 0.001)
	_fill.position.x = -BAR_W * 0.5 * (1.0 - f)
	_mat.albedo_color = HudLogic.level_color(level)
	_label.text = HudLogic.trace_text(value, level)
	_label.modulate = HudLogic.level_color(level)


func shown_text() -> String:
	return _label.text


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	return m

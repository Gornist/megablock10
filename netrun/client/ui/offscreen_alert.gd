class_name OffscreenAlert
extends Node3D
## Предупреждение о событии вне поля зрения: метка на краю обзора в сторону события и короткий звук-заглушка.
## Узел — ребёнок камеры. Событие: точка в мире. Метка исчезает, когда точка снова в поле зрения.

const DIST := 0.8  # расстояние метки от глаз
const EDGE_Y := 0.28
const EDGE_X := 0.4
const BEEP_HZ := 660.0
const BEEP_SEC := 0.12

var camera: Camera3D
var aspect := 16.0 / 9.0
var _marker: Label3D
var _player: AudioStreamPlayer3D
var _event_point := Vector3.ZERO
var _active := false
var beeps := 0


func _ready() -> void:
	_marker = Label3D.new()
	_marker.text = "!"
	_marker.font_size = 72
	_marker.pixel_size = 0.0008
	_marker.modulate = Color(1.0, 0.2, 0.2)
	_marker.no_depth_test = true
	_marker.visible = false
	add_child(_marker)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.3
	_player = AudioStreamPlayer3D.new()
	_player.stream = gen
	add_child(_player)


## Сообщает о событии в точке мира; звук играет, только если точка не видна.
func alert(point: Vector3) -> void:
	_event_point = point
	_active = true
	if camera != null and not _visible(point):
		_beep()


func clear() -> void:
	_active = false
	_marker.visible = false


func is_marker_shown() -> bool:
	return _marker.visible


func _visible(point: Vector3) -> bool:
	return HudLogic.is_point_visible(camera.global_transform, point, camera.fov, aspect)


func _process(_delta: float) -> void:
	if not _active or camera == null:
		return
	if _visible(_event_point):
		_marker.visible = false
		return
	var dir := HudLogic.edge_direction(camera.global_transform, _event_point)
	# На эллипс по краю обзора.
	_marker.position = Vector3(dir.x * EDGE_X, dir.y * EDGE_Y, -DIST)
	_marker.visible = true


func _beep() -> void:
	beeps += 1
	if not _player.playing:
		_player.play()
	var pb := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var rate := 22050.0
	var n := mini(int(rate * BEEP_SEC), pb.get_frames_available())
	for i in n:
		var s := sin(TAU * BEEP_HZ * i / rate) * 0.3
		pb.push_frame(Vector2(s, s))

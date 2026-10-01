extends Node
## Плоская отладочная сборка: сцена прототипа и тот же XR-риг, управляемый клавиатурой и мышью.
## WASD — ход, Q/E — поворот рывками, ПКМ+мышь — осмотр, R — центровка, Esc 3 с — экстренное отключение, F / ЛКМ — взять объект (просит сервер).
## Звук (только отладочная плоская сборка): 1–4 — уровень trace (NORMAL…LOCKDOWN), 5 — фон выкл. (FLATLINE),
## 6/7/8 — состояние тестового ICE (PATROL/SUSPICIOUS/SEARCH). ICE стоит в точке ICE_POS, подойдите — громче.

const ICE_POS := Vector3(0, 1.2, -6)

var trace_audio: TraceAudio
var ice_audio: IceAudio


func start(args: PackedStringArray) -> void:
	var p := ProtoClient.new()
	p.name = "Proto"
	add_child(p)
	p.start(args, "flat", false)
	if p.net != null:
		p.scene.rig.exit_requested.connect(p.net.request_exit)
	if OS.is_debug_build():
		trace_audio = TraceAudio.new()
		add_child(trace_audio)
		ice_audio = IceAudio.new()
		ice_audio.position = ICE_POS
		p.scene.add_child(ice_audio)
	print("[netrun-flat] сцена прототипа, риг управляется мышью и клавиатурой")


func _unhandled_key_input(event: InputEvent) -> void:
	if trace_audio == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_5:
		trace_audio.set_level(k - KEY_1)
		print("[netrun-flat] trace level=%d" % (k - KEY_1))
	elif k >= KEY_6 and k <= KEY_8:
		ice_audio.set_state(k - KEY_6)
		print("[netrun-flat] ice state=%d" % (k - KEY_6))

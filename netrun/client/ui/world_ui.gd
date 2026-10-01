class_name WorldUI
extends Node3D
## Сборка интерфейса в мире: дека (рука / низ-лево поля зрения), индикатор trace, метка события вне обзора.
## В VR крепится к левому контроллеру, в плоской сборке — к камере в левом нижнем углу обзора.

var rig: XRRig
var deck: DeckPanel
var trace: TraceIndicator
var alert: OffscreenAlert
var _anchor: Node3D


func attach(r: XRRig) -> void:
	rig = r
	_anchor = Node3D.new()
	_anchor.name = "HudAnchor"
	add_child(_anchor)
	deck = DeckPanel.new()
	deck.position = Vector3(0, 0, 0)
	_anchor.add_child(deck)
	trace = TraceIndicator.new()
	trace.position = Vector3(0, 0.14, 0)
	_anchor.add_child(trace)
	alert = OffscreenAlert.new()
	alert.camera = rig.camera
	rig.camera.add_child(alert)
	_place()


func _process(_delta: float) -> void:
	_place()


## Руку в VR берём из левого контроллера; плоская сборка — привязка к камере (низ-лево).
func _place() -> void:
	if rig == null:
		return
	var want: Node3D = rig.left_hand if rig.xr_active else rig.camera
	if _anchor.get_parent() != want:
		if _anchor.get_parent() != null:
			_anchor.get_parent().remove_child(_anchor)
		want.add_child(_anchor)
		if rig.xr_active:
			_anchor.transform = Transform3D(Basis.from_euler(Vector3(-PI / 3, 0, 0)), Vector3(0, 0.05, -0.1))
		else:
			_anchor.transform = Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(15), 0)), Vector3(-0.3, -0.2, -0.65))

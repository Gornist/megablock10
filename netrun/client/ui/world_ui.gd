class_name WorldUI
extends Node3D
## Сборка интерфейса в мире: дека (рука / низ-лево поля зрения), индикатор trace, метка события вне обзора.
## В VR крепится к запястью левой руки (якорь HandView.wrist_anchor: на тыле запястья, ближе к локтю, чтобы не закрывать руку), в плоской сборке — к камере
## в левом нижнем углу обзора.

## Дека и индикатор trace на запястье: деку уменьшают (на предплечье шириной 6–7 см она иначе свисает), trace — ниже деки, к локтю: на 4,5 см ниже
## её нижнего края (высота деки с вкладками — DeckPanel.PANEL_HEIGHT_M, после уменьшения 18 см).
const WRIST_DECK_SCALE := 0.75
## Дека на запястье повёрнута в своей плоскости на 90° против часовой (глядя на панель): длинная сторона идёт вдоль предплечья
## (решение владельца, 4 октября 2026, по Pico 4). Плюс — против часовой с точки зрения смотрящего на панель.
const WRIST_DECK_ROLL_DEG := 90.0
## Зазор между запястьем и ближним к кисти краем деки, м: дека лежит на предплечье и не заходит на кисть.
const WRIST_DECK_GAP := 0.02
## Длина деки вдоль предплечья после поворота (её ширина), м.
const WRIST_DECK_LENGTH_M := DeckPanel.PANEL_WIDTH_M * WRIST_DECK_SCALE
## Центр деки в системе якоря (якорь — на WRIST_ANCHOR_ELBOW от запястья к локтю; Y якоря — к пальцам): ближний к кисти край деки — в WRIST_DECK_GAP от запястья.
const WRIST_DECK_POS := Vector3(0, -(WRIST_DECK_LENGTH_M * 0.5 + WRIST_DECK_GAP - HandView.WRIST_ANCHOR_ELBOW), 0)
## Trace — за дальним (к локтю) краем деки.
const WRIST_TRACE_POS := Vector3(0, WRIST_DECK_POS.y - (WRIST_DECK_LENGTH_M * 0.5 + 0.045), 0)
const FLAT_TRACE_POS := Vector3(0, 0.14, 0)

var rig: XRRig
var deck: DeckPanel
var trace: TraceIndicator
var alert: OffscreenAlert
## Вкладки ЧАТ и ЗВОНКИ деки: указатель правого контроллера (мышь в плоской сборке) нажимает деку; отклик — вибрация и звук на сообщения и
## звонки; связь с телефоном (пока фиктивная) — null, и тогда вкладок нет, указатель молчит. Положение и масштаб деки на руке — только здесь.
var pointer: DeckPointer
## Панель взлома хранилища (К3): стоит в мире, появляется у хранилища; свой указатель (второй DeckPointer) нажимает её тем же лучом и курком.
var breach_panel: BreachPanel
var breach_pointer: DeckPointer
var feedback: DeckFeedback
var phone: PhoneLink
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
	trace.position = FLAT_TRACE_POS
	_anchor.add_child(trace)
	alert = OffscreenAlert.new()
	alert.camera = rig.camera
	rig.camera.add_child(alert)
	feedback = DeckFeedback.new()
	feedback.name = "DeckFeedback"
	_anchor.add_child(feedback)   # звук идёт из места деки
	pointer = DeckPointer.new()
	add_child(pointer)
	pointer.setup(rig, deck)
	pointer.clicked.connect(func(): feedback.pulse("right", 0.25, 0.02))   # лёгкий отклик правой руки на нажатие
	breach_panel = BreachPanel.new()
	breach_panel.name = "BreachPanel"
	add_child(breach_panel)   # в мире, а не на руке: WorldUI сидит в корне сцены и сам не двигается
	breach_pointer = DeckPointer.new()
	add_child(breach_pointer)
	breach_pointer.setup(rig, breach_panel)
	breach_pointer.clicked.connect(func(): feedback.pulse("right", 0.25, 0.02))
	breach_panel.trap_felt.connect(func(): feedback.pulse("left", 0.7, 0.15))   # ловушка: импульс левого контроллера
	_place()


## Подключить связь с телефоном (null — отключить): у деки появляются вкладки ЧАТ и ЗВОНКИ, вибрация и звук следят за событиями.
func set_phone(link: PhoneLink) -> void:
	phone = link
	deck.set_phone(link)
	feedback.bind(rig, link)


func _process(delta: float) -> void:
	_place()
	if phone != null:
		phone.advance(delta)


## В VR — якорь на запястье левой руки (нет руки в рига — левый контроллер, как раньше); плоская сборка — привязка к камере (низ-лево).
func _place() -> void:
	if rig == null:
		return
	var wrist := rig.left_hand_view != null and rig.left_hand_view.wrist_anchor != null
	var want: Node3D = rig.camera
	if rig.xr_active:
		want = rig.left_hand_view.wrist_anchor if wrist else rig.left_hand
	if _anchor.get_parent() != want:
		if _anchor.get_parent() != null:
			_anchor.get_parent().remove_child(_anchor)
		want.add_child(_anchor)
		if rig.xr_active and wrist:
			_anchor.transform = Transform3D.IDENTITY
			deck.scale = Vector3.ONE * WRIST_DECK_SCALE
			deck.rotation = Vector3(0, 0, deg_to_rad(WRIST_DECK_ROLL_DEG))
			deck.position = WRIST_DECK_POS
			trace.position = WRIST_TRACE_POS
		elif rig.xr_active:
			_anchor.transform = Transform3D(Basis.from_euler(Vector3(-PI / 3, 0, 0)), Vector3(0, 0.05, -0.1))
			deck.scale = Vector3.ONE
			deck.rotation = Vector3.ZERO
			deck.position = Vector3.ZERO
			trace.position = FLAT_TRACE_POS
		else:
			_anchor.transform = Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(15), 0)), Vector3(-0.3, -0.2, -0.65))
			deck.scale = Vector3.ONE
			deck.rotation = Vector3.ZERO
			deck.position = Vector3.ZERO
			trace.position = FLAT_TRACE_POS
	# На запястье дека живёт, пока рука видна (есть поза контроллера): без данных якорь стоял бы в начале рига.
	_anchor.visible = not (rig.xr_active and wrist) or rig.left_hand_view.visible

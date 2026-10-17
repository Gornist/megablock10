extends Node
## Плоская отладочная сборка: сцена узла и тот же XR-риг, управляемый клавиатурой и мышью.
## T зажата — прицел телепорта по взгляду, отпустить — телепорт (C — отмена), Q/E — плавный поворот, WASD — ход только с --walk, ПКМ+мышь — осмотр, R — центровка, Esc 3 с — экстренное отключение,
## F / ЛКМ — взять объект (просит сервер), 1–9 — применить демона из деки, X — выйти чисто на площадке выхода.
## С аргументом --tester (одиночная игра для тестеров, его передаёт solo_stub) управление другое — client/solo_controls.gd: ходьбы нет, прицел по центру экрана
## (ЛКМ держать), Q/E — щелчок 45°, мышь захвачена, Tab — свободный курсор для деки и панели взлома.
## Trace, ICE, перезарядки и звук приходят с сервера (ProtoClient).

## Аргумент режима тестера (управление SoloControls вместо клавиш разработчика).
const TESTER_ARG := "--tester"

var controls: SoloControls


func start(args: PackedStringArray) -> void:
	var p := ProtoClient.new()
	p.name = "Proto"
	add_child(p)
	p.start(args, "flat", false)
	if p.net != null:
		p.scene.rig.exit_requested.connect(p.net.request_exit)
	if TESTER_ARG in args and p.scene != null:
		controls = SoloControls.new()
		controls.name = "SoloControls"
		add_child(controls)   # после Proto: события мыши и клавиш приходят ему раньше сцены
		controls.setup(p.scene.rig, p.scene.world_ui.breach_panel)
	print("[netrun-flat] сцена узла, риг управляется мышью и клавиатурой", ", режим тестера" if controls != null else "")

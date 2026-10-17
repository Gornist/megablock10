class_name SoloUi
extends Node
## Экраны одиночной игры для тестеров (flat-playtest.md п. 8–11): порядок показа, меню Esc, H, курсор на время экрана, ответы анкеты в журнал.
## Подключается к SoloStub (`setup`), слушает run_finished. Экраны — модальные Control-ы на CanvasLayer (SoloScreen), подсказки — HintsCorner под ними.
## Игра под экранами не останавливается: сервер мира идёт (учебный узел при «Наденьте наушники» безопасен; меню Esc честно предупреждает).
## Курсор: пока экран открыт, мышь свободна. Режимом ведёт SoloControls (Tab-курсор К4) — мы его только просим стать свободным (toggle_cursor) и возвращаем обратно.

## Короткое нажатие Esc — меню; дольше — зажатие аварийного выхода рига (3 с), меню не открываем.
const ESC_TAP_MAX_MS := 1000
const SCREEN_HEADPHONES := "headphones"
const SCREEN_CONTROLS := "controls"
const SCREEN_PAUSE := "pause"
const SCREEN_SURVEY := "survey"
const SCREEN_RESULT := "result"

var stub: Node
var seen: SoloSeen
var hints: HintsCorner
var current: SoloScreen
var current_kind := ""
## Открыть папку (путь res/user — глобализуется) и выйти; тесты подменяют, настоящие уводили бы в Finder и закрывали прогон.
var open_fn := func(path: String) -> int: return OS.shell_open(ProjectSettings.globalize_path(path))
var quit_fn := func() -> void: get_tree().quit()
var _layer: CanvasLayer
var _queue: Array[String] = []
var _return_to := ""
var _last := {}
var _forced_controls: SoloControls
var _esc_down_ms := -1


## Экраны при старте: наушники всегда; картинка управления — только при первом запуске.
static func startup_screens(controls_seen: bool) -> Array[String]:
	var out: Array[String] = [SCREEN_HEADPHONES]
	if not controls_seen:
		out.append(SCREEN_CONTROLS)
	return out


## Экраны после конца забега: итог всегда; анкета перед ним — один раз, после первой настоящей (не учебной) попытки.
static func after_run_screens(tutorial: bool, survey_done: bool) -> Array[String]:
	var out: Array[String] = []
	if not tutorial and not survey_done:
		out.append(SCREEN_SURVEY)
	out.append(SCREEN_RESULT)
	return out


## Нажатие Esc длиной held_ms — «короткое» (меню).
static func is_esc_tap(held_ms: int) -> bool:
	return held_ms >= 0 and held_ms < ESC_TAP_MAX_MS


## Подключить к SoloStub (run_finished, журнал, перезапуск) и состоянию «видел».
func setup(stub_: Node, seen_: SoloSeen) -> void:
	stub = stub_
	seen = seen_
	name = "SoloUi"
	_layer = CanvasLayer.new()
	_layer.name = "Screens"
	_layer.layer = SoloWidgets.LAYER_SCREENS
	add_child(_layer)
	var hints_layer := CanvasLayer.new()
	hints_layer.name = "Hints"
	hints_layer.layer = SoloWidgets.LAYER_HINTS
	add_child(hints_layer)
	hints = HintsCorner.new(seen)
	hints_layer.add_child(hints)
	stub.run_finished.connect(_on_run_finished)


## Старт: наушники, затем (первый запуск) картинка управления, затем игра.
func begin() -> void:
	_queue = startup_screens(seen.controls_seen)
	_return_to = ""
	_next()


## Экран открыт сейчас.
func is_modal() -> bool:
	return current != null


## Короткое нажатие Esc: меню открыть, открытое меню закрыть; картинка управления из меню — назад в меню; прочие экраны Esc не трогает.
func esc_tap() -> void:
	if current == null:
		show_screen(SCREEN_PAUSE)
	elif current_kind == SCREEN_PAUSE:
		_close()
	elif current_kind == SCREEN_CONTROLS and _return_to == SCREEN_PAUSE:
		_next()


## H: скрыть или показать подсказки (не при открытом экране).
func toggle_hints() -> void:
	if current == null and hints != null:
		hints.toggle()


func show_screen(kind: String) -> void:
	_drop_current()
	var screen: SoloScreen
	match kind:
		SCREEN_HEADPHONES:
			screen = HeadphonesScreen.new()
		SCREEN_CONTROLS:
			screen = ControlsPicture.new()
			if not seen.controls_seen:
				seen.mark_controls_seen()
		SCREEN_PAUSE:
			screen = PauseMenu.new()
		SCREEN_SURVEY:
			screen = SurveyScreen.new()
		SCREEN_RESULT:
			screen = RunResultScreen.new(str(_last.get("result", "")), bool(_last.get("tutorial", false)), _last.get("loot", {}), _last.get("summary", {}),
				str(_last.get("dir", "")))
		_:
			push_error("[netrun-solo-ui] неизвестный экран: " + kind)
			return
	current = screen
	current_kind = kind
	screen.chosen.connect(_on_chosen.bind(kind))
	_layer.add_child(screen)
	_free_cursor()


## Конец забега: учебный — сразу итог, настоящий — (один раз) анкета, потом итог.
func _on_run_finished(result: String, tutorial: bool) -> void:
	_last = {"result": result, "tutorial": tutorial, "loot": _deck_snapshot(), "summary": stub.get("last_summary"), "dir": stub.call("journal_dir")}
	_queue = after_run_screens(tutorial, seen.survey_done)
	_return_to = ""
	_next()


func _deck_snapshot() -> Dictionary:
	var d: Variant = stub.call("deck_snapshot")
	return d if d is Dictionary else {}


## Следующий экран: возврат в меню (картинка управления из него), затем очередь; пусто — экраны закончились.
func _next() -> void:
	if not _return_to.is_empty():
		var back := _return_to
		_return_to = ""
		show_screen(back)
	elif not _queue.is_empty():
		show_screen(_queue.pop_front())
	else:
		_close()


func _on_chosen(action: String, kind: String) -> void:
	match action:
		"ready", "close":
			_next()
		"resume":
			_close()
		"controls":
			_return_to = kind
			show_screen(SCREEN_CONTROLS)
		"folder":
			var dir := str(stub.call("journal_dir"))
			if not dir.is_empty():
				open_fn.call(dir)
		"again":
			_restart(false)
		"tutorial":
			_restart(true)
		"quit":
			quit_fn.call()
		"submit":
			_submit_survey()


## Ответы анкеты — в журнал этой же попытки (до restart: после него журнал указывает на новую), анкета больше не покажется.
func _submit_survey() -> void:
	if current is SurveyScreen:
		var err: Error = stub.journal.log_survey((current as SurveyScreen).answers())
		if err != OK:
			push_warning("[netrun-solo-ui] ответы анкеты не записаны в журнал: %s" % error_string(err))
		seen.mark_survey_done()
	_next()


func _restart(with_tutorial: bool) -> void:
	_queue.clear()
	_return_to = ""
	_close()
	stub.restart(with_tutorial)


func _close() -> void:
	_drop_current()
	if _forced_controls != null and is_instance_valid(_forced_controls) and _forced_controls.is_free():
		_forced_controls.toggle_cursor()   # курсор был захвачен до экрана — вернуть мышь взгляду
	_forced_controls = null


func _drop_current() -> void:
	if current != null:
		current.hide()   # до конца кадра не виден и не ловит мышь; из дерева не вынимаем — вынутый, но ещё не освобождённый узел gdUnit считает орфаном
		current.mouse_filter = Control.MOUSE_FILTER_IGNORE
		current.queue_free()
	current = null
	current_kind = ""


## Мышь свободна: окно ведёт курсор сам, а SoloControls просим освободить курсор (иначе его _input проглотит клики по кнопкам).
func _free_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var c := _controls()
	if c != null and not c.is_free():
		c.toggle_cursor()
		_forced_controls = c


func _controls() -> SoloControls:
	var flat: Variant = stub.get("flat")
	if flat == null or not is_instance_valid(flat):
		return null
	var c: Variant = (flat as Node).get("controls")
	return c as SoloControls if c != null and is_instance_valid(c) else null


func _process(_delta: float) -> void:
	if current != null:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			_free_cursor()   # Tab или возврат фокуса окна захватили мышь, пока экран открыт
		else:
			var c := _controls()
			if c != null and not c.is_free():
				_free_cursor()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE and not (event as InputEventKey).echo:
		if event.pressed:
			_esc_down_ms = Time.get_ticks_msec()
		elif _esc_down_ms >= 0:
			var held := Time.get_ticks_msec() - _esc_down_ms
			_esc_down_ms = -1
			if is_esc_tap(held):
				esc_tap()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_H:
		toggle_hints()

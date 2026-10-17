class_name SoloSeen
extends RefCounted
## Что тестер уже видел (одиночная игра, flat-playtest.md п. 8–10): картинка управления показана, подсказки в углу включены, анкета пройдена.
## Лежит в `user://solo_seen.cfg` (ConfigFile): переживает перезапуск exe, чтобы анкета не повторялась, а картинка управления не вылезала каждый раз.
## Нет файла или он битый — всё «не видел», подсказки включены.

const PATH := "user://solo_seen.cfg"
const SECTION := "seen"

var path := PATH
var controls_seen := false
var hints_visible := true
var survey_done := false


## Прочитать состояние из файла path (нет файла — значения по умолчанию, путь запоминается для save).
static func load_from(path_: String = PATH) -> SoloSeen:
	var s := SoloSeen.new()
	s.path = path_
	var cfg := ConfigFile.new()
	if cfg.load(path_) == OK:
		s.controls_seen = bool(cfg.get_value(SECTION, "controls_seen", false))
		s.hints_visible = bool(cfg.get_value(SECTION, "hints_visible", true))
		s.survey_done = bool(cfg.get_value(SECTION, "survey_done", false))
	return s


func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "controls_seen", controls_seen)
	cfg.set_value(SECTION, "hints_visible", hints_visible)
	cfg.set_value(SECTION, "survey_done", survey_done)
	var base := path.get_base_dir()
	if not base.is_empty():
		DirAccess.make_dir_recursive_absolute(base)
	return cfg.save(path)


func mark_controls_seen() -> void:
	controls_seen = true
	save()


func set_hints_visible(v: bool) -> void:
	hints_visible = v
	save()


func mark_survey_done() -> void:
	survey_done = true
	save()

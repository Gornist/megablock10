class_name RunResultScreen
extends SoloScreen
## Итог забега (flat-playtest.md п. 8, §2): чем кончился, добыча цифрами, путь к журналу, «Открыть папку» и «пришлите этот файл». Рисуется 2D поверх завесы
## EndScreen (она в 3D на лице риг-камеры). Цифры добычи — из последнего события `deck` (те же данные, что вкладка ДОБЫЧА деки), сводка попытки — из RunJournal.summary.

const OUTCOME_CLEAN := "clean"
const OUTCOME_CAUGHT := "caught"
const OUTCOME_FAIL := "fail"
const SEND_NOTE := "Пришлите этот файл (zip папки)."
const NO_JOURNAL := "Журнал не создан: папка попытки недоступна."
const TUTORIAL_TAG := "учебный узел"
const WIDTH := 560.0

var result := ""
var tutorial := false
var loot: Dictionary = {}
var summary: Dictionary = {}
var journal_dir := ""


## Исход для экрана: чистый выход / поймали (выброс ICE, флэтлайн) / провал (всё остальное: обрыв связи, аварийный выход, снятие очков).
static func outcome(result_: String) -> String:
	match result_:
		ExitLogic.REASON_CLEAN:
			return OUTCOME_CLEAN
		ExitLogic.REASON_EJECTED, ExitLogic.REASON_FLATLINE:
			return OUTCOME_CAUGHT
	return OUTCOME_FAIL


static func title_text(result_: String) -> String:
	match outcome(result_):
		OUTCOME_CLEAN:
			return "ЧИСТЫЙ ВЫХОД"
		OUTCOME_CAUGHT:
			return "ПОЙМАЛИ"
	return "ПРОВАЛ"


## Пояснение к исходу: что осталось в узле или чем оборвалось.
static func subtitle_text(result_: String) -> String:
	match result_:
		ExitLogic.REASON_CLEAN:
			return "Вы вышли с площадки выхода."
		ExitLogic.REASON_EJECTED:
			return "ICE выбросил вас — добыча осталась в узле."
		ExitLogic.REASON_FLATLINE:
			return "Флэтлайн — дека осталась в узле."
		ExitLogic.REASON_MANUAL_HOLD:
			return "Аварийный выход (Esc, три секунды)."
		ExitLogic.REASON_CONNECTION_LOST:
			return "Связь с узлом потеряна."
	return "Забег прерван: " + result_


static func title_color(result_: String) -> Color:
	match outcome(result_):
		OUTCOME_CLEAN:
			return DeckTheme.OK
		OUTCOME_CAUGHT:
			return DeckTheme.BAD
	return DeckTheme.WARN


## Добыча цифрами из события `deck` ({loot [{kind: shard | daemon}], eddies}): {shards, daemons, eddies}.
static func loot_figures(deck_info: Dictionary) -> Dictionary:
	var shards := 0
	var daemons := 0
	for it: Variant in deck_info.get("loot", []):
		if it is Dictionary:
			match str((it as Dictionary).get("kind", "")):
				"shard":
					shards += 1
				"daemon":
					daemons += 1
	return {"shards": shards, "daemons": daemons, "eddies": int(deck_info.get("eddies", 0))}


static func loot_text(figures: Dictionary) -> String:
	return "шарды %d · демоны %d · эдди %d" % [int(figures.get("shards", 0)), int(figures.get("daemons", 0)), int(figures.get("eddies", 0))]


## Сводка попытки одной строкой: время, взломы, поимки, промахи прицела.
static func stats_text(summary: Dictionary) -> String:
	var sec := int(float(summary.get("sec", 0.0)))
	return "время %d:%02d · взломы %d из %d · поимок %d · промахов прицела %d" % [int(sec / 60.0), sec % 60, int(summary.get("breaches_won", 0)),
		int(summary.get("breaches", 0)), int(summary.get("caught", 0)), int(summary.get("aim_miss", 0))]


func _init(result_: String = "", tutorial_: bool = false, loot_: Dictionary = {}, summary_: Dictionary = {}, journal_dir_: String = "") -> void:
	super()
	result = result_
	tutorial = tutorial_
	loot = loot_
	summary = summary_
	journal_dir = journal_dir_


func _build(b: VBoxContainer) -> void:
	b.add_child(SoloWidgets.title(title_text(result), title_color(result)))
	if tutorial:
		b.add_child(SoloWidgets.label(TUTORIAL_TAG.to_upper(), SoloWidgets.FS_META, DeckTheme.LABEL, DeckTheme.font_mono()))
	b.add_child(SoloWidgets.paragraph(subtitle_text(result), WIDTH, SoloWidgets.FS_BODY, DeckTheme.INK))
	var loot_box := SoloWidgets.label("ДОБЫЧА", SoloWidgets.FS_META, DeckTheme.LABEL, DeckTheme.font_mono())
	b.add_child(loot_box)
	var figs := loot_figures(loot)
	var loot_color := DeckTheme.INK_STRONG if outcome(result) != OUTCOME_CAUGHT else DeckTheme.INK3
	var loot_line := SoloWidgets.label(loot_text(figs) + (" (потеряна)" if outcome(result) == OUTCOME_CAUGHT else ""), 30, loot_color, DeckTheme.font_medium())
	loot_line.name = "LootLine"
	b.add_child(loot_line)
	b.add_child(SoloWidgets.paragraph(stats_text(summary), WIDTH, SoloWidgets.FS_SMALL, DeckTheme.INK2))
	b.add_child(SoloWidgets.spacer(4))
	if journal_dir.is_empty():
		b.add_child(SoloWidgets.paragraph(NO_JOURNAL, WIDTH, SoloWidgets.FS_SMALL, DeckTheme.WARN))
	else:
		b.add_child(SoloWidgets.label("ЖУРНАЛ", SoloWidgets.FS_META, DeckTheme.LABEL, DeckTheme.font_mono()))
		var path := SoloWidgets.paragraph(ProjectSettings.globalize_path(journal_dir), WIDTH, SoloWidgets.FS_SMALL, DeckTheme.INK)
		path.name = "JournalPath"
		b.add_child(path)
		b.add_child(SoloWidgets.paragraph(SEND_NOTE, WIDTH, SoloWidgets.FS_SMALL, DeckTheme.ACC))
		var open_btn := add_action(b, "ОТКРЫТЬ ПАПКУ", "folder", "quiet")
		open_btn.custom_minimum_size.x = WIDTH
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	var again := add_action(row, "ЕЩЁ РАЗ", "again", "primary")
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tut := add_action(row, "ОБУЧЕНИЕ ЗАНОВО", "tutorial", "ghost")
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var quit := add_action(row, "ВЫЙТИ", "quit", "danger")
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

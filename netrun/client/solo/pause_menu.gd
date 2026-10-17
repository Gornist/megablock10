class_name PauseMenu
extends SoloScreen
## Меню по короткому нажатию Esc (три секунды — по-прежнему аварийный выход рига). Игра под меню НЕ останавливается: сервер мира идёт, ICE ходит.

const TITLE := "МЕНЮ"
const NOTE := "Игра идёт, пока открыто меню."
## Кнопки: (подпись, действие, вид). «Обучение заново» — не по умолчанию, поэтому не primary.
const ITEMS := [
	["ПРОДОЛЖИТЬ", "resume", "primary"],
	["ЕЩЁ РАЗ", "again", "ghost"],
	["ОБУЧЕНИЕ ЗАНОВО", "tutorial", "ghost"],
	["КАРТИНКА УПРАВЛЕНИЯ", "controls", "ghost"],
	["ОТКРЫТЬ ПАПКУ ЖУРНАЛА", "folder", "ghost"],
	["ВЫЙТИ", "quit", "danger"],
]
const WIDTH := 400.0


func _build(b: VBoxContainer) -> void:
	b.add_child(SoloWidgets.title(TITLE))
	b.add_child(SoloWidgets.paragraph(NOTE, WIDTH, SoloWidgets.FS_SMALL, DeckTheme.INK2))
	for it: Array in ITEMS:
		var btn := add_action(b, str(it[0]), str(it[1]), str(it[2]))
		btn.custom_minimum_size.x = WIDTH

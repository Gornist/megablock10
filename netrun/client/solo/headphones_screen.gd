class_name HeadphonesScreen
extends SoloScreen
## «Наденьте наушники» — при каждом запуске exe (flat-playtest.md п. 9): ICE слышно раньше, чем видно, без звука цифры не сравнить с очками.
## Игра под экраном уже идёт (учебный узел безопасен), «Готов» (или Enter) просто убирает экран.

const TITLE := "НАДЕНЬТЕ НАУШНИКИ"
const TEXT := "ICE слышно раньше, чем видно."
const SUBTEXT := "Играйте со звуком: без него цифры нельзя сравнить с очками."
const READY := "ГОТОВ"


func _build(b: VBoxContainer) -> void:
	b.add_child(SoloWidgets.title(TITLE))
	b.add_child(SoloWidgets.paragraph(TEXT, 520.0, 28, DeckTheme.INK_STRONG))
	b.add_child(SoloWidgets.paragraph(SUBTEXT, 520.0, SoloWidgets.FS_SMALL, DeckTheme.INK2))
	b.add_child(SoloWidgets.spacer(8))
	add_action(b, READY, "ready", "primary")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		chosen.emit("ready")

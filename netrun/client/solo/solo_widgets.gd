class_name SoloWidgets
extends RefCounted
## Общие кирпичи 2D-экранов тестера (окно ПК, не очки): подпись, кнопка, панель в стиле деки (DeckTheme, MbButton, MbFrame).
## Шрифты крупнее, чем на деке в очках: экран читают с расстояния монитора, а не с вытянутой руки по SubViewport.

const FS_BODY := 22
const FS_TITLE := 38
const FS_SMALL := 17
const FS_META := 16
const BTN_H := 56.0
const BTN_FS := 20
## Слой экранов (CanvasLayer): над прицелом (SoloControls, слой 5) и подсказками (слой 8).
const LAYER_SCREENS := 10
const LAYER_HINTS := 8


static func label(text: String, size: int = FS_BODY, color: Color = DeckTheme.INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else DeckTheme.font_text())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Подпись с переносом по словам: ширина задаётся min-размером (width_px).
static func paragraph(text: String, width_px: float, size: int = FS_BODY, color: Color = DeckTheme.INK) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width_px
	return l


static func title(text: String, color: Color = DeckTheme.ACC) -> Label:
	return label(text, FS_TITLE, color, DeckTheme.font_medium())


static func button(text: String, kind: String = "ghost") -> MbButton:
	var b := MbButton.new(text, kind)
	b.font_size = BTN_FS
	b.button_height = BTN_H
	b.pad_x = 22.0
	b.update_minimum_size()
	return b


## Панель экрана: тёмная заливка, красноватая обвязка гайдлайна, срез по углам.
static func panel(pad_x: int = 32, pad_y: int = 26) -> MbFrame:
	return MbFrame.make(DeckTheme.PLATE, DeckTheme.CHROME, MbShape.Form.STD, DeckTheme.CUT, pad_x, pad_y)


## «Клавиша»: короткая метка в рамке (кеп клавиши в картинке управления и в подсказках).
static func keycap(text: String) -> MbFrame:
	var f := MbFrame.make(DeckTheme.PLATE2, DeckTheme.ACC, MbShape.Form.TAB, DeckTheme.CUT_SMALL, 10, 3)
	f.add_child(label(text, FS_SMALL, DeckTheme.ACC, DeckTheme.font_mono()))
	return f


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

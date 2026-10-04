class_name DeckTheme
extends RefCounted
## Тема деки на руке: цвета, шрифты и размеры из дизайн-системы приложения (docs/ux/ui-style-guide.md, app/.../ui/theme/Mb*), собранные
## в один Godot Theme. Экраны деки (чат, звонки) собираются из общих компонентов (MbFrame, MbButton, MbTabs, MbRow, DeckUi) и берут
## отсюда всё: своих цветов и размеров на экране нет. Единицы — пиксели SubViewport (DeckPanel.VIEW_SIZE), не dp: панель 512 px на 32 см,
## то есть 1 px ≈ 0,6 мм, а на запястье (дека уменьшена в WorldUI.WRIST_DECK_SCALE раз) ≈ 0,47 мм; размеры выбраны так, чтобы нажимаемое было не меньше
## ~2 см и после уменьшения, а текст читался на 40–50 см (README, «Дека на руке»). Размер вьюпорта и ширина панели — константы DeckPanel, масштаб — WorldUI.

# ---------------------------------------------------------------- цвета (токены гайдлайна, основная тема)
const BG := Color("#110A0C")
const PLATE := Color("#150D10")
const PLATE2 := Color("#0F0A0C")
const PLATE_EDGE := Color("#4A2124")
const CHROME := Color("#C65A52")
const CHROME_DIM := Color("#5A2629")
const CHROME_SOFT := Color(0.776, 0.353, 0.322, 0.30)
const LABEL := Color("#F08A80")
const INK := Color("#E2F4F0")
const INK2 := Color("#9DB3AF")
const INK3 := Color("#947A7E")
const INK_STRONG := Color("#F1F1EF")
const ACC := Color("#5EF6FF")
const ACC_INK := Color("#02181B")
const SEL_FILL := Color("#2D6563")
const MONEY := Color("#F5D547")
const ON_MONEY := Color("#1C1600")
const OK := Color("#43F08F")
const WARN := Color("#FF9F43")
const BAD := Color("#FF5A50")
const DLG_FILL := Color("#0A1320")
const DLG_EDGE := Color("#4FB6C4")
const DLG_BAR := Color("#2C6F7A")
const TAB_BAR_IDLE := Color("#F1C7C2")
const BUBBLE_IN_FILL := Color("#0D1819")
const BUBBLE_IN_EDGE := Color("#8FE3D6")
const BUBBLE_IN_TEXT := Color("#DFF5F0")
const BUBBLE_OWN_FILL := Color("#17663D")
const BUBBLE_OWN_EDGE := OK
const BUBBLE_OWN_TEXT := Color("#EFFFF4")

# ---------------------------------------------------------------- размеры, px SubViewport
# Физический размер: 1 px = DeckPanel.PANEL_WIDTH_M / VIEW_SIZE.x (0,625 мм при 32 см / 512 px), на запястье ещё × WorldUI.WRIST_DECK_SCALE (0,75 → 0,47 мм).
# Нажимаемое — не меньше 46 px (≈ 2,2 см на запястье); числа ниже сверяет deck_tabs_test.gd (test_touch_targets_stay_above_2_cm_on_the_wrist).
const FS_TEXT := 19        ## текст сообщения, обычные подписи
const FS_NAME := 20        ## названия в списках, кнопки (Fira Medium)
const FS_SMALL := 16       ## превью, вторичные подписи
const FS_CODE := 19        ## цепочка кодов демона (моноширинный): коды «1C BD» читаются с вытянутой руки только крупно
const FS_META := 14        ## время, статус, метки (Plex Mono Medium)
const FS_TAB := 18
const FS_BUTTON := 17
const FS_BIG := 30         ## позывной звонящего
const FS_TIMER := 32       ## таймер разговора
const PAD := 10            ## отступ содержимого от края панели
const GAP := 6             ## между блоками
const TAB_H := 48
const ROW_H := 58
const BTN_H := 52          ## кнопки карточки звонка
const BTN_SMALL_H := 48    ## кнопки шапки диалога и журнала звонков
const CHIP_H := 48         ## заготовки ответа
const CUT := 8.0           ## срез рамки панели и кнопок
const CUT_SMALL := 4.0     ## метки, «клавиши», заготовки
const CUT_BUBBLE := 7.0
const BUBBLE_MAX_W := 390  ## ширина пузыря сообщения не больше (≈ 78 % ширины списка)

const FONT_TEXT := "res://client/ui/fonts/fira_sans_condensed_regular.ttf"
const FONT_MEDIUM := "res://client/ui/fonts/fira_sans_condensed_medium.ttf"
const FONT_MONO := "res://client/ui/fonts/ibm_plex_mono_medium.ttf"

## Вариации Label (theme_type_variation).
const V_NAME := &"DeckName"       ## ЗАГЛАВНЫЕ названия: диалог, собеседник
const V_DIM := &"DeckDim"         ## превью, вторичный текст
const V_META := &"DeckMeta"       ## время, мета (моношрифт)
const V_ACC := &"DeckAcc"         ## мета бирюзовая («активно», автор во фракционном чате)
const V_OK := &"DeckOk"
const V_WARN := &"DeckWarn"
const V_BAD := &"DeckBad"
const V_BIG := &"DeckBig"         ## позывной звонящего
const V_TIMER := &"DeckTimer"     ## таймер разговора
const V_CODE := &"DeckCode"       ## цепочка кодов демона (моноширинный, FS_CODE ≥ 19 px, бирюзовый)
const V_HEAD := &"DeckHead"       ## заголовок экрана («ДЕМОНЫ», имя собеседника в шапке диалога)

static var _theme: Theme
static var _fonts := {}


static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	# Шрифт может быть не импортирован (первый запуск до импорта) — тогда системный по умолчанию, без ошибки.
	var f: Font = load(path) as Font if ResourceLoader.exists(path) else null
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[path] = f
	return f


static func font_text() -> Font:
	return font(FONT_TEXT)


static func font_medium() -> Font:
	return font(FONT_MEDIUM) if ResourceLoader.exists(FONT_MEDIUM) else font(FONT_TEXT)


static func font_mono() -> Font:
	return font(FONT_MONO)


## Тема целиком; собирается один раз. Присваивается корню SubViewport — потомки наследуют.
static func theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font_text()
	t.default_font_size = FS_TEXT
	t.set_color("font_color", "Label", INK)
	t.set_font("font", "Label", font_text())
	t.set_font_size("font_size", "Label", FS_TEXT)
	t.set_constant("line_spacing", "Label", 0)
	_label_variation(t, V_NAME, font_medium(), FS_NAME, INK_STRONG)
	_label_variation(t, V_HEAD, font_medium(), FS_NAME, ACC)
	_label_variation(t, V_DIM, font_text(), FS_SMALL, INK2)
	_label_variation(t, V_META, font_mono(), FS_META, INK2)
	_label_variation(t, V_ACC, font_mono(), FS_META, ACC)
	_label_variation(t, V_OK, font_mono(), FS_META, OK)
	_label_variation(t, V_WARN, font_mono(), FS_META, WARN)
	_label_variation(t, V_BAD, font_mono(), FS_META, BAD)
	_label_variation(t, V_CODE, font_mono(), FS_CODE, ACC)
	_label_variation(t, V_BIG, font_medium(), FS_BIG, INK_STRONG)
	_label_variation(t, V_TIMER, font_mono(), FS_TIMER, OK)
	# Полоса прокрутки: тонкая, обвязочного цвета, без стрелок.
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(CHROME_DIM, 0.35)
	bar.set_content_margin_all(2.0)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(ACC, 0.55)
	grab.set_content_margin_all(2.0)
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", kind, bar)
		t.set_stylebox("grabber", kind, grab)
		t.set_stylebox("grabber_highlight", kind, grab)
		t.set_stylebox("grabber_pressed", kind, grab)
	return t


static func _label_variation(t: Theme, name: StringName, f: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, f)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


## Цвета кнопки по виду (гайдлайн, раздел 5, «Button»): {fill, edge, text}. chip — заготовка быстрого ответа.
static func button_colors(kind: String, disabled: bool = false) -> Dictionary:
	if disabled:
		return {"fill": Color("#1A1416"), "edge": Color("#3A2A2C"), "text": Color("#7D6A6D")}
	match kind:
		"primary":
			return {"fill": ACC, "edge": ACC, "text": ACC_INK}
		"success":
			return {"fill": Color("#0F3A2A"), "edge": OK, "text": Color("#DFFFEE")}
		"danger":
			return {"fill": Color("#3A1214"), "edge": BAD, "text": Color("#FFE3DF")}
		"alert":
			return {"fill": Color("#B3312A"), "edge": BAD, "text": Color.WHITE}
		"quiet":
			return {"fill": DLG_FILL, "edge": DLG_BAR, "text": ACC}
		"chip":
			return {"fill": PLATE, "edge": CHROME, "text": INK}
	return {"fill": Color("#1B1215"), "edge": Color("#DCCBC8"), "text": Color("#F1ECEA")}   # ghost


## Цвет тона для статусов и меток (гайдлайн, StatusText): ok, warn, bad, acc, money, dim.
static func tone_color(tone: String) -> Color:
	match tone:
		"ok":
			return OK
		"warn":
			return WARN
		"bad":
			return BAD
		"acc":
			return ACC
		"money":
			return MONEY
		"dim":
			return INK3
	return INK2


## Вариация Label для тона.
static func tone_variation(tone: String) -> StringName:
	match tone:
		"ok":
			return V_OK
		"warn":
			return V_WARN
		"bad":
			return V_BAD
		"acc":
			return V_ACC
	return V_META

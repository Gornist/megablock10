class_name AssetMaterials
extends RefCounted
## Подмена материалов импортированного ассета «Сети» по имени роли (shell_soft, points, streaks, solid_dark; glow_edge — устаревшая)
## на ShaderMaterial из `res://assets/shaders/`. .glb аддитивное смешивание и шейдеры не переносит,
## поэтому ассет приходит с материалами-ролями, а вид задают эти шейдеры (STYLE.md, «Что отдаёт Blender, что делает Godot»).
## Подмена идёт на экземпляре (set_surface_override_material): импортированный меш не меняется.

const SHADERS := {
	"shell_soft": preload("res://assets/shaders/shell_soft.gdshader"),
	"glow_edge": preload("res://assets/shaders/glow_edge.gdshader"),
	"points": preload("res://assets/shaders/points.gdshader"),
	"streaks": preload("res://assets/shaders/streaks.gdshader"),
	"solid_dark": preload("res://assets/shaders/solid_dark.gdshader"),
}

## Вуаль на гранях плит (меши `*_skirt` в floor, ceiling и far_*): в .glb у неё материал-роль shell_soft, а шейдер по имени меша — этот.
const SKIRT_SHADER := preload("res://assets/shaders/skirt.gdshader")
## Сплошная дымка горизонта (меш `horizon_mist` в env/horizon_band): тоже роль shell_soft, шейдер по имени меша.
const HAZE_SHADER := preload("res://assets/shaders/haze.gdshader")
## Ореол-«капля» маяка предмета (меш `beacon_halo` в узле Beacon у шарда и токена): роль shell_soft, шейдер по имени меша.
const BEACON_HALO_SHADER := preload("res://assets/shaders/beacon_halo.gdshader")
## Луч маяка (меш `beacon_beam`): штрихи (streaks) с ореолом, но спокойнее обычных — почти без дыхания и качания, гладкий (без бусин), ярче, чтобы читаться с 3 м.
const BEACON_BEAM := {"halo": 0.5, "halo_width": 2.2, "end_fade": 0.6, "breathe": 0.08, "sway": 0.003, "bead_depth": 0.0, "glow": 2.2}

## ЭКСПЕРИМЕНТ: верх стеклянного пола (меш `*_glass` в env/floor_glass_<N>): роль shell_soft, шейдер по имени меша; сторону плиты (plate_size) берём из AABB меша.
const GLASS_SHADER := preload("res://assets/shaders/glass.gdshader")

## ЭКСПЕРИМЕНТ «варианты пола» (env/floor_v<N>_<размер>, src/floor_variants.py): параметры шейдеров по номеру варианта и имени меша. Ключ — номер варианта, вложенный ключ — суффикс меша.
## `_glass` (v1 пыль — слабая дымка; v3 решётка — сплошные линии по границам клеток хода 1 м в мировых координатах, без случайных подсвеченных клеток: их принимали за занятые), `_skirt` (v2: яркая стенка ступени), `_plates` (контур верха плиты по UV).
const FLOOR_V := {
	1: {"_glass": {"glass_alpha": 0.06, "center_k": 1.0, "patch_amount": 0.5, "rim_alpha": 0.25}, "dust_streaks": {"glow": 3.2, "halo": 0.3, "halo_width": 2.0, "breathe": 0.15}},
	2: {"_skirt": {"veil_alpha": 0.32, "falloff": 0.9}, "_plates": {"uv_rim": 0.03, "edge_glow": 1.6, "edge_uneven": 0.5}},
	3: {"_glass": {"glass_alpha": 0.12, "center_k": 0.8, "patch_amount": 0.4, "rim_alpha": 0.5, "grid_alpha": 0.85, "grid_step": 1.0, "grid_width": 0.02, "grid_dot": 0.0,
			"grid_radius": 9.0, "cell_alpha": 0.0, "cell_share": 0.10}},
	4: {"_plates": {"uv_rim": 0.02, "edge_glow": 1.2, "edge_uneven": 0.7}},
}

## ПАЛИТРА КЛИЕНТСКИХ СЛОЁВ (маркеры пола, прицел, след ICE, стрелки, кольцо такта, метки, HUD, экран конца). Цвет и материал задаёт Blender, логику — Godot:
## клиент берёт цвета ТОЛЬКО отсюда (`AssetMaterials.layer("aim_ok")`) и не задаёт свои. База — HEX из lib.py / STYLE.md: голубой мир, ледяной белый, красный только у угрозы
## (ICE и его взгляд), янтарь — только экран деки. ЗАПРЕЩЕНЫ коричневый, жёлтый, оранжевый и ядовито-зелёный (в кадре клиента 07.10 они были: «две разные игры»).
## Стадии ICE (спокойно → подозрение → тревога → охота) идут внутри красной семьи от белого к красному; безопасное — голубое.
const PAL_CYAN := Color("18e6ff")        # BASE, окружение, «можно»
const PAL_ICE := Color("d9f8ff")         # ледяной белый: самые яркие рёбра, текст, нейтрально
const PAL_THREAT := Color("ff1f3d")      # только угроза: ICE, его взгляд, отказ
const PAL_THREAT_HOT := Color("ff7a6b")  # светлый красный: предупреждение, шаг ICE
const PAL_DIM := Color("2d6b78")         # погасший голубой: недоступно, фон шкал
const PAL_VOID := Color("02050a")        # чёрная завеса (экран конца), не чистый чёрный
const PAL_AMBER := Color("ff7a1a")       # янтарь: ТОЛЬКО экран деки (STYLE.md), слои deck_*
const LAYERS := {
	# Клетки пола
	"cell_occupied_fill": Color(PAL_CYAN, 0.14),   # занятая клетка (укрытие, хранилище): слабая голубая заливка
	"cell_occupied_edge": Color(PAL_CYAN, 0.55),   # и контур клетки
	# Клетка в зрении ICE (TickFloor): тёмно-красная заливка на тёмном фоне читается КОРИЧНЕВОЙ, поэтому заливка почти прозрачна, а читается контур клетки
	"cell_vision_fill": Color(PAL_THREAT_HOT, 0.10),
	"cell_vision_edge": Color(PAL_THREAT_HOT, 0.85),
	"cell_future": Color(PAL_CYAN, 0.30),          # клетка будущего положения (FUTURE_TINT)
	# Прицел прыжка
	"aim_ok": PAL_CYAN,                            # безопасно
	"aim_warn": PAL_THREAT_HOT,                    # периферия зрения ICE
	"aim_no": PAL_THREAT,                          # в фокусе ICE / отказ
	"aim_wait": PAL_ICE,                           # ждём ответа сервера
	"aim_denied": PAL_DIM,                         # недоступно
	# ICE: стадии по порядку 0..3 (глаз, значки тревоги, цвет клеток зрения)
	"ice_calm": PAL_ICE,
	"ice_suspect": Color("ff9d8c"),
	"ice_alert": PAL_THREAT_HOT,
	"ice_hunt": PAL_THREAT,
	"ice_lost": Color("a9c9d6"),                   # потерял игрока
	"ice_precapture": PAL_THREAT,                  # мигание перед захватом
	# Следы и стрелки
	"trail_step": PAL_THREAT_HOT,                  # шаг ICE
	"trail_dim": Color(PAL_THREAT, 0.35),          # прежние шаги, тусклые
	"arrow": PAL_ICE,                              # стрелки направления
	# Кольцо такта
	"tick_track": Color("0b3a46", 0.55),
	"tick_fill": Color(PAL_CYAN, 0.95),
	"tick_warn": Color(PAL_THREAT_HOT, 0.95),      # такт на исходе
	# Надписи и HUD
	"label": PAL_ICE,
	"label_dim": Color(PAL_CYAN, 0.60),
	"hud_ok": PAL_CYAN,
	"hud_notice": PAL_ICE,
	"hud_warn": PAL_THREAT_HOT,
	"hud_bad": PAL_THREAT,
	"hud_off": PAL_DIM,
	"end_win": PAL_CYAN,
	"end_lose": PAL_THREAT,
	"end_veil": PAL_VOID,                          # завеса экрана конца (фейд в тёмное)
	# Указка деки (луч из руки к панелям)
	"pointer_dot": PAL_ICE,                        # точка на панели
	"pointer_press": PAL_CYAN,                     # нажатие
	"pointer_beam": Color(PAL_CYAN, 0.50),         # луч
	# Экран деки: янтарь разрешён только здесь (STYLE.md), 2D-интерфейс деки (DeckTheme/mb_*) остаётся своей системой в этой гамме
	"deck_screen": PAL_AMBER,
}


## Цвет слоя клиента по имени из LAYERS (с альфой, если она задана в палитре); alpha ≥ 0 переопределяет альфу. Неизвестное имя — предупреждение и ледяной белый.
static func layer(name: String, alpha := -1.0) -> Color:
	if not LAYERS.has(name):
		push_warning("AssetMaterials.layer: нет цвета '%s' (есть: %s)" % [name, ", ".join(LAYERS.keys())])
		return PAL_ICE
	var c: Color = LAYERS[name]
	return Color(c, alpha) if alpha >= 0.0 else c


## Параметры solid_dark.gdshader для `pillar_block`/`pillar_base` (env/pillar, env/cover) и `exit_bar_*` (env/exit_frame): ровный яркий свет рёбер без «рваности».
const PILLAR_EDGE := {"edge_glow": 2.2, "edge_uneven": 0.0}

## Мягкая светящаяся обводка силуэта (fringe.gdshader, слои через next_pass) у непрозрачных объёмов: укрытия/колонны (`pillar_block`), брусья выхода (`exit_bar_*`),
## хранилище (`vault_body`). Нужны сглаженные нормали меша (Blender: smooth=True). Параметры слоёв: [px, alpha] — узкий и широкий (слабее).
const FRINGE_SHADER := preload("res://assets/shaders/fringe.gdshader")
const FRINGE_LAYERS := [[0.5, 0.5], [1.0, 0.35], [1.6, 0.2]]
const FRINGE_GLOW_DEFAULT := 0.75  # edge_glow solid_dark по умолчанию (хранилище); у PILLAR_EDGE-мешей — PILLAR_EDGE.edge_glow
static var fringe_on := true  # выключатель для сравнения кадров (preview_capture.gd --nofringe) и замера перерисовки

## «Ручки для очков» (ARCHITECTURE §21): настройки, которые крутят на устройстве без пересборки ассетов — A/B за счёт смены netrun.cfg, блок [assets].
## Ручки читаются в момент `apply()` (создание материалов): вызывать `tune()` / `tune_from_config()` ДО построения окружения, один раз при старте.
## Имя → умолчание (то, что стоит в коде без ручек).
const KNOBS := {
	"min_px_streaks": 1.5,   # минимальная полная ширина штриха, px экрана (streaks.gdshader min_px)
	"min_px_points": 2.0,    # минимальный диаметр точки, px (points.gdshader min_px)
	"fringe_on": true,       # мягкая обводка силуэтов укрытий/хранилища/выхода
	"fringe_alpha": 1.0,     # множитель яркости обводки (на FRINGE_LAYERS[i].alpha)
	"fringe_px": 1.0,        # множитель сдвига слоёв обводки (на FRINGE_LAYERS[i].px)
	"halo": 0.4,             # ореол штрихов окружения (ENV_HALO)
	"halo_width": 2.5,       # расширение квада под ореол (ENV_HALO_WIDTH)
	"halo_far": false,       # ореол у дальних пластов /far_* (по умолчанию выключен: вдвое-втрое больше перерисовки)
	"solid_base": "",        # цвет плит solid_dark «#rrggbb»; пусто — по умолчанию из шейдера
	"edge_glow": 2.2,        # яркость рёбер укрытий и брусьев выхода (PILLAR_EDGE.edge_glow)
	"floor_grid": 0.35,      # сетка клеток 1 м ТЕКСТУРОЙ с мипмапами и анизотропией на плите пола (0 — выкл., вернуть точки slab_seams; 0,3–0,5); по умолчанию ВКЛ.: так выглядит кадр Blender, иначе клиент — «другая игра»
	# Мерцание кромок плит пола/потолка/дальних пластов (две линии на расстоянии 3 см сходятся в пиксель). Меры независимы, комбинируются:
	"rim_top_only": false,   # светится только лицевая грань плиты, боковая полоска кромки погашена (одна линия вместо двух)
	"plate_flat": false,     # боковые грани плит отбрасываются: плита без толщины
	"rim_far_min": 1.0,      # яркость кромки плит на дистанции ≥ rim_far_end (1 — не гасить; 0 — гасить полностью)
	"rim_far_start": 8.0,    # с какой дистанции, м, кромка плит начинает гаснуть
	"rim_far_end": 20.0,     # на какой дистанции, м, она достигает rim_far_min
	"skirt_top_fade": 0.0,   # доля высоты вуали сверху, где плотность растёт с нуля (0 — выкл.; 0,12 — ориентир): вуаль отрывается от кромки плиты
	# Лесенка силуэта без MSAA/FXAA (Pico): «кромка внутрь» — яркий контур сдвинут на 1–1,5 см вглубь грани, у самого силуэта свет гаснет, лесенка становится «тёмное по тёмному».
	"edge_soft": 0.0,        # 0 — выкл.; 0,5 — мягко; 0,8 — сильно. Действует на все solid_dark (колонны, брусья, плиты, тайлы) и на обводку fringe
	# Рябь «эквалайзеров» (штрихи окружения, только при tier != ""; существа и аватары не трогаем). Меры независимы:
	"streak_far_min": 1.0,   # яркость штрихов на дистанции ≥ streak_far_end (1 — не гасить; 0,3 — ориентир), как кромка плит
	"streak_far_start": 8.0,
	"streak_far_end": 25.0,
	"streak_keep": 1.0,      # доля штрихов, что остаются (0,6 — реже на 40%, выпавшие не тратят заливку)
	"streak_len": 1.0,       # длина штрихов окружения (0,6 — короче)
	"streak_px_fade": 0.0,   # 0…1: штрих уже ~2 px на экране тускнеет, а не «ползёт лесенкой» (1 — полная мера)
}
static var _tuned := {}
static var _grid_tex: ImageTexture

const GRID_TEX_PX := 128      # пикселей текстуры на метр (клетка 1 м)
const GRID_LINE_SIGMA := 1.8  # σ гауссова профиля линии, px (полная ширина по уровню ½ ≈ 3,3 см)


## Текстура клетки 1×1 м: линия по границе (гауссов профиль, не жёсткий порог), с мипмапами — издали линия тускнеет плавно. Рисуется один раз.
static func _grid_texture() -> ImageTexture:
	if _grid_tex == null:
		var n := GRID_TEX_PX
		var img := Image.create(n, n, false, Image.FORMAT_L8)
		for y in n:
			for x in n:
				var dx := minf(x + 0.5, n - (x + 0.5)) / GRID_LINE_SIGMA
				var dy := minf(y + 0.5, n - (y + 0.5)) / GRID_LINE_SIGMA
				var v := maxf(exp(-0.5 * dx * dx), exp(-0.5 * dy * dy))
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_grid_tex = ImageTexture.create_from_image(img)
	return _grid_tex


## Задать ручки (словарь «имя → значение»). Неизвестные имена игнорируются с предупреждением. Значения: числа, bool, цвет строкой.
static func tune(d: Dictionary) -> void:
	for k in d:
		if not KNOBS.has(k):
			push_warning("AssetMaterials.tune: неизвестная ручка '%s' (есть: %s)" % [k, ", ".join(KNOBS.keys())])
			continue
		var v: Variant = d[k]
		var def: Variant = KNOBS[k]
		if def is bool:
			v = (str(v).to_lower() == "true") if v is String else bool(v)
		elif def is float:
			v = float(v)
		else:
			v = str(v)
		_tuned[k] = v
	if _tuned.has("fringe_on"):
		fringe_on = _tuned["fringe_on"]


## Прочитать блок cfg (по умолчанию [assets]) и применить как tune(). Вызывать сразу после cfg.load(), до построения сцены.
static func tune_from_config(cfg: ConfigFile, section := "assets") -> void:
	if cfg == null or not cfg.has_section(section):
		return
	var d := {}
	for k in cfg.get_section_keys(section):
		d[k] = cfg.get_value(section, k)
	tune(d)


## Сбросить ручки к умолчаниям.
static func reset_tuning() -> void:
	_tuned = {}
	fringe_on = true


## Меш — плита пола/потолка/дальнего пласта (а не объём вроде укрытия, у которого боковые рёбра должны светиться): `slab`, `tiles`, `*_plates`.
static func _is_plate(mi: MeshInstance3D, _root: Node) -> bool:
	var n := String(mi.name)
	return n == "slab" or n == "tiles" or n.ends_with("_plates")


static func _k(name: String) -> Variant:
	return _tuned.get(name, KNOBS[name])

## Параметры haze.gdshader для `edge_mist` (env/room_edge_<N>): низкая дымка вдоль границы комнаты, не туман горизонта.
const EDGE_MIST := {"haze_alpha": 0.6, "glow": 1.6, "shape": 1.0, "noise_amount": 0.35, "stripe_amount": 0.12, "stripe_count": 160.0}

## Яркость подвесных штрихов кромки комнаты (`edge_streaks_hang`): у штрихов окружения glow 1,6.
const EDGE_STREAK_GLOW := 3.4  # было 2,6: в клиентской сцене граница комнаты читалась слабо

## Цвета тиров окружения (BASE/HARD/NIGHTMARE): голубая гамма, красный в тирах не участвует.
const TIER_TINT := {
	"BASE": Color("18e6ff"),
	"HARD": Color("2a7bff"),
	"NIGHTMARE": Color("8a5cff"),
}

## Фон «пустоты» между плитами: слабая тёмная бирюзовая дымка вместо чистого чёрного (решение владельца 07.10). Замер референсов CDPR
## (`pipeline.sh stats`, 06.10): dark ≈ 0 %, lum 19–25, hor 1,4–1,9; у наших кадров на старом фоне Color(0.004, 0.008, 0.016) dark 11–36 %.
## Цель по stats на кадрах окружения BASE: dark ≤ 5 %, lum ≤ ~28, cyan ≥ 85 %, blue < 5 %, hor ≥ 1,3. Это цвет очистки (Environment.background_color):
## бесплатно по перекрытию слоёв на Pico, в отличие от нового аддитивного купола. Клиент ставит `Environment.background_color = AssetMaterials.VOID_BG`.
## Чёрные плиты `solid_dark` остаются чёрными и читаются силуэтом на бирюзовом фоне. Подбор по кадрам room_inside / room_overview / edge_view (BASE): старый фон → этот
## даёт dark 38→31, 16→13, 28→21 %, lum 21→23, 26→27, 26→28, cyan и hor не хуже; остаток dark — чёрные плиты (пол комнаты — одна плита solid_dark, потолок), не фон.
const VOID_BG := Color(0.0, 0.10, 0.13)

## Мягкий ореол штрихов окружения (streaks.gdshader): яркость хвоста, расширение квада и затухание к концам. У ассетов без тира — 0.
const ENV_HALO := 0.4
const ENV_HALO_WIDTH := 2.5
const ENV_END_FADE := 0.6

## Решётка «объёмного дисплея» (решение владельца по эксперименту): сущности (аватар, ICE) выводятся на мировой решётке 4 см, мир не квантуется,
## иначе он теряет вариативность. Шаг 10 см ломает силуэт аватара. Определяется по пути сцены ассета.
const ENTITY_LATTICE := 0.04
const ENTITY_DIRS := ["/avatar/", "/ice/"]


static func _is_entity(root: Node) -> bool:
	for d in ENTITY_DIRS:
		if root.scene_file_path.contains(d):
			return true
	return false


## tier — "BASE"/"HARD"/"NIGHTMARE" для окружения (перекрашивает свечение); пусто — цвета из вершин (ICE, аватар, дека).
## Номер варианта пола по пути сцены (`.../floor_v3_8.glb` → 3), иначе 0.
static func _floor_variant(root: Node) -> int:
	var p := root.scene_file_path
	var i := p.find("/floor_v")
	if i < 0:
		return 0
	return int(p.substr(i + 8, 1))


static func apply(root: Node, tier: String = "") -> void:
	var entity := _is_entity(root)
	var fv := _floor_variant(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		if String(mi.name) == "slab_seams" and float(_k("floor_grid")) > 0.0:  # сетка текстурой заменяет облако точек швов (AssetBatch пропускает невидимые меши; материал всё равно ставим ниже)
			mi.visible = false
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null or not SHADERS.has(src.resource_name):
				continue
			var m := ShaderMaterial.new()
			m.shader = SHADERS[src.resource_name]
			if String(mi.name).ends_with("_skirt"):  # вуаль плит и дымка горизонта: роль shell_soft, но свой шейдер по имени меша
				m.shader = SKIRT_SHADER
			elif String(mi.name).ends_with("_glass"):
				m.shader = GLASS_SHADER
				m.set_shader_parameter("plate_size", mi.mesh.get_aabb().size.x)
			elif String(mi.name).ends_with("_mist"):
				m.shader = HAZE_SHADER
				if root.scene_file_path.contains("/room_edge_"):  # низкая дымка границы комнаты: профиль по высоте круче, штрихи по азимуту реже и слабее
					for k in EDGE_MIST:
						m.set_shader_parameter(k, EDGE_MIST[k])
			if String(mi.name) == "edge_streaks_hang":  # подвесные штрихи кромки комнаты (точек по периметру нет): ярче штрихов плит, иначе край не читается
				m.set_shader_parameter("glow", EDGE_STREAK_GLOW)
			if String(mi.name) == "pillar_block" or String(mi.name) == "pillar_base" or String(mi.name).begins_with("exit_bar"):  # укрытие (корпус и рамка по границе клетки) и брусья рамки выхода: рёбра ровные и яркие, иначе в очках не видно, где оно (у тайлов пола свет рваный намеренно)
				for k in PILLAR_EDGE:
					m.set_shader_parameter(k, PILLAR_EDGE[k])
				m.set_shader_parameter("edge_glow", _k("edge_glow"))  # ручка: яркость рёбер
			if fringe_on and (String(mi.name) == "pillar_block" or String(mi.name).begins_with("exit_bar") or String(mi.name) == "vault_body"):
				var lit := String(mi.name) != "vault_body"
				m.next_pass = _fringe_chain(0, _k("edge_glow") if lit else FRINGE_GLOW_DEFAULT)
			if src.resource_name == "solid_dark" and String(mi.name) == "slab" and float(_k("floor_grid")) > 0.0:  # ручка: сетка клеток текстурой (верх плиты пола)
				m.set_shader_parameter("grid_tex", _grid_texture())
				m.set_shader_parameter("grid_alpha", float(_k("floor_grid")))
			if src.resource_name == "solid_dark" and _is_plate(mi, root):  # ручки мерцания кромок плит (шейдер solid_dark)
				m.set_shader_parameter("rim_top_only", 1.0 if bool(_k("rim_top_only")) else 0.0)
				m.set_shader_parameter("plate_flat", 1.0 if bool(_k("plate_flat")) else 0.0)
				m.set_shader_parameter("rim_far_min", float(_k("rim_far_min")))
				m.set_shader_parameter("rim_far_start", float(_k("rim_far_start")))
				m.set_shader_parameter("rim_far_end", float(_k("rim_far_end")))
			if String(mi.name).ends_with("_skirt") and float(_k("skirt_top_fade")) > 0.0:  # ручка: вуаль отрывается от кромки плиты
				m.set_shader_parameter("top_fade", float(_k("skirt_top_fade")))
			if src.resource_name == "solid_dark" and float(_k("edge_soft")) > 0.0:  # ручка: кромка внутрь (лесенка силуэта)
				m.set_shader_parameter("edge_soft", float(_k("edge_soft")))
			if src.resource_name == "solid_dark" and String(_k("solid_base")) != "":  # ручка: цвет плит
				m.set_shader_parameter("base_color", Color(String(_k("solid_base"))))
			if src.resource_name == "streaks":  # ручка: минимальная ширина штриха в пикселях (антиалиасинг)
				m.set_shader_parameter("min_px", _k("min_px_streaks"))
			elif src.resource_name == "points":
				m.set_shader_parameter("min_px", _k("min_px_points"))
			if tier != "" and TIER_TINT.has(tier):
				m.set_shader_parameter("tint", TIER_TINT[tier])
				m.set_shader_parameter("tint_amount", 1.0)
				var fr := m.next_pass as ShaderMaterial
				while fr != null:  # обводка красится тиром так же, как кромка
					fr.set_shader_parameter("tint", TIER_TINT[tier])
					fr.set_shader_parameter("tint_amount", 1.0)
					fr = fr.next_pass as ShaderMaterial
			if tier != "" and src.resource_name == "streaks":  # окружение: мягкий ореол и длинное затухание к концам; существа и аватары — резкие, без ореола
				var far := root.scene_file_path.contains("/far_")  # дальние пласты (8+ м): ореол вдвое-втрое расширяет квады, а видны они как дымка и без него
				m.set_shader_parameter("halo", 0.0 if (far and not bool(_k("halo_far"))) else float(_k("halo")))
				m.set_shader_parameter("halo_width", float(_k("halo_width")))
				m.set_shader_parameter("end_fade", ENV_END_FADE)
				if float(_k("streak_far_min")) < 1.0:  # ручки ряби «эквалайзеров»: параметры не задаём, пока ручка не тронута (в шейдере они выключены)
					m.set_shader_parameter("far_dim_min", float(_k("streak_far_min")))
					m.set_shader_parameter("far_dim_start", float(_k("streak_far_start")))
					m.set_shader_parameter("far_dim_end", float(_k("streak_far_end")))
				if float(_k("streak_keep")) < 1.0:
					m.set_shader_parameter("keep_frac", float(_k("streak_keep")))
				if float(_k("streak_len")) != 1.0:
					m.set_shader_parameter("len_scale", float(_k("streak_len")))
				if float(_k("streak_px_fade")) > 0.0:
					m.set_shader_parameter("px_fade", float(_k("streak_px_fade")))
			if String(mi.name) == "beacon_halo":  # маяк предмета: капля свечения — свой шейдер; луч — streaks с ореолом (клиент выключает узел Beacon в руке)
				m.shader = BEACON_HALO_SHADER
			elif String(mi.name) == "beacon_beam":
				for k in BEACON_BEAM:
					m.set_shader_parameter(k, BEACON_BEAM[k])
			if entity and (src.resource_name == "streaks" or src.resource_name == "points"):
				m.set_shader_parameter("lattice", ENTITY_LATTICE)
			if String(mi.name).ends_with("_mid"):  # штрихи, симметричные вокруг центра (мембрана портала): длина меняется от центра
				m.set_shader_parameter("anchor", 0.0)
			if String(mi.name).ends_with("_hang"):  # подвесные штрихи (под полом): длина меняется от верхнего конца
				m.set_shader_parameter("anchor", 1.0)
			if FLOOR_V.has(fv):  # варианты пола: параметры по суффиксу меша, последними (поверх ореола и якоря)
				for suffix in FLOOR_V[fv]:
					if String(mi.name).ends_with(suffix):
						for k in FLOOR_V[fv][suffix]:
							m.set_shader_parameter(k, FLOOR_V[fv][suffix][k])
			mi.set_surface_override_material(s, m)


## Цепочка слоёв обводки (next_pass): слой i рисуется после слоя i−1, дальше — следующий.
static func _fringe_chain(i: int, glow: float) -> ShaderMaterial:
	var f := ShaderMaterial.new()
	f.shader = FRINGE_SHADER
	f.set_shader_parameter("px", float(FRINGE_LAYERS[i][0]) * float(_k("fringe_px")))
	f.set_shader_parameter("fringe_alpha", float(FRINGE_LAYERS[i][1]) * float(_k("fringe_alpha")))
	f.set_shader_parameter("edge_glow", glow)
	f.set_shader_parameter("edge_soft", float(_k("edge_soft")))
	if i + 1 < FRINGE_LAYERS.size():
		f.next_pass = _fringe_chain(i + 1, glow)
	return f


## Красный «шрам»: в радиусе вокруг точки (мировые координаты) свечение уходит в красный, часть клеток пропадает.
## Вызывать после apply(); radius = 0 выключает. Так ICE «ломает» соседнюю геометрию, а не рисует наклеенный эффект.
static func set_corruption(root: Node, world_pos: Vector3, radius: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("corrupt_pos", world_pos)
				m.set_shader_parameter("corrupt_radius", radius)


## Затухание по расстоянию до камеры (вместо depth-fade): дальние слои растворяются в темноте.
static func set_distance_fade(root: Node, start: float, end: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("fade_start", start)
				m.set_shader_parameter("fade_end", end)


## Общая яркость ассета (множитель): так делается отражение в полу (зеркальная копия с intensity ≈ 0.2).
static func set_intensity(root: Node, value: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("intensity", value)


## Параметр шейдера на всех материалах ассета (анимация и настройка из кода: touch_pos, touch_radius, breathe, pulse…).
static func set_param(root: Node, param: StringName, value: Variant) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader.get_shader_uniform_list().any(func(u): return u["name"] == param):
				m.set_shader_parameter(param, value)

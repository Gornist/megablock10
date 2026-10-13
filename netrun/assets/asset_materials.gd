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
const CLOUD_SHADER_2S := preload("res://assets/shaders/cloud_dark_2s.gdshader")  # то же, cull_disabled (ручка cloud_two_sided)
const CLOUD_SHADER := preload("res://assets/shaders/cloud_dark.gdshader")  # «облако без основы» (прототип, ручка cloud)
## Ореол-«капля» маяка предмета (меш `beacon_halo` в узле Beacon у шарда и токена): роль shell_soft, шейдер по имени меша.
const BEACON_HALO_SHADER := preload("res://assets/shaders/beacon_halo.gdshader")
## Луч маяка (меш `beacon_beam`): штрихи (streaks) с ореолом, но спокойнее обычных — почти без дыхания и качания, гладкий (без бусин), ярче, чтобы читаться с 3 м.
const BEACON_BEAM := {"halo": 0.5, "halo_width": 2.2, "end_fade": 0.6, "breathe": 0.08, "sway": 0.003, "bead_depth": 0.0, "glow": 2.2}

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
	"cell_vision_fill": Color(PAL_THREAT_HOT, 0.03),   # замер foyer_preview 08.10: смешивание линейное, α 0,04 в красном после sRGB — бурые (58,44,44); 0,03 с пульсом ≤ 0,05 ≈ (40,30,30)
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


## Параметры solid_dark.gdshader для `pillar_block`/`pillar_base` (env/pillar, env/cover) и `exit_bar_*` (env/exit_frame): свет рёбер. 1,0 — принятый на очках V10
## (прежние 2,2 пересвечивали ребро при MSAA в «белую жилу»); рёбра ровные — неравномерность и дрейф света убраны из шейдера целиком (рефактор B1).
const PILLAR_EDGE := {"edge_glow": 1.0}

## «Ручки для очков» (ARCHITECTURE §21): настройки, которые крутят на устройстве без пересборки ассетов — A/B за счёт смены netrun.cfg, блок [assets].
## Ручки читаются в момент `apply()` (создание материалов): вызывать `tune()` / `tune_from_config()` ДО построения окружения, один раз при старте.
## Имя → умолчание (то, что стоит в коде без ручек).
const KNOBS := {
	"min_px_streaks": 1.5,   # минимальная полная ширина штриха, px экрана (streaks.gdshader min_px)
	"min_px_points": 2.0,    # минимальный диаметр точки, px (points.gdshader min_px)
	"solid_base": "",        # цвет плит solid_dark «#rrggbb»; пусто — по умолчанию из шейдера
	"floor_grid": 0.35,      # сетка клеток 1 м ТЕКСТУРОЙ с мипмапами и анизотропией на плите пола (0 — выкл.; 0,3–0,5; точки швов slab_seams убраны в B2); по умолчанию ВКЛ.: так выглядит кадр Blender, иначе клиент — «другая игра»
	# Мерцание кромок плит пола/потолка/дальних пластов (две линии на расстоянии 3 см сходятся в пиксель). Меры независимы, комбинируются:
	"rim_top_only": true,    # светится только лицевая грань плиты, боковая полоска кромки погашена (одна линия вместо двух)
	"rim_far_min": 0.0,      # яркость кромки плит на дистанции ≥ rim_far_end (1 — не гасить; 0 — гасить полностью)
	"rim_far_start": 6.0,    # с какой дистанции, м, кромка плит начинает гаснуть
	"rim_far_end": 10.0,     # на какой дистанции, м, она достигает rim_far_min
	"rim_min_px": 4.0,       # гашение кромки плит по её ширине на экране, px (0 — выкл.): кромка уже ~0,35·N px гаснет совсем, от N px — полная; адаптируется к глазу Pico, в отличие от дистанции
	# «Облако без основы» (владелец 08.10, принято 12.10: вид C3a — облако на колоннах и реквизите, пол/потолок/дальние пласты — сплошной solid_dark; замер на очках: +0,26 мс на MSAA 2×).
	"cloud": 1.0,            # 0 — выкл. (сплошные грани solid_dark); 1 — грани реквизита становятся частицами с дырами (alpha_to_coverage, нужен MSAA 2×+; яркость = значение); см. cloud_dark.gdshader
	"cloud_edge_mix": 0.35,  # доля цвета неона у частиц рёбер/линий сетки (владелец: неона меньше)
	"dust_cell": 0.018,      # ширина ячейки облака, м (высота вдвое больше); владелец: частицы мельче и реже (C2: 0,35 читалось лучше)
	"dust_density": 0.35,    # доля ячеек с частицей на ровной грани вблизи (с пятнами dust_patch: проплешины и сгущения)
	"cloud_far": 0.0,        # цена a2c — в ПЛОЩАДИ материала, не в числе частиц (замер Pico): 1 — и дальние пласты far_* облаком (+3,4 мс), 0 — остаются сплошной тёмной гранью
	"cloud_floor": 0.0,      # 1 — и пол комнаты (floor*) облаком; 0 — остаётся solid_dark (чаще всего самая большая площадь на экране)
	"cloud_ceiling": 0.0,    # 1 — и потолок облаком; 0 — остаётся solid_dark
	"cloud_two_sided": 0.0,  # C3: 1 — cull_disabled (cloud_dark_2s): сквозь дыры передней грани видны задние грани объёма (владелец на очках: «рендерятся не все грани»); цена ≈ ×2 a2c-фрагментов реквизита
	# Рябь «эквалайзеров» (штрихи окружения, только при tier != ""; существа и аватары не трогаем). Меры независимы:
	"streak_far_min": 1.0,   # яркость штрихов на дистанции ≥ streak_far_end (1 — не гасить; 0,3 — ориентир), как кромка плит
	"streak_far_start": 8.0,
	"streak_far_end": 25.0,
	"streak_keep": 0.0,      # доля штрихов окружения, что остаются: 0 — не рисуются (решение владельца на очках; объекты уйдут из моделей в B2), 1 — все
	"streak_len": 1.0,       # длина штрихов окружения (0,6 — короче)
	"streak_px_fade": 0.0,   # 0…1: штрих уже ~2 px на экране тускнеет, а не «ползёт лесенкой» (1 — полная мера)
	"point_keep": 0.0,       # доля точек ОКРУЖЕНИЯ (tier ≠ ""): 0 — убрать все (решение владельца: вдали точки сильно мерцают); существа и аватары не трогаем
	"veil_scale": 1.0,       # множитель альфы вуали плит (`*_skirt`); 0 — меши скрываются совсем; > 1 — усилить (до 4): очки П5 одобрили вуаль у плит потолка
	# Завеса ВВЕРХ от верхней кромки плит пола и дальнего пола (квады в том же меше `*_skirt`, env._slab_rise). Включена по умолчанию (V10); клин у края комнаты — отдельная задача:
	"tile_glow": 3.0,        # множитель альфы завесы вверх относительно вуали (0 — выкл.; 1 — как вуаль потолка; 2–4 — заметнее); вуаль вниз не затрагивает
	"tile_glow_h": 1.0,      # высота завесы вверх относительно модельной (0,45 м в комнате, 1 м в дальнем полу): 0,5 — ниже, 2 — выше
	"edge_round": 1.0,       # 0…1: скруглить профиль света рёбер (smoothstep по яркости вершин): убирает излом на пике градиента — светлую «линию Маха» по середине голубой полосы; 1 — полностью (принято, замер 6 на очках)
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


## Меш — плита пола/потолка/дальнего пласта (а не объём вроде укрытия, у которого боковые рёбра должны светиться): `slab`, `tiles`, `*_plates`.
static func _is_plate(mi: MeshInstance3D, _root: Node) -> bool:
	var n := String(mi.name)
	return n == "slab" or n == "tiles" or n.ends_with("_plates")


static func _k(name: String) -> Variant:
	return _tuned.get(name, KNOBS[name])


## Охват облака (ручка cloud) по группам моделей по пути сцены: far_* / floor* / ceiling* — по своим ручкам (по умолчанию сплошные); ворота lockdown_gate* и вся дека (deck/)
## всегда сплошные: у ворот красная кромка — сигнал LOCKDOWN, облако перекрасило бы её в бирюзу, у деки на руке своя палитра и замера облака не было; остальное (колонны,
## укрытия, хранилище, рамка выхода, платформа…) — облако.
static func _cloud_scope_ok(root: Node) -> bool:
	var path := root.scene_file_path
	var base := path.get_file()
	if base.begins_with("lockdown_gate") or path.contains("/deck/"):
		return false
	if base.begins_with("far_"):
		return float(_k("cloud_far")) > 0.5
	if base.begins_with("floor"):
		return float(_k("cloud_floor")) > 0.5
	if base.begins_with("ceiling"):
		return float(_k("cloud_ceiling")) > 0.5
	return true

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

## Затухание штрихов окружения к концам (streaks.gdshader). Ореол штрихов убран (B1): в окружении штрихи не рисуются (streak_keep=0), у существ и аватаров его не было.
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
static func apply(root: Node, tier: String = "") -> void:
	var entity := _is_entity(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null or not SHADERS.has(src.resource_name):
				continue
			var m := ShaderMaterial.new()
			m.shader = SHADERS[src.resource_name]
			if String(mi.name).ends_with("_skirt"):  # вуаль плит: роль shell_soft, но свой шейдер по имени меша
				m.shader = SKIRT_SHADER
				# меш с завесой вверх (у пола: второй UV-слой с высотой, env._slab_rise) прячем целиком только если выключены обе вуали; иначе гасим квады в шейдере
				var am := mi.mesh as ArrayMesh
				var has_rise: bool = am != null and (am.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
				if has_rise:
					m.set_shader_parameter("rise_gain", float(_k("tile_glow")))
					m.set_shader_parameter("rise_scale", float(_k("tile_glow_h")))
				if float(_k("veil_scale")) <= 0.0 and not (has_rise and float(_k("tile_glow")) > 0.0):
					mi.visible = false
				elif float(_k("veil_scale")) != 1.0:
					m.set_shader_parameter("veil_scale", float(_k("veil_scale")))
			if String(mi.name) == "pillar_block" or String(mi.name) == "pillar_base" or String(mi.name).begins_with("exit_bar"):  # укрытие (корпус и рамка по границе клетки) и брусья рамки выхода: рёбра ровные и яркие, иначе в очках не видно, где оно (у тайлов пола свет рваный намеренно)
				for k in PILLAR_EDGE:
					m.set_shader_parameter(k, PILLAR_EDGE[k])
			if src.resource_name == "solid_dark":  # профиль света ребра: сглаженный (принято на очках; 0 — прежняя «палатка» с изломом на пике)
				m.set_shader_parameter("edge_round", float(_k("edge_round")))
			if src.resource_name == "solid_dark" and String(mi.name) == "slab" and float(_k("floor_grid")) > 0.0:  # ручка: сетка клеток текстурой (верх плиты пола)
				m.set_shader_parameter("grid_tex", _grid_texture())
				m.set_shader_parameter("grid_alpha", float(_k("floor_grid")))
			if src.resource_name == "solid_dark" and _is_plate(mi, root):  # ручки мерцания кромок плит (шейдер solid_dark)
				m.set_shader_parameter("rim_top_only", 1.0 if bool(_k("rim_top_only")) else 0.0)
				m.set_shader_parameter("rim_far_min", float(_k("rim_far_min")))
				m.set_shader_parameter("rim_far_start", float(_k("rim_far_start")))
				m.set_shader_parameter("rim_far_end", float(_k("rim_far_end")))
				m.set_shader_parameter("rim_min_px", float(_k("rim_min_px")))
			if src.resource_name == "solid_dark" and String(_k("solid_base")) != "":  # ручка: цвет плит
				m.set_shader_parameter("base_color", Color(String(_k("solid_base"))))
			if src.resource_name == "streaks":  # ручка: минимальная ширина штриха в пикселях (антиалиасинг)
				m.set_shader_parameter("min_px", _k("min_px_streaks"))
			elif src.resource_name == "points":
				m.set_shader_parameter("min_px", _k("min_px_points"))
				if tier != "" and float(_k("point_keep")) < 1.0:  # ручка: доля точек окружения
					m.set_shader_parameter("keep_frac", float(_k("point_keep")))
			if tier != "" and TIER_TINT.has(tier):
				m.set_shader_parameter("tint", TIER_TINT[tier])
				m.set_shader_parameter("tint_amount", 1.0)
			if tier != "" and src.resource_name == "streaks":  # окружение: длинное затухание к концам; существа и аватары — резкие
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
			if src.resource_name == "solid_dark" and float(_k("cloud")) > 0.0 and _cloud_scope_ok(root):  # прототип «облако без основы»: частицы с дырами вместо тёмной грани (нужен MSAA)
				m.shader = CLOUD_SHADER_2S if float(_k("cloud_two_sided")) > 0.5 else CLOUD_SHADER
				m.set_shader_parameter("glitch_tex", GlitchSprite.texture())
				m.set_shader_parameter("dust", float(_k("cloud")))
				m.set_shader_parameter("dust_cell", float(_k("dust_cell")))
				m.set_shader_parameter("dust_density", float(_k("dust_density")))
				m.set_shader_parameter("edge_mix", float(_k("cloud_edge_mix")))
				if String(mi.name) == "slab" and float(_k("floor_grid")) > 0.0:
					m.set_shader_parameter("grid_tex", _grid_texture())
					m.set_shader_parameter("grid_alpha", float(_k("floor_grid")))
			mi.set_surface_override_material(s, m)


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

class_name AssetMaterials
extends RefCounted
## Подмена материалов импортированного ассета «Сети» по имени роли (shell_soft, points, streaks, solid_dark)
## на ShaderMaterial из `res://assets/shaders/`. .glb аддитивное смешивание и шейдеры не переносит,
## поэтому ассет приходит с материалами-ролями, а вид задают эти шейдеры (STYLE.md, «Что отдаёт Blender, что делает Godot»).
## Подмена идёт на экземпляре (set_surface_override_material): импортированный меш не меняется.

const SHADERS := {
	"shell_soft": preload("res://assets/shaders/shell_soft.gdshader"),
	"points": preload("res://assets/shaders/points.gdshader"),
	"streaks": preload("res://assets/shaders/streaks.gdshader"),
	"solid_dark": preload("res://assets/shaders/solid_dark.gdshader"),
}

## Вуаль на гранях плит (меши `*_skirt` в floor*): в .glb у неё материал-роль shell_soft, а шейдер по имени меша — этот.
const SKIRT_SHADER := preload("res://assets/shaders/skirt.gdshader")
const SURFACE_CLOUD_GROUP := &"surface_clouds"   # меши с облаком на гранях (А): дыхание и отклик ставятся на их материалы
const CLOUD_A2C_SHADER := preload("res://assets/shaders/cloud_dark_a2c.gdshader")  # прежний вид облака: дыры через alpha_to_coverage, за гранью виден мир (ручка cloud_solid = 0)
const CLOUD_SHADER := preload("res://assets/shaders/cloud_dark.gdshader")  # «облако без основы»: вид реквизита (ручка cloud, умолчание 1; принято 12.10, облако (Б) на объектах — 14.10)
## Луч Soft ICE (меши `*_beam*` у датчика и `*_fan` у маяка, ice/sensor_ice и ice/lighthouse_ice): роль shell_soft, шейдер по имени меша; состояния — set_beam(root, state, flash).
const BEAM_SHADER := preload("res://assets/shaders/beam.gdshader")
## Состояния луча датчика (параметр `state` шейдера beam.gdshader).
const BEAM_OFF := 0
const BEAM_ON := 1
const BEAM_BLINK := 2
## Ореол-«капля» маяка предмета (меш `beacon_halo` в узле Beacon у шарда и токена): роль shell_soft, шейдер по имени меша.
const BEACON_HALO_SHADER := preload("res://assets/shaders/beacon_halo.gdshader")
## Вспышка ожога по краям зрения (П6-6 (г)): шейдер квада на камере (DangerCue); цвета — слои burn_flash/burn_flash_hot, форму и силу задаёт шейдер, Godot — только `strength`.
const BURN_FLASH_SHADER := preload("res://assets/shaders/burn_flash.gdshader")
const BURN_FLASH_START := 1.0   ## strength в момент ожога (было 0,85 у Godot — на П6 не заметили; форма шейдера теперь сама держит центр свободным)
const BURN_FLASH_SEC := 0.9     ## спад до 0 (было 0,7): ≈ 80 кадров при 90 Гц; вспышка одна на ожог, без повторов — VR-комфорт (STYLE.md п.7)
## Луч маяка (меш `beacon_beam`): штрихи (streaks) с ореолом, но спокойнее обычных — почти без дыхания и качания, гладкий (без бусин), ярче, чтобы читаться с 3 м.
const BEACON_BEAM := {"halo": 0.5, "halo_width": 2.2, "end_fade": 0.6, "breathe": 0.08, "sway": 0.003, "bead_depth": 0.0, "glow": 2.2}
## Пульс спящего логова Black ICE (ice/black_lair, State_sleep; П6-6 (в), владелец на П6: логова не заметил): холм `black_lair_mound` дышит глубоко и медленно (период ≈ 4 с),
## «сердце» `black_lair_heart` бьётся чаще (≈ 2,5 с) и размашистее — пульс читается от входа, но без стробоскопа (VR-комфорт, STYLE.md п.7: движение только у существ/предметов).
const LAIR_SLEEP_BREATHE := {
	"black_lair_mound": {"breathe": 0.55, "breathe_speed": 1.6},
	"black_lair_heart": {"breathe": 0.7, "breathe_speed": 2.5},
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
	# Луч Soft ICE (датчик, маяк): горит / погашен / вспышка срабатывания; мигание — состояние BEAM_BLINK тем же цветом beam_on
	"beam_on": PAL_THREAT_HOT,                     # луч включён (угроза: ICE видит)
	"beam_off": PAL_CYAN,                          # погашен: путь виден, пройти можно (голубое — «можно»; тусклый PAL_DIM на полу не читался, П6-6)
	"beam_flash": PAL_ICE,                         # вспышка срабатывания (одиночный импульс)
	"alarm_focus": PAL_THREAT_HOT,                 # тревога 2+: свет окружения у игрока (set_alarm_focus)
	"burn_flash": PAL_THREAT,                      # ожог: красный край поля зрения (burn_flash_material)
	"burn_flash_hot": PAL_THREAT_HOT,              # и яркий обод у самой границы
	# Облако частиц (Б), VolumeCloud: цвет облака объекта (файлы `.points`, ARCHITECTURE.md §13)
	"volume_ice": PAL_THREAT,                      # облако ICE (Soft и Black): красное, красное только у угрозы; у Black ICE ложится на синюю оболочку модели («красное внутри»)
	"volume_exit": PAL_ICE,                        # рамка выхода: брусья с кромкой ice_white
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


## Новый материал вспышки ожога для квада на камере (render_priority выше меток 100): клиент меняет только `strength` 0…1 (старт BURN_FLASH_START, спад за BURN_FLASH_SEC).
## half_fov — половина поля зрения камеры, рад.
static func burn_flash_material(half_fov := 0.95) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BURN_FLASH_SHADER
	m.render_priority = 105
	m.set_shader_parameter("strength", 0.0)
	m.set_shader_parameter("half_fov", half_fov)
	m.set_shader_parameter("tint", layer("burn_flash", 1.0))
	m.set_shader_parameter("hot", layer("burn_flash_hot", 1.0))
	return m


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
	# Мерцание кромок плит пола (две линии на расстоянии 3 см сходятся в пиксель). Меры независимы, комбинируются:
	"rim_top_only": true,    # светится только лицевая грань плиты, боковая полоска кромки погашена (одна линия вместо двух)
	"rim_far_min": 0.0,      # яркость кромки плит на дистанции ≥ rim_far_end (1 — не гасить; 0 — гасить полностью)
	"rim_far_start": 6.0,    # с какой дистанции, м, кромка плит начинает гаснуть
	"rim_far_end": 10.0,     # на какой дистанции, м, она достигает rim_far_min
	"rim_min_px": 4.0,       # гашение кромки плит по её ширине на экране, px (0 — выкл.): кромка уже ~0,35·N px гаснет совсем, от N px — полная; адаптируется к глазу Pico, в отличие от дистанции
	# «Облако без основы» (владелец 08.10, принято 12.10: вид C3a — облако на колоннах и реквизите, пол — сплошной solid_dark; замер на очках: +0,26 мс на MSAA 2×).
	"cloud": 1.0,            # 0 — выкл. (сплошные грани solid_dark); 1 — грани реквизита становятся частицами с дырами (alpha_to_coverage, нужен MSAA 2×+; яркость = значение); см. cloud_dark.gdshader
	"cloud_solid": 1.0,      # 1 (умолчание) — грань облака непрозрачна: просвет чёрный, мира за гранью не рисуется (19.10, владелец: «видно не должно быть то, что за колонной»), без alpha_to_coverage; 0 — прежние дыры через a2c
	"cloud_sky": 1.0,        # 1 (умолчание) — просветы непрозрачной грани облака показывают небо купола (грань выглядит прозрачной, мира за ней нет); 0 — чёрные просветы (cloud_solid = 1 откат: «чёрный солид» 20.10); нужен backdrop = 1
	"cloud_edge_mix": 0.35,  # доля цвета неона у частиц рёбер/линий сетки (владелец: неона меньше)
	"dust_cell": 0.018,      # ширина ячейки облака, м (высота вдвое больше); владелец: частицы мельче и реже (C2: 0,35 читалось лучше)
	"dust_density": 0.35,    # доля ячеек с частицей на ровной грани вблизи (с пятнами dust_patch: проплешины и сгущения)
	"dust_fill": 1.0,        # 1 (умолчание) — вдали (ячейка мельче dust_fill_lo px экрана) вместо зерна ровная заливка среднего света, от dust_fill_hi до dust_fill_lo px зерно растворяется в неё (рябь вдали и «граница отрисовки» на очках 18.10)
	"dust_fill_lo": 2.0,     # экранная ширина ячейки, px, ниже которой зерна нет совсем (на Pico: пол дальше ≈6 м); 0 у dust_fill — выкл.
	# Освещение облака (18.10, владелец: «частицы видны только в освещении, где света нет — нет и частиц»): источники приходят из клиента (set_cloud_lights); без них вид равномерный, как раньше.
	"cloud_light": 1.0,      # 0 — выкл. (равномерное облако), 1 — плотность и яркость частиц целиком по освещённости
	"lit_ambient": 0.08,     # доля плотности зерна в полной темноте (редкие пылинки)
	"lit_dim": 0.35,         # яркость частиц в темноте относительно освещённых
	"lit_edge": 0.4,         # линии сетки и рёбра в темноте: 1 — не гаснут, 0 — гаснут как зерно
	"lit_tint": 0.5,         # перекраска освещённых частиц цветом источника
	"dust_sharp": 1.0,       # 1 (умолчание) — прозрачность ячейки почти 0/1 (smoothstep по яркости спрайта): меньше дробной альфы и дитера a2c внутри ячейки (preview_shimmer, пол вблизи: 0,99 → 0,83); 0 — как раньше
	"dust_fill_hi": 4.0,     # выше неё зерно целое (ближе ≈3 м); между lo и hi — плавный переход
	# Фон-купол (BackdropDome, 19.10): ручки для A/B на очках без пересборки.
	"backdrop": 1.0,         # 0 — купола нет (как до 18.10: чистый прозрачный фон), 1 — есть
	"backdrop_haze": 1.0,    # множитель дымки у горизонта (0 — без дымки)
	"backdrop_dust": 0.5,    # яркость неподвижных пылинок (0 — без них)
	"dust_fps": 0.0,        # смен кадра глитч-спрайта у ячейки облака в секунду; 0 — постоянный кадр (рябь на очках 17.10: было 10), для A/B на устройстве можно вернуть 1–3 (волна из нескольких кадров, а не мельтешение)
	# «Всё из частиц» (#424, владелец 17.10): пол по умолчанию тоже облако. ЦЕНА НЕ ИЗМЕРЕНА НА ОЧКАХ (MSAA 4×: цена a2c в ПЛОЩАДИ материала, не в числе частиц),
	# бюджет владельца +1,0 мс при 90 Гц. Потолка и дальних пластов нет с 18.10 (STYLE.md), ручек cloud_far/cloud_ceiling тоже. Не влезаем — cloud_floor 0.
	"cloud_floor": 1.0,      # 1 (умолчание) — пол комнаты (floor*) облаком, линии клеток 1 м остаются (grid_tex в cloud_dark); 0 — solid_dark (цена +? мс НЕ ИЗМЕРЕНА на очках, пол — самая большая площадь)
	"floor_density": 0.6,    # множитель плотности зерна облачного пола (меш slab; dust_density × floor_density), 1 — как dust_density у реквизита: пол плотнее и ярче низких объектов на нём (#424, Ш5); линии клеток 1 м (grid_tex, вес ребра) НЕ гасятся
	# Штрихи и точки окружения (tier != ""; существа и аватары не трогаем): 0 — не рисуются (рамка выхода exit_frame ещё несёт штрихи и точки; решение владельца на очках П5). Ручки гашения по дистанции, длины и ширинного гашения штрихов удалены 19.10: при streak_keep=0 не действовали.
	"streak_keep": 0.0,      # доля штрихов окружения, что остаются: 0 — не рисуются (решение владельца на очках; объекты уйдут из моделей в B2), 1 — все
	"point_keep": 0.0,       # доля точек ОКРУЖЕНИЯ (tier ≠ ""): 0 — убрать все (решение владельца: вдали точки сильно мерцают); существа и аватары не трогаем
	"veil_scale": 1.0,       # множитель альфы вуали плит (`*_skirt`); 0 — меши скрываются совсем; > 1 — усилить (до 4): очки П5 одобрили вуаль у плит потолка
	# Завеса ВВЕРХ от верхней кромки плит пола (квады в том же меше `*_skirt`, env._slab_rise). Включена по умолчанию (V10); клин у края комнаты — отдельная задача:
	"tile_glow": 3.0,        # множитель альфы завесы вверх относительно вуали (0 — выкл.; 1 — как вуаль потолка; 2–4 — заметнее); вуаль вниз не затрагивает
	"tile_glow_h": 1.0,      # высота завесы вверх относительно модельной (0,45 м): 0,5 — ниже, 2 — выше
	# Дыхание и отклик объёмного облака (Б): включаются вызовом set_cloud_breath / set_cloud_touch из клиента каждый кадр; без вызова облако статично, как раньше.
	"cloud_breath": 0.6,     # глубина дыхания 0…1 (0 — выкл.): вдох на тике хода, яркость облака ≈ ×0,73…×1,21, размер до +15 %
	"cloud_touch": 1.0,      # сила отклика на руку/аватар 0…2 (0 — выкл.): рядом частицы ярче, крупнее, теплее по цвету и чуть расходятся
	"edge_round": 1.0,       # 0…1: скруглить профиль света рёбер (smoothstep по яркости вершин): убирает излом на пике градиента — светлую «линию Маха» по середине голубой полосы; 1 — полностью (принято, замер 6 на очках)
}
static var _tuned := {}
## Имя меша сплошной подложки под облачным полом (src/floor_slab.py): облачная ветка apply() его пропускает.
const UNDER_SLAB := "floor_slab_under"
## Материалы с облаком на гранях (А), созданные apply(), слабыми ссылками: дыхание и отклик ставятся на них, где бы ни жил меш. Группа surface_clouds ловит только
## MeshInstance3D в дереве, а колонны, укрытия и корпуса препятствий клиент собирает из частей `NodeAssets.mesh_parts` (MultiMesh и свои MeshInstance3D без группы;
## корень с группой освобождён) — по группе они не дышали (П7-3, 17.10).
static var _surface_cloud_mats: Array[WeakRef] = []
## Источники света узла (set_cloud_lights), упакованные для шейдера: pos[i] = (xyz, радиус), col[i] = (rgb, сила), n — число; материалам, созданным позже, отдаются в apply().
static var _lights_pos := PackedVector4Array()
static var _lights_col := PackedVector4Array()
static var _lit_tex: ImageTexture
static var _lit_rect := Vector4(0.0, 0.0, 1.0, 1.0)
const LIT_TEXEL := 0.125   # м на тексель карты освещённости
const CLOUD_LIGHTS_MAX := 12
## Материалы окружения с перекраской света у игрока (alarm_focus.gdshaderinc: solid_dark, cloud_dark, skirt), созданные apply() вне существ/аватаров; слабые ссылки, как выше.
static var _focus_mats: Array[WeakRef] = []
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


## Меш — плита пола (а не объём вроде укрытия, у которого боковые рёбра должны светиться): `slab`, `tiles`, `*_plates`.
static func _is_plate(mi: MeshInstance3D, _root: Node) -> bool:
	var n := String(mi.name)
	return n == "slab" or n == "tiles" or n.ends_with("_plates")


## Значение ручки по имени (умолчание, если не задана) — для клиента и фона-купола.
static func knob(name: String) -> Variant:
	return _k(name)


## Небо купола (BackdropDome) для просветов граней облака: свет пустоты по тревоге запоминается и отдаётся материалам, созданным позже.
static var _sky_void := Color(0.0, 0.0, 0.0)


## Параметры неба (дымка, цвет пустоты; у купола ещё текстура и яркость пылинок) в материал купола или облака — по ручкам backdrop_haze / backdrop_dust.
static func sky_params(m: ShaderMaterial) -> void:
	m.set_shader_parameter("sky_haze_gain", float(_k("backdrop_haze")))
	m.set_shader_parameter("sky_void", _sky_void)
	m.set_shader_parameter("sky_dust_tex", BackdropDome.dust_texture())
	m.set_shader_parameter("sky_dust_gain", float(_k("backdrop_dust")))


## Свет пустоты по тревоге: звать из BackdropDome.set_alarm; облачным материалам просветов отдаётся тот же цвет.
static func set_sky_void(tree: SceneTree, c: Color) -> void:
	_sky_void = c
	for m in _cloud_materials(tree):
		m.set_shader_parameter("sky_void", c)


## Шейдер облака — любой из двух вариантов (непрозрачный по умолчанию, a2c при cloud_solid = 0).
static func _is_cloud_shader(sh: Shader) -> bool:
	return sh == CLOUD_SHADER or sh == CLOUD_A2C_SHADER


static func _k(name: String) -> Variant:
	return _tuned.get(name, KNOBS[name])


## Охват облака (ручка cloud) по группам моделей по пути сцены: floor* — по ручке cloud_floor (с 17.10 облако); вся дека (deck/)
## всегда сплошная: на руке своя палитра и замера облака не было; остальное (колонны, укрытия, хранилище, рамка выхода, платформа…) — облако.
## «Всё из частиц» (#424, 17.10): облако и у снаряжения ICE (`/ice/`: маяк, излучатель датчика, будка, логово) и у ворот lockdown_gate*, но КРАСНОЕ (`_is_threat_gear`): красное
## только у угрозы, а ворота и снаряжение ICE — угроза; бирюзой они перестали бы читаться как сигнал. Сами существа ICE (Б, облако из .points) этой веткой не затрагиваются.
static func _cloud_scope_ok(root: Node) -> bool:
	var path := root.scene_file_path
	var base := path.get_file()
	if path.contains("/deck/"):
		return false
	if base.begins_with("floor"):
		return float(_k("cloud_floor")) > 0.5
	return true


## Снаряжение ICE (`/ice/`) и ворота LOCKDOWN (`lockdown_gate*`): облако красное, а не бирюзовое (красный — только у угрозы).
static func _is_threat_gear(root: Node) -> bool:
	var path := root.scene_file_path
	return path.contains("/ice/") or path.get_file().begins_with("lockdown_gate")


## Красные цвета облака угрозы (слой volume_ice + светлый красный для горячих частиц, кромок и касания) — задаются в apply() вместо бирюзовых умолчаний шейдера.
static func _paint_threat_cloud(m: ShaderMaterial) -> void:
	var hot := PAL_THREAT_HOT
	m.set_shader_parameter("dust_color", layer("volume_ice"))
	m.set_shader_parameter("dust_hot", hot)
	m.set_shader_parameter("edge_color", hot)
	m.set_shader_parameter("touch_color", Vector3(hot.r, hot.g, hot.b))  # vec3 без source_color: значения как есть


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

## ВИД ТРЕВОГИ УЗЛА 0–4 (docs/gamedesign/ice.md §4, §8: «цвет фона узла сдвигается» — главный сигнал). Уровень приходит от Godot (`alert_level`, `AlarmLevels`):
## 0 спокойно — без изменений; 1 насторожен — лёгкий сдвиг фона; 2 тревога — заметно теплее; 3 охота — красный оттенок и пульс в ритме такта; 4 локдаун — фон на максимуме.
## Это ЦВЕТ ФОНА (Environment.background_color, бесплатно по перекрытию слоёв, как VOID_BG) и тёплый сдвиг кромок окружения (`set_alarm`): кадр не заливается красным
## (красный — только у угрозы, STYLE.md п.4; на 3–4 уровнях угроза и есть узел). Доли смеси фона к ALARM_BG_RED и кромок окружения к PAL_THREAT_HOT — по уровням 0…4.
const ALARM_BG_RED := Color(0.16, 0.015, 0.03)
const ALARM_BG_MIX := [0.0, 0.14, 0.34, 0.58, 0.92]
const ALARM_EDGE_MIX := [0.0, 0.0, 0.22, 0.5, 0.85]
## Пульс фона «охоты» (уровень 3): глубина модуляции яркости и форма (острая вспышка к началу такта и спад); фаза такта 0…1 даёт игра (доля прошедшего такта).
const ALARM_PULSE_DEPTH := 0.18
## Тир окружения нужен, чтобы сдвигать от его цвета: BASE голубой, HARD синий, NIGHTMARE фиолетовый (TIER_TINT).


## Цвет фона узла на уровне тревоги level (0…4); tick_phase 0…1 — доля прошедшего такта (пульс только у уровня 3, «охота»; у остальных не нужен — 0).
static func alarm_background(level: int, tick_phase := 0.0) -> Color:
	var l := clampi(level, 0, 4)
	var base := VOID_BG.lerp(ALARM_BG_RED, float(ALARM_BG_MIX[l]))
	if l == 3:
		var pulse := pow(1.0 - clampf(tick_phase, 0.0, 1.0), 2.0)   # вспышка в начале такта, к концу гаснет
		base = base * (1.0 - ALARM_PULSE_DEPTH + ALARM_PULSE_DEPTH * 2.0 * pulse)
	return Color(base.r, base.g, base.b, 1.0)


## Сдвиг кромок окружения к тёплому по уровню тревоги: звать на корне ОКРУЖЕНИЯ (пол, колонны), не на ICE/аватарах. Тир задаёт исходный цвет
## (`tier`: BASE, HARD, NIGHTMARE), уровень 0 возвращает его. Действует на материалы с `tint`/`edge_color` (solid_dark, skirt, streaks, points, cloud).
static func set_alarm(root: Node, level: int, tier := "BASE") -> void:
	var l := clampi(level, 0, 4)
	var c := _alarm_edge_color(TIER_TINT.get(tier, TIER_TINT["BASE"]), float(ALARM_EDGE_MIX[l]))
	set_param(root, &"tint", c)
	set_param(root, &"edge_color", c)


## Тревога у игрока (П6-6 (б), ice.md §8 «Правило П6»): на уровне 2+ свет кромок, сетки пола и облака в радиусе вокруг игрока уходит в тревожный цвет (`alarm_focus`) —
## сдвиг цвета виден там, куда смотрят, без сравнения «до/после». Звать каждый кадр с позицией игрока (мир); уровень 0–1 и радиус 0 выключают. Состояния нет: ушёл игрок — след сходит
## вместе с ним. Действует на материалы окружения, созданные apply() (реестр, дерево не обходится); существа и аватары не трогает.
const ALARM_FOCUS_RADIUS := [0.0, 0.0, 3.5, 5.0, 7.0]
const ALARM_FOCUS_GAIN := [0.0, 0.0, 1.35, 1.55, 1.8]
static func set_alarm_focus(world_pos: Vector3, level: int) -> void:
	var l := clampi(level, 0, 4)
	var alive: Array[WeakRef] = []
	for w in _focus_mats:
		var m := w.get_ref() as ShaderMaterial
		if m == null:
			continue
		alive.append(w)
		m.set_shader_parameter("focus_pos", world_pos)
		m.set_shader_parameter("focus_radius", float(ALARM_FOCUS_RADIUS[l]))
		m.set_shader_parameter("focus_gain", float(ALARM_FOCUS_GAIN[l]))
		m.set_shader_parameter("focus_color", layer("alarm_focus"))
	_focus_mats = alive


## Цвет кромок на доле t пути от цвета тира к красному: поворот ОТТЕНКА через синий и фиолетовый (а не линейная смесь RGB: голубое + красное = серое, STYLE.md п.4:
## «серого посередине быть не должно»). Насыщенность и яркость идут линейно к PAL_THREAT_HOT.
static func _alarm_edge_color(base: Color, t: float) -> Color:
	if t <= 0.0:
		return base
	var h0 := base.h
	var h1 := 1.0 + PAL_THREAT_HOT.h   # красный как «1.0 + h»: идём вперёд по кругу (голубой → синий → фиолетовый → красный)
	if h1 < h0:
		h1 += 1.0
	var h := fposmod(lerpf(h0, h1, t), 1.0)
	return Color.from_hsv(h, lerpf(base.s, PAL_THREAT_HOT.s, t), lerpf(base.v, PAL_THREAT_HOT.v, t))

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
				if float(_k("streak_keep")) < 1.0:
					m.set_shader_parameter("keep_frac", float(_k("streak_keep")))
			if String(mi.name).ends_with("_fan") or String(mi.name).contains("_beam"):  # луч Soft ICE (датчик, маяк): свой шейдер, цвета — слои beam_*; состояния — set_beam
				m.shader = BEAM_SHADER
				m.set_shader_parameter("on_color", layer("beam_on"))
				m.set_shader_parameter("off_color", layer("beam_off"))
				m.set_shader_parameter("flash_color", layer("beam_flash"))
				m.set_shader_parameter("fan", 1.0 if String(mi.name).ends_with("_fan") else 0.0)
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
			if src.resource_name == "streaks" and LAIR_SLEEP_BREATHE.has(String(mi.name)):  # спящее логово Black ICE (П6-6 (в)): холм дышит медленно и глубоко, «сердце» бьётся чаще — пульс виден от входа
				for k in LAIR_SLEEP_BREATHE[String(mi.name)]:
					m.set_shader_parameter(k, LAIR_SLEEP_BREATHE[String(mi.name)][k])
			if src.resource_name == "solid_dark" and String(mi.name) != UNDER_SLAB and float(_k("cloud")) > 0.0 and _cloud_scope_ok(root):  # floor_slab_under — сплошная подложка под облачным полом (#424 Ш5): solid_dark при любом cloud;  # прототип «облако без основы»: частицы с дырами вместо тёмной грани (нужен MSAA)
				m.shader = CLOUD_SHADER if float(_k("cloud_solid")) > 0.0 else CLOUD_A2C_SHADER
				mi.add_to_group(SURFACE_CLOUD_GROUP)   # set_cloud_breath / set_cloud_touch находят поверхностные облака по группе и по реестру материалов
				_surface_cloud_mats.append(weakref(m))
				m.set_shader_parameter("glitch_tex", GlitchSprite.texture())
				m.set_shader_parameter("dust", float(_k("cloud")))
				m.set_shader_parameter("dust_cell", float(_k("dust_cell")))
				m.set_shader_parameter("dust_fps", float(_k("dust_fps")))
				m.set_shader_parameter("dust_fill", float(_k("dust_fill")))
				m.set_shader_parameter("dust_fill_lo", float(_k("dust_fill_lo")))
				m.set_shader_parameter("dust_fill_hi", float(_k("dust_fill_hi")))
				m.set_shader_parameter("dust_sharp", float(_k("dust_sharp")))
				_push_cloud_light_knobs(m)
				sky_params(m)
				m.set_shader_parameter("sky_fill", 1.0 if float(_k("cloud_sky")) > 0.0 and float(_k("backdrop")) > 0.0 else 0.0)
				_push_lights(m)
				m.set_shader_parameter("dust_density", float(_k("dust_density")) * (float(_k("floor_density")) if String(mi.name) == "slab" else 1.0))
				m.set_shader_parameter("edge_mix", float(_k("cloud_edge_mix")))
				if _is_threat_gear(root):
					_paint_threat_cloud(m)
				if String(mi.name) == "slab" and float(_k("floor_grid")) > 0.0:
					m.set_shader_parameter("grid_tex", _grid_texture())
					m.set_shader_parameter("grid_alpha", float(_k("floor_grid")))
			mi.set_surface_override_material(s, m)
			if not entity and (m.shader == SHADERS["solid_dark"] or _is_cloud_shader(m.shader) or m.shader == SKIRT_SHADER):
				_focus_mats.append(weakref(m))


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


## Состояние луча Soft ICE (датчик, маяк): state — BEAM_OFF / BEAM_ON / BEAM_BLINK, flash 0…1 — вспышка срабатывания (одиночный импульс, длину задаёт игра).
## Действует на меши `*_beam*` и `*_fan` ассета; остальные материалы не трогает.
static func set_beam(root: Node, state: int, flash: float = 0.0) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader == BEAM_SHADER:
				m.set_shader_parameter("state", float(state))
				m.set_shader_parameter("flash", clampf(flash, 0.0, 1.0))


## Доля такта хода 0…1 (0 — тик, к 1 — следующий тик) по полю состояния `tk` {at, win} и серверному времени сейчас. Вне окна (опоздали) — зажимается в 0…1,
## чтобы облако не «перескакивало» при задержке тика. win ≤ 0 — 0.
static func tick_phase(tk: Dictionary, server_now: float) -> float:
	var win := float(tk.get("win", 0.0))
	if win <= 0.0:
		return 0.0
	return clampf((server_now - float(tk.get("at", server_now))) / win, 0.0, 1.0)


## Материалы облаков: объёмных (VolumeCloud, группа `volume_clouds`; материал лежит на QuadMesh внутри MultiMesh) и поверхностных (А: cloud_dark) — из группы
## `surface_clouds` (меши в дереве) и из реестра материалов apply() (MultiMesh и рантайм-меши из частей mesh_parts); общий материал берётся один раз.
static func _cloud_materials(tree: SceneTree) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if tree == null:
		return out
	var seen := {}
	for n in tree.get_nodes_in_group(SURFACE_CLOUD_GROUP):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var sm := mi.get_surface_override_material(s) as ShaderMaterial
			if sm != null and _is_cloud_shader(sm.shader) and not seen.has(sm.get_instance_id()):
				seen[sm.get_instance_id()] = true
				out.append(sm)
	var alive: Array[WeakRef] = []
	for w in _surface_cloud_mats:
		var rm := w.get_ref() as ShaderMaterial
		if rm == null:
			continue
		alive.append(w)
		if _is_cloud_shader(rm.shader) and not seen.has(rm.get_instance_id()):
			seen[rm.get_instance_id()] = true
			out.append(rm)
	_surface_cloud_mats = alive
	for n in tree.get_nodes_in_group("volume_clouds"):
		for c in n.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
				continue
			var m := mmi.multimesh.mesh.material as ShaderMaterial
			if m != null:
				out.append(m)
	return out


## Дыхание облаков: phase — доля такта хода (`tick_phase`), вдох — на тике. Звать каждый кадр; глубина — ручка cloud_breath. Руки и тело не затрагиваются.
static func set_cloud_breath(tree: SceneTree, phase: float) -> void:
	var depth := clampf(float(_k("cloud_breath")), 0.0, 1.0)
	for m in _cloud_materials(tree):
		m.set_shader_parameter("breath_depth", depth)
		m.set_shader_parameter("breath_phase", clampf(phase, 0.0, 1.0))


## Невидимые источники света узла (решение владельца 18.10): частицы поверхностного облака видны там, где свет. Звать один раз при построении или смене узла (не каждый кадр);
## пустой массив — источников нет, облако равномерное, как раньше. Элемент: {"p": Vector3 мир, м; "r": float радиус влияния, м; "s": float сила (1); "c": Color цвет (бирюзово-белый)};
## не больше CLOUD_LIGHTS_MAX (лишние отбрасываются с предупреждением). Запоминается и отдаётся облачным материалам, созданным позже. Рука и аватар освещают через set_cloud_touch.
static func set_cloud_lights(tree: SceneTree, lights: Array) -> void:
	_lights_pos = PackedVector4Array()
	_lights_col = PackedVector4Array()
	if lights.size() > CLOUD_LIGHTS_MAX:
		push_warning("AssetMaterials.set_cloud_lights: %d источников, берём первые %d" % [lights.size(), CLOUD_LIGHTS_MAX])
	for l in lights.slice(0, CLOUD_LIGHTS_MAX):
		var p: Vector3 = l.get("p", Vector3.ZERO)
		var c: Color = l.get("c", Color(0.8, 0.97, 1.0))
		_lights_pos.append(Vector4(p.x, p.y, p.z, maxf(float(l.get("r", 3.0)), 0.01)))
		_lights_col.append(Vector4(c.r, c.g, c.b, float(l.get("s", 1.0))))
	_build_lit_map()
	for m in _cloud_materials(tree):
		if _is_cloud_shader(m.shader):
			_push_lights(m)


## Источники света узла, как их приняло облако: [{"p", "r", "s", "c"}] (для тестов и отладки).
static func cloud_lights() -> Array:
	var out := []
	for i in _lights_pos.size():
		var a := _lights_pos[i]
		var b := _lights_col[i]
		out.append({"p": Vector3(a.x, a.y, a.z), "r": a.w, "s": b.w, "c": Color(b.x, b.y, b.z)})
	return out


static func _push_lights(m: ShaderMaterial) -> void:
	m.set_shader_parameter("cl_n", _lights_pos.size())
	if _lit_tex != null:
		m.set_shader_parameter("lit_map", _lit_tex)
		m.set_shader_parameter("lit_rect", _lit_rect)


## Карта освещённости по XZ (RGBA8): источники «splat» в окно по радиусу, побеждает сильнейший (цвет и сила), форма спада та же, что была в шейдере:
## (1 − smoothstep(0,15·r … r, расстояние)) · сила. Строится один раз на смену узла (≈20 тыс. операций), в шейдере — одна выборка вместо 12 расчётов на фрагмент.
static func _build_lit_map() -> void:
	_lit_tex = null
	if _lights_pos.is_empty():
		return
	var x0 := INF
	var z0 := INF
	var x1 := -INF
	var z1 := -INF
	for l in _lights_pos:
		x0 = minf(x0, l.x - l.w)
		z0 = minf(z0, l.z - l.w)
		x1 = maxf(x1, l.x + l.w)
		z1 = maxf(z1, l.z + l.w)
	var w := maxi(int(ceil((x1 - x0) / LIT_TEXEL)), 8)
	var h := maxi(int(ceil((z1 - z0) / LIT_TEXEL)), 8)
	w = mini(w, 256)
	h = mini(h, 256)
	var sx := (x1 - x0) / float(w)
	var sz := (z1 - z0) / float(h)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var best := PackedFloat32Array()
	best.resize(w * h)
	for i in _lights_pos.size():
		var l := _lights_pos[i]
		var cc := _lights_col[i]
		var ix0 := clampi(int(floor((l.x - l.w - x0) / sx)), 0, w - 1)
		var ix1 := clampi(int(ceil((l.x + l.w - x0) / sx)), 0, w - 1)
		var iz0 := clampi(int(floor((l.z - l.w - z0) / sz)), 0, h - 1)
		var iz1 := clampi(int(ceil((l.z + l.w - z0) / sz)), 0, h - 1)
		for iz in range(iz0, iz1 + 1):
			var pz := z0 + (float(iz) + 0.5) * sz
			for ix in range(ix0, ix1 + 1):
				var px := x0 + (float(ix) + 0.5) * sx
				var k := (1.0 - smoothstep(0.15 * l.w, l.w, Vector2(px - l.x, pz - l.z).length())) * cc.w
				if k > best[iz * w + ix]:
					best[iz * w + ix] = k
					img.set_pixel(ix, iz, Color(cc.x, cc.y, cc.z, clampf(k, 0.0, 1.0)))
	_lit_tex = ImageTexture.create_from_image(img)
	_lit_rect = Vector4(x0, z0, 1.0 / (x1 - x0), 1.0 / (z1 - z0))


static func _push_cloud_light_knobs(m: ShaderMaterial) -> void:
	m.set_shader_parameter("lit_strength", float(_k("cloud_light")))
	m.set_shader_parameter("lit_ambient", float(_k("lit_ambient")))
	m.set_shader_parameter("lit_dim", float(_k("lit_dim")))
	m.set_shader_parameter("lit_edge", float(_k("lit_edge")))
	m.set_shader_parameter("lit_tint", float(_k("lit_tint")))


## Отклик облаков на приближение: sources — до четырёх Vector4 (xyz — мировая позиция руки/аватара, w — радиус влияния, м; 0 — выкл.). Остальные слоты гасятся.
## Звать каждый кадр (состояния нет: ушёл источник — облако как было). Сила — ручка cloud_touch; 0 гасит все слоты.
static func set_cloud_touch(tree: SceneTree, sources: Array) -> void:
	var on := float(_k("cloud_touch"))
	var slots := [&"touch_a", &"touch_b", &"touch_c", &"touch_d"]
	var mats := _cloud_materials(tree)
	for m in mats:
		for i in slots.size():
			var v := Vector4.ZERO
			if on > 0.0 and i < sources.size():
				v = sources[i]
			m.set_shader_parameter(slots[i], v)
		m.set_shader_parameter("touch_gain", 1.2 * on)
		m.set_shader_parameter("touch_grow", 0.8 * on)
		m.set_shader_parameter("touch_push", 0.025 * on)


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

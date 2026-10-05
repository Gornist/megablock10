extends Node3D
## Снимки ассетов «Сети» для приёмки: расставляет ассеты, применяет шейдеры (AssetMaterials) и сохраняет PNG.
## Запуск на devbox в окне (нужен GPU): godot --path <проект> --resolution 1280x720 -- --out=<каталог для PNG>
## Вид проверяем только здесь: вьюпорт Blender аддитивные материалы не показывает. Частота кадров на Pico 4 не проверяется.

const AM := preload("res://assets/asset_materials.gd")
const BG := Color(0.004, 0.008, 0.016)

## Комната 6×6 м из модулей 2×2 м: пол 3×3, стены по периметру, колонны в углах, вход с юга (z=+3), выход на север (z=-3),
## в центре шард, у выхода ICE. Предмет: [путь, позиция, поворот Y (°), тир, масштаб].
const REFLECT := ["props/vault_closed", "props/vault_open", "props/portal", "props/portal_locked", "env/wall", "env/wall_b", "env/wall_c", "env/portal_wall", "env/far_field", "env/far_field_b", "env/far_field_c", "env/doorway", "env/doorway_b", "env/pillar", "ice/soft_ice", "avatar/runner", "avatar/runner_b", "avatar/runner_c"]
const CEILING_H := 5.0
const LAYER_PITCH := 7.0  # шаг между пластами данных: потолок 5 м + 2 м пустоты
const ICE_POS := Vector3(1.0, 0.0, -2.8)
## Яркий горизонт (STYLE.md, ARCHITECTURE.md «Ореол и горизонт»): дальние пласты (env/far_*) и кольцо env/horizon_band не гаснут в чёрный
## на 14…40 м, а светятся: затухание отодвинуто, яркость растёт с расстоянием (far_gain от far_start до far_end).
const FAR_FADE := [40.0, 130.0]
const FAR_GAIN := 1.8
const FAR_GAIN_RANGE := [20.0, 60.0]
const HORIZON_FADE := [150.0, 260.0]
const HORIZON_GAIN := 3.0


func _room() -> Array:
	var items: Array = []
	var g := [-3.0, -1.0, 1.0, 3.0]  # центры модулей 2×2 м: комната 8×8 м = 4×4 модуля
	var variants := ["env/floor", "env/floor_b", "env/floor_c"]
	var n := 0
	for x in g:
		for z in g:
			var clear: bool = absf(x) < 1.5 and absf(z) < 1.5  # четыре модуля вокруг хранилища без тайлов: оно не теряется среди плиток
			items.append(["env/floor_clear" if clear else variants[n % 3], Vector3(x, 0, z), 90.0 * (n % 4), "BASE", 1.0])  # вариант и поворот по кругу: узор не повторяется
			n += 1
	var cv := ["env/ceiling", "env/ceiling_b", "env/ceiling_c"]
	var m := 0
	for x in g:
		for z in g:
			items.append([cv[m % 3], Vector3(x, CEILING_H, z), 90.0 * ((m + 1) % 4), "BASE", 1.0])  # потолок: тот же принцип, что у пола, инвертированный
			m += 1
	if _walls:  # стены-занавесы (wall, wall_b, wall_c, portal_wall) и проёмы (doorway, doorway_b) — временно по флагу --walls, по умолчанию комната открыта к горизонту
		var wv := ["env/wall", "env/wall_b", "env/wall_c"]
		var k := 0
		for x in g:
			if x != -1.0:  # (−1, 4) — вход
				items.append([wv[k % 3], Vector3(x, 0, 4.0), 180.0 * (k % 2), "BASE", 1.0])
			k += 1
			if x != 1.0:  # (1, −4) — выход
				items.append([wv[k % 3], Vector3(x, 0, -4.0), 180.0 * (k % 2), "BASE", 1.0])
			k += 1
		for z in g:
			items.append([wv[k % 3], Vector3(4.0, 0, z), 90.0 + 180.0 * (k % 2), "BASE", 1.0])
			k += 1
			if absf(z) > 2.0:  # западная стена: по краям обычные модули, посередине portal_wall (4 м) с вырезом под портал
				items.append([wv[k % 3], Vector3(-4.0, 0, z), 90.0 + 180.0 * (k % 2), "BASE", 1.0])
			k += 1
		items.append(["env/portal_wall", Vector3(-4.0, 0, 0.0), -90.0, "BASE", 1.0])
		items.append(["env/doorway", Vector3(-1.0, 0, 4.0), 0.0, "BASE", 1.0])     # вход
		items.append(["env/doorway_b", Vector3(1.0, 0, -4.0), 0.0, _tier, 1.0])   # выход
	if not _noedge:
		items.append(["env/room_edge_8", Vector3(0.0, 0.0, 0.0), 0.0, "BASE", 1.0])  # кромка комнаты вместо стен: квадрат 8×8, края на ±4 (в игре — env/room_edge_16 в центр комнаты)
	if not _nohorizon:
		items.append(["env/horizon_band", Vector3(0.0, 0.0, 0.0), 0.0, "BASE", 1.0])  # кольцо тумана у горизонта: один раз на центр комнаты
	for x in [-4.0, 4.0]:
		for z in [-4.0, 4.0]:
			items.append(["env/pillar", Vector3(x, 0, z), 0.0, "BASE", 1.0])
	items.append(["props/vault_closed", Vector3(0.0, 0, 0.0), 180.0, "BASE", 1.0])  # яркость ×1,5 задаётся в _setup  # хранилище в центре лицом ко входу; шард встаёт на якорь внутри
	items.append(["props/sensor", Vector3(3.2, 0, -2.2), 0.0, "BASE", 1.0])  # стационарный датчик узла у восточной стены
	items.append(["props/dead_deck", Vector3(-1.3, 0.0, 1.4), 40.0, "BASE", 1.0])  # мёртвую деку можно подобрать: лежит на полу
	if _portal:  # портал в западной стене, лицом в комнату; по умолчанию убран: большая яркая бирюзовая панель слева в кадрах изнутри (владелец), флаг --portal возвращает
		items.append(["props/portal", Vector3(-4.0, 0, 0.0), -90.0, "BASE", 1.0])
	items.append(["ice/soft_ice", ICE_POS, 15.0, "", 1.0])
	# другие нетраннеры в узле: лицом к Godot −Z при повороте 0°; варианты чередуются
	items.append(["avatar/runner", Vector3(-1.6, 0, 1.4), 150.0, "", 1.0])
	items.append(["avatar/runner_b", Vector3(2.0, 0, 0.6), 200.0, "", 1.0])
	if _crowd:
		var rv := ["avatar/runner", "avatar/runner_b", "avatar/runner_c"]
		for i in 7:
			items.append([rv[i % 3], Vector3(-2.0 + (i % 4) * 1.3, 0, -0.9 + (i / 4) * 1.3), 40.0 * i, "", 1.0])
	if _field:  # эксперимент: дальний план — поле колонн на решётке 0,1 м
		for fz in [-12.0, -16.0]:
			for fx in [-8.0, -4.0, 0.0, 4.0, 8.0]:
				items.append(["env/column_field", Vector3(fx, 0, fz), 0.0, _tier, 1.0])
	else:  # дальний план: пласты данных. Наш пласт (y = 0) продолжается за комнатой участками 11 м (сетка 5×5 без центрального), выше и ниже лежат такие же
		# пласты с шагом LAYER_PITCH (потолок нашего 5 м + 2 м пустоты); в них сетка 3×3. Пол и потолок везде (тайлов ~5%), в каждом пласте башни света.
		var fv := ["env/far_field", "env/far_field_b", "env/far_field_c"]
		var ff := ["env/far_floor", "env/far_floor_b", "env/far_floor_c"]
		var fc := ["env/far_ceiling", "env/far_ceiling_b", "env/far_ceiling_c"]
		var fi := 0
		for ly in [0.0, LAYER_PITCH, -LAYER_PITCH]:
			var r := 2 if ly == 0.0 else 1
			for gx in range(-r, r + 1):
				for gz in range(-r, r + 1):
					if ly == 0.0 and gx == 0 and gz == 0:
						continue
					var pos := Vector3(gx * 11.0, ly, gz * 11.0)
					var rot := 90.0 * (fi % 4)
					items.append([fv[fi % 3], pos, rot, _tier, 1.0])
					items.append([ff[fi % 3], pos, rot, _tier, 1.0])
					items.append([fc[(fi + 1) % 3], pos + Vector3(0, CEILING_H, 0), rot, _tier, 1.0])
					fi += 1
	return items


func _shots() -> Array:
	var room := _room()
	var stage := [["env/floor", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["avatar/runner", Vector3(-0.9, 0, 0.0), 180.0, "", 1.0],
		["avatar/runner_b", Vector3(0.0, 0, -0.4), 180.0, "", 1.0], ["avatar/runner_c", Vector3(0.95, 0, 0.1), 180.0, "", 1.0]]
	var props := [["env/floor", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/floor_b", Vector3(-2, 0, 0), 90.0, "BASE", 1.0], ["env/floor_c", Vector3(2, 0, 0), 180.0, "BASE", 1.0],
		["props/vault_closed", Vector3(-1.0, 0, 0.3), 160.0, "BASE", 1.0], ["props/vault_open", Vector3(1.0, 0, 0.3), 200.0, "BASE", 1.0],
		["props/portal", Vector3(-2.2, 0, -2.4), 15.0, "BASE", 1.0], ["props/portal_locked", Vector3(2.4, 0, -2.6), -20.0, "BASE", 1.0]]
	var solo := [["avatar/runner", Vector3(0, 0, 0), 180.0, "", 1.0]]
	var scar := [ICE_POS + Vector3(0, 1.0, -0.6), 4.2]
	var icestage := [["env/floor_clear", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(2.4, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(-2.4, 0, 0), 0.0, "BASE", 1.0],
		["ice/soft_ice", Vector3(-1.8, 0, 0.0), 180.0, "", 1.0], ["ice/black_ice", Vector3(1.5, 0, 0.0), 180.0, "", 1.0], ["avatar/runner", Vector3(0.0, 0, 1.0), 180.0, "", 1.0]]
	var icestates := [["env/floor_clear", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(2.4, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(-2.4, 0, 0), 0.0, "BASE", 1.0],
		["ice/black_ice", Vector3(-2.0, 0, 0.0), 180.0, "", 1.0], ["ice/black_ice_hunt", Vector3(0.0, 0, 0.0), 180.0, "", 1.0], ["ice/black_ice_catch", Vector3(2.0, 0, 0.0), 180.0, "", 1.0]]
	var nodeprops := [["env/floor_clear", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(2.4, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(-2.4, 0, 0), 0.0, "BASE", 1.0],
		["props/seat", Vector3(-1.6, 0, 0.0), 0.0, "BASE", 1.0], ["props/sensor", Vector3(0.0, 0, 0.0), 0.0, "BASE", 1.0], ["props/dead_deck", Vector3(1.2, 0.02, 0.4), 30.0, "BASE", 3.0],
		["avatar/runner", Vector3(-1.6, 0.14, 0.0), 0.0, "", 1.0]]
	var envmore := [["env/floor_clear", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(-2, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(2, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(4, 0, 0), 0.0, "BASE", 1.0],
		["env/lockdown_gate", Vector3(-3.0, 0, -2.0), 0.0, "", 1.0], ["env/lockdown_gate_open", Vector3(-1.0, 0, -2.0), 0.0, "", 1.0], ["env/corner", Vector3(1.0, 0, -2.0), 0.0, "BASE", 1.0],
		["env/platform", Vector3(3.0, 0, -2.0), 0.0, "BASE", 1.0], ["env/cable_straight", Vector3(-3.0, 0, 0.0), 0.0, "BASE", 1.0], ["env/cable_curve", Vector3(-1.0, 0, 0.0), 0.0, "BASE", 1.0],
		["env/tunnel_ring", Vector3(2.0, 0, 0.5), 0.0, _tier, 1.0]]
	var tk := ["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]
	var decks := [["env/floor_clear", Vector3(0, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(-2, 0, 0), 0.0, "BASE", 1.0], ["env/floor_clear", Vector3(2, 0, 0), 0.0, "BASE", 1.0],
		["deck/wrist_deck", Vector3(0.0, 1.1, 0.4), 90.0, "", 6.0]]
	for i in tk.size():
		decks.append(["deck/daemon_" + tk[i], Vector3(-1.75 + 0.5 * i, 0.55, 0.0), 0.0, "", 8.0])
	return [
		{"name": "red_probe", "cam": Vector3(0.0, 0.9, 2.2), "look": Vector3(0.0, 0.7, 0.0), "fov": 40.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": [
			["deck/daemon_EXTRACT_DAEMON", Vector3(-0.8, 0.5, 0.0), 0.0, "", 8.0], ["deck/daemon_EXTRACT_DAEMON", Vector3(0.0, 0.9, 0.0), 0.0, "", 8.0], ["deck/daemon_EXTRACT_DAEMON", Vector3(0.8, 1.4, 0.3), 0.0, "", 8.0]]},
		{"name": "deck_close", "cam": Vector3(0.9, 1.5, 1.0), "look": Vector3(0.0, 1.1, 0.4), "fov": 45.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": decks},
		{"name": "token_close", "cam": Vector3(-1.2, 0.7, 1.0), "look": Vector3(-1.2, 0.55, 0.0), "fov": 40.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": decks},
		{"name": "deck_stage", "cam": Vector3(0.0, 1.0, 2.9), "look": Vector3(0.0, 0.85, 0.0), "fov": 60.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": decks},
		{"name": "gate_close", "cam": Vector3(-2.0, 1.3, 1.5), "look": Vector3(-2.0, 1.0, -2.0), "fov": 70.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": envmore},
		{"name": "corner_platform", "cam": Vector3(2.0, 1.5, 1.5), "look": Vector3(2.0, 0.6, -2.0), "fov": 70.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": envmore},
		{"name": "env_more", "cam": Vector3(0.0, 1.5, 5.5), "look": Vector3(0.0, 1.0, -1.0), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": envmore},
		{"name": "node_props", "cam": Vector3(0.0, 1.25, 4.8), "look": Vector3(0.0, 0.8, 0.0), "fov": 60.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": nodeprops},
		{"name": "ice_states", "cam": Vector3(0.0, 1.3, 6.5), "look": Vector3(0.0, 1.4, 0.0), "fov": 60.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": icestates},
		{"name": "ice_stage", "cam": Vector3(0.0, 1.25, 6.0), "look": Vector3(0.0, 1.2, 0.0), "fov": 60.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": icestage},
		{"name": "ice_close", "cam": Vector3(1.2, 1.3, 3.2), "look": Vector3(1.5, 1.4, 0.0), "fov": 55.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": icestage},
		{"name": "props_stage", "cam": Vector3(0.0, 1.3, 3.6), "look": Vector3(0.0, 1.1, -1.0), "fov": 65.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": props},
		{"name": "vault_close", "cam": Vector3(-0.2, 1.0, 1.6), "look": Vector3(-0.9, 0.6, 0.3), "fov": 55.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": props},
		{"name": "avatar_stage", "cam": Vector3(0.1, 1.2, 3.0), "look": Vector3(0.0, 0.95, 0.0), "fov": 55.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": stage},
		{"name": "avatar_side", "cam": Vector3(2.0, 1.15, 0.0), "look": Vector3(0.0, 1.0, 0.0), "fov": 55.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": solo},
		{"name": "avatar_close", "cam": Vector3(0.45, 1.25, 1.7), "look": Vector3(0.0, 1.0, 0.0), "fov": 55.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": solo},
		{"name": "far_view", "cam": Vector3(0.0, 1.4, -3.4), "look": Vector3(0.0, 2.2, -20.0), "fov": 70.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
		{"name": "room_entrance", "cam": Vector3(-1.0, 1.25, 8.6), "look": Vector3(0.0, 1.0, -2.5), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
		{"name": "room_overview", "cam": Vector3(11.0, 10.5, 11.0), "look": Vector3(0.0, 0.4, -0.5), "fov": 50.0, "fade": [30.0, 80.0], "corrupt": scar, "items": room},
		{"name": "portal_view", "cam": Vector3(2.2, 1.4, 0.2), "look": Vector3(-4.0, 1.4, 0.0), "fov": 70.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": room},
		{"name": "room_wall", "cam": Vector3(2.4, 1.4, 1.2), "look": Vector3(-1.4, 1.0, -4.0), "fov": 70.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
		{"name": "room_floor", "cam": Vector3(0.3, 1.6, 1.6), "look": Vector3(0.0, 0.0, -0.4), "fov": 70.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
		{"name": "horizon_view", "cam": Vector3(1.0, 1.25, -2.6), "look": Vector3(1.0, 1.6, -40.0), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": room},
		{"name": "horizon_out", "cam": Vector3(0.0, 1.3, 22.0), "look": Vector3(0.0, 1.8, -30.0), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": room},
		{"name": "room_inside", "cam": Vector3(-3.0, 1.25, 3.0), "look": Vector3(0.5, 0.9, -2.8), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": scar, "items": room},
		# с края комнаты (юго-западный угол) вдоль южной кромки и наружу, за обрыв
		{"name": "edge_view", "cam": Vector3(-3.4, 1.4, 3.1), "look": Vector3(3.0, 0.0, 6.0), "fov": 75.0, "fade": [14.0, 40.0], "corrupt": [Vector3.ZERO, 0.0], "items": room},
	]


var out_dir := "/tmp/shots"


var _tier := "HARD"  # --tier=BASE|HARD|NIGHTMARE: тир окружения в кадрах (по умолчанию HARD, как раньше; BASE — бирюза, как в клиенте)
var _lattice := 0.0  # --lattice=0.05: шаг мировой решётки (эксперимент), 0 — выкл.
var _field := false  # --field: вместо дальних стен поле колонн
var _walk := false  # --walk: один аватар ходит по кругу (видно ли мерцание от прищёлкивания к решётке)
var _only: Array = []  # --only=a,b: снимать только эти кадры
var _walker: Node3D
var _walker_mir: Node3D
var _walker_base := Vector3.ZERO
var _crowd := false  # --crowd: в комнате девять аватаров (худший случай по ТЗ), для замера
var _walls := false  # --walls: вернуть стены-занавесы и проёмы (по умолчанию убраны: владелец, «эквалайзер явно не то», открытый горизонт)
var _portal := false  # --portal: вернуть портал в западной стене (по умолчанию убран: яркая бирюзовая панель закрывает кадр изнутри комнаты)
var _nohorizon := false  # --nohorizon: без кольца env/horizon_band (сравнение «с туманом / без»)
var _noedge := false  # --noedge: без кромки env/room_edge_8 (сравнение «с кромкой / без»)
var _movie := false
var _demo := false  # --demo: длинный проход по комнате (вход → хранилище → портал → ICE → вверх), 34 с
var _batch_on := true  # --nobatch: не клеить дальние пласты в MultiMesh
var _static := false
var _fps := false
var _ft: Array = []  # времена кадров, мс (после прогрева)
var _gpu: Array = []  # время кадра на видеокарте, мс
var _cpu: Array = []  # время подготовки кадра на процессоре, мс
var _static_cam := PackedFloat64Array([0.0, 1.25, 6.4, 0.0, 1.0, -2.0])  # x,y,z камеры и x,y,z точки взгляда; --cam=… переопределяет
var _t := 0.0
var _cam: Camera3D
var _insts: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a == "--movie":
			_movie = true
		if a.begins_with("--cam="):
			_static_cam = PackedFloat64Array(Array(a.trim_prefix("--cam=").split(",")).map(func(v): return float(v)))
		if a.begins_with("--tier="):
			_tier = a.trim_prefix("--tier=")
		if a.begins_with("--lattice="):
			_lattice = float(a.trim_prefix("--lattice="))
		if a == "--demo":
			_demo = true
			_movie = true
			_walk = true
		if a == "--nobatch":
			_batch_on = false
		if a == "--field":
			_field = true
		if a == "--walk":
			_walk = true
		if a.begins_with("--only="):
			_only = Array(a.trim_prefix("--only=").split(","))
		if a == "--nohorizon":
			_nohorizon = true
		if a == "--noedge":
			_noedge = true
		if a == "--crowd":
			_crowd = true
		if a == "--walls":
			_walls = true
		if a == "--portal":
			_portal = true
		if a == "--fps":  # замер: 6 с без записи видео, печатает средний fps, худшие кадры и число вызовов отрисовки
			_fps = true
		if a == "--static":  # камера неподвижна: нужно, чтобы по разнице кадров проверять движение штрихов
			_static = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if _fps:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	if _movie:
		# Видео: godot --write-movie <файл.avi> --fixed-fps 24 --quit-after 160 -- --movie. Камера идёт ко входу и в комнату,
		# на 2,5 с «касание» стены у выхода: прогиб штрихов и красная полоса расходятся (как в референсе «contact»).
		var shot: Dictionary = {}
		for sh in _shots():  # видео и замер идут по комнате со входа, по имени (порядок кадров может меняться)
			if sh["name"] == "room_entrance":
				shot = sh
		_build(shot, add_child_ret(Node3D.new()))
		set_process(true)
		return
	set_process(false)
	for shot in _shots():
		if not _only.is_empty() and not (shot["name"] in _only):
			continue
		var root := Node3D.new()
		add_child(root)
		_build(shot, root)
		_cam.fov = shot["fov"]
		_cam.look_at_from_position(shot["cam"], shot["look"])
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, shot["name"]])
		print("SHOT ", shot["name"], " ", img.get_size())
		root.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func add_child_ret(n: Node) -> Node:
	add_child(n)
	return n


func _batched(it: Array) -> bool:  # всё окружение (env/) клеим в MultiMesh (--nobatch отключает: для сравнения вызовов отрисовки)
	return _batch_on and String(it[0]).begins_with("env/")


func _batch_item(batch: AssetBatch, scene: PackedScene, it: Array, shot: Dictionary, xf: Transform3D, intensity: float, layer: int) -> void:
	var key := "%s|%s|%.2f|%d" % [it[0], it[3], intensity, layer]  # группа: ассет, тир, яркость, пласт
	if not batch.has(key):
		var proto: Node3D = scene.instantiate()
		_setup(proto, it, shot, intensity)
		batch.register(key, proto)
	batch.add(key, xf)


func _build(shot: Dictionary, root: Node) -> void:
	_insts.clear()
	var batch := AssetBatch.new()
	for it in shot["items"]:
		var scene: PackedScene = load("res://assets/models/%s.glb" % it[0])
		if _batched(it):
			var bxf := Transform3D(Basis(Vector3.UP, deg_to_rad(it[2])).scaled(Vector3.ONE * it[4]), it[1])
			var layer := int(roundf(it[1].y / 6.0))
			_batch_item(batch, scene, it, shot, bxf, 1.0, layer)
			if String(it[0]) in REFLECT and absf(it[1].y) < 0.01:
				_batch_item(batch, scene, it, shot, Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3.ZERO) * bxf, 0.18, layer)
			continue
		var inst: Node3D = scene.instantiate()
		inst.position = it[1]
		inst.rotation_degrees.y = it[2]
		inst.scale = Vector3.ONE * it[4]
		root.add_child(inst)
		_setup(inst, it, shot, 1.0)
		var anc := inst.find_child("Anchor_Shard", true, false)
		if anc != null:  # якорь хранилища: ставим шард, как это сделает игра
			var sh: Node3D = (load("res://assets/models/props/shard.glb") as PackedScene).instantiate()
			root.add_child(sh)
			sh.global_position = (anc as Node3D).global_position
			sh.scale = Vector3.ONE * 1.6
			AM.apply(sh, "")
		var is_walker := _walk and _walker == null and String(it[0]).begins_with("avatar/")
		if is_walker:
			_walker = inst
			_walker_base = inst.position
		if String(it[0]) in REFLECT and absf(it[1].y) < 0.01:  # отражаем только наш пласт  # отражение в полу: зеркальная копия, тусклая (в референсе Blackwall пол — мутное зеркало)
			var mir: Node3D = scene.instantiate()
			mir.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3.ZERO) * inst.transform
			root.add_child(mir)
			_setup(mir, it, shot, 0.18)
			if is_walker:
				_walker_mir = mir
	batch.flush(root)


func _update_walker() -> void:
	if _walk and _walker != null:  # аватар идёт по кругу r=1 м со скоростью ≈0,55 м/с (медленный шаг VR); отражение следует за ним
		var ang := _t * 0.55
		_walker.position = _walker_base + Vector3(cos(ang), 0, sin(ang)) - Vector3(1, 0, 0)
		_walker.rotation.y = -ang + PI
		_walker_mir.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3.ZERO) * _walker.transform


func _process(delta: float) -> void:
	_t += delta
	_update_walker()
	if _fps and _t > 1.0:
		_ft.append(delta * 1000.0)
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		if _t > 7.0:
			_ft.sort()
			var sum := 0.0
			for f in _ft:
				sum += f
			var avg: float = sum / _ft.size()
			var info := func(k): return RenderingServer.get_rendering_info(k)
			_gpu.sort()
			_cpu.sort()
			var ga := 0.0
			var ca := 0.0
			for g in _gpu:
				ga += g
			for c in _cpu:
				ca += c
			print("GPU мс: avg=%.2f p95=%.2f max=%.2f | CPU мс: avg=%.2f p95=%.2f max=%.2f" % [ga / _gpu.size(), _gpu[int(_gpu.size() * 0.95)], _gpu[-1], ca / _cpu.size(), _cpu[int(_cpu.size() * 0.95)], _cpu[-1]])
			print("FPS avg=%.1f  p95=%.2f мс  p99=%.2f мс  max=%.2f мс  кадров=%d  вызовов отрисовки=%d  примитивов=%d  объектов=%d  окно=%s" % [
				1000.0 / avg, _ft[int(_ft.size() * 0.95)], _ft[int(_ft.size() * 0.99)], _ft[-1], _ft.size(),
				info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), info.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				info.call(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), str(get_window().size)])
			get_tree().quit()
	if _static:
		_cam.look_at_from_position(Vector3(_static_cam[0], _static_cam[1], _static_cam[2]), Vector3(_static_cam[3], _static_cam[4], _static_cam[5]))
		return
	_update_walker()
	var p: Vector3
	var look: Vector3
	if _demo:
		_demo_camera()
		return
	if _t < 2.0:
		p = Vector3(0.0, 1.25, 6.4).lerp(Vector3(0.0, 1.25, 3.6), _t / 2.0)
		look = Vector3(0.0, 1.0, -2.0)
	else:
		var u: float = clampf((_t - 2.0) / 4.0, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		p = Vector3(0.0, 1.25, 3.6).lerp(Vector3(-1.4, 1.25, 1.0), u)
		look = Vector3(0.0, 1.0, -2.0).lerp(Vector3(1.0, 1.0, -2.6), u)
	_cam.look_at_from_position(p, look)
	# касание: радиус растёт 0 → 2,8 м за 2 с, держится, затухает
	var r := 0.0
	if _t > 2.5 and _t < 6.5:
		var k: float = clampf((_t - 2.5) / 2.0, 0.0, 1.0)
		r = 2.8 * k * (1.0 - clampf((_t - 5.5) / 1.0, 0.0, 1.0))
	for inst in _insts:
		AM.set_param(inst, "touch_pos", Vector3(1.2, 1.0, -2.9))
		AM.set_param(inst, "touch_radius", r)


## Маршрут демо: (время с, позиция глаз сидящего, точка взгляда). Между ключами плавно (smoothstep); на стыках камера почти стоит.
const DEMO_KEYS := [
	[0.0, Vector3(-1.0, 1.25, 10.5), Vector3(-1.0, 1.2, 2.0)],
	[4.0, Vector3(-1.0, 1.25, 5.0), Vector3(0.0, 1.0, 0.0)],
	[8.0, Vector3(-0.9, 1.2, 2.6), Vector3(0.0, 0.55, 0.0)],
	[12.0, Vector3(-1.2, 1.2, 1.6), Vector3(0.0, 0.7, 0.0)],
	[16.0, Vector3(-1.0, 1.2, 0.6), Vector3(-4.0, 1.4, 0.0)],
	[20.0, Vector3(-1.0, 1.2, 0.4), Vector3(-3.0, 1.5, -0.5)],
	[24.0, Vector3(0.2, 1.2, 0.6), Vector3(1.0, 1.2, -2.8)],
	[28.0, Vector3(0.2, 1.2, 0.6), Vector3(1.0, 1.2, -2.8)],
	[32.0, Vector3(0.0, 1.2, 0.2), Vector3(0.0, 4.2, -1.5)],
	[34.0, Vector3(0.0, 1.2, 0.2), Vector3(0.0, 4.2, -1.5)],
]


func _demo_camera() -> void:
	var i := 0
	while i < DEMO_KEYS.size() - 2 and _t > DEMO_KEYS[i + 1][0]:
		i += 1
	var a: Array = DEMO_KEYS[i]
	var b: Array = DEMO_KEYS[i + 1]
	var u: float = clampf((_t - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	_cam.look_at_from_position((a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u))


func _setup(inst: Node3D, it: Array, shot: Dictionary, intensity: float) -> void:
	_insts.append(inst)
	AM.apply(inst, it[3])
	if _lattice > 0.0:
		AM.set_param(inst, "lattice", _lattice)
	if String(it[0]).begins_with("props/vault"):
		intensity *= 1.5  # хранилище главный предмет узла: чуть ярче окружения
	if String(it[0]).begins_with("deck/") or String(it[0]) == "props/dead_deck":  # мелкие предметы: шум контура (пятна 7 см) на них не нужен, контур ровнее и ярче
		AM.set_param(inst, "edge_uneven", 0.0)
		AM.set_param(inst, "edge_glow", 2.0)
	if String(it[0]).begins_with("avatar/"):
		AM.set_param(inst, "breathe", 0.25)  # аватар дышит заметнее стены: штрихи короткие
	if String(it[0]).begins_with("ice/"):
		AM.set_param(inst, "breathe", 0.12)  # существа «дышат»: длина штрихов медленно плывёт
	AM.set_distance_fade(inst, shot["fade"][0], shot["fade"][1])
	if String(it[0]).begins_with("env/far_") and shot["fade"][1] < 100.0:  # дальние пласты не гаснут в чёрный (горизонт светится): затухание отодвинуто, яркость растёт с расстоянием
		AM.set_distance_fade(inst, FAR_FADE[0], FAR_FADE[1])
		AM.set_param(inst, "far_gain", FAR_GAIN)
		AM.set_param(inst, "far_start", FAR_GAIN_RANGE[0])
		AM.set_param(inst, "far_end", FAR_GAIN_RANGE[1])
	if String(it[0]) == "env/horizon_band":  # кольцо горизонта: на 35–70 м, поэтому затухание ещё дальше, а усиление у самой дали
		AM.set_distance_fade(inst, HORIZON_FADE[0], HORIZON_FADE[1])
		AM.set_param(inst, "far_gain", HORIZON_GAIN)
		AM.set_param(inst, "bead_depth", 0.0)  # у далёких широких штрихов бусины читаются ступеньками: гладкий туман
		AM.set_param(inst, "far_start", 30.0)
		AM.set_param(inst, "far_end", 60.0)
	if String(it[0]).begins_with("env/"):
		AM.set_corruption(inst, shot["corrupt"][0], shot["corrupt"][1])
	if intensity != 1.0:
		AM.set_intensity(inst, intensity)

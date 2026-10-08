class_name GlitchSprite
extends RefCounted
## Анимированный спрайт «глитч-блок» для облаков частиц (рука, тело): квантованное белое пятно из блоков 4×4 px, которое то сидит компактным блоком,
## то на миг вытягивается в вертикальную колонку и за ~12 кадров оседает обратно, с отскочившими обломками слева и редкими дырами.
## Образец — отзыв владельца 07.10 (видео «частица, из которой собирается волюметрик»): секунда покоя, рывок до ×2,6 высоты, плавный спад.
## Само видео в репозиторий не положено (чужой контент, как и STL головы); спрайт строится кодом, детерминированно.
##
## Атлас 8×4 ячеек по 32×64 px (256×256, L8, с мипмапами): ячейка вдвое выше ширины, пятно в покое 20×24 px, в рывке до 60 px высотой.
## Шейдер (particles_body.gdshaderinc, uniform glitch_tex) выбирает ячейку по времени и случайной фазе частицы и растягивает квад по высоте вдвое.
## Края мягкие (3×3 по ячейке дважды): жёсткие блоки на Pico без MSAA дали бы лесенку.

const COLS := 8
const ROWS := 4
const CELL_W := 32
const CELL_H := 64
const FRAMES := COLS * ROWS
const BLOCK := 4  # размер блока, px
const REST_H := 24
const BURST_H := 60
const SEED := 20771

static var _tex: ImageTexture


## Высота пятна (px, кратна BLOCK) в кадре цикла: покой 0–9, рывок 10–13, плавный спад 14–25, покой 26–31.
static func frame_height(f: int) -> int:
	var h := float(REST_H)
	if f >= 10 and f <= 13:
		h = float(BURST_H)
	elif f > 13 and f <= 25:
		h = lerpf(float(BURST_H), float(REST_H), float(f - 13) / 12.0)
	return int(round(h / float(BLOCK))) * BLOCK


static func texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(build_image())
	return _tex


## Атлас целиком: кадр f — ячейка (f % COLS, f / COLS).
static func build_image() -> Image:
	var img := Image.create(COLS * CELL_W, ROWS * CELL_H, true, Image.FORMAT_L8)
	for f in FRAMES:
		var cell := _blur(_blur(_draw_frame(f)))
		var ox := (f % COLS) * CELL_W
		var oy := (f / COLS) * CELL_H
		for y in CELL_H:
			for x in CELL_W:
				var v := clampf(cell[y * CELL_W + x] * 1.35, 0.0, 1.0)
				img.set_pixel(ox + x, oy + y, Color(v, v, v))
	img.generate_mipmaps()
	return img


## Ячейка кадра f как PackedFloat32Array CELL_W×CELL_H (1 — блок, 0 — пусто).
static func _draw_frame(f: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + f * 7919
	var cell := PackedFloat32Array()
	cell.resize(CELL_W * CELL_H)
	var gw := CELL_W / BLOCK  # 8 блоков в ширину
	var gh := CELL_H / BLOCK  # 16 в высоту
	var rows := frame_height(f) / BLOCK
	var top := (gh - rows) / 2
	var burst := frame_height(f) > 40
	var col0 := 1 + rng.randi() % 2  # положение колонки дрожит на блок
	for r in rows:
		var w := 4 + rng.randi() % 2
		if rng.randf() < 0.12:
			w = 3
		var x0 := col0 + (rng.randi() % 2 if rng.randf() < 0.4 else 0)
		x0 = mini(x0, gw - 1 - w)
		var hole := -1
		if burst and rng.randf() < 0.25:
			hole = x0 + 1 + rng.randi() % maxi(w - 2, 1)
		for c in w:
			if x0 + c == hole:
				continue
			_block(cell, x0 + c, top + r)
	# обломки слева, оторванные от пятна (как в образце): 0–2 штуки у края ячейки
	var frags := rng.randi() % 3
	for k in frags:
		_block(cell, 0, top + rng.randi() % rows)
	return cell


static func _block(cell: PackedFloat32Array, bx: int, by: int) -> void:
	for y in BLOCK:
		for x in BLOCK:
			cell[(by * BLOCK + y) * CELL_W + bx * BLOCK + x] = 1.0


## Размытие 3×3 внутри ячейки (соседние ячейки не смешиваются).
static func _blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for y in CELL_H:
		for x in CELL_W:
			var s := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var yy := clampi(y + dy, 0, CELL_H - 1)
					var xx := clampi(x + dx, 0, CELL_W - 1)
					s += src[yy * CELL_W + xx]
			out[y * CELL_W + x] = s / 9.0
	return out

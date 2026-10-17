class_name XrDiag
extends Node
## Диагностика рендера на очках (`[render] perf = "diag"`): через DELAY_SEC после старта один раз печатает `[xr-diag]` — что реально включено на уровне OpenXR и
## вьюпорта (уровень фовеации и динамика у интерфейса, VRS-режим вьюпорта, MSAA, размер цели глаза), и сохраняет кадр вьюпорта в PNG (user://xr_diag_view.png) —
## чтобы сравнить буфер приложения со скриншотом Pico того же вида: чисто в буфере, а на скриншоте артефакт — виноват компоновщик/XR; артефакт и в буфере — шейдер.
## Путь файла и среднюю яркость кадра (не пустой ли) пишет в ту же строку; в журнал клиента попадает через сигнал reported.

signal reported(info: Dictionary)
## Итог кадра глаза (`[eye] diff=… luma=…`), см. _capture_eye.
signal eye_reported(info: Dictionary)

const DELAY_SEC := 8.0
const FILE := "user://xr_diag_view.png"
const EYE_FILE := "user://xr_diag_eye.png"
const EYE_SIZE := 384            ## сторона кадра глаза, px
const EYE_FOV := 100.0           ## градусов по вертикали, как у глаза Pico
const EYE_SHOTS := 5             ## снимков (EYE_SHOTS - 1 пар для diff)
const EYE_GAP_SEC := 0.12        ## между снимками
const EYE_SETTLE_FRAMES := 3     ## кадров на отрисовку вьюпорта глаза перед чтением

var last: Dictionary = {}
var last_eye: Dictionary = {}


func _ready() -> void:
	await get_tree().create_timer(DELAY_SEC).timeout
	last = collect(get_viewport(), XRServer.find_interface("OpenXR"))
	var path := ""
	var img: Image = null
	var tex := get_viewport().get_texture()
	if tex != null:
		img = tex.get_image()
	if img != null and not img.is_empty():
		img.save_png(FILE)
		path = ProjectSettings.globalize_path(FILE)
		last["shot_size"] = "%dx%d" % [img.get_width(), img.get_height()]
		last["shot_mean"] = snappedf(mean_luma(img), 0.001)
	last["shot_path"] = path
	print(format(last))
	reported.emit(last)
	await _capture_eye()


## Кадр глаза без человека (просьба Blender 17.10: корневое окно при use_xr чёрное, adb screencap видит только компоновщик). Второй вьюпорт того же мира с камерой,
## повторяющей позу головы, рисует то, что видит глаз (сцена, шейдеры, облака; не компоновщик и не MSAA очков). EYE_SHOTS снимков через EYE_GAP_SEC —
## строка `[eye] diff=… luma=…`: diff — средняя разница яркости соседних снимков (поза неподвижна — это «рябь»), luma — средняя яркость первого. Первый снимок — user://xr_diag_eye.png.
func _capture_eye() -> void:
	var main := get_viewport().get_camera_3d()
	if main == null:
		last_eye = {"eye": "no_camera"}
		print(format_eye(last_eye))
		eye_reported.emit(last_eye)
		return
	var sv := SubViewport.new()
	sv.size = Vector2i(EYE_SIZE, EYE_SIZE)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_DISABLED
	var cam := Camera3D.new()
	cam.fov = EYE_FOV
	cam.near = main.near
	cam.far = main.far
	sv.add_child(cam)
	add_child(sv)
	cam.make_current()
	var shots: Array[Image] = []
	for i in EYE_SHOTS:
		cam.global_transform = main.global_transform
		for f in EYE_SETTLE_FRAMES:
			await get_tree().process_frame
			cam.global_transform = main.global_transform
		var img := sv.get_texture().get_image()
		if img != null and not img.is_empty():
			shots.append(img)
		if i < EYE_SHOTS - 1:
			await get_tree().create_timer(EYE_GAP_SEC).timeout
	last_eye = eye_summary(shots)
	if not shots.is_empty():
		shots[0].save_png(EYE_FILE)
		last_eye["eye_path"] = ProjectSettings.globalize_path(EYE_FILE)
	print(format_eye(last_eye))
	eye_reported.emit(last_eye)
	sv.queue_free()


## Итог по снимкам глаза: diff (среднее), diff_max, luma первого, shots. Меньше двух снимков — diff=-1.
static func eye_summary(shots: Array[Image]) -> Dictionary:
	if shots.is_empty():
		return {"shots": 0, "luma": 0.0, "diff": -1.0, "diff_max": -1.0}
	var sum := 0.0
	var peak := 0.0
	for i in range(1, shots.size()):
		var d := frame_diff(shots[i - 1], shots[i])
		sum += d
		peak = maxf(peak, d)
	var n := shots.size() - 1
	return {"shots": shots.size(), "luma": snappedf(mean_luma(shots[0]), 0.0001),
		"diff": snappedf(sum / n, 0.00001) if n > 0 else -1.0, "diff_max": snappedf(peak, 0.00001) if n > 0 else -1.0}


## Средняя абсолютная разница яркости двух кадров одного размера по сетке 32×32 отсчётов (0 — одинаковые; разные размеры или пустой — −1).
static func frame_diff(a: Image, b: Image) -> float:
	if a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
		return -1.0
	var w := a.get_width()
	var h := a.get_height()
	var sum := 0.0
	for iy in 32:
		for ix in 32:
			var x := ix * w / 32
			var y := iy * h / 32
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf((ca.r + ca.g + ca.b) / 3.0 - (cb.r + cb.g + cb.b) / 3.0)
	return sum / 1024.0


static func format_eye(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in d:
		parts.append("%s=%s" % [k, d[k]])
	return "[eye] " + " ".join(parts)


## Что реально стоит у вьюпорта и интерфейса OpenXR (свойства, которых нет в этой версии Godot, пропускаются).
static func collect(vp: Viewport, iface: XRInterface) -> Dictionary:
	var d := {
		"use_xr": vp.use_xr,
		"msaa_3d": int(vp.msaa_3d),
		"screen_space_aa": int(vp.screen_space_aa),
		"vrs_mode": int(vp.vrs_mode),
		"size": "%dx%d" % [vp.size.x, vp.size.y],
	}
	if iface != null:
		d["iface"] = iface.get_name()
		var rts := iface.get_render_target_size()
		d["target_size"] = "%dx%d" % [rts.x, rts.y]
		for k in ["foveation_level", "foveation_dynamic", "render_target_size_multiplier", "refresh_rate"]:
			if k in iface:
				d[k] = iface.get(k)
	return d


## Средняя яркость кадра 0..1 по сетке 16×16 отсчётов (пустой / чёрный кадр даёт ≈0).
static func mean_luma(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return 0.0
	var sum := 0.0
	var n := 0
	for iy in 16:
		for ix in 16:
			var c := img.get_pixel(ix * w / 16, iy * h / 16)
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
	return sum / n


static func format(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in d:
		parts.append("%s=%s" % [k, d[k]])
	return "[xr-diag] " + " ".join(parts)

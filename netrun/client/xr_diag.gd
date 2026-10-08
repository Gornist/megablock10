class_name XrDiag
extends Node
## Диагностика рендера на очках (`[render] perf = "diag"`): через DELAY_SEC после старта один раз печатает `[xr-diag]` — что реально включено на уровне OpenXR и
## вьюпорта (уровень фовеации и динамика у интерфейса, VRS-режим вьюпорта, MSAA, размер цели глаза), и сохраняет кадр вьюпорта в PNG (user://xr_diag_view.png) —
## чтобы сравнить буфер приложения со скриншотом Pico того же вида: чисто в буфере, а на скриншоте артефакт — виноват компоновщик/XR; артефакт и в буфере — шейдер.
## Путь файла и среднюю яркость кадра (не пустой ли) пишет в ту же строку; в журнал клиента попадает через сигнал reported.

signal reported(info: Dictionary)

const DELAY_SEC := 8.0
const FILE := "user://xr_diag_view.png"

var last: Dictionary = {}


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

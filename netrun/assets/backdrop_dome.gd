class_name BackdropDome
extends Node3D
## Свет пустоты по тревоге. Вид V11 (владелец 31.10): купола, неба, звёзд и дымки НЕТ — узел ничего не рисует. Класс оставлен, чтобы клиент (world_scene.gd,
## shader_warmup.gd) не ломался: `set_alarm(level, tick_phase)` передаёт сдвиг пустоты по уровню тревоги просветам граней облака (AssetMaterials.set_sky_void),
## как Environment.background_color клиента. Удалить класс вместе с вызовами клиента — карточка Godot.


func _init() -> void:
	name = "BackdropDome"


## Свет пустоты по уровню тревоги (0…4) и доле такта: просветам граней облака. Спокойный узел — ноль.
func set_alarm(level: int, tick_phase := 0.0) -> void:
	AssetMaterials.set_sky_void(get_tree(), void_for(level, tick_phase))


## Свет пустоты по уровню тревоги: alarm_background(level) − alarm_background(0), без отрицательных каналов (сам фон рисует Environment клиента, CALM_BG + этот сдвиг).
static func void_for(level: int, tick_phase := 0.0) -> Color:
	var c := AssetMaterials.alarm_background(level, tick_phase)
	var calm := AssetMaterials.alarm_background(0)
	return Color(maxf(c.r - calm.r, 0.0), maxf(c.g - calm.g, 0.0), maxf(c.b - calm.b, 0.0))

class_name WorldServer
extends Node
## Сервер мира (каркас G0): живёт без экрана, выходит по сигналу или по `--exit-after=<секунды>`.
## Сетевая часть (ENet) и логика мира — в следующих задачах.

signal stopped

var _exit_after: float = -1.0
var _elapsed: float = 0.0


func start(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--exit-after="):
			_exit_after = float(a.trim_prefix("--exit-after="))
	print("[netrun-server] запущен, Godot ", Engine.get_version_info().string)
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _exit_after >= 0.0 and _elapsed >= _exit_after:
		stop("по таймеру --exit-after")


func stop(reason: String) -> void:
	set_process(false)
	print("[netrun-server] остановка: ", reason)
	stopped.emit()
	get_tree().quit()


# SIGINT/SIGTERM на Unix Godot приводит к закрытию окна (в headless — тоже).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop("сигнал завершения")

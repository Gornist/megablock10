class_name IceNode
extends Node3D
## Узел ICE в сцене: держит шим IceBrain (позиция, взгляд, состояние для снимка и журнала). Сам не думает и не двигается: Soft ICE шагает
## по такту (TickIce), Black ICE логова — TickBlack, обе стороны ставят position узла из GrayNode.
## Добычу не трогает: сигнал ejected — для NetServer/узла, который сам решает, что делать с предметами.

signal ejected(session: String, reason: String)

var brain: IceBrain
## сессия → позиция (Vector3) нетраннеров узла; заполняет владелец узла (журнал берёт отсюда расстояние до игрока).
var targets: Dictionary = {}


## black — Black ICE логова (подменяется на TickBlackBrain); waypoints — маршрут: шим смотрит от первой точки ко второй.
func setup(black: bool = false, waypoints: Array[Vector3] = []) -> void:
	brain = IceBrain.new(black, position)
	if waypoints.size() > 1:
		var d := Vector3(waypoints[1].x - waypoints[0].x, 0.0, waypoints[1].z - waypoints[0].z)
		if d.length() > 0.0001:
			brain.facing = d.normalized()
	brain.ejected.connect(func(s: String, r: String) -> void: ejected.emit(s, r))

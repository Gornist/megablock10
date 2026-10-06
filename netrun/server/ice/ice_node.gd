class_name IceNode
extends Node3D
## Обёртка IceBrain для сцены: ставит позицию узла, думает 10 раз в секунду и только если в узле есть нетраннеры.
## Добычу не трогает: сигнал ejected — для NetServer/узла, который сам решает, что делать с предметами.

signal ejected(session: String, reason: String)

const THINK_INTERVAL := 0.1

var brain: IceBrain
## Сколько нетраннеров сейчас в узле; 0 — ICE спит (не думает и не двигается).
var netrunner_count := 0
## сессия → позиция (Vector3) и сессия → TraceMeter; заполняет владелец узла.
var targets: Dictionary = {}
var meters: Dictionary = {}

## Общие часы узла (секунды): TraceMeter сессий и демоны живут по ним же. Не задан — свои часы ICE.
var time_source: Callable

var _acc := 0.0
var _clock := 0.0


func setup(settings: Dictionary = {}, waypoints: Array[Vector3] = []) -> void:
	brain = IceBrain.new(settings, position, waypoints)
	brain.ejected.connect(func(s: String, r: String) -> void: ejected.emit(s, r))


func _physics_process(delta: float) -> void:
	if brain == null or netrunner_count <= 0:
		_acc = 0.0
		if brain != null:
			brain.rest()   # общие часы идут и без игрока: без этого первый шаг после возврата получает dt = всё время отсутствия
		return
	_acc += delta
	while _acc >= THINK_INTERVAL:
		_acc -= THINK_INTERVAL
		_clock += THINK_INTERVAL
		brain.step(time_source.call() if time_source.is_valid() else _clock, targets, meters)
	position = brain.position

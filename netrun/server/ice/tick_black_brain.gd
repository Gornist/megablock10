class_name TickBlackBrain
extends IceBrain
## Black ICE по тактам в обёртке IceBrain (docs/gamedesign/ice.md §6.1): узел и IceNode видят привычный интерфейс (state, is_hunting, position,
## ejected), а думает TickBlack. Такт приходит из узла через tick_step().

var black: TickBlack
var _view_phase := -1


func _init(tb: TickBlack) -> void:
	super._init(true, NodeGrid.center(tb.cell()))
	black = tb


## Охота закрывает порталы всем нетраннерам узла (ice.md §6.1: «под охотой порталы закрыты»).
func is_hunting(_session: String) -> bool:
	return black.is_hunting()


func target() -> String:
	return black.target()


func awareness() -> float:
	return 1.0 if black.is_hunting() else 0.0


func last_seen() -> Vector3:
	var k: Variant = black.known_cell()
	return NodeGrid.center(k) if k != null else position


## Один такт: ctx как у TickBlack.tick; события — как есть. Выброс по флэтлайну (ejected, black_caught) здесь НЕ шлётся: цепочка выброса синхронно доходит до
## run.finish, а журнал (_black_log) должен быть записан раньше — выбрасывает узел, получив события (GrayNode._step_tick_black).
func tick_step(ctx: Dictionary) -> Array:
	var events := black.tick(ctx)
	position = NodeGrid.center(black.cell())
	var st := State.PATROL
	match black.phase:
		TickBlack.Phase.WAKING:
			st = State.SUSPICIOUS
		TickBlack.Phase.HUNT:
			st = State.HUNT
	_set_state(st)
	return events


## Нетраннер ушёл из узла: ICE его забывает; ожоги остаются за забегом (в словаре владельца).
func forget(session: String) -> void:
	black.forget(session)

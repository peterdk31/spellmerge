extends Node
## A stand-in simulation script for tests/core/test_sim_rules.gd: a tick step, a view function (its
## drawing, in VIEW) and a line marked as view. Never run.

## Not state: the drawing.
const VIEW: Array[StringName] = [&"_process", &"_drawn_at"]

var _left: float = 1.0
var _drawn_at: float = 0.0


func step(delta: float) -> void:
	_left -= delta
	_drawn_at = sin(_left) # view: a wobble only drawn


func _process(_delta: float) -> void:
	_drawn_at = float(Time.get_ticks_msec())
	if _drawn_at > 0.0:
		_drawn_at = sin(_drawn_at)


func left() -> float:
	return _left

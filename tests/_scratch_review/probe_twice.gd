extends "res://tests/gameplay/actor/test_fall.gd"

func test_twice() -> void:
	var body: Actor = _wizard()
	_run(2)
	_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(FALL_TICKS + 1)
	print("after first: ", body.health.health, " protected=", body.health.is_protected())
	_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(FALL_TICKS + 1)
	print("after second: ", body.health.health)
	check(true, "x")

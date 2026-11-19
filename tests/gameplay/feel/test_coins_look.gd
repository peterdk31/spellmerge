extends "res://tests/support/suite.gd"
## The coins' look (connected biomes CB10, gameplay/feel/coins.gd): a coin said laid is drawn; one
## said gone is drawn on as it goes, stage by stage (at least 3 frames, docs/STYLE.md "Smooth"), and
## then no more.

const EventsScript := preload("res://core/events/events.gd")
const CoinsScript := preload("res://gameplay/feel/coins.gd")


func test_a_coin_comes_and_goes_by_stages() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var look := CoinsScript.new()
	root.add_child(look)
	own(look)
	look.bind(bus)
	bus.coin_changed.emit(3, Vector2(10, 10), true)
	check_equal([look.count(), look.lying()], [1, 1], "drawn once laid")
	for frame in 20:
		look._process(1.0 / 60.0)
	bus.coin_changed.emit(3, Vector2(10, 10), true)
	check_equal(look._stage_of(float((look._coins[3] as Array)[1])), 2, "said again (a restore), it stays whole: no pop")
	bus.coin_changed.emit(3, Vector2(10, 10), false)
	check_equal([look.count(), look.lying()], [1, 0], "still drawn as it goes")
	for frame in 3:
		look._process(1.0 / 60.0)
	check_equal(look.count(), 1, "for at least 3 frames")
	for frame in 20:
		look._process(1.0 / 60.0)
	check_equal(look.count(), 0, "then no more")

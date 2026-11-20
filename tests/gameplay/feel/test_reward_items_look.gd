extends "res://tests/support/suite.gd"
## The reward items' look (gameplay/feel/reward_items.gd; the owner's ask of 2026-11-19): an item
## said lying comes in by its stages, never popping; said gone, it goes back down them; a restore's
## forgetting (-1) drops those not said again; each seat has its own ramp of three colours.
const EventsScript := preload("res://core/events/events.gd")
const LooksScript := preload("res://gameplay/feel/reward_items.gd")

var _bus: EventsScript
var _looks: LooksScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_looks = LooksScript.new()
	root.add_child(_looks)
	own(_looks)
	_looks.bind(_bus)


func test_it_comes_in_and_goes_by_stages() -> void:
	_bus.reward_item_changed.emit(1, 5, Vector2(10, 10), true)
	check_equal(_looks.count(), 1, "drawn")
	var seen: Array[float] = []
	for frame in 12:
		_looks._process(1.0 / 60.0)
		seen.append(_looks.frames_of(5))
	check(seen[0] < LooksScript.STAGE_FRAMES and seen.back() >= LooksScript.STAGE_FRAMES * 3.0 - 0.01, "from a sliver to whole over its stages (%s)" % [seen])
	_bus.reward_item_changed.emit(1, 5, Vector2.ZERO, false)
	_looks._process(1.0 / 60.0)
	check_equal(_looks.count(), 1, "going: still drawn, back down its stages")
	for frame in 12:
		_looks._process(1.0 / 60.0)
	check_equal(_looks.count(), 0, "then gone")


func test_a_restore_keeps_only_those_said_again() -> void:
	_bus.reward_item_changed.emit(0, 1, Vector2.ZERO, true)
	_bus.reward_item_changed.emit(2, 2, Vector2(20, 0), true)
	_bus.reward_item_changed.emit(-1, -1, Vector2.ZERO, false)
	_bus.reward_item_changed.emit(0, 1, Vector2.ZERO, true)
	_looks._process(1.0 / 60.0)
	check_equal(_looks.lying(), 1, "the one said again lies on; the other goes")


func test_each_seat_has_its_own_ramp() -> void:
	check_equal(LooksScript.PLAYER_RAMPS.size(), 12, "three colours a seat")
	check(LooksScript.PLAYER_RAMPS[1] != LooksScript.PLAYER_RAMPS[4], "seats apart")

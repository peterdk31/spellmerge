extends "res://tests/support/suite.gd"
## Each wizard's pick over the hub's trial gate (boss OB2; gameplay/feel/trial_picks.gd): one line a
## seat with a pick, in that seat's light shade, stacked upwards over the gate's place; nothing with
## no gate or no pick.

const TrialPicksScript := preload("res://gameplay/feel/trial_picks.gd")
const EventsScript := preload("res://core/events/events.gd")

const AT: Vector2 = Vector2(320.0, 200.0)

var _bus: EventsScript = null
var _picks: TrialPicksScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_picks = TrialPicksScript.new()
	root.add_child(own(_picks))
	_picks.bind(_bus)


func test_each_pick_stands_over_the_gate_in_its_seats_colour() -> void:
	for seat in 4:
		check(not _picks.label_of(seat).visible, "seat %d: hidden with nothing said" % seat)
	_bus.trial_picks_changed.emit(PackedStringArray(["Crypt arena", "", "Boss room", ""]), true, AT)
	var first: Label = _picks.label_of(0)
	var third: Label = _picks.label_of(2)
	check(first.visible and first.text == "Crypt arena", "seat 1's pick shows")
	check(not _picks.label_of(1).visible, "seat 2 picked nothing: no line")
	check(third.visible and third.text == "Boss room", "seat 3's pick shows")
	check(first.position.y + first.size.y <= AT.y, "over the gate's place")
	check(third.position.y < first.position.y, "the next line above the first")
	check(absf(first.position.x + first.size.x * 0.5 - AT.x) <= 1.0, "centred on the gate")
	var shades: PackedColorArray = Palette.shades_of(&"player_3")
	check_equal(third.get_theme_color(&"font_color"), shades[shades.size() - 1], "in seat 3's light shade")
	_bus.trial_picks_changed.emit(PackedStringArray(["Crypt arena", "", "Boss room", ""]), false, Vector2.ZERO)
	check(not first.visible and not third.visible, "no gate (the hub left): hidden")

extends "res://tests/support/suite.gd"
## A carrier's end (docs/CARRIERS.md, "Its end: when a carrier is going"): `Carrier.fade` is the
## share of its life over which it dissolves, `active_left` how long it may still act and `fade_left`
## how whole it looks, one rule for the logic and the looks (owner, 2026-10-31).
##
## godot --headless --path . --script res://tests/core/test_carrier_fade.gd


func test_a_carrier_with_no_fade_acts_to_its_end() -> void:
	var bolt: Carrier = Carriers.of(&"atom")
	check_equal(bolt.fade(), 0.0, "a shot carrier ends at once")
	check(is_equal_approx(bolt.active_left(0.4, 1.0), 0.4), "it may act its whole life left")
	check_equal(bolt.fade_left(0.01, 1.0), 1.0, "and looks whole to its end")


func test_a_beam_is_going_over_its_last_quarter() -> void:
	var beam: Carrier = Carriers.of(&"beam")
	check_equal(beam.fade(), SpellLimits.BEAM_FADE, "a beam fades over BEAM_FADE of its life")
	check(is_equal_approx(beam.active_left(0.5, 1.0), 0.5 - SpellLimits.BEAM_FADE), "it may act until it starts to fade")
	check(beam.active_left(0.2, 1.0) <= 0.0, "and not once it has (%.2f)" % beam.active_left(0.2, 1.0))
	check_equal(beam.fade_left(0.5, 1.0), 1.0, "whole before its fade")
	check(is_equal_approx(beam.fade_left(SpellLimits.BEAM_FADE * 0.5, 1.0), 0.5), "half gone half way through it")
	check_equal(beam.fade_left(0.0, 1.0), 0.0, "gone at its end")


func test_a_held_carrier_has_no_fade() -> void:
	# Switched off, a held beam ends at once: it acts and looks whole all its life.
	var beam: Carrier = Carriers.of(&"beam")
	check(is_equal_approx(beam.active_left(10.0, SpellLimits.HOLD_LIFETIME), 10.0), "a held beam acts until switched off")
	check_equal(beam.fade_left(0.01, SpellLimits.HOLD_LIFETIME), 1.0, "and looks whole")

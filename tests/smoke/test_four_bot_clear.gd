extends "res://tests/support/suite.gd"
## Which room's clear ends the 4-bot smoke test (tests/smoke/four_bot_runner.gd,
## `counts_as_a_fight`): a room that holds a fight, never the start room nor a room without one.

const RunnerScript := preload("res://tests/smoke/four_bot_runner.gd")


func _life(enemies_in: Array[int]) -> RoomLife:
	var fights: Array[RoomFight] = []
	for room in 3:
		var fight := RoomFight.new()
		if enemies_in.has(room):
			fight.enemies = [&"skeleton"] as Array[StringName]
		fights.append(fight)
	var life := RoomLife.new()
	life.begin(3, 3, fights)
	return life


func test_a_fight_rooms_clear_counts() -> void:
	check(RunnerScript.counts_as_a_fight(_life([2]), 2), "the fight room's clear is the one waited for")


func test_a_room_without_a_fight_counts_not() -> void:
	# Regression (2026-11-19): the bots walked through a shop on the way to their fight, and its clear
	# (as it is entered) ended the run before anyone cast.
	check(not RunnerScript.counts_as_a_fight(_life([2]), 1), "a shop or reward room on the way counts not")


func test_the_start_rooms_clear_counts_not() -> void:
	check(not RunnerScript.counts_as_a_fight(_life([0, 2]), 0), "the start room never counts")

extends "res://tests/support/suite.gd"
## The wizard's art is wired so the game can use it (content/wizard/base): one idle, walk and dash
## strip per player index 0-3, each a row of whole 32 px frames, and a staff. How the wizard looks
## is free to change; these checks only hold the contract the player script relies on.

const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const FRAME: int = 32
const PLAYERS: int = 4

var wizard: Node


func before_each() -> void:
	wizard = own(WizardScene.instantiate()) as Node


func _strips(property: String) -> Array[Texture2D]:
	var strips: Array[Texture2D] = []
	strips.assign(wizard.get(property))
	return strips


func _check_whole_frames(property: String) -> void:
	var strips: Array[Texture2D] = _strips(property)
	check_equal(strips.size(), PLAYERS, "%s has one strip per player" % property)
	for i in strips.size():
		var strip: Texture2D = strips[i]
		check(strip != null, "%s[%d] is set" % [property, i])
		if strip != null:
			check_equal(strip.get_height(), FRAME, "%s[%d] height" % [property, i])
			check(strip.get_width() >= FRAME and strip.get_width() % FRAME == 0, "%s[%d] is whole frames" % [property, i])


func test_idle_strips_are_whole_frames_for_every_player() -> void:
	_check_whole_frames("textures")


func test_walk_strips_are_whole_frames_for_every_player() -> void:
	_check_whole_frames("walk_textures")


func test_dash_strips_are_whole_frames_for_every_player() -> void:
	_check_whole_frames("dash_textures")


func test_every_player_gets_a_different_idle_look() -> void:
	var strips: Array[Texture2D] = _strips("textures")
	for i in strips.size():
		for j in range(i + 1, strips.size()):
			check(strips[i] != strips[j], "players %d and %d must be told apart" % [i, j])


func test_the_staff_is_set() -> void:
	check(wizard.get("staff_texture") != null, "the wizard has a staff texture")

extends "res://tests/support/suite.gd"
## The crypt's moss (ground cover GC8, content/cover/crypt_moss, decision 3): look only. It fills the
## crypt by itself, sways a little, bends and is trampled, and plays no part: fire and frost leave
## it as it is and it harms nobody.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://content/cover/crypt_moss/test_crypt_moss.gd
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const MOSS: CoverKind = preload("res://content/cover/crypt_moss/crypt_moss.tres")

var _kit: Kit


func before_each() -> void:
	_kit = Kit.new(root, MOSS)


func after_each() -> void:
	_kit.free_all()


func test_it_is_sound_and_fills_the_crypt() -> void:
	check_equal(_kit.problems(), PackedStringArray(), "its data")
	check(MOSS.fills(&"crypt"), "the crypt's biome")
	check_equal(MOSS.states.size(), 1, "one state: it never changes")
	var rest: CoverState = MOSS.states[0]
	check(rest.bend > 0.0 and rest.sway > 0.0, "it sways and bends")
	check(not rest.trampled_frames.is_empty(), "and draws trampled")
	check(rest.status == &"" and rest.spreads == &"" and rest.triggers.is_empty(), "and plays no part")


func test_fire_and_frost_leave_it_be() -> void:
	var body: Actor = _kit.world.actor(_kit.middle(_kit.cell(5, 5)), [&"health", &"hurtbox"])
	_kit.touch(&"fire", _kit.middle(_kit.cell(5, 5)), 40.0)
	_kit.touch(&"frost", _kit.middle(_kit.cell(9, 5)), 40.0)
	_kit.wait(1.0)
	check_equal(_kit.count_in(&"rest"), _kit.cover.layout.count(MOSS.id), "every cell still at rest")
	check(_kit.cover.active_cells().is_empty(), "nothing active")
	check(_kit.asked.is_empty(), "nobody harmed")
	check(not _kit.has_status(body, &"burn"), "the body stands in it unburnt")

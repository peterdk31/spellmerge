extends "res://tests/support/suite.gd"
## The hub's grass (ground cover GC8, content/cover/hub_grass, docs/milestones/ground-cover.md decision
## 2): it fills the hub by itself; fire lights it, it burns its standers and spreads fire, goes to
## ash and grows back after 30 s; frost puts it out; its burning gives off embers and smoke; its
## sheet holds every frame its states draw, trampled too.
##
## godot --headless --path . --script res://content/cover/hub_grass/test_hub_grass.gd

const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const GRASS: CoverKind = preload("res://content/cover/hub_grass/hub_grass.tres")

var _kit: Kit


func before_each() -> void:
	_kit = Kit.new(root, GRASS)


func after_each() -> void:
	_kit.free_all()


## The grass with no spread: one lit cell's own story.
func _still() -> CoverKind:
	var still := GRASS.duplicate(true) as CoverKind
	var burning: CoverState = still.states[still.state_at(&"burning")]
	burning.spreads = &""
	burning.spread_chance = 0.0
	return still


func test_it_is_sound_and_fills_the_hub() -> void:
	check_equal(_kit.problems(), PackedStringArray(), "its data")
	check(GRASS.fills(&"hub"), "the hub's biome")
	check(not GRASS.fills(&"crypt"), "not the crypt's")
	check_equal(GRASS.frame_count(), 11, "eleven frames: three at rest, two burning, ash, two trampled, then three more at rest")
	var rest: CoverState = GRASS.states[0]
	check_equal(rest.state_id, &"rest", "it starts at rest")
	check_equal(rest.frames, PackedInt32Array([0, 1, 2, 8, 9, 10]), "six tufts at rest, curved and leaning, so the grass is never a row of straight blades")
	check(not rest.trampled_frames.is_empty(), "it draws trampled frames (GC4)")
	check(rest.status == &"", "grass at rest harms nobody")


func test_fire_lights_it_and_it_burns_to_ash_then_grows_back() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(4, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"burning", "lit")
	_kit.wait(1.0)
	check_equal(_kit.state_of(cell), &"burning", "still burning a second on")
	_kit.wait(0.3)
	check_equal(_kit.state_of(cell), &"ash", "then ash")
	_kit.wait(29.0)
	check_equal(_kit.state_of(cell), &"ash", "ash for most of 30 s")
	_kit.wait(1.5)
	check_equal(_kit.state_of(cell), &"rest", "the hub's grass grows back")


func test_frost_puts_it_out() -> void:
	var cell: int = _kit.cell(6, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	_kit.touch(&"frost", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"rest", "back at rest")


func test_a_fire_spreads_through_it() -> void:
	_kit.touch(&"fire", _kit.middle(_kit.cell(9, 4)))
	_kit.wait(4.0)
	check(_kit.count_in(&"burning") + _kit.count_in(&"ash") > 5, "the fire spread beyond the cell it was lit in")


func test_it_burns_whoever_stands_in_it() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(5, 5)
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	_kit.steps(5)
	check(_kit.asked.is_empty(), "at rest it asks nothing")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.asked.size(), 1, "lit: a status asked at once")
	check_equal(_kit.asked[0][1], &"burn", "a burn")
	check(_kit.has_status(body, &"burn"), "Combat put it on")


func test_burning_it_gives_off_embers_and_smoke() -> void:
	var burning: CoverState = GRASS.states[GRASS.state_at(&"burning")]
	var kinds: Array[StringName] = []
	for look: MoteSource in burning.motes:
		check_equal(_kit.look.motes.stream_problems(look), PackedStringArray(), "%s is a sound cover stream" % look.kind)
		kinds.append(look.kind)
	check_equal(kinds, [&"ember", &"smoke"] as Array[StringName], "embers and smoke")
	var cell: int = _kit.cell(3, 3)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check(_kit.look.motes.cells_giving_off(GRASS.id, GRASS.state_at(&"burning")) >= 1, "Feel gives them off from the burning cell")
	check_equal(_kit.look.motes.cells_giving_off(GRASS.id, 0), 0, "and none from the grass at rest")

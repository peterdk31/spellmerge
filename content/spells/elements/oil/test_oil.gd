extends "res://tests/support/suite.gd"
## The Oil card (content/spells/elements/oil/; docs/milestones/oil-spill.md): an infusion with no
## status, whose point is the floor: it coats the floor where it lands and along the way it goes, and
## the oil burns long once fire lights it (the floor's rows: content/cover/floor/test_floor.gd).
## Here: the card's data, an oil bolt oiling its way and where it lands through the real runtime and
## cover, and the oil lit by a second staff's fire as that caster's (builds 2 and 3 are
## tests/gameplay/cover/test_floor_builds.gd).
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const FLOOR: CoverKind = preload("res://content/cover/floor/floor.tres")

var _kit: Kit


func before_each() -> void:
	_kit = Kit.new(root, FLOOR)
	_kit.world.projectiles.set_cap(256)


func after_each() -> void:
	_kit.free_all()


func _card() -> ElementBase:
	return load("res://content/spells/elements/oil/oil.tres") as ElementBase


func _tick(count: int) -> void:
	for i in count:
		_kit.world.run(1)
		_kit.cover.step(Fixture.STEP)


func _caster(muzzle: Vector2, cards: Array[StringName], aim: Vector2) -> Actor:
	var caster: Actor = _kit.world.actor(muzzle, [&"caster"], Fixture.Scripted.new(), [cards])
	caster.aim = aim.normalized()
	caster.position += muzzle - caster.muzzle_position()
	return caster


func _state_at(at: Vector2) -> StringName:
	return _kit.state_of(_kit.cover.layout.cell_of(at))


func test_the_card_is_an_infusion_of_the_floor() -> void:
	var card: ElementBase = _card()
	check(card != null, "oil.tres loads as an ElementBase")
	if card == null:
		return
	check_equal(card.id, &"oil", "its id is its folder")
	check_equal(card.status_id, &"", "no status: its point is the floor")
	check(not card.heals, "it does not heal")
	check(card.icon != null, "it has an icon")
	check_equal(card.icon.get_width(), 64, "drawn at 64 px")
	check_equal(card.look_id, &"", "no particle look of its own yet: its shots read by its tint (oil-spill.md)")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.tint.is_equal_approx(Palette.shades_of(&"oil")[1]), "its tint is the Oil material's base")
	check(card.description.length() <= 60, "its builder line fits")
	var rows: int = 0
	for state: CoverState in FLOOR.states:
		if state.on_element(&"oil") != &"":
			rows += 1
	check(rows >= 2, "the floor answers it (%d rows)" % rows)


func test_an_oil_bolt_oils_its_way_and_where_it_lands() -> void:
	var caster: Actor = _caster(Vector2(24.0, 72.0), [&"oil", &"bolt"], Vector2.RIGHT)
	check(caster.caster.cast(0), "the oil bolt leaves")
	_tick(90)
	var oiled: int = _kit.count_in(&"oiled") + _kit.count_in(&"oiling")
	check(oiled >= 10, "its way is oiled (%d cells)" % oiled)
	check_equal(_state_at(Vector2(120.0, 72.0)), &"oiled", "a cell along its way")
	check_equal(_state_at(Vector2(120.0, 104.0)), &"dry", "and none off it")


func test_a_second_staffs_fire_lights_it_as_its_casters() -> void:
	var oiler: Actor = _caster(Vector2(24.0, 72.0), [&"oil", &"bolt"], Vector2.RIGHT)
	check(oiler.caster.cast(0), "the oil bolt leaves")
	_tick(90)
	_kit.world.actors.erase(oiler)
	oiler.free()
	var lighter: Actor = _caster(Vector2(72.0, 24.0), [&"fire", &"atom"], Vector2.DOWN)
	check(lighter.caster.cast(0), "a fire atom across it")
	_tick(60)
	var lit: int = _kit.count_in(&"burning") + _kit.count_in(&"catching")
	check(lit >= 8, "the oil burns (%d cells)" % lit)
	var cell: int = _kit.cover.layout.cell_of(Vector2(150.0, 72.0))
	check_equal(_kit.cover.room().actor_at(cell), lighter.caster_number(), "the fire is the lighter's, not the oiler's")

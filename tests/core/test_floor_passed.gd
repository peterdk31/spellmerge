extends "res://tests/support/suite.gd"
## What passes over the floor touches it (the floor's first slice, docs/milestones/floor.md; the
## owner, 2026-11-25: every shot, dash and swing): `floor_passed`, once a tick, an entry an element
## for every shot of an element that entered a new floor cell (16 px) and for a beam's end, a
## dash's way and a swing's tip. A shot of no element passes nothing; a Skyfall shot in the air
## passes nothing; a shot an infusion gave an element passes it. `floor_touched` stays the ends'
## (a stray shot in flight opens no lock).
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _world: Fixture
## Every entry of every `floor_passed` heard: [caster, tag, element, at].
var _passed: Array = []
## How many `floor_passed` were heard, and in how many ticks.
var _sent: int = 0
var _touched: int = 0


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_passed.clear()
	_sent = 0
	_touched = 0
	_world.bus.floor_passed.connect(_on_passed)
	_world.bus.floor_touched.connect(func(_c: int, _e: StringName, _a: Vector2, _r: float, _t: int) -> void: _touched += 1)


func after_each() -> void:
	_world.free_all()


func _on_passed(casters: PackedInt32Array, tags: PackedInt64Array, elements: Array[StringName], at: PackedVector2Array) -> void:
	_sent += 1
	for n in elements.size():
		_passed.append([casters[n], tags[n], elements[n], at[n]])


## A caster at (100, 100) aiming right with `cards` on its one staff, cast once.
func _cast(cards: Array[StringName], aim: Vector2 = Vector2.RIGHT) -> Actor:
	var caster: Actor = _world.actor(Vector2(100.0, 100.0), [&"caster", &"mover"], Fixture.Scripted.new(), [cards])
	caster.aim = aim
	check(caster.caster.cast(0), "cast %s" % [cards])
	return caster


## The floor cells (16 px) the entries of `element` fell in, each once, in the order first met.
func _cells_of(element: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for entry: Array in _passed:
		if entry[2] != element:
			continue
		var at: Vector2 = entry[3]
		var cell := Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
		if not cells.has(cell):
			cells.append(cell)
	return cells


func test_a_water_bolt_touches_each_cell_along_its_way_once() -> void:
	var caster: Actor = _cast([&"water", &"bolt"])
	_world.run(20)
	var cells: Array[Vector2i] = _cells_of(&"water")
	check(cells.size() >= 6, "the cells along its way (%d)" % cells.size())
	check(_passed.size() <= cells.size() * 2, "about once a cell: a shot touches as it enters one (%d for %d)" % [_passed.size(), cells.size()])
	for n in range(1, cells.size()):
		check(cells[n].x == cells[n - 1].x + 1 and cells[n].y == cells[0].y, "every cell of its way, to the right, none skipped (%s)" % [cells])
	check_equal(_passed[0][0], caster.caster_number(), "by its caster")
	check(SpellTag.is_spell_tag(int(_passed[0][1])) and SpellTag.caster_of(int(_passed[0][1])) == caster.caster_number(), "with its spell's tag")
	check(_sent <= 20, "at most one event a tick (%d in 20)" % _sent)
	check(_touched <= 1, "floor_touched only where it ends (%d)" % _touched)


func test_every_element_of_a_shot_passes() -> void:
	_cast([&"frost", &"lightning", &"bolt"])
	_world.run(8)
	check(not _cells_of(&"frost").is_empty() and _cells_of(&"frost") == _cells_of(&"lightning"), "frost and lightning on the same cells")


func test_a_shot_of_no_element_passes_nothing() -> void:
	_cast([&"bolt"])
	_world.run(30)
	check(_passed.is_empty(), "a plain bolt: nothing")


func test_a_skyfall_shot_touches_nothing_in_the_air() -> void:
	_cast([&"water", &"skyfall", &"bolt"])
	var in_air: int = -1
	for i in 60:
		_world.run(1)
		if in_air < 0 and _touched > 0:
			in_air = _passed.size()
	check(_touched > 0, "it landed")
	check(in_air <= 2, "it passed over nothing before it came down (%d)" % in_air)


func test_a_portals_infusion_makes_a_plain_shot_pass() -> void:
	var caster: Actor = _cast([&"bolt"])
	_world.run(1)
	var slot: int = -1
	for s in _world.projectiles.get_cap():
		if _world.projectiles.is_alive(s) and _world.projectiles.get_actor_of(s) == caster.caster_number():
			slot = s
	check(slot >= 0, "the bolt flies")
	check(not _world.projectiles.trails(slot), "a plain bolt does not trail")
	var donor := HitProfile.new()
	donor.element_id = &"fire"
	donor.element_ids = [&"fire"] as Array[StringName]
	_world.spells._infuse_shot(slot, donor, Color.ORANGE)
	check(_world.projectiles.trails(slot), "infused: it trails")
	_world.run(10)
	check(not _cells_of(&"fire").is_empty(), "and passes fire")


func test_a_beams_end_pours_every_step() -> void:
	_cast([&"water", &"beam"])
	var poured: int = 0
	for i in 10:
		var was: int = _sent
		_world.run(1)
		if _world.spells.carrier(&"beam").call(&"beam_count") > 0:
			poured += 1
			check_equal(_sent, was + 1, "tick %d: a live beam's end pours" % i)
	check(poured >= 4, "it lived some ticks (%d)" % poured)


func test_a_dash_touches_its_way() -> void:
	_cast([&"frost", &"dash"])
	_world.run(30)
	var cells: Array[Vector2i] = _cells_of(&"frost")
	check(cells.size() >= 3, "the cells along its way (%d)" % cells.size())


func test_a_swing_touches_along_its_tip() -> void:
	_cast([&"fire", &"swing"])
	_world.run(40)
	check(_cells_of(&"fire").size() >= 2, "the cells its tip swept (%d)" % _cells_of(&"fire").size())
	check(_passed.size() >= 3, "along its sweep, not only at its end (%d)" % _passed.size())

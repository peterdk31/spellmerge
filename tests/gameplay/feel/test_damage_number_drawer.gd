extends "res://tests/support/suite.gd"
## Feel's drawer of every actor's damage numbers (props W5, docs/milestones/props.md;
## gameplay/feel/damage_number_drawer.gd): each `damage_number_shown` is a number in one shared
## pool, written at the next step and gone after its seconds; when every slot shows one the oldest
## gives way. Its colour is its element's (`ElementBase.tint`), white for a plain hit, the heal
## colour for a heal; a hit that took nothing is struck through. The "Damage numbers" setting
## hides them all. A storm of hits on 200 actors makes no object and no node per frame. The actors'
## side is tests/gameplay/actor/test_damage_numbers.gd.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_damage_number_drawer.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const DrawerScript := preload("res://gameplay/feel/damage_number_drawer.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const SECONDS: float = 0.8

var _bus: EventsScript
var _registry: RegistryScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


## A drawer on its own, hearing the test's bus.
func _drawer() -> DrawerScript:
	var drawer: DrawerScript = own(DrawerScript.new()) as DrawerScript
	drawer.events = _bus
	drawer.registry = _registry
	root.add_child(drawer)
	return drawer


func _show(amount: float, element: StringName = &"", kind: StringName = EventsScript.NUMBER_HIT) -> void:
	_bus.damage_number_shown.emit(0, Vector2(50.0, 50.0), amount, element, kind, 16.0, SECONDS, 1.0)


func test_a_number_per_hit_that_fades_out() -> void:
	var drawer: DrawerScript = _drawer()
	_show(12.0)
	_show(0.3)
	drawer.step(0.0)
	check_equal(drawer.shown_texts(), PackedStringArray(["12", "0.3"]), "a number per hit, to a tenth")
	drawer.step(SECONDS + 0.05)
	check_equal(drawer.live(), 0, "gone after its seconds")


func test_the_oldest_gives_way_when_every_slot_shows_one() -> void:
	var drawer: DrawerScript = _drawer()
	for i in DrawerScript.SLOTS + 2:
		_show(10.0 + i)
	drawer.step(0.0)
	check_equal(drawer.live(), DrawerScript.SLOTS, "every slot shows one")
	var texts: PackedStringArray = drawer.shown_texts()
	check_equal(texts[0], DrawerScript.text_of(10.0 + DrawerScript.SLOTS), "the first slot shows the newest but one")
	check_equal(texts[1], DrawerScript.text_of(11.0 + DrawerScript.SLOTS), "the second the newest")
	check_equal(texts[2], "12", "the third the oldest left")


func test_the_colour_says_what_kind_of_hit() -> void:
	var drawer: DrawerScript = _drawer()
	var fire := _registry.get_resource(&"spells", &"fire") as ElementBase
	var at: int = drawer.next_slot()
	_show(5.0, &"fire")
	_show(5.0)
	_show(5.0, &"", EventsScript.NUMBER_HEAL)
	_show(5.0, &"", EventsScript.NUMBER_SPARED)
	check_equal(drawer.colour_of_slot(at), Color(fire.tint, 1.0), "fire's tint")
	check_equal(drawer.colour_of_slot(at + 1), DrawerScript.PLAIN_COLOR, "a plain hit white")
	check_equal(drawer.colour_of_slot(at + 2), DrawerScript.HEAL_COLOR, "a heal green")
	check(drawer.is_spared(at + 3) and not drawer.is_spared(at), "a hit that took nothing is struck through")


func test_the_setting_hides_them_all() -> void:
	var drawer: DrawerScript = _drawer()
	_show(5.0)
	drawer.step(0.0)
	_bus.damage_numbers_changed.emit(false)
	check_equal(drawer.live(), 0, "the numbers showing go")
	_show(5.0)
	drawer.step(0.0)
	check_equal(drawer.live(), 0, "and no new one shows")
	_bus.damage_numbers_changed.emit(true)
	_show(5.0)
	drawer.step(0.0)
	check_equal(drawer.live(), 1, "on again, they show")


## Feel makes the drawer and steps it on its own clock.
func test_feel_draws_the_bus_numbers() -> void:
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = _bus
	feel.registry = _registry
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	_show(7.0)
	feel.step(0.016)
	check_equal(feel.damage_numbers().shown_texts(), PackedStringArray(["7"]), "Feel's drawer shows it")
	feel.step(SECONDS)
	check_equal(feel.damage_numbers().live(), 0, "and lets it go on Feel's clock")


## A storm of hits on 200 actors: every hit is told, and no object or node is made per frame (the
## numbers' texts are strings, not objects; the pool is made once).
func test_a_storm_on_200_actors_makes_nothing_per_frame() -> void:
	var world := Fixture.new(root)
	var drawer: DrawerScript = _drawer()
	drawer.events = null
	world.bus.damage_number_shown.connect(drawer.show_number)
	var bodies: Array[Actor] = []
	for i in 200:
		bodies.append(world.actor(Vector2(float(i % 20) * 24.0, float(i / 20) * 24.0), [&"health", &"hurtbox"]))
	for body in bodies:
		body.health.max_health = 1.0e9
		body.health.reset(1.0e9)
	# Two frames first, so whatever is made once (the font's cache of each glyph: every digit and
	# the point) is made; then the storm's frames are measured.
	for warm in 2:
		for body in bodies:
			world.combat.hit(0, body, 1234.5 if body.id % 2 == warm else 6789.0)
		world.combat.hit(0, bodies[0], 0.3)
		drawer.step(0.016)
		await process_frame
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for frame in 10:
		for body in bodies:
			world.combat.hit(0, body, 3.0 + float(frame))
		drawer.step(0.016)
		await process_frame
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "no object made in the storm")
	check_equal(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), nodes, "no node made")
	check_equal(drawer.live(), DrawerScript.SLOTS, "the pool full, the oldest giving way")
	world.free_all()

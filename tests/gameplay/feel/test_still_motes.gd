extends "res://tests/support/suite.gd"
## Still motes (gameplay/feel/still_motes.gd; the owner, 2026-11-09: "use motes for everything you
## can"): a still carrier card that names `look_motes` has its shots give off that kind all the time
## while they stand, from a view of where the projectile manager draws them (`watch_body`,
## `still_shots_drawn`, `StillShotView`): along each piece of a wall's row, over a pool's oval (the
## card's `look_shape`, which its shader draws by too), thinning while it comes and as it goes
## (`look_open`, `look_fade`), in the shot's colours and now and then its infusions' own kinds.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_still_motes.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const StillMotesScript := preload("res://gameplay/feel/still_motes.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const WALL := preload("res://content/spells/forms/wall/wall.tres")
const POOL := preload("res://content/spells/forms/pool/pool.tres")
const FIRE_LOOK: int = 1 << 0

var mgr: ManagerScript
var motes: MotesScript
var still: StillMotesScript
var spells: SpellRuntime


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.actors = own(ActorSeats.table()) as ActorsScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	mgr.set_cap(200)
	root.add_child(mgr)
	spells = own(SpellsScript.new()) as SpellRuntime
	spells.registry = registry
	spells.projectiles = mgr
	spells.register_bodies()
	var kinds: Array[MoteKind] = []
	for kind: Resource in registry.get_all(&"motes"):
		kinds.append(kind as MoteKind)
	motes = own(MotesScript.new(4096, 0, kinds)) as MotesScript
	motes.set_infusions(InfusionTable.of_registry(registry))
	root.add_child(motes)
	still = StillMotesScript.new()
	still.attach(mgr, spells)
	mgr.still_shots_drawn.connect(func(view: StillShotView) -> void: still.give_off(view, motes))


## A still shot of `form`'s body at `at` living `life` seconds; a wall's a row of five across x.
func _place(form: FormBase, at: Vector2, life: float = 5.0) -> int:
	var slot: int = mgr.spawn(0, at, Vector2.ZERO, life, form.radius, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_form(slot, form.id, mgr.register_body(form.look_shader, ManagerScript.MESH_QUAD))
	if form.carrier == &"wall":
		mgr.set_solid(slot, Vector2.RIGHT, form.shots, form.spread)
	return slot


## Step and draw `frames` frames of 1/60 s.
func _run(frames: int) -> void:
	for n in frames:
		mgr.step(1.0 / 60.0)
		motes.step(mgr.sim_time)
		mgr.update_draw(1.0)


## The rows of the motes written from `from` on, as [x, y, kind id].
func _written(from: int) -> Array:
	var found: Array = []
	for row in range(from, motes.next_row()):
		var data: PackedFloat32Array = motes.row_data(row)
		var kind: MoteKind = motes.kinds()[roundi(data[MotesScript.ROW_KIND] * MotesScript.KIND_CODE)]
		found.append([data[MotesScript.ROW_X], data[MotesScript.ROW_Y], kind.id])
	return found


func test_the_wall_and_the_pool_name_their_motes() -> void:
	for form: FormBase in [WALL, POOL]:
		check_equal(form.look_motes, &"rising", "%s gives off rising motes" % form.id)
		check(form.look_mote_rate > 0.0, "%s gives some off every second" % form.id)
		check(form.look_problems().is_empty(), "%s: %s" % [form.id, form.look_problems()])
	check_equal(WALL.look_motes_from, FormBase.LOOK_MOTES_ROW, "a wall's leave along its row")
	check_equal(POOL.look_motes_from, FormBase.LOOK_MOTES_AREA, "a pool's over its oval")
	var cards: Array[StringName] = spells.still_mote_cards()
	check(cards.has(&"wall") and cards.has(&"pool") and not cards.has(&"rune"), "Spells names the still cards that give off motes (%s)" % [cards])


func test_a_body_first_numbered_at_a_launch_is_shaped_too() -> void:
	var later := own(ManagerScript.new()) as ManagerScript
	root.add_child(later)
	spells.projectiles = later
	var body: int = spells._body_of(&"pool", POOL.look_shader, ManagerScript.MESH_QUAD)
	check(body > 0, "a launch numbers a body the start did not")
	var material := later._nodes[ManagerScript.body_batch(body, false)].material as ShaderMaterial
	check_equal(material.get_shader_parameter(&"look_shape"), POOL.look_shape, "and shapes it by its card, as the start does")
	check_equal(spells._body_of(&"pool", POOL.look_shader, ManagerScript.MESH_QUAD), body, "asked again, the same body")
	spells.projectiles = mgr


func test_motes_on_a_card_that_cannot_give_them_off_are_reported() -> void:
	var form := FormBase.new()
	form.id = &"test_form"
	form.carrier = &"atom"
	form.look_motes = &"rising"
	form.look_mote_rate = 10.0
	check(" ".join(form.look_problems()).contains("never given off"), "a flying card's still motes are reported")


func test_a_wall_streams_motes_along_its_row() -> void:
	_run(30)
	var before: int = motes.next_row()
	_place(WALL, Vector2(200.0, 150.0))
	_run(90)
	var found: Array = _written(before)
	# Five pieces at 16 a second for about 1.5 s, less while its seam opens.
	check(found.size() > 60, "a stream of motes (%d)" % found.size())
	var half: float = WALL.spread * 2.0 + WALL.radius * 4.0
	for each: Array in found:
		var at := Vector2(each[0], each[1])
		check(absf(at.x - 200.0) <= half and absf(at.y - 150.0) <= 6.0, "a mote leaves from along the row (%s)" % at)
	check(found.all(func(each: Array) -> bool: return each[2] == &"rising"), "all rising: a plain wall has no infusion kinds")


func test_none_while_it_comes_in_and_fewer_as_it_goes() -> void:
	var end: float = ManagerScript.STILL_END
	check_equal(StillMotesScript.strength(0.0, end, 0.3, 0.8), 0.0, "none the moment it is placed")
	check(is_equal_approx(StillMotesScript.strength(0.15, end, 0.3, 0.8), 0.5), "half way through opening, half")
	check(is_equal_approx(StillMotesScript.strength(ManagerScript.STILL_START, end, 0.3, 0.8), 1.0), "all once it stands")
	var ending: float = StillMotesScript.strength(ManagerScript.STILL_START, 0.4, 0.3, 0.8)
	check(ending > 0.0 and ending < 0.5, "fewer near its end (%f)" % ending)
	check_equal(StillMotesScript.strength(ManagerScript.STILL_START, 0.0, 0.3, 0.8), 0.0, "none at its end")
	check(is_equal_approx(StillMotesScript.strength(0.0, end, 0.0, 0.0), 1.0), "a card that opens and fades at once gives off all from the start")


func test_the_card_shapes_its_shader_and_its_motes_alike() -> void:
	for form: FormBase in [WALL, POOL]:
		var body: int = mgr.body_of(form.look_shader, ManagerScript.MESH_QUAD)
		check(body > 0 and still.watches(body), "%s's body is watched" % form.id)
		var material := mgr._nodes[ManagerScript.body_batch(body, false)].material as ShaderMaterial
		check_equal(material.get_shader_parameter(&"look_shape"), form.look_shape, "%s's shader draws by its card's shape" % form.id)
		check_equal(material.get_shader_parameter(&"look_clock"), Vector2(form.look_open, form.look_fade), "and comes and goes by its card's clock")
		var look: CardLook = spells.look_of(form.id, Carrier.LOOK_STILL)
		check(look.shape == form.look_shape and look.open == form.look_open and look.fade == form.look_fade, "%s's motes read the same numbers (its CardLook)" % form.id)
		var own: String = form.look_shader.code
		check(own.contains("STILL_HIT") and not own.contains("0.15"), "%s's shader takes its hit size from STILL_HIT, not a copy" % form.id)


func test_a_fire_pool_gives_off_embers_too() -> void:
	_run(30)
	var before: int = motes.next_row()
	var slot: int = _place(POOL, Vector2(300.0, 200.0))
	mgr.set_core(slot, Color("e0592f"))
	mgr.set_look(slot, FIRE_LOOK)
	_run(120)
	var found: Array = _written(before)
	var embers: int = found.filter(func(each: Array) -> bool: return each[2] == &"ember").size()
	check(found.size() > 40, "many motes off the pool (%d)" % found.size())
	check(embers > 0 and embers < found.size(), "some are fire's embers, most rising (%d of %d)" % [embers, found.size()])
	for each: Array in found:
		var at := Vector2(each[0], each[1]) - Vector2(300.0, 200.0)
		check(absf(at.x) <= 30.0 and absf(at.y) <= 16.0, "a mote leaves from the pool's oval (%s)" % at)


func test_a_card_with_no_still_motes_gives_none() -> void:
	var rune: FormBase = load("res://content/spells/forms/rune/rune.tres") as FormBase
	_run(30)
	var before: int = motes.next_row()
	_place(rune, Vector2(100.0, 100.0))
	_run(60)
	check_equal(_written(before).size(), 0, "a rune's motes are its shader's")
	check(not still.watches(mgr.body_of(rune.look_shader, ManagerScript.MESH_QUAD)), "a card that names no motes is not watched")

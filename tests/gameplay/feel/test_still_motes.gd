extends "res://tests/support/suite.gd"
## Still motes (gameplay/feel/still_motes.gd; the owner, 2026-11-09: "use motes for everything you
## can"): a still carrier card that names `look_motes` has its shots give off that kind all the time
## while they stand, from the rows the projectile manager draws them by (`watch_rows`, `rows_drawn`):
## along each piece of a wall's row, over a pool's oval, thinning while it comes and as it goes (its
## still clock), in the shot's colours and now and then its infusions' own kinds.
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
var spells: Node


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.actors = own(ActorSeats.table()) as ActorsScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	mgr.set_cap(200)
	root.add_child(mgr)
	spells = own(SpellsScript.new()) as Node
	spells.set(&"registry", registry)
	spells.set(&"projectiles", mgr)
	spells.call(&"register_bodies")
	var kinds: Array[MoteKind] = []
	for kind: Resource in registry.get_all(&"motes"):
		kinds.append(kind as MoteKind)
	motes = own(MotesScript.new(4096, 0, kinds)) as MotesScript
	motes.set_infusions(InfusionTable.of_registry(registry))
	root.add_child(motes)
	still = StillMotesScript.new()
	still.attach(mgr, spells)
	mgr.rows_drawn.connect(func(batch: int, rows: PackedFloat32Array, count: int) -> void:
		still.give_off(batch, rows, count, mgr.sim_time, motes))


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
	check_equal(WALL.look_motes_from, StillMotesScript.FROM_ROW, "a wall's leave along its row")
	check_equal(POOL.look_motes_from, StillMotesScript.FROM_AREA, "a pool's over its oval")
	var cards: Array[StringName] = spells.call(&"still_mote_cards")
	check(cards.has(&"wall") and cards.has(&"pool") and not cards.has(&"rune"), "Spells names the still cards that give off motes (%s)" % [cards])


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
	check_equal(StillMotesScript.strength(1.0 - (ManagerScript.KIND_RUNE + ManagerScript.still_code(0.0, 3.0)) / ManagerScript.KIND_STEPS), 0.0, "none the moment it is placed")
	check(is_equal_approx(StillMotesScript.strength(1.0 - ManagerScript.KIND_RUNE / ManagerScript.KIND_STEPS), 1.0), "all once it stands")
	var ending: float = StillMotesScript.strength(1.0 - (ManagerScript.KIND_RUNE + ManagerScript.still_code(3.0, 0.4)) / ManagerScript.KIND_STEPS)
	check(ending > 0.0 and ending < 0.5, "fewer near its end (%f)" % ending)
	check_equal(StillMotesScript.strength(1.0 - (ManagerScript.KIND_RUNE + ManagerScript.still_code(3.0, 0.0)) / ManagerScript.KIND_STEPS), 0.0, "none at its end")


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
	check(not still.watches(ManagerScript.BATCH_STILL), "the plain still batch is not watched")

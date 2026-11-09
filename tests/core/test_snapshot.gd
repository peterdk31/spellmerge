extends "res://tests/support/suite.gd"
## Snapshots (online-ready N10, core/sim/snapshot.gd): a scripted scene (tests/core/sim_scenes.gd)
## snapshotted at a tick and restored into a fresh world of the same kind plays on with the same
## hashes in every area at every tick as the scene it was taken from. A member wrongly in DERIVED
## (state that is not saved) parts the two, and the desync report names it.
##
## Each scene takes seconds: the runner plays them in processes of their own (tests/support/suite.gd):
# unit-test-shards: 2

const SimScenes := preload("res://tests/core/sim_scenes.gd")
const ContentFight := preload("res://tests/core/content_fight.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const DecoyCard := preload("res://content/spells/forms/decoy/decoy.tres")
const PoolCard := preload("res://content/spells/forms/pool/pool.tres")
const BoltCard := preload("res://content/spells/forms/bolt/bolt.tres")

## Ticks played before the snapshot, and after it.
const BEFORE: int = 70
const AFTER: int = 80
## Ticks a decoy fight plays after its snapshot: past several decoys' ends and new ones.
const DECOY_AFTER: int = 240
## Between the storm's casts (at 0, 0.2 and 0.5 s).
const STORM_EARLY: int = 20


func test_a_staffed_fight_restored_plays_on_the_same() -> void:
	_check_restored(&"fight", BEFORE)


func test_a_fight_restored_at_its_start_plays_on_the_same() -> void:
	_check_restored(&"fight", 1)


## Before the storm's last casts (its stage casts them on its own clock, the scene's input, which
## the restored stage takes on), and after them.
func test_a_spell_storm_restored_plays_on_the_same() -> void:
	_check_restored(&"storm", STORM_EARLY)
	_check_restored(&"storm", BEFORE)


## A possession under way: the enemy's controller drives one wizard and a puppet added in play
## drives the other (a node no scene makes, and controllers pointed at in another body).
## One part of a world, for the unit tests below.
class Item:
	extends RefCounted
	var n: int = 0
	var tags: Array[StringName] = []

	## Idle while it holds nothing (`StateWalk`'s idle objects).
	func idle() -> bool:
		return n == 0 and tags.is_empty()


## Made in code: state like any object, not content.
class Data:
	extends Resource
	var v: int = 0


class Holder:
	extends RefCounted
	const SPARES: Array[StringName] = [&"spares"]
	var order: Dictionary[StringName, int] = {}
	var items: Array[Item] = []
	var first: Item = null
	var again: Item = null
	var waiting: Item = Item.new()
	var nested: Array = []
	var numbers: PackedFloat32Array = PackedFloat32Array()
	var names: Array[StringName] = []
	var spares: Array[Item] = []
	var data: Data = Data.new()


## The pieces of a snapshot, without a game: values copied, arrays and dictionaries with their
## types and their order, an object met twice one object, an idle object fresh, a spare list its
## size, a resource made in code copied; restored into the same holder twice and into a new one.
func test_a_snapshot_restores_plain_objects() -> void:
	var holder := Holder.new()
	for key: StringName in [&"b", &"a", &"c"]:
		holder.order[key] = holder.order.size()
	var item := Item.new()
	item.n = 3
	item.tags = [&"x"]
	holder.items = [item, Item.new()]
	holder.first = item
	holder.again = item
	holder.nested = [[1, 2], {"k": item}]
	holder.numbers = PackedFloat32Array([1.5, 2.5])
	holder.names = [&"p", &"q"]
	holder.spares = [Item.new(), Item.new(), Item.new()]
	holder.data.v = 7
	var snapshot := Snapshot.take({"holder": holder})
	_check_problems(&"plain", snapshot.problems)
	for target: Holder in [holder, holder, Holder.new()]:
		# What happens after the snapshot, undone by it.
		holder.order.erase(&"b")
		holder.order[&"b"] = 9
		item.n = 99
		holder.again = Item.new()
		holder.numbers[0] = -1.0
		holder.names.append(&"r")
		holder.spares.clear()
		holder.data.v = 8
		holder.waiting.n = 5
		check_equal(snapshot.restore({"holder": target}).size(), 0, "restored without problems")
		check_equal(target.order.keys(), [&"b", &"a", &"c"], "a dictionary keeps the order it was filled in")
		check_equal(target.order.get_typed_key_builtin(), TYPE_STRING_NAME, "and its type")
		check_equal(target.first.n, 3, "an object's members")
		check(target.first == target.again, "an object met twice is one object")
		check(target.items[0] == target.first, "in an array too")
		check(target.items.get_typed_script() == Item, "an array keeps its type")
		check(target.nested[1]["k"] == target.first, "and inside untyped arrays and dictionaries")
		check_equal(target.nested[0], [1, 2], "plain values")
		check_equal(target.numbers, PackedFloat32Array([1.5, 2.5]), "a packed array")
		check_equal(target.names, [&"p", &"q"] as Array[StringName], "a typed array of values")
		check_equal(target.waiting.n, 0, "an idle object comes back fresh")
		check_equal(target.spares.size(), 3, "a spare list comes back at its size")
		check_equal(target.data.v, 7, "a resource made in code is state, copied")
	check(snapshot.restore({"holder": holder}).is_empty() and holder.data.v == 7, "the snapshot itself never changed")


## An object that makes nodes from its state (`restore_nodes`), holding another that does too; the
## calls go to one list both share (not state).
class Maker:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"calls"]
	var label: String = ""
	var inner: Maker = null
	var calls: Array[String] = []

	func restore_nodes() -> void:
		calls.append(label)


## `restore_nodes()` of every object restored that has one, the outermost first: a holder sets up
## what it holds before that one makes its nodes (core/sim/snapshot.gd, step 4).
func test_restore_nodes_runs_outermost_first() -> void:
	var outer := Maker.new()
	outer.label = "outer"
	outer.inner = Maker.new()
	outer.inner.label = "inner"
	var calls: Array[String] = []
	outer.calls = calls
	outer.inner.calls = calls
	var snapshot := Snapshot.take({"maker": outer})
	_check_problems(&"makers", snapshot.problems)
	check_equal(snapshot.restore({"maker": outer}).size(), 0, "restored without problems")
	check_equal(calls, ["outer", "inner"] as Array[String], "the holder first, then what it holds")


## Restored into a plain fight (no possession, no puppet), so both are made again.
func test_a_possessed_fight_restored_plays_on_the_same() -> void:
	_check_restored(&"possessed", BEFORE, &"fight")
	var played := SimScenes.new(root, &"possessed")
	for i in BEFORE:
		played.step()
	var snapshot := Snapshot.take(played.areas(), played.world())
	var restored := SimScenes.new(root, &"fight")
	_check_problems(&"possessed", restored.restore(snapshot, played))
	var areas: Dictionary = restored.areas()
	var first: Actor = areas["actor 0"]
	var second: Actor = areas["actor 1"]
	var enemy: Actor = areas["actor 2"]
	var puppet: Node = second.get_node_or_null(^"Puppet")
	check(puppet is PuppetController, "the puppet added in play is made again")
	check(second.controller == puppet, "the puppet drives the second wizard")
	check(first.controller == enemy.home_controller, "the enemy's controller drives the first wizard")
	check(first.possessed_by != null and enemy.home_controller.possessions.has(first.possessed_by), "the possession is one object, held by its target and its driver")
	played.free_all()
	restored.free_all()


## The same world restored to an earlier tick (rollback, later) plays on as it did from there,
## twice from one snapshot; the fight after an enemy died since (made again from its scene) and an
## imp joined (freed).
func test_a_fight_rolled_back_plays_on_the_same() -> void:
	_check_rolled_back(&"fight")


## The storm rolled back: shots, carriers and the stage's imps of another timeline.
func test_a_storm_rolled_back_plays_on_the_same() -> void:
	_check_rolled_back(&"storm")


## Play `scene` for `before` ticks, snapshot it, play on, and restore the snapshot into the same
## world twice (the fight disturbed first): each time it plays on as the first time did.
func _check_rolled_back(scene: StringName, before: int = BEFORE) -> void:
	var played := SimScenes.new(root, scene)
	for i in before:
		played.step()
	var snapshot := Snapshot.take(played.areas(), played.world())
	_check_problems(scene, snapshot.problems)
	var input := _input_of(played)
	var first := Desync.new()
	for i in AFTER:
		played.step()
		first.capture(played.areas())
	for again in 2:
		played.disturb()
		_check_problems(scene, played.restore(snapshot, input))
		var names: Array = played.areas().keys()
		var taken: Array = snapshot.areas.keys()
		names.sort()
		taken.sort()
		check_equal(names, taken, "%s rolled back (%d): its bodies are the snapshot's" % [scene, again])
		var later := Desync.new()
		for i in AFTER:
			played.step()
			later.capture(played.areas())
		check_equal(Desync.first_parting(first, later), -1, "%s rolled back (%d) plays on as it did" % [scene, again])
	played.free_all()


## A scene of the same kind, standing in for `played`'s input at this tick (the stage's casts to
## come), as `restore` takes it.
func _input_of(played: SimScenes) -> Object:
	return played.input_copy()


## Play `scene` for `before` ticks, snapshot it, then play it on and, beside it, a fresh scene
## restored from the snapshot; the two agree at the snapshot's tick and every tick after.
func _check_restored(scene: StringName, before: int, fresh_as: StringName = &"") -> void:
	var tick: int = _parting(scene, before, -1, fresh_as)
	if tick == -1:
		return
	# Again, keeping the parting tick's leaves, so the report names the members.
	var a := Desync.new(tick)
	var b := Desync.new(tick)
	_parting(scene, before, tick, fresh_as, a, b)
	check(false, "%s restored at tick %d: %s" % [scene, before, Desync.compare(a, b)])


## The first tick (0 = right after the restore) the played scene and the restored one part, or -1.
## The restored scene is made as `fresh_as` (the same scene when empty), then plays as `scene`.
func _parting(scene: StringName, before: int, keep: int, fresh_as: StringName = &"", a: Desync = null, b: Desync = null) -> int:
	var played := SimScenes.new(root, scene)
	for i in before:
		played.step()
	var snapshot := Snapshot.take(played.areas(), played.world())
	if keep == -1:
		_check_problems(scene, snapshot.problems)
	var restored := SimScenes.new(root, fresh_as if fresh_as != &"" else scene)
	restored.name = scene
	var problems: PackedStringArray = restored.restore(snapshot, played)
	if keep == -1:
		_check_problems(scene, problems)
	var first: Desync = a if a != null else Desync.new()
	var second: Desync = b if b != null else Desync.new()
	first.capture(played.areas())
	second.capture(restored.areas())
	for i in AFTER:
		played.step()
		restored.step()
		first.capture(played.areas())
		second.capture(restored.areas())
	played.free_all()
	restored.free_all()
	return Desync.first_parting(first, second)


func _check_problems(scene: StringName, problems: PackedStringArray) -> void:
	for problem in problems:
		check(false, "%s: %s" % [scene, problem])


## A decoy restored is a whole decoy (online-ready N10b): Entities builds its decoys in code and
## pools them, so the snapshot asks it to make one again (`remake_body`): its components and mind,
## off the Tick (Entities steps it), its row's again, and its owner's look copied onto it.
func test_a_decoy_restored_is_made_again_by_entities() -> void:
	var played := ContentFight.new(root, ContentFight.CARD, DecoyCard)
	var at: int = -1
	for i in 240:
		played.step()
		if played.entities.count(EntitiesScript.DECOY) > 0:
			at = i
			break
	check(at >= 0, "the decoy card made a decoy")
	var snapshot := Snapshot.take(played.areas(), played.world)
	_check_problems(&"decoy", snapshot.problems)
	played.free_all()
	var restored := ContentFight.new(root, ContentFight.CARD, DecoyCard)
	_check_problems(&"decoy", restored.restore(snapshot, at))
	var decoy: Actor = null
	for child: Node in restored.entities.get_children():
		if child is Actor:
			decoy = child as Actor
	check(decoy != null, "the decoy is made again under Entities")
	if decoy == null:
		restored.free_all()
		return
	check(restored.entities.decoy_of(decoy.belongs_to) == decoy, "its row holds it again")
	check(decoy.health != null and decoy.get_node_or_null(^"Hurtbox") is Hurtbox and decoy.get_node_or_null(^"Mover") is Mover and decoy.get_node_or_null(^"Caster") is Caster, "it has its components")
	check(decoy.get_node_or_null(^"Mind") is DecoyController and decoy.controller == decoy.get_node(^"Mind"), "its mind drives it")
	check(not decoy.ticking, "Entities steps it, not the Tick")
	var look: DecoyLook = decoy.get_node_or_null(^"Look") as DecoyLook
	check(look != null and look.sprite.texture != null, "it looks like its owner again")
	restored.free_all()


## A decoy fight rolled back into the same world plays on as it did, twice from one snapshot
## (online-ready N10b): after the snapshot decoys end and rows hold new ones, which may take the actor
## ids of the snapshot's decoys (ids are handed out again), so a body built in code is matched by its
## name (its row) as well as its id, and each decoy is made new, with nothing of an earlier one.
func test_a_decoy_fight_rolled_back_plays_on_the_same() -> void:
	var fight := ContentFight.new(root, ContentFight.CARD, DecoyCard)
	var at: int = -1
	for i in 240:
		fight.step()
		if fight.entities.count(EntitiesScript.DECOY) > 0:
			at = i
			break
	check(at >= 0, "the decoy card made a decoy")
	var snapshot := Snapshot.take(fight.areas(), fight.world)
	_check_problems(&"decoy", snapshot.problems)
	var first := Desync.new()
	for i in DECOY_AFTER:
		fight.step()
		first.capture(fight.areas())
	for again in 2:
		_check_problems(&"decoy", fight.restore(snapshot, at))
		var later := Desync.new()
		for i in DECOY_AFTER:
			fight.step()
			later.capture(fight.areas())
		check_equal(Desync.first_parting(first, later), -1, "the decoy fight rolled back (%d) plays on as it did" % again)
	fight.free_all()


## A decoy whose actor id another row's decoy took after the snapshot (ids are handed out again)
## comes back as its own row's when the world is rolled back (online-ready N10b): a body built in
## code is matched by its name as well as its id, so the other row's is freed and this one made again.
func test_a_rolled_back_decoy_is_its_rows_though_its_id_was_taken() -> void:
	var fight := ContentFight.new(root, ContentFight.CARD, BoltCard)
	var wizard: Actor = fight.fight.players[0]
	var enemy: Actor = fight.fight.enemies[0]
	var bus: Node = fight.fight.bus
	bus.emit_signal(&"entity_spawn_requested", wizard.id, EntitiesScript.DECOY, Vector2(20.0, 0.0), 6.0, 1, EntitiesScript.CASTER_BODY)
	var own: Actor = fight.entities.decoy_of(wizard.id)
	check(own != null, "the wizard's decoy is made")
	if own == null:
		fight.free_all()
		return
	var own_name: StringName = own.name
	var own_id: int = own.id
	var snapshot := Snapshot.take(fight.areas(), fight.world)
	bus.emit_signal(&"entity_end_requested", wizard.id, 1)
	bus.emit_signal(&"entity_spawn_requested", enemy.id, EntitiesScript.DECOY, Vector2(150.0, 40.0), 6.0, 2, EntitiesScript.CASTER_BODY)
	var other: Actor = fight.entities.decoy_of(enemy.id)
	check(other != null and other.id == own_id and other.name != own_name, "the enemy's decoy takes the ended decoy's id in another row")
	_check_problems(&"decoy", fight.restore(snapshot, 0))
	var back: Actor = fight.entities.decoy_of(wizard.id)
	check(back != null and back.is_inside_tree() and back.name == own_name and back.id == own_id, "the wizard's decoy is back in its own row")
	check(fight.entities.decoy_of(enemy.id) == null, "the enemy's decoy is gone")
	check_equal(fight.entities.count(EntitiesScript.DECOY), 1, "one decoy")
	fight.free_all()


## A shot restored draws as its card's body again (online-ready N12): which batch draws a card's
## shader is this machine's number (`register_body`, in the order it first met each), so the
## projectile manager keeps it as VIEW and Spells gives the live shots theirs after a restore.
func test_a_shot_restored_draws_as_its_card() -> void:
	var played := ContentFight.new(root, ContentFight.CARD, PoolCard)
	var at: int = -1
	var slots: Array[int] = []
	for i in 240:
		played.step()
		slots = _card_body_shots(played)
		if not slots.is_empty():
			at = i
			break
	check(at >= 0, "a pool shot draws as its card's shader")
	var snapshot := Snapshot.take(played.areas(), played.world)
	played.free_all()
	var restored := ContentFight.new(root, ContentFight.CARD, PoolCard)
	_check_problems(&"pool", restored.restore(snapshot, at))
	check_equal(_card_body_shots(restored), slots, "the restored shots draw as their card's shader")
	restored.free_all()


## The live shots of `fight` that draw as the pool card's own shader.
static func _card_body_shots(fight: ContentFight) -> Array[int]:
	var out: Array[int] = []
	var shots: Node = fight.fight.projectiles
	for slot: int in shots.call(&"get_cap"):
		if shots.call(&"get_body_shader_of", slot) == PoolCard.look_shader:
			out.append(slot)
	return out

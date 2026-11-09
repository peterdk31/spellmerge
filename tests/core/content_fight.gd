extends RefCounted
## One piece of content in a short scripted fight (online-ready N12, docs/milestones/online-ready.md):
## the enemy tests' world (tests/gameplay/ai/ai_fixture.gd: its own bus, actor table, projectile
## manager, Spells, Combat and team board) with Entities (decoys, familiars) and a frames service of
## its own, stepped by hand in the Tick's order (core/sim/tick.gd, STEPS): the seats' frames, the
## projectiles, Spells, Combat, Entities (and the team board the brains share), then every body by
## actor id.
##
## - **A card** (`CARD`): seat 0's wizard holds it on a staff with what it needs to cast
##   (`staff_for`), and its player casts it at two enemies: one holding the same staff (its brain
##   casts it at the wizards, so the card's enemy side plays too) and an ember imp. Seat 1's wizard
##   stands by with a plain bolt.
## - **An enemy** (`ENEMY`): two of it against the two wizards, who cast plain bolts at them.
##
## The players read nothing of the game (`Scripted`, as a person's input): they walk a small
## square, sweep their aim across the enemies, tap their first staff and hold it in bursts, so a card
## cast by a tap and one held (a beam, a hold) both play. Their clock is the fight's `ticks`, which a
## restore sets, as a replay's frames go on after a snapshot.
##
##     var fight := ContentFight.new(root, ContentFight.CARD, card)
##     for i in 120:
##         fight.step()
##         desync.capture(fight.areas())
##     fight.free_all()

const AIFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const FramesScript := preload("res://core/sim/frames.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const CARD: StringName = &"card"
const ENEMY: StringName = &"enemy"
## The game's tick.
const DT: float = 1.0 / 60.0
## The plain carrier a card that needs one is cast on, and what the wizards cast otherwise.
const PLAIN: StringName = &"bolt"
const WIZARDS_AT: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.0, 60.0)]
const FOES_AT: Array[Vector2] = [Vector2(150.0, 10.0), Vector2(190.0, 70.0)]
## The fight's shot cap: room for every shot its casts make (a burst, a split on a scatter).
const SHOT_CAP: int = 512


## A player that reads nothing of the game, by the fight's tick (`tick`, set before each frame).
class Scripted:
	extends FrameSource
	var tick: int = 0
	var seat: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		var leg: int = (tick / 30) % 4
		frame.set_move([Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][leg] * 0.5)
		# A sweep of an eighth of a turn across +x, where the enemies stand.
		frame.aim = posmod((tick * 300 + seat * 2000) % 8192 - 4096, InputFrame.AIM_STEPS)
		if tick % 40 == 5 + seat * 7:
			frame.press(0)
		var burst: bool = tick % 90 >= 60
		frame.hold(0, burst)
		if burst and tick % 90 == 60:
			frame.press(0)


var kind: StringName
## The card's or enemy's id.
var content: StringName
## Ticks stepped: the players' clock.
var ticks: int = 0
## Casts of a staff holding the content, counted from the bus: seat 0's first staff (a card the
## player never casts would pass for nothing) and the staffed enemy's.
var wizard_casts: int = 0
var enemy_casts: int = 0
var fight: AIFixture
var entities: EntitiesScript
var frames: FramesScript
var input: InputManagerScript
## The node everything of the fight is under (a snapshot's world).
var world: Node2D
var _sources: Array[Scripted] = []
## The ids open as a tick's bodies step (scratch).
var _ids := PackedInt32Array()
var _staffed: Actor = null


## The cards a staff holds to cast `card` (by its kind): a carrier alone, a trigger or a multicast
## with plain carriers to fire or pull, anything else on a plain carrier.
static func staff_for(card: SpellComponent) -> Array[StringName]:
	var out: Array[StringName] = [card.id]
	if card is FormBase:
		return out
	var carriers: int = 1
	if card is TriggerBase:
		carriers = 2
	elif card is MulticastBase:
		carriers = (card as MulticastBase).extra_draws + 1
	for i in carriers:
		out.append(PLAIN)
	return out


## The fight of `content` (a card's or an enemy's resource), as `kind` says, built fresh under a
## world of its own in `root` (`world`).
func _init(root: Node, fight_kind: StringName, resource: Resource) -> void:
	# Everything under a world of its own, named as in every fight, so a snapshot's parents (by path
	# under the world: Entities, for the decoys) are found again in a fresh one.
	world = Node2D.new()
	world.name = "ContentFight"
	root.add_child(world)
	kind = fight_kind
	content = resource.get(&"id")
	_ids.resize(AIFixture.ActorsScript.ACTORS)
	fight = AIFixture.new(world, 0)
	# Room for every shot a fight makes; the hash walks every slot of the cap each tick.
	fight.projectiles.set_cap(SHOT_CAP)
	entities = EntitiesScript.new()
	entities.name = "Entities"
	entities.events = fight.bus
	entities.projectiles = fight.projectiles
	entities.spells = fight.spells
	entities.actors = fight.actors
	entities.combat = fight.combat
	world.add_child(entities)
	fight.entities = entities
	# The brains share Entities' board, as in the game; Entities steps it.
	fight.board = entities.board
	# An input layer of its own, out of the tree as the wizard tests keep theirs (no device joins it),
	# so the frames read nothing of the game's.
	input = InputManagerScript.new()
	input.events = fight.bus
	frames = FramesScript.new()
	frames.events = fight.bus
	frames.input = input
	frames.auto_tick = false
	frames.name = "Frames"
	world.add_child(frames)
	fight.bus.connect(&"staff_cast", _on_staff_cast)
	var cards: Array[StringName] = [PLAIN]
	if kind == CARD:
		cards = staff_for(resource as SpellComponent)
	for seat in WIZARDS_AT.size():
		var source := Scripted.new()
		source.seat = seat
		_sources.append(source)
		frames.set_source(seat, source)
		var held: Array[StringName] = cards if seat == 0 else ([PLAIN] as Array[StringName])
		fight.players.append(fight.wizard(seat, WIZARDS_AT[seat], frames, _staff(), [held, [], [], []]))
	if kind == CARD:
		_staffed = fight.staffed_enemy([cards], FOES_AT[0])
		fight.imp(FOES_AT[1])
	else:
		var data: EnemyBase = resource as EnemyBase
		for at in FOES_AT:
			fight.enemy(data.scene, data, at)


## A wizard's staff: no wait between casts, a deep pool.
static func _staff() -> StaffBase:
	var staff := StaffBase.new()
	staff.id = &"content_fight"
	staff.slots = 8
	staff.cooldown = 0.0
	staff.max_mana = 1000.0
	staff.mana_regen = 1000.0
	return staff


## One tick, in the Tick's order.
func step() -> void:
	for source in _sources:
		source.tick = ticks
	frames.tick(DT)
	fight.projectiles.step(DT)
	fight.spells.call("step", DT)
	fight.combat.step(DT)
	entities.step(DT)
	# Every body by actor id but the decoys, which Entities steps (the fixture's bodies are kept off
	# the game's Tick, so `ticking` says nothing here): the ids open as the bodies' turn starts, each
	# looked up as its turn comes, as the Tick does (one may end before its turn).
	var n: int = fight.actors.open_ids(_ids)
	for i in n:
		var body: Actor = fight.actors.node_of(_ids[i]) as Actor
		if body != null and body.is_inside_tree() and body.get_parent() != entities:
			body.tick_step(DT)
	ticks += 1


## The fight's areas by name: its services and every actor's body by actor id (as the Tick's
## `state_areas`).
func areas() -> Dictionary:
	return fight.areas({"entities": entities})


## Makes this fight as `snapshot` says (taken from a fight of the same content after its tick
## `at_tick`): bodies made again get this world's services, and the players go on from the next
## tick. Returns the snapshot's problems.
func restore(snapshot: Snapshot, at_tick: int) -> PackedStringArray:
	ticks = at_tick + 1
	var problems: PackedStringArray = snapshot.restore(areas(), world, _prepare)
	fight.regather()
	return problems


## A body the snapshot makes again, before it enters the tree: this world's services, and a
## wizard's seat reads this world's frames.
func _prepare(body: Node) -> void:
	if not body is Actor:
		return
	fight.wire(body as Actor)
	var seat: PlayerController = PlayerController.of(body)
	if seat != null:
		seat.frames = frames
		seat.registry = fight.registry


func _on_staff_cast(player: int, staff: int, _origin: Vector2, _direction: Vector2) -> void:
	if not fight.players.is_empty() and is_instance_valid(fight.players[0]) and player == fight.players[0].id and staff == 0:
		wizard_casts += 1
	elif _staffed != null and is_instance_valid(_staffed) and player == _staffed.id:
		enemy_casts += 1


func free_all() -> void:
	if fight.bus != null and fight.bus.is_connected(&"staff_cast", _on_staff_cast):
		fight.bus.disconnect(&"staff_cast", _on_staff_cast)
	fight.free_all()
	if world != null and is_instance_valid(world):
		world.free()
	if input != null and is_instance_valid(input):
		input.free()
	input = null
	world = null
	entities = null
	frames = null

extends FrameSource
## A bot: plays one player slot. It joins with a virtual device, as a gamepad joins, and fills its
## seat's input frames (online-ready N2: `Frames.set_source`, core/sim/frames.gd), as a device's
## local input layer does: the one input path, so a recorded bot run replays like a person's. It
## never touches a spell field or the projectile manager's shots, so it plays the way a person
## does: the wizard casts what its frame's buttons say.
##
## Fighter (enemy AI L5, docs/milestones/M2-enemy-ai.md): its decisions come from the same brain
## every enemy plays by (`AIBrain`, gameplay/ai/brain.gd), with the bot's profile
## (`bot_profile.tres`: no rest, pressing on, quick to react, dodging). The brain drives the
## wizard but writes a spare `ActorIntent`, never the wizard's own, and the bot turns that into its
## frame (`send`): the walk (each axis full on or off, as the four move keys), the aim, a press for
## each press and the button held while a staff is held. The wizard is on
## the players' team, so the brain winds up nothing (enemies telegraph, allies don't: owner,
## 2026-11-01) and casts the step a staff is ready. It reads what each staff casts next
## (`CastSense`), never a card: it fires the staff that hurts and reaches, walks round walls
## (`AISight`), dodges shots and the telegraphs aimed at it, and when getting away is urgent it
## taps whichever staff's next cast moves the caster (no button is "the dash"). It goes to a downed
## teammate and stands beside it till the coop rule revives it, when no foe is near that one
## (gameplay/ai/behaviours/revive.gd; its profile's `revives`). It holds no grudge
## (a teammate's blast never makes it fight a teammate). **Downed** (connected biomes CB3's crawl;
## the owner, 2026-11-19) it crawls toward the nearest standing teammate (seat order between two as
## near), round the walls, leaning aside from every enemy ahead within CRAWL_SHY of it so it never
## crawls into one, and stops once within CRAWL_BESIDE of that teammate; with none standing it lies still.
## Travel (connected biomes CB8): out of a fight (its room under way or not, `RoomLife`), a fighter
## walks the biome's bridges to the nearest room whose fight is still to come (the fewest bridges from
## where it stands; one behind a shut door, the boss's gate, it waits at: `Flow.gates`), along the
## shortest walk over the wall grid (`bot_route.gd`: round a room's walls, along a walkway of any
## shape and mirroring, through its mouths; on to a shut door's bridge to wait there; round the walls
## toward the landing where no walk is open), then steps in, and its fight seals it in; in a fight the brain plays as
## above, and a revive goes first (its brain's `revive` behaviour running: it stays by the one downed,
## cleared room or not). It reads Flow's map and rooms (`biome`, `life`, `gates`), as a player reads the screen.
## Idler: stands still; it only opens its builder.
##
## Builder: `build_random(seed)` builds a random staff into staff 1 (BUILD_STAFF, RB: `dash` at the
## start, so RT keeps its `bolt` and the room is still cleared; LB is an empty hand since items I2) with the same `staff_change_requested` events a person sends (slot by slot, from the
## card bag of the wizard, never more copies than it holds). The cards come from `staff_fuzzer.gd`, seeded, so a failing run can be
## replayed. `open_builder()` is how bot 4 of the 4-bot test works: one press of `back` (B),
## and it stays there (the full builder, fights included).
##
## The brain thinks at each tick's start, when the frames service asks for the frame
## (`fill_frame`), so a run repeats. Nothing is allocated per step.

enum Mode { FIGHTER, IDLER }

const FuzzerScript := preload("res://tests/bots/staff_fuzzer.gd")
const ReviveScript := preload("res://gameplay/ai/behaviours/revive.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RouteScript := preload("res://tests/bots/bot_route.gd")
## How a bot plays (the brain's numbers).
const PROFILE: AIProfile = preload("res://tests/bots/bot_profile.tres")

## The staff a bot builds into: RB, over its start `dash` (RT keeps its `bolt`).
const BUILD_STAFF: int = 0
## The staff buttons, by staff.
const STAFF_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## A random staff has at most this many cards, so a built staff stays quick to cast.
const BUILD_CARDS: int = 6
## The brain of bot `i` is seeded SEED + i, so a run repeats.
const SEED: int = 4111
## How far into a room from a mouth a traveller aims for where no route is open (pixels).
const LANDING: float = 20.0
## A route (`bot_route.gd`): how near a fight room's middle a traveller walks to, how far into the
## room at a bridge's end its area reaches, and what each route is for.
const GOAL_REACH: float = 24.0
const ROUTE_INTO: float = 64.0
const ROUTE_ON_BRIDGE: int = 0
const ROUTE_OFF_BRIDGE: int = 1
const ROUTE_IN_ROOM: int = 2
const ROUTE_TO_DOOR: int = 3
## How near a shut door's mouth a traveller waits, on its bridge (`GatherDoors` counts it there).
const DOOR_REACH: float = 48.0
## How far a detour round a wall looks (`AISight.detour`).
const DETOUR_PROBE: float = 32.0
## A downed bot's crawl: how near a teammate it stops, and how far an enemy pushes it aside.
const CRAWL_BESIDE: float = 14.0
const CRAWL_SHY: float = 64.0

var player: int = 0
var mode: Mode = Mode.FIGHTER
## The fighter's brain, and the intent it writes (the bot's, never the wizard's own).
var brain: AIBrain = AIBrain.new()
var intent: ActorIntent = ActorIntent.new()

var _input: Node = null
var _flow: Node = null
var _frames: Node = null
## The frame it wants for the next tick (`send`), handed over in `fill_frame`.
var _wanted: InputFrame = InputFrame.new()
## The rooms' bridges from the nearest fight, and the walk out that works them out (sized once a map).
var _hops: PackedInt32Array = PackedInt32Array()
var _hops_queue: PackedInt32Array = PackedInt32Array()
## The traveller's way over the walls, and the map it was worked out on.
var _route: RouteScript = RouteScript.new()
var _route_map: BiomeMap = null
## The open actors, read for a crawl (sized once).
var _ids: PackedInt32Array = PackedInt32Array()

## The cards of the last `build_random`, one per slot of the staff (empty before the first).
var built_cards: Array[StringName] = []
## How many `staff_change_requested` events the bot has sent.
var requests_sent: int = 0


## `input` is the `PlayerInput` autoload and `flow` the `Flow` autoload. Takes the
## virtual device of `index` and fills that seat's frames (the `Frames` autoload); returns false
## if that slot is not free.
func join(index: int, bot_mode: Mode, input: Node, flow: Node) -> bool:
	player = index
	mode = bot_mode
	_input = input
	use_flow(flow)
	_wanted.seat = index
	_wanted.clear()
	if int(_input.call("add_virtual_device", player)) == int(_input.get("NO_DEVICE")):
		return false
	_frames = _input.get_tree().root.get_node_or_null("Frames")
	if _frames != null:
		_frames.call("set_source", player, self)
	return true


## Read the biome, its rooms and its doors from `flow` (the `Flow` autoload, as `join` does; a
## stand-in with `biome`, `life` and `gates` in the travel tests).
func use_flow(flow: Node) -> void:
	_flow = flow


## Press and release `back` (B) once: in play it opens the builder.
func tap_back() -> void:
	_input.call("send_virtual", player, &"back", 1.0)
	_input.call("send_virtual", player, &"back", 0.0)


## Build a random staff into staff 3, slot by slot. The cards are chosen from the wizard's bag
## with `build_seed`. Returns false when the bot has no wizard or the bag has no carrier. True
## means the requests were sent; check the wizard's `caster.cards_of(BUILD_STAFF)`.
func build_random(build_seed: int) -> bool:
	var root: Node = _flow.get_tree().root
	var events: Node = root.get_node_or_null("Events")
	var spells: Node = root.get_node_or_null("Spells")
	var wizard := _flow.call("get_wizard", player) as Actor
	if events == null or spells == null or wizard == null or wizard.caster == null:
		return false
	# One entry a copy in the wizard's card bag (items I3: cards are counted), so the bot never asks
	# for more copies than it holds.
	var bag: Array[StringName] = _copies(wizard)
	var fuzzer := FuzzerScript.new(bag, func(id: StringName) -> StringName: return spells.call("component_kind", id))
	if not fuzzer.can_build():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = build_seed
	var slots: int = wizard.caster.slot_count()
	var cards: Array[StringName] = fuzzer.random_cards(rng, mini(BUILD_CARDS, slots))
	built_cards.clear()
	var left: Array[StringName] = bag.duplicate()
	for slot in slots:
		var card: StringName = cards[slot] if slot < cards.size() else &""
		# A card drawn more often than the bag holds it stays out (the slot empty).
		if card != &"" and not left.has(card):
			card = &""
		left.erase(card)
		built_cards.append(card)
		events.emit_signal("staff_change_requested", player, BUILD_STAFF, slot, built_cards[slot], wizard.key())
		requests_sent += 1
	return true


## The wizard's card bag, one entry a copy.
static func _copies(wizard: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	if wizard.inventory == null:
		return out
	for stack: ItemStack in wizard.inventory.stacks_in(ItemKinds.bag_of(ItemKinds.CARD)):
		for _copy in stack.count:
			out.append(stack.id)
	return out


## Open the builder as a person does: one press of `back` (B).
func open_builder() -> void:
	tap_back()


## Let go of everything the bot holds, stop filling its seat's frames and free the slot.
func leave() -> void:
	_release()
	if _frames != null and _frames.call("source_of", player) == self:
		_frames.call("set_source", player, null)
	_input.call("leave", player)


## The frames service asks for this tick's frame: the brain thinks for the wizard and the frame
## says what it wants. An idler wants nothing.
func fill_frame(frame: InputFrame, delta: float) -> void:
	step(delta)
	frame.move = _wanted.move
	frame.aim = _wanted.aim
	frame.held_bits = _wanted.held_bits
	frame.pressed_bits = _wanted.pressed_bits
	_wanted.pressed_bits = 0


## One step: the brain thinks for the wizard and the bot wants what it wants (`send`). An idler
## does nothing. The frames service calls it each tick (`fill_frame`).
func step(delta: float) -> void:
	if mode == Mode.IDLER:
		return
	var wizard := _flow.call("get_wizard", player) as Actor
	if wizard != null and _flow.get("world") != null and wizard.is_downed():
		# Downed (not falling or spawning in): it crawls.
		_release()
		_wanted.set_move(crawl_way(wizard))
		return
	if wizard == null or _flow.get("world") == null or wizard.is_down() or wizard.caster == null:
		_release()
		return
	if brain.actor != wizard:
		# A new wizard (a new run): a fresh brain for it.
		intent.clear()
		brain.setup(wizard, PROFILE, SEED + player)
	intent.begin_step()
	brain.think(delta, intent)
	# A revive under way (the brain's `revive` behaviour) goes first: it would walk off its teammate.
	var way: Vector2 = Vector2.ZERO if brain.behaviour is ReviveScript else travel(wizard)
	if way != Vector2.ZERO:
		intent.move = way
	send(intent)


## Want `wanted` in the next frame: the walk (each axis full on or off, as the move keys), the aim
## (ZERO keeps it, and the wizard aims where it walks), a press per pressed staff and the button
## held per held staff. A press waits for the frame, so none is lost.
func send(wanted: ActorIntent) -> void:
	_wanted.set_move(Vector2(signi(roundi(wanted.move.x * 1.5)), signi(roundi(wanted.move.y * 1.5))).limit_length(1.0))
	_wanted.set_aim(wanted.aim)
	_wanted.held_bits = wanted.held_bits
	_wanted.pressed_bits |= wanted.pressed_bits


## The way to walk to the nearest fight still to come (unit length), or ZERO: in a fight under way,
## with no biome, or nothing left to go to (`step`'s, and the travel tests').
func travel(wizard: Actor) -> Vector2:
	var biome: BiomeWorld = _flow.get(&"biome") as BiomeWorld
	var life: RoomLife = _flow.get(&"life") as RoomLife
	var gates: GatherDoors = _flow.get(&"gates") as GatherDoors
	if biome == null or life == null or biome.map == null or life.rooms() == 0:
		return Vector2.ZERO
	var map: BiomeMap = biome.map
	var here: int = wizard.room
	if here >= 0 and here < map.rooms() and life.has(here, RoomLife.STARTED) and not life.has(here, RoomLife.CLEARED):
		return Vector2.ZERO
	# The bridges from each room, and how far each room is from the nearest fight still to come.
	# The members themselves (a packed array copied to a local and resized would be a new one each step).
	if _hops.size() != map.rooms():
		_hops.resize(map.rooms())
		_hops_queue.resize(map.rooms())
	_hops.fill(-1)
	var head: int = 0
	var tail: int = 0
	for room in map.rooms():
		# A room behind a shut door (the boss's gate) is a goal too: the bot walks to its door and
		# waits there with the party; no way leads through it.
		if not life.has(room, RoomLife.ENTERED) and life.fights[room].has_enemies():
			_hops[room] = 0
			_hops_queue[tail] = room
			tail += 1
	while head < tail:
		var room: int = _hops_queue[head]
		head += 1
		for bridge in map.bridges():
			for end in 2:
				if map.end_room(bridge, end) == room:
					var other: int = map.end_room(bridge, 1 - end)
					if _hops[other] < 0 and (gates == null or gates.is_open(other)):
						_hops[other] = _hops[room] + 1
						_hops_queue[tail] = other
						tail += 1
	var feet: Vector2 = wizard.global_position
	if biome.map != _route_map:
		# A new biome: its places are numbered afresh.
		_route_map = biome.map
		_route.reset()
	if here >= map.rooms():
		# On a bridge: on to the end nearer the goal.
		var bridge: int = here - map.rooms()
		if bridge >= map.bridges():
			return Vector2.ZERO
		var end: int = 0 if _hops_of(_hops, map.end_room(bridge, 0)) <= _hops_of(_hops, map.end_room(bridge, 1)) else 1
		var room: int = map.end_room(bridge, end)
		var over: Rect2 = biome.bridge_rect(bridge)
		if gates != null and not gates.is_open(room):
			# Its door is shut: it waits on the bridge, by the door.
			return _walk_to(wizard, over, here, biome.mouth_rect(bridge, end).get_center(), DOOR_REACH, _route_key(ROUTE_TO_DOOR, here, room), _landing(biome, bridge, end))
		return _walk_to(wizard, over.merge(_inside(biome.room_rect(room), over)), room, Vector2.ZERO, INF, _route_key(ROUTE_OFF_BRIDGE, here, room), _landing(biome, bridge, end))
	if here < 0 or _hops[here] < 0:
		return Vector2.ZERO
	if _hops[here] == 0:
		var middle: Vector2 = biome.room_rect(here).get_center()
		return _walk_to(wizard, biome.room_rect(here), here, middle, GOAL_REACH, _route_key(ROUTE_IN_ROOM, here, here), middle)
	# The bridge out of this room toward the goal: along its walkway into the room at its far end.
	for bridge in map.bridges():
		for end in 2:
			if map.end_room(bridge, end) != here:
				continue
			var other: int = map.end_room(bridge, 1 - end)
			if _hops[other] < 0 or _hops[other] >= _hops[here]:
				continue
			var over: Rect2 = biome.bridge_rect(bridge)
			if gates != null and not gates.is_open(other):
				# A shut door (a gather door, the boss's gate): along the walkway to it, and wait there.
				return _walk_to(wizard, biome.room_rect(here).merge(over), map.rooms() + bridge, biome.mouth_rect(bridge, 1 - end).get_center(), DOOR_REACH, _route_key(ROUTE_TO_DOOR, here, bridge), _landing(biome, bridge, 1 - end))
			var area: Rect2 = biome.room_rect(here).merge(over).merge(_inside(biome.room_rect(other), over))
			return _walk_to(wizard, area, other, Vector2.ZERO, INF, _route_key(ROUTE_ON_BRIDGE, here, bridge), _landing(biome, bridge, 1 - end))
	return Vector2.ZERO


## The way for `wizard` to walk inside `area` to place `place` (within `reach` of `point`; INF:
## anywhere in it), down the route's field (`bot_route.gd`); where the field has no way (a shut
## door, the boss's gate: it waits there), toward `fallback` round the walls, as before routes.
func _walk_to(wizard: Actor, area: Rect2, place: int, point: Vector2, reach: float, key: int, fallback: Vector2) -> Vector2:
	var feet: Vector2 = wizard.global_position
	var way: Vector2 = _route.aim(wizard.projectiles, feet, area, place, point, reach, wizard.wall_radius(), key)
	if way != Vector2.ZERO or _route.has_way(feet):
		return way
	return _toward(wizard.projectiles, feet, fallback)


## The part of room rectangle `room` within ROUTE_INTO of `bridge`'s rectangle: where a walk off
## the bridge into that room ends.
static func _inside(room: Rect2, bridge: Rect2) -> Rect2:
	return room.intersection(bridge.grow(ROUTE_INTO))


## A route's name: what it is for (ROUTE_*), the place it starts in and where it goes.
static func _route_key(kind: int, from: int, to: int) -> int:
	return kind + 4 * (from + 4096 * to)


static func _hops_of(hops: PackedInt32Array, room: int) -> int:
	return hops[room] if hops[room] >= 0 else 1 << 20


## A point LANDING inside the room at bridge `bridge`'s end `end`, in front of its mouth.
static func _landing(biome: BiomeWorld, bridge: int, end: int) -> Vector2:
	var mouth: Vector2 = biome.mouth_rect(bridge, end).get_center()
	var far: Vector2 = biome.mouth_rect(bridge, 1 - end).get_center()
	return mouth + (mouth - far).normalized() * LANDING


## The way from `feet` to `goal` over `projectiles`' grid, round a wall (a short look: `AISight.detour`).
static func _toward(projectiles: ProjectilesScript, feet: Vector2, goal: Vector2) -> Vector2:
	if feet.distance_to(goal) <= 1.0:
		return Vector2.ZERO
	return AISight.detour(projectiles, feet, goal, DETOUR_PROBE)


## The way a downed `wizard` crawls (unit length, or ZERO): toward the nearest standing teammate,
## round the walls, leaning aside from the enemies near it ahead (see the top of this file).
func crawl_way(wizard: Actor) -> Vector2:
	var feet: Vector2 = wizard.global_position
	var mate: Vector2 = Vector2.INF
	var best: float = INF
	for seat in 4:
		var other := _flow.call("get_wizard", seat) as Actor
		if seat == player or other == null or not other.is_inside_tree() or other.is_down():
			continue
		var gap: float = feet.distance_squared_to(other.global_position)
		if gap < best:
			best = gap
			mate = other.global_position
	if mate == Vector2.INF or best <= CRAWL_BESIDE * CRAWL_BESIDE:
		return Vector2.ZERO
	var way: Vector2 = _toward(wizard.projectiles, feet, mate)
	var table := _flow.get_node_or_null(^"/root/Actors") as ActorsScript
	if table == null:
		return way
	if _ids.size() < ActorsScript.ACTORS:
		_ids.resize(ActorsScript.ACTORS)
	var count: int = table.open_ids(_ids)
	var away: Vector2 = Vector2.ZERO
	for at in count:
		var id: int = _ids[at]
		if table.team_of(id) != ActorsScript.TEAM_ENEMIES:
			continue
		var foe := table.node_of(id) as Node2D
		if foe == null or not foe.is_inside_tree():
			continue
		var rel: Vector2 = foe.global_position - feet
		var near: float = rel.length()
		var ahead: float = rel.dot(way)
		if near >= CRAWL_SHY or ahead < 0.0:
			# Far, or behind it (crawling on is crawling away).
			continue
		# Aside from the foe ahead, never back: across the way, to the side away from it (the way's
		# left when it lies straight ahead).
		var side: Vector2 = rel - way * ahead
		var push: Vector2 = -side.normalized() if side.length() > 0.5 else way.orthogonal()
		away += push * (1.0 - near / CRAWL_SHY) * 2.0
	way += away
	return way.normalized() if way.length() > 0.001 else Vector2.ZERO


## The frame it wants next (read only; tests).
func wanted_frame() -> InputFrame:
	return _wanted


func _release() -> void:
	_wanted.clear()
	if brain.actor != null:
		brain.reset()
		brain.actor = null

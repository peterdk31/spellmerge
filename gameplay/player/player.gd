class_name PlayerController
extends ActorController
## The player's controller (actors G7, docs/milestones/M2-actors.md, "The components"): a human
## seat 0-3 and its input. It drives one actor at a time, its home actor (the wizard of
## content/wizard/base/wizard.tscn, where it is the `PlayerController` node) or another one it
## was handed (`Actor.drive`, possess in G9). It reads only its own seat's input frame (core/sim,
## `Frames.frame_of`; online-ready N2) and never looks at another seat, so nobody waits for anybody.
##
## It IS the seat: the HUD, the builder and the rest of the game hear a seat only from here.
## What the seat's panel, builder and inventory are about is its **shown body** (`shown`, items I8;
## owner, 2026-11-13, decision 10, which replaces "always its own wizard" of 2026-10-28): the body
## it drives now, the first one hit when it possesses several (`Possession`: a controller drives its
## oldest), and its **home body** (the actor whose home controller it is, its wizard) while it
## drives nothing (another controller drives the wizard, or it drives nothing yet). Its own wizard,
## which may stand vulnerable meanwhile, shows its health over its head (Feel's away bar).
##
## - **Frame to intent** (`think`): the seat's `InputFrame` for this tick, never a device. What a
##   device says becomes a frame in front of it (`LocalInput`, core/input: the walk, the aim with
##   the right stick's hold and the keyboard player's mouse, the staff buttons), and so does what a
##   bot or a replay says. The walk and the aim are the frame's (quantised: what is recorded is
##   what is played); the four staff buttons `staff_1` to `staff_4` (staffs 0-3: RB, RT, LB, LT)
##   are held while the frame holds them, and a press is remembered for INPUT_BUFFER seconds,
##   pressed again each step until a cast leaves, so a tap just before the staff is ready still
##   fires (the buffer is the simulation's: only it knows when a cast leaves). The Caster casts (a
##   press, or a hold while no sustained card is on). While the frame says captured (an overlay of
##   the seat is open) the move in progress stops (`Mover.stop`), the intent is empty and the
##   buffer forgets; while the actor is down, too.
## - **The panel's events** (from the shown body; all of them each time the shown body changes, then
##   on every change): `player_stats_changed` (on a health change, when the mana of the staff on
##   show crosses a whole number and when another staff goes on show; every staff has its own
##   pool), `staff_mana_changed` (each staff's pool, when it crosses a whole number): the mana is
##   looked at each step, in `think` or, while the seat is set aside, `watch_home`, so a regen
##   shows a step later), `staff_changed` with the plain view of every hand's staff
##   (`Caster.plan_of`; an empty one for a hand it has not), and `build_refused`.
## - **The inventory's events** (the shown body's `Inventory`, items I3; all of them each time the
##   shown body changes, after `inventory_announced`, then on every change; every actor has one):
##   `bag_changed` for each
##   bag (its ids, counts and capacity), `owned_staff_changed` for each staff it owns, by its number
##   (`Inventory.plan_of`, empty once it went), and `hands_changed` (which number is on which hand).
## - **The cast events** (from the actor it drives now, whose staffs its buttons cast): `spell_cast`
##   (the carrier, `Caster.last_carrier_card`) and `staff_cast` on every cast (the controller has
##   no player of its own: Feel sounds every actor's cast on `cast_left`).
## - **The builder** (`staff_change_requested` and `staff_cards_requested`, each for this seat
##   only and naming a staff by its number; commands, heard at the tick's start: core/events
##   `listen`) builds the shown body's staffs through its inventory (`Inventory.set_card`,
##   `set_cards`: counted, and a staff on a hand goes into the Caster): a possessed enemy's during
##   a possession, its cards taken out going into that body's card bag (items I8).
##   A refusal is sent as `build_refused` with its words (NO_STAFF, NO_SLOT, NO_CARD); a card given back to a full
##   bag is dropped at the body's feet (items I6), never refused.
## - **The inventory menu** (items I7: `staff_hand_requested` and `bag_drop_requested`, commands for
##   this seat only, a staff named by its number) puts the shown body's staffs on hands, in the bag
##   and on the ground, and drops its things (`Inventory.set_hand`, `drop_staff`, `drop`); a
##   refusal is `inventory_refused` with its words.
## - **Down** (items I7b): while the shown body is down every request of the builder's and the
##   inventory's is refused (NO_DOWN, as `build_refused` or `inventory_refused`) and changes nothing.
## - **The body named** (items I8): each of those four requests carries the key of the body the menu
##   showed (`Actor.key`, sent with `inventory_announced`); one for a body the seat no longer shows
##   (sent just before a possession began or ended, a late frame online) is refused (NO_BODY), so
##   it never changes another body's staff of the same number.
## - **The card bag** (each run mode's, from flow through `seat_wizard`: card id to copies,
##   `Inventory.give_cards`); a wizard given none gets Inventory.DEV_COPIES of every card in the
##   registry when it first drives.
## - **Possessed** (G9): when another actor's controller takes the actor it drives, it is set aside
##   (`set_aside`, `is_set_aside`) and drives nothing until `started` hands it an actor again; the
##   panel shows the wizard (its home body) meanwhile, and the time is drawn over the wizard
##   (`PossessedLook`).
##
## Its seat is in the actor table through the actor it drives (`Actor.seat`, `Actors.set_driver`),
## so Spells' budgets (and `mana_reserved`, which no HUD reads yet) reach this seat while it drives;
## the HUD finds the shown body by `Actors.shown_of_seat`. It hears the builder's requests once,
## when it first drives its home body (it is a node of that body, so they go together), the driven
## actor's casts in `started`, letting go in `stopped`, and the shown body's Health, Caster and
## Inventory while it is the shown one (`_watch`, moved again after a restored snapshot:
## `rebuild_derived`); it works the same on any actor with a Caster, Health, Inventory and Mover
## (each optional). The seat's mouse aims from the hand of the body it drives. Nothing here
## allocates per step.
##
## Flow puts a wizard together with `seat_wizard` before adding it to the tree, or, for a player
## a run's start takes along (items I4), with `seat_loadout` from its loadout (`loadout_of`).

const FramesScript := preload("res://core/sim/frames.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A staff cast pressed this long (seconds) before the staff is ready still happens.
const INPUT_BUFFER: float = 0.15
## The four staff buttons (0 RB, 1 RT, 2 LB, 3 LT; owner, 2026-10-26).
const STAFF_COUNT: int = 4
## Why a builder's request is refused (`build_refused`), by `Inventory.Refusal`.
const NO_STAFF: String = "You have no such staff."
const NO_SLOT: String = "There is no such slot."
const NO_CARD: String = "You do not have that card."
const NO_HAND: String = "You have no such hand."
const NO_ROOM: String = "That bag is full."
const NO_ITEM: String = "You do not have that."
## Why every request of the builder's and the inventory's is refused while the home body is down
## (items I7b): the HUD closes both menus then, but a command can still arrive (a late frame online).
const NO_DOWN: String = "You cannot do that while down."
## Why a request of the builder's or the inventory's is refused when it names a body the seat no
## longer shows (items I8: one sent just before a possession began or ended, a late frame online).
const NO_BODY: String = "That is no longer the body you play."
const REFUSALS: Dictionary = {
	Inventory.Refusal.NO_STAFF: NO_STAFF, Inventory.Refusal.NO_SLOT: NO_SLOT,
	Inventory.Refusal.NO_CARD: NO_CARD, Inventory.Refusal.NO_HAND: NO_HAND,
	Inventory.Refusal.NO_ROOM: NO_ROOM, Inventory.Refusal.NO_ITEM: NO_ITEM,
}

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"registry", &"frames", &"_watched", &"_sent_health", &"_sent_mana", &"_sent_shown", &"_sent_staff_mana", &"_sent_staff_max"]
## State as who they point at: the actor it drives and its home body, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_actor", &"_home"]

## The frames service (core/sim/frames.gd: this seat's input frame each tick) and the registry (a
## card bag nobody gave). Only tests set these, before adding the node; otherwise the "Frames" and
## "Registry" autoloads are used. The frames service is the seat's only input (online-ready N9): a
## test feeds a seat through one of its own (tests/gameplay/player/wizard_fixture.gd), and one set
## to null later gives no input at all.
var frames: FramesScript = null
var registry: RegistryScript = null

## The actor driven now (set by `started`, cleared by `stopped`), or null.
var _actor: Actor = null
## Its home body (the actor whose home controller it is), bound the first time it drives it.
var _home: Actor = null
## Per staff: the seconds left in which a remembered press still counts (0 = none remembered).
var _buffer_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## What the last `player_stats_changed` said, to send it only on a change: what this machine's HUD
## was told, not state (a restore sends everything again, `rebuild_derived`).
var _sent_health: float = -1.0
var _sent_mana: int = -1
var _sent_shown: int = -1
## What the last `staff_mana_changed` of each staff said (its whole mana; -1: not sent yet).
var _sent_staff_mana: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _sent_staff_max: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
## True while a possession has set it aside (`set_aside`), until it drives again.
var _aside: bool = false
## The body whose Health, Caster and Inventory it hears (`_watch`): the shown body (`shown`) since
## it last changed, or null.
var _watched: Actor = null


func _init() -> void:
	team = ActorsScript.TEAM_WIZARDS


func _ready() -> void:
	if frames == null:
		frames = get_node_or_null("/root/Frames") as FramesScript
		if frames == null:
			push_warning("PlayerController %d: the Frames autoload is missing, so this seat cannot move." % seat)
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript


## Get `body` (a wizard scene, not yet in the tree) ready for seat `seat_index`: its controller's
## seat, its ramp (the seat's colour), its four staffs (`staff` for every button, or `staffs`,
## one per button: the four heads, a null one an empty hand (items I2); and `cards`: four lists of
## card ids, built when it enters the tree; its Inventory takes them as its own) and its card bag
## (`bag`, card id to copies: the run mode's; empty: Inventory.DEV_COPIES of every card of the
## registry). Returns its controller, or null when `body` has none.
static func seat_wizard(body: Actor, seat_index: int, staff: StaffBase, cards: Array, staffs: Array[StaffBase] = [], bag: Dictionary = {}) -> PlayerController:
	var controller: PlayerController = of(body)
	if controller == null:
		return null
	controller.seat = seat_index
	body.ramp = seat_index
	for child in body.get_children():
		if child is Inventory and not bag.is_empty():
			(child as Inventory).give_cards(bag)
		elif child is Caster:
			var caster := child as Caster
			caster.staff = staff
			caster.staffs = staffs
			caster.start_cards = cards
			caster.empty_hands = _empty_hands(staffs)
	return controller


## The empty hands of `staffs` (one per button), a bit each: a null entry, or a button past its
## end. None when `staffs` is empty (then `staff` is on every button).
static func _empty_hands(staffs: Array[StaffBase]) -> int:
	if staffs.is_empty():
		return 0
	var bits: int = 0
	for at in STAFF_COUNT:
		if at >= staffs.size() or staffs[at] == null:
			bits |= 1 << at
	return bits


## Get `body` (a wizard scene, not yet in the tree) ready for seat `seat_index` as the player
## `loadout` says (items I4: what a run's start takes along): its controller's seat, its ramp, and
## its Inventory holding exactly the loadout (`Inventory.take_loadout`, its staffs found in
## `registry`), which its Caster's hands are made from. Returns its controller, or null when `body`
## has none.
static func seat_loadout(body: Actor, seat_index: int, loadout: PlayerLoadout, registry: Node) -> PlayerController:
	var controller: PlayerController = of(body)
	if controller == null:
		return null
	controller.seat = seat_index
	body.ramp = seat_index
	var inventory: Inventory = null
	var caster: Caster = null
	for child in body.get_children():
		if child is Inventory:
			inventory = child as Inventory
		elif child is Caster:
			caster = child as Caster
	if inventory != null:
		inventory.take_loadout(loadout, registry)
	if caster != null:
		caster.staff = null
		caster.staffs = inventory.hand_staffs() if inventory != null else ([null, null, null, null] as Array[StaffBase])
		caster.start_cards = inventory.hand_cards() if inventory != null else []
		caster.empty_hands = _empty_hands(caster.staffs)
	return controller


## What `body` holds now as a player loadout (its Inventory's, `Inventory.loadout`): what a wizard
## made again is seated with (`seat_loadout`), so it keeps everything it held (Flow, from the hub
## into a run; items I4). Null for a body with no Inventory.
static func loadout_of(body: Actor) -> PlayerLoadout:
	if body == null:
		return null
	for child in body.get_children():
		if child is Inventory:
			return (child as Inventory).loadout()
	return null


## The PlayerController in `body`'s scene (its home controller), or null. Works before `body` is
## in the tree.
static func of(body: Node) -> PlayerController:
	if body == null:
		return null
	for child in body.get_children():
		if child is PlayerController:
			return child as PlayerController
	return null


## The actor this seat drives now, or null.
func driven() -> Actor:
	return _actor


## Its home body (the wizard its panel shows), or null before it first drove it.
func home() -> Actor:
	return _home


## The body the seat's panel, builder and inventory are about (items I8): the body it drives now,
## else its home body; null before it drove anything.
func shown() -> Actor:
	if _actor != null and is_instance_valid(_actor):
		return _actor
	return _home if _home != null and is_instance_valid(_home) else null


func started(actor: Actor) -> void:
	_actor = actor
	_aside = false
	forget_presses()
	bind(actor)
	if _home == null and actor.home_controller == self:
		_bind_home(actor)
	_show_anew()


## The shown body changed (or it drives its first): hear it, and the panel and the menus get all of
## it anew (a staff not built yet is announced when its Caster builds it). Nothing when it is the
## body heard already.
func _show_anew() -> void:
	var body: Actor = shown()
	if body == _watched:
		return
	_watch(body)
	_forget_sent()
	_announce_body()
	announce_stats()


## Hear `body`'s Health, Caster and Inventory (the shown body), and no longer the body heard before.
func _watch(body: Actor) -> void:
	if _watched != null and is_instance_valid(_watched):
		_unwatch(_watched)
	_watched = body
	if body == null:
		return
	if body.caster != null and not body.caster.staff_built.is_connected(_on_staff_built):
		body.caster.staff_built.connect(_on_staff_built)
	if body.health != null and not body.health.changed.is_connected(_on_health_changed):
		body.health.changed.connect(_on_health_changed)
	var inventory: Inventory = body.inventory
	if inventory != null and not inventory.bag_changed.is_connected(_on_bag_changed):
		inventory.bag_changed.connect(_on_bag_changed)
		inventory.staff_changed.connect(_on_owned_staff_changed)
		inventory.hands_changed.connect(_on_hands_changed)


func _unwatch(body: Actor) -> void:
	if body.caster != null and body.caster.staff_built.is_connected(_on_staff_built):
		body.caster.staff_built.disconnect(_on_staff_built)
	if body.health != null and body.health.changed.is_connected(_on_health_changed):
		body.health.changed.disconnect(_on_health_changed)
	var inventory: Inventory = body.inventory
	if inventory != null and inventory.bag_changed.is_connected(_on_bag_changed):
		inventory.bag_changed.disconnect(_on_bag_changed)
		inventory.staff_changed.disconnect(_on_owned_staff_changed)
		inventory.hands_changed.disconnect(_on_hands_changed)


## A snapshot restored: it hears the body it drives (the base's) and the shown body, which may be
## another than before. The HUD is told the shown body's staffs and things again when it changed,
## and its numbers at the next step in any case (what was sent is forgotten: the restored body's
## numbers may equal what was last said of another).
func rebuild_derived() -> void:
	super()
	_forget_sent()
	var body: Actor = shown()
	if body == _watched:
		return
	_watch(body)
	_announce_body()


## Forget what the HUD was told, so the next `announce_stats` says every number again.
func _forget_sent() -> void:
	_sent_health = -1
	_sent_mana = -1
	_sent_shown = -1
	_sent_staff_mana.fill(-1)
	_sent_staff_max.fill(-1.0)


## Bind the home body and the builder's requests for good (this node goes with that body).
func _bind_home(actor: Actor) -> void:
	_home = actor
	# The seat's mouse aims from the hand of the body it drives (the frames service's local input layer).
	if frames != null:
		frames.set_aim_pivot(seat, _aim_pivot)
	var inventory: Inventory = actor.inventory
	if inventory != null and not inventory.cards_given:
		_fill_cards(inventory)
	var bus: EventsScript = actor.events
	if bus != null:
		# Commands, heard at the tick's start (core/events, online-ready N2).
		bus.listen(&"staff_change_requested", _on_staff_change_requested)
		bus.listen(&"staff_cards_requested", _on_staff_cards_requested)
		bus.listen(&"staff_hand_requested", _on_staff_hand_requested)
		bus.listen(&"bag_drop_requested", _on_bag_drop_requested)


## Where the seat's mouse aims from: the hand of the body it drives (`Actor.aim_pivot`; items I8),
## else its wizard's; INF while it has none in the world.
func _aim_pivot() -> Vector2:
	var body: Actor = shown()
	if body == null or not body.is_inside_tree():
		return Vector2.INF
	return body.aim_pivot()


## A possession took the actor it drove for `seconds`: it drives nothing until `started`, and the
## panel shows its wizard meanwhile.
func set_aside(_actor_taken: Actor, _seconds: float) -> void:
	_aside = true
	_show_anew()


## While another controller drives its wizard, the wizard's mana still reaches the panel.
func watch_home(_body: Actor, _delta: float) -> void:
	announce_stats()


## True while a possession has set this seat aside (it drives nothing).
func is_set_aside() -> bool:
	return _aside


func stopped(actor: Actor) -> void:
	unbind(actor)
	if _actor == actor:
		_actor = null
		# Shown again: its wizard, until `started` hands it another body (most often at once).
		_show_anew()


## It hears the casts of the body it drives.
func bind(actor: Actor) -> void:
	super(actor)
	if actor.caster != null and not actor.caster.cast_done.is_connected(_on_cast_done):
		actor.caster.cast_done.connect(_on_cast_done)


func unbind(actor: Actor) -> void:
	if actor.caster != null and actor.caster.cast_done.is_connected(_on_cast_done):
		actor.caster.cast_done.disconnect(_on_cast_done)
	super(actor)


## The seat's input frame becomes the actor's intent for this step (see the class doc).
func think(actor: Actor, delta: float) -> void:
	var intent: ActorIntent = actor.intent
	announce_stats()
	for at in STAFF_COUNT:
		_buffer_left[at] = maxf(_buffer_left[at] - delta, 0.0)
	var frame: InputFrame = _frame()
	if frame == null or actor.is_down():
		# No input (only in tests), or down: stand, cast nothing, and presses made meanwhile are
		# not held against the player after a revive.
		intent.clear()
		forget_presses()
		if frame != null and not frame.captured and actor.mover != null and actor.mover.can_crawl():
			# Downed in a biome it crawls (connected biomes CB3, decision 13): the walk alone.
			intent.move = frame.move_vector()
		return
	if frame.captured and actor.mover != null and actor.mover.is_moving():
		# An overlay opened: freeze, and end a dash in progress.
		actor.mover.stop()
	intent.move = frame.move_vector()
	intent.aim = frame.aim_vector()
	# A press is the frame's (counted in front of it, so a tap released again before this tick is
	# not lost). While an overlay is open (captured) no button holds and the buffer forgets.
	for at in STAFF_COUNT:
		if frame.captured:
			_buffer_left[at] = 0.0
			intent.hold(at, false)
			continue
		if frame.is_pressed(at):
			_buffer_left[at] = INPUT_BUFFER
		intent.hold(at, frame.is_held(at))
		if _buffer_left[at] > 0.0:
			intent.press(at)


## This tick's frame of the seat: the frames service's; null for no input at all (a test's).
func _frame() -> InputFrame:
	return frames.frame_of(seat) if frames != null else null


## Forget remembered presses, so no press made before counts later.
func forget_presses() -> void:
	for at in STAFF_COUNT:
		_buffer_left[at] = 0.0


## Send `staff_mana_changed` for each staff of the shown body whose whole mana or pool size
## differs from the last one sent, and `player_stats_changed` if its health, the staff on show or that staff's
## whole mana differ.
func announce_stats() -> void:
	var body: Actor = shown()
	if body == null or body.events == null:
		return
	var caster: Caster = body.caster
	if caster != null:
		for at in mini(caster.staff_count, STAFF_COUNT):
			var whole: int = floori(caster.mana_of(at))
			var most: float = caster.max_mana_of(at)
			if whole != _sent_staff_mana[at] or most != _sent_staff_max[at]:
				_sent_staff_mana[at] = whole
				_sent_staff_max[at] = most
				body.events.staff_mana_changed.emit(seat, at, float(whole), most)
	var health: float = body.health.health if body.health != null else 0.0
	var max_health: float = body.health.max_health if body.health != null else 0.0
	var shown: int = caster.current if caster != null else 0
	var whole_mana: int = floori(caster.mana_of(shown)) if caster != null else 0
	if health == _sent_health and whole_mana == _sent_mana and shown == _sent_shown:
		return
	_sent_health = health
	_sent_mana = whole_mana
	_sent_shown = shown
	var max_mana: float = caster.max_mana_of(shown) if caster != null else 0.0
	body.events.player_stats_changed.emit(seat, health, max_health, float(whole_mana), max_mana)


func _on_health_changed(_health: float, _max_health: float) -> void:
	announce_stats()


## A staff of the driven actor was cast: the seat's cast events (Feel sounds the cast on
## `staff_cast`), the mana spent (the shown body's), and the buffered press is used up.
func _on_cast_done(at: int, origin: Vector2, direction: Vector2) -> void:
	if at >= 0 and at < STAFF_COUNT:
		_buffer_left[at] = 0.0
	if _actor == null:
		return
	announce_stats()
	var bus: EventsScript = _actor.events
	if bus != null:
		var carrier_card: StringName = _actor.caster.last_carrier_card(at)
		if carrier_card != &"":
			bus.spell_cast.emit(seat, carrier_card, origin, direction)
		bus.staff_cast.emit(seat, at, origin, direction)


## A staff of the shown body was built: the panel and the builder see its plain view (empty for a
## hand it has not).
func _on_staff_built(at: int) -> void:
	var body: Actor = shown()
	if body != null and body.events != null:
		body.events.staff_changed.emit(seat, at, body.caster.plan_of(at) if body.caster != null else {})


## Fill `inventory`'s card bag nobody gave: Inventory.DEV_COPIES of every card in the registry.
func _fill_cards(inventory: Inventory) -> void:
	inventory.give_cards(Inventory.dev_cards(registry))


## Everything of the shown body the HUD shows, to the seat's events (each time the shown body
## changes): every hand's staff for the panel, then `inventory_announced`, what its sustained cards
## hold (`mana_reserved`), every bag, every staff owned and the hands (every actor has an Inventory).
func _announce_body() -> void:
	var body: Actor = shown()
	if body == null or body.events == null:
		return
	for at in STAFF_COUNT:
		if body.caster == null or at >= body.caster.staff_count or body.caster.number >= 0:
			# A staff not built yet is announced when its Caster builds it.
			_on_staff_built(at)
	body.events.inventory_announced.emit(seat, body.key())
	# What its sustained cards hold of each pool (the HUD forgot the last body's on the announcement).
	if body.caster != null and body.caster.number >= 0 and body.spells != null:
		for at in mini(body.caster.staff_count, STAFF_COUNT):
			body.events.mana_reserved.emit(seat, at, body.spells.reserved_mana(body.caster.number, at))
	for bag: StringName in ItemKinds.BAGS:
		_on_bag_changed(bag)
	if body.inventory != null:
		for number: int in body.inventory.numbers():
			_on_owned_staff_changed(number)
	_on_hands_changed()


## `bag_changed` for this seat: what the shown body's bag `bag` holds now.
func _on_bag_changed(bag: StringName) -> void:
	var body: Actor = shown()
	if body == null or body.events == null or body.inventory == null:
		return
	var ids: Array[StringName] = []
	var counts := PackedInt32Array()
	for stack: ItemStack in body.inventory.stacks_in(bag):
		ids.append(stack.id)
		counts.append(stack.count)
	body.events.bag_changed.emit(seat, bag, ids, counts, body.inventory.capacity_of(bag))


## `owned_staff_changed` for this seat: staff `number` of the shown body as it is now.
func _on_owned_staff_changed(number: int) -> void:
	var body: Actor = shown()
	if body != null and body.events != null and body.inventory != null:
		body.events.owned_staff_changed.emit(seat, number, body.inventory.plan_of(number))


## `hands_changed` for this seat.
func _on_hands_changed() -> void:
	var body: Actor = shown()
	if body != null and body.events != null and body.inventory != null:
		body.events.hands_changed.emit(seat, body.inventory.hands())


## The seat's events: the shown body's bus (every body shares one).
func _bus() -> EventsScript:
	var body: Actor = shown()
	return body.events if body != null else null


func _refuse(reason: String) -> void:
	var bus: EventsScript = _bus()
	if bus != null:
		bus.build_refused.emit(seat, reason)


## The shown body's Inventory: the builder and the inventory menu edit the body the seat drives
## (items I8), its wizard while it drives nothing.
func _builder_inventory() -> Inventory:
	var body: Actor = shown()
	return body.inventory if body != null else null


## Why a menu's request naming the body `key` is refused before it is tried: NO_BODY for a body the
## seat no longer shows (items I8), NO_DOWN while the shown body is down (items I7b); "" for none.
func _menu_refusal(key: int) -> String:
	var body: Actor = shown()
	if body == null or body.key() != key:
		return NO_BODY
	if body.is_down():
		return NO_DOWN
	return ""


## A builder asked to put `card_id` into `slot` of staff number `number` (`&""` empties it).
func _on_staff_change_requested(player: int, number: int, slot: int, card_id: StringName, body: int) -> void:
	if player != seat:
		return
	var why: String = _menu_refusal(body)
	if why != "":
		_refuse(why)
		return
	var inventory: Inventory = _builder_inventory()
	_answer(inventory.set_card(number, slot, card_id) if inventory != null else Inventory.Refusal.NO_STAFF)


## A builder asked to set every slot of staff number `number` at once (`cards` by slot; fewer than
## the staff's slots empties the rest). Refused, and nothing changes, as `Inventory.set_cards` says.
func _on_staff_cards_requested(player: int, number: int, cards: Array[StringName], body: int) -> void:
	if player != seat:
		return
	var why: String = _menu_refusal(body)
	if why != "":
		_refuse(why)
		return
	var inventory: Inventory = _builder_inventory()
	_answer(inventory.set_cards(number, cards) if inventory != null else Inventory.Refusal.NO_STAFF)


## A refusal's words to the seat (`build_refused`); nothing for a change that was made.
func _answer(refusal: Inventory.Refusal) -> void:
	if refusal != Inventory.Refusal.NONE:
		_refuse(str(REFUSALS.get(refusal, NO_STAFF)))


## The inventory menu asked to put staff number `number` on hand `hand` (-1: into the staff bag;
## items I7): `Inventory.set_hand`, refused as it says.
func _on_staff_hand_requested(player: int, number: int, hand: int, body: int) -> void:
	if player != seat:
		return
	var why: String = _menu_refusal(body)
	if why != "":
		_refuse_inventory(why)
		return
	var inventory: Inventory = _builder_inventory()
	_answer_inventory(inventory.set_hand(number, hand) if inventory != null else Inventory.Refusal.NO_STAFF)


## The inventory menu asked to drop staff number `number`, or with -1 one copy of `id` from `bag`
## (items I7): `Inventory.drop_staff` or `drop`, refused as they say.
func _on_bag_drop_requested(player: int, bag: StringName, id: StringName, number: int, body: int) -> void:
	if player != seat:
		return
	var why: String = _menu_refusal(body)
	if why != "":
		_refuse_inventory(why)
		return
	var inventory: Inventory = _builder_inventory()
	var refusal: Inventory.Refusal = Inventory.Refusal.NO_ITEM
	if inventory != null:
		refusal = inventory.drop_staff(number) if number != Inventory.NO_STAFF else inventory.drop(bag, id)
	_answer_inventory(refusal)


## A refusal of the inventory menu's to the seat (`inventory_refused`); nothing for a change made.
func _answer_inventory(refusal: Inventory.Refusal) -> void:
	if refusal != Inventory.Refusal.NONE:
		_refuse_inventory(str(REFUSALS.get(refusal, NO_ITEM)))


func _refuse_inventory(reason: String) -> void:
	var bus: EventsScript = _bus()
	if bus != null:
		bus.inventory_refused.emit(seat, reason)

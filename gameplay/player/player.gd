class_name PlayerController
extends ActorController
## The player's controller (actors G7, docs/milestones/M2-actors.md, "The components"): a human
## seat 0-3 and its input. It drives one actor at a time, its home actor (the wizard of
## content/wizard/base/wizard.tscn, where it is the `PlayerController` node) or another one it
## was handed (`Actor.drive`, possess in G9). It reads only its own seat's input frame (core/sim,
## `Frames.frame_of`; online-ready N2) and never looks at another seat, so nobody waits for anybody.
##
## It IS the seat: the HUD, the builder and the rest of the game hear a seat only from here.
## The seat's panel and builder are always its own wizard, its **home body** (the actor whose
## home controller it is): its input drives whatever actor it drives now, but what the player
## sees and builds is the wizard, which may stand vulnerable meanwhile (owner, 2026-10-28).
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
## - **The panel's events** (always from the home body, also while the seat drives another actor
##   or another controller drives the wizard): `player_stats_changed` (when it first drives the
##   wizard and each time it comes home, on a health change, when the mana of the staff on show
##   crosses a whole number and when another staff goes on show; every staff has its own pool),
##   `staff_mana_changed` (each staff's pool, when it crosses a whole number): the mana is looked
##   at each step, in `think` or, while away, `watch_home`, so a regen shows a
##   step later), `staff_changed` with the plain view of every built staff (`Caster.plan_of`),
##   `bag_changed` and `build_refused`.
## - **The cast events** (from the actor it drives now, whose staffs its buttons cast): `spell_cast`
##   (the carrier, `Caster.last_form`) and `staff_cast` on every cast (with the cast sound `cast`
##   from `core/registry`, nothing on null).
## - **The builder** (`staff_change_requested`, `card_move_requested`, `staff_cards_requested`,
##   each for this seat only; commands, heard at the tick's start: core/events `listen`) builds the home body's staffs with `Caster.set_staff`, also during a
##   possession. A change is refused only when the slot does not exist or the card is not in the
##   `bag` (the run mode's, from `seat_wizard`; every card in the registry when none was given); `card_move_requested`'s staff
##   BAG (-1) is the bag.
## - **A set bag** (each run mode's, from flow through `seat_wizard`; the horde's picks,
##   docs/milestones/horde.md): `bag_set_requested` for this seat (or `set_bag`) makes the bag
##   exactly that list and sends `bag_changed`. A set bag is never
##   overwritten by the first fill, also when it was set before the wizard first drove.
## - **Possessed** (G9): when another actor's controller takes the actor it drives, it is set aside
##   (`set_aside`, `is_set_aside`) and drives nothing until `started` hands it an actor again; the
##   panel goes on showing the wizard, and the time is drawn over the wizard (`PossessedLook`).
##
## Its seat is in the actor table through the actor it drives (`Actor.seat`, `Actors.set_driver`),
## so Spells' budgets (and `mana_reserved`, which no HUD reads yet) reach this seat while it drives;
## the HUD finds the home body by `Actors.home_of_seat`. It binds the home body's Health, Caster and
## the builder's requests once, when it first drives it (it is a node of that body, so they go
## together), and the driven actor's casts in `started`, letting go in `stopped`; it works the same
## on any actor with a Caster, Health and Mover (each optional). Nothing here allocates per step.
##
## Flow puts a wizard together with `seat_wizard` before adding it to the tree.

const FramesScript := preload("res://core/sim/frames.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A staff cast pressed this long (seconds) before the staff is ready still happens.
const INPUT_BUFFER: float = 0.15
## The four staff buttons (0 RB, 1 RT, 2 LB, 3 LT; owner, 2026-10-26).
const STAFF_COUNT: int = 4
## Id of the cast sound (looked up in core/registry; a missing sound is silent).
const CAST_SOUND_ID: StringName = &"cast"
## `card_move_requested`'s staff for the bag.
const BAG: int = -1

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"registry", &"frames"]
## State as who they point at: the actor it drives and its home body, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_actor", &"_home"]
## Not state: what only the drawing reads and writes (core/sim/README.md).
const VIEW: Array[StringName] = [&"_sound_player"]

## The frames service (core/sim/frames.gd: this seat's input frame each tick) and the registry (the
## bag, the cast sound). Only tests set these, before adding the node; otherwise the "Frames" and
## "Registry" autoloads are used. The frames service is the seat's only input (online-ready N9): a
## test feeds a seat through one of its own (tests/gameplay/player/wizard_fixture.gd), and one set
## to null later gives no input at all.
var frames: FramesScript = null
var registry: RegistryScript = null

## The card ids this seat may build with. Filled from the registry when it first drives, unless
## it was set (`set_bag`) before.
var bag: Array[StringName] = []

## The actor driven now (set by `started`, cleared by `stopped`), or null.
var _actor: Actor = null
## Its home body (the actor whose home controller it is), bound the first time it drives it.
var _home: Actor = null
## Per staff: the seconds left in which a remembered press still counts (0 = none remembered).
var _buffer_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _bag_filled: bool = false
var _sound_player: AudioStreamPlayer = null
## What the last `player_stats_changed` said, to send it only on a change.
var _sent_health: float = -1.0
var _sent_mana: int = -1
var _sent_shown: int = -1
## What the last `staff_mana_changed` of each staff said (its whole mana; -1: not sent yet).
var _sent_staff_mana: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _sent_staff_max: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
## True while a possession has set it aside (`set_aside`), until it drives again.
var _aside: bool = false


func _init() -> void:
	team = ActorsScript.TEAM_WIZARDS


func _ready() -> void:
	if frames == null:
		frames = get_node_or_null("/root/Frames") as FramesScript
		if frames == null:
			push_warning("PlayerController %d: the Frames autoload is missing, so this seat cannot move." % seat)
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if _sound_player == null:
		_sound_player = AudioStreamPlayer.new()
		add_child(_sound_player)


## Get `body` (a wizard scene, not yet in the tree) ready for seat `seat_index`: its controller's
## seat, its ramp (the seat's colour), its four staffs (`staff` for every button, or `staffs`,
## one per button: the four heads; and `cards`: four lists of card ids, built when it enters the
## tree) and its `bag` (the run mode's, `set_bag`; empty: every card of the registry). Returns its
## controller, or null when `body` has none.
static func seat_wizard(body: Actor, seat_index: int, staff: StaffBase, cards: Array, staffs: Array[StaffBase] = [], bag: Array[StringName] = []) -> PlayerController:
	var controller: PlayerController = of(body)
	if controller == null:
		return null
	controller.seat = seat_index
	if not bag.is_empty():
		controller.set_bag(bag)
	body.ramp = seat_index
	for child in body.get_children():
		if child is Caster:
			(child as Caster).staff = staff
			(child as Caster).staffs = staffs
			(child as Caster).start_cards = cards
	return controller


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


func started(actor: Actor) -> void:
	_actor = actor
	_aside = false
	forget_presses()
	if actor.caster != null:
		actor.caster.cast_done.connect(_on_cast_done)
	if _home == null and actor.home_controller == self:
		_bind_home(actor)
	elif actor != _home:
		return
	# Home again (or for the first time): the panel gets the wizard's staffs (a staff not built
	# yet is announced when its Caster builds it) and numbers anew.
	if actor.caster != null and actor.caster.number >= 0:
		for at in actor.caster.staff_count:
			_on_staff_built(at)
	_sent_health = -1
	_sent_mana = -1
	_sent_staff_mana.fill(-1)
	_sent_staff_max.fill(-1.0)
	announce_stats()


## Bind the home body's numbers and staffs, and the builder's requests, for good (this node goes
## with that body).
func _bind_home(actor: Actor) -> void:
	_home = actor
	# The seat's mouse aims from its wizard's hand (the frames service's local input layer).
	if frames != null:
		frames.set_aim_pivot(seat, _home_pivot)
	if actor.caster != null:
		actor.caster.staff_built.connect(_on_staff_built)
	if actor.health != null:
		actor.health.changed.connect(_on_health_changed)
	var bus: EventsScript = actor.events
	if bus != null:
		# Commands, heard at the tick's start (core/events, online-ready N2).
		bus.listen(&"staff_change_requested", _on_staff_change_requested)
		bus.listen(&"card_move_requested", _on_card_move_requested)
		bus.listen(&"staff_cards_requested", _on_staff_cards_requested)
		bus.bag_set_requested.connect(_on_bag_set_requested)
		if not _bag_filled:
			_fill_bag()
		else:
			_announce_bag()


## Where the seat's mouse aims from: its home wizard's hand (`Actor.aim_pivot`), INF while it has
## none in the world.
func _home_pivot() -> Vector2:
	if _home == null or not is_instance_valid(_home) or not _home.is_inside_tree():
		return Vector2.INF
	return _home.aim_pivot()


## A possession took the actor it drove for `seconds`: it drives nothing until `started`.
func set_aside(_actor_taken: Actor, _seconds: float) -> void:
	_aside = true


## While it is away from its wizard, the wizard's mana still reaches the panel.
func watch_home(_body: Actor, _delta: float) -> void:
	announce_stats()


## True while a possession has set this seat aside (it drives nothing).
func is_set_aside() -> bool:
	return _aside


func stopped(actor: Actor) -> void:
	if actor.caster != null and actor.caster.cast_done.is_connected(_on_cast_done):
		actor.caster.cast_done.disconnect(_on_cast_done)
	if _actor == actor:
		_actor = null


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


## Send `staff_mana_changed` for each staff of the home body whose whole mana or pool size
## differs from the last one sent, and `player_stats_changed` if its health, the staff on show or that staff's
## whole mana differ.
func announce_stats() -> void:
	if _home == null or not is_instance_valid(_home) or _home.events == null:
		return
	var caster: Caster = _home.caster
	if caster != null:
		for at in mini(caster.staff_count, STAFF_COUNT):
			var whole: int = floori(caster.mana_of(at))
			var most: float = caster.max_mana_of(at)
			if whole != _sent_staff_mana[at] or most != _sent_staff_max[at]:
				_sent_staff_mana[at] = whole
				_sent_staff_max[at] = most
				_home.events.staff_mana_changed.emit(seat, at, float(whole), most)
	var health: float = _home.health.health if _home.health != null else 0.0
	var max_health: float = _home.health.max_health if _home.health != null else 0.0
	var shown: int = caster.current if caster != null else 0
	var whole_mana: int = floori(caster.mana_of(shown)) if caster != null else 0
	if health == _sent_health and whole_mana == _sent_mana and shown == _sent_shown:
		return
	_sent_health = health
	_sent_mana = whole_mana
	_sent_shown = shown
	var max_mana: float = caster.max_mana_of(shown) if caster != null else 0.0
	_home.events.player_stats_changed.emit(seat, health, max_health, float(whole_mana), max_mana)


func _on_health_changed(_health: float, _max_health: float) -> void:
	announce_stats()


## A staff of the driven actor was cast: the seat's cast events, the sound, the mana spent (the
## home body's, when it is the one cast), and the buffered press is used up.
func _on_cast_done(at: int, origin: Vector2, direction: Vector2) -> void:
	if at >= 0 and at < STAFF_COUNT:
		_buffer_left[at] = 0.0
	if _actor == null:
		return
	announce_stats()
	var bus: EventsScript = _actor.events
	if bus != null:
		var form: StringName = _actor.caster.last_form(at)
		if form != &"":
			bus.spell_cast.emit(seat, form, origin, direction)
		bus.staff_cast.emit(seat, at, origin, direction)
	_play_cast_sound()


## A staff of the home body was built: the panel and the builder see its plain view.
func _on_staff_built(at: int) -> void:
	if _home != null and _home.events != null and _home.caster != null:
		_home.events.staff_changed.emit(seat, at, _home.caster.plan_of(at))


func _play_cast_sound() -> void:
	if registry == null or _sound_player == null or not _sound_player.is_inside_tree():
		return
	var stream: AudioStream = registry.get_sound(CAST_SOUND_ID)
	if stream == null:
		return
	_sound_player.stream = stream
	_sound_player.play()


func _fill_bag() -> void:
	_bag_filled = true
	bag.clear()
	if registry != null:
		for id: StringName in registry.get_ids(&"spells"):
			if registry.get_resource(&"spells", id) is SpellComponent:
				bag.append(id)
	_announce_bag()


## Make the bag exactly `cards` (a copy) and announce it. The first fill never overwrites it.
func set_bag(cards: Array[StringName]) -> void:
	_bag_filled = true
	bag.assign(cards)
	_announce_bag()


func _on_bag_set_requested(player: int, cards: Array[StringName]) -> void:
	if player == seat:
		set_bag(cards)


## `bag_changed` for this seat, once it has a home body (before that, binding it announces).
func _announce_bag() -> void:
	if _home != null and _home.events != null:
		_home.events.bag_changed.emit(seat, bag.duplicate())


func _refuse(reason: String) -> void:
	if _home != null and _home.events != null:
		_home.events.build_refused.emit(seat, reason)


## The home body's Caster: the builder edits the player's own wizard, also during a possession.
func _builder_caster() -> Caster:
	return _home.caster if _home != null else null


## A builder asked to put `card_id` into `slot` of staff `at` (`&""` empties it).
func _on_staff_change_requested(player: int, at: int, slot: int, card_id: StringName) -> void:
	if player != seat:
		return
	var caster: Caster = _builder_caster()
	if caster == null or at < 0 or at >= caster.staff_count or slot < 0 or slot >= caster.slot_count(at):
		_refuse("There is no such slot.")
		return
	if card_id != &"" and not bag.has(card_id):
		_refuse("You do not have that card.")
		return
	var row: Array[StringName] = caster.cards_of(at)
	row[slot] = card_id
	caster.set_staff(at, row)


## A builder asked to set every slot of staff `at` at once (`cards` by slot; fewer than the
## staff's slots empties the rest). Refused, and nothing changes, for a staff that does not
## exist, more cards than slots, or a card not in the `bag`.
func _on_staff_cards_requested(player: int, at: int, cards: Array[StringName]) -> void:
	if player != seat:
		return
	var caster: Caster = _builder_caster()
	if caster == null or at < 0 or at >= caster.staff_count or cards.size() > caster.slot_count(at):
		_refuse("There is no such slot.")
		return
	for card_id in cards:
		if card_id != &"" and not bag.has(card_id):
			_refuse("You do not have that card.")
			return
	caster.set_staff(at, cards)


## A builder asked to move a card: from a slot of one staff to a slot of another (or the same),
## swapping with what is there; from the bag (`from_staff` BAG, `from_slot` the bag index) it is
## put in, and to the bag (`to_staff` BAG) the slot is emptied.
func _on_card_move_requested(player: int, from_staff: int, from_slot: int, to_staff: int, to_slot: int) -> void:
	if player != seat:
		return
	var caster: Caster = _builder_caster()
	if caster == null:
		_refuse("There is no such slot.")
		return
	var staffs: int = caster.staff_count
	var from_ok: bool = (from_staff == BAG and from_slot >= 0 and from_slot < bag.size()) or (from_staff >= 0 and from_staff < staffs and from_slot >= 0 and from_slot < caster.slot_count(from_staff))
	var to_ok: bool = to_staff == BAG or (to_staff >= 0 and to_staff < staffs and to_slot >= 0 and to_slot < caster.slot_count(to_staff))
	if not from_ok or not to_ok:
		_refuse("There is no such slot.")
		return
	if from_staff == BAG:
		if to_staff != BAG:
			_on_staff_change_requested(seat, to_staff, to_slot, bag[from_slot])
		return
	if to_staff == BAG:
		_on_staff_change_requested(seat, from_staff, from_slot, &"")
		return
	var source: Array[StringName] = caster.cards_of(from_staff)
	var moving: StringName = source[from_slot]
	if from_staff == to_staff:
		source[from_slot] = source[to_slot]
		source[to_slot] = moving
		caster.set_staff(from_staff, source)
		return
	var target: Array[StringName] = caster.cards_of(to_staff)
	source[from_slot] = target[to_slot]
	target[to_slot] = moving
	caster.set_staff(from_staff, source)
	caster.set_staff(to_staff, target)

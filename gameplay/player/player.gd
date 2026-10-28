class_name PlayerController
extends ActorController
## The player's controller (actors G7, docs/milestones/M2-actors.md, "The components"): a human
## seat 0-3 and its input. It drives one actor at a time, its home actor (the wizard of
## content/wizard/base/wizard.tscn, where it is the `PlayerController` node) or another one it
## was handed (`Actor.drive`, possess in G9). It reads only its own seat's input from `core/input`
## and never looks at another seat, so nobody waits for anybody.
##
## It IS the seat: the HUD, the builder and the rest of the game hear a seat only from here.
##
## - **Input to intent** (`think`): the walk; the aim (the right stick, which holds AIM_HOLD_TIME
##   after it is let go, so a quick flick still shoots where it pointed; the keyboard player aims
##   at the mouse once it has moved, the J key switches back; with no aim input the walk
##   direction); the four staff buttons `staff_1` to `staff_4` (staffs 0-3: RB, RT, LB, LT). A
##   button is held while it is down, and a press is counted (`get_press_count`, so a tap released
##   before the step looked is not lost) and remembered for INPUT_BUFFER seconds, pressed again
##   each step until a cast leaves, so a tap just before the staff is ready still fires. The
##   Caster casts (a press, or a hold while no sustained card is on). While an overlay captures
##   the seat (`is_captured`) the move in progress stops (`Mover.stop`), the intent is empty and
##   presses made meanwhile are not held against the player later; while the actor is down, too.
## - **The seat's events** (only from the actor it drives now, so an undriven body sends none):
##   `player_stats_changed` (when it starts driving, on a health change and when mana crosses a
##   whole number: the mana is looked at each step, so a regen shows a step later),
##   `spell_cast` (the carrier, `Caster.last_form`), `staff_cast` and `wizard_cast` on every cast
##   (with the cast sound `cast` from `core/registry`, nothing on null), `staff_changed` with the
##   plain view of every built staff (`Caster.plan_of`), `bag_changed` and `build_refused`.
## - **The builder** (`staff_change_requested`, `card_move_requested`, `staff_cards_requested`,
##   each for this seat only) builds the driven actor's staffs with `Caster.set_staff`. A change
##   is refused only when the slot does not exist or the card is not in the `bag` (every card in
##   the registry until M3's rewards fill it); `card_move_requested`'s staff BAG (-1) is the bag.
##
## - **Possessed** (G9): when another actor's controller takes the actor it drives, it is set aside
##   (`set_aside`) and sends `player_possessed(seat, seconds)`, so the panel marks the seat
##   possessed with the time left; it drives nothing meanwhile. When it drives again `started`
##   sends `player_possessed(seat, 0)`. When it drives an actor with fewer staffs than four (a
##   possessed imp), the staffs it lacks are announced empty, so the panel and the builder show
##   only what that actor has.
##
## Its seat is in the actor table through the actor it drives (`Actor.seat`, `Actors.set_driver`),
## so Spells' `mana_reserved` and budgets reach this seat while it drives. It binds to the actor
## handed to `started` and lets go in `stopped`; it never keeps its home body, so it works the same
## on any actor with a Caster, Health and Mover (each optional). Nothing here allocates per step.
##
## Flow puts a wizard together with `seat_wizard` before adding it to the tree.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A staff cast pressed this long (seconds) before the staff is ready still happens.
const INPUT_BUFFER: float = 0.15
## The four staff buttons (0 RB, 1 RT, 2 LB, 3 LT; owner, 2026-10-26).
const STAFF_COUNT: int = 4
const CAST_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## Seconds the aim holds after the right stick is let go.
const AIM_HOLD_TIME: float = 0.6
## A point closer than this (pixels) to the hand gives no direction (`aim_at`).
const MOUSE_MIN_DISTANCE: float = 4.0
## Id of the cast sound (looked up in core/registry; a missing sound is silent).
const CAST_SOUND_ID: StringName = &"cast"
## `card_move_requested`'s staff for the bag.
const BAG: int = -1

## The input manager and the registry (the bag, the cast sound). Only tests set these, before
## adding the node; otherwise the "PlayerInput" and "Registry" autoloads are used.
var input: InputManagerScript = null
var registry: RegistryScript = null

## The card ids this seat may build with. Filled from the registry when it first drives.
var bag: Array[StringName] = []

## Only tests set this: the mouse position in the world, instead of the real one.
## Vector2.INF means "ask the viewport".
var mouse_world_override: Vector2 = Vector2.INF

## The actor driven now (set by `started`, cleared by `stopped`), or null.
var _actor: Actor = null
var _aim_hold_left: float = 0.0
## Per staff: the button's press count last seen, and the seconds left in which a remembered
## press still counts (0 = none remembered).
var _seen_presses: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _buffer_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _bag_filled: bool = false
var _sound_player: AudioStreamPlayer = null
## What the last `player_stats_changed` said, to send it only on a change.
var _sent_health: int = -1
var _sent_mana: int = -1
## True while a possession has set it aside (`set_aside`), until it drives again.
var _aside: bool = false


func _init() -> void:
	team = ActorsScript.TEAM_WIZARDS


func _ready() -> void:
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
		if input == null:
			push_warning("PlayerController %d: the PlayerInput autoload is missing, so this seat cannot move." % seat)
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if _sound_player == null:
		_sound_player = AudioStreamPlayer.new()
		add_child(_sound_player)


## Get `body` (a wizard scene, not yet in the tree) ready for seat `seat_index`: its controller's
## seat, its ramp (the seat's hat colour) and its four staffs (`staff`, and `cards`: four lists of
## card ids, built when it enters the tree). Returns its controller, or null when `body` has none.
static func seat_wizard(body: Actor, seat_index: int, staff: StaffBase, cards: Array) -> PlayerController:
	var controller: PlayerController = of(body)
	if controller == null:
		return null
	controller.seat = seat_index
	body.ramp = seat_index
	for child in body.get_children():
		if child is Caster:
			(child as Caster).staff = staff
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


func started(actor: Actor) -> void:
	_actor = actor
	_aim_hold_left = 0.0
	_sent_health = -1
	_sent_mana = -1
	forget_presses()
	if actor.caster != null:
		actor.caster.cast_done.connect(_on_cast_done)
		actor.caster.staff_built.connect(_on_staff_built)
	if actor.health != null:
		actor.health.changed.connect(_on_health_changed)
	var bus: EventsScript = actor.events
	if bus != null:
		bus.staff_change_requested.connect(_on_staff_change_requested)
		bus.card_move_requested.connect(_on_card_move_requested)
		bus.staff_cards_requested.connect(_on_staff_cards_requested)
		if not _bag_filled:
			_fill_bag()
		else:
			bus.bag_changed.emit(seat, bag.duplicate())
	# The panel shows what this seat drives now: the staffs it has (a staff not built yet is
	# announced when the actor's Caster builds it), none where it has fewer, and its numbers.
	var staffs: int = actor.caster.staff_count if actor.caster != null else 0
	if actor.caster != null and actor.caster.number >= 0:
		for at in staffs:
			_on_staff_built(at)
	if bus != null:
		for at in range(staffs, STAFF_COUNT):
			bus.staff_changed.emit(seat, at, {})
		if _aside:
			bus.player_possessed.emit(seat, 0.0)
	_aside = false
	announce_stats()


## A possession took the actor it drove for `seconds`: the seat's panel shows it possessed.
func set_aside(actor: Actor, seconds: float) -> void:
	_aside = true
	if actor.events != null:
		actor.events.player_possessed.emit(seat, seconds)


## True while a possession has set this seat aside (it drives nothing).
func is_set_aside() -> bool:
	return _aside


func stopped(actor: Actor) -> void:
	if actor.caster != null:
		if actor.caster.cast_done.is_connected(_on_cast_done):
			actor.caster.cast_done.disconnect(_on_cast_done)
		if actor.caster.staff_built.is_connected(_on_staff_built):
			actor.caster.staff_built.disconnect(_on_staff_built)
	if actor.health != null and actor.health.changed.is_connected(_on_health_changed):
		actor.health.changed.disconnect(_on_health_changed)
	var bus: EventsScript = actor.events
	if bus != null and is_instance_valid(bus):
		if bus.staff_change_requested.is_connected(_on_staff_change_requested):
			bus.staff_change_requested.disconnect(_on_staff_change_requested)
		if bus.card_move_requested.is_connected(_on_card_move_requested):
			bus.card_move_requested.disconnect(_on_card_move_requested)
		if bus.staff_cards_requested.is_connected(_on_staff_cards_requested):
			bus.staff_cards_requested.disconnect(_on_staff_cards_requested)
	if _actor == actor:
		_actor = null


## The seat's input becomes the actor's intent for this step (see the class doc).
func think(actor: Actor, delta: float) -> void:
	var intent: ActorIntent = actor.intent
	announce_stats()
	for at in STAFF_COUNT:
		_buffer_left[at] = maxf(_buffer_left[at] - delta, 0.0)
	if input == null or actor.is_down():
		# No input (only in tests), or down: stand, cast nothing, and presses made meanwhile are
		# not held against the player after a revive.
		intent.clear()
		forget_presses()
		return
	var captured: bool = input.is_captured(seat)
	if captured and actor.mover != null and actor.mover.is_moving():
		# An overlay opened: freeze, and end a dash in progress.
		actor.mover.stop()
	var move: Vector2 = input.get_move(seat)
	intent.move = move
	intent.aim = _aim(actor, move, delta)
	# Count presses rather than asking "just pressed": a tap released again before this step is
	# not lost. The staff buttons are hidden while an overlay is open (captured), so a menu tap
	# never casts, and a press made meanwhile is not held against the player later.
	for at in STAFF_COUNT:
		var presses: int = input.get_press_count(seat, CAST_ACTIONS[at])
		var fresh: bool = presses != _seen_presses[at]
		_seen_presses[at] = presses
		if captured:
			_buffer_left[at] = 0.0
			intent.hold(at, false)
			continue
		if fresh:
			_buffer_left[at] = INPUT_BUFFER
		intent.hold(at, input.is_action_pressed(seat, CAST_ACTIONS[at]))
		if _buffer_left[at] > 0.0:
			intent.press(at)


## The aim for this step: the right stick, else the mouse (keyboard player), else the held stick
## aim, else the move direction; ZERO keeps the aim the actor has.
func _aim(actor: Actor, move: Vector2, delta: float) -> Vector2:
	var stick: Vector2 = input.get_aim(seat)
	if stick != Vector2.ZERO:
		_aim_hold_left = AIM_HOLD_TIME
		return stick
	if input.is_mouse_aiming(seat):
		_aim_hold_left = 0.0
		return aim_at(actor, _mouse_world(actor))
	_aim_hold_left = maxf(_aim_hold_left - delta, 0.0)
	if _aim_hold_left <= 0.0 and move != Vector2.ZERO:
		return move.normalized()
	return Vector2.ZERO


## The aim (unit length) for a shot of `actor` that flies through `point` (world position):
## measured from the hand (`Actor.aim_pivot`), so the shot from the staff tip passes `point`.
## Vector2.ZERO when `point` is within MOUSE_MIN_DISTANCE of the hand.
func aim_at(actor: Actor, point: Vector2) -> Vector2:
	var to_point: Vector2 = point - actor.aim_pivot()
	if to_point.length() < MOUSE_MIN_DISTANCE:
		return Vector2.ZERO
	return to_point.normalized()


func _mouse_world(actor: Actor) -> Vector2:
	if mouse_world_override != Vector2.INF:
		return mouse_world_override
	return actor.get_global_mouse_position() if actor.is_inside_tree() else actor.global_position


## Take the press counts as they are now, so no press made before counts later.
func forget_presses() -> void:
	for at in STAFF_COUNT:
		_buffer_left[at] = 0.0
		if input != null:
			_seen_presses[at] = input.get_press_count(seat, CAST_ACTIONS[at])


## Send `player_stats_changed` for the driven actor if its health or whole mana differ from the
## last one sent.
func announce_stats() -> void:
	if _actor == null or _actor.events == null:
		return
	var health: int = _actor.health.health if _actor.health != null else 0
	var max_health: int = _actor.health.max_health if _actor.health != null else 0
	var whole_mana: int = floori(_actor.caster.mana) if _actor.caster != null else 0
	if health == _sent_health and whole_mana == _sent_mana:
		return
	_sent_health = health
	_sent_mana = whole_mana
	var max_mana: float = _actor.caster.max_mana if _actor.caster != null else 0.0
	_actor.events.player_stats_changed.emit(seat, health, max_health, float(whole_mana), max_mana)


func _on_health_changed(_health: int, _max_health: int) -> void:
	announce_stats()


## A staff of the driven actor was cast: the seat's cast events, the sound, the mana spent, and
## the buffered press is used up.
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
		bus.wizard_cast.emit(seat, _actor)
	_play_cast_sound()


## A staff of the driven actor was built: the builder sees its plain view.
func _on_staff_built(at: int) -> void:
	if _actor != null and _actor.events != null and _actor.caster != null:
		_actor.events.staff_changed.emit(seat, at, _actor.caster.plan_of(at))


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
	if _actor != null and _actor.events != null:
		_actor.events.bag_changed.emit(seat, bag.duplicate())


func _refuse(reason: String) -> void:
	if _actor != null and _actor.events != null:
		_actor.events.build_refused.emit(seat, reason)


## The driven actor's Caster, when it has staffs a builder may edit.
func _builder_caster() -> Caster:
	return _actor.caster if _actor != null else null


## A builder asked to put `card_id` into `slot` of staff `at` (`&""` empties it).
func _on_staff_change_requested(player: int, at: int, slot: int, card_id: StringName) -> void:
	if player != seat:
		return
	var caster: Caster = _builder_caster()
	if caster == null or at < 0 or at >= caster.staff_count or slot < 0 or slot >= caster.slot_count():
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
	if caster == null or at < 0 or at >= caster.staff_count or cards.size() > caster.slot_count():
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
	var slots: int = caster.slot_count()
	var staffs: int = caster.staff_count
	var from_ok: bool = (from_staff == BAG and from_slot >= 0 and from_slot < bag.size()) or (from_staff >= 0 and from_staff < staffs and from_slot >= 0 and from_slot < slots)
	var to_ok: bool = to_staff == BAG or (to_staff >= 0 and to_staff < staffs and to_slot >= 0 and to_slot < slots)
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

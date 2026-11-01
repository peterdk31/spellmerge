extends RefCounted
## A bot: plays one player slot through a virtual device and the real input path
## (`PlayerInput.send_virtual`, `send_virtual_aim`), the same path a gamepad uses. It never
## touches a spell field or the projectile manager's shots, so it plays the way a person does: the
## wizard casts what its buttons say.
##
## Fighter (enemy AI L5, docs/milestones/M2-enemy-ai.md): its decisions come from the same brain
## every enemy plays by (`AIBrain`, gameplay/ai/brain.gd), with the bot's profile
## (`bot_profile.tres`: no rest, pressing on, quick to react, dodging). The brain drives the
## wizard but writes a spare `ActorIntent`, never the wizard's own, and the bot turns that into
## buttons: the walk into the four move actions, the aim into the virtual right stick, a tap of
## a staff's button for each press and the button held while a staff is held. The wizard is on
## the players' team, so the brain winds up nothing (enemies telegraph, allies don't: owner,
## 2026-11-01) and casts the step a staff is ready. It reads what each staff casts next
## (`CastSense`), never a card: it fires the staff that hurts and reaches, walks round walls
## (`AISight`), dodges shots and the telegraphs aimed at it, and when getting away is urgent it
## taps whichever staff's next cast moves the caster (no button is "the dash"). It holds no grudge
## (a teammate's blast never makes it fight a teammate) and is lured by no decoy.
## Idler: stands still; it only opens its builder.
##
## Builder: `build_random(seed)` builds a random staff into staff 3 (BUILD_STAFF, LB, empty at the
## start) with the same `staff_change_requested` events a person sends (slot by slot, from the
## bag of the wizard). The cards come from `staff_fuzzer.gd`, seeded, so a failing run can be
## replayed. `open_builder()` is how bot 4 of the 4-bot test works: one press of `back` (B),
## and it stays there (the full builder, waves included).
##
## Everything is driven by step(delta), so a run with the same frames repeats. A bot sends an
## input only when it changes. Nothing is allocated per step.

enum Mode { FIGHTER, IDLER }

const FuzzerScript := preload("res://tests/bots/staff_fuzzer.gd")
## How a bot plays (the brain's numbers).
const PROFILE: AIProfile = preload("res://tests/bots/bot_profile.tres")

## The staff a bot builds into: staff 3, LB (empty at the start).
const BUILD_STAFF: int = 2
## The staff buttons, by staff.
const STAFF_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## A random staff has at most this many cards, so a built staff stays quick to cast.
const BUILD_CARDS: int = 6
## The brain of bot `i` is seeded SEED + i, so a run repeats.
const SEED: int = 4111

var player: int = 0
var mode: Mode = Mode.FIGHTER
## The fighter's brain, and the intent it writes (the bot's, never the wizard's own).
var brain: AIBrain = AIBrain.new()
var intent: ActorIntent = ActorIntent.new()

var _input: Node = null
var _flow: Node = null
var _held_move: Vector2i = Vector2i.ZERO
var _held_aim: Vector2 = Vector2.ZERO
## The staffs it holds now, by index (0 to 3).
var _held_staffs: PackedByteArray = PackedByteArray([0, 0, 0, 0])

## The cards of the last `build_random`, one per slot of the staff (empty before the first).
var built_cards: Array[StringName] = []
## How many `staff_change_requested` events the bot has sent.
var requests_sent: int = 0


## `input` is the `PlayerInput` autoload and `flow` the `Flow` autoload. Takes the
## virtual device of `index`; returns false if that slot is not free.
func join(index: int, bot_mode: Mode, input: Node, flow: Node) -> bool:
	player = index
	mode = bot_mode
	_input = input
	_flow = flow
	return int(_input.call("add_virtual_device", player)) != int(_input.get("NO_DEVICE"))


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
	var bag: Array[StringName] = []
	bag.assign(PlayerController.of(wizard).bag)
	var fuzzer := FuzzerScript.new(bag, func(id: StringName) -> StringName: return spells.call("component_kind", id))
	if not fuzzer.can_build():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = build_seed
	var slots: int = wizard.caster.slot_count()
	var cards: Array[StringName] = fuzzer.random_cards(rng, mini(BUILD_CARDS, slots))
	built_cards.clear()
	for slot in slots:
		built_cards.append(cards[slot] if slot < cards.size() else &"")
		events.emit_signal("staff_change_requested", player, BUILD_STAFF, slot, built_cards[slot])
		requests_sent += 1
	return true


## Open the builder as a person does: one press of `back` (B).
func open_builder() -> void:
	tap_back()


## Let go of everything the bot holds and free the slot.
func leave() -> void:
	_release()
	_input.call("leave", player)


## One step: the brain thinks for the wizard and the bot presses what it wants. An idler does
## nothing.
func step(delta: float) -> void:
	if mode == Mode.IDLER:
		return
	var wizard := _flow.call("get_wizard", player) as Actor
	if wizard == null or _flow.get("world") == null or wizard.is_down() or wizard.caster == null:
		_release()
		return
	if brain.actor != wizard:
		# A new wizard (a new run): a fresh brain for it.
		intent.clear()
		brain.setup(wizard, PROFILE, SEED + player)
	intent.begin_step()
	brain.think(delta, intent)
	send(intent)


## Turn `wanted` into buttons: the walk, the aim, a tap per pressed staff and the button held per
## held staff.
func send(wanted: ActorIntent) -> void:
	_hold_move(wanted.move)
	_aim(wanted.aim)
	for at in STAFF_ACTIONS.size():
		var held: bool = wanted.is_held(at)
		if wanted.is_pressed(at):
			if _held_staffs[at] != 0:
				_input.call("send_virtual", player, STAFF_ACTIONS[at], 0.0)
			_input.call("send_virtual", player, STAFF_ACTIONS[at], 1.0)
			if not held:
				_input.call("send_virtual", player, STAFF_ACTIONS[at], 0.0)
			_held_staffs[at] = 1 if held else 0
		else:
			_hold_staff(at, held)


## Hold the four move actions for `direction` (each axis on or off).
func _hold_move(direction: Vector2) -> void:
	var wanted := Vector2i(signi(roundi(direction.x * 1.5)), signi(roundi(direction.y * 1.5)))
	if wanted == _held_move:
		return
	_input.call("send_virtual", player, &"move_left", 1.0 if wanted.x < 0 else 0.0)
	_input.call("send_virtual", player, &"move_right", 1.0 if wanted.x > 0 else 0.0)
	_input.call("send_virtual", player, &"move_up", 1.0 if wanted.y < 0 else 0.0)
	_input.call("send_virtual", player, &"move_down", 1.0 if wanted.y > 0 else 0.0)
	_held_move = wanted


## Push the right stick toward `direction` (ZERO lets it go, and the wizard aims where it walks).
func _aim(direction: Vector2) -> void:
	var wanted: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	if wanted == _held_aim:
		return
	_input.call("send_virtual_aim", player, wanted)
	_held_aim = wanted


func _hold_staff(at: int, on: bool) -> void:
	if (_held_staffs[at] != 0) == on:
		return
	_input.call("send_virtual", player, STAFF_ACTIONS[at], 1.0 if on else 0.0)
	_held_staffs[at] = 1 if on else 0


func _release() -> void:
	_hold_move(Vector2.ZERO)
	_aim(Vector2.ZERO)
	for at in _held_staffs.size():
		_hold_staff(at, false)
	if brain.actor != null:
		brain.reset()
		brain.actor = null

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
## taps whichever staff's next cast moves the caster (no button is "the dash"). It holds no grudge
## (a teammate's blast never makes it fight a teammate).
## Idler: stands still; it only opens its builder.
##
## Builder: `build_random(seed)` builds a random staff into staff 1 (BUILD_STAFF, RB: `dash` at the
## start, so RT keeps its `bolt` and the wave is still cleared; LB is an empty hand since items I2) with the same `staff_change_requested` events a person sends (slot by slot, from the
## bag of the wizard). The cards come from `staff_fuzzer.gd`, seeded, so a failing run can be
## replayed. `open_builder()` is how bot 4 of the 4-bot test works: one press of `back` (B),
## and it stays there (the full builder, waves included).
##
## The brain thinks at each tick's start, when the frames service asks for the frame
## (`fill_frame`), so a run repeats. Nothing is allocated per step.

enum Mode { FIGHTER, IDLER }

const FuzzerScript := preload("res://tests/bots/staff_fuzzer.gd")
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
	_flow = flow
	_wanted.seat = index
	_wanted.clear()
	if int(_input.call("add_virtual_device", player)) == int(_input.get("NO_DEVICE")):
		return false
	_frames = _input.get_tree().root.get_node_or_null("Frames")
	if _frames != null:
		_frames.call("set_source", player, self)
	return true


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


## Want `wanted` in the next frame: the walk (each axis full on or off, as the move keys), the aim
## (ZERO keeps it, and the wizard aims where it walks), a press per pressed staff and the button
## held per held staff. A press waits for the frame, so none is lost.
func send(wanted: ActorIntent) -> void:
	_wanted.set_move(Vector2(signi(roundi(wanted.move.x * 1.5)), signi(roundi(wanted.move.y * 1.5))).limit_length(1.0))
	_wanted.set_aim(wanted.aim)
	_wanted.held_bits = wanted.held_bits
	_wanted.pressed_bits |= wanted.pressed_bits


## The frame it wants next (read only; tests).
func wanted_frame() -> InputFrame:
	return _wanted


func _release() -> void:
	_wanted.clear()
	if brain.actor != null:
		brain.reset()
		brain.actor = null

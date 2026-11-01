extends RefCounted
## A bot: plays one player slot through a virtual device and the real input path
## (`PlayerInput.send_virtual`), the same path a gamepad uses. It holds `move_*` and the staff
## buttons `staff_2` and `staff_3` (RT, LB), and taps `staff_1` (RB, the dash staff) and `back`
## (B, which opens the builder in play); it never
## touches a spell field or the projectile manager, so it plays the way a person does. The
## wizard casts a staff when its button is held, so a bot calls nothing on a spell itself.
##
## Fighter: a state machine (owner, 2026-11-01), one `State` a step, picked in this order. It
## reads the world only, never what its own staffs will cast next (owner: which staff to fire
## needs more design):
## - DODGE: an enemy within DODGE_RANGE aims at the wizard and its windup is past DODGE_FROM, as
##   a person reads a telegraph. It seeks cover: if a way within COVER_PROBE pixels ends behind a
##   wall from the enemy (any wall, `AISight.cover`) it walks there and stays while the wall is
##   between them; else it steps off the line of the shot and taps `staff_1`, the dash (once per
##   windup).
## - UNSTICK: it hardly moved for STUCK_STEPS steps (a pillar): it side-steps for SIDESTEP_STEPS.
## - DETOUR: the nearest enemy is within FIRE_RANGE but a wall stands between them (any wall, its
##   own too: `AISight`, the walls shots stop on): it walks the way `AISight.detour` picks for
##   DETOUR_STEPS steps or until the line is clear, and holds no staff meanwhile.
## - ATTACK: within FIRE_RANGE with the line clear: it walks at the enemy (a wizard faces where it
##   walks, so the shots fly at it) and holds `staff_2` (RT, the fire bolt it starts with) and
##   `staff_3` (LB, the staff it built). It fires while dodging too, whenever the line is clear.
## - APPROACH: else it walks at the nearest enemy.
## Idler: stands still; it only opens its builder.
##
## Builder: `build_random(seed)` builds a random staff into staff 3 (BUILD_STAFF, LB, empty at the
## start) with the same `staff_change_requested` events a person sends (slot by slot, from the
## bag of the wizard). The cards come from `staff_fuzzer.gd`, seeded, so a failing run can be
## replayed. `open_builder()` is how bot 4 of the 4-bot test works: one press of `back` (B),
## and it stays there (the full builder, waves included).
##
## Everything is driven by step(delta), so a run with the same frames repeats. A
## bot sends an input only when it changes.

enum Mode { FIGHTER, IDLER }
## The fighter's states (see above).
enum State { APPROACH, ATTACK, DETOUR, UNSTICK, DODGE }

const FuzzerScript := preload("res://tests/bots/staff_fuzzer.gd")

## The staff a bot builds into: staff 3, LB (empty at the start; RB dashes and RT fires the
## start bolt).
const BUILD_STAFF: int = 2
## The staffs a fighter attacks with (RT and LB) and the staff buttons; the dash is staff 0 (RB).
const ATTACK_STAFFS: Array[int] = [1, 2]
const STAFF_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## A random staff has at most this many cards, so a built staff stays quick to cast.
const BUILD_CARDS: int = 6

## Closer than this (pixels) the bot holds `cast`.
const FIRE_RANGE: float = 170.0
## A step that moves less than this (pixels) counts as stuck.
const STUCK_DISTANCE: float = 0.5
const STUCK_STEPS: int = 20
const SIDESTEP_STEPS: int = 25
## How far (pixels) a way to cover is probed (`AISight.cover`).
const COVER_PROBE: float = 48.0
## How far ahead (pixels) a detour direction is probed, and how many steps it is kept.
const PROBE_DISTANCE: float = 40.0
const DETOUR_STEPS: int = 15
## A windup aimed at the wizard (within DODGE_AIM of its line) from closer than
## DODGE_RANGE pixels is dodged once it is DODGE_FROM along (0 to 1).
const DODGE_RANGE: float = 140.0
const DODGE_AIM: float = 0.9
const DODGE_FROM: float = 0.75

var player: int = 0
var mode: Mode = Mode.FIGHTER

var _input: Node = null
var _flow: Node = null
## The state it is in (a fighter), and the state's steps left (DETOUR, UNSTICK).
var state: State = State.APPROACH
var _state_left: int = 0
var _held_move: Vector2i = Vector2i.ZERO
## The staffs it holds now, by index (0 to 3).
var _held_staffs: PackedByteArray = PackedByteArray([0, 0, 0, 0])
## The way to cover in this DODGE, or ZERO when none was near.
var _cover: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.INF
var _stuck: int = 0
var _sidestep_sign: float = 1.0
var _detour: Vector2 = Vector2.ZERO
var _dodged_enemy: int = 0

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
	_sidestep_sign = 1.0 if index % 2 == 0 else -1.0
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


## One decision. An idler does nothing.
func step(_delta: float) -> void:
	if mode == Mode.IDLER:
		return
	var wizard := _flow.call("get_wizard", player) as Actor
	var world := _flow.get("world") as Node2D
	if wizard == null or world == null or wizard.is_down():
		_release()
		return
	var target: Node2D = _nearest_enemy(world, wizard.global_position)
	if target == null:
		_release()
		return
	_track_stuck(wizard.global_position)
	var threat: Node2D = _incoming(world, wizard)
	var in_range: bool = wizard.global_position.distance_to(target.global_position) <= FIRE_RANGE
	var clear: bool = _line_clear(wizard, target)
	_next_state(wizard, target, threat, in_range, clear)
	var direction: Vector2 = (target.global_position - wizard.global_position).normalized()
	match state:
		State.DODGE:
			if _cover != Vector2.ZERO and not _line_clear(wizard, threat):
				# In cover: a wall stands between it and the shot. Stay.
				direction = Vector2.ZERO
			else:
				direction = _cover if _cover != Vector2.ZERO else _off_the_line(wizard, threat)
		State.UNSTICK:
			direction = direction.orthogonal() * _sidestep_sign
		State.DETOUR:
			direction = _detour
	_hold_move(direction)
	# It fires whenever the line is clear and the enemy in range, dodging too; never into a wall.
	for at: int in ATTACK_STAFFS:
		_hold_staff(at, in_range and clear)


## The state for this step, in the order the header gives; entering one does its one-off part.
func _next_state(wizard: Actor, target: Node2D, threat: Node2D, in_range: bool, clear: bool) -> void:
	if threat == null:
		_dodged_enemy = 0
	else:
		if threat.get_instance_id() != _dodged_enemy:
			_dodged_enemy = threat.get_instance_id()
			_seek_cover(wizard, threat)
		state = State.DODGE
		return
	if _stuck >= STUCK_STEPS:
		_stuck = 0
		_sidestep_sign = -_sidestep_sign
		state = State.UNSTICK
		_state_left = SIDESTEP_STEPS
	if state == State.UNSTICK or state == State.DETOUR:
		_state_left -= 1
		if _state_left > 0 and not (state == State.DETOUR and clear):
			return
	if in_range and not clear:
		state = State.DETOUR
		_state_left = DETOUR_STEPS
		_detour = AISight.detour(wizard.projectiles, wizard.global_position, target.global_position, PROBE_DISTANCE)
		return
	state = State.ATTACK if in_range else State.APPROACH


## A threat's windup: cover within reach (any wall between it and the threat), else a dash.
func _seek_cover(wizard: Actor, threat: Node2D) -> void:
	_cover = AISight.cover(wizard.projectiles, wizard.global_position, threat.global_position, COVER_PROBE)
	if _cover == Vector2.ZERO and wizard.caster.has_staff(0):
		_tap(0)


## Off the line of the threat's shot, on the side the wizard already is.
func _off_the_line(wizard: Actor, threat: Node2D) -> Vector2:
	var aim: Vector2 = threat.get("aim")
	var away: Vector2 = wizard.global_position - threat.global_position
	var side: Vector2 = away - aim * away.dot(aim)
	return side.normalized() if side.length() > 1.0 else aim.orthogonal() * _sidestep_sign


## False when a wall (a room's or a Wall card's) is between the wizard and the enemy: shots
## stop there, and a person does not fire into a wall.
func _line_clear(wizard: Actor, target: Node2D) -> bool:
	var to: Vector2 = target.global_position
	if target is Actor:
		to += (target as Actor).body_offset
	return AISight.line_clear(wizard.projectiles, wizard.global_position + wizard.body_offset, to)


## The enemy about to shoot at the wizard (see DODGE_*), or null. Enemies stand in the world, or
## one level down under its `Horde` node (a horde run's enemies).
func _incoming(world: Node2D, wizard: Node2D) -> Node2D:
	var found: Node2D = _incoming_among(world, wizard)
	var horde: Node = world.get_node_or_null(^"Horde")
	if found == null and horde != null:
		found = _incoming_among(horde, wizard)
	return found


func _incoming_among(parent: Node, wizard: Node2D) -> Node2D:
	for child in parent.get_children():
		var enemy := child as Actor
		var ai: AIController = _ai_of(enemy)
		if ai == null or enemy.is_queued_for_deletion():
			continue
		if ai.telegraph_progress() < DODGE_FROM:
			continue
		var to_wizard: Vector2 = wizard.global_position - enemy.global_position
		if to_wizard.length() > DODGE_RANGE:
			continue
		var aim: Vector2 = enemy.get("aim")
		if aim.dot(to_wizard.normalized()) >= DODGE_AIM:
			return enemy
	return null


## The nearest enemy to `from`: among the world's children and, one level down, those of its
## `Horde` node (a horde run's enemies); null when there is none.
func _nearest_enemy(world: Node2D, from: Vector2) -> Node2D:
	var best: Node2D = _nearest_among(world, from, null)
	var horde: Node = world.get_node_or_null(^"Horde")
	if horde != null:
		best = _nearest_among(horde, from, best)
	return best


## The nearest enemy to `from` among `parent`'s children, or `best` when it is nearer.
func _nearest_among(parent: Node, from: Vector2, best: Node2D) -> Node2D:
	var best_distance: float = from.distance_squared_to(best.global_position) if best != null else INF
	for child in parent.get_children():
		# Enemies are the actors an AI drives (actors G6).
		var enemy := child as Actor
		if _ai_of(enemy) == null or enemy.is_queued_for_deletion():
			continue
		var distance: float = from.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## The AI driving `enemy`, or null (not an actor, or no AI drives it).
func _ai_of(enemy: Actor) -> AIController:
	return enemy.controller as AIController if enemy != null else null


func _track_stuck(at: Vector2) -> void:
	if state == State.UNSTICK or at.distance_to(_last_position) >= STUCK_DISTANCE:
		_stuck = 0
	else:
		_stuck += 1
	_last_position = at


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


func _hold_staff(at: int, on: bool) -> void:
	if (_held_staffs[at] != 0) == on:
		return
	_input.call("send_virtual", player, STAFF_ACTIONS[at], 1.0 if on else 0.0)
	_held_staffs[at] = 1 if on else 0


## Press and let go of staff `at` once (the dash).
func _tap(at: int) -> void:
	_input.call("send_virtual", player, STAFF_ACTIONS[at], 1.0)
	_input.call("send_virtual", player, STAFF_ACTIONS[at], 0.0)
	_held_staffs[at] = 0


func _release() -> void:
	_hold_move(Vector2.ZERO)
	for at in _held_staffs.size():
		_hold_staff(at, false)
	_cover = Vector2.ZERO
	state = State.APPROACH

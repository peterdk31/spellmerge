extends RefCounted
## A bot: plays one player slot through a virtual device and the real input path
## (`PlayerInput.send_virtual`), the same path a gamepad uses. It holds `move_*` and the staff
## buttons `staff_2` and `staff_3` (RT, LB), and taps `staff_1` (RB, the dash staff) and `back`
## (B, which opens the builder in play); it never
## touches a spell field or the projectile manager, so it plays the way a person does. The
## wizard casts a staff when its button is held, so a bot calls nothing on a spell itself.
##
## Fighter: walks toward the nearest enemy of the current world (a wizard faces
## where it walks, so the shots fly at the enemy) and holds `cast` within
## FIRE_RANGE and sees it (shots stop at walls): `staff_2` (the fire bolt it starts with) and
## `staff_3` (the staff it built, if any). With a wall in between it walks
## round it: it probes the eight directions PROBE_DISTANCE ahead, takes a free one
## from which the enemy is in view (else the free one nearest the enemy) and keeps
## it for DETOUR_STEPS steps. When it hardly moved for STUCK_STEPS steps (a pillar)
## it side-steps for SIDESTEP_STEPS steps. Dodge: like a person reading the
## telegraph, when an enemy within DODGE_RANGE is aimed at the wizard and its windup
## is past DODGE_FROM, the bot steps off the line of the shot and taps `staff_1`, the dash
## staff (once per windup). Idler: stands still; it only opens its builder.
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

const FuzzerScript := preload("res://tests/bots/staff_fuzzer.gd")

## The staff a bot builds into: staff 3, LB (empty at the start; RB dashes and RT fires the
## start bolt).
const BUILD_STAFF: int = 2
## A random staff has at most this many cards, so a built staff stays quick to cast.
const BUILD_CARDS: int = 6

## Closer than this (pixels) the bot holds `cast`.
const FIRE_RANGE: float = 170.0
## A step that moves less than this (pixels) counts as stuck.
const STUCK_DISTANCE: float = 0.5
const STUCK_STEPS: int = 20
const SIDESTEP_STEPS: int = 25
## How far ahead (pixels) a detour direction is probed, and how many steps it is kept.
const PROBE_DISTANCE: float = 40.0
const DETOUR_STEPS: int = 15
## A windup aimed at the wizard (within DODGE_AIM of its line) from closer than
## DODGE_RANGE pixels is dodged once it is DODGE_FROM along (0 to 1).
const DODGE_RANGE: float = 140.0
const DODGE_AIM: float = 0.9
const DODGE_FROM: float = 0.75
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1),
	Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]

var player: int = 0
var mode: Mode = Mode.FIGHTER

var _input: Node = null
var _flow: Node = null
var _held_move: Vector2i = Vector2i.ZERO
var _casting: bool = false
var _last_position: Vector2 = Vector2.INF
var _stuck: int = 0
var _sidestep_left: int = 0
var _sidestep_sign: float = 1.0
var _detour: Vector2 = Vector2.ZERO
var _detour_left: int = 0
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
## means the requests were sent; check the wizard's `cards_of(BUILD_STAFF)`.
func build_random(build_seed: int) -> bool:
	var root: Node = _flow.get_tree().root
	var events: Node = root.get_node_or_null("Events")
	var spells: Node = root.get_node_or_null("Spells")
	var wizard: Node = _flow.call("get_wizard", player) as Node
	if events == null or spells == null or wizard == null:
		return false
	var bag: Array[StringName] = []
	bag.assign(wizard.get("bag"))
	var fuzzer := FuzzerScript.new(bag, func(id: StringName) -> StringName: return spells.call("component_kind", id))
	if not fuzzer.can_build():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = build_seed
	var slots: int = int(wizard.call("slot_count"))
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
	var wizard := _flow.call("get_wizard", player) as Node2D
	var world := _flow.get("world") as Node2D
	if wizard == null or world == null or bool(wizard.call("is_downed")):
		_release()
		return
	var target: Node2D = _nearest_enemy(world, wizard.global_position)
	if target == null:
		_release()
		return
	var offset: Vector2 = target.global_position - wizard.global_position
	_track_stuck(wizard.global_position)
	var direction: Vector2 = offset.normalized()
	if _sidestep_left > 0:
		_sidestep_left -= 1
		direction = direction.orthogonal() * _sidestep_sign
	var in_range: bool = offset.length() <= FIRE_RANGE
	var sees: bool = _can_see(wizard, target)
	if sees:
		_detour_left = 0
	elif in_range and _sidestep_left == 0:
		# A wall in the way: walk round it until the enemy is in view.
		if _detour_left <= 0:
			_detour = _pick_detour(wizard, target)
			_detour_left = DETOUR_STEPS
		_detour_left -= 1
		direction = _detour
	var threat: Node2D = _incoming(world, wizard)
	if threat == null:
		_dodged_enemy = 0
	else:
		# Off the line of the shot, on the side the wizard already is.
		var aim: Vector2 = threat.get("aim")
		var away: Vector2 = wizard.global_position - threat.global_position
		var side: Vector2 = away - aim * away.dot(aim)
		direction = side.normalized() if side.length() > 1.0 else aim.orthogonal() * _sidestep_sign
	_hold_move(direction)
	if threat != null and threat.get_instance_id() != _dodged_enemy and bool(wizard.call("has_staff", 0)):
		_dodged_enemy = threat.get_instance_id()
		_input.call("send_virtual", player, &"staff_1", 1.0)
		_input.call("send_virtual", player, &"staff_1", 0.0)
	_hold_cast(in_range and sees)




## False when a wall (physics layer 1) is between the wizard and the enemy: shots
## stop at walls, and a person does not fire into a pillar. Without a physics
## space (a test without a world) nothing blocks.
func _can_see(wizard: Node2D, target: Node2D) -> bool:
	var space: PhysicsDirectSpaceState2D = wizard.get_world_2d().direct_space_state if wizard.is_inside_tree() else null
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(wizard.global_position, target.global_position, 1)
	return space.intersect_ray(query).is_empty()


## The direction to walk round a wall between the wizard and `target`: of the free
## directions (no wall within PROBE_DISTANCE), one from whose end the enemy is in
## view, else the one ending nearest the enemy. Without a physics space, straight on.
func _pick_detour(wizard: Node2D, target: Node2D) -> Vector2:
	var from: Vector2 = wizard.global_position
	var goal: Vector2 = target.global_position
	var straight: Vector2 = (goal - from).normalized()
	var space: PhysicsDirectSpaceState2D = wizard.get_world_2d().direct_space_state if wizard.is_inside_tree() else null
	if space == null:
		return straight
	var best: Vector2 = straight
	var best_score: float = INF
	for direction: Vector2 in DIRECTIONS:
		var end: Vector2 = from + direction.normalized() * PROBE_DISTANCE
		if not space.intersect_ray(PhysicsRayQueryParameters2D.create(from, end, 1)).is_empty():
			continue
		var score: float = end.distance_to(goal)
		if space.intersect_ray(PhysicsRayQueryParameters2D.create(end, goal, 1)).is_empty():
			# In view from there: always better than any direction that is not.
			score -= 100000.0
		if score < best_score:
			best_score = score
			best = direction
	return best


## The enemy about to shoot at the wizard (see DODGE_*), or null.
func _incoming(world: Node2D, wizard: Node2D) -> Node2D:
	for child in world.get_children():
		var enemy := child as CharacterBody2D
		if enemy == null or not enemy.has_method("telegraph_progress") or enemy.is_queued_for_deletion():
			continue
		if float(enemy.call("telegraph_progress")) < DODGE_FROM:
			continue
		var to_wizard: Vector2 = wizard.global_position - enemy.global_position
		if to_wizard.length() > DODGE_RANGE:
			continue
		var aim: Vector2 = enemy.get("aim")
		if aim.dot(to_wizard.normalized()) >= DODGE_AIM:
			return enemy
	return null


func _nearest_enemy(world: Node2D, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for child in world.get_children():
		# Enemies are the bodies with the AI script on their root.
		var enemy := child as CharacterBody2D
		if enemy == null or not enemy.has_method("telegraph_progress") or enemy.is_queued_for_deletion():
			continue
		var distance: float = from.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _track_stuck(at: Vector2) -> void:
	if _sidestep_left > 0:
		_last_position = at
		return
	if at.distance_to(_last_position) < STUCK_DISTANCE:
		_stuck += 1
		if _stuck >= STUCK_STEPS:
			_stuck = 0
			_sidestep_left = SIDESTEP_STEPS
			_sidestep_sign = -_sidestep_sign
	else:
		_stuck = 0
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


func _hold_cast(on: bool) -> void:
	if on == _casting:
		return
	_input.call("send_virtual", player, &"staff_2", 1.0 if on else 0.0)
	_input.call("send_virtual", player, &"staff_3", 1.0 if on else 0.0)
	_casting = on


func _release() -> void:
	_hold_move(Vector2.ZERO)
	_hold_cast(false)

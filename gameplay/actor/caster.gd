class_name Caster
extends ActorComponent
## The caster (actors G4, docs/milestones/M2-actors.md, "The components"): an actor's staffs and
## mana. It holds 1-4 staffs (`staff_count`), each a `StaffBase` (`staffs`, one per button; a
## button without one is `staff`) and a row of card ids; `set_staff(at, cards)` builds one and
## installs it in `Spells` under the actor's caster number (`number`). `current` is the staff on
## show (living staffs H3): the one pressed or held last, set before it casts, so the cast leaves
## from that staff's tip (`tip`, `Actor.muzzle_position`); a change sends `staff_shown` (living
## staffs H4: Feel's poof). Every staff has its own mana pool (owner, 2026-11-01), sized by the
## staff (`StaffBase.max_mana`, `mana_regen`) and full when the actor is set up: `mana_of(at)`,
## `max_mana_of(at)`. Every step each pool gets mana back (its staff's regen a second, and what
## siphon on that staff's shots refunds, up to its staff's maximum), it tells the systems where the actor is and aims when it moved, turned or showed
## another staff (the projectile manager's anchor for its orbits at the body, Spells' aim from the
## staff tip for its beams; sent again before each cast), and casts the staffs
## the intent asks for: a staff pressed this step, or held while it holds no sustained (`hold`)
## card on (then only a new press casts, which switches it off). `cast(at)` casts from the staff
## tip (`Actor.muzzle_position`, clipped to walls from the feet) along the actor's aim with that
## staff's free mana (`free_mana(at)`: its pool minus what its sustained cards hold) and pays what
## Spells took from that pool, then sends `actor_cast` (any actor's cast, for visual reactions).
##
## For an AI: `cast_ready(within)` says the next cast can leave within that many seconds with the
## mana there (so a telegraph always comes true), `next_cast_mana`, `next_cast_reach` and
## `next_cast_radius` size its telegraph. For a seat: `cast_done` and `staff_built` are what the
## player's controller turns into the HUD's events; `cards_of`, `plan_of`, `last_form`.
##
## Compiled staffs are shared by every caster: one cache keyed by the Spells, the staff and the
## cards, so a crowd of one enemy type compiles its staff once, and a wizard who builds a row
## back gets the same compiled staff.
##
## The caster number (`number`) is the actor's id (`Actor.open_caster_number` opens its caster
## in Spells when the actor enters the tree, and closes it when it leaves; actors G3b).
##
## Nothing here allocates in `step`.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

## The most staffs an actor has (one per button).
const MAX_STAFFS: int = SpellLimits.STAFFS
## Compiled staffs kept before the cache starts over (a builder makes a new row on every edit).
const CACHE_SIZE: int = 256

## A staff was cast (`cast`): from `origin` along `direction` (`last_form(at)` names the carrier).
## Sent before `actor_cast`.
signal cast_done(at: int, origin: Vector2, direction: Vector2)
## Staff `at` was built (`set_staff`): `cards_of(at)` and `plan_of(at)` say what it is now.
signal staff_built(at: int)

## How many staffs (1-4): a wizard has four, an enemy one.
@export_range(1, 4) var staff_count: int = 1
## The staff of a button with none in `staffs` (its slots, delay, recharge and mana pool);
## without one a staff has 4 slots, casts with no delay of its own and has StaffBase's default
## pool.
@export var staff: StaffBase = null
## The staff of each button (a player's four heads); shorter or null entries fall back to `staff`.
@export var staffs: Array[StaffBase] = []
## The card ids built into each staff when the actor is ready (a list per staff).
@export var start_cards: Array = []
## The staff on show: the one pressed or held last (0 at the start).
var current: int = 0
## The number the actor casts under in Spells (and is the anchor of in the projectile manager),
## -1 while it has none (out of the tree, or no actor id): the actor's `id` (actors G3b).
var number: int = -1

## Every compiled staff, by "spells id|staff id|cards".
static var _cache: Dictionary = {}

## The card ids of each staff, `slots` long (`&""` is an empty slot), and whether it can cast.
var _cards: Array = []
## The mana each staff holds now, by button (`mana_of`).
var _mana: PackedFloat32Array = PackedFloat32Array()
var _has_build: PackedByteArray = PackedByteArray()
## True once the start cards were built (the first attach).
var _built: bool = false
## The plain staff used when `staff` is null.
var _plain: StaffBase = null
## What `_push_place` sent last: the feet, aim and staff on show it was worked out from (INF feet:
## send at the next step), the anchor and the staff tip it sent.
var _placed_feet: Vector2 = Vector2.INF
var _placed_aim: Vector2 = Vector2.INF
var _placed_current: int = -1
var _placed_anchor: Vector2 = Vector2.INF
var _placed_tip: Vector2 = Vector2.INF
## The hand when the place was last sent (what a swing turns round).
var _placed_pivot: Vector2 = Vector2.INF


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	staff_count = clampi(staff_count, 1, MAX_STAFFS)
	_mana.resize(MAX_STAFFS)
	for at in MAX_STAFFS:
		_mana[at] = max_mana_of(at)
	_cards.resize(MAX_STAFFS)
	for at in MAX_STAFFS:
		var empty: Array[StringName] = []
		_cards[at] = empty
	_has_build.resize(MAX_STAFFS)


func attach() -> void:
	_open_number()
	if actor.events != null and not actor.events.mana_refund_requested.is_connected(_on_mana_refund):
		actor.events.mana_refund_requested.connect(_on_mana_refund)
	if number < 0:
		return
	own_hurtbox()
	if not _built:
		_built = true
		for at in staff_count:
			var cards: Array[StringName] = []
			if at < start_cards.size() and start_cards[at] is Array:
				for id: Variant in start_cards[at]:
					cards.append(StringName(str(id)))
			set_staff(at, cards)
	else:
		# Back in the tree with a fresh number: the staffs go in again.
		for at in staff_count:
			_install(at)
	_push_place()


func detach() -> void:
	if actor.events != null and is_instance_valid(actor.events) and actor.events.mana_refund_requested.is_connected(_on_mana_refund):
		actor.events.mana_refund_requested.disconnect(_on_mana_refund)
	_close_number()


## Mana back, the anchor and the aim to the systems, then the casts the intent asks for.
func step(delta: float) -> void:
	if number < 0:
		return
	if actor.is_down():
		# A downed actor holds no orbit and no beam, and gets no mana back.
		if actor.projectiles != null:
			actor.projectiles.clear_anchor(number)
		if actor.spells != null:
			actor.spells.clear_aim(number)
		_placed_feet = Vector2.INF
		return
	for at in staff_count:
		var base: StaffBase = staff_of(at)
		_mana[at] = minf(_mana[at] + base.mana_regen * delta, base.max_mana)
	if actor.global_position != _placed_feet or actor.aim != _placed_aim or current != _placed_current:
		# Only when the body moved, turned or showed another staff: the systems still hold what
		# was sent (performance pass, 2026-10-28).
		_push_place()
	if actor.spells == null:
		return
	var intent: ActorIntent = actor.intent
	if (intent.pressed_bits | intent.held_bits) == 0:
		# No button: nothing to cast or show (most steps of most actors).
		return
	for at in staff_count:
		if _has_build[at] == 0:
			# An empty staff casts nothing, but pressing it still puts it on show.
			if intent.is_pressed(at):
				_show(at)
			continue
		# A held button casts whenever the staff is ready, except while it holds a sustained card:
		# then only a new press casts, which switches it off.
		var pressed: bool = intent.is_pressed(at)
		var held: bool = intent.is_held(at) and not actor.spells.is_holding(number, at)
		if pressed or held:
			_show(at)
			cast(at)


## The projectile manager's anchor at the body and Spells' aim from the staff tip.
## The step sends them only when the body moved, turned or showed another staff since the last
## time (every actor does this every step; performance pass, 2026-10-28).
func _push_place() -> void:
	var feet: Vector2 = actor.global_position
	var anchor: Vector2 = feet + actor.body_offset
	var tip: Vector2 = actor.muzzle_position()
	if actor.projectiles != null:
		# The anchor and the staff tip clipped to walls (`_origin`), in one call.
		tip = actor.projectiles.place_caster(number, anchor, feet, tip)
	if actor.spells != null:
		actor.spells.set_aim(number, tip, actor.aim, actor.aim_pivot())
	_placed_feet = feet
	_placed_aim = actor.aim
	_placed_current = current
	_placed_anchor = anchor
	_placed_tip = tip
	_placed_pivot = actor.aim_pivot()


## Send what `_push_place` sent last again, before a cast: a new run may have cleared the systems
## since, while the body stood still.
func _push_place_again() -> void:
	if not _placed_feet.is_finite():
		return
	if actor.projectiles != null:
		actor.projectiles.set_anchor(number, _placed_anchor)
	if actor.spells != null:
		actor.spells.set_aim(number, _placed_tip, _placed_aim, _placed_pivot)


## Where a cast leaves: the staff tip, or where a wall cuts the staff (the manager takes no pool
## slot for a shot that starts inside a wall).
func _origin() -> Vector2:
	var tip: Vector2 = actor.muzzle_position()
	if actor.projectiles != null:
		return actor.projectiles.clip_to_walls(actor.global_position, tip)
	return tip


## Cast staff `at` now. Returns true if it cast (or switched its sustained cards off). Does
## nothing while the actor is down or for a staff with no build.
func cast(at: int) -> bool:
	if actor.is_down() or not has_staff(at):
		return false
	_push_place_again()
	var origin: Vector2 = _origin()
	var direction: Vector2 = actor.aim
	# The way the body walks, for a dash it casts (staffs A6a).
	var spent: float = actor.spells.cast_staff(number, at, origin, direction, free_mana(at), actor.intent.move)
	if spent == SpellsScript.REFUSED:
		return false
	_mana[at] = maxf(_mana[at] - spent, 0.0)
	cast_done.emit(at, origin, direction)
	if actor.events != null:
		actor.events.actor_cast.emit(actor.id, actor)
	return true


## The mana staff `at` holds now (0 for a staff that does not exist).
func mana_of(at: int) -> float:
	return _mana[at] if at >= 0 and at < _mana.size() else 0.0


## The most mana staff `at` holds: its staff's pool.
func max_mana_of(at: int) -> float:
	return staff_of(at).max_mana


## Set the mana staff `at` holds, kept within 0 and its maximum (tests, a sandbox refill).
func set_mana(at: int, value: float) -> void:
	if at >= 0 and at < _mana.size():
		_mana[at] = clampf(value, 0.0, max_mana_of(at))


## Mana a cast of staff `at` may use now: its pool, minus what its sustained cards hold.
func free_mana(at: int) -> float:
	var reserved: float = actor.spells.reserved_mana(number, at) if actor.spells != null and number >= 0 else 0.0
	return maxf(mana_of(at) - reserved, 0.0)


## True when staff `at` has a build that can cast.
func has_staff(at: int) -> bool:
	return actor.spells != null and number >= 0 and at >= 0 and at < staff_count and _has_build[at] != 0


## True while staff `at` holds a sustained card on.
func is_holding(at: int) -> bool:
	return has_staff(at) and actor.spells.is_holding(number, at)


## The card ids of staff `at` as a copy, one per slot (`&""` for an empty slot).
func cards_of(at: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if at >= 0 and at < staff_count:
		out.assign(_cards[at])
	return out


## How many slots staff `at` has.
func slot_count(at: int = 0) -> int:
	return staff_of(at).slots


## The staff of button `at`: its own in `staffs`, else `staff`, else a plain one of 4 slots.
func staff_of(at: int) -> StaffBase:
	if at >= 0 and at < staffs.size() and staffs[at] != null:
		return staffs[at]
	return _staff_or_plain()


## Pixels from the hand to the tip of the staff on show (0: the actor's own reach).
func tip() -> float:
	return staff_of(current).tip


## Put staff `at` on show (`current`); another than the one shown sends `staff_shown` (the poof).
func _show(at: int) -> void:
	if at == current:
		return
	current = at
	if actor.events != null:
		actor.events.staff_shown.emit(actor.id, actor, at)


## The plain view of staff `at` for a builder (`Spells.staff_view`); empty without Spells.
func plan_of(at: int) -> Dictionary:
	if actor.spells == null or at < 0 or at >= staff_count:
		return {}
	return actor.spells.staff_view(cards_of(at), staff_of(at))


## The form of the carrier staff `at` cast last (`Spells.last_form`), or &"".
func last_form(at: int) -> StringName:
	return actor.spells.last_form(number, at) if has_staff(at) else &""


## Build `cards` (card ids by slot) into staff `at`: cut or padded to the staff's slots, compiled
## (once per staff and cards, for every caster) and installed in Spells; `staff_built` follows.
## Nothing is refused for what the cards do; an empty staff casts nothing. Returns false only for
## a staff that does not exist.
func set_staff(at: int, cards: Array[StringName]) -> bool:
	if at < 0 or at >= staff_count:
		return false
	var row: Array[StringName] = []
	for slot in slot_count(at):
		row.append(cards[slot] if slot < cards.size() else &"")
	_cards[at] = row
	_install(at)
	staff_built.emit(at)
	return true


## The next cast's mana (`Spells.next_cast_mana`): REFUSED (-1) with no build.
func next_cast_mana(at: int = 0) -> float:
	return actor.spells.next_cast_mana(number, at) if has_staff(at) else SpellsScript.REFUSED


## How far the next cast reaches along the aim (0 for one that is not aimed, or no build).
func next_cast_reach(at: int = 0) -> float:
	return actor.spells.next_cast_reach(number, at) if has_staff(at) else 0.0


## What the next cast's first carrier is (`Spells.next_cast_traits`: CarrierTraits flags), 0 with
## no build. `BLOCKS` says it puts up a wall: an AI keeps such a staff for cover.
func next_cast_traits(at: int) -> int:
	return actor.spells.next_cast_traits(number, at) if has_staff(at) else 0


## The hit radius of the next cast's first carrier (0 for none).
func next_cast_radius(at: int = 0) -> float:
	return actor.spells.next_cast_radius(number, at) if has_staff(at) else 0.0


## True when the next cast of staff `at` can leave within `within` seconds: its delay is no
## longer than that and the mana is there.
func cast_ready(within: float, at: int = 0) -> bool:
	# An AI asks every step while its target is in reach: one call to Spells.
	return has_staff(at) and actor.spells.cast_ready(number, at, within, mana_of(at))


## Name the actor's hurt circle as its caster number's (its actor id), so its own spells pass
## it unless they self-hit, as a wizard's always did; every other actor's spells hit it. The
## Hurtbox calls it too.
func own_hurtbox() -> void:
	if number >= 0 and actor.projectiles != null:
		actor.projectiles.set_target_owner(actor, number)


## Compile (or find) and install staff `at`.
func _install(at: int) -> void:
	if actor.spells == null or number < 0:
		_has_build[at] = 0
		return
	var compiled: CompiledStaff = _compiled(_cards[at], staff_of(at))
	_has_build[at] = 1 if actor.spells.install_staff(number, at, compiled) != 0 else 0


func _compiled(cards: Array[StringName], base: StaffBase) -> CompiledStaff:
	var key: String = "%d|%d|%s" % [actor.spells.get_instance_id(), base.get_instance_id(), ",".join(PackedStringArray(cards))]
	var found: CompiledStaff = _cache.get(key) as CompiledStaff
	if found != null:
		return found
	if _cache.size() >= CACHE_SIZE:
		_cache.clear()
	found = actor.spells.compile_staff(cards, base)
	_cache[key] = found
	return found


## The staff the cards sit in: `staff`, or a plain one of 4 slots when none is set.
func _staff_or_plain() -> StaffBase:
	if staff != null:
		return staff
	if _plain == null:
		_plain = StaffBase.new()
		_plain.slots = SpellLimits.STAFFS
		_plain.cast_delay = 0.0
		_plain.recharge = 0.0
	return _plain


## Take the caster number from the actor (`Actor.open_caster_number`); -1 when it has none.
func _open_number() -> void:
	if number < 0:
		number = actor.open_caster_number()


func _close_number() -> void:
	if number < 0:
		return
	if actor.projectiles != null and is_instance_valid(actor.projectiles):
		actor.projectiles.clear_anchor(number)
	if actor.spells != null and is_instance_valid(actor.spells):
		actor.spells.clear_aim(number)
	_placed_feet = Vector2.INF
	actor.close_caster_number()
	number = -1
	_has_build.fill(0)


## Siphon gives mana back as an event for its caster number and the staff that cast the shot,
## whoever drives it; never above that staff's maximum.
func _on_mana_refund(caster: int, at: int, amount: float) -> void:
	if number < 0 or caster != number or actor.is_down() or not is_finite(amount) or amount <= 0.0:
		return
	if at >= 0 and at < staff_count:
		_mana[at] = minf(_mana[at] + amount, max_mana_of(at))

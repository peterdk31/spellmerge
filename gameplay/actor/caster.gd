class_name Caster
extends ActorComponent
## The caster (actors G4, docs/milestones/M2-actors.md, "The components"): an actor's staffs and
## mana. It holds 1-4 staffs (`staff_count`), each a `StaffBase` (`staffs`, one per button; a
## button without one is `staff`) and a row of card ids; `set_staff(at, cards)` builds one and
## installs it in `Spells` under the actor's caster number (`number`). `current` is the staff on
## show (living staffs H3): the one pressed or held last, set before it casts, so the cast leaves
## from that staff's tip (`tip`, `Actor.muzzle_position`); a change sends `staff_shown` (living
## staffs H4: Feel's poof). Every step it gets mana back (`regen` a second and what siphon refunds, up
## to `max_mana`), tells the systems where the actor is and aims (the projectile manager's anchor
## for its orbits at the body, Spells' aim from the staff tip for its beams), and casts the staffs
## the intent asks for: a staff pressed this step, or held while it holds no sustained (`hold`)
## card on (then only a new press casts, which switches it off). `cast(at)` casts from the staff
## tip (`Actor.muzzle_position`, clipped to walls from the feet) along the actor's aim with the
## free mana (`free_mana`: what it has minus what its sustained cards hold) and pays what Spells
## took, then sends `actor_cast` (any actor's cast, for Feel's squash).
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
## The staff of a button with none in `staffs` (its slots, delay and recharge); without one a
## staff has 4 slots and casts with no delay of its own.
@export var staff: StaffBase = null
## The staff of each button (a player's four heads); shorter or null entries fall back to `staff`.
@export var staffs: Array[StaffBase] = []
## The card ids built into each staff when the actor is ready (a list per staff).
@export var start_cards: Array = []
## The mana pool, full at the start, and the mana back a second.
@export var max_mana: float = 100.0
@export var regen: float = 10.0

var mana: float = 100.0
## The staff on show: the one pressed or held last (0 at the start).
var current: int = 0
## The number the actor casts under in Spells (and is the anchor of in the projectile manager),
## -1 while it has none (out of the tree, or no actor id): the actor's `id` (actors G3b).
var number: int = -1

## Every compiled staff, by "spells id|staff id|cards".
static var _cache: Dictionary = {}

## The card ids of each staff, `slots` long (`&""` is an empty slot), and whether it can cast.
var _cards: Array = []
var _has_build: PackedByteArray = PackedByteArray()
## True once the start cards were built (the first attach).
var _built: bool = false
## The plain staff used when `staff` is null.
var _plain: StaffBase = null


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	staff_count = clampi(staff_count, 1, MAX_STAFFS)
	mana = max_mana
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
		return
	mana = minf(mana + regen * delta, max_mana)
	_push_place()
	if actor.spells == null:
		return
	for at in staff_count:
		if _has_build[at] == 0:
			# An empty staff casts nothing, but pressing it still puts it on show.
			if actor.intent.is_pressed(at):
				_show(at)
			continue
		# A held button casts whenever the staff is ready, except while it holds a sustained card:
		# then only a new press casts, which switches it off.
		var pressed: bool = actor.intent.is_pressed(at)
		var held: bool = actor.intent.is_held(at) and not actor.spells.is_holding(number, at)
		if pressed or held:
			_show(at)
			cast(at)


## The projectile manager's anchor at the body and Spells' aim from the staff tip.
func _push_place() -> void:
	if actor.projectiles != null:
		actor.projectiles.set_anchor(number, actor.global_position + actor.body_offset)
	if actor.spells != null:
		actor.spells.set_aim(number, _origin(), actor.aim)


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
	var origin: Vector2 = _origin()
	var direction: Vector2 = actor.aim
	var spent: float = actor.spells.cast_staff(number, at, origin, direction, free_mana())
	if spent == SpellsScript.REFUSED:
		return false
	mana = maxf(mana - spent, 0.0)
	cast_done.emit(at, origin, direction)
	if actor.events != null:
		actor.events.actor_cast.emit(actor.id, actor)
	return true


## Mana a cast may use now: what the actor has, minus what its sustained cards hold.
func free_mana() -> float:
	var reserved: float = actor.spells.reserved_mana(number) if actor.spells != null and number >= 0 else 0.0
	return maxf(mana - reserved, 0.0)


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


## The hit radius of the next cast's first carrier (0 for none).
func next_cast_radius(at: int = 0) -> float:
	return actor.spells.next_cast_radius(number, at) if has_staff(at) else 0.0


## True when the next cast of staff `at` can leave within `within` seconds: its delay is no
## longer than that and the mana is there.
func cast_ready(within: float, at: int = 0) -> bool:
	var cost: float = next_cast_mana(at)
	if cost < 0.0:
		return false
	return actor.spells.cooldown_left(number, at) <= within and free_mana() >= cost


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
	actor.close_caster_number()
	number = -1
	_has_build.fill(0)


## Siphon gives mana back as an event for its caster number, whoever drives it; never above
## `max_mana`.
func _on_mana_refund(caster: int, amount: float) -> void:
	if number < 0 or caster != number or actor.is_down() or not is_finite(amount) or amount <= 0.0:
		return
	mana = minf(mana + amount, max_mana)

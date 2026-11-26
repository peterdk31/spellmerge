class_name Caster
extends ActorComponent
## The caster (actors G4, docs/milestones/M2-actors.md, "The components"): an actor's staffs and
## mana. It has 1-4 buttons (`staff_count`, a wizard's hands), each a `StaffBase` (`staffs`, one per
## button; a button without one is `staff`) and a row of card ids, or none: an empty hand
## (`empty_hands`, items I2) holds no staff, no cards and no mana, casts nothing and is never put
## on show while another hand holds a staff (`holds`). `set_staff(at, cards)` builds one and
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
## Spells took from that pool, then sends `actor_cast` (any actor's cast, for visual reactions). A
## cast that winds up (docs/milestones/cast-timing.md) starts there and leaves later; its mana is
## paid then (`mana_spend_requested`).
##
## For an AI: `cast_ready(within)` says the next cast can leave within that many seconds with the
## mana there (so a telegraph always comes true), `next_cast_mana`, `next_cast_reach` and
## `next_cast_radius` size its telegraph. For a seat: `cast_done` and `staff_built` are what the
## player's controller turns into the HUD's events; `cards_of`, `plan_of`, `last_carrier_card`.
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

## A staff was cast (`cast`): from `origin` along `direction` (`last_carrier_card(at)` names the carrier).
## Sent before `actor_cast`.
signal cast_done(at: int, origin: Vector2, direction: Vector2)
## Staff `at` was built (`set_staff`): `cards_of(at)` and `plan_of(at)` say what it is now.
signal staff_built(at: int)

## How many staffs (1-4): a wizard has four, an enemy one.
@export_range(1, 4) var staff_count: int = 1
## The staff of a button with none in `staffs` (its slots, wind-up, cooldown and mana pool);
## without one a staff has 4 slots, adds no wind-up or cooldown of its own and has StaffBase's default
## pool.
@export var staff: StaffBase = null
## The staff of each button (a player's four heads); shorter or null entries fall back to `staff`.
@export var staffs: Array[StaffBase] = []
## The card ids built into each staff when the actor is ready (a list per staff).
@export var start_cards: Array = []
## Slots its first staff has past its own (connected biomes CB11, decision 24: an elite's extra card,
## the first of its first staff's start cards; `hold_staffs`). 0 for every other body.
var extra_slots: int = 0
## The buttons that hold no staff (a bit each, 1 << button): an empty hand (items I2). Set before
## the actor is ready (`PlayerController.seat_wizard`). An actor with an `Inventory` (items I3) is
## made with its staffs here, which the inventory then owns: it changes a hand's cards with
## `set_staff`, and nothing else does.
var empty_hands: int = 0
## The staff on show: the one pressed or held last (0 at the start).
var current: int = 0
## The number the actor casts under in Spells (and is the anchor of in the projectile manager),
## -1 while it has none (out of the tree, or no actor id): the actor's `id` (actors G3b).
var number: int = -1

## Not state: the compiled staffs' cache (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_cache", &"_trials", &"_held_scratch"]

## Every compiled staff, by "spells id|staff id|cards".
static var _cache: Dictionary = {}
## The builds an AI only tried (`sense_of_build`, items I9), kept apart so trying never starts the
## staffs' own cache over; by the same key, CACHE_SIZE at most.
static var _trials: Dictionary = {}
## One float32, to round a value as a pool holds it (`_as_held`).
static var _held_scratch: PackedFloat32Array = PackedFloat32Array([0.0])

## The card ids of each staff, `slots` long (`&""` is an empty slot), and whether it can cast.
var _cards: Array = []
## The mana each staff holds now, by button (`mana_of`).
var _mana: PackedFloat32Array = PackedFloat32Array()
var _has_build: PackedByteArray = PackedByteArray()
## The staffs whose last cast was the body's own (`cast`'s `own`), by bit: their wind-ups outlast a
## change of driver.
var _own_winds: int = 0
## True once the start cards were built (the first attach).
var _built: bool = false
## True once a staff or its cards changed after the start cards were built (`set_staff`,
## `replace_staffs`): the caster is no longer as its scene and data made it (`at_rest`, props W2).
var _edited: bool = false
## The plain staff used when `staff` is null.
var _plain: StaffBase = null
## The sigils each hand's staff holds (staff-language L4, `set_sigils`): by hand, their ids, what each
## waits for (`SigilBase.when`) and its amount, in the order put on. A staff with any casts by itself
## while one holds (`_auto_cast`). State: a snapshot keeps them.
var _sigil_ids: Array = []
var _sigil_whens: Array = []
var _sigil_amounts: Array = []
## The sigils each staff of an enemy's or a prop's data names (`StaffCards.sigils`, by button), put
## on its hands as the actor enters play.
var start_sigils: Array = []
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
	_sigil_ids.resize(MAX_STAFFS)
	_sigil_whens.resize(MAX_STAFFS)
	_sigil_amounts.resize(MAX_STAFFS)
	for at in MAX_STAFFS:
		var sigils: Array[SigilBase] = []
		if at < start_sigils.size() and start_sigils[at] is Array:
			sigils.assign(start_sigils[at])
		set_sigils(at, sigils)


func attach() -> void:
	_open_number()
	if actor.events != null and not actor.events.mana_refund_requested.is_connected(_on_mana_refund):
		actor.events.mana_refund_requested.connect(_on_mana_refund)
	if actor.events != null and not actor.events.mana_spend_requested.is_connected(_on_mana_spend):
		actor.events.mana_spend_requested.connect(_on_mana_spend)
	if number < 0:
		return
	own_hurtbox()
	if not _built:
		_built = true
		if not holds(current):
			current = first_held()
		for at in staff_count:
			if not holds(at):
				# An empty hand is announced too: its plan is empty (`plan_of`).
				staff_built.emit(at)
				continue
			var cards: Array[StringName] = []
			if at < start_cards.size() and start_cards[at] is Array:
				for id: Variant in start_cards[at]:
					cards.append(StringName(str(id)))
			set_staff(at, cards)
			# A staff it enters play with may wait before its first cast (boss plan OB14).
			var held: StaffBase = staff_of(at)
			if held != null and held.first_wait > 0.0 and actor.spells != null:
				actor.spells.hold_staff(number, at, held.first_wait)
		# The start cards are how it was made, not an edit.
		_edited = false
	else:
		# Back in the tree with a fresh number: the staffs go in again.
		for at in staff_count:
			_install(at)
	_push_place()


func detach() -> void:
	if actor.events != null and is_instance_valid(actor.events) and actor.events.mana_refund_requested.is_connected(_on_mana_refund):
		actor.events.mana_refund_requested.disconnect(_on_mana_refund)
	if actor.events != null and is_instance_valid(actor.events) and actor.events.mana_spend_requested.is_connected(_on_mana_spend):
		actor.events.mana_spend_requested.disconnect(_on_mana_spend)
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
		if not holds(at):
			continue
		var base: StaffBase = staff_of(at)
		_mana[at] = minf(_mana[at] + base.mana_regen * delta, base.max_mana)
	if actor.global_position != _placed_feet or actor.aim != _placed_aim or current != _placed_current:
		# Only when the body moved, turned or showed another staff: the systems still hold what
		# was sent (performance pass, 2026-10-28).
		_push_place()
	if actor.spells == null:
		return
	var intent: ActorIntent = actor.intent
	_auto_cast(intent)
	if (intent.pressed_bits | intent.held_bits) == 0:
		# No button: nothing to cast or show (most steps of most actors).
		return
	for at in staff_count:
		if _has_build[at] == 0:
			# An empty staff casts nothing, but pressing it still puts it on show; an empty hand
			# has nothing to show.
			if intent.is_pressed(at) and holds(at):
				_show(at)
			continue
		# A held button casts whenever the staff is ready, except while it holds a sustained card:
		# then only a new press casts, which switches it off.
		var pressed: bool = intent.is_pressed(at)
		var held: bool = intent.is_held(at) and not actor.spells.is_holding(number, at)
		if pressed or held:
			_show(at)
			cast(at, pressed)


# --- Sigils (staff-language L4) ----------------------------------------------------------

## Hand `at`'s staff holds `sigils` (none: casts only when pressed). The Inventory tells it whenever a
## staff with sigils comes onto a hand or its sigils change; an enemy's come from its data.
func set_sigils(at: int, sigils: Array[SigilBase]) -> void:
	if at < 0 or at >= MAX_STAFFS or _sigil_ids.size() <= at:
		return
	var ids: Array[StringName] = []
	var whens: Array[StringName] = []
	var amounts := PackedFloat32Array()
	for sigil: SigilBase in sigils:
		if sigil == null or ids.has(sigil.id) or ids.size() >= SigilBase.MOST_A_STAFF:
			continue
		ids.append(sigil.id)
		whens.append(sigil.when)
		amounts.append(sigil.amount)
	_sigil_ids[at] = ids
	_sigil_whens[at] = whens
	_sigil_amounts[at] = amounts


## The ids of the sigils hand `at`'s staff holds (none for a hand past its staffs).
func sigils_of(at: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if at >= 0 and at < _sigil_ids.size() and _sigil_ids[at] is Array:
		out.assign(_sigil_ids[at])
	return out


## True when one of hand `at`'s sigils holds now: the one rule the auto cast and the HUD's glow read.
## `hurt`: the body's health below the amount's share of its most; `close`: a foe's hit shape within
## the amount's pixels of its body (`ProjectileManager.has_foe_near`, a pure read). Read from the
## simulation only (core/sim/README.md).
func sigil_holds(at: int) -> bool:
	if at < 0 or at >= _sigil_whens.size() or not (_sigil_whens[at] is Array):
		return false
	var whens: Array = _sigil_whens[at]
	var amounts: PackedFloat32Array = _sigil_amounts[at]
	for i in whens.size():
		match whens[i]:
			&"hurt":
				if actor.health != null and actor.health.max_health > 0.0 and actor.health.health < amounts[i] * actor.health.max_health:
					return true
			&"close":
				if actor.projectiles != null and actor.actors != null and actor.projectiles.has_foe_near(actor.global_position + actor.body_offset, amounts[i], SpellsScript.HITS, actor.actors.team_of(actor.id)):
					return true
	return false


## Each step: every staff on a hand with a sigil that holds, which its driver neither presses nor
## holds, is cast as a held button's repeat (no new press, so no `on recast`), along the body's aim, at
## its own cooldown and mana: only when Spells says it is ready (`cast_ready`), never while its
## sustained cards are on (that cast would switch them off). Its wind-up is a cast's as any (an
## enemy's telegraph).
func _auto_cast(intent: ActorIntent) -> void:
	for at in staff_count:
		if _has_build[at] == 0 or (_sigil_whens[at] as Array).is_empty():
			continue
		if intent.is_pressed(at) or intent.is_held(at) or actor.spells.is_holding(number, at):
			continue
		if not actor.spells.cast_ready(number, at, 0.0, free_mana(at)) or not sigil_holds(at):
			continue
		cast(at, false)


## As its scene and data made it (props W2, `ActorComponent.at_rest`): its start cards unchanged
## and every pool full. The staff on show is in the actor's `rest_leaf`.
func at_rest() -> bool:
	if _edited or _own_winds != 0:
		return false
	for at in staff_count:
		if _mana[at] != _as_held(max_mana_of(at)):
			return false
	return true


## `value` as a pool holds it (a float32: `_mana`), so a pool filled to a most it cannot hold
## exactly still counts as full.
static func _as_held(value: float) -> float:
	_held_scratch[0] = value
	return _held_scratch[0]


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
		return actor.projectiles.grid().clip_to_walls(actor.global_position, tip)
	return tip


## Cast staff `at` now. Returns true if it cast (or switched its sustained cards off). Does
## nothing while the actor is down or for a staff with no build. `pressed`: a new press, not a held
## button's repeat, which also sets off the staff's live `on recast` carriers, busy or not
## (`Spells.press_staff`). `own`: the body's own cast, no driver's (a prop's trigger, props W6): its
## wind-up goes on when the driver changes (`cancel_winds`).
func cast(at: int, pressed: bool = true, own: bool = false) -> bool:
	if actor.is_down() or not has_staff(at):
		return false
	if own:
		_own_winds |= 1 << at
	else:
		_own_winds &= ~(1 << at)
	_push_place_again()
	var origin: Vector2 = _origin()
	var direction: Vector2 = actor.aim
	# The way the body walks, for a dash it casts (staffs A6a).
	var mana: float = free_mana(at)
	var walk: Vector2 = actor.intent.move
	var spent: float = actor.spells.press_staff(number, at, origin, direction, mana, walk) if pressed else actor.spells.cast_staff(number, at, origin, direction, mana, walk)
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


## The most mana staff `at` holds: its staff's pool (0 for an empty hand).
func max_mana_of(at: int) -> float:
	return staff_of(at).max_mana if holds(at) else 0.0


## Set the mana staff `at` holds, kept within 0 and its maximum (a rejoin's kept mana,
## `Inventory.set_staff_mana`; tests).
func set_mana(at: int, value: float) -> void:
	if at >= 0 and at < _mana.size():
		_mana[at] = clampf(value, 0.0, max_mana_of(at))


## Mana a cast of staff `at` may use now: its pool, minus what its sustained cards hold.
func free_mana(at: int) -> float:
	var reserved: float = actor.spells.reserved_mana(number, at) if actor.spells != null and number >= 0 else 0.0
	return maxf(mana_of(at) - reserved, 0.0)


## True when button `at` exists and holds a staff (not an empty hand), whatever its cards.
func holds(at: int) -> bool:
	return at >= 0 and at < staff_count and empty_hands & (1 << at) == 0


## The first button that holds a staff, or 0 when every hand is empty.
func first_held() -> int:
	for at in staff_count:
		if holds(at):
			return at
	return 0


## True when staff `at` has a build that can cast.
func has_staff(at: int) -> bool:
	return actor.spells != null and number >= 0 and at >= 0 and at < staff_count and _has_build[at] != 0


## True while staff `at` winds up a cast (pressed, not yet left; docs/milestones/cast-timing.md).
func is_winding(at: int) -> bool:
	return has_staff(at) and actor.spells.is_winding(number, at)


## Seconds the cast staff `at` winds up has left before it leaves (stretched by a chill, held by a
## freeze: `hold_winds`), 0 when none winds up: what an AI's aim lock is measured against (boss plan
## OB14).
func wind_left(at: int) -> float:
	return actor.spells.cooldown_left(number, at) if is_winding(at) else 0.0


## Every cast its driver wound up leaves no more, for free (its driver changed: `Actor.drive`); the
## body's own (`cast`'s `own`: a lit barrel's fuse) go on.
func cancel_winds() -> void:
	if actor.spells == null or number < 0:
		return
	if _own_winds == 0:
		actor.spells.cancel_winds(number)
		return
	for at in staff_count:
		if _own_winds & (1 << at) == 0:
			actor.spells.cancel_wind(number, at)


## The cast staff `at` winds up leaves no more, for free (a prop left the state that cast it).
func cancel_wind(at: int) -> void:
	if actor.spells != null and number >= 0:
		actor.spells.cancel_wind(number, at)


## True while staff `at` holds a sustained card on.
func is_holding(at: int) -> bool:
	return has_staff(at) and actor.spells.is_holding(number, at)


## The card ids of staff `at` as a copy, one per slot (`&""` for an empty slot).
func cards_of(at: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if holds(at):
		out.assign(_cards[at])
	return out


## How many slots staff `at` has (0 for an empty hand).
func slot_count(at: int = 0) -> int:
	return staff_of(at).slots + (extra_slots if at == 0 else 0) if holds(at) else 0


## The staff of button `at`: its own in `staffs`, else `staff`, else a plain one of 4 slots.
func staff_of(at: int) -> StaffBase:
	if at >= 0 and at < staffs.size() and staffs[at] != null:
		return staffs[at]
	return _staff_or_plain()


## Pixels from the hand to the tip of the staff on show (0: the actor's own reach).
func tip() -> float:
	return staff_of(current).tip


## Pixels the staff on show runs on behind the hand (`StaffBase.butt`).
func butt() -> float:
	return staff_of(current).butt


## Put staff `at` on show (`current`); another than the one shown sends `staff_shown` (the poof).
func _show(at: int) -> void:
	if at == current:
		return
	current = at
	if actor.events != null:
		actor.events.staff_shown.emit(actor.id, actor, at)


## The plain view of staff `at` for a builder (`Spells.staff_view`); empty without Spells and for
## an empty hand.
func plan_of(at: int) -> Dictionary:
	if actor.spells == null or not holds(at):
		return {}
	return actor.spells.staff_view(cards_of(at), staff_of(at))


## The carrier card of the carrier staff `at` cast last (`Spells.last_carrier_card`), or &"".
func last_carrier_card(at: int) -> StringName:
	return actor.spells.last_carrier_card(number, at) if has_staff(at) else &""


## Hold the staffs of `entries` (an enemy's or a prop's data: `StaffCards`, at most 4) from the start,
## one per button, their cards built when the actor enters play. Before the actor is ready.
func hold_staffs(entries: Array[StaffCards], extra_card: StringName = &"") -> void:
	var held: Array[StaffBase] = []
	var cards: Array = []
	var sigils: Array = []
	for entry: StaffCards in entries.slice(0, MAX_STAFFS):
		held.append(entry.staff if entry != null else null)
		cards.append(entry.cards.duplicate() if entry != null else [])
		sigils.append(entry.sigils.duplicate() if entry != null else [])
	if held.is_empty():
		return
	start_sigils = sigils
	extra_slots = 0
	if extra_card != &"" and held[0] != null:
		# An elite's card (connected biomes CB11): one slot more on its first staff, the card in front of
		# its own (a modifier reads the cards after it).
		var first: Array = [extra_card]
		first.append_array((cards[0] as Array).slice(0, held[0].slots))
		cards[0] = first
		extra_slots = 1
	staff_count = held.size()
	staffs = held
	staff = held[0]
	start_cards = cards


## Build `cards` (card ids by slot) into staff `at`: cut or padded to the staff's slots, compiled
## (once per staff and cards, for every caster) and installed in Spells; `staff_built` follows.
## Nothing is refused for what the cards do; an empty staff casts nothing. Returns false only for
## a staff that does not exist (no such button, or an empty hand).
func set_staff(at: int, cards: Array[StringName]) -> bool:
	if not holds(at):
		return false
	var row: Array[StringName] = []
	for slot in slot_count(at):
		row.append(cards[slot] if slot < cards.size() else &"")
	_cards[at] = row
	_edited = true
	_install(at)
	staff_built.emit(at)
	return true


## Put `base` on the empty hand `at` (items I6: a staff picked up), holding `cards` (card ids by
## slot) and `mana` (kept within its pool: a staff off a hand regains none, so it comes back as it
## left), built and installed as `set_staff` does; it waits its own cooldown before it casts (drawn:
## a staff moved between hands skips no delay, items I7); with every hand empty before, it goes on
## show.
## Returns false, and nothing changes, for a button it has not, a hand that holds a staff, or no
## staff.
func fill_hand(at: int, base: StaffBase, cards: Array[StringName], mana: float) -> bool:
	if base == null or at < 0 or at >= staff_count or holds(at):
		return false
	var none_held: bool = not holds(current)
	if staffs.size() < MAX_STAFFS:
		staffs.resize(MAX_STAFFS)
	staffs[at] = base
	empty_hands &= ~(1 << at)
	_mana[at] = clampf(mana, 0.0, base.max_mana)
	set_staff(at, cards)
	# Drawn: it waits its own cooldown before it casts (items I7), whatever the hand waited for.
	if actor.spells != null and number >= 0:
		actor.spells.hold_staff(number, at, base.cooldown)
	if none_held:
		_show(at)
	return true


## Empty hand `at` (items I7: a staff put in the bag or dropped): it holds no staff, no cards and no
## mana from now on, its wind-up and sustained cards end, and the staff on show moves to the first
## hand still held (with none, `current` stays where it was and nothing is put on show: the look
## shows the plain staff);
## `staff_built` follows. Returns the mana it held (what the staff keeps off a hand), or -1, and
## nothing changes, for a hand that holds no staff.
func empty_hand(at: int) -> float:
	if not holds(at):
		return -1.0
	var kept: float = _mana[at]
	cancel_wind(at)
	empty_hands |= 1 << at
	if at < staffs.size():
		staffs[at] = null
	_cards[at] = [] as Array[StringName]
	_mana[at] = 0.0
	set_sigils(at, [] as Array[SigilBase])
	_edited = true
	_install(at)
	if current == at and holds(first_held()):
		_show(first_held())
	staff_built.emit(at)
	return kept


## Hold `new_staffs` (1-4, one per button; a null one falls back to `staff`, as in `hold_staffs`)
## with `new_cards` (card ids by slot, per staff) instead of the staffs it held: a boss's phase
## (`Phases`). Every button it is given holds its staff (none is an empty hand). Each pool starts
## full and each staff ready, with no cooldown left (boss plan OB14: so a phase's Big Sweep is its
## first move); a button it no longer has is emptied (its sustained cards end). `staff_built`
## follows for each.
func replace_staffs(new_staffs: Array[StaffBase], new_cards: Array) -> void:
	if new_staffs.is_empty():
		return
	var before: int = staff_count
	_edited = true
	staffs = new_staffs.duplicate()
	staff = staffs[0]
	staff_count = clampi(staffs.size(), 1, MAX_STAFFS)
	# An elite's slot more was its own first staff's (connected biomes CB11): new staffs have none.
	extra_slots = 0
	empty_hands = 0
	for at in MAX_STAFFS:
		_mana[at] = max_mana_of(at)
	for at in maxi(before, staff_count):
		var cards: Array[StringName] = []
		if at < new_cards.size() and new_cards[at] is Array:
			for id: Variant in new_cards[at]:
				cards.append(StringName(str(id)))
		if at < staff_count:
			set_staff(at, cards)
			if actor.spells != null and number >= 0:
				actor.spells.ready_staff(number, at)
		else:
			_cards[at] = [] as Array[StringName]
			_install(at)
			staff_built.emit(at)


## The next cast's mana (`Spells.next_cast_mana`): the cast a press would fire with the staff's
## free mana (one it cannot pay is skipped); REFUSED (-1) with no build.
func next_cast_mana(at: int = 0) -> float:
	return actor.spells.next_cast_mana(number, at, free_mana(at)) if has_staff(at) else SpellsScript.REFUSED


## How far the next cast reaches along the aim (0 for one that is not aimed, or no build).
func next_cast_reach(at: int = 0) -> float:
	return actor.spells.next_cast_reach(number, at, free_mana(at)) if has_staff(at) else 0.0


## What the next cast of staff `at` does (`Spells.next_cast_sense`, a `CastSense`), or null with
## no build: what an AI reads to play whatever staffs the actor holds (docs/milestones/M2-enemy-ai.md).
func next_cast_sense(at: int = 0) -> CastSense:
	return actor.spells.next_cast_sense(number, at, free_mana(at)) if has_staff(at) else null


## What the staff `base` holding `cards` (ids by slot) would cast first, as a `CastSense` (a staff
## starts its cycle anew when it is built, so its next cast once built): an AI weighing a staff it
## might take or a card it might put in (items I9). Null for a build that casts nothing, no Spells,
## or, with `slot` >= 0, a card in that slot that does nothing (no cast of the cycle reads it, or
## every cast that does wastes it: `CompiledStaff.wasted`). Compiled once per staff and cards, shared
## by every caster: a build held is the staffs' own cache's, any other is kept apart (`_trials`), so
## trying never starts the staffs' cache over.
func sense_of_build(base: StaffBase, cards: Array[StringName], slot: int = -1) -> CastSense:
	if base == null or actor.spells == null:
		return null
	var compiled: CompiledStaff = _tried(cards, base)
	if compiled.is_empty():
		return null
	if slot >= 0 and (compiled.wasted.has(slot) or not _reads(compiled, slot)):
		return null
	var sense: CastSense = compiled.casts[0].sense
	return sense if sense != null and not sense.empty else null


## The hit radius of the next cast's first carrier (0 for none).
func next_cast_radius(at: int = 0) -> float:
	return actor.spells.next_cast_radius(number, at, free_mana(at)) if has_staff(at) else 0.0


## True when a cast of staff `at` can leave within `within` seconds (one it cannot pay is skipped,
## docs/milestones/cast-timing.md): its delay is no
## longer than that and the mana is there.
func cast_ready(within: float, at: int = 0) -> bool:
	# An AI asks every step while its target is in reach: one call to Spells.
	return has_staff(at) and actor.spells.cast_ready(number, at, within, mana_of(at))


## Name the actor's hurt circle as its caster number's (its actor id), so its own spells pass
## it unless they self-hit, as a wizard's always did; every other actor's spells hit it. The
## Hurtbox calls it too.
func own_hurtbox() -> void:
	if number >= 0 and actor.projectiles != null:
		actor.projectiles.set_target_owner(actor, actor.belongs_to if actor.belongs_to >= 0 else number)


## Compile (or find) and install staff `at`.
func _install(at: int) -> void:
	if actor.spells == null or number < 0:
		_has_build[at] = 0
		return
	var compiled: CompiledStaff = _compiled(_cards[at], staff_of(at), slot_count(at))
	_has_build[at] = 1 if actor.spells.install_staff(number, at, compiled) != 0 else 0


func _compiled(cards: Array[StringName], base: StaffBase, slots: int) -> CompiledStaff:
	var key: String = _key(cards, base, slots)
	var found: CompiledStaff = _cache.get(key) as CompiledStaff
	if found != null:
		return found
	if _cache.size() >= CACHE_SIZE:
		_cache.clear()
	found = actor.spells.compile_staff(cards, base, _spell_scale(), slots)
	_cache[key] = found
	return found


## The compiled staff of `cards` on `base` for a trial: the staffs' own cache's when it is there (a
## build held), else the trials' (made there, never in the staffs' own).
func _tried(cards: Array[StringName], base: StaffBase) -> CompiledStaff:
	# The first staff of an elite reads its slot more (connected biomes CB11).
	var slots: int = base.slots + (extra_slots if base == staff_of(0) else 0)
	var key: String = _key(cards, base, slots)
	var found: CompiledStaff = _cache.get(key) as CompiledStaff
	if found == null:
		found = _trials.get(key) as CompiledStaff
	if found != null:
		return found
	if _trials.size() >= CACHE_SIZE:
		_trials.clear()
	found = actor.spells.compile_staff(cards, base, _spell_scale(), slots)
	_trials[key] = found
	return found


## The caches' key of `cards` on `base` with `slots` slots (-1: the staff's own) at the body's spell
## scale: "spells id|staff id|slots|scale|cards".
func _key(cards: Array[StringName], base: StaffBase, slots: int = -1) -> String:
	return "%d|%d|%d|%s|%s" % [actor.spells.get_instance_id(), base.get_instance_id(), slots if slots >= 0 else base.slots, _spell_scale(), ",".join(PackedStringArray(cards))]


## The size its spells are built at (boss plan OB7): its body's `Stats.spell_scale`, 1 without.
func _spell_scale() -> float:
	return actor.stats.spell_scale if actor.stats != null else 1.0


## Build every staff it holds again with the cards it holds (its body's spell scale changed: a
## boss's phase with stats of its own, `Phases`); `staff_built` follows for each. A staff built
## again starts its cycle anew, as after an edit.
func rebuild() -> void:
	if number < 0:
		return
	for at in staff_count:
		if holds(at):
			_install(at)
			staff_built.emit(at)


## True when a cast of `compiled`'s cycle reads the card in `slot`.
static func _reads(compiled: CompiledStaff, slot: int) -> bool:
	for cast: CompiledCast in compiled.casts:
		if cast.slots.has(slot):
			return true
	return false


## The staff the cards sit in: `staff`, or a plain one of 4 slots when none is set.
func _staff_or_plain() -> StaffBase:
	if staff != null:
		return staff
	if _plain == null:
		_plain = StaffBase.new()
		_plain.slots = SpellLimits.STAFFS
		_plain.wind_up = 0.0
		_plain.cooldown = 0.0
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


## A cast that wound up left (`Spells`, docs/milestones/cast-timing.md): its mana is paid from the
## staff that cast it now, not at the press.
func _on_mana_spend(caster: int, at: int, amount: float) -> void:
	if number < 0 or caster != number or not is_finite(amount) or amount <= 0.0:
		return
	if at >= 0 and at < staff_count:
		_mana[at] = maxf(_mana[at] - amount, 0.0)

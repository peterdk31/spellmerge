class_name SpellCasts
extends Object
## A staff's cast (core/spells/spells.gd): `cast_staff`, `press_staff` and `recast_staff`, the
## wind-up and wind-down, the cooldown, the cast that comes next and what it would do
## (`next_cast_*`, `cast_ready`), and a caster opened, closed and its room left. Methods working on
## the runtime (`rt`), whose members hold all of it (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_fires", &"_job_generations", &"_job_lasting", &"_job_launches", &"_current", &"_installed", &"_cursor", &"_hold_tags", &"_last_carrier_card", &"_hold_mana", &"_profiles", &"_cooldown", &"_wind_due", &"_wind_walk", &"_wind_origin", &"_wind_dir", &"_lc_tag", &"_lc_at", &"_last_infused", &"_cast_count", &"_pour_until", &"_cast_turn", &"_walk_turn", &"_aim_origin", &"_aim_dir", &"_aim_seen", &"_aim_pivot", &"_ring", &"_open_ring", &"_open_builds"]

var rt: Runtime = null
var _job_fires: SpellFires = null
var _job_generations: SpellGenerations = null
var _job_lasting: SpellLasting = null
var _job_launches: SpellLaunches = null
var _current: PackedInt32Array
var _installed: Array[CompiledStaff]
var _cursor: PackedInt32Array
var _hold_tags: Array[PackedInt64Array]
var _last_carrier_card: Array[StringName]
var _hold_mana: PackedFloat32Array
var _profiles: Dictionary
var _cooldown: PackedFloat32Array
var _wind_due: PackedFloat64Array
var _wind_walk: PackedFloat32Array
var _wind_origin: PackedVector2Array
var _wind_dir: PackedVector2Array
var _lc_tag: PackedInt64Array
var _lc_at: PackedVector2Array
var _last_infused: Array[CompiledSpell]
var _cast_count: PackedInt32Array
var _pour_until: PackedFloat64Array
var _cast_turn: PackedFloat32Array
var _walk_turn: PackedFloat32Array
var _aim_origin: PackedVector2Array
var _aim_dir: PackedVector2Array
var _aim_seen: PackedByteArray
var _aim_pivot: PackedVector2Array
var _ring: PackedInt32Array
var _open_ring: PackedInt32Array
var _open_builds: PackedInt32Array


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## This actor's staff `slot` may cast again in no less than `seconds` (items I7: a staff put on a
## hand is drawn, and waits its own cooldown, so moving staffs between hands skips no delay).
func hold_staff(actor: int, slot: int, seconds: float) -> void:
	if not _in_range(actor, slot) or not is_finite(seconds) or seconds <= 0.0:
		return
	var index: int = actor * SpellLimits.STAFFS + slot
	_cooldown[index] = maxf(_cooldown[index], seconds)
	rt._cooldown_rows = maxi(rt._cooldown_rows, index + 1)


## This actor's staff `slot` may cast at once: no cooldown left (boss plan OB14: a boss's phase's
## staffs start ready). A cast it winds up is left to leave.
func ready_staff(actor: int, slot: int) -> void:
	if _in_range(actor, slot) and _wind_due[actor * SpellLimits.STAFFS + slot] == INF:
		_cooldown[actor * SpellLimits.STAFFS + slot] = 0.0


## Fires the next cast of this actor's staff from `origin` along `direction`. `mana` is what
## the caster has. Returns the mana spent (0.0 or more) when it fired, or `REFUSED` when it did
## not (nothing built, still in its delay, no cast left its mana pays, no direction, or every shot
## starting inside a wall); the caller then takes that much mana and reads no field. A cast the
## mana does not pay is skipped (docs/milestones/cast-timing.md, T3): the press fires the first
## one after it that it pays, up to the cycle's end; with none, the cycle ends (its cooldown runs,
## `cast_fizzled`) and nothing is paid. A refused cast changes nothing else, except that a cast
## with nothing in it (every card wasted) still moves the staff on, so it never sticks there.
##
## While the staff has sustained (`hold`) carriers on, a cast switches them all off instead,
## frees their reservation and returns 0.0. The caller decides which presses may do that (a
## held button should not switch on and off again and again).
##
## A held cast (this, not `press_staff`) of a carrier that pours on when held (`Carrier.pours_held`:
## a spray) that follows on from such a cast (by when the staff is ready again and `POUR_GRACE`)
## skips its staff's wind-up: an enemy telegraphs its spray
## once, then pours it while it holds the button (its cards' own wind-up stays; a player's staff has
## none). A held swing still winds up every time.
##
## `walk` is the way the caster's body walks (zero when it stands): a move it casts itself (a dash,
## a teleport: MOVES_CASTER) takes that way in place of `direction` (`CarrierMove`; staffs A6a, kept
## by the owner in R4 F1, teleport too since 2026-11-08).
func cast_staff(actor: int, staff: int, origin: Vector2, direction: Vector2, mana: float, walk: Vector2 = Vector2.ZERO) -> float:
	var _clock: float = rt._clock
	if rt.projectiles == null or not _in_range(actor, staff) or not origin.is_finite():
		return Runtime.REFUSED
	if not direction.is_finite() or direction.is_zero_approx():
		return Runtime.REFUSED
	var index: int = actor * SpellLimits.STAFFS + staff
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty() or _cooldown[index] > 0.0 or _wind_due[index] != INF:
		return Runtime.REFUSED
	if not _hold_tags[index].is_empty():
		# The switch-off press frees the staff at once (docs/milestones/cast-timing.md).
		_job_generations._release_hold(index)
		return 0.0
	# A cast the staff cannot pay is skipped (docs/milestones/cast-timing.md, T3): the press fires
	# the first one after it that it can, up to the cycle's end. With none, the cycle ends there:
	# its cooldown runs, nothing leaves and nothing is paid.
	var firing: int = _firing_cast(index, mana)
	if firing < 0:
		_cursor[index] = 0
		_cooldown[index] = compiled.staff.cooldown if compiled.staff != null else 0.0
		rt._cooldown_rows = maxi(rt._cooldown_rows, index + 1)
		if rt.events != null:
			rt.events.cast_fizzled.emit(actor, staff)
		return Runtime.REFUSED
	_cursor[index] = firing
	var cast: CompiledCast = compiled.casts[firing]
	var aim: Vector2 = direction.normalized()
	var turn: float = DMath.angle_to(aim, walk) if walk.is_finite() and not walk.is_zero_approx() else 0.0
	if cast.group.is_empty():
		_after_cast(index, compiled, cast)
		return Runtime.REFUSED
	var wind_up: float = cast.wind_up
	if _clock <= _pour_until[index] and compiled.staff != null and _job_launches._carrier_of(cast.group.spells[0]).pours_held():
		# Held on, a spray pours on: its staff's wind-up (an enemy's telegraph) was its first cast's,
		# and only a new press, or a cast that does not follow on, winds it again. Its cards' own
		# wind-up stays.
		wind_up = maxf(wind_up - compiled.staff.wind_up, 0.0)
	if wind_up > 0.0:
		# It winds up first (docs/milestones/cast-timing.md): the staff is busy, its pose winds,
		# and the cast leaves from where the caster holds the staff then (`_release_winds`), its
		# mana paid as it leaves (`mana_spend_requested`).
		_wind_due[index] = _clock + wind_up
		_wind_walk[index] = turn
		_wind_origin[index] = origin
		_wind_dir[index] = aim
		rt._winding += 1
		_cooldown[index] = wind_up
		rt._cooldown_rows = maxi(rt._cooldown_rows, index + 1)
		_wind_pose(actor, staff, cast, aim, wind_up)
		if rt.events != null:
			# Its look (an enemy's telegraph) is the first carrier card's `wind_cue` (T6b).
			var first_spell: CompiledSpell = cast.group.spells[0]
			# A staff may name its own (a barrel's fuse; props W6): it plays in place of the card's.
			var staff_cue: StringName = compiled.staff.wind_cue if compiled.staff != null else &""
			rt.events.cast_winding.emit(actor, staff, first_spell.carrier_card_id, origin, aim, wind_up, first_spell.tint, first_spell.look, SpellTag.make(actor, staff, first_spell.node, _current[index]), staff_cue)
		return 0.0
	_walk_turn[actor] = turn
	if not _leave(index, compiled, cast, origin, aim):
		return Runtime.REFUSED
	return cast.mana


## The cast `cast` of staff `index`'s cycle leaves from `origin` along `aim`: its group launched,
## the cycle moved on, `cast_left` sent first. False when no shot could start (every one inside a
## wall): then nothing changed but that it was told.
func _leave(index: int, compiled: CompiledStaff, cast: CompiledCast, origin: Vector2, aim: Vector2) -> bool:
	var _clock: float = rt._clock
	var actor: int = floori(float(index) / SpellLimits.STAFFS)
	var staff: int = index % SpellLimits.STAFFS
	if rt.events != null:
		# Before its shots start (props W6): a caster that becomes something else as its cast leaves
		# (a barrel's fuse burns out into rubble) is that when they meet it. Before the scatter is
		# seeded, so a cast a listener makes now does not take this one's.
		# A listener may make a cast of its own as this one leaves (a prop's `cast` trigger): the
		# outer cast is the leaving one again once it is told.
		var outer: CompiledCast = rt._leaving
		rt._leaving = cast
		rt.events.cast_left.emit(actor, staff)
		rt._leaving = outer
	_job_launches._scatter_from(hash(Vector3i(actor, staff, _cast_count[index])))
	_cast_turn[index] = fposmod(float(_cast_count[index]) * SpellLimits.RING_STEP, 1.0)
	# The live carriers listed before this cast's own join: only they hear it (L3).
	var heard: int = rt._lc_count
	if _job_launches._launch_group(cast.group, actor, staff, _current[index], origin, aim, null, true) == 0:
		return false
	# `on any cast` (L3): a cast that left (one whose every shot started in a wall is no cast) sets
	# off every live carrier of this caster with it, listed before it, so none hears the cast that made it.
	_any_cast(actor, heard)
	_cast_count[index] += 1
	_pour_until[index] = _clock + cast.delay + Runtime.POUR_GRACE if _job_launches._carrier_of(cast.group.spells[0]).pours_held() else -1.0
	_after_cast(index, compiled, cast)
	_last_infused[actor] = null
	for carrier in cast.group.spells:
		if not carrier.element_ids.is_empty():
			_last_infused[actor] = carrier
			break
	var first: CompiledSpell = cast.group.spells[0]
	_last_carrier_card[index] = first.carrier_card_id
	return true


## The staff's pose winds for a cast that winds up, from its press: the first carrier's keys, over
## `wind_up` (the cast's, less its staff's for a spray poured on), turning with the live aim (the aim follows the caster until the cast
## leaves); the carrier starts its strike when it leaves.
func _wind_pose(actor: int, staff: int, cast: CompiledCast, aim: Vector2, wind_up: float) -> void:
	var spell: CompiledSpell = cast.group.spells[0]
	if spell.staff_pose.is_empty() or actor < 0 or actor >= Runtime.ACTORS:
		return
	var tag: int = SpellTag.make(actor, staff, spell.node, _current[actor * SpellLimits.STAFFS + staff])
	rt._poses.start(actor, spell, tag, wind_up, StaffPoses.strike_of(spell, spell.lifetime), aim, _job_launches._carrier_of(spell).pose_side(actor, aim))


## The casts whose wind-up is over leave now, from where their caster holds the staff and along
## where it aims (`set_aim`; where it was pressed when that is not known), and their mana is paid.
## One that cannot leave (every shot inside a wall) frees its staff and costs nothing.
func _release_winds() -> void:
	var _clock: float = rt._clock
	for index in rt._cooldown_rows:
		if _wind_due[index] > _clock:
			continue
		_wind_due[index] = INF
		rt._winding -= 1
		_cooldown[index] = 0.0
		var actor: int = floori(float(index) / SpellLimits.STAFFS)
		var staff: int = index % SpellLimits.STAFFS
		var compiled: CompiledStaff = _installed[index]
		if compiled == null or compiled.is_empty():
			continue
		var cast: CompiledCast = compiled.casts[mini(_cursor[index], compiled.casts.size() - 1)]
		var origin: Vector2 = _aim_origin[actor] if _aim_seen[actor] != 0 and _aim_origin[actor].is_finite() else _wind_origin[index]
		var aim: Vector2 = _aim_dir[actor] if _aim_seen[actor] != 0 and _aim_dir[actor].is_finite() else _wind_dir[index]
		_walk_turn[actor] = _wind_walk[index]
		if _leave(index, compiled, cast, origin, aim) and rt.events != null and cast.mana > 0.0:
			rt.events.mana_spend_requested.emit(actor, staff, cast.mana)
		if rt._winding <= 0:
			return


## `actor`'s winding casts leave no more and its staffs are free (a new driver took the body: the
## cast was the old one's; docs/milestones/cast-timing.md).
func cancel_winds(actor: int) -> void:
	if rt._winding <= 0 or actor < 0 or actor >= Runtime.ACTORS:
		return
	for staff in SpellLimits.STAFFS:
		_cancel_wind(actor * SpellLimits.STAFFS + staff)


## The winding cast of `actor`'s staff `staff` leaves no more and the staff is free (a prop left the
## state that wound it up, props W6); nothing was paid.
func cancel_wind(actor: int, staff: int) -> void:
	if rt._winding > 0 and _in_range(actor, staff):
		_cancel_wind(actor * SpellLimits.STAFFS + staff)


## `actor`'s winding casts wait `seconds` longer (its Caster asks while the body is slowed: a chill
## stretches a wind-up, a freeze holds it; docs/milestones/cast-timing.md). Allocates nothing.
func hold_winds(actor: int, seconds: float) -> void:
	if rt._winding <= 0 or seconds <= 0.0 or actor < 0 or actor >= Runtime.ACTORS:
		return
	for staff in SpellLimits.STAFFS:
		var index: int = actor * SpellLimits.STAFFS + staff
		if _wind_due[index] != INF:
			_wind_due[index] += seconds
			_cooldown[index] += seconds


## Staff `index`'s winding cast leaves no more (down, rebuilt, its caster gone): the staff is free
## and nothing was paid.
func _cancel_wind(index: int) -> void:
	if _wind_due[index] == INF:
		return
	_wind_due[index] = INF
	rt._winding -= 1
	_cooldown[index] = 0.0


## The delay and the next cast of the cycle, after `cast` fired (or had nothing in it).
func _after_cast(index: int, compiled: CompiledStaff, cast: CompiledCast) -> void:
	_cooldown[index] = cast.delay
	rt._cooldown_rows = maxi(rt._cooldown_rows, index + 1)
	_cursor[index] = 0 if cast.ends_cycle else (_cursor[index] + 1) % compiled.casts.size()


## A new press of this actor's staff (not a held button's repeat: the caller tells them apart, as
## for a `hold`'s switch-off): its live `on recast` carriers go off (`recast_staff`), then it casts
## (`cast_staff`, whose return this is), so the carrier this press casts is not one of them.
func press_staff(actor: int, staff: int, origin: Vector2, direction: Vector2, mana: float, walk: Vector2 = Vector2.ZERO) -> float:
	rt.recast_staff(actor, staff)
	if _in_range(actor, staff):
		# A new press is a new attack: it winds up whole, a spray too.
		_pour_until[actor * SpellLimits.STAFFS + staff] = -1.0
	return rt.cast_staff(actor, staff, origin, direction, mana, walk)


## `on recast`: staff `staff` of `actor` is pressed again (`press_staff`). Every live carrier that
## staff cast with that trigger fires its payload from where it is now, the way a timer's tick does,
## whether or not the staff is ready to cast again: the press is the detonation. It fires every
## time while the carrier lives; a payload's own `on recast` waits for the next press. Returns how
## many fired.
func recast_staff(actor: int, staff: int) -> int:
	if not _in_range(actor, staff):
		return 0
	var fired: int = 0
	# Payloads may list more such carriers; they sit past `count` and wait for the next press.
	var count: int = rt._lc_count
	for i in count:
		var tag: int = _lc_tag[i]
		if SpellTag.caster_of(tag) != actor or SpellTag.staff_of(tag) != staff:
			continue
		var spell: CompiledSpell = _profiles.get(tag)
		var trigger: CompiledSpell.Trigger = _job_lasting._lc_trigger_of(i, spell)
		if trigger == null or trigger.event != TriggerBase.Event.RECAST or not _job_lasting._lc_follow(i):
			continue
		_job_lasting._lc_fire(i, trigger.payload, _lc_at[i])
		fired += 1
	return fired


## `on any cast` (docs/milestones/staff-language.md, L3): a cast of any staff of `actor` is
## leaving (`_leave`). Every live carrier that caster cast with that trigger fires its payload from
## where it is now, as `on recast` does on a press. Payloads may list more such carriers; they sit
## past the count taken first and wait for the next cast. Returns how many fired.
func _any_cast(actor: int, heard: int) -> int:
	var fired: int = 0
	var count: int = mini(heard, rt._lc_count)
	for i in count:
		var tag: int = _lc_tag[i]
		if SpellTag.caster_of(tag) != actor:
			continue
		var spell: CompiledSpell = _profiles.get(tag)
		var trigger: CompiledSpell.Trigger = _job_lasting._lc_trigger_of(i, spell)
		if trigger == null or trigger.event != TriggerBase.Event.ANY_CAST or not _job_lasting._lc_follow(i):
			continue
		_job_lasting._lc_fire(i, trigger.payload, _lc_at[i])
		fired += 1
	return fired


## Opens the caster `actor` (an actor id a body opened in the actor table, actors G3b): its
## staffs, delays, aim and the rest start new, so it installs, casts and aims (`install_staff`,
## `cast_staff`, `set_aim`) from a clean row; generations go on round the ring, so shots of an
## earlier caster with the same id keep theirs. A body calls it once, before its first build.
## Returns false for an id outside the table.
func open_caster(actor: int) -> bool:
	if actor < 0 or actor >= Runtime.ACTORS:
		return false
	# Whatever an earlier caster with this id left (builds, holds, beams, launches) goes first.
	rt.close_caster(actor)
	for staff in SpellLimits.STAFFS:
		_open_ring[actor * SpellLimits.STAFFS + staff] = _ring[actor * SpellLimits.STAFFS + staff]
	return true


## True when the spell tag `tag` is of a build the caster open now under its id began (`open_caster`,
## then `install_staff`), not one of an earlier caster with the same id whose shots still fly, nor
## of a caster closed since: what reads the caster's body at the hit (Combat's power, boss plan OB7)
## asks it first. Builds count from the caster's open; past GENERATIONS of them every generation
## of the ring is its own (the older shots of each were revoked as it began them).
func cast_by_open(tag: int) -> bool:
	if not SpellTag.is_spell_tag(tag):
		return false
	var index: int = SpellTag.caster_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	var builds: int = _open_builds[index]
	if builds <= 0:
		return false
	if builds >= SpellLimits.GENERATIONS:
		return true
	return posmod(SpellTag.generation_of(tag) - _open_ring[index] - 1, SpellLimits.GENERATIONS) < builds


## The caster `actor` is gone (its body left or died): its staffs are emptied, its own waiting
## launches (a cast's later firings), holds and beams end. Its shots in the air fly on with their
## own numbers until they end, and their waiting payloads fire on, as after an edit. The body
## closes its actor id in the table itself.
func close_caster(actor: int) -> void:
	if actor < 0 or actor >= Runtime.ACTORS:
		return
	_job_fires._drop_pending(func(launch: Runtime.PendingLaunch) -> bool: return launch.actor == actor and launch.caster == Runtime.CASTER_BODY)
	for staff in SpellLimits.STAFFS:
		var index: int = actor * SpellLimits.STAFFS + staff
		_open_builds[index] = 0
		_open_ring[index] = _ring[index]
		_job_generations._release_hold(index)
		var old: int = _current[index]
		_installed[index] = null
		_current[index] = -1
		if old >= 0:
			_job_generations._release_generation(actor, staff, old)
	for carrier: Carrier in rt._carriers.values():
		carrier.end_actor(actor)
	_reset_caster(actor)


## Which cast of staff `index`'s cycle a press with `mana` fires (docs/milestones/cast-timing.md,
## T3): the one at the cursor, or the first after it the mana pays, up to the cycle's end (the
## ones before it are skipped); -1 when the mana pays none of them, or the staff has no build.
## INF mana: the one at the cursor.
func _firing_cast(index: int, mana: float) -> int:
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty():
		return -1
	var count: int = compiled.casts.size()
	for at in range(mini(_cursor[index], count - 1), count):
		if mana >= compiled.casts[at].mana:
			return at
	return -1


## Which cast of this actor's staff's cycle a press with `mana` fires (an unaffordable one is
## skipped; docs/milestones/cast-timing.md, T3), -1 when the mana pays none left in the cycle or it
## has no build: what the corner panel marks.
func firing_cast(actor: int, staff: int, mana: float) -> int:
	return _firing_cast(actor * SpellLimits.STAFFS + staff, mana) if _in_range(actor, staff) else -1


## The cast a press of this staff with `mana` would fire (`_firing_cast`), else the one at its
## cursor; null with no build.
func _next_cast(actor: int, staff: int, mana: float) -> CompiledCast:
	if not _in_range(actor, staff):
		return null
	var index: int = actor * SpellLimits.STAFFS + staff
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty():
		return null
	var at: int = _firing_cast(index, mana)
	return compiled.casts[at if at >= 0 else mini(_cursor[index], compiled.casts.size() - 1)]


## The mana the next cast of this caster's staff costs: the one a press with `mana` would fire
## (an unaffordable one is skipped; with INF, the one at the cursor), 0.0 while its sustained
## carriers are on (that press switches them off), or REFUSED when it has no build. An enemy's AI
## asks before it winds up, so a telegraph is always followed by its cast.
func next_cast_mana(actor: int, staff: int, mana: float = INF) -> float:
	var cast: CompiledCast = _next_cast(actor, staff, mana)
	if cast == null:
		return Runtime.REFUSED
	if not _hold_tags[actor * SpellLimits.STAFFS + staff].is_empty():
		return 0.0
	return cast.mana


## True when a cast of this actor's staff can leave within `within` seconds with `mana` (that
## staff's pool): its delay is no longer than that, and `mana` less what the staff's sustained
## carriers hold (`reserved_mana`) pays a cast before the cycle's end (the ones it cannot pay are
## skipped; docs/milestones/cast-timing.md). False with no build. One call for what an enemy's AI
## asks every step while its target is in reach (performance pass, 2026-10-28).
func cast_ready(actor: int, staff: int, within: float, mana: float) -> bool:
	if not _in_range(actor, staff):
		return false
	var index: int = actor * SpellLimits.STAFFS + staff
	if _cooldown[index] > within:
		return false
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty():
		return false
	if not _hold_tags[index].is_empty():
		return true
	return _firing_cast(index, maxf(mana - _hold_mana[index], 0.0)) >= 0


## How far the next cast of this caster's staff reaches along its aim, for an enemy's telegraph:
## its first carrier's flight (speed x life), a beam's or swing's length;
## 0 for one that is not aimed (a nova, an orbit, a still shot, a decoy...) or no build.
func next_cast_reach(actor: int, staff: int, mana: float = INF) -> float:
	var first: CompiledSpell = _next_carrier(actor, staff, mana)
	if first == null or first.nova_ways() > 1:
		# A nova goes every way: not aimed.
		return 0.0
	if rt._skyfall.falls(first):
		# Skyfall: it falls where it is cast, not along an aim.
		return 0.0
	if Orbit.orbits_on(first, _job_launches._carrier_of(first)):
		# Orbit: it circles its caster, not along an aim.
		return 0.0
	return _job_launches._carrier_of(first).reach_of(first)


## What the next cast of this caster's staff does (`CastSense`; docs/milestones/M2-enemy-ai.md),
## for an AI that plays whatever staffs it holds: the one a press with `mana` would fire; null
## with no build.
func next_cast_sense(actor: int, staff: int, mana: float = INF) -> CastSense:
	var cast: CompiledCast = _next_cast(actor, staff, mana)
	return cast.sense if cast != null else null


## The hit radius of the next cast's first carrier (0 for none), for the width of a telegraph.
func next_cast_radius(actor: int, staff: int, mana: float = INF) -> float:
	var first: CompiledSpell = _next_carrier(actor, staff, mana)
	return first.radius if first != null else 0.0


## The first carrier of the next cast of this staff, or null (no build, or nothing in the cast).
func _next_carrier(actor: int, staff: int, mana: float = INF) -> CompiledSpell:
	var cast: CompiledCast = _next_cast(actor, staff, mana)
	return null if cast == null or cast.group.is_empty() else cast.group.spells[0]


## The party left the room for the next of the run (`room_left`, run generation RG4): what every
## caster's spells left in it ends quietly with it, as the room goes (no blast, no payload, no end
## point): its casts winding up, its waiting launches, its held carriers, every carrier's own rows
## (beams, portals, rings, swings, slams, decoys and familiars) and its moves. The shots in the air are the projectile
## manager's to end (each `shot_ended`). Every caster keeps its builds, delays and mana: the party
## goes on as it is.
func leave_room() -> void:
	for actor in rt._caster_rows:
		for carrier: Carrier in rt._carriers.values():
			carrier.end_actor(actor)
	for index in _hold_tags.size():
		_job_generations._release_hold(index)
	_job_fires._drop_pending(func(_launch: Runtime.PendingLaunch) -> bool: return true)
	for actor in rt._caster_rows:
		rt._moves.reset_actor(actor)
		rt._plow.reset_actor(actor)
		for staff in SpellLimits.STAFFS:
			_cancel_wind(actor * SpellLimits.STAFFS + staff)


## A caster's own state back to new (its builds are handled by the caller).
func _reset_caster(caster: int) -> void:
	for staff in SpellLimits.STAFFS:
		var index: int = caster * SpellLimits.STAFFS + staff
		_cancel_wind(index)
		_cooldown[index] = 0.0
		_cursor[index] = 0
		_cast_count[index] = 0
		_pour_until[index] = -1.0
		_cast_turn[index] = 0.0
		_hold_mana[index] = 0.0
		_last_carrier_card[index] = &""
	rt._moves.reset_actor(caster)
	rt._plow.reset_actor(caster)
	for carrier: Carrier in rt._carriers.values():
		carrier.reset_actor(caster)
	_aim_origin[caster] = Vector2.INF
	_aim_dir[caster] = Vector2.INF
	_aim_seen[caster] = 0
	_aim_pivot[caster] = Vector2.INF
	rt._poses.reset_actor(caster)
	_last_infused[caster] = null


## A caster's staff: any actor id and staff 0-3 (a caster never opened casts from a clean row).
func _in_range(actor: int, staff: int) -> bool:
	return staff >= 0 and staff < SpellLimits.STAFFS and actor >= 0 and actor < Runtime.ACTORS

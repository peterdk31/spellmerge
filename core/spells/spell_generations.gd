class_name SpellGenerations
extends Object
## A staff's builds and what keeps them alive (core/spells/spells.gd): a generation's tags
## (`begin_generation`, `install_staff`), the live shots that count for each (`shot_started`,
## `shot_ended`), the hit profile a tag hits with, and the sustained (`hold`) carriers and the mana
## they reserve. Methods working on the runtime (`rt`), whose members hold all of it
## (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_casts", &"_job_fires", &"_job_lasting", &"revoked_tags", &"_current", &"_installed", &"_cursor", &"_hold_tags", &"_hold_mana", &"_node_counts", &"_profiles", &"_live", &"_generation_live", &"_caster_live", &"_rec_relay", &"_pour_until", &"_ring", &"_open_builds"]

var rt: Runtime = null
var _job_casts: SpellCasts = null
var _job_fires: SpellFires = null
var _job_lasting: SpellLasting = null
var revoked_tags: PackedInt64Array
var _current: PackedInt32Array
var _installed: Array[CompiledStaff]
var _cursor: PackedInt32Array
var _hold_tags: Array[PackedInt64Array]
var _hold_mana: PackedFloat32Array
var _node_counts: Dictionary
var _profiles: Dictionary
var _live: Dictionary
var _generation_live: Dictionary
var _caster_live: PackedInt32Array
var _rec_relay: Array[HitProfile]
var _pour_until: PackedFloat64Array
var _ring: PackedInt32Array
var _open_builds: PackedInt32Array


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## Registers every spell of `compiled` under a new generation of this actor's staff and
## returns the tag of its first spell, or 0 for an empty staff (the staff then has no build)
## or a bad actor or staff. The staff's generation advances; if its shots from 8 builds ago are
## still in the air the oldest generation is revoked (see `revoked_tags`).
func begin_generation(actor: int, staff: int, compiled: CompiledStaff) -> int:
	revoked_tags.clear()
	if compiled == null or not _job_casts._in_range(actor, staff) or compiled.nodes.size() > SpellTag.NODE_MASK + 1:
		return 0
	var index: int = actor * SpellLimits.STAFFS + staff
	_release_hold(index)
	_job_casts._cancel_wind(index)
	_pour_until[index] = -1.0
	# The old build casts no more: its cast's later firings go (a payload of a shot in the air
	# fires on, as the shot flies on).
	_job_fires._drop_pending(func(launch: Runtime.PendingLaunch) -> bool: return launch.actor == actor and launch.staff == staff and launch.caster == Runtime.CASTER_BODY)
	var old: int = _current[index]
	if compiled.is_empty():
		_installed[index] = null
		_cursor[index] = 0
		_current[index] = -1
		if old >= 0:
			_release_generation(actor, staff, old)
		return 0
	var generation: int = (_ring[index] + 1) % SpellLimits.GENERATIONS
	_ring[index] = generation
	_open_builds[index] = mini(_open_builds[index] + 1, SpellLimits.GENERATIONS)
	_current[index] = generation
	var key: int = SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation))
	for node in _node_counts.get(key, 0):
		var stale: int = SpellTag.make(actor, staff, node, generation)
		if _live.get(stale, 0) > 0:
			revoked_tags.append(stale)
		_profiles.erase(stale)
		_live.erase(stale)
	# The revoked build's waiting payloads go with its shots (its numbers are the new build's now).
	_job_fires._drop_pending(func(launch: Runtime.PendingLaunch) -> bool: return launch.actor == actor and launch.staff == staff and launch.generation == generation)
	_drop_live(key)
	for spell in compiled.nodes:
		_profiles[SpellTag.make(actor, staff, spell.node, generation)] = spell
	_node_counts[key] = compiled.nodes.size()
	_installed[index] = compiled
	rt._caster_rows = maxi(rt._caster_rows, actor + 1)
	_cursor[index] = 0
	if old >= 0:
		_release_generation(actor, staff, old)
	return SpellTag.make(actor, staff, 0, generation)


## A shot with `tag` ended (hit, expired or was removed). The generation's spells (every
## node) are freed once its last shot of any node is gone and a newer build has replaced it. A
## sustained (`hold`) carrier whose last shot ends frees its mana reservation.
func shot_ended(tag: int) -> void:
	var live: int = _live.get(tag, 0)
	if live <= 0:
		return
	if live == 1:
		_live.erase(tag)
		_end_hold_of(tag)
		rt._poses.end_strike(tag)
	else:
		_live[tag] = live - 1
	_generation_gone(tag)


## One shot of `tag`'s generation, or one launch that keeps it (`_delay`), is gone: an old
## generation with none left is freed.
func _generation_gone(tag: int) -> void:
	var key: int = SpellTag.generation_key(tag)
	_take_live(key)
	if not _generation_live.has(key) and not _is_current(tag):
		_erase_generation(tag)


## One more shot or launch of the generation `key` is alive (`_generation_live`, and its caster's
## sum, `_caster_live`).
func _add_live(key: int) -> void:
	_generation_live[key] = _generation_live.get(key, 0) + 1
	_caster_live[SpellTag.caster_of(key)] += 1


## One fewer of the generation `key` is alive (none left: its entry goes).
func _take_live(key: int) -> void:
	var had: int = _generation_live.get(key, 0)
	if had <= 1:
		_drop_live(key)
		return
	_generation_live[key] = had - 1
	_caster_live[SpellTag.caster_of(key)] -= 1


## Nothing of the generation `key` is alive any more (its last one gone, or the generation revoked):
## its entry goes, and its count leaves its caster's.
func _drop_live(key: int) -> void:
	_caster_live[SpellTag.caster_of(key)] -= _generation_live.get(key, 0)
	_generation_live.erase(key)


## Generations of this staff that still have spells registered (the current one and any
## older ones with shots in the air).
func generations_held(actor: int, slot: int) -> int:
	var count: int = 0
	if not _job_casts._in_range(actor, slot):
		return 0
	for generation in SpellLimits.GENERATIONS:
		if _node_counts.has(SpellTag.generation_key(SpellTag.make(actor, slot, 0, generation))):
			count += 1
	return count


## What one hit of a shot with `tag` does, or null when the tag is no spell's (a shot of no staff)
## or its generation is gone. `shot` is the shot that hit (the event's `shot`; -1 for a ray or a
## strike). Shared and read-only; allocates nothing.
func hit_profile(tag: int, shot: int = -1) -> HitProfile:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return null
	# A relay shot hits with what it took on (the hit names its shot).
	var slot: int = shot if projectiles != null else -1
	if slot >= 0 and slot < _rec_relay.size() and _rec_relay[slot] != null and rt._same(slot) and projectiles.get_tag_of(slot) == tag:
		return _rec_relay[slot]
	# A ray (a beam, a swing, a zap, a jump of any) has no slot: it hits with what the
	# one being sent carries (an echo's half, a zap's share, a jump's parent hit).
	if rt._ray.hit != null and tag == rt._ray.tag:
		return rt._ray.hit
	return spell.hit


## Makes `compiled` (from `compile_staff`) the build of this actor's staff (0-3), starting its
## cycle at the first cast, and removes the shots the new generation revoked. Editing a staff
## switches its sustained (`hold`) carriers off. Returns the tag of its first spell, or 0 for an
## empty staff (which leaves the staff with no build) or a bad actor or staff.
func install_staff(actor: int, staff: int, compiled: CompiledStaff) -> int:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var tag: int = rt.begin_generation(actor, staff, compiled)
	if projectiles != null:
		for revoked in revoked_tags:
			projectiles.remove_by_tag(revoked)
	for revoked in revoked_tags:
		for carrier: Carrier in rt._carriers.values():
			carrier.end_of(revoked)
	return tag


func _is_current(tag: int) -> bool:
	var index: int = SpellTag.caster_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	return _current[index] == SpellTag.generation_of(tag)


## Erases the profiles of every node of the tag's generation.
func _erase_generation(tag: int) -> void:
	var key: int = SpellTag.generation_key(tag)
	for node in _node_counts.get(key, 0):
		_profiles.erase(SpellTag.make(SpellTag.caster_of(tag), SpellTag.staff_of(tag), node, SpellTag.generation_of(tag)))
	_node_counts.erase(key)


## The old generation is no longer current: free it now if none of its shots is in the air.
func _release_generation(actor: int, staff: int, generation: int) -> void:
	var key: int = SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation))
	if _generation_live.get(key, 0) == 0:
		_erase_generation(key)


## True when `spell`, fired under `tag`, is a sustained (`hold`) carrier: it has the card and its
## build is still its staff's. A hold of an older build (the staff was edited, or its caster
## closed, while a shot that fires it was in the air) was switched off with it: it lives its own life.
func _holds(spell: CompiledSpell, tag: int) -> bool:
	return spell.behaviour(ModifierBase.Behaviour.HOLD) > 0.0 and _is_current(tag)


## True when a held `spell` is cast again rather than kept on: a swing is over at once, so while
## held it is cast anew every wind-up and lifetime (it sweeps back), until switched off. Its hold ends only then, not between two of them.
static func _repeats(spell: CompiledSpell) -> bool:
	return spell != null and spell.has_trait(Carrier.REPEATS_HELD)


## A sustained (`hold`) carrier made shots: it stays on and its staff reserves the mana of the
## cast it belongs to until it is switched off (`cast_staff` again, an edit) or its last shot ends.
## The same for every firing: the cast's own carrier, a payload's, a burst's later firing. The
## firings of one carrier share its tag, so it is listed once; a staff reserves one cast's mana.
func _start_hold(tag: int) -> void:
	if _live.get(tag, 0) <= 0 and not _repeats(rt.profile(tag)):
		return
	var actor: int = SpellTag.caster_of(tag)
	var index: int = actor * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	if _hold_tags[index].has(tag):
		return
	if _hold_tags[index].is_empty():
		_hold_mana[index] = _cast_mana_of(_installed[index], SpellTag.node_of(tag))
	_hold_tags[index].append(tag)
	_send_reserved(actor, SpellTag.staff_of(tag))


## The mana of the cast of `compiled` that `node` belongs to (its own carrier or one of its
## payloads), or 0.0 when none has it.
func _cast_mana_of(compiled: CompiledStaff, node: int) -> float:
	if compiled == null:
		return 0.0
	for cast in compiled.casts:
		if _group_has(cast.group, node):
			return cast.mana
	return 0.0


## True when `node` is a carrier of `group` or of a payload below it.
func _group_has(group: CompiledGroup, node: int) -> bool:
	if group == null:
		return false
	for spell in group.spells:
		if spell.node == node:
			return true
		for trigger in spell.triggers:
			if _group_has(trigger.payload, node):
				return true
	return false


## Switches off the sustained carriers of this staff: their shots go, their waiting firings
## (a burst's later ones, a payload that fires them) go, their mana is free. Other waiting
## launches of the staff fire on.
func _release_hold(index: int) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	if _hold_tags[index].is_empty():
		return
	var tags: PackedInt64Array = _hold_tags[index].duplicate()
	_job_fires._drop_pending(func(launch: Runtime.PendingLaunch) -> bool: return _job_fires._fires_any(launch, tags))
	_hold_tags[index].clear()
	_hold_mana[index] = 0.0
	for tag in tags:
		for carrier: Carrier in rt._carriers.values():
			carrier.switch_off(tag)
		_job_lasting._lc_leave(tag, true)
	if projectiles != null:
		for tag in tags:
			# remove_by_tag sends no shot_ended, so the counts are ended here.
			for _n in projectiles.remove_by_tag(tag):
				rt.shot_ended(tag)
	_send_reserved(floori(float(index) / SpellLimits.STAFFS), index % SpellLimits.STAFFS)


## The last shot of `tag` ended: if it was a sustained carrier, it is off now.
func _end_hold_of(tag: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var index: int = SpellTag.caster_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	var at: int = _hold_tags[index].find(tag)
	if at < 0 or _repeats(rt.profile(tag)):
		return
	_hold_tags[index].remove_at(at)
	if _hold_tags[index].is_empty():
		_hold_mana[index] = 0.0
		_send_reserved(SpellTag.caster_of(tag), SpellTag.staff_of(tag))


## Tells the HUD of the seat that drives `actor` what the sustained carriers of its staff
## `staff` hold (an AI reads `reserved_mana` itself; the event is the seat's).
func _send_reserved(actor: int, staff: int) -> void:
	if rt.events == null:
		return
	var table: Runtime.ActorsScript = rt._actor_table()
	var seat: int = table.seat_of(actor) if table != null else Runtime.ActorsScript.NONE
	if seat != Runtime.ActorsScript.NONE:
		rt.events.mana_reserved.emit(seat, staff, rt.reserved_mana(actor, staff))

class_name SpellLasting
extends Object
## The carriers that last (core/spells/spells.gd): each carrier with a timer or a nearness trigger
## is a row (`_lc_*`), followed where its shot, row or body is now (`_lc_where`), its timer ticked
## and its payload fired (`_step_live`, `_lc_fire`). Methods working on the runtime (`rt`), whose
## members hold all of it (core/README.md, "The spell runtime").

const Runtime := preload("res://core/spells/spells.gd")

## Not state (core/sim/README.md): the runtime, the other jobs this one calls and the runtime's
## arrays it works on, each the runtime's own (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"rt", &"_job_fires", &"_job_launches", &"_profiles", &"_lc_trigger", &"_lc_tag", &"_lc_kind", &"_lc_ref", &"_lc_seq", &"_lc_tied", &"_lc_left", &"_lc_clock", &"_lc_at", &"_lc_way", &"_lc_team", &"_aim_dir", &"_aim_seen"]

var rt: Runtime = null
var _job_fires: SpellFires = null
var _job_launches: SpellLaunches = null
var _profiles: Dictionary
var _lc_trigger: PackedInt32Array
var _lc_tag: PackedInt64Array
var _lc_kind: PackedInt32Array
var _lc_ref: PackedInt32Array
var _lc_seq: PackedInt64Array
var _lc_tied: PackedByteArray
var _lc_left: PackedFloat32Array
var _lc_clock: PackedFloat32Array
var _lc_at: PackedVector2Array
var _lc_way: PackedVector2Array
var _lc_team: PackedInt32Array
var _aim_dir: PackedVector2Array
var _aim_seen: PackedByteArray


## Takes the runtime's arrays and jobs, by the names in DERIVED: again whenever the runtime's
## arrays may have been replaced (`SpellRuntime._link_jobs`).
func link(runtime: Runtime) -> void:
	rt = runtime
	for name: StringName in DERIVED:
		if name != &"rt":
			set(name, runtime.get(name))


## Lists a carrier of `tag` that lasts, once for each trigger of `TriggerBase.LIVE` it has (see
## `_lc_tag`): `kind` and `ref` (with `seq`, the row's birth) say where it is, `tied` that it ends
## with that row, else it lives `life` seconds; `at` is where it starts and `way` its way.
func _lc_join(spell: CompiledSpell, tag: int, kind: int, ref: int, seq: int, tied: bool, life: float, at: Vector2, way: Vector2) -> void:
	for t in spell.triggers.size():
		var trigger: CompiledSpell.Trigger = spell.triggers[t]
		if TriggerBase.LIVE.has(trigger.event):
			_lc_join_one(t, trigger.interval, tag, kind, ref, seq, tied, life, at, way)
			if trigger.event == TriggerBase.Event.NEAR:
				# On near is ready at once: a foe already near sets it off.
				_lc_clock[rt._lc_count - 1] = 0.0


## How many entries `_lc_join` lists for one carrier of `spell`: its triggers of
## `TriggerBase.LIVE`.
static func _lc_rows(spell: CompiledSpell) -> int:
	var rows: int = 0
	for trigger in spell.triggers:
		if TriggerBase.LIVE.has(trigger.event):
			rows += 1
	return rows


func _lc_join_one(trigger: int, interval: float, tag: int, kind: int, ref: int, seq: int, tied: bool, life: float, at: Vector2, way: Vector2) -> void:
	if rt._lc_count == _lc_tag.size():
		_lc_grow(rt._lc_count * 2)
	var i: int = rt._lc_count
	rt._lc_count += 1
	_lc_trigger[i] = trigger
	_lc_tag[i] = tag
	_lc_kind[i] = kind
	_lc_ref[i] = ref
	_lc_seq[i] = seq
	_lc_tied[i] = 1 if tied else 0
	_lc_left[i] = INF if tied else life
	_lc_clock[i] = Runtime.first_tick(interval, life)
	_lc_at[i] = at
	_lc_way[i] = way.normalized() if way.is_finite() and not way.is_zero_approx() else Vector2.RIGHT
	_lc_team[i] = rt._team(SpellTag.caster_of(tag))


func _lc_grow(size: int) -> void:
	_lc_trigger.resize(size)
	_lc_tag.resize(size)
	_lc_kind.resize(size)
	_lc_ref.resize(size)
	_lc_seq.resize(size)
	_lc_tied.resize(size)
	_lc_left.resize(size)
	_lc_clock.resize(size)
	_lc_at.resize(size)
	_lc_way.resize(size)
	_lc_team.resize(size)


## Takes live carrier `i` off the list (the last one takes its place).
func _lc_remove(i: int) -> void:
	rt._lc_count -= 1
	_lc_trigger[i] = _lc_trigger[rt._lc_count]
	_lc_tag[i] = _lc_tag[rt._lc_count]
	_lc_kind[i] = _lc_kind[rt._lc_count]
	_lc_ref[i] = _lc_ref[rt._lc_count]
	_lc_seq[i] = _lc_seq[rt._lc_count]
	_lc_tied[i] = _lc_tied[rt._lc_count]
	_lc_left[i] = _lc_left[rt._lc_count]
	_lc_clock[i] = _lc_clock[rt._lc_count]
	_lc_at[i] = _lc_at[rt._lc_count]
	_lc_way[i] = _lc_way[rt._lc_count]
	_lc_team[i] = _lc_team[rt._lc_count]


## A carrier of `tag` that is not tied to a row ended (an entity): one of its entries leaves, or
## with `every` all of them (its build was revoked).
func _lc_leave(tag: int, every: bool) -> void:
	# One carrier is listed once per trigger of `TriggerBase.LIVE` (`_lc_join`).
	var spell: CompiledSpell = _profiles.get(tag)
	var left: int = maxi(_lc_rows(spell), 1) if spell != null else 1
	var i: int = rt._lc_count - 1
	while i >= 0:
		if _lc_tag[i] == tag and _lc_tied[i] == 0:
			_lc_remove(i)
			left -= 1
			if not every and left <= 0:
				return
		i -= 1


## The entity with `key` (`entity_key`) of `tag` ended: its entries leave, and no other entity's
## of that tag (each decoy is its own body; each familiar its own orb).
func _lc_leave_key(tag: int, key: int) -> void:
	var i: int = rt._lc_count - 1
	while i >= 0:
		if _lc_tag[i] == tag and _lc_tied[i] == 0 and _lc_seq[i] == key and (_lc_kind[i] == Runtime.LC_ACTOR or _lc_kind[i] == Runtime.LC_POINT):
			_lc_remove(i)
		i -= 1


## Where live carrier `i` is now, or `Vector2.INF` when the row it follows is gone.
func _lc_where(i: int) -> Vector2:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var ref: int = _lc_ref[i]
	match _lc_kind[i]:
		Runtime.LC_SLOT:
			return projectiles.get_position_of(ref) if projectiles.get_seq_of(ref) == _lc_seq[i] else Vector2.INF
		Runtime.LC_ROW:
			var spell: CompiledSpell = _profiles.get(_lc_tag[i])
			return _job_launches._carrier_of(spell).tip_of(ref, _lc_seq[i]) if spell != null else Vector2.INF
		Runtime.LC_ACTOR:
			return projectiles.get_anchor(ref)
	return _lc_at[i]


## Runs the live carriers on by `delta`: each that ended leaves the list, each timer whose clock
## runs out fires its payload from where its carrier is. Payloads may list more carriers; they
## run from this step on.
func _step_live(delta: float) -> void:
	var i: int = 0
	while i < rt._lc_count:
		var spell: CompiledSpell = _profiles.get(_lc_tag[i])
		var at: Vector2 = _lc_where(i)
		_lc_left[i] -= delta
		if spell == null or _lc_left[i] <= 0.0 or (_lc_tied[i] == 1 and not at.is_finite()):
			_lc_remove(i)
			continue
		if at.is_finite():
			_lc_at[i] = at
		var trigger: CompiledSpell.Trigger = _lc_trigger_of(i, spell)
		if trigger != null and trigger.event == TriggerBase.Event.TIMER:
			_lc_clock[i] -= delta
			if _lc_clock[i] <= 0.0:
				_lc_clock[i] += trigger.interval
				# The tick was its payload's wind-up: it leaves now.
				_lc_fire(i, trigger.payload, _lc_at[i], true)
		elif trigger != null and trigger.event == TriggerBase.Event.NEAR:
			_lc_clock[i] -= delta
			if _lc_clock[i] <= 0.0:
				_lc_near(i, trigger)
		i += 1


## `on near` of live carrier `i`, due to look: the nearest foe of its caster within its payload's
## reach sets it off, and its payload winds up and fires from the carrier toward that foe; it
## waits its interval (the payload's wind-up, the time over carried as a timer's) before it can
## fire again. With no foe near it looks again SpellLimits.NEAR_LOOK_AGAIN later (paced, never
## dropped: rule 5), so many waiting mines cost a look each every few steps, not every step. Its
## foes are its caster's (`Actors.is_foe`), by the team it had when it joined once that caster is
## gone: a dead imp's mine still spares its pack.
func _lc_near(i: int, trigger: CompiledSpell.Trigger) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var team: int = rt._team(SpellTag.caster_of(_lc_tag[i]))
	if team == Runtime.ActorsScript.NONE:
		team = _lc_team[i]
	var at: Vector2 = _lc_at[i]
	var foe: Node2D = projectiles.nearest_target(at, trigger.reach, Runtime.HITS, null, null, team)
	if foe == null:
		_lc_clock[i] = SpellLimits.NEAR_LOOK_AGAIN
		return
	_lc_clock[i] += trigger.interval
	var toward: Vector2 = projectiles.nearest_point - at
	_lc_fire(i, trigger.payload, at, false, null, toward if not toward.is_zero_approx() else Vector2.ZERO)


## Fires the payload of live carrier `i` from `from`, along `aim` when given (`on near`: toward
## the foe), else its way where it is: a shot's own (`_heading`); on an actor's body (a dash, a decoy) the way that actor aims now; else outward from
## its caster's body through it; else its `_lc_way`. Its shot casts the payload while it flies, an
## actor's body while it is there (owner, 2026-11-06), else the point does.
func _lc_fire(i: int, payload: CompiledGroup, from: Vector2, wound: bool = false, source: Node = null, aim: Vector2 = Vector2.ZERO) -> void:
	var projectiles: Runtime.ProjectilesScript = rt.projectiles
	var spell: CompiledSpell = _profiles.get(_lc_tag[i])
	if spell == null:
		return
	var tag: int = _lc_tag[i]
	var actor: int = SpellTag.caster_of(tag)
	var at: Vector2 = _lc_at[i]
	var slot: int = _lc_ref[i]
	if _lc_kind[i] != Runtime.LC_SLOT or not projectiles.is_alive(slot) or projectiles.get_seq_of(slot) != _lc_seq[i]:
		slot = -1
	var way: Vector2 = _lc_way[i]
	var caster: int = slot if slot >= 0 else Runtime.CASTER_POINT
	if slot >= 0:
		way = _job_launches._heading(spell, slot, at, actor)
	elif _lc_kind[i] == Runtime.LC_ACTOR:
		# An actor's body (a wizard's dash, a decoy): the way that actor aims now.
		var body: int = _lc_ref[i]
		caster = Runtime.body_caster(body)
		# A body that went down has its aim cleared (INF, `clear_aim`): its way stays as it was.
		if body >= 0 and body < Runtime.ACTORS and _aim_seen[body] != 0 and _aim_dir[body].is_finite():
			way = _aim_dir[body]
	else:
		var body: Vector2 = projectiles.get_anchor(actor)
		if body.is_finite() and not (at - body).is_zero_approx():
			way = (at - body).normalized()
	if not aim.is_zero_approx():
		way = aim.normalized()
	_job_fires._fire_payload(payload, tag, actor, from, way, source, caster, wound)


## The trigger live carrier `i` fires, or null.
func _lc_trigger_of(i: int, spell: CompiledSpell) -> CompiledSpell.Trigger:
	var t: int = _lc_trigger[i]
	return spell.triggers[t] if spell != null and t >= 0 and t < spell.triggers.size() else null


## Brings live carrier `i`'s place up to date (`_lc_at`) for an event it fires now (a hurt, a
## recast); false when it follows a row that is gone (`tied`), so it fires nothing.
func _lc_follow(i: int) -> bool:
	var at: Vector2 = _lc_where(i)
	if at.is_finite():
		_lc_at[i] = at
		return true
	return _lc_tied[i] == 0

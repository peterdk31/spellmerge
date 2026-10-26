extends Node
## The spell runtime (autoload `Spells`): staffs compiled from cards and cast (docs/milestones/
## M2-staffs.md). The reading rules live in `StaffCompiler` (`compile_staff`); this script casts.
##
## Building: `compile_staff(cards, staff)` reads a staff's cards into its cycle (`CompiledStaff`;
## it refuses nothing), `staff_view` gives the builder plain values, and
## `install_staff(player, staff, compiled)` makes it the build of one of a player's four staffs:
## a new generation, the shots a full generation ring revoked removed, and the staff's sustained
## (`hold`) carriers switched off.
##
## Casting: `cast_staff(player, staff, origin, direction, mana)` fires the next cast of the
## staff's cycle and returns the mana spent or `REFUSED`; delays (the staff's own, every
## carrier's cooldown, the recharge after the last cast) are per player and staff and tick in
## `step` (physics). A cast is a group: its carriers fan out a little; each carrier's shots are a
## fan (straight), a ring (orbit), still shots or rays; split and nova multiplied them in the
## compiler; homing is set on each shot. Cards that landed on the caster (or a payload's origin)
## ask combat for an area hit there (`area_hit_requested`); a dash card asks the player to move
## (`caster_move_requested`). A `hold` carrier lives until its staff is cast again or edited.
##
## Payloads: a trigger's payload (a group) is fired by its shot's `projectile_hit` (on hit),
## `projectile_expired` (on expire) or every `trigger_interval` seconds (timer, in `step`). It
## starts at the hit point (the shot's place at expiry, a little back from a wall; the shot's
## place for a timer), flies along the shot's velocity (outward from the caster through the shot
## for an orbit or still shot, along the beam for a ray) and cannot hit the target that fired it
## for `SpellLimits.SOURCE_EXCLUSION` seconds (a beam never hits it). Each shot fires at most
## `trigger_max_fires` times. One player's triggers fire at most `SpellLimits.MAX_FIRES_PER_STEP`
## payloads per `step` (an engine safeguard, not a build limit); the rest are dropped, never
## queued (`fires_dropped` counts them). A beam fires an on-expire payload at its end and has no
## timer. Payloads send no `spell_cast`: the player's staff does.
##
## Chain: a shot of a spell with `chain_jumps` that hits a target spawns a shot of the same
## tag from the hit point to the nearest other target within `SpellLimits.CHAIN_RANGE`
## (never the one just hit or the one before it), with one jump fewer; a beam jumps with
## another beam that pierces nothing (it skips only the one just hit, so it may stop at the
## one before if that stands in its way). The trigger's fire count is carried along. One player
## makes at most `SpellLimits.MAX_CHAINS_PER_STEP` jumps per `step`; the rest are dropped
## (`chains_dropped` counts them).
##
## Counting: every shot spawned here is counted with `shot_started`, and the manager's
## `shot_ended` signal ends it, so a generation lives as long as its last shot. A shot
## starts its children before it ends (the manager sends `shot_ended` after the handlers).
## `bind` connects to the manager and the event bus (`_ready` binds the autoloads; tests
## bind their own).
##
## `hit_profile(tag)` is what `gameplay/combat` asks on `projectile_hit`.
##
## Tags (`SpellTag`): player, staff, generation and node. `begin_generation(player, staff,
## compiled)` registers every compiled spell of a staff under a new generation and returns the
## tag of its first one; a payload's spells have their own nodes. Shots keep the tag they were
## born with, so a shot still in the air after a rebuild hits with its old numbers
## (`profile(tag)`). A generation is forgotten as a whole (every node together) when its last
## shot has ended (`shot_ended`) and it is no longer current.
##
## Order matters: a shot that spawns children (a payload on hit) must call `shot_started` for
## each child before it calls `shot_ended` for itself, or an old build could be freed between
## the two.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

## What `cast` returns when the spell did not fire (cooling down, too little mana, no spell).
const REFUSED: float = -1.0

## Payloads dropped by the per-step fire cap since the last `clear`.
var fires_dropped: int = 0
## Chain jumps dropped by the per-step jump cap since the last `clear`.
var chains_dropped: int = 0

## The projectile manager and the event bus; `bind` sets them.
var projectiles: ProjectilesScript = null
var events: EventsScript = null

## Tags whose shots the last `begin_generation` call revoked, because all 8 generations of
## the slot were in the air. Until the caller removes those shots from the projectile
## manager they carry a tag that now means the new spell, so read this right after
## `begin_generation`, remove them, and only then call `begin_generation` (which clears it)
## or `shot_ended` again for them. Part 6 does exactly that.
var revoked_tags: PackedInt64Array = PackedInt64Array()

## Registry stand-in for tests: anything with `get_resource(folder, id)`. Null uses `Registry`.
var registry: Node = null

## player * STAFFS + staff -> the current generation (0-7), -1 for no build
var _current: PackedInt32Array = PackedInt32Array()
## player * STAFFS + staff -> the current build, or null
var _installed: Array[CompiledStaff] = []
## player * STAFFS + staff -> which cast of its cycle comes next
var _cursor: PackedInt32Array = PackedInt32Array()
## player * STAFFS + staff -> the tags of its sustained (`hold`) carriers that are on
var _hold_tags: Array[PackedInt64Array] = []
## player * STAFFS + staff -> the carrier (form id) of its last cast, for the cast's look
var _last_form: Array[StringName] = []
## player * STAFFS + staff -> the mana its sustained carriers reserve
var _hold_mana: PackedFloat32Array = PackedFloat32Array()
## generation key (`SpellTag.generation_key`) -> how many nodes that generation registered
var _node_counts: Dictionary = {}
## tag -> CompiledSpell
var _profiles: Dictionary = {}
## tag -> live shots
var _live: Dictionary = {}
## generation key (the depth-0 tag) -> live shots of all depths of that generation
var _generation_live: Dictionary = {}

## player * STAFFS + staff -> seconds before that staff may cast again
var _cooldown: PackedFloat32Array = PackedFloat32Array()
## Payloads each player has fired in this step.
var _fires_used: PackedInt32Array = PackedInt32Array()
## Chain jumps each player has made in this step.
var _chains_used: PackedInt32Array = PackedInt32Array()
## What each shot knows, by projectile slot; valid while `_rec_seq` matches the manager's.
var _rec_seq: PackedInt64Array = PackedInt64Array()
var _rec_fires: PackedInt32Array = PackedInt32Array()
var _rec_chain: PackedInt32Array = PackedInt32Array()
var _rec_clock: PackedFloat32Array = PackedFloat32Array()
## Instance id of the target a chain came from.
var _rec_prev: PackedInt64Array = PackedInt64Array()
## 1 while `_timers` lists the slot (a stale entry stays until `step` prunes it).
var _rec_timed: PackedByteArray = PackedByteArray()
## Slots of shots with a timer trigger.
var _timers: PackedInt32Array = PackedInt32Array()
var _timer_count: int = 0
## The beam being cast: its tag, direction and how many fires it has left.
## Slots of live shots with an `on hurt` trigger, `_hurt_count` of them, flagged in `_rec_hurt`.
var _hurt_slots: PackedInt32Array = PackedInt32Array()
var _hurt_count: int = 0
var _rec_hurt: PackedByteArray = PackedByteArray()
## What a relay shot's hit became after it passed a teammate, by slot (null for none).
var _rec_relay: Array[HitProfile] = []
## The carrier of each player's last cast that had an infusion (for `relay`), or null.
var _last_infused: Array[CompiledSpell] = []

var _ray_tag: int = 0
var _ray_dir: Vector2 = Vector2.ZERO
var _ray_fires: int = 0
var _ray_chain: int = 0
var _ray_prev: int = 0
## Beam jumps waiting to be cast. A jump is made in a hit handler, i.e. inside the previous
## beam's `ray()`, so casting it there would nest one `ray()` deeper per jump and the
## manager stops at RAY_MAX_DEPTH. The outermost beam casts them, first in first out, once
## its own `ray()` has returned. Fixed size, so nothing is allocated per frame.
const JUMP_QUEUE: int = SpellLimits.MAX_CHAINS_PER_STEP * SpellLimits.PLAYERS
var _jq_spell: Array[CompiledSpell] = []
var _jq_target: Array[Node2D] = []
var _jq_tag: PackedInt64Array = PackedInt64Array()
var _jq_player: PackedInt32Array = PackedInt32Array()
var _jq_pos: PackedVector2Array = PackedVector2Array()
var _jq_dir: PackedVector2Array = PackedVector2Array()
var _jq_len: PackedFloat32Array = PackedFloat32Array()
var _jq_chain: PackedInt32Array = PackedInt32Array()
var _jq_prev: PackedInt64Array = PackedInt64Array()
var _jq_head: int = 0
var _jq_count: int = 0
var _jq_busy: bool = false


func _init() -> void:
	_current.resize(SpellLimits.PLAYERS * SpellLimits.STAFFS)
	_current.fill(-1)
	_installed.resize(SpellLimits.PLAYERS * SpellLimits.STAFFS)
	_cursor.resize(SpellLimits.PLAYERS * SpellLimits.STAFFS)
	_hold_mana.resize(SpellLimits.PLAYERS * SpellLimits.STAFFS)
	for i in SpellLimits.PLAYERS * SpellLimits.STAFFS:
		_hold_tags.append(PackedInt64Array())
		_last_form.append(&"")
	for i in SpellLimits.PLAYERS:
		_last_infused.append(null)
	_cooldown.resize(SpellLimits.PLAYERS * SpellLimits.STAFFS)
	_fires_used.resize(SpellLimits.PLAYERS)
	_chains_used.resize(SpellLimits.PLAYERS)
	_jq_spell.resize(JUMP_QUEUE)
	_jq_target.resize(JUMP_QUEUE)
	_jq_tag.resize(JUMP_QUEUE)
	_jq_player.resize(JUMP_QUEUE)
	_jq_pos.resize(JUMP_QUEUE)
	_jq_dir.resize(JUMP_QUEUE)
	_jq_len.resize(JUMP_QUEUE)
	_jq_chain.resize(JUMP_QUEUE)
	_jq_prev.resize(JUMP_QUEUE)
	_timers.resize(64)


func _ready() -> void:
	if projectiles == null:
		bind(get_node_or_null("/root/Projectiles") as ProjectilesScript, get_node_or_null("/root/Events") as EventsScript)


func _physics_process(delta: float) -> void:
	step(delta)


## Connect to a projectile manager and an event bus (either may be null, then casting is
## refused). Safe to call again: the old ones are disconnected.
func bind(manager: ProjectilesScript, bus: EventsScript) -> void:
	if projectiles != null and is_instance_valid(projectiles):
		projectiles.shot_ended.disconnect(shot_ended)
	if events != null and is_instance_valid(events):
		events.projectile_hit.disconnect(_on_hit)
		events.projectile_expired.disconnect(_on_expired)
		events.shot_blocked.disconnect(_on_shot_blocked)
		events.shield_blocked.disconnect(_on_shield_blocked)
		events.kill_landed.disconnect(_on_kill)
		events.wizard_hurt.disconnect(_on_hurt)
		events.reaction_landed.disconnect(_on_reaction)
		events.ally_passed.disconnect(_on_ally)
	projectiles = manager
	events = bus
	if projectiles != null:
		projectiles.shot_ended.connect(shot_ended)
	if events != null:
		events.projectile_hit.connect(_on_hit)
		events.projectile_expired.connect(_on_expired)
		events.shot_blocked.connect(_on_shot_blocked)
		events.shield_blocked.connect(_on_shield_blocked)
		events.kill_landed.connect(_on_kill)
		events.wizard_hurt.connect(_on_hurt)
		events.reaction_landed.connect(_on_reaction)
		events.ally_passed.connect(_on_ally)


## Compiles a staff's cards (ids by slot, `&""` for an empty slot) into its cycle, the casts it
## makes until it recharges (staffs A4; the rules are docs/milestones/M2-staffs.md, "Reading a
## staff", and `StaffCompiler`). It never errors and refuses nothing: an unknown or useless
## card is listed in `wasted` with the reason.
func compile_staff(cards: Array[StringName], staff: StaffBase) -> CompiledStaff:
	return StaffCompiler.new(_component).compile(cards, staff)


## What the builder shows of a staff, as plain values so that nothing outside `core/spells`
## reads a compiled staff: `empty`; `cards` (the card ids by slot, `&""` for an empty slot); `casts`, one Dictionary per cast of the cycle with `slots`
## (read order), `text`, `mana`, `delay`, `recharges`, `wrapped`, `targets` (card slot -> the
## carrier's slot, or `StaffCompiler.TARGET_CASTER` / `TARGET_POINT`) and `wasted` (slot ->
## reason); and `wasted` for the staff (cards that did nothing in any cast that read them).
func staff_view(cards: Array[StringName], staff: StaffBase) -> Dictionary:
	var compiled: CompiledStaff = compile_staff(cards, staff)
	var casts: Array[Dictionary] = []
	for cast in compiled.casts:
		casts.append({
			"slots": cast.slots, "text": cast.description, "mana": cast.mana, "delay": cast.delay,
			"recharges": cast.recharges, "wrapped": cast.wrapped,
			"targets": cast.targets.duplicate(), "wasted": cast.wasted.duplicate(),
		})
	var row: Array[StringName] = []
	row.assign(compiled.cards)
	return {"empty": compiled.is_empty(), "cards": row, "casts": casts, "wasted": compiled.wasted.duplicate()}


## What the builder shows of the component `id`: its name (the id when it has none, "" for
## an unknown id), its 16x16 icon (null when unknown) and its kind (`&"form"`, `&"element"`,
## `&"modifier"` or `&"trigger"`, `&""` when unknown). Scripts outside `core/` and
## `content/spells/` learn these here and never read the component's fields.
func component_name(id: StringName) -> String:
	var component: SpellComponent = _component(id)
	return _name_of(component) if component != null else ""


func component_icon(id: StringName) -> Texture2D:
	var component: SpellComponent = _component(id)
	return component.icon if component != null else null


## The one-line description of the component `id` for the builder, from its lore file in
## `content/story/lore/components/`. Empty for an unknown id or a missing file; the builder
## shows nothing for an empty one.
func component_description(id: StringName) -> String:
	var source: Node = registry if registry != null else get_node_or_null("/root/Registry")
	if source == null:
		return ""
	return source.call("get_lore", &"component", id)


func component_kind(id: StringName) -> StringName:
	var component: SpellComponent = _component(id)
	return component.kind() if component != null else &""


## The spell registered under `tag`, or null when its generation is gone.
func profile(tag: int) -> CompiledSpell:
	return _profiles.get(tag)


## Registers every spell of `compiled` under a new generation of this player's staff and
## returns the tag of its first spell, or 0 for an empty staff (the staff then has no build)
## or a bad player or staff. The staff's generation advances; if its shots from 8 builds ago are
## still in the air the oldest generation is revoked (see `revoked_tags`).
func begin_generation(player: int, staff: int, compiled: CompiledStaff) -> int:
	revoked_tags.clear()
	if compiled == null or not _in_range(player, staff) or compiled.nodes.size() > SpellTag.NODE_MASK + 1:
		return 0
	var index: int = player * SpellLimits.STAFFS + staff
	_release_hold(index)
	var old: int = _current[index]
	if compiled.is_empty():
		_installed[index] = null
		_cursor[index] = 0
		_current[index] = -1
		if old >= 0:
			_release_generation(player, staff, old)
		return 0
	var generation: int = (old + 1) % SpellLimits.GENERATIONS
	_current[index] = generation
	var key: int = SpellTag.generation_key(SpellTag.make(player, staff, 0, generation))
	for node in _node_counts.get(key, 0):
		var stale: int = SpellTag.make(player, staff, node, generation)
		if _live.get(stale, 0) > 0:
			revoked_tags.append(stale)
		_profiles.erase(stale)
		_live.erase(stale)
	_generation_live.erase(key)
	for spell in compiled.nodes:
		_profiles[SpellTag.make(player, staff, spell.node, generation)] = spell
	_node_counts[key] = compiled.nodes.size()
	_installed[index] = compiled
	_cursor[index] = 0
	if old >= 0:
		_release_generation(player, staff, old)
	return SpellTag.make(player, staff, 0, generation)


## The tag of the current build of this staff at `node`, or 0 when it has no build.
func current_tag(player: int, slot: int, node: int = 0) -> int:
	if not _in_range(player, slot):
		return 0
	var generation: int = _current[player * SpellLimits.STAFFS + slot]
	return 0 if generation < 0 else SpellTag.make(player, slot, node, generation)


## A shot with `tag` was spawned. Ignored for a tag that has no spell.
func shot_started(tag: int) -> void:
	if _profiles.has(tag):
		_live[tag] = _live.get(tag, 0) + 1
		var key: int = SpellTag.generation_key(tag)
		_generation_live[key] = _generation_live.get(key, 0) + 1


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
	else:
		_live[tag] = live - 1
	var key: int = SpellTag.generation_key(tag)
	var in_air: int = _generation_live.get(key, 0) - 1
	if in_air > 0:
		_generation_live[key] = in_air
		return
	_generation_live.erase(key)
	if not _is_current(tag):
		_erase_generation(tag)


## Live shots counted for `tag`.
func live_shots(tag: int) -> int:
	return _live.get(tag, 0)


## Generations of this staff that still have spells registered (the current one and any
## older ones with shots in the air).
func generations_held(player: int, slot: int) -> int:
	var count: int = 0
	if not _in_range(player, slot):
		return 0
	for generation in SpellLimits.GENERATIONS:
		if _node_counts.has(SpellTag.generation_key(SpellTag.make(player, slot, 0, generation))):
			count += 1
	return count


## What one hit of a shot with `tag` does, or null when the tag is no spell's (an enemy's
## shot) or its generation is gone. Shared and read-only; allocates nothing.
func hit_profile(tag: int) -> HitProfile:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return null
	# A relay shot that passed a teammate hits with what it took on (the hit being sent names its slot).
	var slot: int = projectiles.event_slot if projectiles != null else -1
	if slot >= 0 and slot < _rec_relay.size() and _rec_relay[slot] != null and _same(slot) and projectiles.get_tag_of(slot) == tag:
		return _rec_relay[slot]
	return spell.hit


## Makes `compiled` (from `compile_staff`) the build of this player's staff (0-3), starting its
## cycle at the first cast, and removes the shots the new generation revoked. Editing a staff
## switches its sustained (`hold`) carriers off. Returns the tag of its first spell, or 0 for an
## empty staff (which leaves the staff with no build) or a bad player or staff.
func install_staff(player: int, staff: int, compiled: CompiledStaff) -> int:
	var tag: int = begin_generation(player, staff, compiled)
	if projectiles != null:
		for revoked in revoked_tags:
			projectiles.remove_by_tag(revoked)
	return tag


## Seconds before this player's staff may cast again.
func cooldown_left(player: int, slot: int) -> float:
	return _cooldown[player * SpellLimits.STAFFS + slot] if _in_range(player, slot) else 0.0


## Which cast of its cycle this player's staff makes next (0 after a recharge).
func cast_index(player: int, staff: int) -> int:
	return _cursor[player * SpellLimits.STAFFS + staff] if _in_range(player, staff) else 0


## The carrier (form id) of the last cast this player's staff made, `&""` before any or for a
## cast with no carrier (cards that landed on the caster). The player sends it with `spell_cast`.
func last_form(player: int, staff: int) -> StringName:
	return _last_form[player * SpellLimits.STAFFS + staff] if _in_range(player, staff) else &""


## True while this player's staff has sustained (`hold`) carriers switched on.
func is_holding(player: int, staff: int) -> bool:
	return _in_range(player, staff) and not _hold_tags[player * SpellLimits.STAFFS + staff].is_empty()


## Fires the next cast of this player's staff from `origin` along `direction`. `mana` is what
## the caster has. Returns the mana spent (0.0 or more) when it fired, or `REFUSED` when it did
## not (nothing built, still in its delay, too little mana, no direction, or every shot starting
## inside a wall); the caller then takes that much mana and reads no field. A refused cast
## changes nothing, except that a cast with nothing in it (every card wasted) still moves the
## staff on, so it never sticks there.
##
## While the staff has sustained (`hold`) carriers on, a cast switches them all off instead,
## frees their reservation and returns 0.0. The caller decides which presses may do that (a
## held button should not switch on and off again and again).
func cast_staff(player: int, staff: int, origin: Vector2, direction: Vector2, mana: float) -> float:
	if projectiles == null or not _in_range(player, staff) or not origin.is_finite():
		return REFUSED
	if not direction.is_finite() or direction.is_zero_approx():
		return REFUSED
	var index: int = player * SpellLimits.STAFFS + staff
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty() or _cooldown[index] > 0.0:
		return REFUSED
	if not _hold_tags[index].is_empty():
		_release_hold(index)
		_cooldown[index] = compiled.staff.cast_delay if compiled.staff != null else 0.0
		return 0.0
	var cast: CompiledCast = compiled.casts[mini(_cursor[index], compiled.casts.size() - 1)]
	if mana < cast.mana:
		return REFUSED
	var aim: Vector2 = direction.normalized()
	if cast.group.is_empty():
		_after_cast(index, compiled, cast)
		return REFUSED
	if _launch_group(cast.group, player, staff, _current[index], origin, aim, null) == 0:
		return REFUSED
	_after_cast(index, compiled, cast)
	_start_hold(index, player, staff, cast)
	_last_infused[player] = null
	for carrier in cast.group.spells:
		if not carrier.element_ids.is_empty():
			_last_infused[player] = carrier
			break
	var first: CompiledSpell = cast.group.spells[0]
	_last_form[index] = first.form_id
	var combo: StringName = combo_class(first)
	if events != null and combo != &"" and first.fallback == CompiledSpell.FALLBACK_NONE:
		events.combo_cast.emit(player, combo, origin, aim, first.tint)
	return cast.mana


## The delay and the next cast of the cycle, after `cast` fired (or had nothing in it).
func _after_cast(index: int, compiled: CompiledStaff, cast: CompiledCast) -> void:
	_cooldown[index] = cast.delay
	_cursor[index] = 0 if cast.recharges else (_cursor[index] + 1) % compiled.casts.size()


## Which kind of combination a compiled spell is, for the look of its cast (`combo_cast`):
## `&"stacked"` for a trigger with two or more modifiers or a chain of three spells,
## otherwise the event of its trigger (`&"on_hit"`, `&"on_expire"`, `&"timer"`), otherwise
## `&"boosted"` for modifiers alone, and `&""` for a plain shot.
func combo_class(spell: CompiledSpell) -> StringName:
	if spell == null:
		return &""
	if spell.payload != null:
		if spell.modifier_ids.size() >= 2 or spell.chain_length() >= 3:
			return &"stacked"
		match spell.trigger_event:
			TriggerBase.Event.EXPIRE:
				return &"on_expire"
			TriggerBase.Event.TIMER:
				return &"timer"
		return &"on_hit"
	return &"boosted" if not spell.modifier_ids.is_empty() else &""


## Runs the cooldowns and the timer triggers by `delta` seconds, and opens a new step for
## the fire and jump caps. The autoload calls it every physics step; the order of the two
## autoloads in project.godot (Projectiles first) is what makes it run after the manager.
## So a cap's window is this step's timer fires plus the next step's hits, and a `cast` made
## between the two (a beam's on-expire spell, a player's own cast) counts against whichever
## window is open.
func step(delta: float) -> void:
	for c in _cooldown.size():
		_cooldown[c] = maxf(_cooldown[c] - delta, 0.0)
	_fires_used.fill(0)
	_chains_used.fill(0)
	var i: int = 0
	while i < _timer_count:
		var slot: int = _timers[i]
		if not _knows(slot) or not _is_timer(slot):
			_rec_timed[slot] = 0
			_timer_count -= 1
			_timers[i] = _timers[_timer_count]
			continue
		_rec_clock[slot] -= delta
		if _rec_clock[slot] <= 0.0:
			_fire_timer(slot)
		if _rec_fires[slot] <= 0:
			_rec_timed[slot] = 0
			_timer_count -= 1
			_timers[i] = _timers[_timer_count]
			continue
		i += 1


## The shots made by one launch of `spell`, returned as how many were made (a beam counts
## as one). `source` is the target that fired the trigger, or null.
func _launch(spell: CompiledSpell, tag: int, player: int, origin: Vector2, direction: Vector2, source: Node, chain: int = -1, prev: int = 0) -> int:
	var count: int = spell.shots
	var made: int = 0
	var carried: int = spell.chain_jumps if chain < 0 else chain
	var lifetime: float = SpellLimits.HOLD_LIFETIME if spell.behaviour(ModifierBase.Behaviour.HOLD) > 0.0 else spell.lifetime
	if spell.motion == FormBase.Motion.DASH:
		# The wizard moves, not a shot: the player picks the way (the way it walks) and answers
		# with `caster_move_finished` where it stops (staffs A6a).
		if events != null:
			events.caster_move_requested.emit(player, &"dash", origin + direction * spell.speed * spell.lifetime, spell.lifetime, tag)
		return 1
	var base: float = direction.angle()
	if spell.motion == FormBase.Motion.RAY and spell.homing_turn > 0.0:
		direction = projectiles.homing_aim(player, origin, direction, deg_to_rad(30.0), ProjectilesScript.LAYER_ENEMY)
		base = direction.angle()
	for n in count:
		var angle: float = base + _fan_angle(n, count, spell)
		var heading: Vector2 = Vector2.from_angle(angle)
		if spell.motion == FormBase.Motion.RAY:
			_shoot_ray(spell, tag, player, origin, heading, carried, prev, source)
			made += 1
			continue
		var slot: int = -1
		match spell.motion:
			FormBase.Motion.ORBIT:
				var turn: float = SpellLimits.ORBIT_TURN
				if spell.speed > 0.0 and spell.orbit_radius > 0.0:
					turn = spell.speed / spell.orbit_radius
				slot = projectiles.spawn_orbit(player, spell.orbit_radius, base + TAU * n / count, turn, lifetime, spell.radius, ProjectilesScript.LAYER_ENEMY, spell.pierce, tag)
			FormBase.Motion.STILL:
				var at: Vector2 = origin if count == 1 else origin + heading * spell.radius * 2.0
				slot = projectiles.spawn(player, at, Vector2.ZERO, lifetime, spell.radius, ProjectilesScript.LAYER_ENEMY, spell.pierce, tag, ProjectilesScript.MOTION_STILL)
			_:
				slot = projectiles.spawn(player, origin, heading * spell.speed, lifetime, spell.radius, ProjectilesScript.LAYER_ENEMY, spell.pierce, tag)
				if slot >= 0 and spell.homing_turn > 0.0:
					projectiles.set_homing(slot, spell.homing_turn)
				if slot >= 0:
					_apply_travel(slot, spell)
		if slot < 0:
			continue
		made += 1
		_register(slot, tag, spell, spell.trigger_max_fires, carried, prev)
		if source != null:
			projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	# The ring is only a cue, drawn once, and only when a shot really flew.
	if events != null and made > 0 and count > 1 and spell.spread >= 360.0 and spell.motion == FormBase.Motion.STRAIGHT:
		events.form_shown.emit(player, &"nova", origin, direction, 0.0, spell.tint)
	return made


## Hand a flying shot the behaviours of its cards that the projectile manager runs (staffs B1).
## A plain shot costs one comparison per behaviour and no call.
func _apply_travel(slot: int, spell: CompiledSpell) -> void:
	if spell.motion == FormBase.Motion.RETURN:
		projectiles.set_return(slot)
	if spell.behaviours.is_empty():
		return
	var bounce: float = spell.behaviour(ModifierBase.Behaviour.BOUNCE)
	if bounce > 0.0:
		projectiles.set_bounce(slot, roundi(bounce))
	if spell.behaviour(ModifierBase.Behaviour.GHOST) > 0.0:
		projectiles.set_ghost(slot)
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL)
	if spiral > 0.0:
		projectiles.set_spiral(slot, spiral)
	var linger: float = spell.behaviour(ModifierBase.Behaviour.LINGER)
	if linger > 0.0:
		projectiles.set_linger(slot, linger)
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	if growth > 1.0:
		projectiles.set_growth(slot, growth)
	var sticky: float = spell.behaviour(ModifierBase.Behaviour.STICKY)
	if sticky > 0.0:
		projectiles.set_sticky(slot, sticky)
	var shield: float = spell.behaviour(ModifierBase.Behaviour.SHIELD)
	if shield > 0.0:
		projectiles.set_shield(slot, roundi(shield))


## The shots of every spell of `group`, fired together from `origin` along `direction` by this
## player's staff in its `generation` (each spell's tag names its node); returns how many were
## made (a fallback counts as one). Two or more carriers of one group fan out a little
## (`SpellLimits.MULTICAST_SPREAD` degrees apart). A fallback asks for an area hit on the spot:
## the caster's for a cast, the payload's origin for a payload. `source` is the target that
## fired the payload, or null.
func _launch_group(group: CompiledGroup, player: int, staff: int, generation: int, origin: Vector2, direction: Vector2, source: Node) -> int:
	var made: int = 0
	var carriers: int = 0
	for spell in group.spells:
		if spell.fallback == CompiledSpell.FALLBACK_NONE:
			carriers += 1
	var k: int = 0
	for spell in group.spells:
		var tag: int = SpellTag.make(player, staff, spell.node, generation)
		if spell.fallback != CompiledSpell.FALLBACK_NONE:
			made += _fallback_hit(spell, tag, player, origin)
			continue
		var heading: Vector2 = direction
		if carriers > 1:
			heading = direction.rotated(deg_to_rad(SpellLimits.MULTICAST_SPREAD) * (float(k) / (carriers - 1) - 0.5) * (carriers - 1))
		k += 1
		var launched: int = _launch(spell, tag, player, origin, heading, source)
		made += launched
		# `on cast`: the payload leaves at once, from where the carrier did.
		if launched > 0 and spell.payload != null and spell.trigger_event == TriggerBase.Event.CAST and _take_fire(player):
			_launch_group(spell.payload, player, staff, generation, origin, heading, source)
	return made


## The cards that landed on the caster or on a payload's origin: an area hit there with the
## spell's profile (a blast is as wide as its strength). Combat decides what it does (staffs B3).
func _fallback_hit(spell: CompiledSpell, tag: int, player: int, at: Vector2) -> int:
	if events != null:
		events.area_hit_requested.emit(player, at, maxf(spell.radius, spell.behaviour(ModifierBase.Behaviour.BLAST)), tag)
	return 1


## Degrees (as radians) off the aim of shot `n` of `count`: none for one shot, an even ring
## for a 360 degree spread, otherwise an even fan centred on the aim.
func _fan_angle(n: int, count: int, spell: CompiledSpell) -> float:
	if count <= 1 or spell.motion == FormBase.Motion.ORBIT:
		return 0.0
	if spell.spread >= 360.0:
		return TAU * n / count
	return deg_to_rad(spell.spread) * (float(n) / (count - 1) - 0.5)


## Gives the manager's shot in `slot` its record and counts it.
func _register(slot: int, tag: int, spell: CompiledSpell, fires: int, chain: int, prev: int) -> void:
	projectiles.set_core(slot, spell.tint)
	projectiles.set_look(slot, spell.look)
	if _rec_seq.size() < projectiles.get_cap():
		var size: int = projectiles.get_cap()
		var old_size: int = _rec_seq.size()
		_rec_seq.resize(size)
		for at in range(old_size, size):
			_rec_seq[at] = -1
		_rec_fires.resize(size)
		_rec_chain.resize(size)
		_rec_clock.resize(size)
		_rec_prev.resize(size)
		_rec_timed.resize(size)
		_rec_hurt.resize(size)
		_rec_relay.resize(size)
		_hurt_slots.resize(size)
	_rec_relay[slot] = null
	_rec_seq[slot] = projectiles.get_seq_of(slot)
	_rec_fires[slot] = fires
	_rec_chain[slot] = chain
	_rec_prev[slot] = prev
	_rec_clock[slot] = spell.trigger_interval
	shot_started(tag)
	if spell.payload != null and spell.trigger_event == TriggerBase.Event.TIMER:
		# A shot that ended and was replaced in this slot before `step` is still listed once.
		if _rec_timed[slot] == 0:
			if _timer_count == _timers.size():
				_timers.resize(_timers.size() * 2)
			_timers[_timer_count] = slot
			_timer_count += 1
			_rec_timed[slot] = 1
	if spell.payload != null and spell.trigger_event == TriggerBase.Event.HURT and _rec_hurt[slot] == 0:
		_hurt_slots[_hurt_count] = slot
		_hurt_count += 1
		_rec_hurt[slot] = 1


## One beam: counted while it is cast, with its context set for the hit handler.
func _shoot_ray(spell: CompiledSpell, tag: int, player: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, length: float = -1.0, pierce: int = -1) -> void:
	shot_started(tag)
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_fires: int = _ray_fires
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	_ray_tag = tag
	_ray_dir = heading
	_ray_fires = spell.trigger_max_fires
	_ray_chain = chain
	_ray_prev = prev
	var reach: float = spell.ray_length if length < 0.0 else length
	var got: float = projectiles.ray(player, origin, heading, reach, spell.pierce if pierce < 0 else pierce, ProjectilesScript.LAYER_ENEMY, tag, spell.radius * 0.5, source)
	if got > 0.0 and events != null:
		events.form_shown.emit(player, &"beam", origin, heading, got, spell.tint)
	# A `ray()` that did nothing (too deep, or a bad aim) has no end to fire the payload from.
	if got > 0.0 and spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE and _ray_fires > 0 and _take_fire(player):
		_ray_fires -= 1
		_fire_payload(spell, tag, player, origin + heading * got, heading, null)
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_fires = saved_fires
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	shot_ended(tag)
	_cast_jumps()


## Casts the queued beam jumps, if this is the outermost beam. Each jump's own jumps join the
## end of the queue, so the chain runs as a loop, one `ray()` deep per jump.
func _cast_jumps() -> void:
	if _jq_busy:
		return
	_jq_busy = true
	while _jq_count > 0:
		var at: int = _jq_head
		_jq_head = (_jq_head + 1) % JUMP_QUEUE
		_jq_count -= 1
		var spell: CompiledSpell = _jq_spell[at]
		var target: Node2D = _jq_target[at]
		_jq_spell[at] = null
		_jq_target[at] = null
		if spell == null or not is_instance_valid(target):
			continue
		_shoot_ray(spell, _jq_tag[at], _jq_player[at], _jq_pos[at], _jq_dir[at], _jq_chain[at], _jq_prev[at], target, _jq_len[at], 0)
	_jq_busy = false


## True when the shot in `slot` fires its payload on a timer.
func _is_timer(slot: int) -> bool:
	var spell: CompiledSpell = _profiles.get(projectiles.get_tag_of(slot))
	return spell != null and spell.payload != null and spell.trigger_event == TriggerBase.Event.TIMER


## Fires the payload of `spell` (whose shot has `tag`) from `at` along `heading`, in the same
## player's staff and generation as the shot.
func _fire_payload(spell: CompiledSpell, tag: int, player: int, at: Vector2, heading: Vector2, source: Node) -> int:
	return _launch_group(spell.payload, player, SpellTag.staff_of(tag), SpellTag.generation_of(tag), at, heading, source)


## True when this player may fire one more payload in this step.
func _take_fire(player: int) -> bool:
	if _fires_used[player] >= SpellLimits.MAX_FIRES_PER_STEP:
		fires_dropped += 1
		return false
	_fires_used[player] += 1
	return true


## True when the record of `slot` was made for the shot the manager last had there (it may
## have ended just now).
func _same(slot: int) -> bool:
	return slot >= 0 and slot < _rec_seq.size() and _rec_seq[slot] == projectiles.get_seq_of(slot)


## True when `slot` holds a live shot this record was made for.
func _knows(slot: int) -> bool:
	return _same(slot) and projectiles.is_alive(slot)


## The way a payload fired by a shot goes: its velocity, or outward from the caster
## through the shot for an orbit or still one (or one with no velocity).
func _heading(spell: CompiledSpell, slot: int, at: Vector2, player: int) -> Vector2:
	var velocity: Vector2 = projectiles.get_velocity_of(slot)
	if spell.motion == FormBase.Motion.ORBIT or spell.motion == FormBase.Motion.STILL or velocity.is_zero_approx():
		var anchor: Vector2 = projectiles.get_anchor(player)
		if anchor.is_finite() and not (at - anchor).is_zero_approx():
			return (at - anchor).normalized()
	return Vector2.RIGHT if velocity.is_zero_approx() else velocity.normalized()


func _fire_timer(slot: int) -> void:
	var tag: int = projectiles.get_tag_of(slot)
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.payload == null:
		_rec_fires[slot] = 0
		return
	var player: int = SpellTag.player_of(tag)
	_rec_clock[slot] += spell.trigger_interval
	if not _take_fire(player):
		return
	_rec_fires[slot] -= 1
	var at: Vector2 = projectiles.get_position_of(slot)
	_fire_payload(spell, tag, player, at, _heading(spell, slot, at, player), null)


func _on_hit(player: int, target: Node, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or player < 0 or player >= SpellLimits.PLAYERS:
		return
	var slot: int = projectiles.event_slot
	var fires: int = spell.trigger_max_fires
	var chain: int = spell.chain_jumps
	var prev: int = 0
	var heading: Vector2 = Vector2.RIGHT
	var by_ray: bool = slot < 0
	if by_ray:
		if tag != _ray_tag:
			return
		fires = _ray_fires
		chain = _ray_chain
		prev = _ray_prev
		heading = _ray_dir
	else:
		if _same(slot):
			fires = _rec_fires[slot]
			chain = _rec_chain[slot]
			prev = _rec_prev[slot]
		heading = _heading(spell, slot, position, player)
	var held: bool = spell.payload != null and spell.trigger_event == TriggerBase.Event.HIT and fires > 0 and _take_fire(player)
	if held:
		fires -= 1
	# Write the record back before spawning: a shot that has ended may lose its slot to a child.
	if by_ray:
		_ray_fires = fires
	elif _same(slot):
		_rec_fires[slot] = fires
	var struck: int = target.get_instance_id()
	if held:
		_fire_payload(spell, tag, player, position, heading, target)
	if chain > 0:
		_jump(spell, tag, player, position, target as Node2D, struck, prev, fires, chain - 1, by_ray)


## Sends a chain on from `position` to the nearest other target, if there is one in range.
func _jump(spell: CompiledSpell, tag: int, player: int, position: Vector2, target: Node2D, struck: int, prev: int, fires: int, chain: int, by_ray: bool) -> void:
	if _chains_used[player] >= SpellLimits.MAX_CHAINS_PER_STEP:
		chains_dropped += 1
		return
	var before: Node2D = null
	if prev != 0:
		before = instance_from_id(prev) as Node2D
	var best: Node2D = projectiles.nearest_target(position, SpellLimits.CHAIN_RANGE, ProjectilesScript.LAYER_ENEMY, target, before)
	if best == null:
		return
	var aim: Vector2 = projectiles.nearest_point
	if not aim.is_finite() or aim.is_equal_approx(position):
		return
	_chains_used[player] += 1
	var along: Vector2 = position.direction_to(aim)
	var distance: float = position.distance_to(aim)
	if by_ray:
		if _jq_count >= JUMP_QUEUE:
			chains_dropped += 1
			return
		var end: int = (_jq_head + _jq_count) % JUMP_QUEUE
		_jq_count += 1
		_jq_spell[end] = spell
		_jq_target[end] = target
		_jq_tag[end] = tag
		_jq_player[end] = player
		_jq_pos[end] = position
		_jq_dir[end] = along
		_jq_len[end] = distance + spell.radius + 8.0
		_jq_chain[end] = chain
		_jq_prev[end] = struck
		return
	var speed: float = maxf(spell.speed, SpellLimits.CHAIN_MIN_SPEED)
	var life: float = (distance + 16.0) / speed * 1.5 + 0.05
	var slot: int = projectiles.spawn(player, position, along * speed, life, spell.radius, ProjectilesScript.LAYER_ENEMY, 0, tag)
	if slot < 0:
		return
	_register(slot, tag, spell, fires, chain, struck)
	projectiles.exclude(slot, target, SpellLimits.SOURCE_EXCLUSION)


func _on_expired(player: int, position: Vector2, tag: int) -> void:
	var event: int = TriggerBase.Event.EXPIRE
	var spell: CompiledSpell = _profiles.get(tag)
	if spell != null and spell.trigger_event == TriggerBase.Event.WALL and projectiles.expired_on_wall:
		event = TriggerBase.Event.WALL
	_fire_event(event, player, position, tag, null, true)


func _on_shot_blocked(player: int, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, player, position, tag, null)


func _on_shield_blocked(player: int, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, player, position, tag, null)


func _on_kill(player: int, target: Node, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.KILL, player, position, tag, target if is_instance_valid(target) else null)


func _on_reaction(player: int, _reaction_id: StringName, target: Node, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.REACTION, player, position, tag, target if is_instance_valid(target) else null)


func _on_ally(player: int, ally: Node, position: Vector2, tag: int) -> void:
	if not is_instance_valid(ally):
		return
	_relay(player, projectiles.target_owner_of(ally), tag)
	_fire_event(TriggerBase.Event.ALLY, player, position, tag, ally)


## Fires the payload of the shot with `tag` from `at`, when that shot's trigger is `event` (the
## shared way of the events that name a shot's tag). When the event is being sent for that
## very shot, its record limits how often it fires. `back_off` pulls the point out of a wall.
func _fire_event(event: int, player: int, at: Vector2, tag: int, source: Node, back_off: bool = false) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.payload == null or spell.trigger_event != event:
		return
	if player < 0 or player >= SpellLimits.PLAYERS:
		return
	var slot: int = projectiles.event_slot
	if slot >= 0 and (not _same(slot) or projectiles.get_tag_of(slot) != tag):
		slot = -1
	var fires: int = spell.trigger_max_fires
	if slot >= 0:
		fires = _rec_fires[slot]
	if fires <= 0 or not _take_fire(player):
		return
	if slot >= 0:
		_rec_fires[slot] = fires - 1
	var heading: Vector2 = _heading(spell, slot, at, player)
	if back_off:
		at -= heading * SpellLimits.EXPIRE_BACKOFF
	_fire_payload(spell, tag, player, at, heading, source)


## `on hurt`: every live carrier of `player` with that trigger fires its payload from where
## the wizard was hurt.
func _on_hurt(player: int, _amount: int, position: Vector2, _tag: int, _kind: StringName) -> void:
	if player < 0 or player >= SpellLimits.PLAYERS or _hurt_count == 0:
		return
	var i: int = 0
	while i < _hurt_count:
		var slot: int = _hurt_slots[i]
		var spell: CompiledSpell = null
		if _knows(slot):
			spell = _profiles.get(projectiles.get_tag_of(slot))
		if spell == null or spell.payload == null or spell.trigger_event != TriggerBase.Event.HURT or _rec_fires[slot] <= 0:
			_rec_hurt[slot] = 0
			_hurt_count -= 1
			_hurt_slots[i] = _hurt_slots[_hurt_count]
			continue
		i += 1
	# Payloads may start more such shots; they sit past `count` and wait for the next hurt.
	var count: int = _hurt_count
	for n in count:
		var slot: int = _hurt_slots[n]
		var tag: int = projectiles.get_tag_of(slot)
		if SpellTag.player_of(tag) != player or _rec_fires[slot] <= 0 or not _take_fire(player):
			continue
		var spell: CompiledSpell = _profiles[tag]
		_rec_fires[slot] -= 1
		_fire_payload(spell, tag, player, position, _heading(spell, slot, projectiles.get_position_of(slot), player), null)


## `relay`: a shot with it that passes the teammate `ally_player` takes on the infusions of
## that player's last cast: their elements join the hit, and the status is theirs if the shot
## had none. Allocates one profile per pass, never per frame.
func _relay(player: int, ally_player: int, tag: int) -> void:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.behaviour(ModifierBase.Behaviour.RELAY) <= 0.0:
		return
	if ally_player < 0 or ally_player >= SpellLimits.PLAYERS or ally_player == player:
		return
	var slot: int = projectiles.event_slot
	var donor: CompiledSpell = _last_infused[ally_player]
	if donor == null or slot < 0 or not _same(slot) or projectiles.get_tag_of(slot) != tag:
		return
	var base: HitProfile = _rec_relay[slot] if _rec_relay[slot] != null else spell.hit
	var merged: HitProfile = HitProfile.new()
	merged.damage = base.damage
	merged.knockback = base.knockback
	merged.element_id = base.element_id
	merged.element_ids = base.element_ids.duplicate()
	merged.status_id = base.status_id
	merged.status_duration = base.status_duration
	merged.status_strength = base.status_strength
	var added: bool = false
	for id in donor.element_ids:
		if not merged.element_ids.has(id):
			merged.element_ids.append(id)
			added = true
	if not added:
		return
	if merged.element_id == &"":
		merged.element_id = donor.element_id
		projectiles.set_core(slot, donor.tint)
	if merged.status_id == &"":
		merged.status_id = donor.status_id
		merged.status_duration = donor.status_duration
		merged.status_strength = donor.status_strength
	_rec_relay[slot] = merged


## Forgets every registered spell and shot count (a new run, and tests).
func clear() -> void:
	_cooldown.fill(0.0)
	_fires_used.fill(0)
	_chains_used.fill(0)
	_jq_head = 0
	_jq_count = 0
	_timer_count = 0
	_rec_seq.fill(-1)
	_rec_timed.fill(0)
	_rec_hurt.fill(0)
	_hurt_count = 0
	_rec_relay.fill(null)
	_last_infused.fill(null)
	fires_dropped = 0
	chains_dropped = 0
	_current.fill(-1)
	_cursor.fill(0)
	_hold_mana.fill(0.0)
	for i in _installed.size():
		_installed[i] = null
		_hold_tags[i].clear()
	_node_counts.clear()
	_profiles.clear()
	_live.clear()
	_generation_live.clear()
	revoked_tags.clear()


func _in_range(player: int, staff: int) -> bool:
	return player >= 0 and player < SpellLimits.PLAYERS and staff >= 0 and staff < SpellLimits.STAFFS


func _is_current(tag: int) -> bool:
	var index: int = SpellTag.player_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	return _current[index] == SpellTag.generation_of(tag)


## Erases the profiles of every node of the tag's generation.
func _erase_generation(tag: int) -> void:
	var key: int = SpellTag.generation_key(tag)
	for node in _node_counts.get(key, 0):
		_profiles.erase(SpellTag.make(SpellTag.player_of(tag), SpellTag.staff_of(tag), node, SpellTag.generation_of(tag)))
	_node_counts.erase(key)


## The old generation is no longer current: free it now if none of its shots is in the air.
func _release_generation(player: int, staff: int, generation: int) -> void:
	var key: int = SpellTag.generation_key(SpellTag.make(player, staff, 0, generation))
	if _generation_live.get(key, 0) == 0:
		_erase_generation(key)


## After a cast: its sustained (`hold`) carriers that made shots stay on and reserve the cast's
## mana until they are switched off (`cast_staff` again, an edit) or their last shot ends.
func _start_hold(index: int, player: int, staff: int, cast: CompiledCast) -> void:
	var tags: PackedInt64Array = _hold_tags[index]
	for spell in cast.group.spells:
		if spell.fallback == CompiledSpell.FALLBACK_NONE and spell.behaviour(ModifierBase.Behaviour.HOLD) > 0.0:
			var tag: int = SpellTag.make(player, staff, spell.node, _current[index])
			if _live.get(tag, 0) > 0:
				tags.append(tag)
	if not tags.is_empty():
		_hold_mana[index] = cast.mana
		_send_reserved(player)


## Switches off the sustained carriers of this staff: their shots go, their mana is free.
func _release_hold(index: int) -> void:
	if _hold_tags[index].is_empty():
		return
	var tags: PackedInt64Array = _hold_tags[index].duplicate()
	_hold_tags[index].clear()
	_hold_mana[index] = 0.0
	if projectiles != null:
		for tag in tags:
			# remove_by_tag sends no shot_ended, so the counts are ended here.
			for _n in projectiles.remove_by_tag(tag):
				shot_ended(tag)
	_send_reserved(floori(float(index) / SpellLimits.STAFFS))


## The last shot of `tag` ended: if it was a sustained carrier, it is off now.
func _end_hold_of(tag: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var index: int = SpellTag.player_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	var at: int = _hold_tags[index].find(tag)
	if at < 0:
		return
	_hold_tags[index].remove_at(at)
	if _hold_tags[index].is_empty():
		_hold_mana[index] = 0.0
		_send_reserved(SpellTag.player_of(tag))


## Mana this player's sustained carriers hold, over all their staffs.
func reserved_mana(player: int) -> float:
	var total: float = 0.0
	if player >= 0 and player < SpellLimits.PLAYERS:
		for staff in SpellLimits.STAFFS:
			total += _hold_mana[player * SpellLimits.STAFFS + staff]
	return total


func _send_reserved(player: int) -> void:
	if events != null:
		events.mana_reserved.emit(player, reserved_mana(player))


func _component(id: StringName) -> SpellComponent:
	var source: Node = registry if registry != null else get_node_or_null("/root/Registry")
	if source == null:
		return null
	return source.call("get_resource", &"spells", id) as SpellComponent


func _name_of(component: SpellComponent) -> String:
	return component.display_name if not component.display_name.is_empty() else String(component.id)

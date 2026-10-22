extends Node
## The spell runtime (autoload `Spells`): the compiler, the limits and the tags (part 5),
## casting and triggers (part 6).
##
## Casting: `install(player, slot, spell)` makes a compiled spell the build of a slot
## (and removes the shots a full generation ring revoked); `cast(player, slot, origin,
## direction, mana)` fires it and returns the mana spent or `REFUSED`. Cooldowns are per player and slot and tick in `step` (physics). The
## form decides the shots (a fan for straight, a ring for orbit, still ones, or rays), split
## and nova have already multiplied them in `compile`, homing is set on each shot.
##
## Triggers: a held spell is fired by its shot's `projectile_hit` (on hit), `projectile_expired`
## (on expire) or every `trigger_interval` seconds (timer, in `step`). It starts at the hit
## point (the shot's place at expiry, a little back from a wall; the shot's place for a timer),
## flies along the shot's velocity (outward from the caster through the shot for an orbit or
## still shot, along the beam for a ray) and cannot hit the target that fired it for
## `SpellLimits.SOURCE_EXCLUSION` seconds (a beam never hits it). Each shot fires at most
## `trigger_max_fires` times. One player's triggers fire at most
## `SpellLimits.MAX_FIRES_PER_STEP` held spells per `step`; the rest are dropped, never
## queued (`fires_dropped` counts them). A beam fires an on-expire spell
## at its end and has no timer. Held spells send no `spell_cast`: the player's staff does.
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
## A recipe is a Dictionary of component ids (a held spell is a recipe too):
##
##     {"form": &"bolt", "element": &"fire", "modifiers": [&"split", &"homing"],
##      "trigger": &"on_hit", "held": {"form": &"nova"}}
##
## Only `form` is required; `element`, `modifiers`, `trigger` and `held` may be left out.
## `compile` never errors: a recipe that breaks a rule gives a spell with `valid == false`
## and a plain `reason`, and numbers over a limit are clamped and said so in `description`.
##
## Tags: `begin_generation(player, slot, spell)` registers a built spell under a new
## generation of that slot and returns the tag of its cast (depth 0); its held spells get
## the same tag with depth 1 and 2. Shots keep the tag they were born with, so a shot still
## in the air after a rebuild hits with its old numbers (`profile(tag)`). A generation is
## forgotten as a whole (all its depths together) when its last shot, of any depth, has
## ended (`shot_ended`) and it is no longer current.
##
## Order matters: a shot that spawns children (a held spell on hit) must call
## `shot_started` for each child before it calls `shot_ended` for itself, or an old build
## could be freed between the two.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

## What `cast` returns when the spell did not fire (cooling down, too little mana, no spell).
const REFUSED: float = -1.0

## Held spells dropped by the per-step fire cap since the last `clear`.
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

## How the description says a status (the ids belong to gameplay/combat).
const STATUS_VERBS: Dictionary = {
	&"burn": "Burns",
	&"chill": "Chills",
	&"freeze": "Freezes",
	&"shock": "Shocks",
	&"hex": "Hexes",
}

## Registry stand-in for tests: anything with `get_resource(folder, id)`. Null uses `Registry`.
var registry: Node = null

## player * SLOTS + slot -> the current generation (0-7)
var _current: PackedInt32Array = PackedInt32Array()
## tag -> CompiledSpell
var _profiles: Dictionary = {}
## tag -> live shots
var _live: Dictionary = {}
## generation key (the depth-0 tag) -> live shots of all depths of that generation
var _generation_live: Dictionary = {}

## player * SLOTS + slot -> seconds before that slot may cast again
var _cooldown: PackedFloat32Array = PackedFloat32Array()
## Held spells each player has fired in this step.
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
	_current.resize(SpellLimits.PLAYERS * SpellLimits.SLOTS)
	_current.fill(-1)
	_cooldown.resize(SpellLimits.PLAYERS * SpellLimits.SLOTS)
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
	projectiles = manager
	events = bus
	if projectiles != null:
		projectiles.shot_ended.connect(shot_ended)
	if events != null:
		events.projectile_hit.connect(_on_hit)
		events.projectile_expired.connect(_on_expired)


## Turns a recipe into a CompiledSpell. See the class doc for the recipe shape.
func compile(recipe: Dictionary) -> CompiledSpell:
	var spell: CompiledSpell = _compile(recipe, 0)
	if not spell.valid:
		return spell
	if spell.complexity > SpellLimits.MAX_COMPLEXITY:
		return _refused("Too complex: %d of %d." % [spell.complexity, SpellLimits.MAX_COMPLEXITY])
	_describe(spell)
	return spell


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


## What the builder shows of `recipe` at held level `level` (0 is the cast), as plain values so
## that nothing outside `core/spells` reads a `CompiledSpell`. Always has `valid` and
## `complexity` (of the whole spell, held spells included; 0 when invalid). When the recipe is
## valid and has a spell at `level` it also has `shown` true and `damage`, `shots`, `ray` (a beam:
## no shot count), `cooldown`, `mana`, `pattern` (`&"fan"`, `&"ring"`, `&"orbit"`, `&"rune"` or
## `&"ray"`), `spread` (degrees), `pierce` and `tint`; otherwise `shown` is false.
func builder_view(recipe: Dictionary, level: int) -> Dictionary:
	var whole: CompiledSpell = compile(recipe)
	var view: Dictionary = {"valid": whole.valid, "complexity": whole.complexity if whole.valid else 0, "shown": false}
	var spell: CompiledSpell = whole.at_depth(level) if whole.valid else null
	if spell == null:
		return view
	view["shown"] = true
	view["damage"] = spell.damage
	view["shots"] = spell.shots
	view["ray"] = spell.motion == FormBase.Motion.RAY
	view["cooldown"] = spell.cooldown
	view["mana"] = spell.mana_cost
	view["spread"] = spell.spread
	view["pierce"] = spell.pierce
	view["tint"] = spell.tint
	match spell.motion:
		FormBase.Motion.RAY:
			view["pattern"] = &"ray"
		FormBase.Motion.ORBIT:
			view["pattern"] = &"orbit"
		FormBase.Motion.STILL:
			view["pattern"] = &"rune"
		_:
			view["pattern"] = &"ring" if spell.spread >= 360.0 else &"fan"
	return view


## The one-line description of the component `id` for the builder. Empty until the first lore
## exists (M2 part 23 reads it from Story); the builder shows nothing for an empty one.
func component_description(_id: StringName) -> String:
	return ""


func component_kind(id: StringName) -> StringName:
	var component: SpellComponent = _component(id)
	return component.kind() if component != null else &""


## The spell registered under `tag`, or null when its generation is gone.
func profile(tag: int) -> CompiledSpell:
	return _profiles.get(tag)


## Registers `spell` (which must be valid) as the new build of this player's slot and
## returns the tag of its cast, or 0 for an invalid spell or a bad player or slot.
## The slot's generation advances; if its shots from 8 builds ago are still in the air the
## oldest generation is revoked (see `revoked_tags`).
func begin_generation(player: int, slot: int, spell: CompiledSpell) -> int:
	revoked_tags.clear()
	if spell == null or not spell.valid or not _in_range(player, slot):
		return 0
	var index: int = player * SpellLimits.SLOTS + slot
	var old: int = _current[index]
	var generation: int = (old + 1) % SpellLimits.GENERATIONS
	_current[index] = generation
	for depth in SpellLimits.MAX_DEPTH + 1:
		var tag: int = SpellTag.make(player, slot, depth, generation)
		if _live.get(tag, 0) > 0:
			revoked_tags.append(tag)
		_profiles.erase(tag)
		_live.erase(tag)
	_generation_live.erase(SpellTag.make(player, slot, 0, generation))
	var level: CompiledSpell = spell
	for depth in SpellLimits.MAX_DEPTH + 1:
		if level == null:
			break
		_profiles[SpellTag.make(player, slot, depth, generation)] = level
		level = level.held
	if old >= 0:
		_release_generation(player, slot, old)
	return SpellTag.make(player, slot, 0, generation)


## The tag of the current build of this slot at `depth`, or 0 when it was never built.
func current_tag(player: int, slot: int, depth: int = 0) -> int:
	if not _in_range(player, slot):
		return 0
	var generation: int = _current[player * SpellLimits.SLOTS + slot]
	return 0 if generation < 0 else SpellTag.make(player, slot, depth, generation)


## A shot with `tag` was spawned. Ignored for a tag that has no spell.
func shot_started(tag: int) -> void:
	if _profiles.has(tag):
		_live[tag] = _live.get(tag, 0) + 1
		var key: int = _generation_key(tag)
		_generation_live[key] = _generation_live.get(key, 0) + 1


## A shot with `tag` ended (hit, expired or was removed). The generation's spells (every
## depth) are freed once its last shot of any depth is gone and a newer build has replaced it.
func shot_ended(tag: int) -> void:
	var live: int = _live.get(tag, 0)
	if live <= 0:
		return
	if live == 1:
		_live.erase(tag)
	else:
		_live[tag] = live - 1
	var key: int = _generation_key(tag)
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


## Generations of this slot that still have a spell registered (the current one and any
## older ones with shots in the air).
func generations_held(player: int, slot: int) -> int:
	var count: int = 0
	if not _in_range(player, slot):
		return 0
	for generation in SpellLimits.GENERATIONS:
		if _profiles.has(SpellTag.make(player, slot, 0, generation)):
			count += 1
	return count


## What one hit of a shot with `tag` does, or null when the tag is no spell's (an enemy's
## shot) or its generation is gone. Shared and read-only; allocates nothing.
func hit_profile(tag: int) -> HitProfile:
	var spell: CompiledSpell = _profiles.get(tag)
	return null if spell == null else spell.hit


## Makes `spell` the build of this player's slot, as `begin_generation` does, and removes
## from the projectile manager the shots it revoked (see `revoked_tags`). Returns the tag of
## its cast, or 0 for an invalid spell or a bad player or slot.
func install(player: int, slot: int, spell: CompiledSpell) -> int:
	var tag: int = begin_generation(player, slot, spell)
	if tag != 0 and projectiles != null:
		for revoked in revoked_tags:
			projectiles.remove_by_tag(revoked)
	return tag


## Seconds before this player's slot may cast again.
func cooldown_left(player: int, slot: int) -> float:
	return _cooldown[player * SpellLimits.SLOTS + slot] if _in_range(player, slot) else 0.0


## Fires the spell built in this player's slot from `origin` along `direction`. `mana` is
## what the caster has. Returns the mana spent (0.0 or more) when the spell fired, or
## `REFUSED` when it did not (nothing built, cooling down, too little mana, no direction,
## or every shot starting inside a wall); the caller then takes that much mana and reads
## no field. A refused cast changes nothing.
func cast(player: int, slot: int, origin: Vector2, direction: Vector2, mana: float) -> float:
	if projectiles == null or not _in_range(player, slot) or not origin.is_finite():
		return REFUSED
	if not direction.is_finite() or direction.is_zero_approx():
		return REFUSED
	var tag: int = current_tag(player, slot)
	var spell: CompiledSpell = _profiles.get(tag)
	var index: int = player * SpellLimits.SLOTS + slot
	if spell == null or _cooldown[index] > 0.0 or mana < spell.mana_cost:
		return REFUSED
	if _launch(spell, tag, player, origin, direction.normalized(), null) == 0:
		return REFUSED
	_cooldown[index] = spell.cooldown
	return spell.mana_cost


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
				slot = projectiles.spawn_orbit(player, spell.orbit_radius, base + TAU * n / count, turn, spell.lifetime, spell.radius, ProjectilesScript.LAYER_ENEMY, spell.pierce, tag)
			FormBase.Motion.STILL:
				var at: Vector2 = origin if count == 1 else origin + heading * spell.radius * 2.0
				slot = projectiles.spawn(player, at, Vector2.ZERO, spell.lifetime, spell.radius, ProjectilesScript.LAYER_ENEMY, spell.pierce, tag, ProjectilesScript.MOTION_STILL)
			_:
				slot = projectiles.spawn(player, origin, heading * spell.speed, spell.lifetime, spell.radius, ProjectilesScript.LAYER_ENEMY, spell.pierce, tag)
				if slot >= 0 and spell.homing_turn > 0.0:
					projectiles.set_homing(slot, spell.homing_turn)
		if slot < 0:
			continue
		made += 1
		_register(slot, tag, spell, spell.trigger_max_fires, carried, prev)
		if source != null:
			projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	return made


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
	_rec_seq[slot] = projectiles.get_seq_of(slot)
	_rec_fires[slot] = fires
	_rec_chain[slot] = chain
	_rec_prev[slot] = prev
	_rec_clock[slot] = spell.trigger_interval
	shot_started(tag)
	if spell.held != null and spell.trigger_event == TriggerBase.Event.TIMER:
		# A shot that ended and was replaced in this slot before `step` is still listed once.
		if _rec_timed[slot] == 0:
			if _timer_count == _timers.size():
				_timers.resize(_timers.size() * 2)
			_timers[_timer_count] = slot
			_timer_count += 1
			_rec_timed[slot] = 1


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
	# A `ray()` that did nothing (too deep, or a bad aim) has no end to fire the held spell from.
	if got > 0.0 and spell.held != null and spell.trigger_event == TriggerBase.Event.EXPIRE and _ray_fires > 0 and _take_fire(player):
		_ray_fires -= 1
		_launch(spell.held, _held_tag(tag), player, origin + heading * got, heading, null)
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


## True when the shot in `slot` fires its held spell on a timer.
func _is_timer(slot: int) -> bool:
	var spell: CompiledSpell = _profiles.get(projectiles.get_tag_of(slot))
	return spell != null and spell.held != null and spell.trigger_event == TriggerBase.Event.TIMER


func _held_tag(tag: int) -> int:
	return SpellTag.make(SpellTag.player_of(tag), SpellTag.slot_of(tag), SpellTag.depth_of(tag) + 1, SpellTag.generation_of(tag))


## True when this player may fire one more held spell in this step.
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


## The way a held spell fired by a shot goes: its velocity, or outward from the caster
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
	if spell == null or spell.held == null:
		_rec_fires[slot] = 0
		return
	var player: int = SpellTag.player_of(tag)
	_rec_clock[slot] += spell.trigger_interval
	if not _take_fire(player):
		return
	_rec_fires[slot] -= 1
	var at: Vector2 = projectiles.get_position_of(slot)
	_launch(spell.held, _held_tag(tag), player, at, _heading(spell, slot, at, player), null)


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
	var held: bool = spell.held != null and spell.trigger_event == TriggerBase.Event.HIT and fires > 0 and _take_fire(player)
	if held:
		fires -= 1
	# Write the record back before spawning: a shot that has ended may lose its slot to a child.
	if by_ray:
		_ray_fires = fires
	elif _same(slot):
		_rec_fires[slot] = fires
	var struck: int = target.get_instance_id()
	if held:
		_launch(spell.held, _held_tag(tag), player, position, heading, target)
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
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.held == null or spell.trigger_event != TriggerBase.Event.EXPIRE:
		return
	if player < 0 or player >= SpellLimits.PLAYERS:
		return
	var slot: int = projectiles.event_slot
	var fires: int = spell.trigger_max_fires
	if _same(slot):
		fires = _rec_fires[slot]
	if fires <= 0 or not _take_fire(player):
		return
	var heading: Vector2 = _heading(spell, slot, position, player)
	_launch(spell.held, _held_tag(tag), player, position - heading * SpellLimits.EXPIRE_BACKOFF, heading, null)


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
	fires_dropped = 0
	chains_dropped = 0
	_current.fill(-1)
	_profiles.clear()
	_live.clear()
	_generation_live.clear()
	revoked_tags.clear()


func _in_range(player: int, slot: int) -> bool:
	return player >= 0 and player < SpellLimits.PLAYERS and slot >= 0 and slot < SpellLimits.SLOTS


func _is_current(tag: int) -> bool:
	var index: int = SpellTag.player_of(tag) * SpellLimits.SLOTS + SpellTag.slot_of(tag)
	return _current[index] == SpellTag.generation_of(tag)


## The depth-0 tag of the tag's generation: one key for all three depths.
func _generation_key(tag: int) -> int:
	return SpellTag.make(SpellTag.player_of(tag), SpellTag.slot_of(tag), 0, SpellTag.generation_of(tag))


## Erases the profiles of every depth of the tag's generation.
func _erase_generation(tag: int) -> void:
	for depth in SpellLimits.MAX_DEPTH + 1:
		_profiles.erase(SpellTag.make(SpellTag.player_of(tag), SpellTag.slot_of(tag), depth, SpellTag.generation_of(tag)))


## The old generation is no longer current: free it now if none of its shots is in the air.
func _release_generation(player: int, slot: int, generation: int) -> void:
	var key: int = SpellTag.make(player, slot, 0, generation)
	if _generation_live.get(key, 0) == 0:
		_erase_generation(key)


func _component(id: StringName) -> SpellComponent:
	var source: Node = registry if registry != null else get_node_or_null("/root/Registry")
	if source == null:
		return null
	return source.call("get_resource", &"spells", id) as SpellComponent


func _refused(reason: String) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.valid = false
	spell.reason = reason
	return spell


## One component of `kind` by id, or null with the reason in `problem[0]`.
func _pick(id: StringName, kind: StringName, problem: PackedStringArray) -> SpellComponent:
	var component: SpellComponent = _component(id)
	if component == null:
		problem.append("Unknown component '%s'." % id)
		return null
	if component.kind() != kind:
		problem.append("'%s' is %s %s, not %s %s." % [id, _article(component.kind()), component.kind(), _article(kind), kind])
		return null
	return component


## A component id field: missing or null is &"", a String or StringName is its id,
## anything else adds a reason to `problem`.
func _id_field(recipe: Dictionary, key: String, problem: PackedStringArray) -> StringName:
	var value: Variant = recipe.get(key)
	if value == null:
		return &""
	if value is String or value is StringName:
		return StringName(value)
	problem.append("'%s' must be a component id, not %s." % [key, type_string(typeof(value))])
	return &""


## A list of component ids (Array or PackedStringArray); missing or null is empty.
func _id_list_field(recipe: Dictionary, key: String, problem: PackedStringArray) -> Array:
	var value: Variant = recipe.get(key)
	var ids: Array = []
	if value == null:
		return ids
	if not (value is Array or value is PackedStringArray):
		problem.append("'%s' must be a list of component ids, not %s." % [key, type_string(typeof(value))])
		return ids
	for item in value:
		if item is String or item is StringName:
			ids.append(StringName(item))
		else:
			problem.append("'%s' holds %s, not a component id." % [key, type_string(typeof(item))])
			return []
	return ids


func _article(word: StringName) -> String:
	return "an" if String(word).left(1) in ["a", "e", "i", "o", "u"] else "a"


func _name_of(component: SpellComponent) -> String:
	return component.display_name if not component.display_name.is_empty() else String(component.id)


func _compile(recipe: Dictionary, depth: int) -> CompiledSpell:
	var problem: PackedStringArray = PackedStringArray()
	var form: FormBase = null
	var element: ElementBase = null
	var trigger: TriggerBase = null
	var modifiers: Array[ModifierBase] = []

	var form_id: StringName = _id_field(recipe, "form", problem)
	var element_id: StringName = _id_field(recipe, "element", problem)
	var trigger_id: StringName = _id_field(recipe, "trigger", problem)
	var modifier_ids: Array = _id_list_field(recipe, "modifiers", problem)
	if not problem.is_empty():
		return _refused(problem[0])
	if form_id == &"":
		return _refused("A spell needs a form.")
	if modifier_ids.size() > SpellLimits.MAX_MODIFIERS:
		return _refused("A spell holds at most %d modifiers." % SpellLimits.MAX_MODIFIERS)
	form = _pick(form_id, &"form", problem) as FormBase
	if element_id != &"" and form != null:
		element = _pick(element_id, &"element", problem) as ElementBase
	for id in modifier_ids:
		if problem.is_empty():
			modifiers.append(_pick(id as StringName, &"modifier", problem) as ModifierBase)
	if trigger_id != &"" and problem.is_empty():
		trigger = _pick(trigger_id, &"trigger", problem) as TriggerBase
	if not problem.is_empty():
		return _refused(problem[0])

	var held_recipe: Variant = recipe.get("held")
	var held: CompiledSpell = null
	if held_recipe != null and not held_recipe is Dictionary:
		return _refused("The held spell must be a recipe (a Dictionary).")
	if held_recipe is Dictionary and not (held_recipe as Dictionary).is_empty():
		if trigger == null:
			return _refused("A held spell needs a trigger to fire it.")
		if depth + 1 > SpellLimits.MAX_DEPTH:
			return _refused("Triggers can hold spells at most %d levels deep." % SpellLimits.MAX_DEPTH)
		held = _compile(held_recipe as Dictionary, depth + 1)
		if not held.valid:
			return held

	var spell := CompiledSpell.new()
	spell.depth = depth
	_apply(spell, form, element, modifiers, trigger)
	spell.held = held
	spell.complexity += 0 if held == null else held.complexity
	return spell


## Fills the numbers: the form's base, then the element, then the modifiers in slot order.
func _apply(spell: CompiledSpell, form: FormBase, element: ElementBase, modifiers: Array[ModifierBase], trigger: TriggerBase) -> void:
	spell.form_id = form.id
	spell.form_name = _name_of(form)
	spell.complexity = form.complexity
	var damage: float = form.base_damage
	var mana: float = form.mana_cost
	var cooldown: float = form.cooldown
	var speed: float = form.speed
	var radius: float = form.radius
	var shots: int = form.shots
	var pierce: int = form.pierce
	if element != null:
		spell.element_id = element.id
		spell.element_name = _name_of(element)
		spell.complexity += element.complexity
		spell.status_id = element.status_id
		spell.status_duration = element.status_duration
		spell.status_strength = element.status_strength
		spell.tint = element.tint
		damage *= element.damage_scale
	for modifier in modifiers:
		spell.modifier_ids.append(modifier.id)
		spell.complexity += modifier.complexity
		damage *= modifier.damage_mult
		mana *= modifier.mana_mult
		cooldown *= modifier.cooldown_mult
		speed *= modifier.speed_mult
		radius *= modifier.radius_mult
		shots *= modifier.shot_mult
		pierce += modifier.extra_pierce
		match modifier.behaviour:
			ModifierBase.Behaviour.HOMING:
				spell.homing_turn = maxf(spell.homing_turn, modifier.behaviour_strength)
			ModifierBase.Behaviour.CHAIN:
				spell.chain_jumps += int(modifier.behaviour_strength)
	spell.chain_jumps = clampi(spell.chain_jumps, 0, SpellLimits.MAX_CHAIN_JUMPS)
	spell.damage = clampi(roundi(damage), 1, SpellLimits.MAX_DAMAGE)
	spell.mana_cost = mana
	spell.cooldown = maxf(cooldown, SpellLimits.MIN_COOLDOWN)
	spell.speed = minf(speed, SpellLimits.MAX_SPEED)
	spell.lifetime = clampf(form.lifetime, SpellLimits.MIN_LIFETIME, SpellLimits.MAX_LIFETIME)
	spell.radius = minf(radius, SpellLimits.MAX_RADIUS)
	spell.pierce = mini(pierce, SpellLimits.MAX_PIERCE)
	spell.motion = form.motion
	spell.orbit_radius = form.orbit_radius
	spell.ray_length = form.ray_length
	spell.spread = form.spread
	spell.hit = HitProfile.new()
	spell.hit.damage = spell.damage
	spell.hit.knockback = SpellLimits.KNOCKBACK
	spell.hit.element_id = spell.element_id
	spell.hit.status_id = spell.status_id
	spell.hit.status_duration = spell.status_duration
	spell.hit.status_strength = spell.status_strength
	spell.shots_requested = shots
	if shots > SpellLimits.MAX_SHOTS:
		spell.shots_clamped = true
		spell.shots = SpellLimits.MAX_SHOTS
	else:
		spell.shots = shots
	if spell.shots > 1 and spell.spread <= 0.0 and spell.motion != FormBase.Motion.ORBIT:
		spell.spread = SpellLimits.SPLIT_SPREAD
	if trigger != null:
		spell.trigger_id = trigger.id
		spell.complexity += trigger.complexity
		spell.trigger_event = trigger.event
		spell.trigger_interval = trigger.interval
		spell.trigger_max_fires = trigger.max_fires
		if trigger.event == TriggerBase.Event.TIMER:
			spell.trigger_max_fires = mini(trigger.max_fires, SpellLimits.MAX_TIMER_FIRES)
			spell.trigger_interval = clampf(trigger.interval, SpellLimits.MIN_TIMER_INTERVAL, SpellLimits.MAX_TIMER_INTERVAL)


## Writes the description of this spell and, first, of the spells it holds.
func _describe(spell: CompiledSpell) -> void:
	if spell.held != null:
		_describe(spell.held)
	var parts: PackedStringArray = PackedStringArray()
	var title: String = spell.form_name
	if spell.element_id != &"":
		title = "%s %s" % [spell.element_name, title]
	parts.append("%s: %d damage" % [title, spell.damage])
	if spell.motion == FormBase.Motion.RAY:
		parts.append("a ray")
	elif spell.shots > 1:
		parts.append("%d shots" % spell.shots)
	else:
		parts.append("1 shot")
	parts.append("cooldown %s s" % _number(spell.cooldown))
	if spell.mana_cost > 0.0:
		parts.append("%s mana" % _number(spell.mana_cost))
	var text: String = ", ".join(parts) + "."
	if spell.shots_clamped:
		text += " Cut from %d to %d shots, the limit." % [spell.shots_requested, SpellLimits.MAX_SHOTS]
	if spell.pierce > 0:
		text += " Pierces %d." % spell.pierce
	if spell.status_id != &"" and spell.status_duration > 0.0:
		text += " %s for %s s." % [_status_verb(spell.status_id), _number(spell.status_duration)]
	if spell.homing_turn > 0.0:
		text += " Homing."
	if spell.chain_jumps > 0:
		text += " Chains %d times." % spell.chain_jumps
	if spell.held != null:
		var when: String = "on hit"
		if spell.trigger_event == TriggerBase.Event.EXPIRE:
			when = "when it ends"
		elif spell.trigger_event == TriggerBase.Event.TIMER:
			when = "every %s s" % _number(spell.trigger_interval)
		text += " Then, %s: %s" % [when, spell.held.description]
	spell.description = text


func _status_verb(status: StringName) -> String:
	return STATUS_VERBS.get(status, "Applies %s" % status)


func _number(value: float) -> String:
	return String.num(value, 2)

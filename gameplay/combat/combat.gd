extends Node
## Combat: the damage pipeline. One autoload ("Combat") turns hits into damage, knockback,
## statuses, reactions and deaths. It is the only sender of `damage_dealt` and `enemy_died`.
##
##     Combat.register_actor(imp, 20, 11.0, 1, Vector2(0, -12))   # health, hurt circle, touch
##     Combat.apply_status(caster, imp.id, Combat.BURN, 3.0, 2.0)
##     Combat.pace(imp)                                           # 0.0 while frozen
##
## One body model (actors G5, docs/milestones/M2-actors.md, "Combat: one rule"): every body that
## can be hurt is a row of packed arrays sized `Actors.ACTORS` and indexed by its actor id, a
## wizard's and an enemy's alike, and every rule below is written once and applied to every
## row. Finding a row is an array read (by id) or one dictionary read (by node); freeing it
## is O(1). A body's id is its own (`id` of a kit Actor; `actor_id` or `caster` of a plain
## body) or, for a body that has none, one Combat opens for it in the actor table (the enemies' team, the enemy ramp) and
## closes when it goes, so every body has an owner; the projectile manager is told it
## (`add_target`'s owner).
##
## Parameters: everything that names one actor takes `actor: Variant`, either its actor id
## (an int) or its node; both find the same row. The two calls a body makes about itself every
## step, `pace` and `consume_knockback`, take its node (`pace_of` takes either). Attackers
## (`caster`, `by`) are actor ids, `Events.NO_PLAYER` for none, passed through as they came.
##
## Health: a kit Actor's is its Health component (Combat calls `take(amount, killer)` and
## `heal`; at 0 the actor dies, `die(killer)`, unless something downs it instead: a wizard's
## Downed). A plain body without the kit (tests' stand-ins) has its health in Combat's row. A
## kit Actor is not hurt while down, dying or protected.
##
## A spell's hit (`projectile_hit`; a blast's too, rules R4 F2) is looked up in Spells' hit profiles
## (`Spells.hit_profile(tag, shot)`) and runs `_apply_spell`: a heal for the caster's team (a mend),
## else damage and a push (a pull while hexed), the shock jump, the static discharge, then
## each element's reaction or status. Plain hits (`hit`, contact, reactions, burn) run `_hit`:
## a barrier takes the hit whole, then hex adds its share, static goes off, health goes down,
## `hit_landed`, `damage_dealt` (and the actor's own `Actor.damaged`) and `actor_hurt` are sent,
## and a body at 0 dies: `kill_landed` (a spell's own hit only), `enemy_died` (for every body not
## on the wizards' team, a kit actor by its own controller's team so a possessed enemy still
## counts; flow counts the wave by it), and the body is freed.
##
## The one rules (owner, 2026-10-28), the same on every actor:
##  - **shock:** the next spell hit also jumps to the nearest other actor of the victim's team;
##  - **static:** any hit (not a burn tick) sets it off: the victim's actors of other teams
##    within STATIC_RANGE take its share, and the charge is always spent;
##  - **hex:** extra damage, and a spell hit pulls the victim toward it instead of pushing;
##  - **pull:** moves every actor in the circle;
##  - **barriers:** on any actor (`wizard_shield_requested` gives the caster's actor one);
##  - **several elements:** every element of a hit acts in turn, later statuses too;
##  - **burn ticks** are quiet for everyone: no event unless the tick kills;
##  - **contact:** an actor with contact damage hurts every actor of another team it touches,
##    once per CONTACT_COOLDOWN per victim (an imp walking through imps hurts none).
##
## Knockback: Combat only keeps each actor's push. It never moves a body: whoever moves it adds
## `consume_knockback(actor, delta)` to its own velocity each physics step and multiplies its
## pace by `pace(actor)` (chill slows, freeze stops).
##
## Nothing here allocates per hit or per frame. Listeners of the events Combat sends may call
## hit(), register or unregister: rows are looked up again after every send.

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
## The element reactions, loaded by their literal path (the registry skips the table).
const REACTIONS: ReactionTable = preload("res://content/spells/reactions.tres")

## The statuses an element can put on an actor (`ElementBase.status_id`), and `freeze`,
## which three stacks of chill make.
const BURN: StringName = &"burn"
const CHILL: StringName = &"chill"
const FREEZE: StringName = &"freeze"
const SHOCK: StringName = &"shock"
const HEX: StringName = &"hex"
const STATIC: StringName = &"static"
## Every status by its index (`ST_*`): a row keeps each one's seconds left and power in
## `_status_left` and `_status_power`, at `row * STATUS_COUNT + ST_*`. A plain status (shock, hex,
## static) is only its name, its index and its row in each table below; burn and chill have rules of
## their own, in the few places that name them (`_apply_status_row`, `_extend`, `_remove_status`,
## `_tick`). What a status does to a hit is where the hit is dealt (`_hit`, `_apply_spell`, `_pace`).
const STATUSES: Array[StringName] = [BURN, CHILL, FREEZE, SHOCK, HEX, STATIC]
const ST_BURN: int = 0
const ST_CHILL: int = 1
const ST_FREEZE: int = 2
const ST_SHOCK: int = 3
const ST_HEX: int = 4
const ST_STATIC: int = 5
const STATUS_COUNT: int = 6
## A status's index by its name.
const STATUS_AT: Dictionary[StringName, int] = {BURN: ST_BURN, CHILL: ST_CHILL, FREEZE: ST_FREEZE, SHOCK: ST_SHOCK, HEX: ST_HEX, STATIC: ST_STATIC}
## By ST_*: whether `apply_status` puts it on (freeze only comes from chill).
const STATUS_APPLIED: Array[bool] = [true, true, false, true, true, true]
## By ST_*: what `apply_status`'s strength is in its power (its power is the strength over this):
## burn's damage a second, chill's share of speed (its strength a percent), shock's, hex's and
## static's percent; freeze has none.
const STATUS_STRENGTH_PER_POWER: Array[float] = [1.0, 100.0, 0.0, 1.0, 1.0, 1.0]
## The id a discharge is announced with on `reaction_triggered`, at each actor it hits.
const DISCHARGE: StringName = &"discharge"

## The kinds of a hit (M2-staffs.md, "Self-harm and hits"). A shot, beam or swing of a spell, a
## slam's ring (`burst`), a reaction's damage, damage over time, and a heal.
const KIND_SHOT: StringName = &"shot"
## The cues of a barrier's block (played on the shielded actor, turned back the way the hit came)
## and of a body caught by a pull (on the body, the way it is pulled, as the puller's); content's
## looks (content/cues; S6, item 13).
const SHIELD_BLOCK_CUE: StringName = &"shield_block"
const PULL_CUE: StringName = &"pull"
## A body pulled within this many steps of its last pull is still caught: no new PULL_CUE (a
## magnet that pulls every other step, `SpellLimits.MAX_PULLS_PER_STEP`, catches it once).
const PULL_GAP_STEPS: int = 6
const KIND_RAY: StringName = &"ray"
const KIND_SWING: StringName = &"swing"
const KIND_BURST: StringName = &"burst"
const KIND_REACTION: StringName = &"reaction"
const KIND_STATUS: StringName = &"status"
const KIND_HEAL: StringName = &"heal"

## What "downed by your own ..." calls a hit when its spell has no name of its own.
const KIND_NAMES: Dictionary = {
	KIND_SHOT: "Shot",
	KIND_RAY: "Beam",
	KIND_SWING: "Swing",
	KIND_BURST: "Blast",
	KIND_REACTION: "Reaction",
	KIND_STATUS: "Burn",
}

## How many rows there are: one per actor id.
const ACTORS: int = ActorsScript.ACTORS
## Seats: `home_actor_of` finds a wizard by its home seat.
const PLAYER_SLOTS: int = ActorsScript.SEATS
## A barrier given for less than this many seconds lasts this long (a dash is shorter).
const SHIELD_MIN_TIME: float = 0.5
## An actor knocked at least this fast into a wall (one step ahead of it) takes the slam of a
## heavy hit, once.
const SLAM_MIN_SPEED: float = 60.0
const SLAM_REACH: float = 2.0
## Seconds an actor is safe from contact damage after one contact hit.
const CONTACT_COOLDOWN: float = 1.0
## Up to this many actors that contact can hurt are checked against every toucher directly;
## more (a crowd of two teams that both touch) are found with the projectile manager's grid.
const CONTACT_DIRECT: int = 16
## How fast knockback speed falls, in pixels per second per second.
const KNOCKBACK_DECAY: float = 1200.0
## Chill stacks that freeze, how long the freeze lasts, and the largest share of speed
## chill can take away.
const CHILL_STACKS_TO_FREEZE: int = 3
const FREEZE_TIME: float = 1.0
const CHILL_SLOW_MAX: float = 0.9
## A shocked actor's next spell hit also jumps to the nearest other actor of its team within
## this many pixels.
const SHOCK_JUMP_RANGE: float = 64.0
## A spell hit on a hexed actor pulls it toward the hit point with this share of the push it
## would have had away from it.
const HEX_PULL_SHARE: float = 0.5
## A charged (static) actor that is hit discharges to every actor of another team within this
## many pixels of it, once: the discharge is plain damage, so it sets off nothing else.
const STATIC_RANGE: float = 96.0
## The statuses a reaction can start from, in the order they are looked at: a hit reacts with the
## first the target has that has a row for the hit's element (a frozen target counts as chilled).
## The one list of that order (`_status_bits`).
const REACTING_STATUSES: Array[StringName] = [BURN, CHILL, SHOCK, HEX, STATIC]
## `_hit`'s `team` when its caller has not read the row's team (it reads it then).
const TEAM_UNREAD: int = -2
## A consume reaction does this many times its damage to a frozen actor.
const FROZEN_BONUS: int = 2
## An actor reacts at most once per this many seconds; a hit inside the wait does its own
## status instead. Keeps fast spells from setting the same reaction off on every hit.
const REACTION_WAIT: float = 0.5
## Limits for the reaction EXTEND effect: the longest freeze, the longest any other extended
## status, the largest extra damage share of hex or shock in per cent, and the fastest burn.
const MAX_FREEZE: float = 4.0
const MAX_EXTENDED_TIME: float = 8.0
const MAX_EXTENDED_PERCENT: float = 100.0
const MAX_EXTENDED_BURN: float = 20.0
## By ST_*: the most power EXTEND gives a status (chill's EXTEND is a freeze, freeze has none).
const STATUS_EXTENDED_MAX: Array[float] = [MAX_EXTENDED_BURN, 0.0, 0.0, MAX_EXTENDED_PERCENT, MAX_EXTENDED_PERCENT, MAX_EXTENDED_PERCENT]

## What a row holds: nothing, a kit Actor (health in its Health), or a plain body (health in the
## row).
const BODY_NONE: int = 0
const BODY_ACTOR: int = 1
const BODY_PLAIN: int = 3
## Where a body without the kit keeps its actor id, looked at in this order.
const OWN_ID_PROPERTIES: Array[StringName] = [&"actor_id", &"caster"]

## Sent at the start of every `step`, before freed bodies are dropped, statuses tick and touches are
## checked: the moment no hit is being dealt. The horde swarm promotes the swarmers a rule asked
## for here (docs/milestones/horde-swarm.md, S3), so the full actor stands before anything touches.
signal stepping()

## Not state: services, caches and scratch, set up again (core/sim/README.md); `_node_id` and
## `_row_by_node`, a lookup from a body's node to its row (by instance id, equality only: a row is
## its actor id, and the row's identity is its actor's key, N5).
const DERIVED: Array[StringName] = [&"events", &"projectiles", &"registry", &"spells", &"actors", &"_due_node", &"_slam_due_node", &"_touch_node", &"_auto_table", &"_node_id", &"_row_by_node", &"_reacting_at"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_nodes"]
## The session's settings a new run keeps (`begin_run`): the reaction table.
const RUN_KEEPS: Array[StringName] = [&"reactions"]

## The event bus, the projectile manager and the registry. Only tests set these, before
## adding the node; otherwise the "Events", "Projectiles" and "Registry" autoloads are used.
var events: EventsScript = null
var projectiles: ProjectileManagerScript = null
var registry: RegistryScript = null
## The spell runtime, which tells what a spell's shot does (`hit_profile`). Same rule.
var spells: SpellsScript = null
## The reaction table. Tests may set another one; null means REACTIONS.
var reactions: ReactionTable = null
## Hit-stop, the game's rule (online-ready N4): which moments hold which bodies, and the game-wide
## stop. State (its step count and its reactions' repeat clocks); its services are Combat's
## (`_bind_hit_stop`).
var hit_stop: HitStop = HitStop.new()
## The actor table. Null uses the projectile manager's, else the `Actors` autoload, else one
## of Combat's own (a scene with neither).
var actors: ActorsScript = null

# The rows, by actor id. `_live` lists the ids in use (order not kept), `_live_at` where each
# is in it, `_row_by_node` the id of each registered node (by instance id).
var _body: PackedByteArray = PackedByteArray()
var _owned: PackedByteArray = PackedByteArray()
var _nodes: Array[Node2D] = []
var _node_id: PackedInt64Array = PackedInt64Array()
var _row_by_node: Dictionary[int, int] = {}
var _live: PackedInt32Array = PackedInt32Array()
var _live_at: PackedInt32Array = PackedInt32Array()
# The row of the actor whose home controller has each seat (a wizard body), or NONE.
var _seat_row: PackedInt32Array = PackedInt32Array()

# The body: health (plain bodies only), its most, the damage of its touch, its hurt circle,
# its push, and seconds before contact may hurt it again.
var _health: PackedFloat64Array = PackedFloat64Array()
var _max_health: PackedFloat64Array = PackedFloat64Array()
var _contact_damage: PackedInt32Array = PackedInt32Array()
var _hurt_radius: PackedFloat32Array = PackedFloat32Array()
var _hurt_offset: PackedVector2Array = PackedVector2Array()
var _knock: PackedVector2Array = PackedVector2Array()
## The step (`_steps`) each row was last pulled in (`pull`), so a body newly caught plays PULL_CUE.
var _pulled_at: PackedInt32Array = PackedInt32Array()
## Steps taken (`step`).
var _steps: int = 0
var _contact_left: PackedFloat32Array = PackedFloat32Array()

# Statuses, STATUS_COUNT a row (`row * STATUS_COUNT + ST_*`): seconds left (0: off) and power
# (burn's damage a second, chill's share of speed taken, the percent a shock jumps with, a hex
# adds, a static charge discharges; freeze has none).
var _status_left: PackedFloat32Array = PackedFloat32Array()
var _status_power: PackedFloat32Array = PackedFloat32Array()
# Burn's own: the fraction of a point not yet dealt, and who set it. Chill's: its stacks.
var _burn_carry: PackedFloat32Array = PackedFloat32Array()
var _burn_by: PackedInt32Array = PackedInt32Array()
var _chill_stacks: PackedInt32Array = PackedInt32Array()
## REACTING_STATUSES as ST_* (`_status_bits`). Not state: made from the constants.
var _reacting_at: PackedInt32Array = _reacting_indices()
# Seconds until the actor may react again.
var _react_wait: PackedFloat32Array = PackedFloat32Array()
# The barrier: blocked hits left, seconds left and the card's tag.
var _shield: PackedInt32Array = PackedInt32Array()
var _shield_left: PackedFloat32Array = PackedFloat32Array()
var _shield_tag: PackedInt32Array = PackedInt32Array()
# Heavy hits armed: the slam damage waiting for a wall, and who dealt it.
var _slam: PackedInt32Array = PackedInt32Array()
var _slam_by: PackedInt32Array = PackedInt32Array()
# Who hurt the actor last, for "downed by ...": the actor (or NO_PLAYER), the hit kind and the
# spell's name.
var _last_by: PackedInt32Array = PackedInt32Array()
var _last_kind: Array[StringName] = []
var _last_name: PackedStringArray = PackedStringArray()

## True while a discharge is being dealt, so nothing it causes can start another.
var _discharging: bool = false
## True when the last `_hit` set a static charge off (a spell's hit then puts no first status on).
var _discharged: bool = false
## The tag of the spell hit being dealt now (0 for none): `kill_landed`, `reaction_landed` and
## `actor_hurt` carry it. Set around a spell's hit, restored after, so hits inside hits are right.
var _tag: int = 0
## The shot that hit (the projectile manager's slot from `projectile_hit`), -1 for none: what the
## hit sets off names it as its `shot`, as `_tag` its tag.
var _slot: int = -1

# Burn damage due this step, sent after the status loop (hits can free rows): body, who, points.
var _due_node: Array[Node2D] = []
var _due_by: PackedInt32Array = PackedInt32Array()
var _due_amount: PackedInt32Array = PackedInt32Array()
# Slams due this step, the same way.
var _slam_due_node: Array[Node2D] = []
var _slam_due_by: PackedInt32Array = PackedInt32Array()
var _slam_due_amount: PackedInt32Array = PackedInt32Array()
# Contact hits due this step: the body touched, who touched it, damage.
var _touch_node: Array[Node2D] = []
var _touch_by: PackedInt32Array = PackedInt32Array()
var _touch_amount: PackedInt32Array = PackedInt32Array()
# The actors contact may hurt this step and their teams; the teams that touch, as bits.
var _victims: PackedInt32Array = PackedInt32Array()
var _victim_team: PackedInt32Array = PackedInt32Array()
## Where each victim's hurt circle is this step (the direct check, `_touch`).
var _victim_at: PackedVector2Array = PackedVector2Array()
## The actor table's teams (`Actors.teams`, taken in `step`; its own array, always current):
## what `_team` answers for each row, without a call.
var _teams: PackedInt32Array = PackedInt32Array()
var _toucher_teams: int = 0
# Scratch lists for grid queries, one per nesting depth (a hit set off by another hit's burst
# gets its own), so nothing is allocated once the deepest nesting was seen.
var _pool: Array = []
var _pool_depth: int = 0

## The `Actors` autoload once found, or Combat's own table when there is none.
var _auto_table: ActorsScript = null


func _init() -> void:
	_body.resize(ACTORS)
	_owned.resize(ACTORS)
	_nodes.resize(ACTORS)
	_node_id.resize(ACTORS)
	_live_at.resize(ACTORS)
	_live_at.fill(-1)
	_seat_row.resize(PLAYER_SLOTS)
	_seat_row.fill(ActorsScript.NONE)
	# (Packed arrays are values: each is resized by name.)
	_health.resize(ACTORS)
	_max_health.resize(ACTORS)
	_contact_damage.resize(ACTORS)
	_burn_by.resize(ACTORS)
	_chill_stacks.resize(ACTORS)
	_shield.resize(ACTORS)
	_shield_tag.resize(ACTORS)
	_slam.resize(ACTORS)
	_slam_by.resize(ACTORS)
	_last_by.resize(ACTORS)
	_last_by.fill(EventsScript.NO_PLAYER)
	_hurt_radius.resize(ACTORS)
	_contact_left.resize(ACTORS)
	_status_left.resize(ACTORS * STATUS_COUNT)
	_status_power.resize(ACTORS * STATUS_COUNT)
	_burn_carry.resize(ACTORS)
	_react_wait.resize(ACTORS)
	_shield_left.resize(ACTORS)
	_hurt_offset.resize(ACTORS)
	_knock.resize(ACTORS)
	_pulled_at.resize(ACTORS)
	_pulled_at.fill(-(1 << 30))
	_last_kind.resize(ACTORS)
	_last_name.resize(ACTORS)


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Combat").steps(&"Combat", step).renewed_by(begin_run)
	setup()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Give back the ids Combat opened.
		var table: ActorsScript = _table()
		for n in _live.size():
			var row: int = _live[n]
			if _owned[row] != 0 and table != null and table.is_open(row):
				table.close(row)


## Find what is not set yet and listen to the events. `_ready` calls it; a scene that builds
## combat outside the tree (a test, the clip recorder) calls it after setting the fields.
func setup() -> void:
	# Absolute paths only work inside the tree (tests build combat outside it).
	var in_tree: bool = is_inside_tree()
	if events == null and in_tree:
		events = get_node_or_null("/root/Events") as EventsScript
		if events == null:
			push_warning("Combat: the Events autoload is missing, so combat hears and sends nothing.")
	if projectiles == null and in_tree:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if registry == null and in_tree:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if spells == null and in_tree:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if reactions == null:
		reactions = REACTIONS
	_bind_hit_stop()
	if events == null:
		return
	if not events.projectile_hit.is_connected(_on_projectile_hit):
		events.projectile_hit.connect(_on_projectile_hit)
	if not events.player_downed.is_connected(_on_player_downed):
		events.player_downed.connect(_on_player_downed)
	if not events.player_revived.is_connected(_on_player_revived):
		events.player_revived.connect(_on_player_revived)
	if not events.wizard_shield_requested.is_connected(_on_wizard_shield_requested):
		events.wizard_shield_requested.connect(_on_wizard_shield_requested)
	if not events.pull_requested.is_connected(_on_pull_requested):
		events.pull_requested.connect(_on_pull_requested)
	if not events.status_requested.is_connected(_on_status_requested):
		events.status_requested.connect(_on_status_requested)
	# The moments of other areas that hold bodies (online-ready N4, `hit_stop.gd`).
	if not events.shot_blocked.is_connected(_on_shot_blocked):
		events.shot_blocked.connect(_on_shot_blocked)
	if not events.carrier_ended.is_connected(_on_carrier_ended):
		events.carrier_ended.connect(_on_carrier_ended)
	if not events.cue_shown.is_connected(_on_cue_shown):
		events.cue_shown.connect(_on_cue_shown)
	if not events.projectile_impact.is_connected(_on_projectile_impact):
		events.projectile_impact.connect(_on_projectile_impact)


## A swing's block (the projectile manager's `impact_form` while it is sent, no shot of its own)
## is a parry: its stop.
func _on_shot_blocked(caster: int, _position: Vector2, _tag: int, shot: int) -> void:
	if shot < 0 and projectiles != null and projectiles.impact_form == &"swing":
		hit_stop.parried(caster)


## A shot struck (the projectile manager's `impact_form` while it is sent names its card).
func _on_projectile_impact(caster: int, _target: Node, _position: Vector2, _direction: Vector2) -> void:
	if projectiles != null:
		hit_stop.impact(caster, projectiles.impact_form)


func _on_carrier_ended(caster: int, form: StringName, _at: Vector2, _direction: Vector2, _size: float, _tint: Color, _look: int) -> void:
	hit_stop.carrier_ended(caster, form)


func _on_cue_shown(caster: int, cue: StringName, _at: Vector2, _direction: Vector2, _size: float, _tint: Color, _look: int) -> void:
	hit_stop.cue(cue, caster)


## A run starts (`Tick.begin_run`, online-ready N3b): any body still registered leaves, and Combat
## is a fresh one's state (core/sim/sim_fresh.gd): its step count, rows, pools and scratch, with
## the session's reaction table (RUN_KEEPS).
func begin_run() -> void:
	for row in _nodes.size():
		var node: Variant = _nodes[row]
		if node != null and is_instance_valid(node):
			unregister_actor(node)
	# Its caches by node (DERIVED) went with the rows.
	SimFresh.renew(self)


# --- Bodies ------------------------------------------------------------------

## Make `actor` something that can be hurt (the kit's Hurtbox calls it): its hurt circle
## (`radius` at `offset` from the feet) is a projectile target every spell can hit, and its touch
## does `contact_damage` to other teams. `health` is used only by a body without the kit (a kit
## Actor's is its Health). Returns the actor id its row is kept under (see the top), or
## Actors.NONE when it could not be registered. Registering again resets its numbers.
func register_actor(actor: Node2D, health: float = 1.0, radius: float = 8.0, contact_damage: int = 0, offset: Vector2 = Vector2.ZERO) -> int:
	var body: int = BODY_ACTOR if actor is Actor else BODY_PLAIN
	return _register(actor, body, maxf(health, Health.EMPTY), radius, contact_damage, offset, ActorsScript.NONE, ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY, ActorsScript.NONE)


## Forget `actor` (an id or its node) without killing it (no event).
func unregister_actor(actor: Variant) -> void:
	var row: int = _row_of(actor)
	if row != ActorsScript.NONE:
		_free_row(row)


## The actor id the body `node` is kept under, or Actors.NONE when it is not registered.
func actor_of(node: Node) -> int:
	return _row_of(node)


## True while `actor` (an id or its node) is registered.
func is_registered(actor: Variant) -> bool:
	return _row_of(actor) != ActorsScript.NONE


## How many bodies are registered.
func actor_count() -> int:
	return _live.size()


## Health left of `actor` (parts of a point too), or -1 if it is not registered (or dead).
func health_of(actor: Variant) -> float:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE:
		return -1.0
	match _body[row]:
		BODY_ACTOR:
			var kit: Actor = _nodes[row] as Actor
			return kit.health.health if kit.health != null else -1.0
	return _health[row]


## The push on `actor` now (zero when none). It is not faded by reading it.
func knockback_of(actor: Variant) -> Vector2:
	var row: int = _row_of(actor)
	return _knock[row] if row != ActorsScript.NONE else Vector2.ZERO


## Everything Combat keeps on `actor` (an id or its node) but its body, hurt circle and touch: its
## health, every status (time left, strength, stacks, who set a burn), its barrier, its push, its
## armed slam, its contact wait, its reaction wait and who hurt it last. Empty when it is not
## registered. The swarm's promotion (docs/milestones/horde-swarm.md) carries a swarmer's row to
## the full actor that replaces it with `carry_row_state`. Allocates (one Dictionary): not per step.
func row_state(actor: Variant) -> Dictionary:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE:
		return {}
	return {
		"health": health_of(row), "knock": _knock[row], "contact_left": _contact_left[row],
		"status_left": _status_left.slice(row * STATUS_COUNT, (row + 1) * STATUS_COUNT),
		"status_power": _status_power.slice(row * STATUS_COUNT, (row + 1) * STATUS_COUNT),
		"burn": [_burn_carry[row], _burn_by[row]], "chill_stacks": _chill_stacks[row], "react_wait": _react_wait[row],
		"shield": [_shield[row], _shield_left[row], _shield_tag[row]], "slam": [_slam[row], _slam_by[row]],
		"last": [_last_by[row], _last_kind[row], _last_name[row]],
	}


## Puts `state` (a `row_state`) on `actor` (an id or its node, registered): its health (a kit
## Actor's Health is set to it, at most its most), statuses, barrier, push and the rest, as they
## were. Sends nothing (nothing new happened to it). Returns false when `actor` is not registered.
func carry_row_state(actor: Variant, state: Dictionary) -> bool:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE or state.is_empty():
		return false
	var health: float = state["health"] as float
	if health >= 0.0:
		if _body[row] == BODY_ACTOR:
			var kit: Actor = _nodes[row] as Actor
			if kit.health != null and kit.health.health != health:
				kit.health.reset(health)
		else:
			_health[row] = minf(health, _max_health[row])
	_knock[row] = state["knock"] as Vector2
	_contact_left[row] = state["contact_left"] as float
	var lefts: PackedFloat32Array = state["status_left"]
	var powers: PackedFloat32Array = state["status_power"]
	for st in STATUS_COUNT:
		_status_left[row * STATUS_COUNT + st] = lefts[st]
		_status_power[row * STATUS_COUNT + st] = powers[st]
	var burn: Array = state["burn"]
	_burn_carry[row] = burn[0]
	_burn_by[row] = burn[1]
	_chill_stacks[row] = state["chill_stacks"] as int
	_react_wait[row] = state["react_wait"] as float
	var barrier: Array = state["shield"]
	_shield[row] = barrier[0]
	_shield_left[row] = barrier[1]
	_shield_tag[row] = barrier[2]
	var slam: Array = state["slam"]
	_slam[row] = slam[0]
	_slam_by[row] = slam[1]
	var last: Array = state["last"]
	_last_by[row] = last[0]
	_last_kind[row] = last[1]
	_last_name[row] = last[2]
	return true


## For whoever moves the body `actor` (its node: the one call a body makes about itself every
## step, with `pace`): the push (pixels per second) to add to its movement this step. Call it
## once per physics step; it then fades the stored push by `KNOCKBACK_DECAY * delta`. Zero when
## there is none.
func consume_knockback(actor: Node2D, delta: float) -> Vector2:
	return _consume_knockback(_row_of_node(actor), delta)


## For whoever moves the body `actor` (its node): the share of its walking pace it keeps. 1.0
## free, less chilled, 0.0 frozen. It scales walking and an enemy's attack timers, not its
## knockback. By id: `pace_of`.
func pace(actor: Node2D) -> float:
	return _pace(_row_of_node(actor))


## `pace` for `actor` given as an id or a node.
func pace_of(actor: Variant) -> float:
	return _pace(_row_of(actor))


## `pace` and `consume_knockback` for a body asking about itself with its own actor `id` (a kit
## Actor's row is its id): the cheap way for an actor's own step, which asks every physics step
## (no node lookup; performance pass, 2026-10-28). The same answer as by node: a body kept under
## another row (or none) is looked up by node.
func own_pace(actor: Node2D, id: int) -> float:
	if id < 0 or id >= ACTORS or _nodes[id] != actor or _body[id] == BODY_NONE:
		return _pace(_row_of_node(actor))
	# `_pace`, written out: this runs for every actor every step.
	var at: int = id * STATUS_COUNT
	if _status_left[at + ST_FREEZE] > 0.0:
		return 0.0
	if _status_left[at + ST_CHILL] > 0.0:
		return 1.0 - _status_power[at + ST_CHILL]
	return 1.0


func own_knockback(actor: Node2D, id: int, delta: float) -> Vector2:
	if id < 0 or id >= ACTORS or _nodes[id] != actor or _body[id] == BODY_NONE:
		return _consume_knockback(_row_of_node(actor), delta)
	# `_consume_knockback`, written out: this runs for every actor every step.
	var push: Vector2 = _knock[id]
	if push != Vector2.ZERO:
		_knock[id] = push.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	return push


## `own_pace` and `own_knockback` for the first `count` bodies of `nodes` (their actor ids in `ids`)
## at once (a crowd's step: one call instead of two per body, Horde swarm S4): for each `i` whose
## `seconds[i]` is above 0, `paces[i]` becomes `own_pace(nodes[i], ids[i])` and `pushes[i]`
## `own_knockback(nodes[i], ids[i], seconds[i])`, the push spent as that spends it; the others are
## left as they were (a body held still spends no push). The arrays must hold `count` entries.
func own_paces_and_pushes(nodes: Array[Node2D], ids: PackedInt32Array, count: int, seconds: PackedFloat64Array, paces: PackedFloat64Array, pushes: PackedVector2Array) -> void:
	for i in count:
		var walk: float = seconds[i]
		if walk <= 0.0:
			continue
		var actor: Node2D = nodes[i]
		var id: int = ids[i]
		if id < 0 or id >= ACTORS or _nodes[id] != actor or _body[id] == BODY_NONE:
			var row: int = _row_of_node(actor)
			paces[i] = _pace(row)
			pushes[i] = _consume_knockback(row, walk)
			continue
		# `own_pace` and `own_knockback`, written out.
		var at: int = id * STATUS_COUNT
		if _status_left[at + ST_FREEZE] > 0.0:
			paces[i] = 0.0
		elif _status_left[at + ST_CHILL] > 0.0:
			paces[i] = 1.0 - _status_power[at + ST_CHILL]
		else:
			paces[i] = 1.0
		var push: Vector2 = _knock[id]
		if push != Vector2.ZERO:
			_knock[id] = push.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * walk)
		pushes[i] = push


func _pace(row: int) -> float:
	if row == ActorsScript.NONE:
		return 1.0
	var at: int = row * STATUS_COUNT
	if _status_left[at + ST_FREEZE] > 0.0:
		return 0.0
	if _status_left[at + ST_CHILL] > 0.0:
		return 1.0 - _status_power[at + ST_CHILL]
	return 1.0


func _consume_knockback(row: int, delta: float) -> Vector2:
	if row == ActorsScript.NONE:
		return Vector2.ZERO
	var push: Vector2 = _knock[row]
	if push != Vector2.ZERO:
		_knock[row] = push.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	return push


# --- Statuses ----------------------------------------------------------------

## Put `status_id` (burn, chill, shock, hex or static) on `actor` (an id or its node) for
## `duration` seconds. `strength` is burn damage per second, the percent of speed chill takes,
## the percent of the hit that a shock jumps with, the percent of extra damage a hex adds, or the
## percent of a hit a static charge discharges. `caster` is credited with burn damage. A second
## application refreshes the time and keeps the stronger number; the third chill in a row
## freezes (`freeze`, FREEZE_TIME seconds) and clears the chill, and a frozen actor takes no
## chill. Sends `status_applied`. Returns false for an unknown status, a time of 0, an actor
## that is not registered or is down, or a chill on a frozen actor.
func apply_status(caster: int, actor: Variant, status_id: StringName, duration: float, strength: float) -> bool:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE:
		return false
	return _apply_status_row(caster, row, status_id, duration, strength)


## `apply_status` on a row already known to hold a body (a spell's hit, which has its row): the
## same, less the lookup of the actor.
func _apply_status_row(caster: int, row: int, status_id: StringName, duration: float, strength: float) -> bool:
	if duration <= 0.0 or not is_instance_valid(_nodes[row]) or _is_down(row):
		return false
	var st: int = STATUS_AT.get(status_id, -1)
	if st < 0 or not STATUS_APPLIED[st]:
		push_warning("Combat: unknown status '%s'." % status_id)
		return false
	var at: int = row * STATUS_COUNT
	var power: float = strength / STATUS_STRENGTH_PER_POWER[st]
	var froze: bool = false
	if st == ST_BURN:
		# A fresh burn starts from nothing; one still burning keeps its stronger rate.
		if _status_left[at + ST_BURN] <= 0.0:
			_status_power[at + ST_BURN] = 0.0
			_burn_carry[row] = 0.0
		_burn_by[row] = caster
	elif st == ST_CHILL:
		# A frozen actor takes no chill; the third in a row freezes it.
		if _status_left[at + ST_FREEZE] > 0.0:
			return false
		power = clampf(power, 0.0, CHILL_SLOW_MAX)
	# Every status: the longer time and the stronger power.
	_status_left[at + st] = maxf(_status_left[at + st], duration)
	_status_power[at + st] = maxf(_status_power[at + st], power)
	if st == ST_CHILL:
		_chill_stacks[row] += 1
		if _chill_stacks[row] >= CHILL_STACKS_TO_FREEZE:
			_status_left[at + ST_CHILL] = 0.0
			_status_power[at + ST_CHILL] = 0.0
			_chill_stacks[row] = 0
			_status_left[at + ST_FREEZE] = FREEZE_TIME
			froze = true
	if events != null:
		var node: Node2D = _nodes[row]
		events.status_applied.emit(caster, node, status_id)
		if froze:
			events.status_applied.emit(caster, node, FREEZE)
	return true


## Seconds left of `status_id` (burn, chill, freeze, shock, hex or static) on `actor`; 0 when
## it is off or the actor is not registered.
func status_left(actor: Variant, status_id: StringName) -> float:
	var row: int = _row_of(actor)
	var st: int = STATUS_AT.get(status_id, -1)
	if row == ActorsScript.NONE or st < 0:
		return 0.0
	return _status_left[row * STATUS_COUNT + st]


func has_status(actor: Variant, status_id: StringName) -> bool:
	return status_left(actor, status_id) > 0.0


## Chill stacks on `actor` (0 up to CHILL_STACKS_TO_FREEZE - 1; the last one freezes).
func chill_stacks(actor: Variant) -> int:
	var row: int = _row_of(actor)
	return _chill_stacks[row] if row != ActorsScript.NONE else 0


# --- Barriers, pulls, notes --------------------------------------------------

## A barrier on `actor` (an id or its node): `charges` more blocked hits for `seconds` (at
## least SHIELD_MIN_TIME). Charges add up; the longer time is kept. A down actor gets none.
func give_shield(actor: Variant, charges: int, seconds: float, tag: int = 0) -> void:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE or charges <= 0 or _is_down(row):
		return
	_shield[row] = (_shield[row] if _shield_left[row] > 0.0 else 0) + charges
	_shield_left[row] = maxf(_shield_left[row], maxf(seconds, SHIELD_MIN_TIME))
	_shield_tag[row] = tag
	_send_barrier(row, Vector2.ZERO)


## `barrier_changed` for the barrier on `row` as it is now; `way` the way a hit it blocked flew
## (zero for no block).
func _send_barrier(row: int, way: Vector2) -> void:
	if events != null:
		var left: float = _shield_left[row]
		events.barrier_changed.emit(_cast_id(row), _shield[row] if left > 0.0 else 0, left, _shield_tag[row], way, _hurt_radius[row])


## Hits the barrier on `actor` still blocks; 0 when none.
func shield(actor: Variant) -> int:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE or _shield_left[row] <= 0.0:
		return 0
	return _shield[row]


## Pull every actor whose hurt circle is within `radius` of `position` toward it at `strength`
## pixels per second, through the push Combat keeps (whoever moves the actor already adds it).
## With a finite `to`, within `radius` of the line from `position` to `to`, toward the nearest
## point of the line (a beam's magnet). A pull replaces the push an actor had, so a magnet each
## step does not pile speed up. `caster` is who pulls (a pull does no damage); a body it newly
## catches (not pulled in the last PULL_GAP_STEPS steps) plays PULL_CUE. With `foes_only`,
## actors on the caster's team (the caster too) are left alone, their push and slam arming
## included; a caster with no team pulls everyone.
func pull(caster: int, position: Vector2, radius: float, strength: float, foes_only: bool = false, to: Vector2 = Vector2.INF) -> void:
	if projectiles == null or strength <= 0.0:
		return
	var table: ActorsScript = _table()
	var own_team: int = table.team_of(caster) if foes_only and table != null else ActorsScript.NONE
	var near: Array[Node2D] = _take_scratch()
	var end: Vector2 = to if to.is_finite() else position
	var count: int = projectiles.targets_in(position, radius, ProjectileManagerScript.ACTOR_LAYERS, near, end)
	for i in count:
		var row: int = _row_of_node(near[i])
		if row == ActorsScript.NONE:
			continue
		if own_team != ActorsScript.NONE and _team(row) == own_team:
			continue
		var body: Vector2 = _position_of(_nodes[row]) + _hurt_offset[row]
		var toward: Vector2 = (Geometry2D.get_closest_point_to_segment(body, position, end) - body).normalized()
		_knock[row] = toward * strength
		_slam[row] = 0
		# A body caught by a pull it was not in lately: the moment's cue (S6, item 13).
		if _pulled_at[row] < _steps - PULL_GAP_STEPS and events != null:
			events.cue_shown.emit(caster, PULL_CUE, body, toward, 0.0, Color.WHITE, 0)
		_pulled_at[row] = _steps
	_give_scratch()


## Why `actor` went down, in plain words, for the screen: "downed by your own Blast" when its
## own spell did it, "downed by player 2's Frost Nova" for an actor seat 2 drives, and an empty
## string for an actor no seat drives or when nothing is known.
func downed_note_of(actor: Variant) -> String:
	var row: int = _row_of(actor)
	if row == ActorsScript.NONE:
		return ""
	var who: int = _last_by[row]
	if who < 0:
		return ""
	var what: String = _last_name[row]
	if what.is_empty():
		what = KIND_NAMES.get(_last_kind[row], "spell") as String
	if who == row or who == _cast_id(row):
		return "downed by your own %s" % what
	var seat: int = _seat_of(who)
	if seat == ActorsScript.NONE:
		return ""
	return "downed by player %d's %s" % [seat + 1, what]


## The registered actor whose home controller has seat `seat` (the wizard body that seat plays,
## also while the seat drives another actor), or Actors.NONE. Feel finds a downed wizard by it.
func home_actor_of(seat: int) -> int:
	return _seat_row_of(seat)


# --- The pipeline ------------------------------------------------------------

## The damage pipeline for a hit that does not come from a spell. The actor `caster` (or
## Events.NO_PLAYER) dealt `amount` to `target` (an id or its node), pushing it along
## `direction` (unit length, or zero) at `strength` pixels per second. Returns true if the hit
## counted (`damage_dealt` was sent). A hit on an unknown body, a dead or down one, a protected
## one, or for 0 or less does nothing; a barrier takes it whole (false).
## `kind` is the hit kind (`KIND_*`), told to Feel by `hit_landed`.
func hit(caster: int, target: Variant, amount: float, direction: Vector2 = Vector2.ZERO, strength: float = 0.0, kind: StringName = KIND_SHOT) -> bool:
	var row: int = _row_of(target)
	if row == ActorsScript.NONE:
		return false
	return _hit(caster, row, amount, direction, strength, kind, null, false)


## One hit on the row `row` (see `hit`). A `quiet` hit (a burn tick) takes the whole pipeline,
## deaths included, but sends no event for an actor that survives, so Feel and the AI do not
## stutter, shake or flinch twice a second per burning actor; a status tick is no hit for a
## barrier, a hex, a static charge or `actor_hurt`. `amount` may be part of a point (an atom's
## speck takes 0.3 health). `team` is the row's team when the caller read it already (a spell's
## hit, `_apply_spell`), else TEAM_UNREAD. Sets `_discharged`.
func _hit(by: int, row: int, amount: float, direction: Vector2, strength: float, kind: StringName, profile: HitProfile, quiet: bool, team: int = TEAM_UNREAD) -> bool:
	_discharged = false
	if amount <= 0.0 or not _can_hurt(row):
		return false
	var node: Node2D = _nodes[row]
	var where: Vector2 = _position_of(node)
	var actor: int = _cast_id(row)
	var tick: bool = kind == KIND_STATUS
	# A barrier takes the hit whole: no damage, no status, no push.
	if not tick and _shield[row] > 0 and _shield_left[row] > 0.0:
		_shield[row] -= 1
		if _shield[row] == 0:
			_shield_left[row] = 0.0
		if events != null:
			events.shield_blocked.emit(actor, where, _shield_tag[row])
			# Its look is content's (S6, item 13): turned back the way the hit came.
			events.cue_shown.emit(actor, SHIELD_BLOCK_CUE, where + _hurt_offset[row], -direction, 0.0, Color.WHITE, 0)
			# A hit with no way of its own (contact) is drawn as one from straight above.
			_send_barrier(row, direction if direction != Vector2.ZERO else Vector2.DOWN)
		return false
	var discharge_share: float = 0.0
	if team == TEAM_UNREAD:
		team = _team(row)
	var centre: Vector2 = where + _hurt_offset[row]
	if not tick:
		var at: int = row * STATUS_COUNT
		if _status_left[at + ST_HEX] > 0.0:
			amount += amount * _status_power[at + ST_HEX] / 100.0
		# A charge goes off on any hit and is always spent (not by a discharge's own damage).
		if _status_left[at + ST_STATIC] > 0.0 and not _discharging:
			discharge_share = _status_power[at + ST_STATIC]
			_remove_status(row, STATIC)
	if strength > 0.0:
		_knock[row] = direction * strength
	_last_by[row] = by
	_last_kind[row] = kind
	_last_name[row] = profile.source_name if profile != null else ""
	var left: float = _take(row, by, amount, quiet)
	# Nobody hears a quiet hit that does not kill (a wizard's went to it directly, `_take`).
	if events != null and not (quiet and left != 0.0):
		events.hit_landed.emit(by, node, amount, where, kind, _slot)
		events.damage_dealt.emit(by, node, amount, where)
		# Its stop (online-ready N4): the attacker, this body (its row is its actor id) and the shot.
		hit_stop.hit(by, row, kind, _slot)
		if node is Actor:
			# The actor's own listeners (its AI's grudge, its look's hurt pose) hear it directly.
			(node as Actor).damaged.emit(by, amount)
		# A burn tick is not a hit: cards that fire on hurt are not set off by it.
		if not tick:
			events.actor_hurt.emit(actor, amount, where, _tag, kind)
	# A listener may have forgotten the body: it is not killed by Combat then.
	if left == 0.0 and _same(row, node):
		_die(row, by, where, team)
	if discharge_share > 0.0:
		# A charged actor is a lightning rod: the charge leaves in one step to the other teams near.
		_discharge(actor, team, node, centre, amount * discharge_share / 100.0)
	_discharged = discharge_share > 0.0
	return true


## Take `amount` off the body's health; returns what is left (-1 for a kit Actor with no
## Health, which never dies of hits).
func _take(row: int, by: int, amount: float, quiet: bool) -> float:
	match _body[row]:
		BODY_ACTOR:
			var kit: Actor = _nodes[row] as Actor
			if kit.health == null:
				return -1.0
			kit.health.take(amount, by)
			return kit.health.health
	_health[row] = maxf(_health[row] - amount, 0.0)
	if _health[row] < Health.EMPTY:
		_health[row] = 0.0
	return _health[row]


## The body at row `row` died, killed by `by`: forget it, tell (`kill_landed` for a spell's own
## hit, `enemy_died` for a body not on the wizards' team, a kit actor by its own controller's team
## so a possessed enemy still counts) and free it. A kit Actor that something downs instead
## (`downable`) stays.
func _die(row: int, by: int, where: Vector2, team: int) -> void:
	var node: Node2D = _nodes[row]
	var kit: Actor = node as Actor if _body[row] == BODY_ACTOR else null
	if kit != null and kit.downable:
		return
	_free_row(row)
	if events != null:
		if _tag != 0:
			events.kill_landed.emit(by, node, where, _tag, _slot)
		# A possessed enemy is on its driver's team while it lasts, but its death is an enemy's
		# (the wave counts on it): an actor counts by its own controller's team. Its depletion
		# already ended the possession, so `team` (read before the hit) is the driver's.
		var own_team: int = kit.home_controller.team if kit != null and kit.home_controller != null else team
		if own_team != ActorsScript.TEAM_WIZARDS:
			events.enemy_died.emit(by, node, where, _slot)
			hit_stop.killed(by, node, _slot)
	if kit != null:
		kit.die(by)
	elif is_instance_valid(node) and node.is_inside_tree():
		node.queue_free()


## A heal hit: `amount` health for the row `row` from `by`'s spell. A down or dead actor is not
## healed. A wizard's own code adds it (`heal_dealt`).
func _heal(by: int, row: int, amount: float) -> bool:
	if amount <= 0.0 or not _can_heal(row):
		return false
	var node: Node2D = _nodes[row]
	match _body[row]:
		BODY_ACTOR:
			var kit: Actor = node as Actor
			if kit.health != null:
				kit.health.heal(amount)
		BODY_PLAIN:
			_health[row] = minf(_health[row] + amount, _max_health[row])
	var where: Vector2 = _position_of(node)
	if events != null:
		events.hit_landed.emit(by, node, amount, where, KIND_HEAL, _slot)
		events.heal_dealt.emit(by, node, amount, where)
	return true


## A shot landed. Every shot is a spell's, described by `Spells.hit_profile(tag)` (damage,
## knockback, status); a shot with no profile, or on a body Combat does not know (a decoy), does
## nothing.
func _on_projectile_hit(caster: int, target: Node, position: Vector2, tag: int, shot: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var row: int = _row_of_node(target)
	if row == ActorsScript.NONE:
		return
	var profile: HitProfile = spells.hit_profile(tag, shot) if spells != null else null
	if profile == null:
		return
	var saved_tag: int = _tag
	var saved_slot: int = _slot
	_tag = tag
	_slot = shot
	_apply_spell(caster, row, position, profile, profile.kind)
	_tag = saved_tag
	_slot = saved_slot


## A spell's hit on the row `row`, struck at `position`: a mend heals an actor of the caster's
## team (teams aim: a mend is for friends); otherwise damage and a push away from the hit (a pull
## toward it while hexed), the shock jump, the static discharge (in `_hit`), then every element in
## order: each reacts with what the ones before it left, or puts its own status on, later
## statuses too (`fire · frost · bolt` thaws on its own hit).
func _apply_spell(by: int, row: int, position: Vector2, profile: HitProfile, kind: StringName) -> void:
	if profile.heal > 0 and _heals(by, row):
		_heal(by, row, profile.heal)
		return
	var node: Node2D = _nodes[row]
	var damage: float = profile.damage
	var strength: float = profile.knockback
	# Away from the hit, measured to the hurt circle's centre (shots, beams and swings strike it at
	# hand height), not the feet: a swing up at a body pushes it up, not down onto the caster. A
	# hit on the very spot the body stands (a blast it sets off where its dash ends) has no way to
	# push it.
	var feet: Vector2 = _position_of(node)
	var direction: Vector2 = Vector2.ZERO if feet.is_equal_approx(position) else (feet + _hurt_offset[row] - position).normalized()
	var at: int = row * STATUS_COUNT
	if _status_left[at + ST_HEX] > 0.0:
		direction = -direction
		strength *= HEX_PULL_SHARE
	var jump_share: float = _status_power[at + ST_SHOCK] if _status_left[at + ST_SHOCK] > 0.0 else 0.0
	var jump_from: Vector2 = feet + _hurt_offset[row]
	# (Read now: a body the hit kills has no row, and so no team, after it.)
	var team: int = _team(row)
	# The reaction is chosen from the statuses the target had when the hit arrived.
	var reaction: ReactionRow = null
	if profile.element_id != &"" and _react_wait[row] <= 0.0:
		reaction = _reaction_for(row, profile.element_id)
	if not _hit(by, row, damage, direction, strength, kind, profile, false, team):
		return
	var discharged: bool = _discharged
	if _same(row, node):
		if strength > 0.0:
			# A push replaces the knockback, so it replaces the slam too: only a heavy hit arms it.
			_slam[row] = profile.slam if profile.slam > 0 else 0
			_slam_by[row] = by
		if jump_share > 0.0:
			_remove_status(row, SHOCK)
	# What the jump and the reactions kill is not the spell's own kill: no `kill_landed`.
	if jump_share > 0.0:
		var spell_tag: int = _tag
		_tag = 0
		_shock_jump(by, team, node, jump_from, damage * jump_share / 100.0)
		_tag = spell_tag
	# (One reaction per hit on a target, but within a hit the chain goes on: `reacted` lets the
	# next element read what is left.)
	var reacted: bool = false
	var elements: int = maxi(profile.element_ids.size(), profile.later_status_ids.size() + 1)
	# A hit of one element or none, with no reaction and no status of its own, has nothing more to do.
	if elements == 1 and reaction == null and profile.status_id == &"":
		return
	for i in elements:
		if not _same(row, node) or _is_down(row):
			return
		var step_reaction: ReactionRow = reaction
		var status_id: StringName = profile.status_id
		var duration: float = profile.status_duration
		var power: float = profile.status_strength
		if i > 0:
			var element: StringName = profile.element_ids[i] if i < profile.element_ids.size() else &""
			step_reaction = _reaction_for(row, element) if element != &"" and (reacted or _react_wait[row] <= 0.0) else null
			status_id = profile.later_status_ids[i - 1] if i - 1 < profile.later_status_ids.size() else &""
			duration = profile.later_status_durations[i - 1] if i - 1 < profile.later_status_durations.size() else 0.0
			power = profile.later_status_strengths[i - 1] if i - 1 < profile.later_status_strengths.size() else 0.0
		if step_reaction != null:
			# The reaction runs instead of the status, and only on a target that lived.
			_react(by, row, step_reaction)
			reacted = true
		elif status_id != &"" and not (i == 0 and discharged):
			# (A discharge replaces the first status, so a lightning hit does not charge again at once.)
			_apply_status_row(by, row, status_id, duration, power)


## True when `by`'s heal is for the row `row`: the same team (an actor of no team heals nobody).
func _heals(by: int, row: int) -> bool:
	var table: ActorsScript = _table()
	if table == null:
		return false
	var team: int = table.team_of(by)
	return team != ActorsScript.NONE and team == _team(row)


## The spell hit on `node` (of `team`) jumps from `from` to the nearest other actor of that team
## in reach, for `amount`. The jump pushes nothing and puts on no status.
func _shock_jump(by: int, team: int, node: Node2D, from: Vector2, amount: float) -> void:
	if projectiles == null:
		return
	var near: Array[Node2D] = _take_scratch()
	var count: int = projectiles.targets_in(from, SHOCK_JUMP_RANGE, ProjectileManagerScript.ACTOR_LAYERS, near)
	var best: int = ActorsScript.NONE
	var best_sq: float = INF
	for i in count:
		if near[i] == node:
			continue
		var other: int = _row_of_node(near[i])
		if other == ActorsScript.NONE or _team(other) != team:
			continue
		var d: float = (_position_of(_nodes[other]) + _hurt_offset[other]).distance_squared_to(from)
		if d < best_sq:
			best_sq = d
			best = other
	_give_scratch()
	if best != ActorsScript.NONE:
		_hit(by, best, amount, Vector2.ZERO, 0.0, KIND_SHOT, null, false)


## A charged actor (`actor`, of `team`, the body `victim`) was hit: every actor of another team
## within STATIC_RANGE of `from` takes `amount`, credited to the charged actor, and
## `reaction_triggered(actor, &"discharge", ...)` and `discharge_arc(actor, from, to)` are sent for
## each. One step: the damage sets off nothing else (`_discharging`), and is no spell's kill.
func _discharge(actor: int, team: int, victim: Node2D, from: Vector2, amount: float) -> void:
	if projectiles == null or _discharging:
		return
	_discharging = true
	var spell_tag: int = _tag
	_tag = 0
	var near: Array[Node2D] = _take_scratch()
	var count: int = projectiles.targets_in(from, STATIC_RANGE, ProjectileManagerScript.ACTOR_LAYERS, near)
	for i in count:
		var other_node: Node2D = near[i]
		if other_node == victim or not is_instance_valid(other_node):
			continue
		var other: int = _row_of_node(other_node)
		if other == ActorsScript.NONE or _team(other) == team:
			continue
		if events != null:
			# Feel shows a burst on each actor zapped and a jagged arc from the struck one.
			var zapped: Vector2 = _position_of(other_node) + _hurt_offset[other]
			events.reaction_triggered.emit(actor, DISCHARGE, zapped, _slot)
			hit_stop.reaction(actor, DISCHARGE, _slot)
			events.discharge_arc.emit(actor, from, zapped)
			# A listener may have changed the registrations.
			other = _row_of_node(other_node)
		if other != ActorsScript.NONE:
			_hit(actor, other, amount, Vector2.ZERO, 0.0, KIND_REACTION, null, false)
	_give_scratch()
	_tag = spell_tag
	_discharging = false


# --- Reactions ---------------------------------------------------------------

## The reaction a hit of `element_id` sets off on the row `row`: the row of the first of
## REACTING_STATUSES the target has that has one for that element; null when none does.
## Allocation-free: the element's rows come lined up with REACTING_STATUSES from the table, and the
## target's statuses as one mask (shot scale H3: a lookup by status cost more than the rest of an
## elemental hit's own work).
func _reaction_for(row: int, element_id: StringName) -> ReactionRow:
	var table: ReactionTable = reactions if reactions != null else REACTIONS
	var in_order: Array[ReactionRow] = table.in_order(element_id, REACTING_STATUSES)
	if in_order.is_empty():
		return null
	var on: int = _status_bits(row)
	for at in in_order.size():
		if (on >> at) & 1 != 0 and in_order[at] != null:
			return in_order[at]
	return null


## Which of REACTING_STATUSES the row has: bit `i` for `REACTING_STATUSES[i]`; a frozen actor counts
## as chilled (a row for `chill` matches a frozen target). The one place a reaction reads them.
func _status_bits(row: int) -> int:
	var at: int = row * STATUS_COUNT
	var on: int = 0
	for i in _reacting_at.size():
		var st: int = _reacting_at[i]
		if _status_left[at + st] > 0.0 or (st == ST_CHILL and _status_left[at + ST_FREEZE] > 0.0):
			on |= 1 << i
	return on


## REACTING_STATUSES as ST_* (`_reacting_at`).
static func _reacting_indices() -> PackedInt32Array:
	var found := PackedInt32Array()
	for status in REACTING_STATUSES:
		found.append(STATUS_AT[status])
	return found


## Run `reaction` on the row `row`: announce it (`reaction_triggered` at the actor, and
## `reaction_landed` for the caster's `on reaction`), then do its effect kind. Reactions only
## start from a spell's hit; the damage they deal sets off no more and is no spell's kill.
func _react(by: int, row: int, reaction: ReactionRow) -> void:
	var node: Node2D = _nodes[row]
	var centre: Vector2 = _position_of(node) + _hurt_offset[row]
	_react_wait[row] = REACTION_WAIT
	if events != null:
		events.reaction_triggered.emit(by, reaction.reaction_id, centre, _slot)
		hit_stop.reaction(by, reaction.reaction_id, _slot)
		if _tag != 0:
			events.reaction_landed.emit(by, reaction.reaction_id, node, centre, _tag, _slot)
		if not _same(row, node):
			return
	var spell_tag: int = _tag
	_tag = 0
	match reaction.effect:
		ReactionRow.Effect.CONSUME:
			var amount: float = reaction.damage
			if _status_left[row * STATUS_COUNT + ST_FREEZE] > 0.0:
				amount *= FROZEN_BONUS
				_remove_status(row, CHILL)
			_remove_status(row, reaction.status_id)
			_hit(by, row, amount, Vector2.ZERO, 0.0, KIND_REACTION, null, false)
		ReactionRow.Effect.BURST:
			if reaction.consume_status:
				_remove_status(row, reaction.status_id)
			_burst(by, row, centre, reaction)
		ReactionRow.Effect.EXTEND:
			_extend(by, row, reaction)
		ReactionRow.Effect.SPREAD:
			_spread(by, row, centre, reaction)
	_tag = spell_tag


## BURST: `reaction.damage` to every actor in the circle, the struck one included, and a pull
## toward the centre when the row has one.
func _burst(by: int, row: int, centre: Vector2, reaction: ReactionRow) -> void:
	if projectiles == null:
		_hit(by, row, reaction.damage, Vector2.ZERO, 0.0, KIND_REACTION, null, false)
		return
	var near: Array[Node2D] = _take_scratch()
	var count: int = projectiles.targets_in(centre, reaction.radius, ProjectileManagerScript.ACTOR_LAYERS, near)
	for i in count:
		var other_node: Node2D = near[i]
		if not is_instance_valid(other_node):
			continue
		var other: int = _row_of_node(other_node)
		if other == ActorsScript.NONE:
			continue
		var toward: Vector2 = (centre - _position_of(other_node)).normalized() if reaction.pull > 0.0 else Vector2.ZERO
		_hit(by, other, reaction.damage, toward, reaction.pull, KIND_REACTION, null, false)
	_give_scratch()


## EXTEND: the status lasts longer and is stronger. A chilled actor freezes for the row's
## duration; a frozen one stays frozen that much longer.
func _extend(by: int, row: int, reaction: ReactionRow) -> void:
	var st: int = STATUS_AT.get(reaction.status_id, -1)
	if st < 0 or st == ST_FREEZE:
		return
	var at: int = row * STATUS_COUNT
	if st == ST_CHILL:
		var newly: bool = _status_left[at + ST_FREEZE] <= 0.0
		_status_left[at + ST_CHILL] = 0.0
		_status_power[at + ST_CHILL] = 0.0
		_chill_stacks[row] = 0
		_status_left[at + ST_FREEZE] = minf(_status_left[at + ST_FREEZE] + reaction.duration, MAX_FREEZE)
		if newly and events != null:
			events.status_applied.emit(by, _nodes[row], FREEZE)
		return
	_status_left[at + st] = minf(_status_left[at + st] + reaction.duration, MAX_EXTENDED_TIME)
	_status_power[at + st] = minf(_status_power[at + st] + reaction.strength, STATUS_EXTENDED_MAX[st])


## SPREAD: the status, as it is now, goes on every other actor in the circle.
func _spread(by: int, row: int, centre: Vector2, reaction: ReactionRow) -> void:
	var node: Node2D = _nodes[row]
	var left: float = status_left(row, reaction.status_id)
	var strength: float = _strength_of(row, reaction.status_id)
	if reaction.consume_status:
		_remove_status(row, reaction.status_id)
	if left <= 0.0 or projectiles == null:
		return
	var near: Array[Node2D] = _take_scratch()
	var count: int = projectiles.targets_in(centre, reaction.radius, ProjectileManagerScript.ACTOR_LAYERS, near)
	for i in count:
		if near[i] != node and is_instance_valid(near[i]):
			var other: int = _row_of_node(near[i])
			if other != ActorsScript.NONE:
				apply_status(by, other, reaction.status_id, left, strength)
	_give_scratch()


## The number `apply_status` takes as strength for the status on the row `row`.
func _strength_of(row: int, status_id: StringName) -> float:
	var st: int = STATUS_AT.get(status_id, -1)
	if st < 0:
		return 0.0
	return _status_power[row * STATUS_COUNT + st] * STATUS_STRENGTH_PER_POWER[st]


## Switch `status_id` off on the row `row` (a frozen actor loses its freeze with its chill).
func _remove_status(row: int, status_id: StringName) -> void:
	var st: int = STATUS_AT.get(status_id, -1)
	if st < 0 or st == ST_FREEZE:
		return
	var at: int = row * STATUS_COUNT
	_status_left[at + st] = 0.0
	_status_power[at + st] = 0.0
	if st == ST_BURN:
		_burn_carry[row] = 0.0
	elif st == ST_CHILL:
		_chill_stacks[row] = 0
		_status_left[at + ST_FREEZE] = 0.0


# --- Requests ---

## A barrier for the caster's own actor (`wizard_shield_requested`), whoever it is.
func _on_wizard_shield_requested(caster: int, charges: int, seconds: float, tag: int) -> void:
	give_shield(caster, charges, seconds, tag)


## A carrier that hits nothing gave `target` a status (a portal's infusion): applied with no hit.
func _on_status_requested(caster: int, target: Node, status_id: StringName, duration: float, strength: float) -> void:
	if status_id != &"" and is_instance_valid(target):
		apply_status(caster, target, status_id, duration, strength)


func _on_pull_requested(caster: int, position: Vector2, radius: float, strength: float, _tag_of_card: int, to: Vector2) -> void:
	pull(caster, position, radius, strength, true, to)


## A wizard of seat `player` went down: its statuses, push and barrier go, and shots fly past it
## (its target is removed) until it is revived. What hurt it last stays, for `downed_note_of`.
func _on_player_downed(player: int) -> void:
	# The game-wide stop of a downed wizard (online-ready N4).
	hit_stop.downed()
	var row: int = _seat_row_of(player)
	if row == ActorsScript.NONE:
		return
	_clear_state(row)
	if projectiles != null and is_instance_valid(_nodes[row]):
		projectiles.remove_target(_nodes[row])


func _on_player_revived(player: int, _reviver: int) -> void:
	var row: int = _seat_row_of(player)
	if row == ActorsScript.NONE:
		return
	_last_by[row] = EventsScript.NO_PLAYER
	_last_name[row] = ""
	_add_target(row)


# --- Time --------------------------------------------------------------------

## Move time on: statuses count down and burn, barriers fade, heavy hits slam into walls, and
## contact hurts. Called every physics frame; tests call it with fixed deltas. Knockback is not
## applied here (see the top).
func step(delta: float) -> void:
	_steps += 1
	_bind_hit_stop()
	hit_stop.step()
	stepping.emit()
	# Drop bodies freed from outside (backwards: a freed row takes the last one's place).
	var n: int = _live.size() - 1
	while n >= 0:
		if n < _live.size() and not is_instance_valid(_nodes[_live[n]]):
			_free_row(_live[n])
		n -= 1
	_toucher_teams = 0
	# Every actor's team at once (`_team` for each row, written out: this runs for every body, every
	# step; Horde swarm S5): the table's own array, so it is always current; read only.
	var table: ActorsScript = _table()
	_teams = table.teams() if table != null else PackedInt32Array()
	for i in _live.size():
		var row: int = _live[i]
		_tick(row, delta)
		if _slam[row] > 0:
			_check_slam(row)
		if _contact_damage[row] > 0:
			_toucher_teams |= _team_bit(_teams[row] if row < _teams.size() else ActorsScript.NONE)
	_send_burns()
	_send_slams()
	if _toucher_teams != 0:
		_touch()
	_send_touches()


## Count one actor's statuses, barrier and contact wait down; burn collects whole points of
## damage for _send_burns().
func _tick(row: int, delta: float) -> void:
	# A count at 0 stays at 0: only the ones running are written (what is read is all of them).
	if _contact_left[row] != 0.0:
		_contact_left[row] = maxf(_contact_left[row] - delta, 0.0)
	if _shield_left[row] > 0.0:
		_shield_left[row] = maxf(_shield_left[row] - delta, 0.0)
		if _shield_left[row] == 0.0:
			_shield[row] = 0
			_send_barrier(row, Vector2.ZERO)
	var at: int = row * STATUS_COUNT
	# Burn deals its rate for the seconds it still had.
	var burning: float = _status_left[at + ST_BURN]
	if burning > 0.0:
		var burned: float = minf(delta, burning)
		_status_left[at + ST_BURN] = burning - burned
		_burn_carry[row] += _status_power[at + ST_BURN] * burned
		var whole: int = int(_burn_carry[row])
		if whole > 0:
			_burn_carry[row] -= float(whole)
			_due_node.append(_nodes[row])
			_due_by.append(_burn_by[row])
			_due_amount.append(whole)
	# Every other status counts down; a chill that runs out takes its slow and stacks with it.
	for st in range(ST_BURN + 1, STATUS_COUNT):
		var left: float = _status_left[at + st]
		if left != 0.0:
			left = maxf(left - delta, 0.0)
			_status_left[at + st] = left
			if left == 0.0 and st == ST_CHILL:
				_status_power[at + ST_CHILL] = 0.0
				_chill_stacks[row] = 0
	if _react_wait[row] != 0.0:
		_react_wait[row] = maxf(_react_wait[row] - delta, 0.0)


## Deal the burn damage counted this step: quiet hits of kind `status`. After the loop, because
## hits can free rows.
func _send_burns() -> void:
	var sent: int = 0
	while sent < _due_node.size():
		var row: int = _row_of_node(_due_node[sent])
		if row != ActorsScript.NONE:
			_hit(_due_by[sent], row, _due_amount[sent], Vector2.ZERO, 0.0, KIND_STATUS, null, true)
		sent += 1
	_due_node.clear()
	_due_by.clear()
	_due_amount.clear()


## Count a heavy hit's slam: an actor knocked fast into a wall (a step ahead of it) takes the
## damage once. Rows are collected here and hit after the loop, as hits can free rows.
func _check_slam(row: int) -> void:
	if _slam[row] <= 0:
		return
	var speed: float = _knock[row].length()
	if speed < SLAM_MIN_SPEED:
		_slam[row] = 0
		return
	if projectiles == null:
		return
	var from: Vector2 = _position_of(_nodes[row]) + _hurt_offset[row]
	var to: Vector2 = from + _knock[row] / speed * (_hurt_radius[row] + SLAM_REACH)
	if projectiles.clip_to_walls(from, to) != to:
		_slam_due_node.append(_nodes[row])
		_slam_due_by.append(_slam_by[row])
		_slam_due_amount.append(_slam[row])
		_slam[row] = 0


## A slam is not the spell's own hit: no tag, so it sends no `kill_landed`.
func _send_slams() -> void:
	var saved_tag: int = _tag
	_tag = 0
	var sent: int = 0
	while sent < _slam_due_node.size():
		var row: int = _row_of_node(_slam_due_node[sent])
		if row != ActorsScript.NONE:
			_hit(_slam_due_by[sent], row, maxi(_slam_due_amount[sent], 1), Vector2.ZERO, 0.0, KIND_REACTION, null, false)
		sent += 1
	_tag = saved_tag
	_slam_due_node.clear()
	_slam_due_by.clear()
	_slam_due_amount.clear()


## Contact: every actor that touches (`_contact_damage`) hurts each actor of another team whose
## hurt circle its own overlaps, once per CONTACT_COOLDOWN per victim. Hits are queued and sent
## after the loops. The usual crowd (many touchers, a few wizards) is checked directly against
## live positions; past CONTACT_DIRECT victims each victim asks the grid what touches it.
func _touch() -> void:
	_victims.clear()
	_victim_team.clear()
	var team_rows: int = _teams.size()
	for i in _live.size():
		var row: int = _live[i]
		if _contact_left[row] > 0.0:
			continue
		var team: int = _teams[row] if row < team_rows else ActorsScript.NONE
		if (_toucher_teams & ~_team_bit(team)) == 0 or not _can_hurt(row):
			continue
		_victims.append(row)
		_victim_team.append(team)
	if _victims.is_empty():
		return
	if _victims.size() <= CONTACT_DIRECT or projectiles == null:
		# The victims' hurt circles once (nothing moves while contact is counted), and the box round
		# them all, a pixel wider: a toucher whose circle stays out of it touches none of them, so
		# most of a crowd is passed after one look at where it is (Horde swarm S5).
		var victims: int = _victims.size()
		_victim_at.resize(victims)
		var low: Vector2 = Vector2.INF
		var high: Vector2 = -Vector2.INF
		for v in victims:
			var victim: int = _victims[v]
			var centre: Vector2 = _position_of(_nodes[victim]) + _hurt_offset[victim]
			_victim_at[v] = centre
			var spread: float = _hurt_radius[victim] + 1.0
			low = low.min(centre - Vector2(spread, spread))
			high = high.max(centre + Vector2(spread, spread))
		for i in _live.size():
			var row: int = _live[i]
			if _contact_damage[row] <= 0:
				continue
			# `_position_of`, written out.
			var body: Node2D = _nodes[row]
			var at: Vector2 = (body.global_position if body.is_inside_tree() else body.position) + _hurt_offset[row]
			var own: float = _hurt_radius[row]
			if at.x + own < low.x or at.y + own < low.y or at.x - own > high.x or at.y - own > high.y:
				continue
			var team: int = _teams[row] if row < team_rows else ActorsScript.NONE
			for v in victims:
				var victim: int = _victims[v]
				if victim == row or _victim_team[v] == team or _contact_left[victim] > 0.0:
					continue
				var reach: float = own + _hurt_radius[victim]
				if at.distance_squared_to(_victim_at[v]) <= reach * reach:
					_touched(victim, row)
		return
	var near: Array[Node2D] = _take_scratch()
	for v in _victims.size():
		var victim: int = _victims[v]
		var centre: Vector2 = _position_of(_nodes[victim]) + _hurt_offset[victim]
		var count: int = projectiles.targets_in(centre, _hurt_radius[victim], ProjectileManagerScript.ACTOR_LAYERS, near)
		for i in count:
			var row: int = _row_of_node(near[i])
			if row != ActorsScript.NONE and row != victim and _contact_damage[row] > 0 and _team(row) != _victim_team[v]:
				_touched(victim, row)
				break
	_give_scratch()


## The toucher `row` touched `victim`: queue the hit and start the victim's wait.
func _touched(victim: int, row: int) -> void:
	_contact_left[victim] = CONTACT_COOLDOWN
	_touch_node.append(_nodes[victim])
	_touch_by.append(_cast_id(row))
	_touch_amount.append(_contact_damage[row])


## Send the contact hits counted this step (kind `shot`, credited to the toucher).
func _send_touches() -> void:
	var sent: int = 0
	while sent < _touch_node.size():
		var row: int = _row_of_node(_touch_node[sent])
		if row != ActorsScript.NONE:
			_hit(_touch_by[sent], row, _touch_amount[sent], Vector2.ZERO, 0.0, KIND_SHOT, null, false)
		sent += 1
	_touch_node.clear()
	_touch_by.clear()
	_touch_amount.clear()


# --- Rows --------------------------------------------------------------------

## Register `node` as a body of kind `body` (see `register_actor`). Its row is its own actor id;
## else `fallback` (an id the caller found for it); else one Combat opens with `team`, `ramp`
## and `seat`. Returns the row, or NONE.
func _register(node: Node2D, body: int, health: float, radius: float, contact: int, offset: Vector2, fallback: int, team: int, ramp: int, seat: int) -> int:
	if node == null or not is_instance_valid(node):
		return ActorsScript.NONE
	var row: int = _row_of_node(node)
	if row == ActorsScript.NONE:
		var owned: bool = false
		row = _own_id_of(node)
		if row == ActorsScript.NONE:
			row = fallback
		if row == ActorsScript.NONE:
			var table: ActorsScript = _table()
			row = table.open(team, ramp, seat) if table != null else ActorsScript.NONE
			if row == ActorsScript.NONE:
				push_warning("Combat: the actor table is full, so %s cannot be hurt." % node.name)
				return ActorsScript.NONE
			table.set_node(row, node)
			owned = true
		if _body[row] != BODY_NONE:
			# The id's last body (a stale row of a node that left without unregistering).
			_free_row(row)
		_nodes[row] = node
		_node_id[row] = node.get_instance_id()
		_row_by_node[_node_id[row]] = row
		_owned[row] = 1 if owned else 0
		_live_at[row] = _live.size()
		_live.append(row)
	_body[row] = body
	_health[row] = health
	_max_health[row] = health
	_contact_damage[row] = contact
	_hurt_radius[row] = radius
	_hurt_offset[row] = offset
	_clear_state(row)
	if body == BODY_ACTOR:
		# `home_actor_of(seat)` finds a wizard by its home seat, never by the seat's driven actor
		# (another one while it possesses).
		var home: ActorController = (node as Actor).home_controller
		if home != null and home.seat >= 0 and home.seat < PLAYER_SLOTS:
			_seat_row[home.seat] = row
	_contact_left[row] = 0.0
	_last_by[row] = EventsScript.NO_PLAYER
	_last_kind[row] = &""
	_last_name[row] = ""
	_add_target(row)
	return row


## The row's body as a projectile target, unless it is down: a wizard on LAYER_PLAYER, the rest
## by team (the layers merge later), owned by the actor it casts as (or the actor it belongs to:
## `Actor.belongs_to`, a decoy's caster), so those shots skip it.
func _add_target(row: int) -> void:
	if projectiles == null or _is_down(row):
		return
	var wizards: bool = _body[row] == BODY_ACTOR and _team(row) == ActorsScript.TEAM_WIZARDS
	var layer: int = ProjectileManagerScript.LAYER_PLAYER if wizards else ProjectileManagerScript.LAYER_ENEMY
	var owner: int = _cast_id(row)
	if _body[row] == BODY_ACTOR and (_nodes[row] as Actor).belongs_to != ActorsScript.NONE:
		owner = (_nodes[row] as Actor).belongs_to
	# Its identity is the actor's key (N5): shots keep it, not the node's instance id.
	var table: ActorsScript = _table()
	var key: int = table.key_of(row) if table != null else 0
	projectiles.add_target(_nodes[row], _hurt_radius[row], layer, owner, _hurt_offset[row], key)


## Forget the row: its target, its node and, if Combat opened it, its actor id. O(1).
func _free_row(row: int) -> void:
	var node: Variant = _nodes[row]
	if projectiles != null and is_instance_valid(node):
		projectiles.remove_target(node as Node2D)
	_row_by_node.erase(_node_id[row])
	var at: int = _live_at[row]
	var last: int = _live[_live.size() - 1]
	_live[at] = last
	_live_at[last] = at
	_live.resize(_live.size() - 1)
	_live_at[row] = -1
	if _owned[row] != 0:
		var table: ActorsScript = _table()
		if table != null and table.is_open(row):
			var holder: Node = table.node_of(row)
			if holder == null or holder == node:
				table.close(row)
	for seat in PLAYER_SLOTS:
		if _seat_row[seat] == row:
			_seat_row[seat] = ActorsScript.NONE
	_body[row] = BODY_NONE
	_owned[row] = 0
	_nodes[row] = null
	_node_id[row] = 0
	_clear_state(row)


## Statuses, push, barrier, reaction wait and slam off.
func _clear_state(row: int) -> void:
	_knock[row] = Vector2.ZERO
	for st in STATUS_COUNT:
		_status_left[row * STATUS_COUNT + st] = 0.0
		_status_power[row * STATUS_COUNT + st] = 0.0
	_burn_carry[row] = 0.0
	_burn_by[row] = EventsScript.NO_PLAYER
	_chill_stacks[row] = 0
	_react_wait[row] = 0.0
	var shielded: bool = _shield_left[row] > 0.0
	_shield[row] = 0
	_shield_left[row] = 0.0
	if shielded:
		_send_barrier(row, Vector2.ZERO)
	_shield_tag[row] = 0
	_slam[row] = 0
	_slam_by[row] = EventsScript.NO_PLAYER


## The row of `actor`: an actor id (the row itself, or the row of the body that casts under that
## id) or a node. NONE when not registered.
func _row_of(actor: Variant) -> int:
	if actor is int:
		var id: int = actor
		if id < 0 or id >= ACTORS:
			return ActorsScript.NONE
		if _body[id] != BODY_NONE:
			# A body freed since the last step is no actor any more.
			return id if is_instance_valid(_nodes[id]) else ActorsScript.NONE
		# A body registered before it opened its own actor (an enemy that casts, until G6).
		var table: ActorsScript = _table()
		var node: Node = table.node_of(id) if table != null else null
		return _row_of_node(node) if node != null else ActorsScript.NONE
	if actor is Object:
		return _row_of_node(actor)
	return ActorsScript.NONE


## The row of a node (a freed one, or one not registered: NONE). Takes a Variant, so a freed
## node can be asked about.
func _row_of_node(node: Variant) -> int:
	if not is_instance_valid(node):
		return ActorsScript.NONE
	return _row_by_node.get((node as Object).get_instance_id(), ActorsScript.NONE)


## True while the row still holds `node`.
func _same(row: int, node: Node2D) -> bool:
	return _body[row] != BODY_NONE and _nodes[row] == node


## The body's own actor id, or NONE (see OWN_ID_PROPERTIES).
func _own_id_of(node: Node2D) -> int:
	if node is Actor:
		var id: int = (node as Actor).id
		return id if id >= 0 and id < ACTORS else ActorsScript.NONE
	for property in OWN_ID_PROPERTIES:
		var value: Variant = node.get(property)
		if value is int and (value as int) >= 0 and (value as int) < ACTORS:
			return value as int
	return ActorsScript.NONE


## The actor the row's body casts as: the row, or for a row Combat opened, the actor its body
## opened since (an enemy's `caster`, until G6).
func _cast_id(row: int) -> int:
	if _owned[row] == 0:
		return row
	var value: Variant = _nodes[row].get(&"caster") if is_instance_valid(_nodes[row]) else null
	return value as int if value is int and (value as int) >= 0 else row


## True while a hit can hurt the row's body: it is there, not down, dying or protected (a kit
## Actor), or has health left (a plain body).
func _can_hurt(row: int) -> bool:
	if not is_instance_valid(_nodes[row]):
		return false
	var node: Node2D = _nodes[row]
	match _body[row]:
		BODY_ACTOR:
			var kit: Actor = node as Actor
			if kit.is_down() or kit.is_dying():
				return false
			return kit.health == null or (not kit.health.is_depleted() and not kit.health.is_protected())
	return _health[row] > 0


func _can_heal(row: int) -> bool:
	if not is_instance_valid(_nodes[row]) or _is_down(row):
		return false
	var node: Node2D = _nodes[row]
	match _body[row]:
		BODY_ACTOR:
			var kit: Actor = node as Actor
			return not kit.is_dying() and (kit.health == null or not kit.health.is_depleted())
		BODY_PLAIN:
			return _health[row] > 0
	return true


## True while the row's body is down (a kit Actor held down: a downed wizard).
func _is_down(row: int) -> bool:
	if not is_instance_valid(_nodes[row]):
		return false
	var node: Node2D = _nodes[row]
	match _body[row]:
		BODY_ACTOR:
			return (node as Actor).is_down()
	return false


## Whom the row aims at (its actor's team), NONE when unknown.
func _team(row: int) -> int:
	var table: ActorsScript = _table()
	return table.team_of(row) if table != null else ActorsScript.NONE


## A team as one bit (NONE is bit 0).
func _team_bit(team: int) -> int:
	return 1 << clampi(team + 1, 0, 30)


## The seat (0-3) that drives the actor `actor`, or Actors.NONE.
func _seat_of(actor: int) -> int:
	var table: ActorsScript = _table()
	return table.seat_of(actor) if table != null else ActorsScript.NONE


## The row of the actor whose home controller has seat `seat`, or NONE.
func _seat_row_of(seat: int) -> int:
	if seat < 0 or seat >= PLAYER_SLOTS:
		return ActorsScript.NONE
	return _seat_row[seat]


## Hand hit-stop the services it holds and stops through: Combat's actor table and projectile
## manager, its registry (else the Registry autoload: a test world built out of the tree has the
## game's content all the same), and the game's sim. At setup and at each step, since a test may
## set them after; the sim once Combat is in the game's tree (a test hands its own).
func _bind_hit_stop() -> void:
	var content: RegistryScript = registry
	if content == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			content = tree.root.get_node_or_null(^"Registry") as RegistryScript
	hit_stop.bind(_table(), projectiles, content)
	if hit_stop.sim == null and is_inside_tree():
		hit_stop.sim = Sim.found(self)


## The actor table: `actors`, else the projectile manager's, else the `Actors` autoload, else
## a table of Combat's own.
func _table() -> ActorsScript:
	if actors != null:
		return actors if is_instance_valid(actors) else null
	if projectiles != null and is_instance_valid(projectiles):
		var shared: ActorsScript = projectiles.actor_table()
		if shared != null:
			return shared
	if _auto_table == null or not is_instance_valid(_auto_table):
		_auto_table = null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			_auto_table = tree.root.get_node_or_null(^"Actors") as ActorsScript
		if _auto_table == null:
			_auto_table = ActorsScript.new()
			add_child(_auto_table)
	return _auto_table


## A cleared scratch list for a grid query, one per nesting depth. Give it back with
## `_give_scratch` before returning.
func _take_scratch() -> Array[Node2D]:
	if _pool_depth >= _pool.size():
		var fresh: Array[Node2D] = []
		_pool.append(fresh)
	var list: Array[Node2D] = _pool[_pool_depth]
	_pool_depth += 1
	list.clear()
	return list


func _give_scratch() -> void:
	_pool_depth -= 1
	(_pool[_pool_depth] as Array).clear()


func _position_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position

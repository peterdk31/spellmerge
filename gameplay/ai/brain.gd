class_name AIBrain
extends RefCounted
## The AI every enemy, minion, boss and test bot plays by (docs/milestones/M2-enemy-ai.md): it
## reads the world and what each of its staffs casts next (`CastSense`, never a card), lets its
## behaviours (`AIBehaviours`) weigh what to do, and carries out the winner's plan by writing an
## `ActorIntent`: where to walk, where to aim, which staff to press or hold. An enemy's
## `AIController` owns one and hands it the actor's own intent; a test bot owns one, hands it a
## spare intent and turns that into virtual buttons.
##
## **Perceiving and deciding** run on the profile's `reaction` timer (staggered per brain), and at
## once when an attack is over or the target was lost, never every step. Targeting is as before:
## the nearest actor of another team that can be hit now (`Projectiles.nearest_target`; a decoy
## is one, chased when it is the nearest), a teammate that hurt it for GRUDGE_TIME (infighting).
##
## **The steps of the executor** (`state`): CHASE (walk as planned, aim at the target, wind up the
## planned staff once it is ready), WINDUP (it presses the staff at once and stands while the
## cast winds up in Spells, its staff's and cards' `wind_up`: docs/milestones/cast-timing.md; it
## keeps aiming at the target, with lead and the profile's aim error drawn once, as a player's aim
## follows the stick (owner, 2026-11-06); the telegraph shows it), CHANNEL (a cast that goes on while held: hold the button while the target
## stays in its lane, the mana lasts and `channel_max` is not up, turning after the target at
## `track_speed`), RECOVER (stand, the aim locked; a shot about to hit may still make it dodge),
## REPOSITION (walk round a wall for REPOSITION_TIME or until the line is clear), TRANSITION (a
## boss changing phase: stand) and CALL (before a windup, with teamwork, a teammate near: it
## glances at the teammate for `TeamBoard.CALL_TIME`, its Face's brows raised, and the board's call
## makes the teammates near keener to join in; then it winds up). A profile that presses on
## (`AIProfile.press_on`, a test bot's) walks toward its target wherever an enemy stands in a
## fight, and with no rest goes on at once. The windup starts only when the staff can cast now
## (`Caster.cast_ready`), and nothing but being downed stops a wind-up, so a telegraph is always
## followed by its cast. An urgent plan (a dodge,
## an escape) presses a staff whose next cast moves the caster once (after that staff's wind-up,
## so a dodging enemy holds its dash on a staff with none), and the move goes the way it walks.
## Its own timers slow by `Combat.pace`; a cast's wind-up is the staff's and does not.
##
## **Harmful floor** (ground cover GC7, docs/milestones/ground-cover.md, rule 8): it asks the floor
## round it through the bus (`cover_danger_looked`, a `CoverSight`), never the cover area. At each
## decision it notes whether it stands in harmful cover and the nearest cell out of it in view
## (`in_harm`, `harm_exit`: `evade` walks there). Every step it walks, it probes the cells along its
## move (every cell to `HARM_PROBE` ahead, past the cell it stands in) and, if one harms, turns to the nearest of
## the eight ways (`AISight.DIRECTIONS`) whose cells do not and whose line is clear of walls, keeping
## to the side it turned last; with none free it walks on as it would. It has no pathfinder: this is
## steering, beside `AISight.detour`.
## **The aim lock** (boss plan OB14, decision 26): with the profile's `aim_lock` above 0 its aim
## stops following the target once the cast it winds up has no more than that left in Spells
## (`Caster.wind_left`), and it tells the lane so (`aim_locked`). **Turns** (`AIProfile.turns`):
## after an attack it may turn to the foe it aimed at longest ago, and keeps that one its target
## until its next attack. **Round blocking props** (decision 36): a pillar's ground stands in its
## line as a wall does (`AISight.ground_clear`, feet to feet), and a walk at the target or to a
## point that would meet one goes round it (`AISight.detour`) instead.
##
## **Enemies telegraph, allies don't** (owner, 2026-11-01): a telegraph is a warning for the
## players. How long a cast winds up is its staff's data (an enemy's staff has a `wind_up`, a
## player's none; cast-timing, owner 2026-11-06), whoever holds it; only a brain driving an actor
## of another team than the players' shows it (`warns()`, `is_telegraphing`). It follows the driven
## actor's team, which is its driver's: a bot, a minion, and an enemy body a player's side drives
## show none; an enemy's AI possessing a wizard still warns.
##
## Nothing here allocates per step.

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

enum State { CHASE, WINDUP, RECOVER, REPOSITION, CHANNEL, TRANSITION, CALL }
## How a plan walks: stand, toward or away from the target, a set way (`plan_way`), or to a point
## (`plan_point`: an item to take, items I9; walked to with or without a target).
enum Move { STAND, TOWARD, AWAY, WAY, POINT }

## Seconds between looking for the nearest target again.
const RETARGET_TIME: float = 0.5
## Seconds it chases a teammate that hurt it before going back to its team's targets.
const GRUDGE_TIME: float = 3.0
## How far it looks for a target: farther than any room, so the nearest anywhere.
const SIGHT: float = 100000.0
## The rings it looks in, nearest first, before the whole room: a target is most often near, and
## a small ring reads a few cells of the target grid where the whole room reads all of them (enemy
## AI L1: the lookup was two thirds of a staffed enemy's step). The nearest of all is the same.
const LOOKS: Array[float] = [160.0, 480.0, SIGHT]
## Closer than this to its target it stops walking (an actor with nothing to cast, on top of it).
const CLOSE_ENOUGH: float = 1.0
## How far ahead (pixels) a way round a wall, or to cover, is probed.
const DETOUR_PROBE: float = 40.0
## The widest its line of fire is taken either side (pixels; `_fire_width`).
const FIRE_WIDTH_MOST: float = 8.0
const COVER_PROBE: float = 48.0
## Seconds it walks one way round a wall before it looks again.
const REPOSITION_TIME: float = 0.4
## The rest after a cast: REST_BASE plus half its delay (at most a second), times `rest_scale`.
const REST_BASE: float = 0.6
## Rests are whole sixteenths of a second, so they read the same on every frame rate and a test's
## fixed step meets them exactly.
const TIME_GRAIN: float = 0.0625
## The widest aim error (radians), at accuracy 0.
const AIM_ERROR: float = deg_to_rad(14.0)
## Dodging: shots within this many pixels of its hurt circle, arriving within the horizon, count;
## one arriving sooner than URGENT_TIME makes the dodge urgent.
const DODGE_MARGIN: float = 6.0
const DODGE_HORIZON: float = 0.9
const URGENT_TIME: float = 0.35
## A target winding up a cast aimed within this (dot of its aim and the way to it) counts as a
## threat this many seconds off (`_read_telegraph`).
const TELEGRAPH_AIM: float = 0.9
const TELEGRAPH_THREAT: float = 0.45
## Seconds it remembers a hit (for guarding).
const HURT_MEMORY: float = 2.0
## Pixels beyond its lane a held cast's target may stray before it lets go.
const LANE_MARGIN: float = 10.0
## The decision timer is the profile's `reaction` times a random factor this far either side, so
## a crowd does not decide in one step.
const REACTION_JITTER: float = 0.2
## Spreading round a target: the most it turns round the target toward its slot in one plan, and
## the bonus Fight gets alone on a target (times teamwork, shared by its attackers).
## The target key of a body that is no open actor (a test's plain node): a target, of no identity.
const NO_KEY: int = -1
const SLOT_TURN: float = deg_to_rad(50.0)
const SPREAD_BONUS: float = 0.1
## Harmful floor (GC7): how far ahead along its move it probes (every cell on the way), how far round it
## it looks each step and at a decision (for the way out), and the bonus the side it turned last gets
## (above any difference of two ways' dots: that side's free ways come first while its way is blocked).
const HARM_PROBE: float = 24.0
const HARM_LOOK: float = 32.0
const HARM_EXIT_LOOK: float = 64.0
const HARM_SIDE_KEEP: float = 2.0
## Turns (boss plan OB14): how many foes it remembers aiming at, and when.
const TURN_MEMORY: int = 8
## Pixels past a target's own ground a walk at it heads for (`_walk_goal`): a wall cell and more.
const GROUND_MARGIN: float = 12.0

## Not state: services, caches and scratch, set up again (core/sim/README.md); the team board is
## Entities' (hashed there), handed over by the controller.
const DERIVED: Array[StringName] = [&"entities", &"board", &"_face", &"_ground", &"_open_ids", &"_cover"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"actor", &"target", &"grudge", &"plan_target", &"_target_actor", &"_turn_to"]

## The actor it drives, the profile it plays by and Entities (its team board; null: none).
var actor: Actor = null
var profile: AIProfile = null
var entities: EntitiesScript = null
## The team board (gameplay/ai/team_board.gd), or null: staggered fire, calls, and where its
## teammates stand and how hurt they are (it reports itself at each decision).
var board: TeamBoard = null
## Its chance (online-ready N3c): its rolls are named by this key (`setup`: per actor, so a test
## repeats) and counted, from the actor's `sim` (`_roll`).
var dice: int = 0
var rolls: int = 0

# What it perceived at its last decision.
## What it chases (an actor, a decoy), or null.
var target: Node2D = null
## The teammate that hurt it last, chased while `grudge_left()` > 0, or null.
var grudge: Node2D = null
## From its body to the target's, and how far.
var to_target: Vector2 = Vector2.ZERO
var distance: float = 0.0
## No wall and no prop's body (a pillar's) between its body and the target's, and no blocking
## body's ground between their feet: an aimed shot would reach it.
var line_clear: bool = true
## No blocking body's ground (a pillar's) nor a hole (hub rework HR-H2) between its feet and the
## target's: a walk at it is not held up by one (boss plan OB14).
var ground_clear: bool = true
## Seconds until the soonest shot coming at it arrives (-1 for none), and the way off its line.
var threat_time: float = -1.0
var threat_away: Vector2 = Vector2.ZERO
## It stands in harmful cover (GC7), and the middle of the nearest cell out of it with no wall between
## (Vector2.INF for none in sight).
var in_harm: bool = false
var harm_exit: Vector2 = Vector2.INF
## Seconds since a hit it still remembers (counting down from HURT_MEMORY; 0 for none).
var hurt_left: float = 0.0
## Its health as a fraction of the most (1 without Health).
var health_fraction: float = 1.0
## The range its staffs give (reach × (0.75 - 0.6 aggression) to reach × (0.95 - 0.35
## aggression)): closer than `band_min` it steps back, farther than `band_max` it walks in (both 0 when nothing it casts hurts: it walks into its target).
var band_min: float = 0.0
var band_max: float = 0.0
## Its staffs now: how many, what each casts next, whether it is ready (within its windup) and
## whether its sustained cast is on (a press would switch it off, so it is left alone).
var staff_count: int = 0
var senses: Array[CastSense] = [null, null, null, null]
var ready: PackedByteArray = PackedByteArray([0, 0, 0, 0])
var holding: PackedByteArray = PackedByteArray([0, 0, 0, 0])
## Spreading round its target (teamwork above 0; `TeamBoard`): how many of its team attacked its
## target at the board's last count (itself too; 0 for none) and the angle (from the target) of
## its own slot round it.
var attackers: int = 0
var slot_angle: float = 0.0
## Seconds this brain has thought (for behaviours' memos).
var clock: float = 0.0

# What it decided.
var behaviour: AIBehaviour = null
var plan_staff: int = -1
var plan_move: Move = Move.STAND
var plan_way: Vector2 = Vector2.ZERO
## Where a POINT plan walks to (room pixels).
var plan_point: Vector2 = Vector2.ZERO
## Where the run-up (boss plan OB14) found to start its move, between its `want` and its `act`
## (Vector2.INF: cast it from here).
var run_up_point: Vector2 = Vector2.INF
## When (its `clock`) the run-up under way started.
var run_up_since: float = 0.0
var plan_urgent: bool = false
## What the planned staff is aimed at when not `target` (a teammate to heal); null for `target`.
var plan_target: Node2D = null
## Per behaviour: a staff it picked in `want` for `act`, and a number it keeps (`AIBehaviour`).
var picks: PackedInt32Array = PackedInt32Array()
var memo: PackedFloat32Array = PackedFloat32Array()

# Carrying it out.
var state: State = State.CHASE
## The staff wound up, channelled or cast last (-1 before the first).
var chosen: int = -1
## The windup and rest of the attack under way (0 before the first).
var windup_time: float = 0.0
var recover_time: float = 0.0
## How often it looked for a target (tests count it).
var lookup_count: int = 0

var _chosen_sense: CastSense = null
## The intent `think` wrote last (the actor's own, or a bot's spare one), for letting go of holds.
var _last_intent: ActorIntent = null
var _locked_aim: Vector2 = Vector2.DOWN
## The aim error of the attack under way (radians), drawn once as it starts winding up.
var _aim_error: float = 0.0
## The attack under way stopped following its target (its profile's `aim_lock`).
var _aim_locked: bool = false
## Turns: the keys of the foes it aimed at (0: a free row) and when (its `clock`), whether it turns
## after the attack under way, and the foe it turned to (null: none), kept its target until its
## next attack.
var _aimed_keys: PackedInt64Array = PackedInt64Array()
var _aimed_at: PackedFloat32Array = PackedFloat32Array()
var _turn_due: bool = false
var _turn_to: Node2D = null
## Scratch: the open actors' ids, read when it turns.
var _open_ids: PackedInt32Array = PackedInt32Array()
var _state_left: float = 0.0
var _channel_left: float = 0.0
var _decide_left: float = 0.0
var _retarget_left: float = 0.0
var _retarget_offset: float = 0.0
var _grudge_left: float = 0.0
var _looked: bool = false
var _decide_now: bool = true
var _tapped: bool = false
var _strafe_side: float = 1.0
## The key of `target` when it was chosen (`Actors.key_of`, N5; NO_KEY for a body of no actor), or 0
## for none; `target` typed when an actor.
var _target_id: int = 0
var _target_actor: Actor = null
## The actor's Face (the actor kit's), for the call's glance; null without one.
var _face: Face = null
## What it saw lying round it at its last look (`look_ground`), made once: scratch, filled and read
## within one decision.
var _ground: GroundSight = GroundSight.new()
## Where the floor round it harms (`look_harm`), made once: scratch, filled and read within one step.
var _cover: CoverSight = CoverSight.new()
## The side (the sign of the cross of its move and the way it turned to) it last turned off harmful
## floor, 0 before the first and once its way is clear again: kept while it walks round a fire, so it
## goes round one way and does not swing between two.
var _steer_side: float = 0.0
## The last call of its team it has heard (`TeamBoard.called_at`).
var _heard_call: float = -INF
## Its slot on the board at its last report and at its last noted attack (-1 for none).
var _report_slot: int = -1
var _attack_slot: int = -1


## Start driving `with_actor` by `with_profile` (null: the shared default). `seed_value` names its
## rolls and staggers its timers.
func setup(with_actor: Actor, with_profile: AIProfile, seed_value: int) -> void:
	actor = with_actor
	profile = with_profile if with_profile != null else AIProfile.fallback()
	dice = seed_value
	rolls = 0
	_retarget_offset = RETARGET_TIME * float(absi(seed_value) % 8) / 8.0
	_strafe_side = 1.0 if seed_value % 2 == 0 else -1.0
	_face = null
	for child in actor.get_children():
		if child is Face:
			_face = child as Face
			break
	var count: int = AIBehaviours.all().size()
	if picks.size() != count:
		picks.resize(count)
		memo.resize(count)
	reset()


## A fresh start: no target, no grudge, no attack, no plan; holds let go.
func reset() -> void:
	state = State.CHASE
	target = null
	_target_id = 0
	_target_actor = null
	grudge = null
	_grudge_left = 0.0
	_turn_due = false
	_turn_to = null
	_aimed_keys.resize(TURN_MEMORY)
	_aimed_at.resize(TURN_MEMORY)
	_aimed_keys.fill(0)
	_aimed_at.fill(0.0)
	_state_left = 0.0
	_looked = false
	_retarget_left = _retarget_offset
	_decide_now = true
	in_harm = false
	harm_exit = Vector2.INF
	_steer_side = 0.0
	behaviour = null
	_clear_plan()
	if _last_intent != null and chosen >= 0:
		_last_intent.hold(chosen, false)
	chosen = -1
	for i in memo.size():
		memo[i] = -INF


## Think one step of `delta` seconds and write `intent` (the actor's own, or a bot's spare one).
func think(delta: float, intent: ActorIntent) -> void:
	_last_intent = intent
	clock += delta
	_retarget_left -= delta
	_decide_left -= delta
	hurt_left = maxf(hurt_left - delta, 0.0)
	if _grudge_left > 0.0:
		_grudge_left -= delta
		if _grudge_left <= 0.0 or not _is_valid_target(grudge):
			_drop_grudge()
	_track_target()
	intent.move = Vector2.ZERO
	match state:
		State.CHASE:
			if board != null and profile.teamwork > 0.0 and board.called_at(actor.team()) > _heard_call:
				# A teammate called: decide at once whether to join in.
				_heard_call = board.called_at(actor.team())
				_decide_now = true
			if _decide_left <= 0.0 or _decide_now:
				_perceive()
				_decide()
			_chase(intent)
		State.WINDUP:
			# The cast winds up in Spells; the aim follows the target until it leaves, or until its
			# profile's lock (measured against the wind-up the cast has left, so a chill moves it).
			if not _aim_locked and profile.aim_lock > 0.0 and actor.caster != null and actor.caster.is_winding(chosen) and actor.caster.wind_left(chosen) <= profile.aim_lock:
				_aim_locked = true
				if warns() and actor.events != null:
					actor.events.aim_locked.emit(actor.id, chosen)
			var aimed: Node2D = _aim_node()
			if aimed != null and not _aim_locked:
				_locked_aim = _aim_for(_chosen_sense, aimed.global_position - actor.global_position, _aim_error)
			intent.aim = _locked_aim
			_press_on(intent)
			# Its own clock only shows the telegraph's progress, slowed as the wind-up is (a chill,
			# a freeze: `Caster` holds the cast in Spells); the attack goes on once the cast left.
			_state_left = maxf(_state_left - delta * _pace(), 0.0)
			if actor.caster == null or not actor.caster.is_winding(chosen):
				_release(intent)
		State.CHANNEL:
			_channel(delta, intent)
		State.RECOVER:
			intent.aim = _locked_aim
			_press_on(intent)
			_state_left -= delta * _pace()
			if _decide_left <= 0.0 and (profile.dodge > 0.0 or _can_block()):
				# Resting is no promise: a shot about to hit may still make it move.
				_decide_left = _reaction()
				_perceive_threat()
				if threat_time >= 0.0 and threat_time < URGENT_TIME * 2.0:
					_state_left = 0.0
			if _state_left <= 0.0:
				_attack_over()
		State.REPOSITION:
			_state_left -= delta
			# Over once it can shoot (a hole is no wall to a shot, HR-H2).
			if target == null or _state_left <= 0.0 or (_ground_clear_now(false) and _line_clear()):
				_to_chase()
				_perceive()
				_decide()
				_chase(intent)
			else:
				intent.move = plan_way
				intent.aim = to_target
		State.TRANSITION:
			_state_left -= delta
			if _state_left <= 0.0:
				_to_chase()
		State.CALL:
			_call(delta, intent)
	_steer_off_harm(intent)


## True from the start of a windup until its cast leaves: the attack is coming.
func is_telegraphing() -> bool:
	# Read from the cast itself, so the warning ends the step the cast leaves.
	return state == State.WINDUP and warns() and actor.caster != null and actor.caster.is_winding(chosen)


## 0.0 at the start of the telegraph, 1.0 when the cast leaves; 0.0 when not telegraphing.
func telegraph_progress() -> float:
	if not is_telegraphing() or windup_time <= 0.0:
		return 0.0
	return clampf(1.0 - _state_left / windup_time, 0.0, 1.0)


## The staff the telegraph is for: the one wound up, else the one planned, else 0.
func telegraph_staff() -> int:
	if chosen >= 0:
		return chosen
	return maxi(plan_staff, 0)


## False while the actor it drives is on the players' team: an ally gives no warning.
func warns() -> bool:
	return actor == null or actor.team() != ActorsScript.TEAM_WIZARDS


## The windup the next attack of staff `at` would take (seconds): its cast's wind-up, its staff's
## and its cards' (`CastSense.wind_up`; docs/milestones/cast-timing.md), whoever drives it.
func windup_for(at: int) -> float:
	var sense: CastSense = _sense_of(at)
	return sense.wind_up if sense != null else 0.0


## The rest after a cast of staff `at` (seconds).
func rest_for(at: int) -> float:
	var sense: CastSense = _sense_of(at)
	var delay: float = sense.delay if sense != null else 0.0
	return snappedf((REST_BASE + minf(delay, 1.0) * 0.5) * profile.rest_scale, TIME_GRAIN)


## Seconds the grudge still lasts (0 for none).
func grudge_left() -> float:
	return maxf(_grudge_left, 0.0) if grudge != null else 0.0


## The actor it drives was hurt by the actor `caster` (any hit): remembered for guarding, and an
## actor of its own team (not itself) earns a grudge.
func hurt_by(caster: int) -> void:
	hurt_left = HURT_MEMORY
	if actor == null or caster < 0 or caster == actor.id or actor.actors == null:
		return
	if actor.actors.team_of(caster) != actor.team():
		return
	var attacker: Node2D = actor.actors.node_of(caster) as Node2D
	if attacker == null or attacker == actor or not _is_valid_target(attacker):
		return
	carry_grudge(attacker, GRUDGE_TIME)


## Chase `attacker` for `seconds`, as if hurt by it just now.
func carry_grudge(attacker: Node2D, seconds: float) -> void:
	if seconds <= 0.0 or not _is_valid_target(attacker):
		return
	grudge = attacker
	_grudge_left = seconds
	_retarget_left = 0.0


## A boss changes phase: stand `seconds`, no attack; the profile `next` from now on (null: keep).
func transition(seconds: float, next: AIProfile) -> void:
	if next != null:
		profile = next
	if chosen >= 0 and _last_intent != null:
		_last_intent.hold(chosen, false)
	state = State.TRANSITION
	_state_left = seconds
	_decide_now = true


## Its staffs changed (a new build, a boss's phase): decide again at once.
func staffs_changed() -> void:
	_decide_now = true


## Behaviours ask: does the next cast `sense` reach the target from here (or `other`, when
## given: a teammate)?
func reaches(sense: CastSense, other: Node2D = null) -> bool:
	var far: float = distance if other == null else actor.global_position.distance_to(other.global_position)
	var radius: float = _target_radius() if other == null else _radius_of(other)
	if sense.reach > 0.0:
		return far <= sense.reach * 0.95 + radius
	return far <= maxf(sense.close_reach, 24.0) + radius


## Behaviours ask: of its teammates the board has under `TeamBoard.HURT` (itself not), the most
## hurt that a cast of `sense` reaches along a clear line, or null.
func hurt_mate(sense: CastSense) -> Actor:
	if board == null or actor.actors == null:
		return null
	var team: int = actor.team()
	var best: Actor = null
	var lowest: float = TeamBoard.HURT
	for slot in TeamBoard.PLACES:
		var who: int = board.mate(team, slot)
		if who < 0 or who == actor.id or board.mate_health(team, slot) >= TeamBoard.HURT:
			continue
		if actor.actors.team_of(who) != team:
			continue
		var mate: Actor = actor.actors.node_of(who) as Actor
		if mate == null or not _is_valid_target(mate):
			continue
		var share: float = health_of(mate)
		if share >= lowest or not reaches(sense, mate):
			continue
		var width: float = minf(sense.radius, FIRE_WIDTH_MOST)
		if sense.reach > 0.0 and not AISight.fire_clear(actor.projectiles, actor.global_position + actor.body_offset, mate.global_position + mate.body_offset, width, _fire_short(mate, width)):
			continue
		best = mate
		lowest = share
	return best


## Behaviours ask: the health of `body` now, a share of its most (1 without Health).
static func health_of(body: Actor) -> float:
	if body == null or body.health == null or body.health.max_health <= 0.0:
		return 1.0
	return body.health.health / body.health.max_health


## Behaviours ask: a way to cover from the target within reach (a wall between), or ZERO.
func cover_from_target() -> Vector2:
	if actor == null or target == null:
		return Vector2.ZERO
	return AISight.cover(actor.projectiles, actor.global_position, target.global_position, COVER_PROBE)


## Behaviours ask: how keen the team leaves it to start an attack now (1: as keen as it is; less
## just after a teammate started one, so a barrage reads as a sequence: `TeamBoard`).
func team_beat() -> float:
	if board == null or actor == null:
		return 1.0
	return board.beat(actor.team(), actor.id, profile.teamwork, actor.global_position)


## Behaviours ask: how far round its target its slot is from where it stands (radians, 0 to PI);
## 0 with no slot to keep (alone on it, or no teamwork).
func slot_off() -> float:
	if attackers < 2 or target == null or to_target == Vector2.ZERO:
		return 0.0
	return absf(angle_difference(DMath.angle(-to_target), slot_angle))


## Behaviours ask: the way to its slot round the target, at the middle of its band (turning round
## the target at most SLOT_TURN at a time, so it walks round and not through), or ZERO with no
## slot to keep.
func slot_way() -> Vector2:
	if attackers < 2 or target == null or band_max <= 0.0 or to_target == Vector2.ZERO:
		return Vector2.ZERO
	var now: float = DMath.angle(-to_target)
	var turn: float = clampf(angle_difference(now, slot_angle), -SLOT_TURN, SLOT_TURN)
	var point: Vector2 = target.global_position + DMath.from_angle(now + turn) * (band_min + band_max) * 0.5
	var way: Vector2 = point - actor.global_position
	return way.normalized() if way.length_squared() > 1.0 else Vector2.ZERO


## Behaviours ask: how far a move of `sense` (one that runs it along, a dash) would run from where
## it stands at the target before a wall or a blocking body's ground holds it up (pixels, at most
## its `move_reach`; boss plan OB14, the run-up).
func run_here(sense: CastSense) -> float:
	if target == null or sense == null:
		return 0.0
	return AISight.run_along(actor.projectiles, actor.global_position, to_target, sense.move_reach, actor.wall_radius())


## Behaviours ask: where to stand to run a move of `sense` at the target the longest way (a wall's
## foot facing the open room, `AISight.run_up_spot`), and how far it would run from there: a
## Vector3 of the place (x, y) and the run (z); z is -1 when there is no such place.
func run_up(sense: CastSense) -> Vector3:
	if target == null or sense == null:
		return Vector3(0.0, 0.0, -1.0)
	var radius: float = actor.wall_radius()
	var spot: Vector2 = AISight.run_up_spot(actor.projectiles, actor.global_position, target.global_position, sense.move_reach, radius)
	if spot == Vector2.INF:
		return Vector3(0.0, 0.0, -1.0)
	var run: float = AISight.run_along(actor.projectiles, spot, target.global_position - spot, sense.move_reach, radius)
	return Vector3(spot.x, spot.y, run)


## Behaviours ask: a little more keenness to fight a target few of its team attack (teamwork).
func spread_bonus() -> float:
	if attackers <= 0:
		return 0.0
	return profile.teamwork * SPREAD_BONUS / float(attackers)


## Behaviours ask: what lies within `reach` of its feet (items I9: a `GroundSight`, the nearest
## first, each with whether it is in reach to take), asked of the ground through the bus
## (`ground_looked`), never of the Items area; empty with no bus. Filled anew at each look.
func look_ground(reach: float) -> GroundSight:
	_ground.clear()
	if actor != null and actor.events != null:
		actor.events.ground_looked.emit(actor.id, actor.global_position, reach, _ground)
	return _ground


## Behaviours ask: what its last look saw (`look_ground`'s sight, as it was filled), without looking
## again: a behaviour's `act` reads what its `want` looked at in the same decision.
func seen_ground() -> GroundSight:
	return _ground


## Behaviours ask: where the floor within `reach` of its feet would harm it (GC7: a `CoverSight`),
## asked of the cover through the bus (`cover_danger_looked`), never of the cover area; empty with no
## bus. Filled anew at each look.
func look_harm(reach: float) -> CoverSight:
	_cover.clear()
	if actor != null and actor.events != null:
		actor.events.cover_danger_looked.emit(actor.id, actor.global_position, reach, _cover)
	return _cover


## Behaviours ask: take the item `item` off the ground now (`actor_take_requested`: the Items area
## gives it to its Inventory as the pickup rule says, if it lies in reach and there is room).
func take_item(item: int) -> void:
	if actor != null and actor.events != null:
		actor.events.actor_take_requested.emit(actor.id, item)


## Behaviours ask: walk round the wall or prop in the line for a while (REPOSITION): to a step
## near from which a shot would reach the target (`AISight.flank`), else round the way at it
## (`AISight.detour`).
func reposition() -> void:
	plan_move = Move.WAY
	plan_way = Vector2.ZERO
	if target != null:
		plan_way = AISight.flank(actor.projectiles, actor.global_position, _walk_goal(), _target_body(), actor.body_offset, DETOUR_PROBE, _fire_width(), _fire_short(target))
	if plan_way == Vector2.ZERO:
		plan_way = AISight.detour(actor.projectiles, actor.global_position, _walk_goal(), DETOUR_PROBE)
	state = State.REPOSITION
	_state_left = REPOSITION_TIME


# --- perceiving ---


func _track_target() -> void:
	var lost: bool = false
	if _target_id != 0:
		if _target_actor != null:
			lost = not is_instance_valid(_target_actor) or _target_actor.is_down() or _target_actor.is_dying()
		else:
			lost = not _is_valid_target(target)
	if _retarget_left <= 0.0 or lost or not _looked:
		_retarget_left = RETARGET_TIME if _looked else _retarget_offset
		_looked = true
		var before: int = _target_id
		target = _find_target()
		_target_id = _key_of(target)
		_target_actor = target as Actor
		if _target_id != before:
			_decide_now = true


## The identity of the body `body` (online-ready N5): its actor's key (`Actors.key_of`), NO_KEY for a
## body that is no open actor, 0 for none.
func _key_of(body: Node2D) -> int:
	if body == null:
		return 0
	var as_actor: Actor = body as Actor
	if as_actor != null and actor != null and actor.actors != null:
		var key: int = actor.actors.key_of(as_actor.id)
		if key != 0:
			return key
	return NO_KEY


func _perceive() -> void:
	_decide_left = _reaction()
	_decide_now = false
	# Its staffs first: the line of fire is as wide as its shots (`_fire_width`).
	_read_staffs()
	if target != null:
		to_target = target.global_position - actor.global_position
		distance = to_target.length()
		ground_clear = _ground_clear_now()
		# A hole is no wall to a shot (HR-H2): the line of fire minds only a blocking body's ground.
		line_clear = (ground_clear or _ground_clear_now(false)) and _line_clear()
		_note_attack()
	else:
		to_target = Vector2.ZERO
		distance = 0.0
		line_clear = true
		ground_clear = true
		attackers = 0
	health_fraction = health_of(actor)
	if board != null:
		_report_slot = board.report(actor.team(), actor.id, actor.global_position, health_fraction, _report_slot)
	_perceive_threat()
	_perceive_harm()


func _perceive_threat() -> void:
	threat_time = -1.0
	threat_away = Vector2.ZERO
	if actor.projectiles == null or (profile.dodge <= 0.0 and not _can_block()):
		return
	var radius: float = (actor.hurtbox.outer_radius() if actor.hurtbox != null else 8.0) + DODGE_MARGIN
	threat_time = actor.projectiles.threat(actor.global_position + actor.body_offset, radius, actor.team(), actor.id, DODGE_HORIZON)
	threat_away = actor.projectiles.threat_away
	if threat_time < 0.0:
		_read_telegraph()
	if threat_time >= 0.0 and profile.dodge > 0.0 and profile.randomness > 0.0 and _roll() < profile.randomness * 0.3:
		# Sometimes it sees the shot late.
		threat_time = -1.0


## Whether it stands in harmful cover, and the nearest cell's middle out of it with no wall between
## (`harm_exit`; on a tie the first in row order, the topmost).
func _perceive_harm() -> void:
	in_harm = false
	harm_exit = Vector2.INF
	var at: Vector2 = actor.global_position
	var sight: CoverSight = look_harm(HARM_EXIT_LOOK)
	if not sight.harms(at):
		return
	in_harm = true
	var best: float = INF
	for y in range(sight.origin.y, sight.origin.y + sight.rows):
		for x in range(sight.origin.x, sight.origin.x + sight.columns):
			var cell := Vector2i(x, y)
			if sight.harms_cell(cell):
				continue
			var middle: Vector2 = CoverSight.middle(cell)
			var far: float = middle.distance_squared_to(at)
			if far < best and AISight.line_clear(actor.projectiles, at, middle):
				best = far
				harm_exit = middle


## With teamwork, it notes its target on the board and reads its slot round it (`TeamBoard`).
func _note_attack() -> void:
	if board == null or profile.teamwork <= 0.0:
		attackers = 0
		return
	var team: int = actor.team()
	_attack_slot = board.note_attack(team, actor.id, _target_id, target.global_position, actor.global_position, _attack_slot)
	attackers = board.attackers(team, _attack_slot, actor.id)
	slot_angle = board.slot_angle(team, _attack_slot) if attackers > 0 else 0.0


## Its target winds up a cast aimed at it (a telegraph is there to be read, as a person reads it):
## a threat about TELEGRAPH_THREAT seconds off, the way off its line on the side it already is.
func _read_telegraph() -> void:
	if _target_actor == null or _target_actor.controller == null or not _target_actor.controller.is_telegraphing():
		return
	var from_it: Vector2 = actor.global_position - _target_actor.global_position
	if from_it == Vector2.ZERO or _target_actor.aim.dot(from_it.normalized()) < TELEGRAPH_AIM:
		return
	threat_time = TELEGRAPH_THREAT
	var side: Vector2 = from_it - _target_actor.aim * from_it.dot(_target_actor.aim)
	threat_away = side.normalized() if side.length_squared() > 1.0 else _target_actor.aim.orthogonal() * _strafe_side


## True when some staff's next cast stops shots (so shots coming are worth looking for).
func _can_block() -> bool:
	for at in staff_count:
		if senses[at] != null and senses[at].blocks:
			return true
	return false


## What each staff casts next, which are ready and the range band they give.
func _read_staffs() -> void:
	var caster: Caster = actor.caster
	staff_count = caster.staff_count if caster != null else 0
	band_min = 0.0
	band_max = 0.0
	var best: float = 0.0
	var blast: float = 0.0
	for at in senses.size():
		var sense: CastSense = caster.next_cast_sense(at) if at < staff_count else null
		senses[at] = sense
		holding[at] = 1 if sense != null and caster.is_holding(at) else 0
		ready[at] = 1 if sense != null and not sense.empty and caster.cast_ready(windup_for(at), at) else 0
		if sense == null or sense.empty or not sense.harms() or sense.moves_caster:
			continue
		var reach: float = sense.reach if sense.reach > 0.0 else sense.close_reach
		best = maxf(best, reach)
		blast = maxf(blast, sense.blast)
	if best > 0.0:
		# The bolder, the nearer it fights: a slow shot from afar is easy to dodge.
		band_max = best * (0.95 - 0.35 * profile.aggression)
		band_min = clampf(best * (0.75 - 0.6 * profile.aggression), 0.0, band_max * 0.9)
		if blast > 0.0:
			band_min = minf(maxf(band_min, blast + 12.0), band_max)


# --- deciding ---


func _decide() -> void:
	var list: Array[AIBehaviour] = AIBehaviours.all()
	var best: AIBehaviour = null
	var best_want: float = 0.0
	var second: AIBehaviour = null
	var second_want: float = 0.0
	for candidate: AIBehaviour in list:
		var wanted: float = candidate.want(self)
		if wanted <= 0.0:
			continue
		if candidate == behaviour:
			wanted += profile.commitment * 0.3
		if wanted > best_want:
			second = best
			second_want = best_want
			best = candidate
			best_want = wanted
		elif wanted > second_want:
			second = candidate
			second_want = wanted
	# Standing in harmful cover with a way out, it takes no chance (GC7): it does not roll.
	if second != null and not (in_harm and harm_exit != Vector2.INF) and second_want >= best_want * 0.7 and _roll() < profile.randomness * 0.5:
		best = second
	behaviour = best
	_clear_plan()
	if best != null:
		best.act(self)
	_steer()


## A walk at the target, or to a point while it has one, that a blocking body's ground (a pillar)
## would hold up goes round it instead (boss plan OB14, decision 36), looked at again at its next
## decision. An urgent one (a dodge) goes as it is.
func _steer() -> void:
	if plan_urgent or target == null or actor.projectiles == null:
		return
	var goal: Vector2 = Vector2.INF
	if plan_move == Move.TOWARD and not ground_clear:
		goal = _walk_goal()
	elif plan_move == Move.POINT and not AISight.feet_clear(actor.projectiles, actor.global_position, plan_point):
		goal = plan_point
	if goal == Vector2.INF:
		return
	plan_move = Move.WAY
	plan_way = AISight.detour(actor.projectiles, actor.global_position, goal, DETOUR_PROBE)


func _clear_plan() -> void:
	plan_staff = -1
	plan_move = Move.STAND
	plan_way = Vector2.ZERO
	plan_point = Vector2.ZERO
	plan_urgent = false
	plan_target = null


# --- carrying it out ---


func _chase(intent: ActorIntent) -> void:
	if plan_move == Move.POINT:
		# A walk to a point (an item to take) goes on whether or not there is a target to aim at.
		intent.move = _to_point()
	var aimed: Node2D = _aim_node()
	if aimed == null:
		return
	var now: Vector2 = aimed.global_position - actor.global_position
	if now != Vector2.ZERO:
		intent.aim = now
	var aim_way: Vector2 = now
	if aimed != target:
		# The plan aims at a teammate; it walks as planned by its target.
		now = target.global_position - actor.global_position if target != null else Vector2.ZERO
	match plan_move:
		Move.TOWARD:
			if now.length_squared() > CLOSE_ENOUGH * CLOSE_ENOUGH:
				intent.move = now.normalized()
		Move.AWAY:
			intent.move = -now.normalized() if now != Vector2.ZERO else Vector2.ZERO
		Move.WAY:
			intent.move = plan_way
		Move.STAND:
			_press_on(intent)
	if plan_urgent:
		if not _tapped and intent.move != Vector2.ZERO:
			var mover: int = _ready_mover()
			if mover >= 0 and _lands_on_ground(mover, intent.move):
				intent.press(mover)
				_tapped = true
	else:
		_tapped = false
	if plan_staff < 0 or actor.caster == null:
		return
	var windup: float = windup_for(plan_staff)
	if not actor.caster.cast_ready(0.0, plan_staff):
		# Not ready yet: wait as planned, so the telegraph only ever shows a cast that comes.
		return
	var moved: CastSense = _sense_of(plan_staff)
	if moved != null and moved.moves_caster and not _lands_on_ground(plan_staff, intent.move if intent.move != Vector2.ZERO else aim_way):
		# Its own move would leave it over a hole (HR-H2): not cast; it walks as planned.
		return
	if _begin_call(windup, intent):
		return
	_begin_windup(plan_staff, windup, aim_way, intent)


## Before an attack that winds up, with teamwork (as often as `teamwork`), its team not calling
## lately and a teammate within `TeamBoard.CALL_REACH` on the board: it calls (CALL). Returns
## whether it did.
func _begin_call(windup: float, intent: ActorIntent) -> bool:
	if board == null or profile.teamwork <= 0.0 or windup <= 0.0 or plan_target != null:
		return false
	var team: int = actor.team()
	if not board.can_call(team) or board.is_calling(team):
		return false
	var sense: CastSense = _sense_of(plan_staff)
	if sense == null or not sense.harms():
		return false
	var mate: Vector2 = board.nearest_mate(team, actor.id, actor.global_position, TeamBoard.CALL_REACH)
	if mate == Vector2.INF or _roll() >= profile.teamwork:
		return false
	state = State.CALL
	_state_left = TeamBoard.CALL_TIME
	intent.move = Vector2.ZERO
	board.call_attack(team, actor.id, actor.global_position)
	_heard_call = board.called_at(team)
	if _face != null and is_instance_valid(_face):
		_face.glance(mate - actor.global_position, TeamBoard.CALL_TIME)
	return true


## Calling: stand, aim at the target, then wind up the planned staff if it is still ready.
func _call(delta: float, intent: ActorIntent) -> void:
	if target == null:
		_to_chase()
		return
	var now: Vector2 = target.global_position - actor.global_position
	if now != Vector2.ZERO:
		intent.aim = now
	_state_left -= delta * _pace()
	if _state_left > 0.0:
		return
	var windup: float = windup_for(plan_staff) if plan_staff >= 0 else 0.0
	if plan_staff >= 0 and actor.caster != null and actor.caster.cast_ready(0.0, plan_staff):
		_begin_windup(plan_staff, windup, now, intent)
	else:
		_to_chase()


## The attack starts: the staff is pressed now and its cast winds up in Spells for `windup`
## seconds (docs/milestones/cast-timing.md); with none it leaves this step.
func _begin_windup(at: int, windup: float, now: Vector2, intent: ActorIntent) -> void:
	chosen = at
	_chosen_sense = _sense_of(at)
	_aim_locked = false
	_note_aimed()
	windup_time = windup
	recover_time = rest_for(at)
	state = State.WINDUP
	_state_left = windup
	_aim_error = (_roll() * 2.0 - 1.0) * (1.0 - profile.accuracy) * AIM_ERROR
	_locked_aim = _aim_for(_chosen_sense, now, _aim_error)
	intent.aim = _locked_aim
	intent.press(at)
	_press_on(intent)
	if board != null:
		board.started(actor.team(), actor.id)
	if windup <= 0.0:
		_release(intent)


## The windup is over and the cast has left: it channels or rests.
func _release(intent: ActorIntent) -> void:
	var sense: CastSense = _chosen_sense
	if sense != null and sense.repeats_held and not sense.sustained and profile.channel_max > 0.0:
		state = State.CHANNEL
		_channel_left = profile.channel_max
		intent.hold(chosen, true)
		return
	if recover_time <= 0.0:
		# No rest (rest_scale 0): it goes on at once.
		_attack_over()
		return
	state = State.RECOVER
	_state_left = recover_time


func _channel(delta: float, intent: ActorIntent) -> void:
	_channel_left -= delta * _pace()
	var sense: CastSense = _chosen_sense
	var aimed: Node2D = _aim_node()
	var keep: bool = _channel_left > 0.0 and aimed != null and sense != null and actor.caster != null
	if keep:
		var now: Vector2 = aimed.global_position - actor.global_position
		if profile.track_speed > 0.0 and now != Vector2.ZERO:
			var turn: float = deg_to_rad(profile.track_speed) * delta * _pace()
			var off: float = DMath.angle_to(_locked_aim, now)
			_locked_aim = DMath.rotated(_locked_aim, clampf(off, -turn, turn))
		keep = _in_lane(sense, now, _radius_of(aimed)) and actor.caster.free_mana(chosen) >= sense.mana
	intent.aim = _locked_aim
	_press_on(intent)
	if keep:
		intent.hold(chosen, true)
		return
	intent.hold(chosen, false)
	state = State.RECOVER
	_state_left = recover_time


## True while what it aims at (`now` away, `radius` round) stands where a held cast along the aim
## still meets it.
func _in_lane(sense: CastSense, now: Vector2, radius: float) -> bool:
	var reach: float = sense.reach if sense.reach > 0.0 else sense.close_reach
	var along: float = now.dot(_locked_aim)
	if along < -LANE_MARGIN or along > reach + LANE_MARGIN + radius:
		return false
	if sense.reach <= 0.0:
		return true
	var across: float = absf(now.cross(_locked_aim))
	return across <= sense.radius + radius + LANE_MARGIN


func _to_chase() -> void:
	state = State.CHASE
	_decide_now = true


## Every step it walks: the cells along its move (every cell to HARM_PROBE ahead, past the one it stands in) are
## probed, and when one harms its move turns to the nearest of the eight ways whose cells do not and
## whose line is clear of walls (on the side it turned last first, while it walks round), at the same
## speed; with no such way it walks on as it would. Looks only while it walks, and costs one ask when no cell harms.
func _steer_off_harm(intent: ActorIntent) -> void:
	var move: Vector2 = intent.move
	if move == Vector2.ZERO or actor == null or actor.events == null:
		return
	var at: Vector2 = actor.global_position
	var sight: CoverSight = look_harm(HARM_LOOK)
	if sight.count == 0:
		_steer_side = 0.0
		return
	var way: Vector2 = move.normalized()
	if _clear_of_harm(sight, at, way):
		_steer_side = 0.0
		return
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for other: Vector2 in AISight.DIRECTIONS:
		if not _clear_of_harm(sight, at, other):
			continue
		var score: float = other.dot(way)
		if _steer_side != 0.0 and signf(way.cross(other)) == _steer_side:
			score += HARM_SIDE_KEEP
		if score > best_score and AISight.line_clear(actor.projectiles, at, at + other * HARM_PROBE):
			best_score = score
			best = other
	if best == Vector2.ZERO:
		return
	var side: float = way.cross(best)
	if absf(side) > 0.001:
		_steer_side = signf(side)
	intent.move = best * move.length()


## True when no cell along `way` from `at` (every cell to HARM_PROBE ahead, `CoverSight.harms_along`),
## but the one `at` is in, harms.
func _clear_of_harm(sight: CoverSight, at: Vector2, way: Vector2) -> bool:
	return not sight.harms_along(at, at + way * HARM_PROBE)
## The attack is over (its rest, or none): back to CHASE, and if it rolled a turn (`AIProfile.turns`)
## it turns to the foe it aimed at longest ago. Only here: a stand, a call or a detour ending turns
## nobody.
func _attack_over() -> void:
	_to_chase()
	if _turn_due:
		_turn_due = false
		_turn_to = _longest_ago_foe()
		_retarget_left = 0.0


## Turns (boss plan OB14): the attack starting is aimed at the target (remembered with the time),
## the foe it turned to is let go, and whether it turns after this one is rolled.
func _note_aimed() -> void:
	_turn_to = null
	if profile.turns <= 0.0:
		return
	var key: int = _target_id if _aim_node() == target else 0
	if key != 0 and key != NO_KEY:
		# Its own row, else a free one, else the oldest.
		var row: int = _aimed_keys.find(key)
		if row < 0:
			row = _aimed_keys.find(0)
		if row < 0:
			row = 0
			for i in TURN_MEMORY:
				if _aimed_at[i] < _aimed_at[row]:
					row = i
		_aimed_keys[row] = key
		_aimed_at[row] = clock
	_turn_due = _roll() < profile.turns


## Of the foes it can target now (every open actor of another team it may aim at, `Actors.is_foe`),
## the one it aimed at longest ago (one never aimed at before any), the nearest of those; null for
## none.
func _longest_ago_foe() -> Node2D:
	var table: ActorsScript = actor.actors
	if table == null:
		return null
	var team: int = actor.team()
	var count: int = table.open_ids(_open_ids)
	var best: Node2D = null
	var best_at: float = INF
	var best_far: float = INF
	for n in count:
		var id: int = _open_ids[n]
		if id == actor.id or not ActorsScript.is_foe(team, table.team_of(id)):
			continue
		var node: Node2D = table.node_of(id) as Node2D
		if node == null or not can_target(node):
			continue
		var key: int = table.key_of(id)
		var at: float = -INF
		for i in TURN_MEMORY:
			if _aimed_keys[i] == key and key != 0:
				at = _aimed_at[i]
				break
		var far: float = actor.global_position.distance_squared_to(node.global_position)
		if at < best_at or (at == best_at and far < best_far):
			best = node
			best_at = at
			best_far = far
	return best


## The way to `plan_point`, ZERO once there.
func _to_point() -> Vector2:
	var way: Vector2 = plan_point - actor.global_position
	return way.normalized() if way.length_squared() > CLOSE_ENOUGH * CLOSE_ENOUGH else Vector2.ZERO


## Where an enemy stands in a fight: a profile that presses on walks toward its target instead, at
## `press_on` of its speed, until their hurt circles touch.
func _press_on(intent: ActorIntent) -> void:
	intent.move = Vector2.ZERO
	if profile.press_on <= 0.0 or target == null:
		return
	var now: Vector2 = target.global_position - actor.global_position
	var touch: float = _target_radius() + (actor.hurtbox.outer_radius() if actor.hurtbox != null else 0.0)
	if now.length_squared() > touch * touch:
		intent.move = now.normalized() * profile.press_on


## Where to aim a cast of `sense` at what the plan aims at (`_aim_node`), `now` away: ahead of a
## moving one by its flight (`lead`), then off by `error` radians (the profile's aim error, drawn
## once an attack).
func _aim_for(sense: CastSense, now: Vector2, error: float) -> Vector2:
	var point: Vector2 = now
	var aimed: Node2D = _aim_node()
	var aimed_actor: Actor = aimed as Actor
	if aimed_actor != null:
		point += aimed_actor.body_offset - actor.body_offset
	if sense != null and sense.speed > 0.0 and profile.lead > 0.0:
		if aimed_actor != null:
			point += aimed_actor.velocity * (point.length() / sense.speed) * profile.lead
	if point == Vector2.ZERO:
		point = actor.aim
	return DMath.rotated(point.normalized(), error)


## A staff whose next cast moves the caster and can leave now, or -1.
func _ready_mover() -> int:
	var caster: Caster = actor.caster
	if caster == null:
		return -1
	for at in caster.staff_count:
		var sense: CastSense = caster.next_cast_sense(at)
		if sense != null and sense.moves_caster and not caster.is_holding(at) and caster.cast_ready(0.0, at):
			return at
	return -1


## True unless staff `at`'s next cast moves the body (a dash, a teleport; `CastSense.moves_caster`)
## along `way` to end over a hole (hub rework HR-H2, "Holes" 5: the AI never ends a move of its own
## over one): its end is its reach along the way (a dash walks the way it is cast, staffs A6a), or,
## homing, the target's feet when they are nearer, short of the first wall either way.
func _lands_on_ground(at: int, way: Vector2) -> bool:
	var projectiles: ProjectileManagerScript = actor.projectiles
	if projectiles == null or not projectiles.grid().has_holes() or way == Vector2.ZERO:
		return true
	var sense: CastSense = _sense_of(at)
	if sense == null or not sense.moves_caster:
		return true
	var from: Vector2 = actor.global_position
	var reach: float = sense.move_reach
	if sense.homing and target != null:
		reach = minf(reach, from.distance_to(target.global_position))
	var grid: RoomGrid = projectiles.grid()
	var end: Vector2 = grid.clip_to_walls(from, from + way.normalized() * reach)
	return not grid.is_hole(end)


## `senses[at]` from the last decision, else asked now.
func _sense_of(at: int) -> CastSense:
	if at < 0:
		return null
	if at < senses.size() and senses[at] != null:
		return senses[at]
	return actor.caster.next_cast_sense(at) if actor != null and actor.caster != null else null


func _reaction() -> float:
	return profile.reaction * (1.0 + REACTION_JITTER * (_roll() * 2.0 - 1.0))


## Its next roll in [0, 1), from its actor's sim (core/sim/sim.gd).
func _roll() -> float:
	var game: Sim = actor.sim if actor != null and actor.sim != null else Sim.found(actor)
	var roll: float = game.chance(&"brain", dice, rolls)
	rolls += 1
	return roll


func _target_radius() -> float:
	return _target_actor.hurtbox.outer_radius() if _target_actor != null and _target_actor.hurtbox != null else 0.0


func _radius_of(node: Node2D) -> float:
	if node == target:
		return _target_radius()
	var other: Actor = node as Actor
	return other.hurtbox.outer_radius() if other != null and other.hurtbox != null else 0.0


## What the plan aims at: `plan_target` while it can be aimed at (let go once it cannot), else
## the target.
func _aim_node() -> Node2D:
	if plan_target != null:
		if _is_valid_target(plan_target):
			return plan_target
		plan_target = null
	return target


## No blocking body's ground between its feet and the target's, nor with `holes` a hole (HR-H2:
## `AISight.feet_clear`, a walk; without, `AISight.ground_clear`, the line of fire), up to the edge
## of the target's own ground when it stands on some (a body that cannot move lays it under its own
## feet: `_walk_goal`).
func _ground_clear_now(holes: bool = true) -> bool:
	if target == null:
		return true
	var goal: Vector2 = _walk_goal()
	if goal.distance_squared_to(actor.global_position) <= 1.0:
		return true
	if holes:
		return AISight.feet_clear(actor.projectiles, actor.global_position, goal)
	return AISight.ground_clear(actor.projectiles, actor.global_position, goal)


## Where a walk at the target heads: its feet, or for a target standing on its own ground (a body
## with no Mover, a training dummy) the point on the way to them just outside that ground, so its
## own footprint never stands between the two.
func _walk_goal() -> Vector2:
	var feet: Vector2 = target.global_position
	if _target_actor == null or actor.projectiles == null or _target_actor.id < 0:
		return feet
	var box: Rect2 = actor.projectiles.grid().footprint_of(_target_actor.id)
	if not box.has_area() or not box.has_point(feet):
		return feet
	var back: Vector2 = actor.global_position - feet
	if back == Vector2.ZERO:
		return feet
	var out: float = box.size.length() * 0.5 + GROUND_MARGIN
	return feet + back.normalized() * minf(out, back.length())


## True when a shot from the actor's body would reach its target's: no wall and no prop's body (a
## pillar's) in the way, minding its shots' width (`AISight.fire_clear`).
func _line_clear() -> bool:
	if target == null:
		return true
	return AISight.fire_clear(actor.projectiles, actor.global_position + actor.body_offset, _target_body(), _fire_width(), _fire_short(target))


## How wide its line of fire is either side: the widest hit width of its aimed staffs that hurt
## (`CastSense.radius`, as last read), at most FIRE_WIDTH_MOST (a spray's cone is wide, and a few of
## its drops on a pillar are no waste). A shot that grazes a pillar is spent on it.
func _fire_width() -> float:
	var width: float = 0.0
	for at in staff_count:
		var sense: CastSense = senses[at]
		if sense != null and not sense.empty and sense.harms() and sense.reach > 0.0:
			width = maxf(width, sense.radius)
	return minf(width, FIRE_WIDTH_MOST)


## How far short of `body`'s centre a shot `width` either side (`_fire_width` when negative) meets
## it: its hit shape's reach (`HitShape.outer_radius`) plus the width. A prop past that point
## is no cover (`AISight.fire_clear`).
func _fire_short(body: Node2D, width: float = -1.0) -> float:
	if width < 0.0:
		width = _fire_width()
	if actor.projectiles == null or body == null:
		return width
	return HitShape.outer_radius(actor.projectiles.target_half(body), actor.projectiles.target_round(body)) + width


## Where the target's body is (its feet and its body offset): what a shot at it aims for.
func _target_body() -> Vector2:
	var to: Vector2 = target.global_position
	if _target_actor != null:
		to += _target_actor.body_offset
	return to


## The grudge, else the nearest standing actor of another team.
func _find_target() -> Node2D:
	lookup_count += 1
	if grudge != null and _grudge_left > 0.0:
		return grudge
	if _turn_to != null:
		if can_target(_turn_to):
			return _turn_to
		_turn_to = null
	return nearest_foe(actor)


## The nearest standing actor of another team than `from_actor`'s (a decoy among them), or null:
## looked for in the rings of LOOKS, nearest first. A decoy aims by it too (`DecoyController`).
static func nearest_foe(from_actor: Actor) -> Node2D:
	if from_actor.projectiles == null:
		return null
	var from: Vector2 = from_actor.global_position + from_actor.body_offset
	for ring: float in LOOKS:
		var found: Node2D = from_actor.projectiles.nearest_target(from, ring, ProjectileManagerScript.ACTOR_LAYERS, from_actor, null, from_actor.team())
		# Found with its centre inside the ring, nothing outside it is nearer; a big body only
		# touching the ring is checked again in the next.
		if found != null and (ring >= SIGHT or from_actor.projectiles.nearest_point.distance_squared_to(from) <= ring * ring):
			return found if can_target(found) else null
	return null


## A freed node may still sit in `target` or `grudge`, hence the Variant. A downed wizard, a down
## actor, one that is dying and one out of the world (a decoy that ended) are no targets.
static func can_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Actor:
		var other: Actor = node as Actor
		return other.is_inside_tree() and not other.is_down() and not other.is_dying()
	return not (node.has_method("is_downed") and node.is_downed())


func _is_valid_target(node: Variant) -> bool:
	return can_target(node)


func _drop_grudge() -> void:
	grudge = null
	_grudge_left = 0.0
	_retarget_left = 0.0


## Chill slows the attack timers, freeze stops them (the Mover slows the walk by the same pace).
func _pace() -> float:
	return actor.combat.own_pace(actor, actor.id) if actor.combat != null else 1.0

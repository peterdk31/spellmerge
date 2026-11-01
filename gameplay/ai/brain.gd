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
## the nearest actor of another team that can be hit now (`Projectiles.nearest_target`), a
## player's decoy in lure range first, a teammate that hurt it for GRUDGE_TIME (infighting).
##
## **The steps of the executor** (`state`): CHASE (walk as planned, aim at the target, wind up the
## planned staff once it is ready), WINDUP (stand, the aim locked, with lead and the profile's aim
## error added once; the telegraph shows it; it lasts longer for a more dangerous cast), the cast
## (`intent.press`), CHANNEL (a cast that goes on while held: hold the button while the target
## stays in its lane, the mana lasts and `channel_max` is not up, turning after the target at
## `track_speed`), RECOVER (stand, the aim locked; a shot about to hit may still make it dodge),
## REPOSITION (walk round a wall for REPOSITION_TIME or until the line is clear) and TRANSITION (a
## boss changing phase: stand). A profile that presses on (`AIProfile.press_on`, a test bot's)
## walks toward its target wherever an enemy stands in a fight, and with no rest goes on at once. The windup starts only when the cast can leave within it
## (`Caster.cast_ready`), so a telegraph is always followed by its cast. An urgent plan (a dodge,
## an escape) presses a staff whose next cast moves the caster once, with no windup, and the move
## goes the way it walks. Timers slow by `Combat.pace` (freeze stops an attack).
##
## **Enemies telegraph, allies don't** (owner, 2026-11-01): a telegraph is a warning for the
## players, so a brain driving an actor of the players' team winds up nothing (`warns()` false:
## `windup_for` is 0 and the cast leaves the step its staff is ready, so no telegraph and no
## furious face). It follows the driven actor's team, which is its driver's: a bot, a minion, and
## an enemy body a player's side drives cast at once; an enemy's AI possessing a wizard still warns.
##
## Nothing here allocates per step.

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

enum State { CHASE, WINDUP, RECOVER, REPOSITION, CHANNEL, TRANSITION }
## How a plan walks: stand, toward or away from the target, or a set way (`plan_way`).
enum Move { STAND, TOWARD, AWAY, WAY }

## Seconds between looking for the nearest target again.
const RETARGET_TIME: float = 0.5
## Seconds it chases a teammate that hurt it before going back to its team's targets.
const GRUDGE_TIME: float = 3.0
## How far it looks for a target: farther than any room, so the nearest anywhere.
const SIGHT: float = 100000.0
## Closer than this to its target it stops walking (an actor with nothing to cast, on top of it).
const CLOSE_ENOUGH: float = 1.0
## How far ahead (pixels) a way round a wall, or to cover, is probed.
const DETOUR_PROBE: float = 40.0
const COVER_PROBE: float = 48.0
## Seconds it walks one way round a wall before it looks again.
const REPOSITION_TIME: float = 0.4
## A windup: BASE, plus PER_DAMAGE a point of the cast's damage and AREA for a cast that hits round
## a point or explodes, kept between MIN and MAX, times the profile's `windup_scale`. A cast that
## hurts nobody (a move, a wall, a decoy) winds up HARMLESS.
const WINDUP_BASE: float = 0.6
const WINDUP_PER_DAMAGE: float = 0.02
const WINDUP_AREA: float = 0.15
const WINDUP_MIN: float = 0.3
const WINDUP_MAX: float = 2.0
const WINDUP_HARMLESS: float = 0.2
## The rest after a cast: REST_BASE plus half its delay (at most a second), times `rest_scale`.
const REST_BASE: float = 0.6
## Windups and rests are whole sixteenths of a second, so a telegraph's length reads the same on
## every frame rate and a test's fixed step meets it exactly.
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

## The actor it drives, the profile it plays by and the decoys it is lured by (null: none).
var actor: Actor = null
var profile: AIProfile = null
var entities: EntitiesScript = null
## The team board of its team (gameplay/ai/team_board.gd), or null: staggered fire and calls.
var board: TeamBoard = null
## Seeded per actor (`setup`), so a test repeats.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# What it perceived at its last decision.
## What it chases (an actor, a decoy), or null.
var target: Node2D = null
## The teammate that hurt it last, chased while `grudge_left()` > 0, or null.
var grudge: Node2D = null
## From its body to the target's, and how far.
var to_target: Vector2 = Vector2.ZERO
var distance: float = 0.0
## No wall between its body and the target's.
var line_clear: bool = true
## Seconds until the soonest shot coming at it arrives (-1 for none), and the way off its line.
var threat_time: float = -1.0
var threat_away: Vector2 = Vector2.ZERO
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
## Seconds this brain has thought (for behaviours' memos).
var clock: float = 0.0

# What it decided.
var behaviour: AIBehaviour = null
var plan_staff: int = -1
var plan_move: Move = Move.STAND
var plan_way: Vector2 = Vector2.ZERO
var plan_urgent: bool = false
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
## Instance id of `target` when it was chosen, or 0 for none; `target` typed when an actor.
var _target_id: int = 0
var _target_actor: Actor = null


## Start driving `with_actor` by `with_profile` (null: the shared default). `seed_value` seeds its
## randomness and staggers its timers.
func setup(with_actor: Actor, with_profile: AIProfile, seed_value: int) -> void:
	actor = with_actor
	profile = with_profile if with_profile != null else AIProfile.fallback()
	rng.seed = seed_value
	_retarget_offset = RETARGET_TIME * float(absi(seed_value) % 8) / 8.0
	_strafe_side = 1.0 if seed_value % 2 == 0 else -1.0
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
	_state_left = 0.0
	_looked = false
	_retarget_left = _retarget_offset
	_decide_now = true
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
			if _decide_left <= 0.0 or _decide_now:
				_perceive()
				_decide()
			_chase(intent)
		State.WINDUP:
			intent.aim = _locked_aim
			_press_on(intent)
			_state_left -= delta * _pace()
			if _state_left <= 0.0:
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
				_to_chase()
		State.REPOSITION:
			_state_left -= delta
			if target == null or _state_left <= 0.0 or _line_clear():
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


## True from the start of a windup until its cast leaves: the attack is coming.
func is_telegraphing() -> bool:
	return state == State.WINDUP


## 0.0 at the start of the telegraph, 1.0 when the cast leaves; 0.0 when not telegraphing.
func telegraph_progress() -> float:
	if state != State.WINDUP or windup_time <= 0.0:
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


## The windup the next attack of staff `at` would take (seconds), for its telegraph; 0 for an ally
## (`warns`).
func windup_for(at: int) -> float:
	if not warns():
		return 0.0
	var sense: CastSense = _sense_of(at)
	if sense == null:
		return snappedf(WINDUP_BASE * profile.windup_scale, TIME_GRAIN)
	if not sense.harms():
		return maxf(snappedf(WINDUP_HARMLESS * profile.windup_scale, TIME_GRAIN), TIME_GRAIN)
	var danger: float = sense.damage * WINDUP_PER_DAMAGE
	if sense.area or sense.blast > 0.0:
		danger += WINDUP_AREA
	return maxf(snappedf(clampf(WINDUP_BASE + danger, WINDUP_MIN, WINDUP_MAX) * profile.windup_scale, TIME_GRAIN), TIME_GRAIN)


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


## Chase `attacker` for `seconds`, as if hurt by it just now (the horde swarm's promotion keeps a
## swarmer's grudge).
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


## Behaviours ask: does the next cast `sense` reach the target from here?
func reaches(sense: CastSense) -> bool:
	if sense.reach > 0.0:
		return distance <= sense.reach * 0.95 + _target_radius()
	return distance <= maxf(sense.close_reach, 24.0) + _target_radius()


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
	return board.beat(actor.team(), actor.id, profile.teamwork)


## Behaviours ask: walk round the wall in the line for a while (REPOSITION).
func reposition() -> void:
	plan_move = Move.WAY
	plan_way = AISight.detour(actor.projectiles, actor.global_position, target.global_position, DETOUR_PROBE)
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
		_target_id = target.get_instance_id() if target != null else 0
		_target_actor = target as Actor
		if _target_id != before:
			_decide_now = true


func _perceive() -> void:
	_decide_left = _reaction()
	_decide_now = false
	if target != null:
		to_target = target.global_position - actor.global_position
		distance = to_target.length()
		line_clear = _line_clear()
	else:
		to_target = Vector2.ZERO
		distance = 0.0
		line_clear = true
	health_fraction = actor.health.health / actor.health.max_health if actor.health != null and actor.health.max_health > 0.0 else 1.0
	_read_staffs()
	_perceive_threat()


func _perceive_threat() -> void:
	threat_time = -1.0
	threat_away = Vector2.ZERO
	if actor.projectiles == null or (profile.dodge <= 0.0 and not _can_block()):
		return
	var radius: float = (actor.hurtbox.radius if actor.hurtbox != null else 8.0) + DODGE_MARGIN
	threat_time = actor.projectiles.threat(actor.global_position + actor.body_offset, radius, actor.team(), actor.id, DODGE_HORIZON)
	threat_away = actor.projectiles.threat_away
	if threat_time < 0.0:
		_read_telegraph()
	if threat_time >= 0.0 and profile.dodge > 0.0 and profile.randomness > 0.0 and rng.randf() < profile.randomness * 0.3:
		# Sometimes it sees the shot late.
		threat_time = -1.0


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
	if second != null and second_want >= best_want * 0.7 and rng.randf() < profile.randomness * 0.5:
		best = second
	behaviour = best
	_clear_plan()
	if best != null:
		best.act(self)


func _clear_plan() -> void:
	plan_staff = -1
	plan_move = Move.STAND
	plan_way = Vector2.ZERO
	plan_urgent = false


# --- carrying it out ---


func _chase(intent: ActorIntent) -> void:
	if target == null:
		return
	var now: Vector2 = target.global_position - actor.global_position
	if now != Vector2.ZERO:
		intent.aim = now
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
			if mover >= 0:
				intent.press(mover)
				_tapped = true
	else:
		_tapped = false
	if plan_staff < 0 or actor.caster == null:
		return
	var windup: float = windup_for(plan_staff)
	if not actor.caster.cast_ready(windup, plan_staff):
		# Not ready yet: wait as planned, so the telegraph only ever shows a cast that comes.
		return
	_begin_windup(plan_staff, windup, now, intent)
	if windup <= 0.0:
		# No warning to give (an ally): the cast leaves this step.
		_release(intent)


func _begin_windup(at: int, windup: float, now: Vector2, intent: ActorIntent) -> void:
	chosen = at
	_chosen_sense = _sense_of(at)
	windup_time = windup
	recover_time = rest_for(at)
	state = State.WINDUP
	_state_left = windup
	_locked_aim = _aim_for(_chosen_sense, now)
	intent.aim = _locked_aim
	_press_on(intent)
	if board != null:
		board.started(actor.team(), actor.id)


## The windup is over: the cast leaves, then it channels or rests.
func _release(intent: ActorIntent) -> void:
	intent.press(chosen)
	var sense: CastSense = _chosen_sense
	if sense != null and sense.repeats_held and not sense.sustained and profile.channel_max > 0.0:
		state = State.CHANNEL
		_channel_left = profile.channel_max
		intent.hold(chosen, true)
		return
	if recover_time <= 0.0:
		# No rest (rest_scale 0): it goes on at once.
		_to_chase()
		return
	state = State.RECOVER
	_state_left = recover_time


func _channel(delta: float, intent: ActorIntent) -> void:
	_channel_left -= delta * _pace()
	var sense: CastSense = _chosen_sense
	var keep: bool = _channel_left > 0.0 and target != null and sense != null and actor.caster != null
	if keep:
		var now: Vector2 = target.global_position - actor.global_position
		if profile.track_speed > 0.0 and now != Vector2.ZERO:
			var turn: float = deg_to_rad(profile.track_speed) * delta * _pace()
			var off: float = _locked_aim.angle_to(now)
			_locked_aim = _locked_aim.rotated(clampf(off, -turn, turn))
		keep = _in_lane(sense, now) and actor.caster.free_mana(chosen) >= sense.mana
	intent.aim = _locked_aim
	_press_on(intent)
	if keep:
		intent.hold(chosen, true)
		return
	intent.hold(chosen, false)
	state = State.RECOVER
	_state_left = recover_time


## True while the target stands where a held cast along the aim still meets it.
func _in_lane(sense: CastSense, now: Vector2) -> bool:
	var reach: float = sense.reach if sense.reach > 0.0 else sense.close_reach
	var along: float = now.dot(_locked_aim)
	if along < -LANE_MARGIN or along > reach + LANE_MARGIN + _target_radius():
		return false
	if sense.reach <= 0.0:
		return true
	var across: float = absf(now.cross(_locked_aim))
	return across <= sense.radius + _target_radius() + LANE_MARGIN


func _to_chase() -> void:
	state = State.CHASE
	_decide_now = true


## Where an enemy stands in a fight: a profile that presses on walks toward its target instead, at
## `press_on` of its speed, until their hurt circles touch.
func _press_on(intent: ActorIntent) -> void:
	intent.move = Vector2.ZERO
	if profile.press_on <= 0.0 or target == null:
		return
	var now: Vector2 = target.global_position - actor.global_position
	var touch: float = _target_radius() + (actor.hurtbox.radius if actor.hurtbox != null else 0.0)
	if now.length_squared() > touch * touch:
		intent.move = now.normalized() * profile.press_on


## Where to aim a cast of `sense` at the target `now` away: ahead of a moving one by its flight
## (`lead`), then off by the profile's aim error, once.
func _aim_for(sense: CastSense, now: Vector2) -> Vector2:
	var point: Vector2 = now
	if _target_actor != null:
		point += _target_actor.body_offset - actor.body_offset
	if sense != null and sense.speed > 0.0 and profile.lead > 0.0:
		var body := target as CharacterBody2D
		if body != null:
			point += body.velocity * (point.length() / sense.speed) * profile.lead
	if point == Vector2.ZERO:
		point = actor.aim
	var error: float = rng.randf_range(-1.0, 1.0) * (1.0 - profile.accuracy) * AIM_ERROR
	return point.normalized().rotated(error)


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


## `senses[at]` from the last decision, else asked now.
func _sense_of(at: int) -> CastSense:
	if at < 0:
		return null
	if at < senses.size() and senses[at] != null:
		return senses[at]
	return actor.caster.next_cast_sense(at) if actor != null and actor.caster != null else null


func _reaction() -> float:
	return profile.reaction * rng.randf_range(1.0 - REACTION_JITTER, 1.0 + REACTION_JITTER)


func _target_radius() -> float:
	return _target_actor.hurtbox.radius if _target_actor != null and _target_actor.hurtbox != null else 0.0


## True when no wall stands between the actor's body and its target's (`AISight`).
func _line_clear() -> bool:
	if target == null:
		return true
	var to: Vector2 = target.global_position
	if _target_actor != null:
		to += _target_actor.body_offset
	return AISight.line_clear(actor.projectiles, actor.global_position + actor.body_offset, to)


## The grudge, else a decoy in lure range, else the nearest standing actor of another team.
func _find_target() -> Node2D:
	lookup_count += 1
	if grudge != null and _grudge_left > 0.0:
		return grudge
	var here: Vector2 = actor.global_position
	var decoy: Node2D = entities.lure(here) if entities != null and is_instance_valid(entities) else null
	if decoy != null:
		return decoy
	if actor.projectiles == null:
		return null
	var found: Node2D = actor.projectiles.nearest_target(here + actor.body_offset, SIGHT, ProjectileManagerScript.ACTOR_LAYERS, actor, null, actor.team())
	return found if _is_valid_target(found) else null


## A freed node may still sit in `target` or `grudge`, hence the Variant. A downed wizard, a down
## actor and one that is dying are no targets.
func _is_valid_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Actor:
		var other: Actor = node as Actor
		return not other.is_down() and not other.is_dying()
	return not (node.has_method("is_downed") and node.is_downed())


func _drop_grudge() -> void:
	grudge = null
	_grudge_left = 0.0
	_retarget_left = 0.0


## Chill slows the attack timers, freeze stops them (the Mover slows the walk by the same pace).
func _pace() -> float:
	return actor.combat.own_pace(actor, actor.id) if actor.combat != null else 1.0

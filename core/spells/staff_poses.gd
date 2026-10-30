class_name StaffPoses
extends RefCounted
## The staff animation of each actor's body (`FormBase.staff_pose`), kept by the spell runtime
## (`Spells`, which owns it): `start` plays a carrier's keys from its cast, `end_strike` cuts its
## strike short when the carrier's last shot ends, and `staff_pose` and the other getters (read
## through `Spells.poses`) give the body's look where the staff is now.

## actor -> its body's last staff animation (`staff_pose`): when it began (INF for none), the
## carrier's wind-up and strike in seconds (its strike ends early when its last shot does: the tag
## it plays for), the aim locked at the cast, which way it turns (a swing's side), its keys
## (`FormBase.packed_pose`), the carrier's tint (its glow's colour), and where the staff was when it
## began (POSE_CHANNELS numbers a body, in its own frame: what the first key starts from).
var _pose_start: PackedFloat32Array = PackedFloat32Array()
var _pose_wind: PackedFloat32Array = PackedFloat32Array()
var _pose_strike: PackedFloat32Array = PackedFloat32Array()
var _pose_tag: PackedInt64Array = PackedInt64Array()
var _pose_dir: PackedVector2Array = PackedVector2Array()
## 1 when the animation keeps the aim of the cast (a swing, a slam: their aim is locked), 0 when
## it turns with the live aim (a held beam follows it).
var _pose_lock: PackedByteArray = PackedByteArray()
var _pose_side: PackedInt32Array = PackedInt32Array()
var _pose_keys: Array[PackedFloat32Array] = []
var _pose_tint: PackedColorArray = PackedColorArray()
var _pose_from: PackedFloat32Array = PackedFloat32Array()
## The pose worked out last (`_pose_now`), for whom and when: the channels and the mood.
var _pose_out: PackedFloat32Array = PackedFloat32Array()
var _pose_out_mood: int = 0
var _pose_out_actor: int = -1
var _pose_out_clock: float = -1.0
## Numbers a pose has: FormBase.POSE_CHANNELS (turn, lift, push, glow, stretch, shake).
const POSE_CHANNELS: int = 6

## The runtime this belongs to (`CarrierKit`): its clock and its actors' aims.
var kit: CarrierKit = null


func _init(runtime_kit: CarrierKit) -> void:
	kit = runtime_kit
	_pose_start.resize(SpellRuntime.ACTORS)
	_pose_wind.resize(SpellRuntime.ACTORS)
	_pose_strike.resize(SpellRuntime.ACTORS)
	_pose_dir.resize(SpellRuntime.ACTORS)
	_pose_side.resize(SpellRuntime.ACTORS)
	_pose_keys.resize(SpellRuntime.ACTORS)
	_pose_tag.resize(SpellRuntime.ACTORS)
	_pose_lock.resize(SpellRuntime.ACTORS)
	_pose_tint.resize(SpellRuntime.ACTORS)
	_pose_from.resize(SpellRuntime.ACTORS * POSE_CHANNELS)
	_pose_out.resize(POSE_CHANNELS)
	clear()


## No actor's staff moves (`Spells.clear`).
func clear() -> void:
	_pose_start.fill(INF)


## `actor`'s staff does not move (a caster opened or closed under its id).
func reset_actor(actor: int) -> void:
	_pose_start[actor] = INF


## When `actor`'s last staff animation began (INF for none): one cast's carriers start one.
func started_at(actor: int) -> float:
	return _pose_start[actor]


## How long `spell`'s strike lasts for its staff animation (`FormBase.staff_pose`): the working time
## of a carrier the staff keeps working (a beam's, rain's or dash's `lifetime`, a held one's until its
## last shot ends); none for one that leaves the staff (a bolt, a rune, an orbit).
static func strike_of(spell: CompiledSpell, lifetime: float) -> float:
	return maxf(lifetime, 0.0) if spell.has_trait(Carrier.HOLDS_STAFF) else 0.0


## Starts `actor`'s staff animation for `spell` (its `staff_pose`, cast with `tag`) now: `wind` and
## `strike` seconds of wind-up and strike, the aim `dir` locked now, turning `side` (1, or -1 for a
## backhand). It starts from where the last one has the staff now, so a new cast never jumps.
func start(actor: int, spell: CompiledSpell, tag: int, wind: float, strike: float, dir: Vector2, side: int, lock: bool = false) -> void:
	var at: int = actor * POSE_CHANNELS
	var was: Vector2 = staff_pose_dir(actor)
	if was.is_zero_approx():
		for c in POSE_CHANNELS:
			_pose_from[at + c] = 0.0
	else:
		_pose_now(actor)
		var heading: float = was.angle() + deg_to_rad(_pose_out[0]) * _pose_side[actor]
		for c in POSE_CHANNELS:
			_pose_from[at + c] = _pose_out[c]
		_pose_from[at] = rad_to_deg(angle_difference(dir.angle(), heading)) * side
	_pose_out_actor = -1
	if spell.staff_pose.is_empty():
		_pose_start[actor] = INF
		return
	_pose_start[actor] = kit.clock()
	_pose_wind[actor] = wind
	_pose_strike[actor] = strike
	_pose_tag[actor] = tag
	_pose_dir[actor] = dir
	_pose_lock[actor] = 1 if lock else 0
	_pose_side[actor] = side
	_pose_keys[actor] = spell.staff_pose
	_pose_tint[actor] = spell.tint


## The carrier with `tag` has no shot left: the strike of the animation it plays ends now.
func end_strike(tag: int) -> void:
	var actor: int = SpellTag.caster_of(tag)
	if actor < 0 or actor >= SpellRuntime.ACTORS or not is_finite(_pose_start[actor]) or _pose_tag[actor] != tag:
		return
	var into: float = maxf(kit.clock() - _pose_start[actor] - _pose_wind[actor], 0.0)
	if into < _pose_strike[actor]:
		_pose_strike[actor] = into
		_pose_out_actor = -1


## Where `actor`'s staff is in its animation now (its carrier's `staff_pose`), for its look: x the
## turn off the aim locked at the cast (radians, a backhand's the other way), y the lift and z the
## push along that aim (pixels). Zero when it plays none: then `staff_pose_dir` is zero too and the
## look follows the aim. A new animation starts from where the last one had the staff.
func staff_pose(actor: int) -> Vector3:
	if not _pose_now(actor):
		return Vector3.ZERO
	return Vector3(deg_to_rad(_pose_out[0]) * _pose_side[actor], _pose_out[1], _pose_out[2])


## How strongly `actor`'s staff glows now (0 to 1), and in what colour: its carrier's infusion's,
## or white for a plain one (the look takes the player's colour then).
func staff_glow(actor: int) -> float:
	return _pose_out[3] if _pose_now(actor) else 0.0


func staff_glow_tint(actor: int) -> Color:
	return _pose_tint[actor] if actor >= 0 and actor < SpellRuntime.ACTORS else Color.WHITE


## How much `actor`'s staff is stretched along its aim now (0 none, negative squashed), and the
## pixels it shakes by.
func staff_stretch(actor: int) -> float:
	return _pose_out[4] if _pose_now(actor) else 0.0


func staff_shake(actor: int) -> float:
	return _pose_out[5] if _pose_now(actor) else 0.0


## The mood `actor`'s staff animation shows on its face now (`FormBase.POSE_MOODS`), or empty.
func staff_mood(actor: int) -> StringName:
	if not _pose_now(actor) or _pose_out_mood <= 0:
		return &""
	return FormBase.POSE_MOODS[_pose_out_mood - 1]


## The aim `actor`'s staff animation turns from, or zero when it plays none: the aim of the cast
## for a carrier that locks it (a swing, a slam), else the live aim (a held beam turns with it).
func staff_pose_dir(actor: int) -> Vector2:
	if not _pose_now(actor):
		return Vector2.ZERO
	if _pose_lock[actor] == 0 and kit.aim_dir(actor).is_finite() and not kit.aim_dir(actor).is_zero_approx():
		return kit.aim_dir(actor)
	return _pose_dir[actor]


## Works out `actor`'s animation now into `_pose_out` and `_pose_out_mood` (once per actor and
## clock); false when it plays none (none started, or past its last key). The keys run from where
## the staff was at the cast; "hold" keys repeat, each round from the last of them, while the
## strike lasts. Allocation-free.
func _pose_now(actor: int) -> bool:
	if actor < 0 or actor >= SpellRuntime.ACTORS or not is_finite(_pose_start[actor]):
		return false
	if _pose_out_actor == actor and _pose_out_clock == kit.clock():
		return _pose_out_mood >= 0
	_pose_out_actor = actor
	_pose_out_clock = kit.clock()
	var keys: PackedFloat32Array = _pose_keys[actor]
	var s: float = kit.clock() - _pose_start[actor]
	var wind: float = _pose_wind[actor]
	var strike: float = _pose_strike[actor]
	var stride: int = FormBase.POSE_STRIDE
	var count: int = keys.size() / stride
	# Where the last key passed left the staff (the start: where it was at the cast), and when.
	var base: int = actor * POSE_CHANNELS
	var from_key: int = -1
	var from_t: float = 0.0
	var mood: int = 0
	var k: int = 0
	while k < count:
		var phase: int = roundi(keys[k * stride + FormBase.PK_PHASE])
		if phase == FormBase.POSE_PHASES["hold"]:
			# The run of hold keys, played round and round through the strike.
			var first: int = k
			while k < count and roundi(keys[k * stride + FormBase.PK_PHASE]) == phase:
				k += 1
			var last: int = k - 1
			var period: float = keys[last * stride + FormBase.PK_AT]
			if s < wind and strike > 0.0:
				# Still winding up past its last wind key: it stays there until the strike.
				return _pose_between(keys, actor, from_key, first, 0.0, mood)
			if s >= wind and s < wind + strike and period > 0.0:
				var into: float = s - wind
				var round_n: int = floori(into / period)
				var u: float = into - round_n * period
				var h_from: int = from_key if round_n == 0 else last
				var h_t: float = 0.0
				for h in range(first, last + 1):
					var t: float = keys[h * stride + FormBase.PK_AT]
					if u < t:
						return _pose_between(keys, actor, h_from, h, clampf((u - h_t) / (t - h_t), 0.0, 1.0) if t > h_t else 1.0, mood)
					h_from = h
					h_t = t
					mood = _mood_of(keys, h, mood)
				return _pose_between(keys, actor, h_from, h_from, 1.0, mood)
			if s >= wind + strike or strike <= 0.0:
				from_key = last if strike > 0.0 else from_key
				from_t = wind + strike
			continue
		var at: float = keys[k * stride + FormBase.PK_AT]
		var t: float = at * wind if phase == 0 else (wind + at * strike if phase == 1 else wind + strike + at)
		if s < t:
			return _pose_between(keys, actor, from_key, k, clampf((s - from_t) / (t - from_t), 0.0, 1.0) if t > from_t else 1.0, mood)
		from_key = k
		from_t = t
		mood = _mood_of(keys, k, mood)
		k += 1
	_pose_out_mood = -1
	return false


## The mood shown once key `k` is passed: its own, else the one before.
static func _mood_of(keys: PackedFloat32Array, k: int, mood: int) -> int:
	var own: int = roundi(keys[k * FormBase.POSE_STRIDE + FormBase.PK_MOOD])
	return own if own > 0 else mood


## Puts into `_pose_out` the pose `x` of the way from key `from` (-1: where the staff was at the
## cast) to key `to`, eased by `to`'s ease, with `mood`; true.
func _pose_between(keys: PackedFloat32Array, actor: int, from: int, to: int, x: float, mood: int) -> bool:
	var stride: int = FormBase.POSE_STRIDE
	var eased: float = pose_ease(x, roundi(keys[to * stride + FormBase.PK_EASE]))
	for c in POSE_CHANNELS:
		var a: float = _pose_from[actor * POSE_CHANNELS + c] if from < 0 else keys[from * stride + FormBase.PK_CHANNELS + c]
		_pose_out[c] = lerpf(a, keys[to * stride + FormBase.PK_CHANNELS + c], eased)
	_pose_out_mood = mood
	return true


## The side a staff animation turns for a carrier that is no swing: the one where a negative turn
## lifts the head (toward the top of the screen) whichever way it faces.
static func up_side(aim: Vector2) -> int:
	return 1 if aim.x >= 0.0 else -1


## `x` (0 to 1) of the way into a key, eased by `ease` (`FormBase.POSE_EASES`: 0 slow, fast, slow;
## 1 slowing into the key; 2 speeding up into it).
static func pose_ease(x: float, ease: int) -> float:
	match ease:
		1:
			return 1.0 - (1.0 - x) * (1.0 - x)
		2:
			return x * x
	return CarrierSwing.swing_ease(x)

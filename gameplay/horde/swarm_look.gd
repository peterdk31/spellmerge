class_name SwarmLook
extends Node2D
## The swarm's look (horde swarm S2, docs/milestones/horde-swarm.md, "The idea"): every swarmer
## drawn exactly as a full enemy of its kind is (owner, 2026-10-31: a simpler look is not fine),
## but in batches: one MultiMeshInstance2D per kind, an instance per swarmer, never a node each.
## It reads the swarm's rows and draws; it changes nothing the game plays by.
##
## What it draws, per row, is what the nodes of the kind's full scene show, by the same rules and
## the same numbers (read from the scripts' constants and the Feel preset, never copied):
## - the body (the scene's "Sprite": its texture, frame, place, offset and scale), with
##   `CreatureLook`'s hop while walking (faster than HOP_SPEED: HOP_HEIGHT px, HOP_RATE a second)
##   and bob while standing (HOP_IDLE), and its hurt pose for HURT_TIME after a hit when the scene
##   has a `hurt_texture`; a swarmer has no staff, so no telegraph, windup or staff animation;
## - Feel's hit flash (the body in plain white) and squash (wide and low, settling back) for the
##   preset's `flash_seconds` and `hit_squash`, stepped in real time as Feel steps them;
## - the whole `Face` (the scene's style, resting mood, anchor and glow): eyes in the nine look
##   directions from the aim and the blink, brows by mood (worried for Face.HURT_TIME after a hit,
##   down: shut and worried), the style's idle habits from a generator seeded per row (the swarm's
##   `seeds`; seeded as a Face seeds its own, and stepped the same, so a row with a Face's seed
##   blinks when that Face does), and the follow-through lag of eyes and brows behind the body.
## A full enemy's statuses are Feel's, drawn by node position (each swarmer keeps its bare node),
## so they are not here. Not the same yet: Feel's death animation copies the dead node's "Sprite",
## which a swarmer's bare node lacks, so a swarmer dies without it (integration's to give Feel);
## Feel flashes at most REACT_SLOTS sprites at once, the look every row hit.
##
## Each instance's mesh is three quads, body, eyes and brows, so a swarmer is drawn whole before the
## next, as an actor's nodes are, in row order within its kind (`swarm_look.gdshader` places them
## and picks the frames); kinds are drawn one batch after the other. The shader is warmed by the
## Horde autoload (`horde.gd`, `_ready`), before the first Play.
##
## **What the swarm gives it** (S1, `swarm.gd`; "The rows S1 gives S2"): `count`, `kinds`
## (PackedInt32Array, an index into `kinds_list`, whose entries each have a `scene`: the kind's
## full PackedScene, read once here), `positions`, `velocities` and `aims` (PackedVector2Array, in
## this node's space: put the look where the swarm's nodes are, at no offset), `seeds` (an int per
## row), and optionally `down` (PackedByteArray) and `ran` (PackedFloat64Array, doubles as
## `Actors.spend_hold` returns them: the seconds each row stepped in the last step, less than
## `delta` when a hit-stop hold ended within it, 0 while held; without it every row ran `delta`).
##
## **What the swarm must call:**
## - `step(delta)` in its physics step, after it set the rows' velocities and aims and BEFORE it
##   moves their positions (a full actor's looks step after its Mover and before `move_and_slide`).
## - `on_hit(row)` for every `damage_dealt` naming a swarmer's node (as Combat's hit sends a full
##   actor its `damaged`, which CreatureLook, Face and Feel react to).
## - `on_row_removed(row)` right after it swap-removed `row` (the last row moved into `row`), and
##   `on_row_moved(from, to)` for any other move of a row; new rows are taken up by themselves
##   (rows `count` grew by). `clear()` when the swarm empties at once.
## The look steps Feel's part in its own `_process` in real time (as Feel does); tests turn that
## off (`real_time = false`) and call `step_feel(seconds)`, which also writes the batches.
##
## Nothing is allocated per step: every row's look is packed arrays that grow only with the
## swarm's largest count, and each batch is written from one reused buffer.

const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const SHADER: Shader = preload("res://gameplay/horde/swarm_look.gdshader")
const DEFAULT_PRESET: Resource = preload("res://gameplay/feel/presets/punchy.tres")
## Floats per instance in a batch's buffer: a 2D transform, a colour and the custom data.
const STRIDE: int = 16
## The batches grow by this many rows at a time.
const GROW: int = 256
## The layers' quads cover at most this far round a swarmer (for the batch's culling box).
const REACH: float = 64.0
## The brows' column: + this while Feel's flash shows, + this twice while the hurt pose shows.
const FLAG_FLASH: float = 8.0
const FLAG_HURT: float = 16.0

## The swarm whose rows it draws (see the class doc); set before it is added, or with `setup`.
var swarm: Object = null
## The Feel autoload (its `preset`); empty: "/root/Feel", else the default preset.
var feel: Node = null
## True: Feel's part (flash, squash) and the batches step in `_process` in real time.
var real_time: bool = true

## Per kind (an index into the swarm's `kinds_list`): its batch, its buffer, and the scene's look.
var _batches: Array[MultiMeshInstance2D] = []
var _buffers: Array[PackedFloat32Array] = []
## The draw's scratch: rows written per kind, where each kind's rows start in `_order`, the rows
## by kind, and an empty buffer that holds a kind's place while its own is written.
var _filled: PackedInt32Array = PackedInt32Array()
var _first: PackedInt32Array = PackedInt32Array()
var _order: PackedInt32Array = PackedInt32Array()
var _none: PackedFloat32Array = PackedFloat32Array()
## Each kind's look read from its scene: the face style, resting mood and anchor, the brow row, and
## whether it has a hurt pose.
var _style: PackedInt32Array = PackedInt32Array()
var _resting: PackedInt32Array = PackedInt32Array()
var _anchor: PackedVector2Array = PackedVector2Array()
var _brow_row: PackedInt32Array = PackedInt32Array()
var _has_hurt: PackedByteArray = PackedByteArray()

## Rows the look knows (in step with the swarm's `count`) and the room in its arrays.
var _count: int = 0
var _room: int = 0
## CreatureLook's and the Face's numbers are doubles, as their `float` fields are (a half pixel
## rounds the same way); Feel's are singles, as its packed arrays are.
## CreatureLook's part: the time hopped, the lift (px, up negative) and the hurt pose left.
var _hop_time: PackedFloat64Array = PackedFloat64Array()
var _lift: PackedFloat64Array = PackedFloat64Array()
var _hurt_left: PackedFloat64Array = PackedFloat64Array()
## The Face's part (its private fields, a row each).
var _eye_point: PackedVector2Array = PackedVector2Array()
var _brow_point: PackedVector2Array = PackedVector2Array()
var _placed: PackedByteArray = PackedByteArray()
var _mood_left: PackedFloat64Array = PackedFloat64Array()
var _still_for: PackedFloat64Array = PackedFloat64Array()
var _blink_in: PackedFloat64Array = PackedFloat64Array()
var _blink_left: PackedFloat64Array = PackedFloat64Array()
var _glance_in: PackedFloat64Array = PackedFloat64Array()
var _glance_left: PackedFloat64Array = PackedFloat64Array()
var _glance_x: PackedInt32Array = PackedInt32Array()
var _raise_in: PackedFloat64Array = PackedFloat64Array()
var _raise_left: PackedFloat64Array = PackedFloat64Array()
## Each row's generator state (one generator is shared: its state is put in and taken out).
var _rng_state: PackedInt64Array = PackedInt64Array()
## What the face layers show: the eye and brow columns, and where each layer sits.
var _eye_column: PackedInt32Array = PackedInt32Array()
var _brow_column: PackedInt32Array = PackedInt32Array()
var _eyes_at: PackedVector2Array = PackedVector2Array()
var _brows_at: PackedVector2Array = PackedVector2Array()
## Feel's part: seconds of the flash left and in all, its squash, and the squash now.
var _flash_left: PackedFloat32Array = PackedFloat32Array()
var _flash_total: PackedFloat32Array = PackedFloat32Array()
var _flash_amount: PackedFloat32Array = PackedFloat32Array()
var _squash: PackedFloat32Array = PackedFloat32Array()
## A held row's looks have shown the start of its hold (Actor.step's `_hold_shown`).
var _hold_shown: PackedByteArray = PackedByteArray()

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## How far the face layers close on the body in one step of `_k_delta` seconds (Face's).
var _k_delta: float = -1.0
var _k: float = 0.0
## The real clock, for Feel's part in `_process`.
var _last_usec: int = 0


## Draw `of_swarm`'s rows from now on.
func setup(of_swarm: Object) -> void:
	swarm = of_swarm
	_take_kinds()


func _init() -> void:
	name = "SwarmLook"
	# Compiled before the first room, as every shader is (core/README.md, "The shot shaders").
	ShaderWarmupScript.want(SHADER, ShaderWarmupScript.BATCH)


func _ready() -> void:
	if feel == null:
		feel = get_node_or_null("/root/Feel")
	_last_usec = Time.get_ticks_usec()
	_take_kinds()


func _process(delta: float) -> void:
	if not real_time:
		return
	# Real time, as Feel's flash runs: a game-wide stop (Engine.time_scale) does not slow it.
	var now: int = Time.get_ticks_usec()
	var real_delta: float = minf(float(now - _last_usec) / 1000000.0, 0.25) if _last_usec > 0 else delta
	_last_usec = now
	step_feel(real_delta)


## Step every row's body and face by `delta` seconds (see the class doc for when).
func step(delta: float) -> void:
	if swarm == null:
		return
	_take_kinds()
	_take_rows()
	var count: int = _count
	var positions: PackedVector2Array = swarm.positions
	var velocities: PackedVector2Array = swarm.velocities
	var aims: PackedVector2Array = swarm.aims
	var kinds: PackedInt32Array = swarm.kinds
	var has_ran: bool = "ran" in swarm
	var has_down: bool = "down" in swarm
	var ran: PackedFloat64Array = swarm.ran if has_ran else PackedFloat64Array()
	var down: PackedByteArray = swarm.down if has_down else PackedByteArray()
	# The scripts' numbers, read once a step (a class constant costs a lookup each time).
	var hop_speed: float = CreatureLook.HOP_SPEED * CreatureLook.HOP_SPEED
	var hop_rate: float = CreatureLook.HOP_RATE
	var hop_height: float = CreatureLook.HOP_HEIGHT
	var hop_idle: float = CreatureLook.HOP_IDLE
	var snap: float = Face.SNAP * Face.SNAP
	var max_lag: float = Face.MAX_LAG
	var lean: float = Face.LOOK_LEAN
	var blink_column: int = Face.BLINK_COLUMN
	var idle_after: float = Face.IDLE_AFTER
	var worried: int = Face.Mood.WORRIED
	var raised: int = Face.Mood.RAISED
	# Every row's CreatureLook and Face step (their `step`s written out for a row; one loop, no
	# call per row).
	for row in count:
		var seconds: float = delta
		var velocity: Vector2 = velocities[row]
		if has_ran:
			# Doubles, as the actors' own: the hop rounds half pixels, so a time off in its last
			# bits can show a pixel off.
			seconds = ran[row]
			if seconds <= 0.0:
				# Held (a hit-stop): the looks show its start once, standing, with no time passing.
				if _hold_shown[row] != 0:
					continue
				_hold_shown[row] = 1
				seconds = 0.0
				velocity = Vector2.ZERO
			else:
				_hold_shown[row] = 0
		var is_down: bool = has_down and down[row] != 0
		var kind: int = kinds[row]
		# CreatureLook: the hurt pose counts down, then the hop (no staff animation: no staff).
		if _hurt_left[row] > 0.0:
			_hurt_left[row] = maxf(_hurt_left[row] - seconds, 0.0)
		var hop_time: float = _hop_time[row] + seconds
		_hop_time[row] = hop_time
		var walking: bool = velocity.length_squared() > hop_speed
		var lift: float = 0.0
		if walking:
			lift = -roundf(absf(sin(hop_time * hop_rate * PI)) * hop_height)
		else:
			lift = -roundf((sin(hop_time * hop_rate) * 0.5 + 0.5) * hop_idle)
		_lift[row] = lift
		# Face: no cast pops (no staff); the shown mood counts down; the habits; the follow.
		if _mood_left[row] > 0.0:
			_mood_left[row] = maxf(_mood_left[row] - seconds, 0.0)
		var blink_left: float = maxf(_blink_left[row] - seconds, 0.0)
		var blink_in: float = _blink_in[row] - seconds
		_blink_in[row] = blink_in
		if blink_in <= 0.0:
			blink_left = _blink(row, _style[kind])
		_blink_left[row] = blink_left
		# A Face stands while its intent does not walk; a swarmer has no intent, so it stands while
		# its body does not walk (the hop's own test). A stray never glances nor raises a brow.
		var still_for: float = _still_for[row] + seconds if not walking else 0.0
		_still_for[row] = still_for
		if still_for >= idle_after:
			_idle_habits(row, _style[kind], seconds)
		else:
			_glance_left[row] = 0.0
			_raise_left[row] = 0.0
		var body: Vector2 = positions[row]
		body.y += lift
		var eye_point: Vector2 = _eye_point[row]
		var brow_point: Vector2 = _brow_point[row]
		if _placed[row] == 0 or eye_point.distance_squared_to(body) > snap:
			eye_point = body
			brow_point = body
			_placed[row] = 1
		if seconds != _k_delta:
			# The same step length every physics step: worked out once (as the Face does).
			_k_delta = seconds
			_k = 1.0 - exp(-seconds / Face.LAG)
		eye_point += (body - eye_point) * _k
		brow_point += (eye_point - brow_point) * _k
		_eye_point[row] = eye_point
		_brow_point[row] = brow_point
		var eyes_at: Vector2 = _anchor[kind] + (eye_point - body).clampf(-max_lag, max_lag).round()
		eyes_at.y += lift
		_eyes_at[row] = eyes_at
		_brows_at[row] = eyes_at + (brow_point - eye_point).clampf(-max_lag, max_lag).round()
		var column: int = blink_column
		if blink_left <= 0.0 and not is_down:
			var look_x: int = 0
			var look_y: int = 0
			if _glance_left[row] > 0.0:
				look_x = _glance_x[row]
			else:
				var aim: Vector2 = aims[row]
				look_x = 1 if aim.x > lean else (-1 if aim.x < -lean else 0)
				look_y = 1 if aim.y > lean else (-1 if aim.y < -lean else 0)
			column = (look_y + 1) * 3 + look_x + 1
		_eye_column[row] = column
		var mood: int = _resting[kind]
		if is_down or _mood_left[row] > 0.0:
			mood = worried
		elif _raise_left[row] > 0.0:
			mood = raised
		_brow_column[row] = mood


## Step Feel's part (flash and squash) by `real_delta` seconds of real time, then write the batches.
func step_feel(real_delta: float) -> void:
	if swarm == null:
		return
	_take_kinds()
	_take_rows()
	for row in _count:
		if _flash_left[row] <= 0.0:
			continue
		# Feel._step_reactions: the time goes first; done, the body is put back.
		_flash_left[row] -= real_delta
		if _flash_left[row] <= 0.0:
			_flash_left[row] = 0.0
			_squash[row] = 0.0
		else:
			_squash[row] = _flash_amount[row] * _flash_left[row] / maxf(_flash_total[row], 0.001)
	draw_rows()


## A hit on the swarmer in `row`: CreatureLook's hurt pose, the Face's worried brows and Feel's
## flash and squash start (again), as a full actor's do on its `damaged` and Feel's `damage_dealt`.
func on_hit(row: int) -> void:
	_take_rows()
	if row < 0 or row >= _count:
		return
	_hurt_left[row] = CreatureLook.HURT_TIME
	_mood_left[row] = Face.HURT_TIME
	var preset: Resource = _preset()
	var seconds: float = preset.get(&"flash_seconds") as float
	if seconds <= 0.0:
		return
	# Feel._react: the flash shows at once; the squash is written by the next step of Feel's part.
	_flash_left[row] = seconds
	_flash_total[row] = seconds
	_flash_amount[row] = preset.get(&"hit_squash") as float


## The swarm moved the row `from` to `to` (its look goes with it).
func on_row_moved(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= _room or to >= _room:
		return
	_hop_time[to] = _hop_time[from]
	_lift[to] = _lift[from]
	_hurt_left[to] = _hurt_left[from]
	_eye_point[to] = _eye_point[from]
	_brow_point[to] = _brow_point[from]
	_placed[to] = _placed[from]
	_mood_left[to] = _mood_left[from]
	_still_for[to] = _still_for[from]
	_blink_in[to] = _blink_in[from]
	_blink_left[to] = _blink_left[from]
	_glance_in[to] = _glance_in[from]
	_glance_left[to] = _glance_left[from]
	_glance_x[to] = _glance_x[from]
	_raise_in[to] = _raise_in[from]
	_raise_left[to] = _raise_left[from]
	_rng_state[to] = _rng_state[from]
	_eye_column[to] = _eye_column[from]
	_brow_column[to] = _brow_column[from]
	_eyes_at[to] = _eyes_at[from]
	_brows_at[to] = _brows_at[from]
	_flash_left[to] = _flash_left[from]
	_flash_total[to] = _flash_total[from]
	_flash_amount[to] = _flash_amount[from]
	_squash[to] = _squash[from]
	_hold_shown[to] = _hold_shown[from]


## The swarm swap-removed `row`: its last row took `row`'s place, and there is one row less.
func on_row_removed(row: int) -> void:
	if row < 0 or row >= _count:
		return
	var last: int = _count - 1
	on_row_moved(last, row)
	_count = last


## Forget every row (the swarm emptied at once).
func clear() -> void:
	_count = 0
	for batch in _batches:
		batch.multimesh.visible_instance_count = 0


## Rows the look knows now.
func row_count() -> int:
	return _count


## Write every row into its kind's batch: where it is now and what each layer shows.
func draw_rows() -> void:
	if swarm == null:
		return
	var kinds_made: int = _batches.size()
	var positions: PackedVector2Array = swarm.positions
	var kinds: PackedInt32Array = swarm.kinds
	# The rows by kind, in row order within each (a counting sort into `_order`).
	_filled.fill(0)
	for row in _count:
		var kind: int = kinds[row]
		if kind >= 0 and kind < kinds_made:
			_filled[kind] += 1
	var start: int = 0
	for kind in kinds_made:
		var rows_of_kind: int = _filled[kind]
		_first[kind] = start
		_filled[kind] = start
		start += rows_of_kind
	for row in _count:
		var kind: int = kinds[row]
		if kind >= 0 and kind < kinds_made:
			_order[_filled[kind]] = row
			_filled[kind] += 1
	for kind in kinds_made:
		var first: int = _first[kind]
		var shown: int = _filled[kind] - first
		# Taken out of the list while written, so the writes do not copy it.
		var buffer: PackedFloat32Array = _buffers[kind]
		_buffers[kind] = _none
		var has_hurt: bool = _has_hurt[kind] != 0
		for slot in shown:
			var row: int = _order[first + slot]
			var at: int = slot * STRIDE
			var place: Vector2 = positions[row]
			var flags: float = float(_brow_column[row])
			if _flash_left[row] > 0.0:
				flags += FLAG_FLASH
			if has_hurt and _hurt_left[row] > 0.0:
				flags += FLAG_HURT
			var eyes: Vector2 = _eyes_at[row]
			var brows: Vector2 = _brows_at[row]
			# The transform's basis is written once, when the batch grows: only the place moves.
			buffer[at + 3] = place.x
			buffer[at + 7] = place.y
			buffer[at + 8] = _lift[row]
			buffer[at + 9] = _squash[row]
			buffer[at + 10] = float(_eye_column[row])
			buffer[at + 11] = flags
			buffer[at + 12] = eyes.x
			buffer[at + 13] = eyes.y
			buffer[at + 14] = brows.x
			buffer[at + 15] = brows.y
		var multimesh: MultiMesh = _batches[kind].multimesh
		if shown > 0:
			RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)
		multimesh.visible_instance_count = shown
		_buffers[kind] = buffer


## For tests: what row `row` shows now, as a full enemy's nodes would say it: the body's offset
## from the Sprite's rest offset (the hop), the body's scale (Feel's squash), whether it is white
## (Feel's flash) and in the hurt pose, the eye and brow frames (column, row of their sheets) and
## where the eye and brow layers sit (the Face's space).
func row_look(row: int) -> Dictionary:
	var kind: int = (swarm.kinds as PackedInt32Array)[row]
	var squash: float = _squash[row]
	return {
		"lift": Vector2(0.0, _lift[row]),
		"scale": Vector2(1.0 + squash, 1.0 - squash),
		"flash": _flash_left[row] > 0.0,
		"hurt": _hurt_left[row] > 0.0 and _has_hurt[kind] != 0,
		"eyes_frame": Vector2i(_eye_column[row], _style[kind]),
		"brows_frame": Vector2i(_brow_column[row], _brow_row[kind]),
		"eyes_at": _eyes_at[row],
		"brows_at": _brows_at[row],
		"shut": _blink_left[row] > 0.0,
	}


## For tests and the stress runs: the batch of `kind` (an index into the swarm's `kinds_list`).
func batch(kind: int) -> MultiMeshInstance2D:
	return _batches[kind] if kind >= 0 and kind < _batches.size() else null


## For tests: the STRIDE floats last written for instance `slot` of `kind`'s batch (a transform,
## the colour and the custom data, as the shader reads them).
func instance_data(kind: int, slot: int) -> PackedFloat32Array:
	return _buffers[kind].slice(slot * STRIDE, (slot + 1) * STRIDE)


## A row's blink starts (Face._step_habits): its length, and the wait for the next one drawn from
## the row's generator. Returns the blink's seconds.
func _blink(row: int, style: int) -> float:
	_rng.state = _rng_state[row]
	_blink_in[row] = _wait(Face.BLINK_EVERY, style)
	_rng_state[row] = _rng.state
	return Face.BLINK_TIME[style]


## Face._step_habits for a row that is idle: its glances and raised brows.
func _idle_habits(row: int, style: int, delta: float) -> void:
	_glance_left[row] = maxf(_glance_left[row] - delta, 0.0)
	_raise_left[row] = maxf(_raise_left[row] - delta, 0.0)
	_glance_in[row] -= delta
	if _glance_in[row] <= 0.0:
		_rng.state = _rng_state[row]
		_glance_left[row] = Face.GLANCE_TIME
		_glance_x[row] = -1 if _rng.randf() < 0.5 else 1
		_glance_in[row] = _wait(Face.GLANCE_EVERY, style)
		_rng_state[row] = _rng.state
	_raise_in[row] -= delta
	if _raise_in[row] <= 0.0:
		_rng.state = _rng_state[row]
		_raise_left[row] = Face.RAISE_TIME
		_raise_in[row] = _wait(Face.RAISE_EVERY, style)
		_rng_state[row] = _rng.state


## Face._wait with the shared generator (holding the row's state).
func _wait(every_by_style: PackedFloat32Array, style: int) -> float:
	var every: float = every_by_style[style]
	if every <= 0.0:
		return INF
	return every * _rng.randf_range(0.7, 1.3)


## Take up the rows the swarm added since the last call (its `count` grew).
func _take_rows() -> void:
	var count: int = swarm.count
	if count < _count:
		# Rows went without `on_row_removed`: nothing tells which, so the last ones are dropped.
		_count = count
		return
	if count == _count:
		return
	if count > _room:
		_grow(count)
	var kinds: PackedInt32Array = swarm.kinds
	for row in range(_count, count):
		_start_row(row, kinds[row])
	_count = count


## A new row's look, as a Face and a CreatureLook start: seeded from the swarm's `seeds`.
func _start_row(row: int, kind: int) -> void:
	var style: int = _style[kind] if kind >= 0 and kind < _style.size() else Face.Style.STRAY
	var seed_value: int = swarm.seeds[row]
	_rng.seed = seed_value
	_blink_in[row] = _wait(Face.BLINK_EVERY, style)
	_glance_in[row] = _wait(Face.GLANCE_EVERY, style)
	_raise_in[row] = _wait(Face.RAISE_EVERY, style)
	_rng_state[row] = _rng.state
	_hop_time[row] = 0.0
	_lift[row] = 0.0
	_hurt_left[row] = 0.0
	_placed[row] = 0
	_mood_left[row] = 0.0
	_still_for[row] = 0.0
	_blink_left[row] = 0.0
	_glance_left[row] = 0.0
	_glance_x[row] = 0
	_raise_left[row] = 0.0
	_flash_left[row] = 0.0
	_flash_total[row] = 0.0
	_flash_amount[row] = 0.0
	_squash[row] = 0.0
	_hold_shown[row] = 0
	_eye_column[row] = (0 + 1) * 3 + 0 + 1
	_brow_column[row] = _resting[kind] if kind >= 0 and kind < _resting.size() else Face.Mood.NEUTRAL
	var anchor: Vector2 = _anchor[kind] if kind >= 0 and kind < _anchor.size() else Vector2.ZERO
	_eyes_at[row] = anchor
	_brows_at[row] = anchor


## Room for `rows` rows (and their instances in every batch), grown GROW at a time.
func _grow(rows: int) -> void:
	_room = (rows / GROW + 1) * GROW
	_order.resize(_room)
	_hop_time.resize(_room)
	_lift.resize(_room)
	_hurt_left.resize(_room)
	_eye_point.resize(_room)
	_brow_point.resize(_room)
	_placed.resize(_room)
	_mood_left.resize(_room)
	_still_for.resize(_room)
	_blink_in.resize(_room)
	_blink_left.resize(_room)
	_glance_in.resize(_room)
	_glance_left.resize(_room)
	_glance_x.resize(_room)
	_raise_in.resize(_room)
	_raise_left.resize(_room)
	_rng_state.resize(_room)
	_eye_column.resize(_room)
	_brow_column.resize(_room)
	_eyes_at.resize(_room)
	_brows_at.resize(_room)
	_flash_left.resize(_room)
	_flash_total.resize(_room)
	_flash_amount.resize(_room)
	_squash.resize(_room)
	_hold_shown.resize(_room)
	for kind in _batches.size():
		_size_batch(kind)


func _size_batch(kind: int) -> void:
	var multimesh: MultiMesh = _batches[kind].multimesh
	if multimesh.instance_count >= _room:
		return
	multimesh.instance_count = _room
	multimesh.visible_instance_count = 0
	var buffer: PackedFloat32Array = _buffers[kind]
	_buffers[kind] = _none
	var from: int = buffer.size() / STRIDE
	buffer.resize(_room * STRIDE)
	for slot in range(from, _room):
		# An unturned, unscaled transform (x axis, then y axis, each with the place's column).
		buffer[slot * STRIDE] = 1.0
		buffer[slot * STRIDE + 5] = 1.0
	_buffers[kind] = buffer


## A batch for every kind of the swarm's `kinds_list` not made yet.
func _take_kinds() -> void:
	if swarm == null:
		return
	var list: Array = swarm.kinds_list
	while _batches.size() < list.size():
		var entry: Object = list[_batches.size()] as Object
		var scene: PackedScene = entry.get(&"scene") as PackedScene if entry != null else null
		_add_kind(scene)


## Read the look of a full enemy's `scene` (its Sprite, CreatureLook and Face, as set in the scene)
## and make its batch.
func _add_kind(scene: PackedScene) -> void:
	var sprite: Sprite2D = null
	var creature: CreatureLook = null
	var face: Face = null
	var instance: Node = scene.instantiate() if scene != null else null
	if instance != null:
		sprite = instance.get_node_or_null(^"Sprite") as Sprite2D
		for child in instance.get_children():
			if child is CreatureLook and creature == null:
				creature = child as CreatureLook
			elif child is Face and face == null:
				face = child as Face
	if sprite == null or sprite.texture == null or face == null:
		push_warning("SwarmLook: %s has no Sprite with a texture or no Face; its swarmers are not drawn." % (scene.resource_path if scene != null else "a kind"))
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var style: int = Face.Style.STRAY
	var resting: int = Face.Mood.NEUTRAL
	var anchor: Vector2 = Vector2.ZERO
	var has_hurt: bool = false
	var body_texture: Texture2D = null
	if sprite != null and sprite.texture != null:
		body_texture = sprite.texture
		var sheet: Vector2 = body_texture.get_size()
		var size: Vector2 = Vector2(sheet.x / float(sprite.hframes), sheet.y / float(sprite.vframes))
		var region: Vector2 = Vector2(float(sprite.frame % sprite.hframes), float(sprite.frame / sprite.hframes)) * size
		if sprite.region_enabled:
			region = sprite.region_rect.position
			size = sprite.region_rect.size
			sheet = body_texture.get_size()
		var offset: Vector2 = sprite.offset - (size / 2.0 if sprite.centered else Vector2.ZERO)
		material.set_shader_parameter(&"body_size", size)
		material.set_shader_parameter(&"body_region", region)
		material.set_shader_parameter(&"body_texture_size", sheet)
		material.set_shader_parameter(&"sprite_position", sprite.position)
		material.set_shader_parameter(&"sprite_scale", sprite.scale)
		material.set_shader_parameter(&"sprite_offset", offset)
		var hurt: Texture2D = creature.hurt_texture if creature != null else null
		if hurt != null:
			# CreatureLook._show_strip: square frames, the first shown.
			has_hurt = true
			material.set_shader_parameter(&"hurt_sheet", hurt)
			material.set_shader_parameter(&"hurt_region", Vector2.ZERO)
			material.set_shader_parameter(&"hurt_texture_size", hurt.get_size())
			if not is_equal_approx(float(hurt.get_height()), size.y):
				push_warning("SwarmLook: %s's hurt frames are not its body's size." % scene.resource_path)
		else:
			material.set_shader_parameter(&"hurt_texture_size", Vector2.ONE)
	if face != null:
		style = face.style
		resting = face.resting_mood
		anchor = face.anchor
		material.set_shader_parameter(&"face_position", face.position)
		material.set_shader_parameter(&"glow", face.glow)
	material.set_shader_parameter(&"eyes_sheet", Face.EYES_SHEET)
	material.set_shader_parameter(&"brows_sheet", Face.BROWS_SHEET)
	material.set_shader_parameter(&"eyes_sheet_size", Face.EYES_SHEET.get_size())
	material.set_shader_parameter(&"brows_sheet_size", Face.BROWS_SHEET.get_size())
	material.set_shader_parameter(&"frame_size", Vector2(Face.FRAME))
	material.set_shader_parameter(&"eyes_origin", Face.EYES_ORIGIN)
	material.set_shader_parameter(&"brows_origin", Face.BROWS_ORIGIN)
	material.set_shader_parameter(&"eyes_row", float(style))
	var brow_row: int = 1 if style == Face.Style.STRAY_ONE else 0
	material.set_shader_parameter(&"brows_row", float(brow_row))
	if instance != null:
		instance.free()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _layers_mesh()
	var node := MultiMeshInstance2D.new()
	node.name = "Kind%d" % _batches.size()
	node.multimesh = multimesh
	node.texture = body_texture
	node.material = material
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite != null:
		node.texture_filter = sprite.texture_filter if sprite.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE else CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(node)
	_batches.append(node)
	_buffers.append(PackedFloat32Array())
	_filled.append(0)
	_first.append(0)
	_style.append(style)
	_resting.append(resting)
	_anchor.append(anchor)
	_brow_row.append(brow_row)
	_has_hurt.append(1 if has_hurt else 0)
	if _room > 0:
		_size_batch(_batches.size() - 1)


## The mesh every instance draws: the body's, the eyes' and the brows' quads in that order, each
## telling the shader its layer and corner in its UV. Its corners only size the culling box.
static func _layers_mesh() -> ArrayMesh:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for layer in 3:
		for corner in corners:
			points.append((corner * 2.0 - Vector2.ONE) * REACH)
			uvs.append(Vector2(corner.x + 2.0 * float(layer), corner.y))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The Feel preset the flash and squash read (the live one, so a change there changes both).
func _preset() -> Resource:
	if feel != null and is_instance_valid(feel):
		var preset: Resource = feel.get(&"preset") as Resource
		if preset != null:
			return preset
	return DEFAULT_PRESET

class_name HitBatch
extends RefCounted
## A hit pass's merged hits (hit batch A1, docs/milestones/hit-batch.md, "The seam"): the projectile
## manager's, emptied within its step. A pass's shot hits of one caster's spell (one tag) on one body
## are one entry, sent after the pass as one `projectile_hit` with `impact_count` (a shot that hits
## alone, `F_ALONE`, is an entry of its own). Kept here: the entries; each body's tally in the pass
## (its health as Combat last told it, `HitRoom`, the damage the pass's hits counted off it, its
## barrier's charges and those used), so no shot is spent on a body the pass has killed; the shots
## the pass's hits spent (ended at its end, their tails where they were spent); the slots of shots
## ended during the pass (held until its hits are sent: a hit names its shot's slot); and the tags of
## the ends kept for after the hits.
##
## The manager ends the shots, frees and takes back slots, asks Combat (with `room`) and sends the
## entries; the batch never calls it. The native hit pass (`ShotKernel`, `BATCH_FIELDS`) reads and
## writes the entries' counts, the tallies and the spent list in place, so they are packed arrays,
## sized before the pass (the kernel never grows one), and it counts a hit as `count_hit` does.
##
## Not state: emptied within a step (the manager's DERIVED `_hit_batch`).

## The entries, `entries` of them: each one's caster, target (an index of the manager's targets),
## tag, shot (`slot`, and its `seq` when it hit: a slot taken since names no shot), point, heading
## and how many hits it stands for, and its first shot's look (carrier card, body, core, look bits).
## Read by the manager to send them; written by the batch (and the kernel, as `count_hit`).
var entries: int = 0
var caster: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()
var tag: PackedInt64Array = PackedInt64Array()
var slot: PackedInt32Array = PackedInt32Array()
var seq: PackedInt64Array = PackedInt64Array()
var at: PackedVector2Array = PackedVector2Array()
var heading: PackedVector2Array = PackedVector2Array()
var count: PackedInt32Array = PackedInt32Array()
var card: Array[StringName] = []
var body: PackedInt32Array = PackedInt32Array()
var core: PackedColorArray = PackedColorArray()
var look: PackedInt32Array = PackedInt32Array()
## What Combat is asked to fill at an entry's first hit (`hit_room_asked`), one for every ask.
var room: HitRoom = HitRoom.new()

## Each entry's next on its target (-1 for the last), its damage a hit and whether its spell meets
## the target's barrier.
var _next: PackedInt32Array = PackedInt32Array()
var _damage: PackedFloat64Array = PackedFloat64Array()
var _blocks: PackedByteArray = PackedByteArray()
## By target, while `_target_pass` is this pass (`_pass`): its first entry, the health the last ask
## told (whichever spell asked, so damage dealt outside the batch meanwhile counts), the damage the
## pass's hits counted off it, and its barrier's charges and those the pass's hits took.
var _pass: int = 0
var _target_pass: PackedInt32Array = PackedInt32Array()
var _head: PackedInt32Array = PackedInt32Array()
var _health: PackedFloat64Array = PackedFloat64Array()
var _spent: PackedFloat64Array = PackedFloat64Array()
var _charges: PackedInt32Array = PackedInt32Array()
var _charges_used: PackedInt32Array = PackedInt32Array()
## The shots the pass's hits spent, in order, and where each was spent; sized for the pass's shots.
var _used: PackedInt32Array = PackedInt32Array()
var _used_at: PackedVector2Array = PackedVector2Array()
var _used_n: int = 0
## The slots of the shots ended during the pass, held until its hits are sent.
var _held: PackedInt32Array = PackedInt32Array()
var _held_n: int = 0
## The tags of the shots' ends kept for after the pass's hits.
var _ended: PackedInt64Array = PackedInt64Array()
var _ended_n: int = 0


## A pass of `shots` shots over `targets` targets begins: the tallies of the last are forgotten.
func open(targets: int, shots: int) -> void:
	_pass += 1
	fit_targets(targets)
	if _used.size() < shots:
		_used.resize(shots)
		_used_at.resize(shots)


## Every list emptied (a pass's end, or the manager's `clear`, which a handler may call mid-pass).
func empty() -> void:
	entries = 0
	_used_n = 0
	_held_n = 0
	_ended_n = 0


## The per-target tables sized for `targets` targets (one a hit handler added during the pass too).
func fit_targets(targets: int) -> void:
	if _target_pass.size() < targets:
		_head.resize(targets)
		_health.resize(targets)
		_spent.resize(targets)
		_charges.resize(targets)
		_charges_used.resize(targets)
		_target_pass.resize(targets)


## False when the damage the pass's hits counted off `t`, every spell's, reaches its health.
func takes(t: int) -> bool:
	return not (t < _target_pass.size() and _target_pass[t] == _pass and _spent[t] >= _health[t])


## A hit of `who`'s spell `spell` on target `t` added to its entry of the pass (one more hit,
## counted off the target's room: `count_hit`), which is returned; -1, counting nothing, when it has
## none yet. A shot that hits alone (`alone`), and an entry whose shot does (`flags` of its slot, the
## manager's shot flags, `alone_flag` the bit), add to none. The slot's flags are read now, as the
## kernel reads them, not kept at `add`: a slot taken back at the cap may hold another shot by now.
## One call a hit, the lookup and the count in it (the hit pass's hottest call).
func add_to(t: int, who: int, spell: int, alone: bool, flags: PackedInt32Array, alone_flag: int) -> int:
	if alone or t >= _target_pass.size() or _target_pass[t] != _pass:
		return -1
	var entry: int = _head[t]
	while entry >= 0:
		if caster[entry] == who and tag[entry] == spell and (flags[slot[entry]] & alone_flag) == 0:
			count[entry] += 1
			_spend_room(t, entry)
			return entry
		entry = _next[entry]
	return -1


## One more hit of `entry` on its target, counted off the target's room: what `add_to` does to the
## entry it finds, and the kernel to an entry it adds a hit to.
func count_hit(entry: int) -> void:
	count[entry] += 1
	_spend_room(target[entry], entry)


## A new entry: the first hit of `who`'s spell `spell` on target `t` (of `targets`) in this pass, by
## the shot in `shot` (`shot_seq`), with that shot's look. Its room is `take_room`'s, next.
func add(t: int, targets: int, who: int, spell: int, shot: int, shot_seq: int, point: Vector2, way: Vector2, carrier_card: StringName, kind: int, colour: Color, look_bits: int) -> int:
	if entries == caster.size():
		_grow(maxi(64, entries * 2))
	fit_targets(targets)
	var entry: int = entries
	entries += 1
	var last: int = -1
	if t < _target_pass.size() and _target_pass[t] == _pass:
		last = _head[t]
		while _next[last] >= 0:
			last = _next[last]
	if last >= 0:
		_next[last] = entry
	else:
		# The target's first entry of the pass: its tally starts.
		_target_pass[t] = _pass
		_head[t] = entry
		_spent[t] = 0.0
		_charges[t] = 0
		_charges_used[t] = 0
	_next[entry] = -1
	caster[entry] = who
	target[entry] = t
	tag[entry] = spell
	slot[entry] = shot
	seq[entry] = shot_seq
	at[entry] = point
	heading[entry] = way
	count[entry] = 1
	card[entry] = carrier_card
	body[entry] = kind
	core[entry] = colour
	look[entry] = look_bits
	return entry


## `room` as Combat filled it for `entry`'s first hit: its damage a hit, the target's health (the
## latest ask's, whichever spell asked) and the barrier's charges as a spell they meet says; then
## that first hit counted.
func take_room(entry: int) -> void:
	var t: int = target[entry]
	_damage[entry] = room.damage
	_health[t] = room.health
	_blocks[entry] = 1 if room.charges > 0 else 0
	if room.charges > 0:
		_charges[t] = room.charges
	_spend_room(t, entry)


## The shot in `shot` was spent by a hit at `point`: ended at the pass's end.
func spend(shot: int, point: Vector2) -> void:
	_used[_used_n] = shot
	_used_at[_used_n] = point
	_used_n += 1


## How many shots the pass has spent and not ended yet; the `i`-th of them and where it was spent.
func spent_count() -> int:
	return _used_n


func spent_slot(i: int) -> int:
	return _used[i]


func spent_at(i: int) -> Vector2:
	return _used_at[i]


## The spent list emptied (its shots ended).
func forget_spent() -> void:
	_used_n = 0


## The `i`-th spent shot out of the list (the last takes its place).
func drop_spent(i: int) -> void:
	_used_n -= 1
	_used[i] = _used[_used_n]
	_used_at[i] = _used_at[_used_n]


## The slot `shot` of a shot ended during the pass, held until its hits are sent.
func hold(shot: int) -> void:
	if _held_n == _held.size():
		_held.resize(maxi(64, _held_n * 2))
	_held[_held_n] = shot
	_held_n += 1


## How many slots are held; the `i`-th of them.
func held_count() -> int:
	return _held_n


func held_slot(i: int) -> int:
	return _held[i]


## The `i`-th held slot out of the list (the last takes its place).
func drop_held(i: int) -> void:
	_held_n -= 1
	_held[i] = _held[_held_n]


## The held list emptied (its slots freed).
func forget_held() -> void:
	_held_n = 0


## A shot's end (`tag`) kept for after the pass's hits.
func keep_end(spell: int) -> void:
	if _ended_n == _ended.size():
		_ended.resize(maxi(64, _ended_n * 2))
	_ended[_ended_n] = spell
	_ended_n += 1


## How many ends are kept (read anew as they are sent: a handler's `clear` empties it); the `i`-th.
func ended_count() -> int:
	return _ended_n


func ended_tag(i: int) -> int:
	return _ended[i]


## The entries emptied (sent).
func forget_entries() -> void:
	entries = 0


## The kept ends emptied (sent).
func forget_ended() -> void:
	_ended_n = 0


## One hit of `entry`'s counted on `t`: a charge of its barrier, if its spell meets one with charges
## left, else its damage.
func _spend_room(t: int, entry: int) -> void:
	if _blocks[entry] != 0 and _charges_used[t] < _charges[t]:
		_charges_used[t] += 1
	else:
		_spent[t] += _damage[entry]


func _grow(size: int) -> void:
	_next.resize(size)
	caster.resize(size)
	target.resize(size)
	tag.resize(size)
	slot.resize(size)
	seq.resize(size)
	_damage.resize(size)
	_blocks.resize(size)
	at.resize(size)
	heading.resize(size)
	count.resize(size)
	card.resize(size)
	body.resize(size)
	core.resize(size)
	look.resize(size)

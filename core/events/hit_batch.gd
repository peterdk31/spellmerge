class_name HitBatch
extends RefCounted
## A step's hits of flying shots, sent as one (`Events.projectile_hits`; shot scale H3b,
## docs/milestones/shot-scale.md, "H3b: bundled hit events"). The projectile manager fills it during
## its hit pass instead of sending each hit as it is found, then resolves it in phases, each over
## every hit of the step in hit order:
##
## 1. PHASE_PRE: what must be read before any damage: Spells' `relay` (it changes the profile
##    Combat reads), and Feel's impact looks.
## 2. PHASE_COMBAT: damage, statuses, reactions and kills, hit by hit, as before. A hit on a body
##    an earlier hit of the batch removed (killed) is *lost*: no listener takes it, and its shot is
##    handed back to the manager, which tests it again from the start of its path at the next step
##    (it flies on past where the body was), so no damage is lost.
## 3. PHASE_SPELLS: on-hit cards, chains and payloads, after all of the step's damage.
##
## A listener takes each hit with `Projectiles.batch_turn(i)`, which says whether the hit is still
## to be taken (false for a lost one) and sets what the manager tells while a hit is sent
## (`impact_form`, `impact_core`, its event slot, ...). The arrays are the manager's and reused:
## read them in the handler, never keep them.
##
## Only the hit pass of flying shots fills a batch, and only while the manager's `batch_hits` is on
## (off by default: this is the first part of H3b, to measure). Rays, sweeps and blasts send their
## hits one by one (`projectile_hit`), as before.

const PHASE_PRE: int = 0
const PHASE_COMBAT: int = 1
const PHASE_SPELLS: int = 2

## What a hit did to its shot, for undoing it if the hit is lost: it took one of its pierce, it
## stuck the shot to the body, or it spent the shot (which ends once the batch's damage is done).
const SHOT_PIERCED: int = 0
const SHOT_STUCK: int = 1
const SHOT_SPENT: int = 2

## How many hits there are.
var count: int = 0
## The phase being sent (PHASE_*), -1 while it is filled or idle.
var phase: int = -1
## The hit a listener took last (`batch_turn`), -1 for none: a hit an earlier one kills is lost
## only if it comes after it.
var current: int = -1

# Per hit, in hit order.
var caster: PackedInt32Array = PackedInt32Array()
var target: Array[Node] = []
## The body's index in the manager's targets (stable within a step) and its key (online-ready N5).
var target_index: PackedInt32Array = PackedInt32Array()
var target_key: PackedInt64Array = PackedInt64Array()
var point: PackedVector2Array = PackedVector2Array()
var heading: PackedVector2Array = PackedVector2Array()
var tag: PackedInt64Array = PackedInt64Array()
var shot: PackedInt32Array = PackedInt32Array()
var seq: PackedInt64Array = PackedInt64Array()
var lost: PackedByteArray = PackedByteArray()
# The shot's look while the hit is sent (the manager's `impact_*`).
var form: Array[StringName] = []
var body: PackedInt32Array = PackedInt32Array()
var core: PackedColorArray = PackedColorArray()
var look: PackedInt32Array = PackedInt32Array()
# What the hit did to its shot (SHOT_*), and the shot as it was before it: its pierce, life and
# stick time, and where the path it was tested on began.
var did: PackedByteArray = PackedByteArray()
var pierce_before: PackedInt32Array = PackedInt32Array()
var life_before: PackedFloat32Array = PackedFloat32Array()
var stick_before: PackedFloat32Array = PackedFloat32Array()
var path_from: PackedVector2Array = PackedVector2Array()


## Empty it for the next step (the arrays keep their size).
func clear() -> void:
	for i in count:
		target[i] = null
	count = 0
	phase = -1
	current = -1


## Room for one more hit; returns its index. The arrays only grow (doubling), so a steady step
## allocates nothing.
func add() -> int:
	var i: int = count
	if i == caster.size():
		_grow(maxi(64, i * 2))
	count = i + 1
	lost[i] = 0
	return i


func _grow(size: int) -> void:
	caster.resize(size)
	target.resize(size)
	target_index.resize(size)
	target_key.resize(size)
	point.resize(size)
	heading.resize(size)
	tag.resize(size)
	shot.resize(size)
	seq.resize(size)
	lost.resize(size)
	form.resize(size)
	body.resize(size)
	core.resize(size)
	look.resize(size)
	did.resize(size)
	pierce_before.resize(size)
	life_before.resize(size)
	stick_before.resize(size)
	path_from.resize(size)


## The body with the key `key` was removed (killed): every later hit of the batch on it is lost.
func lose_target(key: int) -> void:
	for i in range(current + 1, count):
		if target_key[i] == key:
			lost[i] = 1

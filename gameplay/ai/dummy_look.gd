class_name DummyLook
extends ActorLook
## What the sandbox's training dummy shows (staffs B7, docs/milestones/M2-staffs.md, "The
## sandbox"; a look since actors G6): the training dummy (content/enemies/training_dummy) is an
## actor with Health (its data's billion), a Hurtbox, the enemy AI like every enemy (an
## `AIController` and the `post` profile; it holds no staff and has no Mover, so it never moves:
## knockback, a swap or a pull leave it where it is) and no build takes it down; "Reset dummies"
## in the sandbox page puts a fresh one there. Enemies never target it: its AI is on their team.
##
## What it shows, all about its actor, with the scene's labels `%Dps`, `%Status` and `%Number`:
## - **Damage numbers:** each hit on the actor (`Actor.damaged`, which Combat sends right after
##   `damage_dealt`: only this actor's hits, not every hit on anyone) rises from its head for NUMBER_TIME
##   seconds, from a pool of NUMBER_COUNT labels (the oldest is reused when all are up). A hit
##   keeps its number, and the new ones are written to their labels once a frame, before it is
##   drawn (`_write_new_numbers`; performance, 2026-11-02: a storm of shots hits a dummy several
##   times a frame, and each write of a label was most of a hit's cost in the sandbox).
## - **Damage per second** over the last DPS_WINDOW seconds, in DPS_BUCKETS buckets, read from
##   the drop of its health in Combat each step, so burn ticks (which send no `damage_dealt` on a
##   target that lives) count too; while a streak is younger than the window it is divided by the
##   streak's age (at least one second), so a short burst reads true. A streak ends when no damage
##   came for a whole window.
## - **Statuses** on it (Combat's `has_status`), and the last **reaction** for REACTION_TIME
##   seconds (`reaction_triggered` at its body, `Actor.body_offset`).
## The labels change every REFRESH seconds at most; nothing is allocated per step. The actor
## steps it (`step`), so tests drive it with fixed deltas through the actor's step.

const CombatScript := preload("res://gameplay/combat/combat.gd")

## Seconds of damage the damage per second covers, and its buckets.
const DPS_WINDOW: float = 5.0
const DPS_BUCKETS: int = 20
## Seconds between label updates.
const REFRESH: float = 0.25
## Damage numbers: how many at once, how long each shows and how far it rises (pixels).
const NUMBER_COUNT: int = 8
const NUMBER_TIME: float = 0.8
const NUMBER_RISE: float = 16.0
## Where a damage number starts, relative to the feet, and how far apart numbers spread sideways.
const NUMBER_START: Vector2 = Vector2(-12.0, -40.0)
const NUMBER_SPREAD: float = 8.0
## Seconds a reaction's name stays on the status line.
const REACTION_TIME: float = 2.0
## How near to the body a `reaction_triggered` must be to count as on this dummy, in pixels.
const REACTION_REACH: float = 2.0
## The statuses the status line names, in this order.
const STATUSES: Array[StringName] = [
	CombatScript.BURN, CombatScript.CHILL, CombatScript.FREEZE, CombatScript.SHOCK,
	CombatScript.HEX, CombatScript.STATIC,
]

## Damage taken since this dummy stood up.
var total_damage: float = 0.0

var _buckets: PackedFloat64Array = PackedFloat64Array()
var _bucket: int = 0
## Health in Combat at the last step (-1 for not known yet).
var _health: float = -1.0
var _bucket_left: float = 0.0
## Seconds since the first hit of the streak, or -1 with no streak.
var _streak: float = -1.0
## Seconds since the last hit.
var _quiet: float = 0.0
var _refresh_left: float = 0.0
var _reaction: String = ""
var _reaction_left: float = 0.0
var _numbers: Array[Label] = []
var _number_left: PackedFloat32Array = PackedFloat32Array()
var _number_x: PackedFloat32Array = PackedFloat32Array()
var _number_amount: PackedFloat32Array = PackedFloat32Array()
## 1 for a label whose number is not written yet, and whether that write is queued.
var _number_new: PackedByteArray = PackedByteArray()
var _numbers_queued: bool = false
var _next_number: int = 0

@onready var _dps_label: Label = %Dps
@onready var _status_label: Label = %Status
@onready var _number_template: Label = %Number


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	_buckets.resize(DPS_BUCKETS)
	_buckets.fill(0.0)
	_bucket_left = DPS_WINDOW / float(DPS_BUCKETS)
	_number_template.visible = false
	for i in NUMBER_COUNT:
		var label := _number_template.duplicate() as Label
		label.unique_name_in_owner = false
		label.name = "Number%d" % (i + 1)
		add_child(label)
		_numbers.append(label)
	_number_left.resize(NUMBER_COUNT)
	_number_left.fill(0.0)
	_number_x.resize(NUMBER_COUNT)
	_number_x.fill(0.0)
	_number_amount.resize(NUMBER_COUNT)
	_number_amount.fill(0.0)
	_number_new.resize(NUMBER_COUNT)
	_number_new.fill(0)
	# Combat registers the actor with its full health once it is in the tree (the Hurtbox).
	_health = actor.health.max_health if actor.health != null else -1.0
	actor.damaged.connect(_on_damaged)
	if actor.events != null:
		actor.events.reaction_triggered.connect(_on_reaction_triggered)
	_show()


## Move time on by `delta` seconds: the damage window, the numbers and the labels.
func step(delta: float) -> void:
	_take_health()
	_bucket_left -= delta
	while _bucket_left <= 0.0:
		_bucket_left += DPS_WINDOW / float(DPS_BUCKETS)
		_bucket = (_bucket + 1) % DPS_BUCKETS
		_buckets[_bucket] = 0
	if _streak >= 0.0:
		_streak += delta
		_quiet += delta
		if _quiet >= DPS_WINDOW:
			_streak = -1.0
	_reaction_left = maxf(_reaction_left - delta, 0.0)
	for i in NUMBER_COUNT:
		if _number_left[i] <= 0.0:
			continue
		_number_left[i] = maxf(_number_left[i] - delta, 0.0)
		_place_number(i)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_show()


## Damage per second over the last DPS_WINDOW seconds (see the top).
func dps() -> float:
	if _streak < 0.0:
		return 0.0
	var sum: float = 0.0
	for amount: float in _buckets:
		sum += amount
	return sum / clampf(_streak, 1.0, DPS_WINDOW)


## The status line: the statuses on the dummy and the last reaction, or "" for none.
func status_text() -> String:
	var words: PackedStringArray = PackedStringArray()
	if actor.combat != null:
		for status: StringName in STATUSES:
			if actor.combat.has_status(actor, status):
				words.append(String(status).capitalize())
	if _reaction_left > 0.0:
		words.append(_reaction + "!")
	return " ".join(words)


## The texts of the damage numbers now showing (tests read them).
func shown_numbers() -> PackedStringArray:
	var shown: PackedStringArray = PackedStringArray()
	for i in NUMBER_COUNT:
		if _number_left[i] > 0.0:
			shown.append(_number_text(_number_amount[i]))
	return shown


## A damage number's text: to a tenth (an atom's speck shows 0.3, a bolt 5).
static func _number_text(amount: float) -> String:
	return ("%.1f" % amount).trim_suffix(".0")


## Number `i`'s label where its age puts it: rising and fading, hidden once it is gone.
func _place_number(i: int) -> void:
	var label: Label = _numbers[i]
	var age: float = 1.0 - _number_left[i] / NUMBER_TIME
	label.position = NUMBER_START + Vector2(_number_x[i], -NUMBER_RISE * age)
	label.modulate.a = 1.0 - age * age
	label.visible = _number_left[i] > 0.0


## The numbers hit since the last write, each written to its label once (a label reused within
## the frame shows its last hit, as it would have). Queued by `_on_damaged`, run before drawing.
func _write_new_numbers() -> void:
	_numbers_queued = false
	for i in NUMBER_COUNT:
		if _number_new[i] == 0:
			continue
		_number_new[i] = 0
		_numbers[i].text = _number_text(_number_amount[i])
		_place_number(i)


func _show() -> void:
	_dps_label.text = "DPS %d" % roundi(dps())
	_status_label.text = status_text()


## Count what Combat took off since the last look.
func _take_health() -> void:
	if actor.combat == null:
		return
	var health: float = actor.combat.health_of(actor)
	if health < 0.0:
		return
	var taken: float = _health - health if _health >= 0.0 else 0.0
	_health = health
	if taken <= 0.0:
		return
	total_damage += taken
	_buckets[_bucket] += taken
	if _streak < 0.0:
		_streak = 0.0
	_quiet = 0.0


func _on_damaged(_by: int, amount: float) -> void:
	if amount <= 0.0:
		return
	_number_left[_next_number] = NUMBER_TIME
	_number_x[_next_number] = NUMBER_SPREAD * float(_next_number % 3 - 1)
	_number_amount[_next_number] = amount
	_number_new[_next_number] = 1
	_next_number = (_next_number + 1) % NUMBER_COUNT
	if not _numbers_queued:
		_numbers_queued = true
		_write_new_numbers.call_deferred()


func _on_reaction_triggered(_caster: int, reaction_id: StringName, position: Vector2, _shot: int) -> void:
	var body: Vector2 = actor.global_position + actor.body_offset
	if position.distance_to(body) > REACTION_REACH:
		return
	_reaction = String(reaction_id).capitalize()
	_reaction_left = REACTION_TIME
	_show()

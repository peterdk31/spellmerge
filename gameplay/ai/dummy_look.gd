class_name DummyLook
extends ActorLook
## What the sandbox's training dummy shows (staffs B7, docs/milestones/M2-staffs.md, "The
## sandbox"; a look since actors G6): the training dummy (content/enemies/training_dummy) is an
## actor with Health (its data's billion), a Hurtbox, no controller and no Mover, so it never
## moves (knockback, a swap or a pull leave it where it is) and no build takes it down; "Reset
## dummies" in the sandbox page puts a fresh one there. Enemies never target it: it is on the
## enemies' team (the actor's `idle_team`).
##
## What it shows, all about its actor, with the scene's labels `%Dps`, `%Status` and `%Number`:
## - **Damage numbers:** each `damage_dealt` on the actor rises from its head for NUMBER_TIME
##   seconds, from a pool of NUMBER_COUNT labels (the oldest is reused when all are up).
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
var total_damage: int = 0

var _buckets: PackedInt32Array = PackedInt32Array()
var _bucket: int = 0
## Health in Combat at the last step (-1 for not known yet).
var _health: int = -1
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
var _next_number: int = 0

@onready var _dps_label: Label = %Dps
@onready var _status_label: Label = %Status
@onready var _number_template: Label = %Number


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	_buckets.resize(DPS_BUCKETS)
	_buckets.fill(0)
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
	# Combat registers the actor with its full health once it is in the tree (the Hurtbox).
	_health = actor.health.max_health if actor.health != null else -1
	if actor.events != null:
		actor.events.damage_dealt.connect(_on_damage_dealt)
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
		var label: Label = _numbers[i]
		var age: float = 1.0 - _number_left[i] / NUMBER_TIME
		label.position = NUMBER_START + Vector2(_number_x[i], -NUMBER_RISE * age)
		label.modulate.a = 1.0 - age * age
		label.visible = _number_left[i] > 0.0
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_show()


## Damage per second over the last DPS_WINDOW seconds (see the top).
func dps() -> float:
	if _streak < 0.0:
		return 0.0
	var sum: int = 0
	for amount: int in _buckets:
		sum += amount
	return float(sum) / clampf(_streak, 1.0, DPS_WINDOW)


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
			shown.append(_numbers[i].text)
	return shown


func _show() -> void:
	_dps_label.text = "DPS %d" % roundi(dps())
	_status_label.text = status_text()


## Count what Combat took off since the last look.
func _take_health() -> void:
	if actor.combat == null:
		return
	var health: int = actor.combat.health_of(actor)
	if health < 0:
		return
	var taken: int = _health - health if _health >= 0 else 0
	_health = health
	if taken <= 0:
		return
	total_damage += taken
	_buckets[_bucket] += taken
	if _streak < 0.0:
		_streak = 0.0
	_quiet = 0.0


func _on_damage_dealt(_caster: int, target: Node, amount: int, _position: Vector2) -> void:
	if target != actor or amount <= 0:
		return
	var label: Label = _numbers[_next_number]
	_number_left[_next_number] = NUMBER_TIME
	_number_x[_next_number] = NUMBER_SPREAD * float(_next_number % 3 - 1)
	label.text = str(amount)
	label.position = NUMBER_START + Vector2(_number_x[_next_number], 0.0)
	label.modulate.a = 1.0
	label.visible = true
	_next_number = (_next_number + 1) % NUMBER_COUNT


func _on_reaction_triggered(_caster: int, reaction_id: StringName, position: Vector2) -> void:
	var body: Vector2 = actor.global_position + actor.body_offset
	if position.distance_to(body) > REACTION_REACH:
		return
	_reaction = String(reaction_id).capitalize()
	_reaction_left = REACTION_TIME
	_show()

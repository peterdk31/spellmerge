extends Node2D
## The training dummy of the sandbox (staffs B7, docs/milestones/M2-staffs.md, "The sandbox"):
## a target that never dies and never moves, and shows what each hit did. Flow puts it at the
## sandbox room's first dummy spawn and sets `data` before adding it, as for any enemy.
##
## Combat holds its health like any enemy's, only far more of it (HEALTH), so no build takes it
## down; "Reset dummies" in the sandbox page puts a fresh one there. It never moves: it is a plain
## node, so nothing adds Combat's knockback to it, and a swap (`target_move_requested`) or a pull
## leaves it where it is. Enemies never target it (they chase the `players` group).
##
## What it shows, all from events about itself:
## - **Damage numbers:** each `damage_dealt` on it rises from its head for NUMBER_TIME seconds,
##   from a pool of NUMBER_COUNT labels (the oldest is reused when all are up).
## - **Damage per second** over the last DPS_WINDOW seconds, in DPS_BUCKETS buckets, read from
##   the drop of its health in Combat each step, so burn ticks (which send no `damage_dealt` on a
##   target that lives) count too; while a streak is younger than the window it is divided by the streak's age (at least one second),
##   so a short burst reads true. A streak ends when no damage came for a whole window.
## - **Statuses** on it (Combat's `has_status`), and the last **reaction** for REACTION_TIME
##   seconds (`reaction_triggered` at its body).
## The labels change every REFRESH seconds at most; nothing is allocated per frame.
##
## All timing runs in step(delta), so tests drive it with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

## Health in Combat: more than any build deals in a session.
const HEALTH: int = 1000000000
## The hurt circle, and where it sits above the feet (the straw body).
const HURT_RADIUS: float = 11.0
const HURT_OFFSET: Vector2 = Vector2(0.0, -14.0)
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

## The enemy data flow hands every enemy (kept for the id; the numbers here are constants).
var data: EnemyBase = null
## The event bus and Combat. Only tests set these, before adding the node; otherwise the
## "Events" and "Combat" autoloads are used.
var events: EventsScript = null
var combat: CombatScript = null

## Damage taken since this dummy stood up.
var total_damage: int = 0

var _buckets: PackedInt32Array = PackedInt32Array()
var _bucket: int = 0
## Health in Combat at the last step.
var _health: int = HEALTH
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


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
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
	if combat != null:
		combat.register_enemy(self, HEALTH, HURT_RADIUS, 0, HURT_OFFSET)
	if events != null:
		events.damage_dealt.connect(_on_damage_dealt)
		events.reaction_triggered.connect(_on_reaction_triggered)
	_show()


func _exit_tree() -> void:
	if events != null:
		if events.damage_dealt.is_connected(_on_damage_dealt):
			events.damage_dealt.disconnect(_on_damage_dealt)
		if events.reaction_triggered.is_connected(_on_reaction_triggered):
			events.reaction_triggered.disconnect(_on_reaction_triggered)
	if combat != null and is_instance_valid(combat):
		combat.unregister_enemy(self)


func _process(delta: float) -> void:
	step(delta)


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
	if combat != null:
		for status: StringName in STATUSES:
			if combat.has_status(self, status):
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
	if combat == null:
		return
	var health: int = combat.get_health(self)
	if health < 0:
		return
	var taken: int = _health - health
	_health = health
	if taken <= 0:
		return
	total_damage += taken
	_buckets[_bucket] += taken
	if _streak < 0.0:
		_streak = 0.0
	_quiet = 0.0


func _on_damage_dealt(_player: int, target: Node, amount: int, _position: Vector2) -> void:
	if target != self or amount <= 0:
		return
	var label: Label = _numbers[_next_number]
	_number_left[_next_number] = NUMBER_TIME
	_number_x[_next_number] = NUMBER_SPREAD * float(_next_number % 3 - 1)
	label.text = str(amount)
	label.position = NUMBER_START + Vector2(_number_x[_next_number], 0.0)
	label.modulate.a = 1.0
	label.visible = true
	_next_number = (_next_number + 1) % NUMBER_COUNT


func _on_reaction_triggered(_player: int, reaction_id: StringName, position: Vector2) -> void:
	var body: Vector2 = (global_position if is_inside_tree() else self.position) + HURT_OFFSET
	if position.distance_to(body) > REACTION_REACH:
		return
	_reaction = String(reaction_id).capitalize()
	_reaction_left = REACTION_TIME
	_show()

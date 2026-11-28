class_name HitTable
extends RefCounted
## The hits the projectile manager sent since its last step began (perf plan, change 3, H1;
## docs/milestones/perf-plan.md): one row for each hit on a body, in the order they were sent. A
## row is a hit pass's merged hit (`HitBatch`: a caster's spell on one body, `count` hits) or one
## ray's or sweep's hit (`count` 1, no shot), with its first shot's look (carrier card, body, core,
## look bits).
##
## The manager writes a row (`write`), sends its `projectile_impact` and `projectile_hit` as before,
## then hands it to the table's applier (`apply`): Combat's `apply_hit_row`, so Combat applies every
## hit the manager sends in one function, in the order it is sent, and after the hit's other
## listeners (Spells' first, as today). While a row's `projectile_hit` goes out, `sending` names it,
## so the applier's own listener on that event leaves it to `apply` (a hit sent by hand, a test's,
## is heard there alone).
##
## Sized once: `FIRST_ROWS` rows to start, doubled when a tick sends more, never shrunk (no
## per-tick allocation once the crowd has been met). Not state (core/sim/README.md): rows are read
## only while they are sent; the manager's DERIVED `hit_table`.

const FIRST_ROWS: int = 256
## Not state: the rows are read only while they are sent, and the applier is set up by Combat.
const DERIVED: Array[StringName] = [&"rows", &"caster", &"target", &"at", &"heading", &"tag", &"shot", &"count", &"card", &"body", &"core", &"look", &"sending", &"applier"]

## The rows written since the last `empty`.
var rows: int = 0
## Each row's caster, body hit, point, heading, spell tag, shot (the manager's slot; -1 for a ray's
## hit, or a slot taken since), hits it stands for, and its first shot's look.
var caster: PackedInt32Array = PackedInt32Array()
var target: Array[Node] = []
var at: PackedVector2Array = PackedVector2Array()
var heading: PackedVector2Array = PackedVector2Array()
var tag: PackedInt64Array = PackedInt64Array()
var shot: PackedInt32Array = PackedInt32Array()
var count: PackedInt32Array = PackedInt32Array()
var card: Array[StringName] = []
var body: PackedInt32Array = PackedInt32Array()
var core: PackedColorArray = PackedColorArray()
var look: PackedInt32Array = PackedInt32Array()
## The row whose `projectile_hit` is being sent, -1 when none (a nested send keeps the outer one's
## and gives it back).
var sending: int = -1
## Called with (table, row) once a row's `projectile_hit` has been heard (`apply`); none by default.
var applier: Callable = Callable()


func _init() -> void:
	_fit(FIRST_ROWS)


## Every row forgotten (the manager's step begins).
func empty() -> void:
	rows = 0


## A new row, returned: `count` hits of `who`'s spell `spell` on `node` at `point` going `way`, by
## the shot in `slot` (-1 for none), with that shot's look.
func write(who: int, node: Node, point: Vector2, way: Vector2, spell: int, slot: int, hits: int, carrier_card: StringName, kind: int, colour: Color, look_bits: int) -> int:
	if rows == caster.size():
		_fit(rows * 2)
	var row: int = rows
	rows += 1
	caster[row] = who
	target[row] = node
	at[row] = point
	heading[row] = way
	tag[row] = spell
	shot[row] = slot
	count[row] = hits
	card[row] = carrier_card
	body[row] = kind
	core[row] = colour
	look[row] = look_bits
	return row


## Whether `listener`'s object is the table's applier, so its `projectile_hit` listener leaves the
## row being sent to `apply`.
func applied_by(listener: Object) -> bool:
	return sending >= 0 and applier.is_valid() and applier.get_object() == listener


## The row `row` handed to the applier, if it has one.
func apply(row: int) -> void:
	if applier.is_valid():
		applier.call(self, row)


func _fit(size: int) -> void:
	caster.resize(size)
	target.resize(size)
	at.resize(size)
	heading.resize(size)
	tag.resize(size)
	shot.resize(size)
	count.resize(size)
	card.resize(size)
	body.resize(size)
	core.resize(size)
	look.resize(size)

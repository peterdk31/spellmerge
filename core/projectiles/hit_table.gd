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
## The table also keeps what the hits looked like, for the drawing (perf plan H2): an impact on no
## body (a shot's end on a wall, a ray's spark at a wall it met: `ROW_WALL`, never applied), and the
## damage and deaths Combat deals (`ROW_DAMAGE`, `ROW_DEATH`, `write_damage`, `write_death`), each a
## row in the order sent, between the hits that dealt them. A row says what its look needs from the
## moment it was sent (the body's instance id, actor id and own colour; the impact's look tag), so
## it is read after the tick, when its body may be gone. While a row's own events go out, `told`
## names it, so a reader that also listens to those events (for the ones sent by hand) leaves them.
##
## Who keeps the rows: by default they are forgotten when a tick begins (`begin_tick`, the
## manager's step, the tick's first). A reader (Feel, `hold`) keeps them over ticks instead, until
## it has read them once a drawn frame (`read_done`): every tick's rows, when a frame runs several.
## `tick` stamps each row with the ticks begun so far, so the reader tells one tick's rows from the
## next. At most MOST_HELD rows wait for a reader that never reads (a frame that never comes): past
## that, a tick forgets them as with none.
##
## Sized once: `FIRST_ROWS` rows to start, doubled when a tick sends more, never shrunk (no
## per-tick allocation once the crowd has been met). Not state (core/sim/README.md): the game reads
## rows only while they are sent, the drawing after; the manager's DERIVED `hit_table`.

const FIRST_ROWS: int = 256
## The most rows kept for a reader that has not read them (see the class doc).
const MOST_HELD: int = 65536
## What a row is: a hit on a body (applied), an impact on no body, a body's damage, a death.
const ROW_HIT: int = 0
const ROW_WALL: int = 1
const ROW_DAMAGE: int = 2
const ROW_DEATH: int = 3
## Not state: the rows are read only while they are sent (and by the drawing), and the applier is
## set up by Combat.
const DERIVED: Array[StringName] = [&"rows", &"kind", &"tick", &"caster", &"target", &"target_id", &"actor", &"at", &"heading", &"tag", &"look_tag", &"shot", &"count", &"amount", &"hit_kind", &"card", &"body", &"core", &"look", &"colour", &"sending", &"told", &"applier", &"ticks", &"held"]

## The rows written since the last `empty`.
var rows: int = 0
## Each row's kind (ROW_*) and the tick it was sent in (`ticks` then). A column a row's kind does
## not write holds an older row's value: read only those of its kind.
var kind: PackedByteArray = PackedByteArray()
var tick: PackedInt32Array = PackedInt32Array()
## Each row's caster (the attacker of a damage, the killer of a death), body (null for none; read
## only while it is sent, as it may be freed after), that body's instance id (0 for none) and actor
## id (Actors.NONE for no actor), point, heading, spell tag, the tag its impact is drawn with (the
## manager's `impact_tag` while it is sent: a ray's is 0), shot (the manager's slot; -1 for a ray's
## hit, or a slot taken since), hits it stands for, damage dealt, hit kind (Combat's `KIND_*`, a
## damage's), and its look: carrier card, shot body, core colour and look bits (a death's: its
## killing shot's); and a damage's or a death's body's own colour (its data's `hit_color`).
var caster: PackedInt32Array = PackedInt32Array()
var target: Array[Node] = []
var target_id: PackedInt64Array = PackedInt64Array()
var actor: PackedInt32Array = PackedInt32Array()
var at: PackedVector2Array = PackedVector2Array()
var heading: PackedVector2Array = PackedVector2Array()
var tag: PackedInt64Array = PackedInt64Array()
var look_tag: PackedInt64Array = PackedInt64Array()
var shot: PackedInt32Array = PackedInt32Array()
var count: PackedInt32Array = PackedInt32Array()
var amount: PackedFloat32Array = PackedFloat32Array()
var hit_kind: Array[StringName] = []
var card: Array[StringName] = []
var body: PackedInt32Array = PackedInt32Array()
var core: PackedColorArray = PackedColorArray()
var look: PackedInt32Array = PackedInt32Array()
var colour: PackedColorArray = PackedColorArray()
## The row whose own events are being sent (its impact, its damage's, its death's), -1 when none (a
## nested one gives the outer back): a reader that listens to them for hand-sent ones leaves these
## to the rows.
var told: int = -1
## The ticks begun (`begin_tick`), and whether a reader keeps the rows until it has read them.
var ticks: int = 0
var held: bool = false
## The row whose `projectile_hit` is being sent, -1 when none (a nested send keeps the outer one's
## and gives it back).
var sending: int = -1
## Called with (table, row) once a row's `projectile_hit` has been heard (`apply`); none by default.
var applier: Callable = Callable()


func _init() -> void:
	_fit(FIRST_ROWS)


## Every row forgotten (a reader has read them, or a test's).
func empty() -> void:
	rows = 0


## A tick begins (the manager's step, the tick's first): the rows are forgotten unless a reader
## keeps them (`held`, up to MOST_HELD).
func begin_tick() -> void:
	ticks += 1
	if not held or rows >= MOST_HELD:
		rows = 0


## A reader keeps the rows (`on`) until it has read them (`read_done`), or no longer.
func hold(on: bool) -> void:
	held = on


## The reader has read every row: they are forgotten.
func read_done() -> void:
	rows = 0


## A new row, returned: `count` hits of `who`'s spell `spell` on `node` at `point` going `way`, by
## the shot in `slot` (-1 for none), with that shot's look; its impact drawn with `shown_tag` (the
## manager's `impact_tag` as it sends it). `node` null is an impact on no body (ROW_WALL).
func write(who: int, node: Node, point: Vector2, way: Vector2, spell: int, slot: int, hits: int, carrier_card: StringName, shot_body: int, colour: Color, look_bits: int, shown_tag: int = -1) -> int:
	var row: int = _next(ROW_HIT if node != null else ROW_WALL, who, node, point)
	heading[row] = way
	tag[row] = spell
	look_tag[row] = spell if shown_tag == -1 else shown_tag
	shot[row] = slot
	count[row] = hits
	card[row] = carrier_card
	body[row] = shot_body
	core[row] = colour
	look[row] = look_bits
	return row


## A damage row, returned: `by` dealt `dealt` to `node` (actor `id`, its own colour `own`) at
## `point`, a hit of kind `what` by the shot `slot` (-1 for none) of the carrier card `carrier_card`.
func write_damage(by: int, node: Node, id: int, point: Vector2, dealt: float, what: StringName, slot: int, carrier_card: StringName, own: Color) -> int:
	var row: int = _next(ROW_DAMAGE, by, node, point)
	actor[row] = id
	amount[row] = dealt
	hit_kind[row] = what
	shot[row] = slot
	card[row] = carrier_card
	colour[row] = own
	return row


## A death row, returned: `killer` killed `node` (its own colour `own`) at `point`, by the shot
## `slot` (-1 for none) whose look was `shot_core` and `look_bits` (white and none for no shot).
func write_death(killer: int, node: Node, point: Vector2, slot: int, shot_core: Color, look_bits: int, own: Color) -> int:
	var row: int = _next(ROW_DEATH, killer, node, point)
	shot[row] = slot
	core[row] = shot_core
	look[row] = look_bits
	colour[row] = own
	return row


## The next row, of kind `what`, by `who` on `node` at `point`; its other columns are the writer's.
func _next(what: int, who: int, node: Node, point: Vector2) -> int:
	if rows == caster.size():
		_fit(rows * 2)
	var row: int = rows
	rows += 1
	kind[row] = what
	tick[row] = ticks
	caster[row] = who
	target[row] = node
	target_id[row] = node.get_instance_id() if node != null else 0
	at[row] = point
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
	kind.resize(size)
	tick.resize(size)
	caster.resize(size)
	target.resize(size)
	target_id.resize(size)
	actor.resize(size)
	look_tag.resize(size)
	amount.resize(size)
	hit_kind.resize(size)
	colour.resize(size)
	at.resize(size)
	heading.resize(size)
	tag.resize(size)
	shot.resize(size)
	count.resize(size)
	card.resize(size)
	body.resize(size)
	core.resize(size)
	look.resize(size)

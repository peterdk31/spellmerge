extends RefCounted
## Still motes: the motes a still carrier's shots give off all the time while they stand (the owner,
## 2026-11-09: "use motes for everything you can"; a wall's stream rising off its seam, a pool's
## motes rising off its mire). A carrier card names them (`FormBase.look_motes`, `look_mote_rate`,
## `look_motes_from`; Spells hands them out as its `CardLook`, `Spells.still_mote_cards`), and they
## are given off from where its shots are drawn: the projectile manager hands out the rows of the
## card's body batches each frame (`watch_rows`, `rows_drawn`), so nothing is asked of a shot and no
## area calls another to find one. Each row is a shot (a piece of a solid one): its place, its quad's
## size and turn (a wall's row runs along its +x), its colours and look, and its still clock (the
## code beside its kind, `ProjectileManager.still_code`), so its motes thin while it comes and as it
## goes. Each is a one-mote cue part (`Motes.throw_part`) of the card's kind, or now and then of its
## infusions' own kinds (fire's embers, frost's flecks), in the shot's ramp, its infusions in turn
## (`Motes.set_infusions`). View only: it keeps nothing the simulation reads, and its dice are its own.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")

## Where a card's motes leave from (`FormBase.look_motes_from`): the oval of its hit size, seen at a
## slant (as `pool.gdshader` draws it), or its piece of the row along the floor (`stone.gdshader`'s
## seam).
const FROM_AREA: int = 0
const FROM_ROW: int = 1
## As the shaders read a quad: its hit size's part of the quad (`size x HIT`), the oval's half sizes
## (times that), a piece's half span of its row and its seam below its middle (times that).
const HIT: float = 0.15
const OVAL: Vector2 = Vector2(1.3, 0.75)
const ROW_SPAN: float = 1.25
const ROW_FOOT: float = 0.6
## Seconds its motes take to come in full once it is placed, and the seconds of its end they thin
## over (the shaders' OPEN and FADE).
const OPEN: float = 0.3
const FADE: float = 0.8
## The share of its motes that are its infusions' own kinds, when it has infusions with kinds.
const OWN_SHARE: float = 0.3
## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1

## Each watched batch's card look: {batch: CardLook}.
var _looks: Dictionary = {}
## The infusions' own kinds of a look's infusion layers, kept: {layers: PackedInt32Array}.
var _own_kinds: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The manager's clock when the rows were last handed out, and the seconds since the one before.
var _seen: float = -1.0
var _frame: float = 0.0
## How many motes it gave off (for tests and the benchmark).
var given: int = 0


func _init() -> void:
	_rng.seed = 7


## Watch the body batches of every still card that gives off motes (`spells`: Spells, with
## `still_mote_cards` and `look_of`; `projectiles` the manager that draws them). Again when the
## manager numbers new bodies (its batches grow): a card's body is numbered the same each time.
func attach(projectiles: ProjectilesScript, spells: Object) -> void:
	_looks.clear()
	if projectiles == null or spells == null or not spells.has_method(&"still_mote_cards"):
		return
	for form: StringName in spells.call(&"still_mote_cards") as Array[StringName]:
		var look := spells.call(&"look_of", form, Carrier.LOOK_STILL) as CardLook
		if look == null or look.shader == null or look.motes == &"" or look.mote_rate <= 0.0:
			continue
		var body: int = projectiles.register_body(look.shader, ProjectilesScript.MESH_QUAD)
		for enemy: bool in [false, true]:
			var batch: int = ProjectilesScript.body_batch(body, enemy)
			_looks[batch] = look
			projectiles.watch_rows(batch, true)


## True while it watches batch `batch`.
func watches(batch: int) -> bool:
	return _looks.has(batch)


## The rows of batch `batch` were drawn (`rows_drawn`) at the manager's clock `now`: each of its
## first `count` shots gives off its share of its card's motes into `pool` (null: none now).
func give_off(batch: int, rows: PackedFloat32Array, count: int, now: float, pool: MotesScript) -> void:
	if now != _seen:
		_frame = clampf(now - _seen, 0.0, LONGEST_FRAME) if _seen >= 0.0 else 0.0
		_seen = now
	var look: CardLook = _looks.get(batch) as CardLook
	if look == null or pool == null or _frame <= 0.0:
		return
	var kind: int = pool.kind_index(look.motes)
	if kind < 0:
		return
	var stride: int = ProjectilesScript.DRAW_STRIDE
	for n in mini(count, rows.size() / stride):
		var i: int = n * stride
		var many: int = floori(look.mote_rate * _frame * strength(rows[i + 15]) + _rng.randf())
		if many <= 0:
			continue
		var at := Vector2(rows[i + 3], rows[i + 7])
		var x_axis := Vector2(rows[i], rows[i + 4])
		var size: float = x_axis.length()
		var across: Vector2 = x_axis / size if size > 0.0 else Vector2.RIGHT
		var red: int = roundi(rows[i + 8] * 255.0)
		var bits: int = roundi(rows[i + 9] * 255.0) | (roundi(rows[i + 10] * 255.0) << 8) | (roundi(rows[i + 11] * 255.0) << 16)
		var source: int = MotesScript.spell_source(red % 4, bits)
		var core := Color(rows[i + 12], rows[i + 13], rows[i + 14])
		var own: PackedInt32Array = _own_kinds_of(pool, bits)
		var reach: float = size * HIT
		for m in many:
			var from: Vector2 = at + _point(look.motes_from, reach, across)
			var k: int = kind
			if not own.is_empty() and _rng.randf() < OWN_SHARE:
				k = own[_rng.randi() % own.size()]
			pool.throw_part(k, from, Vector2.UP, source, core, 1, 0.0, -1.0, 1.0, false, true, Vector2.ZERO, 1.0, bits)
			given += 1


## How strongly a shot whose row's custom alpha is `alpha` gives off now (0 to 1): coming in over
## its first OPEN seconds, thinning over the last FADE of its end (its still clock).
static func strength(alpha: float) -> float:
	var coded: float = (1.0 - alpha) * ProjectilesScript.KIND_STEPS
	var code: float = coded - roundf(coded)
	var since: float = ProjectilesScript.STILL_START
	var left: float = ProjectilesScript.STILL_END
	if code > 0.01:
		since = clampf((code - ProjectilesScript.TRACE_FROM) / ProjectilesScript.TRACE_SPAN, 0.0, 1.0) * ProjectilesScript.STILL_START
	elif code < -0.01:
		left = (1.0 - clampf((-code - ProjectilesScript.TRACE_FROM) / ProjectilesScript.TRACE_SPAN, 0.0, 1.0)) * ProjectilesScript.STILL_END
	var fade: float = clampf((1.0 - left / ProjectilesScript.STILL_END) / FADE, 0.0, 1.0)
	return minf(since / OPEN, 1.0) * (1.0 - fade)


## A point a mote leaves from, round a shot of hit size `reach` whose row runs along `across`.
func _point(from: int, reach: float, across: Vector2) -> Vector2:
	if from == FROM_ROW:
		return Vector2(0.0, floorf(reach * ROW_FOOT + 0.5)) + across * _rng.randf_range(-1.0, 1.0) * reach * ROW_SPAN
	var a: float = _rng.randf() * TAU
	return Vector2(cos(a), sin(a)) * OVAL * reach * sqrt(_rng.randf()) * 0.9


## The kinds of the infusions on a look `bits` (those that name their infusion's layer), kept.
func _own_kinds_of(pool: MotesScript, bits: int) -> PackedInt32Array:
	var layers: int = pool.infusion_layers(bits)
	var known: Variant = _own_kinds.get(layers)
	if known != null:
		return known
	var found := PackedInt32Array()
	for layer in range(1, MotesScript.LOOK_LAYERS + 1):
		if (layers >> (layer - 1)) & 1 == 1:
			for k in pool.kinds_named_by_layer(layer):
				if not found.has(k):
					found.append(k)
	_own_kinds[layers] = found
	return found

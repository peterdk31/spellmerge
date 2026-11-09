extends RefCounted
## Still motes: the motes a still carrier's shots give off all the time while they stand (the owner,
## 2026-11-09: "use motes for everything you can"; a wall's stream rising off its seam, a pool's
## motes rising off its mire, a rune's drips and the motes rising off its ring once armed). A carrier
## card lists them, one `StillMoteSource` a stream (`FormBase.look_motes`: kind, rate, where from in
## its `look_shape`, how high, from when, how far apart), coming and going by `look_open` and
## `look_fade`; Spells hands them out as its `CardLook` (`SpellRuntime.still_mote_cards`). They are
## given off from where its shots are drawn: the projectile manager hands out a view of the card
## body's still shots each frame it draws them (`watch_body`, `still_shots_drawn`, `StillShotView`:
## place, the way its row runs, hit size as drawn, colours, still clock), so nothing is asked of a
## shot, no area calls another to find one, and no row of the manager's is read here. Each mote is a
## one-mote cue part (`Motes.throw_part`) of the source's kind, or now and then of its infusions' own
## kinds (fire's embers, frost's flecks), in the shot's ramp, its infusions in turn
## (`Motes.set_infusions`). Where a shot or a beam strikes one of its shots (`struck`), its streams
## part there for a moment and a few motes are knocked out (the owner's pick for the wall: "a hit
## bursts sparks out where it lands and parts the stream for a moment"). View only: it keeps nothing
## the simulation reads, and its dice are its own.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")

## The share of its motes that are its infusions' own kinds, when it has infusions with kinds.
const OWN_SHARE: float = 0.3
## How far into its oval a mote leaves from, at most (so none leaves from its very rim).
const AREA_INSIDE: float = 0.9
## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1
## A strike parts the streams within PART_REACH pixels of it for PART_SECONDS, and knocks out
## KNOCKED motes of the struck shot's first stream, flying out to KNOCK_REACH pixels.
const PART_REACH: float = 5.0
const PART_SECONDS: float = 0.5
const KNOCKED: int = 6
const KNOCK_REACH: float = 10.0
## The strikes remembered at once (the oldest is forgotten first), and so the most a frame looks
## for: a storm of shots on a wall finds the still shots it struck MOST_STRIKES times a frame at most.
const MOST_STRIKES: int = 16

## Each watched card body's look: {body: CardLook}.
var _looks: Dictionary = {}
## The last view of each watched batch (the manager's, refilled each frame it draws): where its shots
## were last drawn, for a strike to find the shot it struck. {body * 2 + enemy: StillShotView}.
var _views: Dictionary = {}
## The infusions' own kinds of a look's infusion layers, kept: {layers: PackedInt32Array}.
var _own_kinds: Dictionary = {}
## Recent strikes: where, and the clock when (a ring of MOST_STRIKES).
var _strike_at: PackedVector2Array = PackedVector2Array()
var _strike_when: PackedFloat32Array = PackedFloat32Array()
var _strike_next: int = 0
## Strikes looked for this frame, and the manager's clock it was counted at.
var _strikes_looked: int = 0
var _strikes_at: float = -1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The manager's clock when shots were last handed out, and the seconds since the one before.
var _seen: float = -1.0
var _frame: float = 0.0
## How many motes it gave off, and how many a strike held back (for tests and the benchmark).
var given: int = 0
var parted: int = 0


func _init() -> void:
	_rng.seed = 7
	_strike_at.resize(MOST_STRIKES)
	_strike_when.resize(MOST_STRIKES)
	_strike_when.fill(-INF)


## Watch the body of every still card that gives off motes (`spells` names them and their looks;
## `projectiles` the manager that numbered and draws them). Again when the manager numbers new bodies
## (its batches grow): a card's body keeps its number. A card whose body is not numbered yet is
## skipped until then.
func attach(projectiles: ProjectilesScript, spells: SpellRuntime) -> void:
	_looks.clear()
	_views.clear()
	if projectiles == null or spells == null:
		return
	for form: StringName in spells.still_mote_cards():
		var look: CardLook = spells.look_of(form, Carrier.LOOK_STILL)
		if look.shader == null or look.motes.is_empty():
			continue
		var body: int = projectiles.body_of(look.shader, ProjectilesScript.MESH_QUAD)
		if body == 0:
			continue
		_looks[body] = look
		projectiles.watch_body(body, true)


## True while it watches card body `body`.
func watches(body: int) -> bool:
	return _looks.has(body)


## A watched body's still shots were drawn (`view`, `still_shots_drawn`): each of them gives off its
## share of each of its card's streams into `pool` (null: none now).
func give_off(view: StillShotView, pool: MotesScript) -> void:
	_views[view.body * 2 + (1 if view.enemy else 0)] = view
	if view.time != _seen:
		_frame = clampf(view.time - _seen, 0.0, LONGEST_FRAME) if _seen >= 0.0 else 0.0
		_seen = view.time
	var look: CardLook = _looks.get(view.body) as CardLook
	if look == null or pool == null or _frame <= 0.0:
		return
	for source: StillMoteSource in look.motes:
		var kind: int = pool.kind_index(source.kind)
		if kind >= 0:
			_give_off_source(view, look, source, kind, pool)


## One stream `source` (its kind `kind`) of every shot of `view`.
func _give_off_source(view: StillShotView, look: CardLook, source: StillMoteSource, kind: int, pool: MotesScript) -> void:
	for n in view.count:
		if source.stop > 0.0 and view.since[n] >= source.stop:
			continue
		var many: int = floori(source.rate * _frame * strength(view.since[n] - source.start, view.left[n], look.open, look.fade) + _rng.randf())
		if many <= 0:
			continue
		var bits: int = view.look[n]
		var ramp_source: int = MotesScript.spell_source(view.ramp[n], bits)
		var own: PackedInt32Array = _own_kinds_of(pool, bits)
		var reach: float = view.reach[n]
		var height: float = source.height * reach
		for m in many:
			var ground: Vector2 = view.at[n] + _point(source, look.shape, reach, view.at[n], view.across[n])
			if _parted(ground, view.time):
				parted += 1
				continue
			var k: int = kind
			if not own.is_empty() and _rng.randf() < OWN_SHARE:
				k = own[_rng.randi() % own.size()]
			pool.throw_part(k, ground - Vector2(0.0, height), Vector2.UP, ramp_source, view.core[n], 1, 0.0, -1.0, 1.0, false, true, Vector2.ZERO, 1.0, bits, height)
			given += 1


## A shot or a beam struck a wall at `at`, at the projectile manager's clock `now`: if it is one of
## the still shots drawn in the last frame (a wall made by a card), its streams part there for
## PART_SECONDS and KNOCKED motes of the shot's first stream are knocked out into `pool` (null:
## none), in its colours. A batch drawn longer ago than LONGEST_FRAME is not where its shots are any
## more (the manager hands out no view of a batch that draws none: a wall that ended).
func struck(at: Vector2, now: float, pool: MotesScript) -> void:
	if now != _strikes_at:
		_strikes_at = now
		_strikes_looked = 0
	if _views.is_empty() or _strikes_looked >= MOST_STRIKES:
		return
	_strikes_looked += 1
	for key: int in _views:
		var view: StillShotView = _views[key]
		var look: CardLook = _looks.get(view.body) as CardLook
		if look == null or now - view.time > LONGEST_FRAME:
			continue
		for n in view.count:
			var reach: float = view.reach[n]
			var span: float = maxf(look.shape.x, look.shape.y) * reach + PART_REACH
			if view.at[n].distance_squared_to(at) > span * span:
				continue
			_strike_at[_strike_next] = at
			_strike_when[_strike_next] = now
			_strike_next = (_strike_next + 1) % MOST_STRIKES
			var first: StillMoteSource = look.motes[0]
			var kind: int = pool.kind_index(first.kind) if pool != null else -1
			if kind >= 0:
				pool.throw_part(kind, at, Vector2.UP, MotesScript.spell_source(view.ramp[n], view.look[n]), view.core[n], KNOCKED, KNOCK_REACH, 360.0, 1.0, false, true, Vector2.ZERO, 1.0, view.look[n])
			return


## True while a strike parts the streams at `at` (the manager's clock `now`).
func _parted(at: Vector2, now: float) -> bool:
	for s in MOST_STRIKES:
		if now - _strike_when[s] < PART_SECONDS and _strike_at[s].distance_squared_to(at) < PART_REACH * PART_REACH:
			return true
	return false


## How strongly a stream gives off now (0 to 1), `since` seconds after it starts with `left`
## seconds of life left: coming in over its first `open` seconds, thinning over the last `fade`;
## nothing before it starts.
static func strength(since: float, left: float, open: float, fade: float) -> float:
	if since < 0.0:
		return 0.0
	var coming: float = minf(since / open, 1.0) if open > 0.0 else 1.0
	var going: float = clampf((ProjectilesScript.STILL_END - left) / fade, 0.0, 1.0) if fade > 0.0 else (1.0 if left <= 0.0 else 0.0)
	return coming * (1.0 - going)


## A point a mote of `source` leaves from, from the middle of a shot at `middle` of hit size `reach`
## (as drawn) whose row runs along `across`, in the card's look `shape`.
func _point(source: StillMoteSource, shape: Vector2, reach: float, middle: Vector2, across: Vector2) -> Vector2:
	match source.from:
		StillMoteSource.FROM_ROW:
			var along: float = _rng.randf_range(-1.0, 1.0) * reach * shape.x
			if source.spacing > 0.0:
				# On the world's grid along the row, so every piece's places line up.
				var w: float = middle.dot(across)
				along = roundf((w + along) / source.spacing) * source.spacing - w
			return Vector2(0.0, floorf(reach * shape.y + 0.5)) + across * along
		StillMoteSource.FROM_RIM:
			var a: float = _rng.randf() * TAU
			if source.spacing > 0.0:
				var steps: float = maxf(roundf(TAU * maxf(shape.x, shape.y) * reach / source.spacing), 1.0)
				a = roundf(a / TAU * steps) / steps * TAU
			return (Vector2(cos(a), sin(a)) * shape * reach).round()
		StillMoteSource.FROM_MIDDLE:
			return Vector2.ZERO
	var b: float = _rng.randf() * TAU
	return Vector2(cos(b), sin(b)) * shape * reach * sqrt(_rng.randf()) * AREA_INSIDE


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

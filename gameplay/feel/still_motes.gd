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
## The strikes held at once, waiting for the still shots and parting them (the oldest is let go
## first): a storm of shots on a wall costs MOST_STRIKES searches a frame at most.
const MOST_STRIKES: int = 16

## Each watched card body's look: {body: CardLook}.
var _looks: Dictionary = {}
## The infusions' own kinds of a look's infusion layers, kept: {layers: PackedInt32Array}.
var _own_kinds: Dictionary = {}
## Strikes waiting for the next drawing of the still shots (`struck`): where, the clock when, how many.
var _wait_at: PackedVector2Array = PackedVector2Array()
var _wait_when: PackedFloat32Array = PackedFloat32Array()
var _waiting: int = 0
## The clock until which some strike still parts the streams (none to look at past it).
var _parting_until: float = -INF
## Strikes that met a still shot, parting its streams: where, and the clock when (a ring).
var _strike_at: PackedVector2Array = PackedVector2Array()
var _strike_when: PackedFloat32Array = PackedFloat32Array()
var _strike_next: int = 0
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
	_wait_at.resize(MOST_STRIKES)
	_wait_when.resize(MOST_STRIKES)


## Watch the body of every still card that gives off motes (`spells` names them and their looks;
## `projectiles` the manager that numbered and draws them). Again when the manager numbers new bodies
## (its batches grow): a card's body keeps its number. A card whose body is not numbered yet is
## skipped until then.
func attach(projectiles: ProjectilesScript, spells: SpellRuntime) -> void:
	_looks.clear()
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


## A watched body's still shots were drawn (`view`, `still_shots_drawn`; read now, never kept): the
## strikes waiting for a still shot find theirs among them, and each shot gives off its share of each
## of its card's streams into `pool` (null: none now). The work follows the motes, not the shots: for
## each stream, as many picks as the whole batch would give off at full strength this frame, each a
## shot at random kept as often as its strength says (its clock, its start and stop), so each shot
## gives off what it would one by one, and a shot that gives off nothing this frame is never read
## (a wall's hundreds of pieces give off a few motes a frame).
func give_off(view: StillShotView, pool: MotesScript) -> void:
	if view.time != _seen:
		_frame = clampf(view.time - _seen, 0.0, LONGEST_FRAME) if _seen >= 0.0 else 0.0
		_seen = view.time
	var look: CardLook = _looks.get(view.body) as CardLook
	if look == null:
		return
	if _waiting > 0:
		_meet_strikes(view, look, pool)
	if pool == null or _frame <= 0.0 or view.count == 0:
		return
	for source: StillMoteSource in look.motes:
		var picks: int = floori(source.rate * _frame * view.count + _rng.randf())
		for p in picks:
			var n: int = _rng.randi() % view.count
			var clock: Vector2 = view.clock(n)
			if source.stop > 0.0 and clock.x >= source.stop:
				continue
			if _rng.randf() < strength(clock.x - source.start, clock.y, look.open, look.fade):
				_give_off_shot(view, n, look, source, 1, pool)


## `many` motes of the stream `source` off shot `n` of `view`.
func _give_off_shot(view: StillShotView, n: int, look: CardLook, source: StillMoteSource, many: int, pool: MotesScript) -> void:
	var kind: int = pool.kind_index(source.kind)
	if kind < 0:
		return
	var bits: int = view.look(n)
	var ramp_source: int = MotesScript.spell_source(view.ramp(n), bits)
	var core: Color = view.core(n)
	var own: PackedInt32Array = _own_kinds_of(pool, bits)
	var middle: Vector2 = view.at(n)
	var across: Vector2 = view.across(n)
	var reach: float = view.reach(n)
	var height: float = source.height * reach
	for m in many:
		var ground: Vector2 = middle + _point(source, look.shape, reach, middle, across)
		if _parted(ground, view.time):
			parted += 1
			continue
		var k: int = kind
		if not own.is_empty() and _rng.randf() < OWN_SHARE:
			k = own[_rng.randi() % own.size()]
		pool.throw_part(k, ground - Vector2(0.0, height), Vector2.UP, ramp_source, core, 1, 0.0, -1.0, 1.0, false, true, Vector2.ZERO, 1.0, bits, height)
		given += 1


## A shot or a beam struck a wall at `at`, at the projectile manager's clock `now`. It waits for the
## next drawing of the watched still shots (`give_off`): if it struck one of them (a wall made by a
## card), that shot's streams part there for PART_SECONDS and KNOCKED motes of its first stream are
## knocked out, in its colours; a strike no still shot meets within LONGEST_FRAME (a room's wall, or
## where a wall ended) is let go. At most MOST_STRIKES wait at once.
func struck(at: Vector2, now: float) -> void:
	if _looks.is_empty():
		return
	if _waiting >= MOST_STRIKES:
		_let_go_older_than(now - LONGEST_FRAME)
	if _waiting >= MOST_STRIKES:
		return
	_wait_at[_waiting] = at
	_wait_when[_waiting] = now
	_waiting += 1


## The waiting strikes that struck a shot of `view` (whose card's look is `look`): parted and
## knocked, and let go; those too old are let go too.
func _meet_strikes(view: StillShotView, look: CardLook, pool: MotesScript) -> void:
	var w: int = 0
	while w < _waiting:
		var at: Vector2 = _wait_at[w]
		var met: int = -1
		if view.time - _wait_when[w] <= LONGEST_FRAME:
			for n in view.count:
				var span: float = maxf(look.shape.x, look.shape.y) * view.reach(n) + PART_REACH
				if view.at(n).distance_squared_to(at) <= span * span:
					met = n
					break
		if met < 0 and view.time - _wait_when[w] <= LONGEST_FRAME:
			w += 1
			continue
		if met >= 0:
			_strike_at[_strike_next] = at
			_strike_when[_strike_next] = view.time
			_strike_next = (_strike_next + 1) % MOST_STRIKES
			_parting_until = view.time + PART_SECONDS
			var kind: int = pool.kind_index(look.motes[0].kind) if pool != null else -1
			if kind >= 0:
				var bits: int = view.look(met)
				pool.throw_part(kind, at, Vector2.UP, MotesScript.spell_source(view.ramp(met), bits), view.core(met), KNOCKED, KNOCK_REACH, 360.0, 1.0, false, true, Vector2.ZERO, 1.0, bits)
		_waiting -= 1
		_wait_at[w] = _wait_at[_waiting]
		_wait_when[w] = _wait_when[_waiting]


## Lets go of the waiting strikes struck before the manager's clock `then` (no still shot was drawn
## since: none of them met one).
func _let_go_older_than(then: float) -> void:
	var w: int = 0
	while w < _waiting:
		if _wait_when[w] < then:
			_waiting -= 1
			_wait_at[w] = _wait_at[_waiting]
			_wait_when[w] = _wait_when[_waiting]
		else:
			w += 1


## True while a strike parts the streams at `at` (the manager's clock `now`).
func _parted(at: Vector2, now: float) -> bool:
	if now >= _parting_until:
		return false
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

extends RefCounted
## Still motes: the motes a still carrier's shots give off all the time while they stand (the owner,
## 2026-11-09: "use motes for everything you can"; a wall's stream rising off its seam, a pool's
## motes rising off its mire). A carrier card names them (`FormBase.look_motes`, `look_mote_rate`,
## `look_motes_from`, in its `look_shape`, coming and going by `look_open` and `look_fade`; Spells
## hands them out as its `CardLook`, `SpellRuntime.still_mote_cards`), and they are given off from
## where its shots are drawn: the projectile manager hands out a view of the card body's still shots
## each frame it draws them (`watch_body`, `still_shots_drawn`, `StillShotView`: place, the way its
## row runs, hit size as drawn, colours, still clock), so nothing is asked of a shot, no area calls
## another to find one, and no row of the manager's is read here. Each mote is a one-mote cue part
## (`Motes.throw_part`) of the card's kind, or now and then of its infusions' own kinds (fire's
## embers, frost's flecks), in the shot's ramp, its infusions in turn (`Motes.set_infusions`). View
## only: it keeps nothing the simulation reads, and its dice are its own.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")

## The share of its motes that are its infusions' own kinds, when it has infusions with kinds.
const OWN_SHARE: float = 0.3
## How far into its oval a mote leaves from, at most (so none leaves from its very rim).
const AREA_INSIDE: float = 0.9
## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1

## Each watched card body's look: {body: CardLook}.
var _looks: Dictionary = {}
## The infusions' own kinds of a look's infusion layers, kept: {layers: PackedInt32Array}.
var _own_kinds: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The manager's clock when shots were last handed out, and the seconds since the one before.
var _seen: float = -1.0
var _frame: float = 0.0
## How many motes it gave off (for tests and the benchmark).
var given: int = 0


func _init() -> void:
	_rng.seed = 7


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
		if look.shader == null or look.motes == &"" or look.mote_rate <= 0.0:
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
## share of its card's motes into `pool` (null: none now).
func give_off(view: StillShotView, pool: MotesScript) -> void:
	if view.time != _seen:
		_frame = clampf(view.time - _seen, 0.0, LONGEST_FRAME) if _seen >= 0.0 else 0.0
		_seen = view.time
	var look: CardLook = _looks.get(view.body) as CardLook
	if look == null or pool == null or _frame <= 0.0:
		return
	var kind: int = pool.kind_index(look.motes)
	if kind < 0:
		return
	for n in view.count:
		var many: int = floori(look.mote_rate * _frame * strength(view.since[n], view.left[n], look.open, look.fade) + _rng.randf())
		if many <= 0:
			continue
		var bits: int = view.look[n]
		var source: int = MotesScript.spell_source(view.ramp[n], bits)
		var own: PackedInt32Array = _own_kinds_of(pool, bits)
		for m in many:
			var from: Vector2 = view.at[n] + _point(look, view.reach[n], view.across[n])
			var k: int = kind
			if not own.is_empty() and _rng.randf() < OWN_SHARE:
				k = own[_rng.randi() % own.size()]
			pool.throw_part(k, from, Vector2.UP, source, view.core[n], 1, 0.0, -1.0, 1.0, false, true, Vector2.ZERO, 1.0, bits)
			given += 1


## How strongly a shot gives off now (0 to 1), by its still clock (`since` seconds placed, `left`
## seconds of life left): coming in over its first `open` seconds, thinning over the last `fade`.
static func strength(since: float, left: float, open: float, fade: float) -> float:
	var coming: float = minf(since / open, 1.0) if open > 0.0 else 1.0
	var going: float = clampf((ProjectilesScript.STILL_END - left) / fade, 0.0, 1.0) if fade > 0.0 else (1.0 if left <= 0.0 else 0.0)
	return coming * (1.0 - going)


## A point a mote leaves from, round a shot of hit size `reach` (as drawn) whose row runs along
## `across`, in its card's look shape.
func _point(look: CardLook, reach: float, across: Vector2) -> Vector2:
	if look.motes_from == FormBase.LOOK_MOTES_ROW:
		return Vector2(0.0, floorf(reach * look.shape.y + 0.5)) + across * _rng.randf_range(-1.0, 1.0) * reach * look.shape.x
	var a: float = _rng.randf() * TAU
	return Vector2(cos(a), sin(a)) * look.shape * reach * sqrt(_rng.randf()) * AREA_INSIDE


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

extends RefCounted
## Motes given off by what Feel draws itself (docs/milestones/spell-spectacle-2.md, S6 item 10): a
## swing's sparks and card particles as its tip passes, and a beam's splash where it lands and its
## card particles along it. They were drawn inside their shot shaders (`shot_swing.gdshader`,
## `shot_beam.gdshader`) until then; now each is a birth in the projectile manager's own format
## (SPARK_BIRTH_STRIDE floats, its SPARK_* names: where, the way it is thrown, its look kind, the
## caster's ramp, the look, the core colour and the spell's tag), handed to the motes' `give_off`
## once a frame after the shots' trails, so one writer throws every mote (the native MoteKernel
## where it is built) and a birth takes its spell's cards' kinds by its tag, as a trail's does.
##
## The spectacle owns one (`Spectacle.births`); Feel adds to it while it draws, only while motes
## are on (`Spectacle.motes_on`). Rates are per second of Feel's clock and rolled with stochastic
## rounding (`roll`), so a slow source still gives off its share over a few frames. At most
## SPARK_BIRTHS_MAX a frame; past that a source gives off nothing more that frame.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

const STRIDE: int = ProjectilesScript.SPARK_BIRTH_STRIDE
const MOST: int = ProjectilesScript.SPARK_BIRTHS_MAX

## The births of this frame: the first `count` of `rows`.
var rows: PackedFloat32Array = PackedFloat32Array()
var count: int = 0
## Births asked for past MOST this frame (for tests and the storm).
var dropped: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_value: int = 0x5eed) -> void:
	rows.resize(MOST * STRIDE)
	_rng.seed = seed_value


## Starts a new frame: the births handed out are forgotten.
func clear() -> void:
	count = 0
	dropped = 0


## One birth: a mote of look kind `layer` (LOOK_*; 0 the plain sparks) at `at`, thrown along `way`,
## of a caster of `ramp` (0-3 a hat ramp, anything else the enemies'), the look `look` and the core
## colour `core`, of the spell tagged `tag` (0 for none: by its look layer alone). False once the
## frame's MOST are taken.
func add(at: Vector2, way: Vector2, layer: int, ramp: int, look: int, core: Color, tag: int) -> bool:
	if count >= MOST:
		dropped += 1
		return false
	if not at.is_finite():
		return true
	var i: int = count * STRIDE
	rows[i + ProjectilesScript.SPARK_X] = at.x
	rows[i + ProjectilesScript.SPARK_Y] = at.y
	rows[i + ProjectilesScript.SPARK_BACK_X] = way.x
	rows[i + ProjectilesScript.SPARK_BACK_Y] = way.y
	rows[i + ProjectilesScript.SPARK_KIND] = float(layer)
	rows[i + ProjectilesScript.SPARK_RAMP] = float(ramp)
	rows[i + ProjectilesScript.SPARK_LOOK] = float(look)
	rows[i + ProjectilesScript.SPARK_CORE] = core.r
	rows[i + ProjectilesScript.SPARK_CORE + 1] = core.g
	rows[i + ProjectilesScript.SPARK_CORE + 2] = core.b
	rows[i + ProjectilesScript.SPARK_TAG] = float(tag & ((1 << ProjectilesScript.SPARK_TAG_BITS) - 1))
	rows[i + ProjectilesScript.SPARK_TAG + 1] = float(tag >> ProjectilesScript.SPARK_TAG_BITS)
	count += 1
	return true


## How many to give off now for `expected` (a rate times the seconds since the last frame, or a
## share of a count): its whole part, and one more at the chance of its fraction.
func roll(expected: float) -> int:
	if not (expected > 0.0):
		return 0
	return floori(expected + _rng.randf())


## A random number from 0 to 1 (the births' own dice, so a test can seed them).
func dice() -> float:
	return _rng.randf()


## The look kinds of `look` that give off particles (ProjectilesScript.EMITTING_MASK): how many.
static func emitting_count(look: int) -> int:
	var bits: int = look & ProjectilesScript.EMITTING_MASK
	var n: int = 0
	while bits != 0:
		bits &= bits - 1
		n += 1
	return n


## One of the look kinds of `look` that give off particles, at random (LOOK_*), or 0 for none.
func emitting_layer(look: int) -> int:
	var bits: int = look & ProjectilesScript.EMITTING_MASK
	var n: int = emitting_count(look)
	if n == 0:
		return 0
	var pick: int = _rng.randi_range(0, n - 1)
	var kind: int = 1
	while bits != 0:
		if bits & 1 != 0:
			if pick == 0:
				return kind
			pick -= 1
		bits >>= 1
		kind += 1
	return 0

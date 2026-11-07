extends "res://tests/support/suite.gd"
## Deterministic maths (online-ready N7, core/sim/dmath.gd and native/src/dmath.h): the GDScript twin
## gives the native module's bits for every function on every input, and both stay within a few units
## in the last place of the engine's results where the game uses them.
##
## Without the native module the twin is still checked against the engine (SPELLMERGE_NATIVE=required
## fails the comparison instead).
##
## godot --headless --path . --script res://tests/core/test_dmath.gd

const NativeScript := preload("res://core/native/native.gd")

## The functions of one argument, by name: [native method, twin, engine].
var _unary: Dictionary = {
	"sin": [DMath.gd_sin, func(x: float) -> float: return sin(x)],
	"cos": [DMath.gd_cos, func(x: float) -> float: return cos(x)],
	"tan": [DMath.gd_tan, func(x: float) -> float: return tan(x)],
	"atan": [DMath.gd_atan, func(x: float) -> float: return atan(x)],
	"asin": [DMath.gd_asin, func(x: float) -> float: return asin(x)],
	"acos": [DMath.gd_acos, func(x: float) -> float: return acos(x)],
	"exp": [DMath.gd_exp, func(x: float) -> float: return exp(x)],
	"log": [DMath.gd_log, func(x: float) -> float: return log(x)],
}


func after_each() -> void:
	DMath.use_native(true)
	super.after_each()


## The module's kernel, or null (and a failure when the module is required).
func _kernel() -> Object:
	var kernel: Object = NativeScript.dmath_kernel()
	if kernel == null and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	return kernel


## Inputs for `name`: the values the game meets most (angles, small and large), the edges, and a
## seeded spread.
func _inputs(name: String) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, -0.0, 1.0, -1.0, 0.5, -0.5, PI, -PI, TAU, PI / 2.0, PI / 4.0, 1e-300, 1e-8, -1e-8,
		3.0, 100.0, -100.0, 1e6, 1e20, -1e20, INF, -INF, NAN, 0.9999999, 2.0, 10.0, 709.0, 710.0, -745.0, -746.0, 1e308, 4.9e-324])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for i in 3000:
		match name:
			"asin", "acos":
				out.append(rng.randf_range(-1.0, 1.0))
			"exp":
				out.append(rng.randf_range(-40.0, 40.0))
			"log":
				out.append(pow(10.0, rng.randf_range(-30.0, 30.0)))
			_:
				out.append(rng.randf_range(-50.0, 50.0) if i % 2 == 0 else rng.randf_range(-4.0, 4.0))
	return out


## Same bits (a NaN matches any NaN).
static func _same(a: float, b: float) -> bool:
	if is_nan(a) or is_nan(b):
		return is_nan(a) and is_nan(b)
	return var_to_bytes(a) == var_to_bytes(b)


## How many doubles lie between `a` and `b` (0 when equal; huge across signs or for a NaN).
static func _ulps(a: float, b: float) -> int:
	if a == b or (is_nan(a) and is_nan(b)):
		return 0
	if is_nan(a) or is_nan(b) or (a < 0.0) != (b < 0.0):
		return 1 << 62
	var bytes := PackedFloat64Array([absf(a), absf(b)]).to_byte_array()
	return absi(bytes.decode_s64(0) - bytes.decode_s64(8))


func test_the_twin_gives_the_modules_bits_for_every_function() -> void:
	var kernel: Object = _kernel()
	if kernel == null:
		return
	for name: String in _unary:
		var twin: Callable = _unary[name][0]
		var parted: int = 0
		var first: String = ""
		for x in _inputs(name):
			var native: float = kernel.call(name, x)
			var mine: float = twin.call(x)
			if not _same(native, mine):
				parted += 1
				if first == "":
					first = "%s(%s): module %s, twin %s" % [name, x, native, mine]
		check(parted == 0, "%s: the twin parts from the module on %d inputs (first %s)" % [name, parted, first])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pairs: int = 0
	for i in 3000:
		var a: float = rng.randf_range(-50.0, 50.0)
		var b: float = rng.randf_range(-50.0, 50.0)
		if i % 3 == 0:
			b = 0.0 if i % 2 == 0 else -a
		var base: float = rng.randf_range(0.0, 3.0)
		var power: float = rng.randf_range(-4.0, 4.0)
		if i % 5 == 0:
			base = -float(i % 7)
			power = float(i % 4)
		var v := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var w := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var ok: bool = _same(kernel.atan2(a, b), DMath.gd_atan2(a, b))
		ok = _same(kernel.pow(base, power), DMath.gd_pow(base, power)) and ok
		ok = _same(kernel.lerp_angle(a, b, 0.3), DMath.gd_lerp_angle(a, b, 0.3)) and ok
		ok = kernel.from_angle(a) == DMath.gd_from_angle(a) and ok
		ok = kernel.rotated(v, a) == DMath.gd_rotated(v, a) and ok
		ok = _same(kernel.angle(v), DMath.gd_atan2(v.y, v.x)) and ok
		ok = _same(kernel.angle_to(v, w), DMath.gd_angle_to(v, w)) and ok
		if not ok:
			pairs += 1
	check(pairs == 0, "atan2, pow, lerp_angle and the Vector2 helpers: the twin parts from the module on %d of 3000 inputs" % pairs)


## Close to the engine's (the C library's) where the game uses them: the twin, and through it the
## module, which gives the same bits.
func test_close_to_the_engines_results() -> void:
	DMath.use_native(false)
	var most: Dictionary = {"sin": 2, "cos": 2, "tan": 4, "atan": 2, "asin": 4, "acos": 4, "exp": 2, "log": 2}
	for name: String in _unary:
		var twin: Callable = _unary[name][0]
		var engine: Callable = _unary[name][1]
		var worst: int = 0
		var at: float = 0.0
		for x in _inputs(name):
			var expected: float = engine.call(x)
			# Near a zero of the function a unit of the input is many of the output: compare there
			# against the size of the input's unit instead.
			if absf(expected) < 1e-3 and absf(x) > 1e-3 and absf(x) < 1e6:
				check(absf(twin.call(x) - expected) < 1e-15 * maxf(absf(x), 1.0), "%s(%s) near zero: %s, the engine %s" % [name, x, twin.call(x), expected])
				continue
			var off: int = _ulps(twin.call(x), expected)
			if absf(x) <= 1e6 and off > worst:
				worst = off
				at = x
		check(worst <= most[name], "%s: at most %d units in the last place from the engine (worst %d, at %s)" % [name, most[name], worst, at])


func test_special_values() -> void:
	DMath.use_native(false)
	check_equal(DMath.sin(0.0), 0.0, "sin 0")
	check_equal(DMath.cos(0.0), 1.0, "cos 0")
	check_equal(DMath.exp(0.0), 1.0, "exp 0")
	check_equal(DMath.log(1.0), 0.0, "log 1")
	check_equal(DMath.exp(1000.0), INF, "exp overflows to INF")
	check_equal(DMath.exp(-1000.0), 0.0, "and underflows to 0")
	check_equal(DMath.log(0.0), -INF, "log 0")
	check(is_nan(DMath.log(-1.0)), "log of a negative is NaN")
	check(is_nan(DMath.sin(INF)), "sin INF is NaN")
	check_equal(DMath.pow(2.0, 10.0), 1024.0, "pow of a whole power, near enough to round to it")
	check_equal(DMath.pow(-2.0, 3.0), -8.0, "a negative base takes a whole power")
	check(is_nan(DMath.pow(-2.0, 0.5)), "and no other")
	check_equal(DMath.pow(1.5, -3.0), 1.0 / (1.5 * 1.5 * 1.5), "a negative whole power")
	check_equal(DMath.asin(2.0), PI / 2.0, "asin clamps as the engine's")
	check_equal(DMath.acos(-2.0), PI, "acos too")
	check_equal(DMath.pow(0.0, 2.0), 0.0, "0 to a power")
	check_equal(DMath.pow(5.0, 0.0), 1.0, "anything to 0")
	check_equal(DMath.atan2(0.0, 0.0), 0.0, "atan2 0, 0")
	check_equal(DMath.atan2(0.0, -1.0), PI, "atan2 0, -1")
	check_equal(DMath.atan2(1.0, 0.0), PI / 2.0, "atan2 1, 0")
	check_equal(DMath.atan2(-1.0, -1.0), -0.75 * PI, "atan2 -1, -1")
	check_equal(DMath.angle(Vector2.ZERO), 0.0, "the angle of no vector")
	check_equal(DMath.from_angle(0.0), Vector2.RIGHT, "from_angle 0")
	check((DMath.from_angle(PI / 2.0) - Vector2.DOWN).length() < 1e-7, "from_angle a quarter turn")
	check((DMath.rotated(Vector2(3.0, 4.0), PI) + Vector2(3.0, 4.0)).length() < 1e-5, "a half turn")


## The Vector2 helpers stand for the engine's: the same within the vector's float precision.
func test_the_vector_helpers_match_the_engines() -> void:
	for native: bool in [false, true]:
		DMath.use_native(native)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var worst: float = 0.0
		for i in 2000:
			var a: float = rng.randf_range(-20.0, 20.0)
			var v := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
			var w := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
			worst = maxf(worst, (DMath.from_angle(a) - Vector2.from_angle(a)).length())
			worst = maxf(worst, (DMath.rotated(v, a) - v.rotated(a)).length() / maxf(v.length(), 1.0))
			worst = maxf(worst, absf(angle_difference(DMath.angle(v), v.angle())))
			worst = maxf(worst, absf(angle_difference(DMath.angle_to(v, w), v.angle_to(w))))
			worst = maxf(worst, absf(angle_difference(DMath.lerp_angle(a, -a, 0.3), lerp_angle(a, -a, 0.3))))
		check(worst < 1e-6, "within a float's precision of the engine's (native %s; worst %s)" % [native, worst])

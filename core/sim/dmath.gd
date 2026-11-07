class_name DMath
## Deterministic maths (online-ready N7, docs/milestones/online-ready.md): what the simulation turns
## and curves by, the same to the bit on every platform. The engine's `sin`, `atan2`,
## `Vector2.from_angle` and the rest call the C library, which differs between Linux, Windows and
## the web by a unit in the last place now and then (N2b found exactly that), so two machines would
## play two games. These are built from + - * / and sqrt only (and floor and fmod, which are exact),
## each rounded the same way by IEEE 754 everywhere.
##
##     var way: Vector2 = DMath.from_angle(aim)
##     var turned: Vector2 = DMath.rotated(velocity, DMath.angle_to(velocity, want))
##     var grown: float = radius * DMath.pow(growth, delta)
##
## Simulation code (the folders in core/sim/README.md) calls these and never the engine's trig
## (`tests/core/test_sim_trig.gd` reads the source); view code keeps the engine's.
##
## Each function runs the native module's (`DMathKernel`, native/src/dmath.h) when it is loaded,
## else this file's twin of it, the same operations in the same order: `tests/core/test_dmath.gd`
## compares them to the bit. Change one and you change the other. Everything is in doubles; a
## Vector2 helper rounds its result to the vector's floats once.

const NativeScript := preload("res://core/native/native.gd")

# pi/2 in three parts: the first two of 33 significant bits each, so k * part is exact for a quadrant
# count k below 2^20, and the rest. Every constant here is an exact integer times a power of two (a
# float literal of 17 digits is not read exactly by the script parser); native/src/dmath.h holds the
# same doubles as hex.
const PIO2_HI: float = 1686629713 / float(1 << 30)
const PIO2_MID: float = 2242054355 / float(1 << 62) / float(1 << 3)
const PIO2_LO: float = 5376105825661043 / float(1 << 62) / float(1 << 59)
# pi/2 and pi, the doubles nearest them, and what each leaves out.
const PIO2: float = 884279719003555 / float(1 << 49)
const PIO2_D_LO: float = 4967757600021511 / float(1 << 62) / float(1 << 44)
const PI_HI: float = 884279719003555 / float(1 << 48)
const PI_LO: float = 4967757600021511 / float(1 << 62) / float(1 << 43)
const D_TAU: float = 884279719003555 / float(1 << 47)
const TWO_OVER_PI: float = 5734161139222659 / float(1 << 53)
# ln 2: the first 32 significant bits and the rest.
const LN2_HI: float = 2977044471 / float(1 << 32)
const LN2_LO: float = 3691024475790907 / float(1 << 62) / float(1 << 22)
const INV_LN2: float = 3248660424278399 / float(1 << 51)
const SQRT2: float = 6369051672525773 / float(1 << 52)

# 1/n!, each the double nearest it.
const F2: float = 1 / float(1 << 1)
const F3: float = 6004799503160661 / float(1 << 55)
const F4: float = 6004799503160661 / float(1 << 57)
const F5: float = 4803839602528529 / float(1 << 59)
const F6: float = 6405119470038039 / float(1 << 62)
const F7: float = 3660068268593165 / float(1 << 62) / float(1 << 2)
const F8: float = 3660068268593165 / float(1 << 62) / float(1 << 5)
const F9: float = 1626697008263629 / float(1 << 62) / float(1 << 7)
const F10: float = 1301357606610903 / float(1 << 62) / float(1 << 10)
const F11: float = 1892883791434041 / float(1 << 62) / float(1 << 14)
const F12: float = 630961263811347 / float(1 << 62) / float(1 << 16)
const F13: float = 6212541674450185 / float(1 << 62) / float(1 << 23)
const F14: float = 7100047627943069 / float(1 << 62) / float(1 << 27)
const F15: float = 7573384136472607 / float(1 << 62) / float(1 << 31)
const F16: float = 7573384136472607 / float(1 << 62) / float(1 << 35)
const F17: float = 3563945475987109 / float(1 << 62) / float(1 << 38)
const F18: float = 6335903068421527 / float(1 << 62) / float(1 << 43)
const F19: float = 5335497320776023 / float(1 << 62) / float(1 << 47)
const F20: float = 8536795713241637 / float(1 << 62) / float(1 << 52)
# 1/n for odd n, each the double nearest it.
const I3: float = 6004799503160661 / float(1 << 54)
const I5: float = 3602879701896397 / float(1 << 54)
const I7: float = 2573485501354569 / float(1 << 54)
const I9: float = 2001599834386887 / float(1 << 54)
const I11: float = 3275345183542179 / float(1 << 55)
const I13: float = 1385722962267845 / float(1 << 54)
const I15: float = 4803839602528529 / float(1 << 56)
const I17: float = 4238682002231055 / float(1 << 56)
const I19: float = 948126237341157 / float(1 << 54)
const I21: float = 857828500451523 / float(1 << 54)
const I23: float = 1566469435607129 / float(1 << 55)
# atan(k/8) for k = 0..8: the double nearest it, and what that leaves out.
const ATAN_HI: Array[float] = [0.0,
	4480360856819639 / float(1 << 55), 8826286527774941 / float(1 << 55), 6463037827768049 / float(1 << 54),
	8352332796509007 / float(1 << 54), 1257853834215341 / float(1 << 51), 5796142707547873 / float(1 << 53),
	1618661259219341 / float(1 << 51), 884279719003555 / float(1 << 50)]
const ATAN_LO: Array[float] = [0.0,
	-8113805363383319 / float(1 << 62) / float(1 << 49), 6943889398673341 / float(1 << 62) / float(1 << 47),
	-998860627303715 / float(1 << 62) / float(1 << 43), 3683087214424817 / float(1 << 62) / float(1 << 45),
	-7081813339694735 / float(1 << 62) / float(1 << 48), 642335192798347 / float(1 << 62) / float(1 << 43),
	-3485067776454523 / float(1 << 62) / float(1 << 45), 4967757600021511 / float(1 << 62) / float(1 << 45)]
const LOG_STEPS: Array[float] = [512.0, 256.0, 128.0, 64.0, 32.0, 16.0, 8.0, 4.0, 2.0, 1.0]

## The native module's `DMathKernel`, or null (no module, or switched off by a test).
static var _kernel: Object = NativeScript.dmath_kernel()


## Whether these run the native module's maths (tests switch it off to time or compare the twin).
static func native_on() -> bool:
	return _kernel != null


## Run the native module's maths (when it is loaded) or this file's twin.
static func use_native(on: bool) -> void:
	_kernel = NativeScript.dmath_kernel() if on else null


static func sin(x: float) -> float:
	if _kernel != null:
		return _kernel.sin(x)
	return gd_sin(x)


static func cos(x: float) -> float:
	if _kernel != null:
		return _kernel.cos(x)
	return gd_cos(x)


static func tan(x: float) -> float:
	if _kernel != null:
		return _kernel.tan(x)
	return gd_tan(x)


static func atan(x: float) -> float:
	if _kernel != null:
		return _kernel.atan(x)
	return gd_atan(x)


static func atan2(y: float, x: float) -> float:
	if _kernel != null:
		return _kernel.atan2(y, x)
	return gd_atan2(y, x)


static func asin(x: float) -> float:
	if _kernel != null:
		return _kernel.asin(x)
	return gd_asin(x)


static func acos(x: float) -> float:
	if _kernel != null:
		return _kernel.acos(x)
	return gd_acos(x)


static func exp(x: float) -> float:
	if _kernel != null:
		return _kernel.exp(x)
	return gd_exp(x)


static func log(x: float) -> float:
	if _kernel != null:
		return _kernel.log(x)
	return gd_log(x)


static func pow(x: float, y: float) -> float:
	if _kernel != null:
		return _kernel.pow(x, y)
	return gd_pow(x, y)


static func lerp_angle(from: float, to: float, weight: float) -> float:
	if _kernel != null:
		return _kernel.lerp_angle(from, to, weight)
	return gd_lerp_angle(from, to, weight)


## The unit vector at `angle` (in place of `Vector2.from_angle`).
static func from_angle(angle: float) -> Vector2:
	if _kernel != null:
		return _kernel.from_angle(angle)
	return gd_from_angle(angle)


## `v` turned by `angle` (in place of `Vector2.rotated`).
static func rotated(v: Vector2, angle: float) -> Vector2:
	if _kernel != null:
		return _kernel.rotated(v, angle)
	return gd_rotated(v, angle)


## The angle of `v` (in place of `Vector2.angle`).
static func angle(v: Vector2) -> float:
	if _kernel != null:
		return _kernel.angle(v)
	return gd_atan2(v.y, v.x)


## The angle from `from` to `to` (in place of `from.angle_to(to)`).
static func angle_to(from: Vector2, to: Vector2) -> float:
	if _kernel != null:
		return _kernel.angle_to(from, to)
	return gd_angle_to(from, to)


# The twin: native/src/dmath.h, line by line.

static func _sin_poly(r: float) -> float:
	var z: float = r * r
	return r + r * z * (-F3 + z * (F5 + z * (-F7 + z * (F9 + z * (-F11 + z * (F13 + z * (-F15 + z * (F17 + z * -F19))))))))


static func _cos_poly(r: float) -> float:
	var z: float = r * r
	return 1.0 + z * (-F2 + z * (F4 + z * (-F6 + z * (F8 + z * (-F10 + z * (F12 + z * (-F14 + z * (F16 + z * (-F18 + z * F20)))))))))


# Each of sin, cos and tan reduces x itself (dmath.h's `reduce`): x = r + q pi/2, q taken mod 4.
static func gd_sin(x: float) -> float:
	var k: float = floorf(x * TWO_OVER_PI + 0.5)
	var q: float = k - 4.0 * floorf(k * 0.25)
	var r: float = ((x - k * PIO2_HI) - k * PIO2_MID) - k * PIO2_LO
	if q == 0.0:
		return _sin_poly(r)
	if q == 1.0:
		return _cos_poly(r)
	if q == 2.0:
		return -_sin_poly(r)
	return -_cos_poly(r)


static func gd_cos(x: float) -> float:
	var k: float = floorf(x * TWO_OVER_PI + 0.5)
	var q: float = k - 4.0 * floorf(k * 0.25)
	var r: float = ((x - k * PIO2_HI) - k * PIO2_MID) - k * PIO2_LO
	if q == 0.0:
		return _cos_poly(r)
	if q == 1.0:
		return -_sin_poly(r)
	if q == 2.0:
		return -_cos_poly(r)
	return _sin_poly(r)


static func gd_tan(x: float) -> float:
	var k: float = floorf(x * TWO_OVER_PI + 0.5)
	var q: float = k - 4.0 * floorf(k * 0.25)
	var r: float = ((x - k * PIO2_HI) - k * PIO2_MID) - k * PIO2_LO
	if q == 0.0 or q == 2.0:
		return _sin_poly(r) / _cos_poly(r)
	return -_cos_poly(r) / _sin_poly(r)


static func _atan_unit(a: float) -> float:
	var k: float = floorf(a * 8.0 + 0.5)
	var t: float = a
	var hi: float = 0.0
	var lo: float = 0.0
	if k > 0.0:
		var c: float = k * 0.125
		t = (a - c) / (1.0 + a * c)
		var i: int = int(k)
		hi = ATAN_HI[i]
		lo = ATAN_LO[i]
	var z: float = t * t
	var p: float = t * z * (-I3 + z * (I5 + z * (-I7 + z * (I9 + z * (-I11 + z * (I13 + z * -I15))))))
	return hi + (t + (p + lo))


static func gd_atan(x: float) -> float:
	if x != x:
		return x
	var negative: bool = x < 0.0
	var a: float = -x if negative else x
	var r: float
	if a > 1.0:
		r = (PIO2 - _atan_unit(1.0 / a)) + PIO2_D_LO
	else:
		r = _atan_unit(a)
	return -r if negative else r


static func gd_atan2(y: float, x: float) -> float:
	if x != x or y != y:
		return x + y
	if y == 0.0:
		return PI_HI if x < 0.0 else 0.0
	var ax: float = -x if x < 0.0 else x
	var ay: float = -y if y < 0.0 else y
	var a: float
	if ax == ay:
		a = ATAN_HI[8]
	elif ay > ax:
		a = (PIO2 - _atan_unit(ax / ay)) + PIO2_D_LO
	else:
		a = _atan_unit(ay / ax)
	if x < 0.0:
		a = (PI_HI - a) + PI_LO
	return -a if y < 0.0 else a


static func gd_asin(x: float) -> float:
	if x != x:
		return x
	if x <= -1.0:
		return -PIO2
	if x >= 1.0:
		return PIO2
	return gd_atan2(x, sqrt((1.0 - x) * (1.0 + x)))


static func gd_acos(x: float) -> float:
	if x != x:
		return x
	if x <= -1.0:
		return PI_HI
	if x >= 1.0:
		return 0.0
	return gd_atan2(sqrt((1.0 - x) * (1.0 + x)), x)


## 2^n for a whole n in [-1022, 1023], exactly.
static func _pow2(n: float) -> float:
	var result: float = 1.0
	var base: float = 0.5 if n < 0.0 else 2.0
	var left: int = int(-n if n < 0.0 else n)
	while left > 0:
		if left & 1:
			result *= base
		left >>= 1
		if left > 0:
			base *= base
	return result


static func _scale2(p: float, k: float) -> float:
	if k > 1023.0:
		return p * _pow2(1023.0) * _pow2(k - 1023.0)
	if k < -1022.0:
		return p * _pow2(k + 60.0) * _pow2(-60.0)
	return p * _pow2(k)


static func gd_exp(x: float) -> float:
	if x != x:
		return x
	var k: float = floorf(x * INV_LN2 + 0.5)
	if k > 1024.0:
		return INF
	if k < -1080.0:
		return 0.0
	var r: float = (x - k * LN2_HI) - k * LN2_LO
	var p: float = 1.0 + r * (1.0 + r * (F2 + r * (F3 + r * (F4 + r * (F5 + r * (F6 + r * (F7 + r * (F8 + r * (F9 + r * (F10 + r * (F11 + r * (F12 + r * (F13 + r * (F14 + r * F15))))))))))))))
	return _scale2(p, k)


static func gd_log(x: float) -> float:
	if x != x:
		return x
	if x < 0.0:
		return NAN
	if x == 0.0:
		return -INF
	if x == INF:
		return x
	var m: float = x
	var e: float = 0.0
	if m < _pow2(-1022.0):
		m *= _pow2(54.0)
		e = -54.0
	for p: float in LOG_STEPS:
		if m >= _pow2(p):
			m *= _pow2(-p)
			e += p
	for p: float in LOG_STEPS:
		if m < _pow2(1.0 - p):
			m *= _pow2(p)
			e -= p
	if m > SQRT2:
		m *= 0.5
		e += 1.0
	var s: float = (m - 1.0) / (m + 1.0)
	var z: float = s * s
	var q: float = s * z * (I3 + z * (I5 + z * (I7 + z * (I9 + z * (I11 + z * (I13 + z * (I15 + z * (I17 + z * (I19 + z * (I21 + z * I23))))))))))
	var logm: float = 2.0 * (s + q)
	return e * LN2_HI + (e * LN2_LO + logm)


static func gd_pow(x: float, y: float) -> float:
	if y == 0.0 or x == 1.0:
		return 1.0
	if x != x or y != y:
		return x + y
	if y == 1.0:
		return x
	if y == 2.0:
		return x * x
	if x == 0.0:
		return 0.0 if y > 0.0 else INF
	var whole: bool = floorf(y) == y
	if whole and y >= -64.0 and y <= 64.0:
		var result: float = 1.0
		var base: float = x
		var left: int = int(-y if y < 0.0 else y)
		while left > 0:
			if left & 1:
				result *= base
			left >>= 1
			if left > 0:
				base *= base
		return 1.0 / result if y < 0.0 else result
	var negative: bool = false
	var a: float = x
	if x < 0.0:
		if not whole:
			return NAN
		negative = fmod(y, 2.0) != 0.0
		a = -x
	var r: float = gd_exp(y * gd_log(a))
	return -r if negative else r


static func gd_lerp_angle(from: float, to: float, weight: float) -> float:
	var difference: float = fmod(to - from, D_TAU)
	var distance: float = fmod(2.0 * difference, D_TAU) - difference
	return from + distance * weight


static func gd_from_angle(angle: float) -> Vector2:
	return Vector2(gd_cos(angle), gd_sin(angle))


static func gd_rotated(v: Vector2, angle: float) -> Vector2:
	var s: float = gd_sin(angle)
	var c: float = gd_cos(angle)
	var x: float = v.x
	var y: float = v.y
	return Vector2(x * c - y * s, x * s + y * c)


static func gd_angle_to(from: Vector2, to: Vector2) -> float:
	var cross: float = from.x * to.y - from.y * to.x
	var dot: float = from.x * to.x + from.y * to.y
	return gd_atan2(cross, dot)

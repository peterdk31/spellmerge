extends Node2D
## The portals' gates while they are open (docs/milestones/portal.md, "Looks and sound"), drawn by
## Feel every frame from the runtime's portal rows (`CarrierPortal`: `portal_slots`, `portal_on`,
## `portal_gate_count`, `portal_gate`, `portal_caster`, `portal_seconds`, `portal_infusions`) and the
## projectile manager's gates (`gate_position`, `gate_face`, `gate_radius`, `gate_is_mouth`).
##
## Each gate is a mote rift (the owner's pick, 2026-11-09: "use motes for everything you can"): a dark
## lens standing across the way through, its stars twinkling motes drifting through it, its lips two
## thick streams of twinkling motes (the ward's look: a pixel, white-hot at the start of its twinkle,
## a little plus at its brightest), up one side and down the other; loose motes spiral into a mouth
## and are thrown out of an exit. It opens tall, then wide, and closes the other way. A faint dotted
## line joins a mouth to each of its exits, so anybody can read where a shot will come out (pillar 4).
## Every infusion shows (the owner: "in cool ways"): its first lip in its first infusion, its second
## in its second (the first's with one), its stars and loose motes in each in turn; with none, in its
## caster's colours. Its opening and closing are its card's cues too (`portal_open`, `portal_close`).
## Drawn only: nothing here feeds back into the game, and its dice are its own hash.

## Seconds it takes to open tall, and to open wide after a beat; seconds before its end it starts to
## close (narrowing, then shrinking).
const OPEN_TALL: float = 0.3
const OPEN_WIDE_FROM: float = 0.2
const OPEN_WIDE: float = 0.3
const CLOSE: float = 0.65
const CLOSE_WIDE: float = 0.3
const CLOSE_TALL: float = 0.35
## A gate of radius RADIUS is a lens HALF_TALL pixels up and down and HALF_WIDE across (it scales).
const RADIUS: float = 12.0
const HALF_TALL: float = 12.0
const HALF_WIDE: float = 4.2
## Each lip's motes: how many a stream, two streams deep, and how fast they run (lap a second).
const LIP_MOTES: int = 22
const LIP_ROWS: int = 2
const LIP_RUN: float = 0.45
## Loose motes round a gate, and how far out they start (a mouth) or end (an exit).
const LOOSE: int = 10
const LOOSE_REACH: float = 12.0
## Portals draw where beams do: above the room, under the shots and the flashes.
const PORTAL_Z: int = 17
const DARK: Color = Color(0.078, 0.071, 0.122)
## A twinkle's plus round a mote, and the lens's two sides.
const PLUS: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const SIDES: Array[int] = [-1, 1]

var _portals: Object = null
var _projectiles: Object = null
var _clock: float = 0.0
## The colours of the portal being drawn: each infusion's ramp (white-hot, light, base, shadow),
## four a slot, and how many slots.
var _colours: PackedColorArray = PackedColorArray()
var _ramp_count: int = 1

func _init() -> void:
	z_index = PORTAL_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Feel's step: `portals` is the runtime's portal carrier (null when there is none), `projectiles`
## the manager its gates are rows of, `clock` Feel's clock.
func step(portals: Object, projectiles: Object, clock: float) -> void:
	_portals = portals
	_projectiles = projectiles
	_clock = clock
	queue_redraw()


func _draw() -> void:
	if _portals == null or _projectiles == null or not is_instance_valid(_projectiles):
		return
	var slots: int = int(_portals.call("portal_slots"))
	for at in slots:
		if not bool(_portals.call("portal_on", at)):
			continue
		var count: int = int(_portals.call("portal_gate_count", at))
		if count == 0:
			continue
		var player: Color = _projectiles.call("tint_of", int(_portals.call("portal_caster", at)))
		_take_colours(_portals.call("portal_infusions", at) as PackedColorArray, player)
		var seconds: Vector2 = _portals.call("portal_seconds", at)
		var open: Vector2 = opening(seconds.x, seconds.y)
		var mouth: Vector2 = Vector2.INF
		for n in count:
			var gate: int = int(_portals.call("portal_gate", at, n))
			if bool(_projectiles.call("gate_is_mouth", gate)):
				mouth = _projectiles.call("gate_position", gate)
		for n in count:
			var gate: int = int(_portals.call("portal_gate", at, n))
			var centre: Vector2 = _projectiles.call("gate_position", gate)
			var face: Vector2 = _projectiles.call("gate_face", gate)
			var radius: float = float(_projectiles.call("gate_radius", gate))
			var is_mouth: bool = bool(_projectiles.call("gate_is_mouth", gate))
			if not centre.is_finite():
				continue
			if not is_mouth and mouth.is_finite():
				_tether(mouth, centre, open.y)
			_gate(centre, face, radius, is_mouth, open, at * 97 + n * 13)


## How open a gate is `age` seconds after it opened with `left` seconds to go: (tall, wide), each 0
## to 1. It opens tall, then wide (a little past, settling back), and closes narrowing, then shrinking.
static func opening(age: float, left: float) -> Vector2:
	var tall: float = 1.0 - pow(1.0 - clampf(age / OPEN_TALL, 0.0, 1.0), 2.0)
	var k: float = clampf((age - OPEN_WIDE_FROM) / OPEN_WIDE, 0.0, 1.0) - 1.0
	var wide: float = 1.0 + 2.70158 * k * k * k + 1.70158 * k * k
	if left < CLOSE:
		var narrow: float = clampf((CLOSE - left) / CLOSE_WIDE, 0.0, 1.0)
		wide = minf(wide, 1.0 - narrow * narrow)
		tall = minf(tall, 1.0 - clampf((CLOSE - CLOSE_WIDE - left) / CLOSE_TALL, 0.0, 1.0))
	return Vector2(maxf(tall, 0.0), maxf(wide, 0.0))


## Each infusion's ramp for the portal being drawn, from its tints in slot order (its caster's
## colour `player` for none): white-hot, light, base, shadow.
func _take_colours(tints: PackedColorArray, player: Color) -> void:
	_ramp_count = maxi(tints.size(), 1)
	if _colours.size() < _ramp_count * 4:
		_colours.resize(_ramp_count * 4)
	for n in _ramp_count:
		var base: Color = Color(tints[n].r, tints[n].g, tints[n].b) if n < tints.size() else player
		_colours[n * 4] = base.lerp(Color.WHITE, 0.75)
		_colours[n * 4 + 1] = base.lerp(Color.WHITE, 0.35)
		_colours[n * 4 + 2] = base
		_colours[n * 4 + 3] = base.darkened(0.5)


## Shade `shade` (0 white-hot, 1 light, 2 base, 3 shadow) of the `slot`th infusion in turn.
func _shade(slot: int, shade: int) -> Color:
	return _colours[posmod(slot, _ramp_count) * 4 + shade]


## A number in [0, 1) from three numbers: the same every frame for the same ones.
static func _hash(a: float, b: float, c: float) -> float:
	var s: float = sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453
	return s - floorf(s)


## Half the lens's width `n` (-1 to 1) of the way up it, for a lens `wide` across.
static func lens_width(n: float, wide: float) -> float:
	return wide * sqrt(maxf(0.0, 1.0 - n * n))


## A dotted line from `a` to `b`, its ends left clear of the gates.
func _tether(a: Vector2, b: Vector2, tall: float) -> void:
	var length: float = a.distance_to(b)
	if length < 8.0:
		return
	var way: Vector2 = (b - a) / length
	var dots: int = int(length / 6.0)
	var colour: Color = Color(_shade(0, 1), 0.6 * tall)
	for k in range(2, dots - 1):
		var at: Vector2 = (a + way * (k * 6.0)).round()
		draw_rect(Rect2(at - Vector2.ONE * 0.5, Vector2.ONE * 2.0), colour)


## One pixel at `at` (world), in `colour`.
func _pixel(at: Vector2, colour: Color) -> void:
	draw_rect(Rect2(at.floor(), Vector2.ONE), colour)


## A twinkling mote at `at` in the `slot`th infusion's colours, its twinkle by `key`; `bright` below 1
## twinkles less (a back row).
func _mote(at: Vector2, key: float, slot: int, bright: float) -> void:
	var tw: float = fposmod(_clock * (1.3 + _hash(key, 1.0, 0.0)) + _hash(key, 2.0, 0.0), 1.0)
	_pixel(at, _shade(slot, 0) if tw < 0.12 * bright else _shade(slot, 1 if tw < 0.55 else 2))
	if tw < 0.07 * bright:
		for side: Vector2 in PLUS:
			_pixel(at + side, _shade(slot, 1))


## A gate at `centre` facing `face` (a shot goes through along it), of `radius`, open (tall, wide) as
## `open`; `key` its own dice. Its lens stands across `face`.
func _gate(centre: Vector2, face: Vector2, radius: float, is_mouth: bool, open: Vector2, key: int) -> void:
	var size: float = radius / RADIUS
	var tall: float = HALF_TALL * size * open.x
	var wide: float = HALF_WIDE * size * open.y
	if tall < 0.5:
		return
	var across: Vector2 = face.normalized() if face.length_squared() > 0.0001 else Vector2.RIGHT
	var up: Vector2 = Vector2(-across.y, across.x)
	if up.y > 0.0:
		up = -up
	var dir: float = 1.0 if is_mouth else -1.0
	# The dark lens, its edge in the first's shadow, stars drifting through it.
	var rows: int = int(ceilf(tall))
	for j in range(-rows, rows + 1):
		var half: float = lens_width(float(j) / tall, maxf(wide - 0.4, 0.0))
		var cols: int = int(floorf(half))
		for i in range(-cols, cols + 1):
			var colour: Color = DARK
			if absi(i) == cols:
				colour = _shade(0, 3)
			elif _hash(float(j), floorf(float(i) + _clock * 3.0 * dir), float(key)) > 0.95:
				colour = _shade(i + j, 1 if _hash(float(i), float(j), 4.0) > 0.7 else 2)
			_pixel(centre + across * float(i) + up * float(j), colour)
	# The lips: streams of motes up one side and down the other, two deep; the first lip in the
	# first infusion, the second in the second.
	for side: int in SIDES:
		var slot: int = 0 if side < 0 else 1
		for r in LIP_ROWS:
			for k in LIP_MOTES:
				var s: float = fposmod(float(k) / LIP_MOTES + _clock * (LIP_RUN + r * 0.2) * side * dir + r * 0.5 / LIP_MOTES, 1.0)
				var n: float = s * 2.0 - 1.0
				var at: Vector2 = centre + across * (side * (lens_width(n, wide) + 0.6 + r * 1.3)) + up * (n * tall)
				_mote(at, float(k + r * 50 + (200 if side > 0 else 0) + key), slot, 0.6 if r > 0 else 1.0)
	# Loose motes: spiralling into a mouth, thrown out of an exit; each infusion in turn.
	if open.y > 0.5:
		for k in LOOSE:
			var v: float = _clock * 0.7 + _hash(float(k), float(key), 0.0)
			var p: float = fposmod(v, 1.0)
			if not is_mouth and p > 0.85:
				continue
			var ang: float = _hash(float(k), floorf(v), float(key) + 1.0) * TAU + p * 1.5 * dir
			var d: float = (LOOSE_REACH * (1.0 - p) + 2.0 if is_mouth else 2.0 + LOOSE_REACH * p) * size
			_mote(centre + across * (cos(ang) * d * 0.7) + up * (sin(ang) * d), float(k + key), k, 0.7)

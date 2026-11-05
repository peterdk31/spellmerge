extends Node2D
## The portals' gates while they are open (docs/milestones/portal.md, "Looks and sound"), drawn by
## Feel every frame from the runtime's portal rows (`CarrierPortal`: `portal_slots`, `portal_on`,
## `portal_gate_count`, `portal_gate`, `portal_caster`, `portal_tint`, `portal_left`) and the
## projectile manager's gates (`gate_position`, `gate_face`, `gate_radius`, `gate_is_mouth`).
##
## Each gate is a sphere (owner, 2026-11-05: it has no front): a ring in its caster's colour round a
## dark heart, with a white-hot inner edge in the portal's tint (its infusion's colour, or white) and
## a glint high on its left. A mouth's three short arcs swirl inward, an exit's outward. A faint dotted line joins a mouth
## to each of its exits, so anybody can read where a shot will come out (pillar 4). A portal fades
## over the last FADE of its life. Drawn only: nothing here feeds back into the game.

## The share of its life, at its end, over which a portal fades.
const FADE: float = 0.15
## Seconds a swirl takes to turn once.
const SWIRL_SECONDS: float = 1.2
## Portals draw where beams do: above the room, under the shots and the flashes.
const PORTAL_Z: int = 17
const HEART: Color = Color(0.078, 0.071, 0.122, 0.75)

var _portals: Object = null
var _projectiles: Object = null
var _clock: float = 0.0


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
		var tint: Color = _portals.call("portal_tint", at)
		var whole: float = clampf(float(_portals.call("portal_left", at)) / FADE, 0.0, 1.0)
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
				_tether(mouth, centre, player, whole)
			_gate(centre, face, radius, is_mouth, player, tint, whole)


## A dotted line from `a` to `b`, its ends left clear of the gates.
func _tether(a: Vector2, b: Vector2, player: Color, whole: float) -> void:
	var length: float = a.distance_to(b)
	if length < 8.0:
		return
	var way: Vector2 = (b - a) / length
	var dots: int = int(length / 6.0)
	var colour: Color = Color(player.lerp(Color.WHITE, 0.35), 0.6 * whole)
	for k in range(2, dots - 1):
		var at: Vector2 = (a + way * (k * 6.0)).round()
		draw_rect(Rect2(at - Vector2.ONE * 0.5, Vector2.ONE * 2.0), colour)


func _gate(centre: Vector2, _face: Vector2, radius: float, is_mouth: bool, player: Color, tint: Color, whole: float) -> void:
	var points: int = maxi(16, int(radius * 2.0))
	draw_circle(centre, radius, Color(HEART, HEART.a * whole))
	draw_arc(centre, radius, 0.0, TAU, points, Color(player, whole), 2.0, false)
	draw_arc(centre, maxf(radius - 2.0, 1.0), 0.0, TAU, points, Color(tint.lerp(Color.WHITE, 0.5), 0.8 * whole), 1.0, false)
	# Three short arcs swirling: inward for a mouth, outward for an exit.
	var turn: float = TAU * fposmod(_clock / SWIRL_SECONDS, 1.0) * (1.0 if is_mouth else -1.0)
	var inner: float = radius * (0.55 + 0.25 * fposmod(_clock / SWIRL_SECONDS * (1.0 if is_mouth else -1.0), 1.0))
	for k in 3:
		var from: float = turn + TAU * k / 3.0
		draw_arc(centre, inner, from, from + 0.9, 6, Color(player.lerp(Color.WHITE, 0.4), 0.7 * whole), 1.0, false)
	# A glint high on its left, so it reads as a sphere.
	draw_arc(centre, maxf(radius - 4.0, 1.0), PI * 1.05, PI * 1.35, 4, Color(Color.WHITE, 0.6 * whole), 1.0, false)

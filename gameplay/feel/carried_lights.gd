extends RefCounted
## Carried lights (docs/milestones/atmosphere.md, A): every seat's wizard carries a small light at
## its staff tip, in its hat's light shade, so in a dark room the players are lit pools and still
## the easiest thing to read (crypt rework, rule 6). While a seat drives another body (it possesses
## one) the light goes with the body it drives, still in the seat's hat colour, since that is where
## the player looks. View only: it reads where the bodies are drawn (the actor table's nodes) once
## a frame and writes one spot row a seat (`SpellLight.write_spot_row`) into a buffer made once,
## which the spectacle hands the spell light (`SpellLight.light_carried`). It knows the actors, not
## the light's batches; the spell light knows the batches, not the actors.
##
## Smooth (docs/STYLE.md): a light never pops. Each seat's strength eases toward what it should be
## (full, dimmer while downed, out as its body falls into a hole, out when its body is gone) over
## EASE_SECONDS, at least 3 frames, and a light whose body is gone fades where it last was.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## How far a carried light reaches (px, its radius: to where it is gone), and how bright it is at
## its middle: about a torch's reach, dimmer than one (LightSpot.DEFAULT_STRENGTH 0.7), so a
## wizard is lit round itself but a candle's pool still reads as the place to stand.
const CARRIED_REACH: float = 52.0
const CARRIED_STRENGTH: float = 0.4
## How much of it a downed wizard keeps (its staff dims while it waits for a teammate).
const DOWNED_SHARE: float = 0.5
## A carried light's flicker (a little: a staff's glow, not a flame's).
const CARRIED_FLICKER: float = 0.08
## How long a whole change of strength takes (s): 0.15 is 9 frames at 60 per second.
const EASE_SECONDS: float = 0.15
## Below this strength a light is out (no row).
const OUT: float = 0.002

## The rows (ActorsScript.SEATS of them, made once) and how many are written this frame. Read only.
var rows: PackedFloat32Array = PackedFloat32Array()
var count: int = 0
## The actor carrying each row's light (the body its seat drives; NONE once that body is gone), so
## a body's shadow is not cast by its own light (atmosphere C, `body_shadows.gd`). Read only.
var owners: PackedInt32Array = PackedInt32Array()
## Each seat's light as drawn: its strength now, where it was last and its colour (kept so a light
## whose body is gone fades where it stood). Read only.
var strength: PackedFloat32Array = PackedFloat32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _colour: PackedColorArray = PackedColorArray()
## Feel's clock at the last step (-1: none yet), for the ease's time.
var _last: float = -1.0


func _init() -> void:
	rows.resize(ActorsScript.SEATS * SpellLightScript.STRIDE)
	strength.resize(ActorsScript.SEATS)
	owners.resize(ActorsScript.SEATS)
	_at.resize(ActorsScript.SEATS)
	_colour.resize(ActorsScript.SEATS)


## Write this frame's rows from `table` (the actor table; null: every light fades) at Feel's clock
## `now` (real seconds).
func step(table: ActorsScript, now: float) -> void:
	var delta: float = clampf(now - _last, 0.0, 0.25) if _last >= 0.0 else 0.0
	_last = now
	var most: float = CARRIED_STRENGTH * delta / EASE_SECONDS
	count = 0
	for seat in ActorsScript.SEATS:
		var want: float = 0.0
		var body: Actor = _body_of(table, seat)
		var owner: int = body.id if body != null else ActorsScript.NONE
		if body != null:
			want = CARRIED_STRENGTH * (DOWNED_SHARE if body.is_downed() else 1.0) * (1.0 - body.fall_share())
			_at[seat] = body.muzzle_position()
			_colour[seat] = ProjectileManagerScript.ramp_light(table.ramp_of(table.home_of_seat(seat)))
			if strength[seat] <= OUT and delta <= 0.0:
				# The very first frame (nothing to ease from): no light yet, it eases in from the next.
				want = 0.0
		strength[seat] = move_toward(strength[seat], want, most)
		if strength[seat] <= OUT:
			continue
		# Each seat's own seed, so four staffs do not flicker together.
		var seed: float = (float(seat) + 0.5) / float(ActorsScript.SEATS)
		SpellLightScript.write_spot_row(rows, count, _at[seat], CARRIED_REACH, _colour[seat], strength[seat], CARRIED_FLICKER, seed)
		owners[count] = owner
		count += 1


## The body seat `seat` drives (its own wizard, or the body it possesses: `shown_of_seat`) while it
## is drawn in a tree, else null.
func _body_of(table: ActorsScript, seat: int) -> Actor:
	if table == null:
		return null
	var id: int = table.shown_of_seat(seat)
	if id == ActorsScript.NONE:
		return null
	var body := table.node_of(id) as Actor
	if body == null or not body.is_inside_tree() or body.is_queued_for_deletion() or not body.is_visible_in_tree():
		return null
	return body

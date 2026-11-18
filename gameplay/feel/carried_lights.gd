extends RefCounted
## Carried lights (docs/milestones/atmosphere.md, A): every seat's wizard carries a small light at
## its staff tip, in its hat's light shade, so in a dark room the players are lit pools and still
## the easiest thing to read (crypt rework, rule 6). View only: it reads where the bodies are drawn
## (the actor table's nodes) once a frame and writes one spot row each (`SpellLight.write_spot_row`)
## into a buffer made once, which the spectacle hands the spell light (`SpellLight.light_carried`).
## It knows the actors, not the light's batches; the spell light knows the batches, not the actors.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## How far a carried light reaches (px, to where it is gone), and how bright it is at its middle:
## about a torch's reach, dimmer than one (LightSpot.DEFAULT_STRENGTH 0.7), so a wizard is lit
## round itself but a torch's pool still reads as the place to stand.
const CARRIED_REACH: float = 52.0
const CARRIED_STRENGTH: float = 0.4
## How much of it a downed wizard keeps (its staff dims while it waits for a teammate).
const DOWNED_SHARE: float = 0.5
## A carried light's flicker (a little: a staff's glow, not a flame's).
const CARRIED_FLICKER: float = 0.08

## The rows (ActorsScript.SEATS of them, made once) and how many are written this frame. Read only.
var rows: PackedFloat32Array = PackedFloat32Array()
var count: int = 0


func _init() -> void:
	rows.resize(ActorsScript.SEATS * SpellLightScript.STRIDE)


## Write this frame's rows from `table` (the actor table; null: none): a light at the staff tip
## of each seat's own body that is drawn in a tree.
func step(table: ActorsScript) -> void:
	count = 0
	if table == null:
		return
	for seat in ActorsScript.SEATS:
		var id: int = table.home_of_seat(seat)
		if id == ActorsScript.NONE:
			continue
		var body := table.node_of(id) as Actor
		if body == null or not body.is_inside_tree() or not body.is_visible_in_tree():
			continue
		var strength: float = CARRIED_STRENGTH * (DOWNED_SHARE if body.is_downed() else 1.0)
		var colour: Color = ProjectileManagerScript.ramp_light(table.ramp_of(id))
		# Each seat's own seed, so four staffs do not flicker together.
		var seed: float = (float(seat) + 0.5) / float(ActorsScript.SEATS)
		SpellLightScript.write_spot_row(rows, count, body.muzzle_position(), CARRIED_REACH, colour, strength, CARRIED_FLICKER, seed)
		count += 1

extends "res://tests/support/screenshot.gd"
## Trails (the owner, 2026-10-28: "the tail of projectiles turn with the projectile"): a shot's
## tail and card particles stay in the world where it was, so they bend with any path. Drawn by
## the real projectile manager, a column per infusion (plain, fire, frost, storm, void, lightning;
## the real cards' colours and looks):
##   top     homing bolts fired upward that turn hard toward a target to their right: the tail
##           follows the curve, it does not swing round with the head
##   middle  bolts that bounced off the wall above them and fly down again: the tail turns the
##           corner
##   bottom  a dash (the caster's trail, `follow_caster`) along a curve, as a wizard that walks
##           round while it dashes: the streaks and cards are where it went
## `trails` at 1x, `trails_4x` (the plain, fire and frost columns of the top two rows).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const BOLT := preload("res://content/spells/forms/bolt/bolt.tres")
const COLUMN: float = 106.0
## Steps before the picture: the homing bolts are round their turn, the bounced ones on their way
## down, the dashes half done.
const STEPS: int = 24

var _shots: Node = null
var _targets: Array[Node2D] = []


func take() -> void:
	if not need(["Projectiles", "Actors"]):
		return
	_shots = root.get_node("Projectiles")
	lay_floor()
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	_shots.call("set_cap", 300)
	# The wall the middle row bounces off.
	_shots.call("set_walls", [Rect2(0.0, 120.0, SCREEN.x, 8.0)] as Array[Rect2])
	var speed: float = float(BOLT.get("speed"))
	# The dashers: four seated wizards, then two enemies (their streaks are the enemy ramp).
	var dashers: Array[int] = _casters()
	for e in 6:
		var x: float = 30.0 + e * COLUMN
		var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
		var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
		var player: int = dashers[e % 4]
		var target := Node2D.new()
		target.position = Vector2(x + 70.0, 30.0)
		root.add_child(target)
		_targets.append(target)
		_shots.call("add_target", target, 6.0, ManagerScript.LAYER_ENEMY)
		var homing: int = _shots.call("spawn", player, Vector2(x, 110.0), Vector2(0.0, -speed), 2.0, float(BOLT.get("radius"))) as int
		_shots.call("set_homing", homing, 9.0, 200.0)
		_dress(homing, tint, look)
		var bounce: int = _shots.call("spawn", player, Vector2(x + 10.0, 200.0), Vector2(speed * 0.35, -speed), 2.0, float(BOLT.get("radius")), 0) as int
		_shots.call("set_bounce", bounce, 1)
		_dress(bounce, tint, look)
		_shots.call("set_anchor", dashers[e], _dash_point(e, 0.0))
		_shots.call("follow_caster", dashers[e], tint, look, 0.3)
	for n in STEPS:
		await physics_frame
		for e in 6:
			_shots.call("set_anchor", dashers[e], _dash_point(e, float(n + 1) / 18.0))
	var image: Image = await grab()
	var drawn: int = int(_shots.get("drawn")) + int(_shots.get("drawn_trails"))
	if drawn < 12:
		fail("only %d trails were drawn" % drawn)
		return
	save(image, "trails")
	save_crop(image, Vector2(160.0, 110.0), "trails_4x", Vector2i(160, 100))


## The casters' actor ids, opened in the `Actors` table: four seated wizards, then two enemies.
func _casters() -> Array[int]:
	var table: ActorsScript = ActorSeats.autoload()
	var casters: Array[int] = []
	for id in ActorSeats.seat_wizards(table):
		casters.append(id)
	casters.append(ActorSeats.enemy(table))
	casters.append(ActorSeats.enemy(table))
	return casters


## Where dasher `e` is `t` of the way through its dash: a quarter circle, as a wizard that dashes
## while it walks round.
func _dash_point(e: int, t: float) -> Vector2:
	var centre := Vector2(30.0 + e * COLUMN, 330.0)
	var angle: float = PI + minf(t, 1.0) * PI * 0.5
	return centre + Vector2(cos(angle), sin(angle)) * Vector2(-70.0, 70.0)


func _dress(slot: int, tint: Color, look: int) -> void:
	_shots.call("set_core", slot, tint)
	_shots.call("set_look", slot, look)

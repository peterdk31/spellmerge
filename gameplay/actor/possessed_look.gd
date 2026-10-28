class_name PossessedLook
extends ActorLook
## What a possession shows over the possessed actor (actors G9; owner, 2026-10-28), so "that imp
## is player 2's now, for 2 more seconds" reads at a glance while the corner panel stays the
## player's own wizard:
##
## - **The timer**, always: a small ring just above the character (a 32 px cell) in the style of
##   the wizard's revive ring: a dark outline, a Stone back ring and an arc for the time left in
##   the light shade of the driver's colour (`Possession.driver_ramp`: the seat's hat colour, or
##   the caster body's ramp for an AI driver), sweeping clockwise from the top.
## - **Its health and mana**, when a seat drives an actor that is not its own wizard (`shows_bars`):
##   two small bars beside the timer, health in Fire and mana in Spark on a Stone trough with a
##   1 px outline, the colours of the corner panel's bars (docs/STYLE.md). A wizard an enemy's AI
##   drives shows only the timer: its numbers are on its player's panel.
##
## The actor's own look and spell colours stay as they are. Made by the possession and taken off
## when it ends (`Actor.add_look`, `remove_look`); it redraws only when the arc moves a step
## (ARC_STEPS) or a bar a pixel, and allocates nothing per step.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The bottom of the overlay above the feet: just over a 32 px character.
const TOP: float = -31.0
## The timer ring: radius, and the widths of its outline, back ring and arc.
const RING_RADIUS: float = 4.0
const OUTLINE_WIDTH: float = 4.0
const RING_WIDTH: float = 2.0
## The arc of the time left is redrawn in this many steps over the whole possession.
const ARC_STEPS: int = 24
const POINTS: int = 16
## The bars: inner width, each bar's height, and the gap between the ring and the bars.
const BAR_WIDTH: int = 16
const BAR_HEIGHT: int = 2
const BAR_GAP: float = 2.0
## docs/STYLE.md: Outline, Stone shadow and base, Fire base (health), Spark base (mana).
const OUTLINE_COLOR: Color = Color("14121f")
const TROUGH_COLOR: Color = Color("2b2840")
const RING_BACK_COLOR: Color = Color("4a4663")
const HEALTH_COLOR: Color = Color("e0592f")
const MANA_COLOR: Color = Color("f2c230")

## The possession it shows (set before it is added).
var possession: Possession = null

var _drawn_steps: int = -1
## The pixels of each bar drawn (-1: no bars).
var _drawn_health: int = -1
var _drawn_mana: int = -1


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	_drawn_steps = -1
	_drawn_health = -1
	_drawn_mana = -1


func step(_delta: float) -> void:
	if possession == null or possession.seconds <= 0.0:
		return
	var steps: int = arc_steps()
	var health_px: int = -1
	var mana_px: int = -1
	if shows_bars():
		health_px = health_pixels()
		mana_px = mana_pixels()
	if steps != _drawn_steps or health_px != _drawn_health or mana_px != _drawn_mana:
		_drawn_steps = steps
		_drawn_health = health_px
		_drawn_mana = mana_px
		queue_redraw()


## True when the bars show: a seat drives this actor and it is not that seat's own wizard.
func shows_bars() -> bool:
	if possession == null or actor == null or not is_instance_valid(possession.driver):
		return false
	return possession.driver.seat >= 0 and actor.home_controller != possession.driver


## True once a step has drawn the bars (for tests: what the last redraw shows).
func draws_bars() -> bool:
	return _drawn_health >= 0


## The steps of the timer's arc drawn (ARC_STEPS at the start, 0 at the end; -1 before a step).
func drawn_steps() -> int:
	return _drawn_steps


## The steps of the timer's arc left (ARC_STEPS at the start, 0 at the end).
func arc_steps() -> int:
	if possession == null or possession.seconds <= 0.0:
		return 0
	return ceili(possession.left / possession.seconds * float(ARC_STEPS))


## The health bar's filled pixels (0 to BAR_WIDTH); a hurt actor shows at least one until 0.
func health_pixels() -> int:
	if actor == null or actor.health == null or actor.health.max_health <= 0:
		return 0
	return _pixels(float(actor.health.health) / float(actor.health.max_health))


## The mana bar's filled pixels (0 to BAR_WIDTH).
func mana_pixels() -> int:
	if actor == null or actor.caster == null or actor.caster.max_mana <= 0.0:
		return 0
	return _pixels(actor.caster.mana / actor.caster.max_mana)


func _pixels(share: float) -> int:
	if share <= 0.0:
		return 0
	return clampi(floori(share * float(BAR_WIDTH)), 1, BAR_WIDTH)


func _draw() -> void:
	if actor == null or possession == null:
		return
	# The ring's reach (its outline included); its centre sits that far over TOP.
	var reach: float = RING_RADIUS + OUTLINE_WIDTH * 0.5
	var ring_centre := Vector2(0.0, TOP - reach)
	if _drawn_health >= 0:
		# The ring and an outlined box of the two bars side by side, centred together over the
		# actor, the box level with the ring.
		var box_width: float = float(BAR_WIDTH + 2)
		var box_height: float = float(BAR_HEIGHT * 2 + 2)
		var left: float = roundf(-(reach * 2.0 + BAR_GAP + box_width) * 0.5)
		ring_centre.x = left + reach
		var box_left: float = left + reach * 2.0 + BAR_GAP
		var box_top: float = ring_centre.y - box_height * 0.5
		draw_rect(Rect2(box_left, box_top, box_width, box_height), OUTLINE_COLOR)
		draw_rect(Rect2(box_left + 1.0, box_top + 1.0, float(BAR_WIDTH), float(BAR_HEIGHT * 2)), TROUGH_COLOR)
		if _drawn_health > 0:
			draw_rect(Rect2(box_left + 1.0, box_top + 1.0, float(_drawn_health), float(BAR_HEIGHT)), HEALTH_COLOR)
		if _drawn_mana > 0:
			draw_rect(Rect2(box_left + 1.0, box_top + 1.0 + float(BAR_HEIGHT), float(_drawn_mana), float(BAR_HEIGHT)), MANA_COLOR)
	# The timer: like the wizard's revive ring, in the driver's colour.
	var colour: Color = ProjectilesScript.ramp_light(possession.driver_ramp())
	draw_arc(ring_centre, RING_RADIUS, 0.0, TAU, POINTS, OUTLINE_COLOR, OUTLINE_WIDTH)
	draw_arc(ring_centre, RING_RADIUS, 0.0, TAU, POINTS, RING_BACK_COLOR, RING_WIDTH)
	var share: float = clampf(float(maxi(_drawn_steps, 0)) / float(ARC_STEPS), 0.0, 1.0)
	if share > 0.0:
		draw_arc(ring_centre, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * share, POINTS, colour, RING_WIDTH)

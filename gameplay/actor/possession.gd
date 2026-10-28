class_name Possession
extends RefCounted
## One possession (actors G9, docs/milestones/M2-actors.md, "Possess (a card)"): the controller
## of the body that cast `possess` (`by`) drives the actor its carrier hit (`target`) for
## `seconds`. The rule, in full:
##
## - **It starts** (`begin`, when the target hears `possess_requested`): an older possession of
##   the target ends first. Then the caster body's controller (`driver`) drives the target
##   (`Actor.drive`, which takes it off the caster's body: that body stands with no controller,
##   can be hit, and keeps its home team), and the target's own controller is put aside
##   (`ActorController.set_aside`; a seat's panel goes on showing its own wizard). Team and seat
##   follow the driver into the actor table on both bodies. Nothing starts when either body is
##   down, dying or out of the tree, or when the caster's body has no controller.
## - **It ends** (`end`) when its time is up, when the target dies or is down, or when the
##   caster's body is down or dies: the target gets its own controller back (`started`: an AI
##   picks a fresh target and winds up again), and the driver goes home to the caster's body. When
##   someone else possesses that body meanwhile, the driver waits behind that possession and comes
##   back when it ends.
## - **Nested:** a driver who possesses again from a possessed body moves on (`newer`); ending a
##   possession first ends the newer ones of its driver, so they unwind in order.
##
## The target keeps its possession in `Actor.possessed_by` and steps it (`step`); the caster's body
## lists those it cast in `Actor.possessions_cast`, so its death ends them. `possess_started` and
## `possess_ended` (the caster's and the target's actor ids) tell Feel. A ring in the driver's
## colour with the time left (`PossessedLook`) is drawn round the target while it lasts, and over
## an actor a seat drives that is not its own wizard, its health and mana too. A builder never
## edits the target: a seat's builder edits its own wizard (owner, 2026-10-28).

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## The controller that drives the target, the body it came from, and the actor it drives.
var driver: ActorController = null
var by: Actor = null
var target: Actor = null
## The target's own controller, put aside meanwhile (null when it had none).
var put_aside: ActorController = null
## Its whole length and the seconds left.
var seconds: float = 0.0
var left: float = 0.0
## The driver's possession it moved on from (whose target is `by`), and the one it moved on to.
var older: Possession = null
var newer: Possession = null
var ended: bool = false
## The ids at the start (sent with `possess_ended` even when a body is gone).
var by_id: int = -1
var target_id: int = -1

var _look: PossessedLook = null


## `by`'s controller takes `target` for `seconds`. Returns the possession, or null when none
## started (see the class doc).
static func begin(by_body: Actor, target_body: Actor, length: float) -> Possession:
	if by_body == target_body or length <= 0.0 or not can_start(by_body) or not can_start(target_body):
		return null
	var taker: ActorController = by_body.controller
	if taker == null:
		return null
	# A newer possession of an actor ends the older first.
	if target_body.possessed_by != null:
		target_body.possessed_by.end()
	# Ending it may have moved controllers: the caster must still be driven by the same one.
	if taker.driving != by_body or not can_start(by_body) or not can_start(target_body):
		return null
	var possession := Possession.new()
	possession.driver = taker
	possession.by = by_body
	possession.target = target_body
	possession.put_aside = target_body.controller
	possession.seconds = length
	possession.left = length
	possession.by_id = by_body.id
	possession.target_id = target_body.id
	var from: Possession = by_body.possessed_by
	if from != null and not from.ended and from.driver == taker:
		possession.older = from
		from.newer = possession
	target_body.possessed_by = possession
	by_body.possessions_cast.append(possession)
	target_body.drive(taker)
	if possession.put_aside != null:
		possession.put_aside.set_aside(target_body, length)
	possession._look = PossessedLook.new()
	possession._look.possession = possession
	target_body.add_look(possession._look)
	if target_body.events != null:
		target_body.events.possess_started.emit(possession.by_id, possession.target_id)
	return possession


## True when `body` may take part in a new possession: in the tree, not dying, not down.
static func can_start(body: Actor) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_leaving() and not body.is_dying() and not body.is_down()


## True when a controller can be handed to `body`: in the tree and not dying (down is fine: a
## downed wizard's seat comes back to it).
static func can_hold(body: Actor) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_leaving() and not body.is_dying()


## Count `delta` seconds; end when the time is up or a body is down or gone. The target calls it
## each step, before its controller thinks.
func step(delta: float) -> void:
	if ended:
		return
	left = maxf(left - delta, 0.0)
	if left <= 0.0 or should_end():
		end()


## True when a body is down, dying or gone.
func should_end() -> bool:
	return not can_start(target) or not can_start(by)


## End it now (once): the newer possessions of its driver first, then the target gets its own
## controller and staffs back and the driver goes home (see the class doc).
func end() -> void:
	if ended:
		return
	ended = true
	if newer != null:
		newer.end()
	if older != null and older.newer == self:
		older.newer = null
	if is_instance_valid(by):
		by.possessions_cast.erase(self)
	var aside: ActorController = put_aside if is_instance_valid(put_aside) else null
	if is_instance_valid(target):
		if target.possessed_by == self:
			target.possessed_by = null
		if _look != null:
			target.remove_look(_look)
		if can_hold(target):
			target.drive(aside)
		elif target.controller == driver:
			target.drive(null)
	_look = null
	if is_instance_valid(driver) and driver.driving == null and can_hold(by):
		var holder: Possession = by.possessed_by
		if holder != null and not holder.ended and holder.driver != driver:
			# Someone else drives the body now: the driver waits behind that possession.
			holder.put_aside = driver
			driver.set_aside(by, holder.left)
		else:
			by.drive(driver)
	var bus: EventsScript = null
	if is_instance_valid(by):
		bus = by.events
	elif is_instance_valid(target):
		bus = target.events
	if bus != null and is_instance_valid(bus):
		bus.possess_ended.emit(by_id, target_id)


## The ramp of the driver's colour: its seat's, else the caster body's.
func driver_ramp() -> int:
	if is_instance_valid(driver) and driver.seat >= 0:
		return driver.seat
	return by.ramp if is_instance_valid(by) else ActorsScript.RAMP_ENEMY


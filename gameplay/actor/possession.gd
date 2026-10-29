class_name Possession
extends RefCounted
## One possession (actors G9, docs/milestones/M2-actors.md, "Possess (a card)"): a controller
## (`driver`) possesses the actor a carrier of its body hit (`target`) for `seconds`. The rule, in
## full (owner, 2026-10-29):
##
## - **Each hit** possesses the actor it hits (`begin`, when the target hears `possess_requested`).
##   The driver is the controller of the body that cast it (its home controller while it stands
##   empty), or that controller's leader when it is a puppet (`ActorController.leader`). Nothing
##   starts on the driver's own home body, on a body it drives or already possesses, when either
##   body is down, dying or out of the tree, or when the caster's body has no controller at all.
## - **The newest possession of a body holds it:** an older possession of the target (another
##   driver's) ends first.
## - **A controller drives the oldest body it possesses** (`ActorController.possessions`, oldest
##   first); each other one is driven by a `PuppetController` that copies its intent. The target's
##   own controller is put aside (`ActorController.set_aside`; a seat's panel goes on showing its
##   own wizard). Team and seat follow the driver into the actor table; a puppet is no seat.
## - **It ends** (`end`) when its time is up or the target dies or is down: the target gets its
##   own controller back (`started`: an AI picks a fresh target and winds up again). When the
##   driver was in it, it moves into its next oldest possession; with none left it goes home to
##   its home body, or, while another controller possesses that body, waits behind that
##   possession (it is put aside there) and comes back when it ends. A controller whose home body
##   died has no home: it is freed when its last possession ends.
##
## The target keeps its possession in `Actor.possessed_by` and steps it (`step`). `possess_started`
## and `possess_ended` (`by_id` and the target's id) tell Feel. A ring in the driver's
## colour with the time left (`PossessedLook`) is drawn round the target while it lasts, and over
## an actor a seat possesses that is not its own wizard, its health and mana too. A builder never
## edits the target: a seat's builder edits its own wizard (owner, 2026-10-28).

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## The controller that possesses the target, and the actor it possesses.
var driver: ActorController = null
var target: Actor = null
## The target's own controller, put aside meanwhile (null when it had none).
var put_aside: ActorController = null
## The puppet driving the target while the driver drives an older body (null while it drives it).
var puppet: PuppetController = null
## Its whole length and the seconds left.
var seconds: float = 0.0
var left: float = 0.0
var ended: bool = false
## The ids at the start: the driver's home body (the body that cast it when it has none) and the
## target (sent with `possess_ended` even when a body is gone).
var by_id: int = -1
var target_id: int = -1

var _look: PossessedLook = null


## The controller of `by_body` (or its leader) possesses `target_body` for `seconds`. Returns the
## possession, or null when none started (see the class doc).
static func begin(by_body: Actor, target_body: Actor, length: float) -> Possession:
	if by_body == target_body or length <= 0.0 or not can_start(by_body) or not can_start(target_body):
		return null
	# A body standing empty (its controller is away possessing) casts for its home controller.
	var by: ActorController = by_body.controller if by_body.controller != null else by_body.home_controller
	if by == null or not is_instance_valid(by):
		return null
	var taker: ActorController = by.leader()
	if target_body.home_controller == taker or target_body.controller == taker or taker.possesses(target_body):
		return null
	# The newest possession of a body holds it: another driver's older one ends first.
	if target_body.possessed_by != null:
		target_body.possessed_by.end()
	if not is_instance_valid(taker) or not can_start(target_body):
		return null
	var possession := Possession.new()
	possession.driver = taker
	possession.target = target_body
	possession.put_aside = target_body.controller
	possession.seconds = length
	possession.left = length
	possession.by_id = taker.home_actor.id if is_instance_valid(taker.home_actor) else by_body.id
	possession.target_id = target_body.id
	target_body.possessed_by = possession
	taker.possessions.append(possession)
	if taker.possessions.size() == 1:
		# Its first: the driver moves in, and the body it drove stands.
		target_body.drive(taker)
	else:
		possession.puppet = PuppetController.new()
		possession.puppet.name = "Puppet"
		possession.puppet.leader_controller = taker
		possession.puppet.team = taker.team
		target_body.add_child(possession.puppet)
		target_body.drive(possession.puppet)
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


## Count `delta` seconds; end when the time is up or the target is down or gone. The target calls
## it each step, before its controller thinks.
func step(delta: float) -> void:
	if ended:
		return
	left = maxf(left - delta, 0.0)
	if left <= 0.0 or not can_start(target):
		end()


## End it now (once): the target gets its own controller back, and the driver moves on to its next
## oldest possession, or home (see the class doc).
func end() -> void:
	if ended:
		return
	ended = true
	var bus: EventsScript = target.events if is_instance_valid(target) else null
	var was_in: bool = is_instance_valid(driver) and driver.driving == target
	if is_instance_valid(driver):
		driver.possessions.erase(self)
	var aside: ActorController = put_aside if is_instance_valid(put_aside) else null
	if is_instance_valid(target):
		if target.possessed_by == self:
			target.possessed_by = null
		if _look != null:
			target.remove_look(_look)
		if can_hold(target):
			target.drive(aside)
		elif target.controller == driver or (puppet != null and target.controller == puppet):
			target.drive(null)
	_look = null
	_free_puppet()
	if was_in:
		Possession.move_on(driver)
	if bus != null and is_instance_valid(bus):
		bus.possess_ended.emit(by_id, target_id)


## `driver` drives nothing: it moves into its oldest possession, or goes home (see the class doc).
static func move_on(driver: ActorController) -> void:
	if not is_instance_valid(driver) or driver.driving != null:
		return
	if not driver.possessions.is_empty():
		var next: Possession = driver.possessions[0]
		next.target.drive(driver)
		next._free_puppet()
		return
	var home: Actor = driver.home_actor
	if not can_hold(home):
		if home == null or not is_instance_valid(home) or home.is_dying():
			# Its body died meanwhile: nothing to come home to.
			driver.queue_free()
		return
	var holder: Possession = home.possessed_by
	if holder != null and not holder.ended and holder.driver != driver:
		# Another controller possesses the body: the driver waits behind that possession.
		holder.put_aside = driver
		driver.set_aside(home, holder.left)
	else:
		home.drive(driver)


## The ramp of the driver's colour: its seat's, else its home body's.
func driver_ramp() -> int:
	if is_instance_valid(driver) and driver.seat >= 0:
		return driver.seat
	if is_instance_valid(driver) and is_instance_valid(driver.home_actor):
		return driver.home_actor.ramp
	return ActorsScript.RAMP_ENEMY


func _free_puppet() -> void:
	if puppet != null and is_instance_valid(puppet):
		puppet.queue_free()
	puppet = null

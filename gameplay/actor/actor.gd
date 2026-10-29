class_name Actor
extends CharacterBody2D
## An actor (actors G4, docs/milestones/M2-actors.md, "The actor"): anything that acts, a wizard
## or an enemy, as one kind of body built from components. This is the root script of an actor
## scene. A wizard and an enemy differ only in which components they have and which controller
## drives them.
##
## Identity: when the actor is ready (and each time it re-enters the tree) it opens an id in the
## actor table (`core/actors`) with its `ramp` and its driver's team and seat, and closes it when
## it leaves the tree. `id`, `ramp`, `team()` and `seat()` (-1 when no seat drives it). No code may
## assume an id is a seat.
##
## Components: found once in `_ready` among the children, at most one of each kind, none required:
## `health` (Health), `hurtbox` (Hurtbox), `contact` (Contact), `mover` (Mover), `caster`
## (Caster), plus any number of looks (ActorLook) and the first ActorController, its
## `home_controller`. Components reach each other only through the actor, never by node path.
##
## Controllers: `controller` is the one driving it now: its home controller, a guest handed over
## by `drive` (possess, G9), or none. `release` gives the guest back. A controller drives one actor
## at a time: `drive` takes it off the actor it drove before (that one stands with none), so its
## signals are never bound twice and a seat's events only come from the actor it drives. Every
## change of driver tells the actor table the new team and seat at once. With no controller the
## body stands, aims where it last aimed and casts nothing; its team is its home controller's, and
## with none at all `idle_team`.
##
## Possess (G9, `possession.gd`): the actor hears `possess_requested` for its own id and starts a
## `Possession` by the caster's body's controller; it steps the one holding it (`possessed_by`)
## before its controller thinks, and ends it when it dies or leaves the tree. Its home controller's
## possessions end when the body leaves the tree with it; when the body dies, a home controller
## that is away possessing goes on (it moves to the body's parent) until its last one ends.
##
## The body's points: `body_offset` (the hurt circle's centre and the orbit anchor), `aim_pivot()`
## (the hand, `hand_offset` above the feet: the aim, the staff and the shot line up from it),
## `muzzle_position()` (the staff tip, `reach()` from the hand along the aim: the tip of the staff
## on show, else `staff_reach`; an imp's reach is 0, so its spells start at its body) and `aim` (unit length).
##
## The step, in this order: the intent's presses are spent, Health counts its protection down,
## the controller thinks (writes `intent`), the aim follows the intent, the Caster steps (mana,
## anchor and aim to the systems, the casts asked for), the Mover steps (sets `velocity`), the
## Hurtbox follows down and up, the looks step (read only), and a home controller that is away
## (it drives another actor, or another controller drives this one) watches its body
## (`ActorController.watch_home`, read only). `_physics_process` then calls
## `move_and_slide()`. Tests call `step(delta)` with fixed deltas and move the body themselves.
##
## Data: `data` (an `EnemyBase`) is applied to the components in `_ready`, before they are set up:
## health, walking speed, contact damage, staff, cards and mana. Data with no staff or no cards
## leaves the actor without a caster (an enemy that only chases).
##
## Down and out: `is_down()` is true while a Downed component (gameplay/player, G7) holds the actor
## down (`set_down`); `die(killer)` sends the local `died` and frees the actor. When its Health is
## used up the actor dies, unless something downs it instead (`downable`).
##
## Services are the autoloads (`Events`, `Combat`, `Projectiles`, `Spells`, `Actors`), found by
## node path when the actor enters the tree; tests set them before adding the actor. Nothing here
## allocates in `step`.

const EventsScript := preload("res://core/events/events.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

## Physics: an actor is on no body layer and collides only with walls (layer 1), so actors walk
## through each other; spells find it by its hurt circle (the projectile manager), not by physics.
const LAYER_WALLS: int = 1

## The actor died (`die`); `killer` is who landed the last hit (an event's player, or -1).
signal died(killer: int)
## Combat hurt this actor: sent with every `damage_dealt` that names it, right after it, for the
## actor's own components and controller (`by` is the attacker's actor id or -1). Listening here
## instead of on the bus keeps a hit to this actor's listeners: a bus listener per enemy was
## called for every hit on anyone (performance pass, 2026-10-28).
signal damaged(by: int, amount: int)

## The colour ramp of its spells: 0-3 the hat colours, 4 the enemy ramp.
@export var ramp: int = ActorsScript.RAMP_ENEMY
## The team it keeps while no controller drives it and it has no home controller.
@export var idle_team: int = ActorsScript.NONE
## The body: the hurt circle's centre and the orbit anchor, from the feet.
@export var body_offset: Vector2 = Vector2(0.0, -12.0)
## The hand (`aim_pivot`), from the feet: a wizard's is at hand height, a creature's its body.
@export var hand_offset: Vector2 = Vector2(0.0, -12.0)
## The staff tip's distance from the hand along the aim (0: spells start at the hand).
@export var staff_reach: float = 0.0

## The enemy's numbers, applied to the components in `_ready`. Set before adding the actor.
var data: EnemyBase = null

## The event bus, Combat, the projectile manager, the spell runtime and the actor table. Only
## tests set these, before adding the actor; otherwise the autoloads are used.
var events: EventsScript = null
var combat: CombatScript = null
var projectiles: ProjectilesScript = null
var spells: SpellsScript = null
var actors: ActorsScript = null

## Its id in the actor table, or -1 while it has none (out of the tree, or the table full).
var id: int = ActorsScript.NONE
## Where it aims (unit length).
var aim: Vector2 = Vector2.DOWN
## What its controller wants this step; made once, never replaced.
var intent: ActorIntent = ActorIntent.new()
## The controller in its scene (or null), and the one driving it now (or null).
var home_controller: ActorController = null
var controller: ActorController = null
## Its components (null for a kind it does not have).
var health: Health = null
var hurtbox: Hurtbox = null
var contact: Contact = null
var mover: Mover = null
var caster: Caster = null
## True when something downs the actor at 0 health instead of letting it die (a Downed
## component, G7, sets it).
var downable: bool = false
## The possession holding this actor now (another controller possesses it), or null.
var possessed_by: Possession = null

## The number it casts under in Spells and the projectile manager: its `id` while its caster is
## open (see `open_caster_number`), else -1.
var _caster_number: int = -1

var _components: Array[ActorComponent] = []
var _looks: Array[ActorLook] = []
var _is_ready: bool = false
var _down: bool = false
var _dying: bool = false
## True from the moment it starts leaving the tree until it is back.
var _leaving: bool = false


func _init() -> void:
	collision_layer = 0
	collision_mask = LAYER_WALLS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func _enter_tree() -> void:
	_leaving = false
	_find_services()
	_listen()
	if not _is_ready:
		# The first time, `_ready` opens the id once the controller is known.
		return
	_open_id()
	for component in _components:
		component.attach()


func _ready() -> void:
	_find_services()
	_find_components()
	_apply_data()
	for component in _components:
		component.setup(self)
	if health != null and not health.depleted.is_connected(_on_depleted):
		health.depleted.connect(_on_depleted)
	for look in _looks:
		look.setup(self)
	controller = home_controller
	if home_controller != null:
		home_controller.home_actor = self
	_is_ready = true
	_open_id()
	if controller != null:
		controller.driving = self
		controller.started(self)
	for component in _components:
		component.attach()


func _exit_tree() -> void:
	_leaving = true
	_end_possessions()
	if events != null and is_instance_valid(events) and events.possess_requested.is_connected(_on_possess_requested):
		events.possess_requested.disconnect(_on_possess_requested)
	for at in range(_components.size() - 1, -1, -1):
		_components[at].detach()
	_close_id()


func _physics_process(delta: float) -> void:
	step(delta)
	move_and_slide()


## Advance the actor by `delta` seconds and set `velocity` (see the class doc for the order). The
## caller moves the body (`_physics_process` does).
func step(delta: float) -> void:
	# Each component is called only when it has something to do (performance pass, 2026-10-28):
	# a step runs for every actor every frame, and a call costs more than the checks here.
	intent.pressed_bits = 0
	if health != null and health.protecting:
		health.step(delta)
	if possessed_by != null:
		possessed_by.step(delta)
	if controller != null:
		controller.think(self, delta)
	else:
		intent.clear()
	if intent.aim != Vector2.ZERO:
		aim = intent.aim.normalized()
	if caster != null:
		caster.step(delta)
	if mover != null:
		mover.step(delta)
	else:
		velocity = Vector2.ZERO
	if hurtbox != null and hurtbox.registered == _down:
		hurtbox.step()
	for look in _looks:
		look.step(delta)
	if home_controller != null and home_controller != controller:
		# Its own controller is away (it drives another actor, or another drives this one): it
		# still watches its body (a seat's panel shows its own wizard; owner, 2026-10-28).
		home_controller.watch_home(self, delta)


## Whom it aims at: its driver's team (its home controller's while none drives it).
func team() -> int:
	var by: ActorController = controller if controller != null else home_controller
	return by.team if by != null else idle_team


## The human seat (0-3) driving it now, or -1.
func seat() -> int:
	return controller.seat if controller != null else ActorsScript.NONE


## Hand the actor to `guest` (a controller from elsewhere: possess), or to nobody with null. The
## controller driving it until now stops; the intent starts empty. A guest still driving another
## actor is taken off it first (that actor stands with no controller), so no controller ever
## drives two bodies.
func drive(guest: ActorController) -> void:
	if guest == controller:
		return
	if guest != null and is_instance_valid(guest.driving) and guest.driving != self:
		guest.driving.drive(null)
	if controller != null:
		var before: ActorController = controller
		controller = null
		if is_instance_valid(before):
			before.stopped(self)
			if before.driving == self:
				before.driving = null
	controller = guest
	intent.clear()
	if controller != null:
		controller.driving = self
		controller.started(self)
	_tell_driver()


## Give a guest controller back: the home controller drives again.
func release() -> void:
	drive(home_controller)


## The hand: the point the aim, the staff and the shot line up from.
func aim_pivot() -> Vector2:
	return global_position + hand_offset


## Where spells start: the staff tip, `reach()` from the hand along the aim.
func muzzle_position() -> Vector2:
	return aim_pivot() + aim * reach()


## The staff tip's distance from the hand: the tip of the staff on show (`Caster.tip`, living
## staffs H3), or `staff_reach` when that staff names none.
func reach() -> float:
	var tip: float = caster.tip() if caster != null else 0.0
	return tip if tip > 0.0 else staff_reach


## The number it casts under in Spells and the projectile manager, -1 for none.
func caster_number() -> int:
	return _caster_number


## Open its caster in Spells (the Caster does, when the actor enters the tree) and return the
## number it casts under: its `id`, since Spells and the projectile manager cast by actor id
## (actors G3b); -1 when it has no id (a full table) or no Spells.
func open_caster_number() -> int:
	if _caster_number >= 0 or spells == null or id == ActorsScript.NONE:
		return _caster_number
	if spells.open_caster(id):
		_caster_number = id
	return _caster_number


## Close its caster in Spells (the actor leaves the tree): its staffs, holds and beams end.
func close_caster_number() -> void:
	if _caster_number >= 0 and spells != null and is_instance_valid(spells):
		spells.close_caster(_caster_number)
	_caster_number = -1


## True while the actor is down (a Downed component holds it; G7).
func is_down() -> bool:
	return _down


## Down (`on`) or standing again. Called by the Downed component.
func set_down(on: bool) -> void:
	_down = on


## The name the old wizard slots asked by (`is_down`); the AI's target check and the bots still
## ask it.
func is_downed() -> bool:
	return _down


## The actor is dead: the possession holding it ends, a home controller that is away possessing
## goes on without it, and it sends `died` and frees itself (once).
func die(killer: int) -> void:
	if _dying:
		return
	_dying = true
	if possessed_by != null:
		possessed_by.end()
	var away: ActorController = home_controller
	if away != null and away.get_parent() == self and not away.possessions.is_empty() and get_parent() != null:
		# Its possessions go on (owner, 2026-10-29): the controller leaves the body before it is
		# freed, and is freed itself when its last possession ends (`Possession.move_on`).
		away.reparent(get_parent())
	died.emit(killer)
	queue_free()


## True once `die` was called.
func is_dying() -> bool:
	return _dying


## True while it leaves the tree (its `_exit_tree` runs).
func is_leaving() -> bool:
	return _leaving


## Step and draw `look` from now on (a look made while the game runs: the possession ring). It
## is added as a child.
func add_look(look: ActorLook) -> void:
	if look == null or _looks.has(look):
		return
	look.setup(self)
	add_child(look)
	_looks.append(look)


## Stop stepping `look` and free it.
func remove_look(look: ActorLook) -> void:
	if look == null:
		return
	_looks.erase(look)
	if is_instance_valid(look):
		look.queue_free()


## The controller of the actor `caster` takes this actor (`possess_requested` for this id).
func _on_possess_requested(caster: int, target: int, seconds: float, _tag: int) -> void:
	if target != id or id == ActorsScript.NONE or actors == null:
		return
	var by: Actor = actors.node_of(caster) as Actor
	if by != null:
		Possession.begin(by, self, seconds)


## The body leaves the tree: the possession holding it ends, and so do its home controller's when
## that controller leaves with it.
func _end_possessions() -> void:
	if possessed_by != null:
		possessed_by.end()
	if home_controller != null and is_instance_valid(home_controller) and home_controller.get_parent() == self:
		home_controller.end_possessions()


func _listen() -> void:
	if events != null and not events.possess_requested.is_connected(_on_possess_requested):
		events.possess_requested.connect(_on_possess_requested)


func _on_depleted(killer: int) -> void:
	if not downable:
		die(killer)


## The autoloads, for every service a test did not set (absolute paths only work in the tree).
func _find_services() -> void:
	if not is_inside_tree():
		return
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectilesScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if actors == null:
		actors = get_node_or_null("/root/Actors") as ActorsScript


## Each kind of component once (the first child of its kind), the looks, the home controller.
func _find_components() -> void:
	_components.clear()
	_looks.clear()
	for child in get_children():
		if child is ActorController:
			if home_controller == null:
				home_controller = child as ActorController
		elif child is ActorLook:
			_looks.append(child as ActorLook)
		elif child is Health:
			health = _first(health, child) as Health
		elif child is Hurtbox:
			hurtbox = _first(hurtbox, child) as Hurtbox
		elif child is Contact:
			contact = _first(contact, child) as Contact
		elif child is Mover:
			mover = _first(mover, child) as Mover
		elif child is Caster:
			caster = _first(caster, child) as Caster
		elif child is ActorComponent:
			# A kind the kit does not name (the wizard's Downed): stepped by nobody, attached too.
			_components.append(child as ActorComponent)
	# Set up and attached in this order: health first, the caster last (it names the hurtbox).
	var ordered: Array[ActorComponent] = [health, hurtbox, contact, mover, caster]
	var at: int = 0
	for component in ordered:
		if component != null:
			_components.insert(at, component)
			at += 1


## `found` if there is one already (a second of a kind is left alone, with a warning), else `child`.
func _first(found: ActorComponent, child: Node) -> ActorComponent:
	if found != null:
		push_warning("Actor %s: a second %s is ignored." % [name, child.name])
		return found
	return child as ActorComponent


## The enemy's numbers to its components. Without a staff and cards the caster is left out.
func _apply_data() -> void:
	if data == null:
		return
	if health != null:
		health.max_health = data.max_health
	if mover != null:
		mover.speed = data.move_speed
	if contact != null:
		contact.damage = data.contact_damage
	if caster == null:
		return
	if data.staff == null or data.cards.is_empty():
		_components.erase(caster)
		caster = null
		return
	caster.staff_count = 1
	caster.staff = data.staff
	caster.start_cards = [data.cards]
	caster.max_mana = data.max_mana
	caster.regen = data.mana_regen


func _open_id() -> void:
	if actors == null or id != ActorsScript.NONE:
		return
	id = actors.open(team(), ramp, seat())
	if id == ActorsScript.NONE:
		push_warning("Actor %s: the actor table is full, so this actor has no id." % name)
		return
	actors.set_node(id, self)
	# The seat whose own body it is (a wizard): the HUD finds it there while it is away.
	if home_controller != null:
		actors.set_home(id, home_controller.seat)


func _close_id() -> void:
	if id != ActorsScript.NONE and actors != null and is_instance_valid(actors):
		actors.close(id)
	id = ActorsScript.NONE


## The actor table hears of a change of driver: the new team and seat.
func _tell_driver() -> void:
	if actors != null and id != ActorsScript.NONE:
		actors.set_driver(id, team(), seat())

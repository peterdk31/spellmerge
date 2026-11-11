class_name Actor
extends Node2D
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
## (Caster), `footprint` (Footprint: the ground it stands on; the actor adds one with the default
## circle when its scene has none, so every actor has one), plus any number of looks (ActorLook)
## and the first ActorController, its `home_controller`. Components reach each other only through the actor, never by node path.
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
## (`ActorController.watch_home`, read only). The tick then moves the body by its `velocity`
## (`move`). Tests call `step(delta)` with fixed deltas and move the body themselves.
##
## Still (props W2, docs/milestones/props.md): a body that no controller drives and that has no
## Mover is still. Nothing it does changes from tick to tick, so the Tick never steps it
## (`Actors.still`, set when its id opens and at every change of driver, `_tell_driver`): a prop.
## Hits still land on it (Combat writes its health and statuses), its casts still go (a reaction's,
## or a possessor's: a possession gives it a driver, and it is stepped while that lasts), and a
## slowed actor's wind-ups are held back by Combat, not by its step. What only a step does is not
## done for it: its pools do not refill, and it takes no hit-stop hold or protection.
##
## Resting (props W2): the state hash sums up a still body that is as it was made as a few values
## (`rest_leaf`): its health full, not down, dying or leaving, and every component as made
## (`ActorComponent.at_rest`, false unless a component says). Only the hash does; a snapshot saves
## every body whole.
##
## The move (online-ready N6): `move(delta)` slides the body, its footprint's circle (`wall_radius`),
## along the walls (the room's, the solid shots' and the footprints', the projectile manager's
## wall grid, `ProjectileManager.slide_body`), the same to the bit on every machine; `velocity` is then what it
## moved by over the step, so a body against a wall keeps only its slide. Actors walk through each
## other (Combat's push parts them); spells find them by their hurt circles. No physics engine.
##
## Data: `data` (an `EnemyBase`) is applied to the components in `_ready`, before they are set up:
## health, walking speed, contact damage, staff, cards and mana. Data with no staff or no cards
## leaves the actor without a caster (an enemy that only chases).
##
## Local stop: while `Actors.hold(id, seconds)` holds it (Feel's hit-stop, which holds only the
## bodies in a hit), `step` does nothing and the body stands still; its looks step once at the
## start (no time passing), so the stop shows the moment of the hit.
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

## The actor died (`die`); `killer` is who landed the last hit (an event's player, or -1).
signal died(killer: int)
## Combat hurt this actor: sent with every `damage_dealt` that names it, right after it, for the
## actor's own components and controller (`by` is the attacker's actor id or -1). Listening here
## instead of on the bus keeps a hit to this actor's listeners: a bus listener per enemy was
## called for every hit on anyone (performance pass, 2026-10-28).
signal damaged(by: int, amount: float)

## Not state: services, caches and scratch, set up again (core/sim/README.md); its components' list,
## found again from its children (`_find_components`; each component is walked as its member).
const DERIVED: Array[StringName] = [&"events", &"combat", &"projectiles", &"spells", &"actors", &"sim", &"_components"]
## Not state: what only the drawing reads and writes (core/sim/README.md).
const VIEW: Array[StringName] = [&"_looks"]
## State as who it points at: the controller driving it now, which may be another body's (a
## possessor's, `possession.gd`). Its own controller's state is walked through `home_controller`,
## and who drives what is the controller's `driving`.
const REFS: Array[StringName] = [&"controller"]

## The colour ramp of its spells: 0-3 the hat colours, 4 the enemy ramp.
@export var ramp: int = ActorsScript.RAMP_ENEMY
## The team it keeps while no controller drives it and it has no home controller: a prop's is
## `Actors.TEAM_WORLD` (props W4).
@export var idle_team: int = ActorsScript.NONE
## The body: the hurt circle's centre and the orbit anchor, from the feet.
@export var body_offset: Vector2 = Vector2(0.0, -12.0)
## The hand (`aim_pivot`), from the feet: a wizard's is at hand height, a creature's its body.
@export var hand_offset: Vector2 = Vector2(0.0, -12.0)
## The staff tip's distance from the hand along the aim (0: spells start at the hand).
@export var staff_reach: float = 0.0

## The enemy's numbers, applied to the components in `_ready`. Set before adding the actor.
var data: EnemyBase = null

## The event bus, Combat, the projectile manager, the spell runtime, the actor table and the game's
## time and chance (`Sim`). Only tests set these, before adding the actor; otherwise the autoloads
## are used (the Tick's sim).
var events: EventsScript = null
var combat: CombatScript = null
var projectiles: ProjectilesScript = null
var spells: SpellsScript = null
var actors: ActorsScript = null
var sim: Sim = null

## Its id in the actor table, or -1 while it has none (out of the tree, or the table full).
var id: int = ActorsScript.NONE
## Where it aims (unit length).
var aim: Vector2 = Vector2.DOWN
## The body's velocity in pixels per second: set by the Mover in `step`, moved by in `move` (which
## leaves what it moved by: along a wall, its slide).
var velocity: Vector2 = Vector2.ZERO
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
var footprint: Footprint = null
## True when something downs the actor at 0 health instead of letting it die (a Downed
## component, G7, sets it).
var downable: bool = false
## The possession holding this actor now (another controller possesses it), or null.
var possessed_by: Possession = null
## The actor whose body this one belongs to (a decoy belongs to its caster), or NONE: that actor's
## shots pass it as they pass its own body (its hurt circle is a projectile target owned by that
## actor: `Caster.own_hurtbox`, Combat). Set before adding the actor.
var belongs_to: int = ActorsScript.NONE

## The number it casts under in Spells and the projectile manager: its `id` while its caster is
## open (see `open_caster_number`), else -1.
var _caster_number: int = -1

var _components: Array[ActorComponent] = []
## A boss's phases (`Phases`), added by the actor when its data has any; null otherwise.
var phases: Phases = null
## The body's scale now (`set_size`; 1 as drawn).
var size: float = 1.0
var _looks: Array[ActorLook] = []
## True once the looks have shown the start of the local stop the body is in (see `step`).
var _hold_shown: bool = false
## Whether the Tick steps this body (core/sim/tick.gd, by actor id): off for a body another
## steps (a decoy: Entities) or a test steps by hand.
var ticking: bool = true
var _is_ready: bool = false
var _down: bool = false
var _dying: bool = false
## True from the moment it starts leaving the tree until it is back.
var _leaving: bool = false


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


## One tick of the body (core/sim/tick.gd steps every actor's body by id): its step, then its move.
func tick_step(delta: float) -> void:
	step(delta)
	move(delta)


## True while no controller drives it and it has no Mover (props W2; see the class doc): the Tick
## does not step it.
func is_still() -> bool:
	return controller == null and mover == null


## The body as a few values for the state hash while it rests (props W2; see the class doc): still,
## its health full, not down, dying or leaving, and every component as it was made
## (`ActorComponent.at_rest`); null otherwise, and the hash walks it member by member. The values
## are what may differ between two bodies made alike: where it stands and aims, its size, the staff
## on show, its health and whether hits take any.
func rest_leaf() -> Variant:
	if _down or _dying or _leaving or not is_still() or possessed_by != null or phases != null:
		return null
	# What a step it took while driven may have left (a possession that ended).
	if _hold_shown or velocity != Vector2.ZERO or intent.pressed_bits != 0 or intent.held_bits != 0:
		return null
	if health != null and health.health != health.max_health:
		return null
	for component in _components:
		if not component.at_rest():
			return null
	return [position, aim, size, ticking, health.health if health != null else -1.0, health.invincible if health != null else false, caster.current if caster != null else -1]


## Move the body by `velocity` for `delta` seconds, sliding along the walls (see the class doc); when
## a wall changed the move, `velocity` is left as what it moved by. A body standing still is moved
## too: a wall laid over it (a Wall card's) pushes it out. A body with no Mover never moves (props
## W4: a prop stands in its own footprint, which would push it out; a possession drives it, and it
## still stands).
func move(delta: float) -> void:
	if delta <= 0.0 or mover == null:
		return
	var from: Vector2 = global_position
	var unhindered: Vector2 = from + velocity * delta
	var to: Vector2 = projectiles.slide_body(from, velocity * delta, wall_radius()) if projectiles != null else unhindered
	global_position = to
	if to != unhindered:
		velocity = (to - from) / delta


## The radius of the body against the walls: its footprint's circle (`Footprint.radius`).
func wall_radius() -> float:
	return footprint.radius if footprint != null else 0.0


## Advance the actor by `delta` seconds and set `velocity` (see the class doc for the order). The
## caller moves the body (`tick_step` does).
func step(delta: float) -> void:
	var full: float = delta
	# Each component is called only when it has something to do (performance pass, 2026-10-28):
	# a step runs for every actor every frame, and a call costs more than the checks here.
	if actors != null and (actors.held_count > 0 or actors.resting_count > 0) and id != ActorsScript.NONE:
		# A local stop (hit-stop in co-op): the body holds still while it lasts; the rest of the
		# game runs on. A step that outlasts it runs for what is left.
		delta = actors.spend_hold(id, delta)
		if delta <= 0.0:
			velocity = Vector2.ZERO
			if not _hold_shown:
				# What stopped it (a hit, a slam's impact) came after its own step, so its looks
				# catch up once: the stop shows that moment, not the step before.
				_hold_shown = true
				for look in _looks:
					look.step(0.0)
			return
	_hold_shown = false
	intent.pressed_bits = 0
	if health != null and health.protecting:
		health.step(delta)
	if phases != null:
		phases.step(delta)
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
		if delta < full:
			# A step a hold covered part of moves the body for what is left of it (online-ready
			# N4): whoever moves it by its velocity moves it that far.
			velocity *= delta / full
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
	return controller.team if controller != null else own_team()


## The team it is on by itself, whoever drives it now: its home controller's, else `idle_team` (a
## prop's is the world's). A possessed enemy's death is still an enemy's (Combat).
func own_team() -> int:
	return home_controller.team if home_controller != null else idle_team


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
	if caster != null:
		# A cast the old driver wound up was its decision: it leaves no more (cast timing).
		caster.cancel_winds()
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


## Where the drawn staff ends behind the hand: `Caster.butt` against the aim from the hand (the
## hand itself without a caster). The whole staff runs from here to `muzzle_position`.
func butt_position() -> Vector2:
	return aim_pivot() - aim * (caster.butt() if caster != null else 0.0)


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
	if target != id or id == ActorsScript.NONE:
		return
	take_possession(caster, seconds)


## The controller of the actor `caster` possesses this actor for `seconds` (`Possession.begin`):
## what `possess_requested` for this id does. Returns the possession, or null when none started.
func take_possession(caster: int, seconds: float) -> Possession:
	if actors == null or id == ActorsScript.NONE:
		return null
	var by: Actor = actors.node_of(caster) as Actor
	return Possession.begin(by, self, seconds) if by != null else null


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
	if sim == null:
		sim = Sim.found(self)


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
		elif child is Footprint:
			footprint = _first(footprint, child) as Footprint
		elif child is ActorComponent:
			# A kind the kit does not name (the wizard's Downed): stepped by nobody, attached too.
			_components.append(child as ActorComponent)
	if footprint == null:
		# Every actor stands on some ground (props W4): one with the default circle when its scene
		# has none, added as a boss's Phases is (a snapshot makes it again before `_ready`).
		footprint = Footprint.new()
		footprint.name = "Footprint"
		# A body hit as a box stands on that box's base (a bench on the ground under it).
		if hurtbox != null and hurtbox.is_box():
			footprint.fit_base(hurtbox.size, hurtbox.offset)
		add_child(footprint)
	# Set up and attached in this order: health first, the caster last (it names the hurtbox).
	var ordered: Array[ActorComponent] = [health, hurtbox, contact, mover, footprint, caster]
	var at: int = 0
	for component in ordered:
		if component != null:
			_components.insert(at, component)
			at += 1


## `found` if there is one already (a second of a kind is left alone, with a warning), else `child`.
## `found` may be `child` itself: a body made again from a snapshot is given its members before its
## `_ready` (core/sim/snapshot.gd).
func _first(found: ActorComponent, child: Node) -> ActorComponent:
	if found != null and found != child:
		push_warning("Actor %s: a second %s is ignored." % [name, child.name])
		return found
	return child as ActorComponent


## The enemy's numbers to its components: health, speed, touch, size and its 1-4 staffs (enemy AI
## AI4, docs/milestones/M2-enemy-ai.md). Without a staff the caster is left out.
func _apply_data() -> void:
	if data == null:
		return
	if health != null:
		health.max_health = data.max_health
	if mover != null:
		mover.speed = data.move_speed
	if contact != null:
		contact.damage = data.contact_damage
	if data.size > 0.0 and not is_equal_approx(data.size, 1.0):
		set_size(data.size)
	if not data.phases.is_empty() and phases == null:
		phases = Phases.new()
		phases.name = "Phases"
		add_child(phases)
		_components.append(phases)
	if caster == null:
		return
	if not data.has_staffs():
		_components.erase(caster)
		caster = null
		return
	var staffs: Array[StaffBase] = []
	var cards: Array = []
	for entry: StaffCards in data.staffs.slice(0, EnemyBase.MAX_STAFFS):
		staffs.append(entry.staff if entry != null else null)
		cards.append(entry.cards.duplicate() if entry != null else [])
	caster.staff_count = staffs.size()
	caster.staffs = staffs
	caster.staff = staffs[0]
	caster.start_cards = cards


## Make the body `factor` times its drawn size (a boss, a boss's phase): the node scales, and the
## points and shapes kept in pixels (hurt shape, body, hand and its footprint) with
## it. A hurt shape already registered is registered again at its new size.
func set_size(factor: float) -> void:
	if factor <= 0.0 or is_equal_approx(factor, size):
		return
	var by: float = factor / size
	size = factor
	scale = Vector2(factor, factor)
	body_offset *= by
	hand_offset *= by
	if footprint != null:
		footprint.scale_by(by)
	if hurtbox != null:
		hurtbox.radius *= by
		hurtbox.size *= by
		hurtbox.offset *= by
		if hurtbox.registered and is_inside_tree():
			hurtbox.detach()
			hurtbox.attach()


func _open_id() -> void:
	if actors == null or id != ActorsScript.NONE:
		return
	id = actors.open(team(), ramp, seat())
	if id == ActorsScript.NONE:
		push_warning("Actor %s: the actor table is full, so this actor has no id." % name)
		return
	actors.set_node(id, self)
	actors.set_still(id, is_still())
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
		actors.set_still(id, is_still())

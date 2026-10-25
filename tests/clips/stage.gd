extends RefCounted
## The stage of one clip (#245): the real spell runtime, projectile manager, combat and Feel,
## fresh for every clip and wired to their own event bus (like `combo_arena.gd`, but with the
## drawing nodes in the scene tree), with a crypt floor, imps and wizards where the scenario
## puts them. Nothing runs by itself: `tick()` moves one physics step (1/60 s) in the order of
## project.godot (projectiles, spells, combat, Feel), so the same scenario gives the same
## frames. Whoever uses it calls `free_all()` afterwards.
##
## Example (see record.gd):
##   var stage := StageScript.new(root, registry)
##   if stage.start(scenario):
##       stage.tick()
##   stage.free_all()

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

const STEP: float = 1.0 / 60.0
const IMP_HEALTH: int = 400
const IMP_RADIUS: float = 10.0
const MANA: float = 100.0
## Feel's hit sprays are CPU particles, which simulate by the real time of each frame, so two
## takes of a clip never agree pixel for pixel, and the pipeline tells a changed clip from an
## unchanged one by its frames. They stay out of the clips until that is solved
## (docs/BACKLOG.md); everything else Feel draws (flashes, names, beams, rings) is in.
const HIT_SPRAYS: bool = false
## The cap on shots, as in the test arena.
const SHOT_CAP: int = 512
## The world the projectile manager draws in.
const BOUNDS: Rect2 = Rect2(-640.0, -400.0, 1280.0, 800.0)
const FLOOR: Texture2D = preload("res://art/tilesets/crypt/floor.svg")
const IMP_ART: Texture2D = preload("res://content/enemies/ember_imp/idle.svg")
const WIZARD_ART: Texture2D = preload("res://content/wizard/base/wizard_idle.svg")
const HATS: Array[Texture2D] = [
	preload("res://content/wizard/base/wizard_hat_p1.svg"),
	preload("res://content/wizard/base/wizard_hat_p2.svg"),
	preload("res://content/wizard/base/wizard_hat_p3.svg"),
	preload("res://content/wizard/base/wizard_hat_p4.svg"),
]
## Sprites stand with their feet on the node, the art is drawn this far above it.
const SPRITE_LIFT: float = 14.0

var bus: EventsScript
var projectiles: ManagerScript
var spells: SpellsScript
var combat: CombatScript
var feel: FeelScript
## The node everything visible hangs under.
var world: Node2D
var camera: Camera2D
var imps: Array[Node2D] = []
## Every reaction_triggered as [player, id, position].
var reactions: Array = []
## Seconds of stage time that have passed.
var time: float = 0.0

var _root: Node
var _registry: Node
var _owned: Array[Object] = []
var _pending: Array[Dictionary] = []
## Where each player stands: {player: Vector2}.
var _anchors: Dictionary = {}


func _init(root: Node, registry: Node) -> void:
	_root = root
	_registry = registry


## Builds the stage for `scenario` (see scenarios.gd). False, with the reason printed, when a
## recipe does not compile.
func start(scenario: Dictionary) -> bool:
	free_all()
	bus = _own(EventsScript.new()) as EventsScript
	projectiles = _own(ManagerScript.new()) as ManagerScript
	projectiles.events = bus
	projectiles.set_cap(SHOT_CAP)
	projectiles.set_bounds(BOUNDS)
	spells = _own(SpellsScript.new()) as SpellsScript
	spells.registry = _registry
	spells.bind(projectiles, bus)
	combat = _own(CombatScript.new()) as CombatScript
	combat.events = bus
	combat.projectiles = projectiles
	combat.spells = spells
	combat.setup()
	bus.reaction_triggered.connect(func(player: int, id: StringName, at: Vector2) -> void: reactions.append([player, id, at]))
	feel = _own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.registry = _registry as RegistryScript
	feel.projectiles = projectiles
	feel.drive_engine = false
	feel.particles_enabled = HIT_SPRAYS
	world = _own(Node2D.new()) as Node2D
	_root.add_child(world)
	world.add_child(_floor())
	camera = Camera2D.new()
	camera.position = centre_of(scenario)
	world.add_child(camera)
	camera.make_current()
	# The drawing nodes enter the tree; nothing steps by itself.
	world.add_child(projectiles)
	world.add_child(feel)
	projectiles.set_physics_process(false)
	projectiles.set_process(false)
	feel.set_process(false)
	for entry: Dictionary in scenario["casts"]:
		var recipe: Dictionary = entry["recipe"] as Dictionary
		var built: CompiledSpell = spells.compile(recipe)
		if not built.valid:
			printerr("CLIP SKIPPED: %s: the recipe does not build: %s" % [scenario["id"], built.reason])
			return false
		spells.install(int(entry["player"]), int(entry["slot"]), built)
		_anchors[int(entry["player"])] = entry["origin"]
	for at: Vector2 in scenario["imps"]:
		_add_imp(at)
	for player: int in _anchors:
		world.add_child(_wizard(player, _anchors[player] as Vector2))
	_pending.assign(scenario["casts"])
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
	return true


## The point the clip is cropped around: the middle of the box round the casters and imps.
static func centre_of(scenario: Dictionary) -> Vector2:
	var low: Vector2 = Vector2.ZERO
	var high: Vector2 = Vector2.ZERO
	var points: Array[Vector2] = []
	points.assign(scenario["imps"])
	for entry: Dictionary in scenario["casts"]:
		points.append(entry["origin"] as Vector2)
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return ((low + high) * 0.5).round()


## Moves one physics step on: the casts that are due, then projectiles, spells, combat, Feel.
func tick() -> void:
	while not _pending.is_empty() and float(_pending[0]["at"]) <= time + STEP * 0.5:
		var entry: Dictionary = _pending.pop_front()
		var origin: Vector2 = entry["origin"] as Vector2
		projectiles.set_anchor(int(entry["player"]), origin)
		spells.cast(int(entry["player"]), int(entry["slot"]), origin, entry["aim"] as Vector2, MANA)
	# Orbits circle their caster's anchor, which has to be current every step, as in the game.
	for player: int in _anchors:
		projectiles.set_anchor(player, _anchors[player] as Vector2)
	projectiles.step(STEP)
	spells.step(STEP)
	combat.step(STEP)
	feel.step(STEP)
	time += STEP


## Writes the shots into the draw batch; call before the frame is drawn.
func update_draw() -> void:
	# The manager draws a shot between its last two steps by the engine's real time since the
	# last physics tick, which no clip can repeat: draw every shot where its last step put it.
	projectiles.update_draw(1.0)


## The ids of the reactions seen, in order.
func reaction_ids() -> Array:
	var ids: Array = []
	for row: Array in reactions:
		ids.append(row[1])
	return ids


## A fingerprint of the simulation so far, for comparing two runs without pixels: the live
## shots, each imp's health and the reactions seen.
func fingerprint() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(projectiles.get_count()))
	for imp in imps:
		parts.append("%s@%s" % [combat.get_health(imp) if is_instance_valid(imp) else -1, imp.global_position if is_instance_valid(imp) else Vector2.ZERO])
	for row: Array in reactions:
		parts.append("%s@%s" % [row[1], row[2]])
	return ",".join(parts)


## Frees everything the stage made.
func free_all() -> void:
	for object in _owned:
		if is_instance_valid(object):
			if object is Node and (object as Node).is_inside_tree():
				(object as Node).get_parent().remove_child(object as Node)
			object.free()
	_owned.clear()
	imps.clear()
	reactions.clear()
	_pending.clear()
	_anchors.clear()
	time = 0.0


func _add_imp(at: Vector2) -> void:
	var imp := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = IMP_ART
	sprite.hframes = 2
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(0.0, -SPRITE_LIFT)
	imp.add_child(sprite)
	world.add_child(imp)
	imp.global_position = at
	combat.register_enemy(imp, IMP_HEALTH, IMP_RADIUS)
	imps.append(imp)


func _wizard(player: int, at: Vector2) -> Node2D:
	var wizard := Node2D.new()
	wizard.position = at
	var body := Sprite2D.new()
	body.texture = WIZARD_ART
	body.hframes = 4
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.position = Vector2(0.0, -SPRITE_LIFT)
	var hat := Sprite2D.new()
	hat.texture = HATS[player % HATS.size()]
	hat.hframes = 4
	hat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(hat)
	wizard.add_child(body)
	return wizard


func _floor() -> Sprite2D:
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(Vector2.ZERO, BOUNDS.size)
	floor_sprite.position = BOUNDS.position
	floor_sprite.z_index = -10
	return floor_sprite


func _own(object: Object) -> Object:
	_owned.append(object)
	return object

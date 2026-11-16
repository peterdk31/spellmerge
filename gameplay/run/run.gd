extends Node
## Run (autoload `Run`): the run's map and the room the party is in (run generation RG3,
## docs/milestones/run-generation.md). A run of rooms begins when Flow says so (`run_begun`, on the
## run's fresh state, its seed dealt): this area makes the run's map once from the run's definition
## (`RUN_FOLDER`, content/runs), the content there is (`Registry.run_content`) and the run's chance
## (`RunGenerator.generate`), and answers with the map's first room and what stands in it
## (`run_room_chosen`: with the kinds of the rooms it leads to), which Flow builds, and how much
## harder it is (`run_room_scaled`, run generation RG5: its depth and the run's players), which
## difficulty scales its enemies by. When the party
## takes a lit exit (`run_way_taken(way)`, run generation RG4), it moves on through the map to the
## room that way links to (`at`, and with it the depth) and names that room the same way. The view
## hears the map as the party sees it (`run_map_changed`, run generation RG8: every room's row, kind
## and links, and where the party is) as it enters each room, empty as a run starts. Areas never
## call each other: Flow knows the run by these events only, and this area knows nothing of a world,
## a body or a scene.
##
## The map is the run's state (`map`, `at`: hashed, saved in snapshots), the same on every machine;
## a joining machine gets it from the snapshot. A run's start renews it (`begin_run`): out of a run
## of rooms (the hub) there is no map.
##
## **Meta progression's hook** (run generation RG6): the map is made by the run definition as the
## run's unlocks change it (`RunDefinition.changed_by`: each `RunRuleChange` whose save flag they
## hold). The unlocks are the run's start's (`Sim.unlocks`, core/sim/run_unlocks.gd): the host's
## save, carried in the replay's header, never this machine's save during a run. This area says
## which they are on this machine (`unlocks_now`, the frames service's unlocks source): the flags of
## this machine's save (`save`) that some run's rule change names, so nothing else of the save
## travels.
##
## A run that cannot be made from the content there is (`Registry.run_problems`, which Flow asks
## before anything goes), or a map its rolls cornered, answers nothing (`RunMap.problems`): Flow
## starts no run, and the warning says why.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FramesScript := preload("res://core/sim/frames.gd")

## The registry folder of the run definitions (content/runs).
const RUN_FOLDER: StringName = &"runs"

## Not state: services (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events", &"registry", &"frames", &"save"]

## The services, and this machine's save (only `unlocks_now` reads it, for a run's start). Only
## tests set these, before adding the node; otherwise the autoloads and the save file are used.
var events: EventsScript = null
var registry: RegistryScript = null
var frames: FramesScript = null
var save: SaveFile = null

## The run's map (null out of a run of rooms) and the room the party is in (its `RunNode.index`;
## -1 for none).
var map: RunMap = null
var at: int = -1


func _ready() -> void:
	# Renewed at every run's start (core/sim/tick.gd, core/sim/sim_area.gd); it takes no step.
	SimArea.join(self, &"Run").renewed_by(begin_run)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if frames == null:
		frames = get_node_or_null("/root/Frames") as FramesScript
	if save == null:
		save = SaveFile.new()
	if frames != null:
		frames.set_unlocks_source(unlocks_now)
	if events == null:
		push_warning("Run: the Events autoload is missing, so no run of rooms can begin.")
		return
	events.run_begun.connect(_on_run_begun)
	events.run_way_taken.connect(_on_run_way_taken)


## A run's start: no map until a run of rooms begins (`run_begun`).
func begin_run() -> void:
	SimFresh.renew(self)
	_tell_map()


## After a snapshot is restored (core/sim/README.md, "Snapshots"): the view hears the restored map,
## so a machine that joined a run in a later room shows it as the others do.
func rebuild_derived() -> void:
	_tell_map()


## The save flags this machine's save has unlocked now (`save`): those some run definition's rule
## change names (`RunDefinition.flags`), so a run's start carries nothing else of the save. The
## frames service asks it at a run's start with no replay on the deck, and as a recording begins.
func unlocks_now() -> RunUnlocks:
	if save == null or registry == null:
		return RunUnlocks.new()
	var named: Array[StringName] = []
	for found: Resource in registry.get_all(RUN_FOLDER):
		var definition: RunDefinition = found as RunDefinition
		if definition != null:
			named.append_array(definition.flags())
	return RunUnlocks.of(save.flags_among(named))


## The room the party is in (null out of a run of rooms).
func room_now() -> RunNode:
	return map.node(at) if map != null else null


## A run of rooms of the definition `run_id` begins (Flow, after the run's start) for `players`
## players: its map is made from the run's seed for them, and the party enters its first room, or
## with a `start_depth` (the hub's lectern, run generation RG7) the first room of the row that depth
## names (`RunMap.start_at`, by the depths the registry's definition offers, as the lectern listed
## them). The map is the same either way: only where the party enters changes.
func _on_run_begun(run_id: StringName, players: int, start_depth: int) -> void:
	map = null
	at = -1
	var definition: RunDefinition = registry.get_resource(RUN_FOLDER, run_id) as RunDefinition if registry != null else null
	if definition == null:
		push_warning("Run: no run '%s' in the registry, so no run of rooms begins." % run_id)
		_tell_map()
		return
	var sim: Sim = Sim.found(self)
	# The rules the run's unlocks leave (the run's start's, never this machine's save now). A
	# definition the content cannot make a map of says so in the map (`RunDefinition.problems`).
	var played: RunDefinition = definition.changed_by(sim.unlocks)
	var made: RunMap = RunGenerator.generate(played, registry.run_content(), sim, players)
	if not made.is_made():
		push_warning("Run: no map for the run '%s': %s" % [run_id, "; ".join(made.problems)])
		_tell_map()
		return
	map = made
	_enter(made.start_at(start_depth, definition.start_depths()))


## The party took the way `way` out of the room it is in (0 = its leftmost link): it enters the room
## that way links to. A way the room has not (no run of rooms, the last room) moves nothing.
func _on_run_way_taken(way: int) -> void:
	var node: RunNode = room_now()
	if node == null or way < 0 or way >= node.links.size():
		push_warning("Run: no way %d out of the room the party is in, so it stays." % way)
		return
	_enter(node.links[way])


## The party enters room `index` of the map: its scale is told (`run_room_scaled`, for difficulty),
## then what Flow builds (`run_room_chosen`), with the kinds of the rooms it leads to, left to right.
func _enter(index: int) -> void:
	at = index
	var node: RunNode = map.node(index)
	var ways: Array[StringName] = []
	for link: int in node.links:
		ways.append(map.node(link).kind)
	_tell_map()
	events.run_room_scaled.emit(node.scale)
	# A copy: what hears it never holds the map's own list.
	events.run_room_chosen.emit(node.room, node.enemies.duplicate(), ways)


## Tell the view the map as the party sees it (`run_map_changed`): each room's row, kind and links,
## in the map's order, and the room the party is in; no rooms and -1 with no map. Copies: what hears
## it never holds the map's own lists.
func _tell_map() -> void:
	if events == null:
		return
	var rows := PackedInt32Array()
	var kinds: Array[StringName] = []
	var links: Array[PackedInt32Array] = []
	if map != null:
		for node: RunNode in map.nodes:
			rows.append(node.row)
			kinds.append(node.kind)
			links.append(node.links.duplicate())
	events.run_map_changed.emit(rows, kinds, links, at if map != null else -1)

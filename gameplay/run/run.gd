extends Node
## Run (autoload `Run`): the run's map and the room the party is in (run generation RG3,
## docs/milestones/run-generation.md). A run of rooms begins when Flow says so (`run_begun`, on the
## run's fresh state, its seed dealt): this area makes the run's map once from the run's definition
## (`RUN_FOLDER`, content/runs), the content there is (`Registry.run_content`) and the run's chance
## (`RunGenerator.generate`), and answers with the map's first room and what stands in it
## (`run_room_chosen`), which Flow builds. Areas never call each other: Flow knows the run by these
## two events only, and this area knows nothing of a world, a body or a scene.
##
## The map is the run's state (`map`, `at`: hashed, saved in snapshots), the same on every machine;
## a joining machine gets it from the snapshot. A run's start renews it (`begin_run`): out of a run
## of rooms (the hub, the sandbox) there is no map.
##
## A run that cannot be made from the content there is (`Registry.run_problems`, which Flow asks
## before anything goes), or a map its rolls cornered, answers nothing (`RunMap.problems`): Flow
## starts no run, and the warning says why.
##
## Next (RG4): the exits, the way on through the map (`at` moving on) and the run's end.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The registry folder of the run definitions (content/runs).
const RUN_FOLDER: StringName = &"runs"

## Not state: services (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events", &"registry"]

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null

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
	if events == null:
		push_warning("Run: the Events autoload is missing, so no run of rooms can begin.")
		return
	events.run_begun.connect(_on_run_begun)


## A run's start: no map until a run of rooms begins (`run_begun`).
func begin_run() -> void:
	SimFresh.renew(self)


## The room the party is in (null out of a run of rooms).
func room_now() -> RunNode:
	return map.node(at) if map != null else null


## A run of rooms of the definition `run_id` begins (Flow, after the run's start): its map is made
## from the run's seed, and its first room is the one the party enters.
func _on_run_begun(run_id: StringName) -> void:
	map = null
	at = -1
	var definition: RunDefinition = registry.get_resource(RUN_FOLDER, run_id) as RunDefinition if registry != null else null
	if definition == null:
		push_warning("Run: no run '%s' in the registry, so no run of rooms begins." % run_id)
		return
	# A definition the content cannot make a map of says so in the map (`RunDefinition.problems`).
	var made: RunMap = RunGenerator.generate(definition, registry.run_content(), Sim.found(self))
	if not made.is_made():
		push_warning("Run: no map for the run '%s': %s" % [run_id, "; ".join(made.problems)])
		return
	map = made
	_enter(0)


## The party enters room `index` of the map: what Flow builds is told (`run_room_chosen`).
func _enter(index: int) -> void:
	at = index
	var node: RunNode = map.node(index)
	# A copy: what hears it never holds the map's own list.
	events.run_room_chosen.emit(node.room, node.enemies.duplicate())

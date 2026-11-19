extends Node
## Run (autoload `Run`): the run's map (run generation RG3, docs/milestones/run-generation.md; a
## biome's map since connected biomes CB8, docs/milestones/connected-biomes.md). A run begins when
## Flow says so (`run_begun`, on the run's fresh state, its seed dealt): this area makes the run's
## biome map once from the run's definition (`RUN_FOLDER`, content/runs), the content there is
## (`Registry.run_content`), its templates' shapes (`Registry.run_shapes`) and the run's chance
## (`BiomeGenerator.generate`), and answers with each room's fight (`run_room_filled`: its enemies,
## its scale, run generation RG5, and the pace they come in at, enemy spawning EA4, worked out from
## its biome's `MapRules.spawning` at its scaled budget), then the map itself (`run_biome_chosen`),
## which Flow lays and plays. Areas never call each other: Flow knows the run by these events only,
## and this area knows nothing of a world, a body or a scene.
##
## The map is the run's state (`map`: hashed, saved in snapshots), the same on every machine; a
## joining machine gets it from the snapshot. A run's start renews it (`begin_run`): out of a run
## (the hub) there is no map.
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
## before anything goes), or a map its templates' shapes left no room for in every try, answers
## nothing (`BiomeMap.not_made`): Flow starts no run, and the warning says why.

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

## The run's biome map (null out of a run).
var map: BiomeMap = null


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
		push_warning("Run: the Events autoload is missing, so no run can begin.")
		return
	events.run_begun.connect(_on_run_begun)


## A run's start: no map until a run begins (`run_begun`).
func begin_run() -> void:
	SimFresh.renew(self)


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


## A run of the definition `run_id` begins (Flow, after the run's start) for `players` players: its
## biome map is made from the run's seed for them, and Flow is told each room's fight
## (`run_room_filled`, room by room) and then the map (`run_biome_chosen`, a copy).
func _on_run_begun(run_id: StringName, players: int) -> void:
	map = null
	var definition: RunDefinition = registry.get_resource(RUN_FOLDER, run_id) as RunDefinition if registry != null else null
	if definition == null:
		push_warning("Run: no run '%s' in the registry, so no run begins." % run_id)
		return
	var sim: Sim = Sim.found(self)
	# The rules the run's unlocks leave (the run's start's, never this machine's save now). A
	# definition the content cannot make a map of says so in the map (`RunDefinition.biome_problems`).
	var played: RunDefinition = definition.changed_by(sim.unlocks)
	var made: BiomeMap = BiomeGenerator.generate(played, registry.run_content(), registry.run_shapes(played), sim, players)
	if not made.is_made():
		push_warning("Run: no map for the run '%s': %s" % [run_id, "; ".join(made.not_made)])
		return
	map = made
	var rules: MapRules = played.biomes[0]
	for room in made.rooms():
		var enemies: Array[StringName] = made.enemies_of(room)
		var scale: float = made.room_scales[room]
		var pace: Array = RoomFill.pace(rules.spawning, RunScaling.scaled_budget(rules.room_budget, scale)) if not enemies.is_empty() else [0, 0, 0.0]
		events.run_room_filled.emit(room, enemies, scale, pace[0], pace[1], pace[2])
	# A copy: what hears it never holds the run's own map.
	events.run_biome_chosen.emit(made.copy())

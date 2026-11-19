extends RefCounted
## A run of one room, for a test that plays a room of its choosing (a run's rooms come from its
## generated biome map: connected biomes CB8, docs/milestones/connected-biomes.md). `pin` registers,
## under ids of their own, a room kind only that room hosts, a copy of the room hosting it (in
## `biome`, its own by default), and a run definition whose biome is its start room alone
## (`MapRules.start_only`) of that kind: the generator lays that room unmirrored at the world's
## origin, and fills it as the game fills any room of the kind (`fill`: the biome's enemies by
## `budget`, or one of its bosses). The party starts in it, so its fight starts with the run. With
## `spawning` (enemy spawning EA4) its enemies come in groups at that pace; with none, all at once.
## Nothing of the game's content changes: what is registered is new, under `PREFIX`.
##
##     var run_id: StringName = PinnedRun.pin(registry, arena)
##     flow.run_id_to_play = run_id   # the run starts in a copy of `arena`, `PinnedRun.room_id(arena)`
##
## A registry made again (a fresh game) has none of it: pin again after.

## What the ids it registers start with.
const PREFIX: String = "pinned_"


## The run of the one room `room` (a copy of it as `room_id(room)`), registered in `registry` (the
## Registry autoload, or one of a test's), and its id. `biome` empty: the room's own (a room of no
## biome needs one whose enemies fill it). Pinned again, the same ids (nothing is added twice).
static func pin(registry: Node, room: RoomBase, biome: StringName = &"", fill: StringName = RoomKind.FILL_ENEMIES, budget: int = 16, spawning: SpawnRules = null) -> StringName:
	var id: StringName = room_id(room, spawning)
	var kind := RoomKind.new()
	kind.id = id
	kind.fill = fill
	registry.call("add", &"room_kinds", kind)
	var copy := room.duplicate() as RoomBase
	copy.id = id
	copy.biome = biome if biome != &"" else room.biome
	copy.kinds = [id] as Array[StringName]
	copy.walkway = false
	registry.call("add", &"rooms", copy)
	var rules := MapRules.new()
	rules.biome = copy.biome
	rules.rooms_min = 0
	rules.rooms_max = 0
	rules.start_kind = id
	rules.room_budget = budget
	rules.spawning = spawning
	var run := RunDefinition.new()
	run.id = id
	run.biomes = [rules] as Array[MapRules]
	registry.call("add", &"runs", run)
	return id


## The id of the copy of `room` a pinned run plays (and of its kind and its run); with `spawning`,
## ids of that pace's own (its numbers in hundredths: two paces closer than that share one, and the
## first pinned is kept).
static func room_id(room: RoomBase, spawning: SpawnRules = null) -> StringName:
	var id: String = PREFIX + String(room.id)
	if spawning != null:
		id += "_paced_%d_%d_%d" % [roundi(spawning.group_share * 100.0), roundi(spawning.refill_share * 100.0), roundi(spawning.stagger * 100.0)]
	return StringName(id)

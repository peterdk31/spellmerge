extends RefCounted
## A run of one room, for a test that plays a room of its choosing (run generation RG3: a run's room
## comes from its generated map, docs/milestones/run-generation.md). `pin` registers, under ids of
## their own, a room kind only that room hosts, a copy of the room hosting it (in `biome`, its own by
## default), and a run definition one row deep whose one room is of that kind: the generator can
## only pick that room, and fills it as the game fills any room of the kind (`fill`: the biome's
## enemies by `budget`, or one of its bosses). With `depth` and `width` (run generation RG4), the run
## is that many rows of copies of the room, every row after the first `width` rooms wide, each room
## leading to every room of the next row (the room needs `width` exits). With `arrivals` (enemy
## arrivals EA4) its rooms' enemies come in groups at that pace; with none, all at once. Nothing of
## the game's content changes: what is registered is new, under `PREFIX`.
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
static func pin(registry: Node, room: RoomBase, biome: StringName = &"", fill: StringName = RoomKind.FILL_ENEMIES, budget: int = 16, depth: int = 1, width: int = 1, arrivals: ArrivalRules = null) -> StringName:
	var id: StringName = room_id(room, depth, width, arrivals)
	var kind := RoomKind.new()
	kind.id = id
	kind.fill = fill
	registry.call("add", &"room_kinds", kind)
	var copy := room.duplicate() as RoomBase
	copy.id = id
	copy.biome = biome if biome != &"" else room.biome
	copy.kinds = [id] as Array[StringName]
	registry.call("add", &"rooms", copy)
	var rules := MapRules.new()
	rules.biome = copy.biome
	rules.depth_min = depth
	rules.depth_max = depth
	rules.width_min = width
	rules.width_max = width
	rules.branches_min = width
	rules.branches_max = width
	rules.room_budget = budget
	rules.arrivals = arrivals
	rules.kinds = [KindRule.make(id, 0, -1)] as Array[KindRule]
	var run := RunDefinition.new()
	run.id = id
	run.biomes = [rules] as Array[MapRules]
	registry.call("add", &"runs", run)
	return id


## The id of the copy of `room` a pinned run of `depth` rows `width` wide plays (and of its kind and
## its run); with `arrivals`, ids of that pace's own (its numbers in hundredths), so two paces never
## share a pinned run.
static func room_id(room: RoomBase, depth: int = 1, width: int = 1, arrivals: ArrivalRules = null) -> StringName:
	var id: String = PREFIX + String(room.id)
	if depth != 1 or width != 1:
		id += "_%dx%d" % [depth, width]
	if arrivals != null:
		id += "_paced_%d_%d_%d" % [roundi(arrivals.group_share * 100.0), roundi(arrivals.refill_share * 100.0), roundi(arrivals.stagger * 100.0)]
	return StringName(id)

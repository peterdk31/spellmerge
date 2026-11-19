class_name MapStyle
extends Resource
## A shape of a biome's map (connected biomes CB5, docs/milestones/connected-biomes.md, decision 5):
## a few weights the generator (`BiomeGenerator`, gameplay/run) grows the map by. A biome rolls one
## of its rules' styles (`MapRules.styles`) by `weight`; the crypt's are long, branching, loop and
## hub and spokes. A new style is a new entry of numbers, never code. A sub-resource of `MapRules`.
##
## - `way_share`: the share of the biome's rooms on the way from the start room to the boss (long:
##   most of them; hub and spokes: few). The rest hang off it, optional.
## - `branch_chain`: the chance a room off the way hangs off the last such room placed, so branches
##   grow long, rather than off any room by chance.
## - `hub_pull`: how much more a room with more bridges draws the next room off the way (each of its
##   bridges adds this much to its weight of 1): hub and spokes.
## - `loops`: how many extra bridges the generator closes between rooms already placed, where two
##   free sockets meet a bridge's ends (a loop), and `loop_pull` how much it favours placing a room
##   where such a bridge will fit (each such pair adds this much to a placement's weight of 1).

## The most loops a style may ask for (the editor's range; a rule change may not pass it either).
const MOST_LOOPS: int = 8
## The most a pull may be.
const MOST_PULL: float = 10000.0

## Its name, for the map, the tests and a rule change (`RunRuleChange.style`).
@export var id: StringName = &""
## How often a biome rolls it against its rules' other styles (above 0).
@export_range(0.01, 100.0, 0.01) var weight: float = 1.0
## The share of the rooms on the way to the boss (0 to 1).
@export_range(0.0, 1.0, 0.01) var way_share: float = 0.5
## The chance a room off the way hangs off the last such room (0 to 1).
@export_range(0.0, 1.0, 0.01) var branch_chain: float = 0.3
## How much a room's bridges draw the next room off the way to it (0: not at all).
@export_range(0.0, 10000.0, 0.1) var hub_pull: float = 0.0
## How many loops it closes at most.
@export_range(0, 8) var loops: int = 0
## How much it favours a placement where a loop's bridge will fit (0: not at all).
@export_range(0.0, 10000.0, 0.1) var loop_pull: float = 0.0


## A style `of_id` of these numbers (tests, made-up content).
static func make(of_id: StringName, of_way_share: float, of_branch_chain: float = 0.3, of_hub_pull: float = 0.0, of_loops: int = 0, of_loop_pull: float = 0.0) -> MapStyle:
	var style := MapStyle.new()
	style.id = of_id
	style.way_share = of_way_share
	style.branch_chain = of_branch_chain
	style.hub_pull = of_hub_pull
	style.loops = of_loops
	style.loop_pull = of_loop_pull
	return style


## What is wrong with it, one line each, named by `what` (its biome): no id, a weight of 0 or less,
## a share or a chance out of 0 to 1, a pull below 0 or past MOST_PULL, loops out of 0 to MOST_LOOPS.
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	var named: String = "%s: map style '%s'" % [what, id]
	if id == &"":
		found.append("%s: a map style has no id." % what)
	if not (weight > 0.0) or weight > KindRule.MOST_WEIGHT:
		found.append("%s: its weight is %s; above 0, %s at most." % [named, weight, KindRule.MOST_WEIGHT])
	if not (way_share >= 0.0 and way_share <= 1.0):
		found.append("%s: way_share %s; 0 to 1." % [named, way_share])
	if not (branch_chain >= 0.0 and branch_chain <= 1.0):
		found.append("%s: branch_chain %s; 0 to 1." % [named, branch_chain])
	if not (hub_pull >= 0.0 and hub_pull <= MOST_PULL) or not (loop_pull >= 0.0 and loop_pull <= MOST_PULL):
		found.append("%s: hub_pull %s and loop_pull %s; 0 to %s." % [named, hub_pull, loop_pull, MOST_PULL])
	if loops < 0 or loops > MOST_LOOPS:
		found.append("%s: loops %d; 0 to %d." % [named, loops, MOST_LOOPS])
	return found

class_name RunScaling
extends Resource
## How a run grows harder (run generation RG5, docs/milestones/run-generation.md, "Scaling"): one
## scale for each room, from its depth and the number of players in the run, the product of two
## curves (`ScaleCurve`: a start, an end and an ease, as the cards' speed curves are): `per_depth`
## from the map's first row (its start) to the deepest row its rules allow (its end), and
## `per_player` from one player (its start) to four (its end), each extra player a third of the way.
## `RunDefinition.scaling`; the owner tunes it in data. The scale multiplies the room's enemy budget
## (`scaled_budget`, by the generator) and every enemy's and boss's health (gameplay/difficulty);
## power, spell size and a boss's adds join it as the boss plan's OB7 and OB13 land, and a
## difficulty setting later is one more factor here.
##
## Pure functions of numbers through `DMath`: the same scale on every machine and in every replay.

## The most players a run has (the seats).
const MOST_PLAYERS: int = InputFrame.SEATS

## The factor per depth: its start at the first row, its end at the deepest row the rules allow
## (null: 1 at every depth).
@export var per_depth: ScaleCurve = null
## The factor per extra player: its start with one player, its end with four (null: 1 for any number).
@export var per_player: ScaleCurve = null


## A copy of its own, its curves too (run generation RG6, `RunDefinition.copied`).
func copied() -> RunScaling:
	var made: RunScaling = duplicate(false)
	made.per_depth = per_depth.duplicate(false) if per_depth != null else null
	made.per_player = per_player.duplicate(false) if per_player != null else null
	return made


## The scale of a room `depth` rows in (`RunNode.depth`; 0 the first) of a map whose rules allow
## `deepest` as their deepest row (`MapRules.depth_max` - 1), in a run of `players` players (1 to
## `MOST_PLAYERS`, clamped).
func room_scale(depth: int, deepest: int, players: int) -> float:
	var scale: float = 1.0
	if per_depth != null:
		scale *= per_depth.at(float(depth) / float(deepest) if deepest > 0 else 0.0)
	if per_player != null:
		var extra: int = clampi(players, 1, MOST_PLAYERS) - 1
		scale *= per_player.at(float(extra) / float(MOST_PLAYERS - 1))
	return scale


## A room's enemy budget `budget` (`MapRules.room_budget`) at the scale `scale`: rounded, 1 at least.
static func scaled_budget(budget: int, scale: float) -> int:
	return maxi(1, roundi(float(budget) * scale))


## What is wrong with the scaling, one line each, named by `what` (the run): each curve's problems.
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	if per_depth != null:
		found.append_array(per_depth.problems("%s: scaling per depth" % what))
	if per_player != null:
		found.append_array(per_player.problems("%s: scaling per player" % what))
	return found

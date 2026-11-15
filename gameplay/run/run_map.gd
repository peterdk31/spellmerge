class_name RunMap
extends RefCounted
## A run's map (run generation RG2, docs/milestones/run-generation.md, "The generator"): rows of
## rooms (`RunNode`), the first one room, each linking to rooms of the next, the last the deepest
## (the boss's when the rules and the content give one). Made once at the run's start by
## `RunGenerator.generate` from the run's seed; after that it is the run's state, the same on every
## machine: hashed and saved in snapshots as it is, so a joining machine never makes its own.
##
## A map that could not be made has no rooms and says why (`problems`).

## The run it is a map of (`RunDefinition.id`).
var run: StringName = &""
## The biome its rooms are of (`MapRules.biome`).
var biome: StringName = &""
## How many players the run was made for (the seats joined at its start; run generation RG5): its
## rooms' scales (`RunNode.scale`) count them.
var players: int = 1
## Its rooms, row by row, each row left to right (`RunNode.index` is the place here).
var nodes: Array[RunNode] = []
## Why no map could be made, one line each (empty for a map that was made).
var problems: PackedStringArray = PackedStringArray()


## True when it has rooms (it was made).
func is_made() -> bool:
	return not nodes.is_empty()


## How many rows deep it is.
func rows() -> int:
	return 0 if nodes.is_empty() else nodes[nodes.size() - 1].row + 1


## The rooms of row `at`, left to right (none outside the map).
func row(at: int) -> Array[RunNode]:
	var found: Array[RunNode] = []
	for node: RunNode in nodes:
		if node.row == at:
			found.append(node)
	return found


## The room numbered `index`, or null outside the map.
func node(index: int) -> RunNode:
	return nodes[index] if index >= 0 and index < nodes.size() else null


## The first room, where the party enters (null for a map not made).
func first() -> RunNode:
	return node(0)


## The rooms that lead to room `index` (their numbers, left to right).
func parents_of(index: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for node: RunNode in nodes:
		if node.links.has(index):
			found.append(node.index)
	return found

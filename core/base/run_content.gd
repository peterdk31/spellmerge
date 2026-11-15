class_name RunContent
extends RefCounted
## What a run can be made of (run generation RG1, docs/milestones/run-generation.md, "The model"):
## the room kinds, the room templates and the enemies and bosses there are, gathered once from the
## registry's folders (`gather`), and the questions a run's rules ask of them: which templates of a
## biome host a kind, which enemies fight in a biome from a depth, which bosses. Every list is in id
## order, so what is asked of it is the same on every machine. It reads no file and no node: a test
## gathers made-up content the same way.

## Room kinds by id (`RoomKind`).
var kinds: Dictionary = {}
## Every room template, in id order (a room that hosts no kind is never offered).
var rooms: Array[RoomBase] = []
## Every enemy and boss, in id order (`EnemyBase.boss` tells them apart).
var enemies: Array[EnemyBase] = []


## The content in `of_kinds`, `of_rooms` and `of_enemies` (each what the registry's `get_all` gives
## for its folder, so in id order; for the enemies the folders of `EnemyBase.FOLDERS` one after the
## other). What is not of the folder's class is left out.
static func gather(of_kinds: Array[Resource], of_rooms: Array[Resource], of_enemies: Array[Resource]) -> RunContent:
	var made := RunContent.new()
	for item: Resource in of_kinds:
		var kind := item as RoomKind
		if kind != null and kind.id != &"" and not made.kinds.has(kind.id):
			made.kinds[kind.id] = kind
	for item: Resource in of_rooms:
		if item is RoomBase:
			made.rooms.append(item as RoomBase)
	for item: Resource in of_enemies:
		if item is EnemyBase:
			made.enemies.append(item as EnemyBase)
	made.rooms.sort_custom(func(a: RoomBase, b: RoomBase) -> bool: return String(a.id) < String(b.id))
	made.enemies.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool: return String(a.id) < String(b.id))
	return made


## The ids of the room kinds there are, sorted.
func kind_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in kinds:
		ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## The room kind `id`, or null when there is none.
func kind(id: StringName) -> RoomKind:
	return kinds.get(id) as RoomKind


## The templates of biome `biome` that can host kind `kind_id`, in id order.
func templates_for(biome: StringName, kind_id: StringName) -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for room: RoomBase in rooms:
		if room.biome == biome and room.hosts(kind_id):
			found.append(room)
	return found


## The enemies (not bosses) that fight in biome `biome` from depth `depth` (row; 0 the first room) on, in id order.
func enemy_pool(biome: StringName, depth: int) -> Array[EnemyBase]:
	var found: Array[EnemyBase] = []
	for enemy: EnemyBase in enemies:
		if not enemy.boss and enemy.fights_in(biome, depth):
			found.append(enemy)
	return found


## The bosses that fight in biome `biome`, in id order.
func boss_pool(biome: StringName) -> Array[EnemyBase]:
	var found: Array[EnemyBase] = []
	for enemy: EnemyBase in enemies:
		if enemy.boss and enemy.biomes.has(biome):
			found.append(enemy)
	return found


## Why a room of kind `kind_id` cannot stand in row `row` of biome `biome` (empty when it can): no
## such kind, no template of the biome hosts it, or what fills it has nothing there (no enemy that
## fights there by that depth, no boss of the biome).
func cannot_fill(biome: StringName, kind_id: StringName, row: int) -> String:
	var of_kind: RoomKind = kind(kind_id)
	if of_kind == null:
		return "no room kind '%s'" % kind_id
	if templates_for(biome, kind_id).is_empty():
		return "no %s room hosts '%s'" % [biome, kind_id]
	match of_kind.fill:
		RoomKind.FILL_ENEMIES:
			if enemy_pool(biome, row).is_empty():
				return "no enemy fights in %s by row %d" % [biome, row]
		RoomKind.FILL_BOSS:
			if boss_pool(biome).is_empty():
				return "no boss fights in %s" % biome
	return ""

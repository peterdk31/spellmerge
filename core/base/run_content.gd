class_name RunContent
extends RefCounted
## What a run can be made of (run generation RG1, docs/milestones/run-generation.md, "The model"):
## the room kinds, the room templates and the enemies and bosses there are, gathered once from the
## registry's folders (`gather`), and the questions a run's rules ask of them: which templates of a
## biome host a kind, which enemies fight in a biome from a depth, which
## bosses. Every list is in id
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
## other). What is not of the folder's class is left out, and so is an id met before (an enemy and a
## boss of one id: the first folder's, as the game finds it).
static func gather(of_kinds: Array[Resource], of_rooms: Array[Resource], of_enemies: Array[Resource]) -> RunContent:
	var made := RunContent.new()
	for item: Resource in of_kinds:
		var kind := item as RoomKind
		if kind != null and kind.id != &"" and not made.kinds.has(kind.id):
			made.kinds[kind.id] = kind
	for item: Resource in of_rooms:
		if item is RoomBase:
			made.rooms.append(item as RoomBase)
	var seen: Dictionary = {}
	for item: Resource in of_enemies:
		var enemy := item as EnemyBase
		if enemy != null and not seen.has(enemy.id):
			seen[enemy.id] = true
			made.enemies.append(enemy)
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


## The enemies (not bosses) that fight in biome `biome` from depth `depth` (bridges from the start room) on, in id order.
func enemy_pool(biome: StringName, depth: int) -> Array[EnemyBase]:
	var found: Array[EnemyBase] = []
	for enemy: EnemyBase in enemies:
		if not enemy.boss and enemy.fights_in(biome, depth):
			found.append(enemy)
	return found


## The bosses that fight in biome `biome` from depth `depth` on, in id order.
func boss_pool(biome: StringName, depth: int) -> Array[EnemyBase]:
	var found: Array[EnemyBase] = []
	for enemy: EnemyBase in enemies:
		if enemy.boss and enemy.fights_in(biome, depth):
			found.append(enemy)
	return found

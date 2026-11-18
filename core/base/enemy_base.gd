class_name EnemyBase
extends Resource
## An enemy: its body's numbers, its scene, its staffs, how it plays them and a boss's phases, and its
## health by the players in play (`health_per_player`, boss plan OB13).

## Unique name of the enemy, also its folder name; the registry finds it by this.
@export var id: StringName = &""
## Its name for people (the enemy arena's picker); empty: its id.
@export var display_name: String = ""
@export var max_health: float = 1.0
## The share of `max_health` each player in play after the first adds (boss plan OB13; 0: the same for
## any number). Counted from the wizards in play when the body stands; one joining or leaving later
## changes its most and its current health by the same share (`Actor.count_players`).
@export_range(0.0, 4.0) var health_per_player: float = 0.0
## Pixels per second.
@export var move_speed: float = 0.0
## Damage a player takes from touching the enemy.
@export var contact_damage: int = 0
@export var scene: PackedScene
## True for a boss: its death stops the whole game for a moment (Feel); other kills hold only the
## bodies in them.
@export var boss: bool = false
## Its line of lore for people (boss OB3; the boss's entrance banner shows it, OB16): why it fights,
## one line of at most `StoryValidator.MAX_LORE_CHARS` characters, checked with the other words of the
## game (`Registry.validate_story`). A boss has one; a stray may leave it empty.
@export var lore: String = ""
## Its music while it lives (boss plan OB15, `MusicTrack`; null: the room's plays on): it overrides
## the room's (`RoomBase.music`), and its phases raise its intensity (`EnemyPhase.intensity`). A
## sub-resource of its data, so the music comes with the boss (decision 17).
@export var music: MusicTrack = null
## The sound its death plays in place of its death cue's (`enemy_death`, `boss_death`; empty: the
## cue's own), so a boss splinters as only it does while the cue stays everyone's.
@export var death_sound: StringName = &""
## Its intro (docs/milestones/boss-intro.md, `BossIntro`; null: none, the entrance banner): the
## overlay that stops the game as its fight starts, its portrait, lines, accent and cues. A
## sub-resource of its data, as its music is.
@export var boss_intro: BossIntro = null

## The body's scale (1: as drawn); a boss is bigger.
@export var size: float = 1.0
## Its stats (boss plan OB7: power, mass, spell scale, resists; null: every default, the game as it
## is). Copied into the body's own `Stats` as it enters play.
@export var stats: ActorStats = null

## Its own colour when hit (Feel): the spray of a hit on its body and its death's puff, in the
## palette ramp nearest it; not its spell's colours (those are its shots'). Ember for every enemy so
## far, and for a body with no enemy data (a stand-in).
const DEFAULT_HIT_COLOR: Color = Color("e0592f")
@export var hit_color: Color = DEFAULT_HIT_COLOR

# Enemy AI (docs/milestones/M2-enemy-ai.md, "The enemy's data"): an enemy holds 1-4 staffs of
# player cards and casts them like a wizard, paying each staff's own mana. The AI reads what each
# staff casts next (`CastSense`), so a new enemy type is a sprite and staffs, with no code. Without
# a staff it only chases and hurts by touch.

## Its staffs, one per button (at most 4); empty for an enemy that only chases.
@export var staffs: Array[StaffCards] = []
## How it plays them (null: `AIProfile.fallback()`).
@export var profile: AIProfile = null
## A boss's phases, in order (empty: one phase).
@export var phases: Array[EnemyPhase] = []

# Where it fights (run generation RG1, docs/milestones/run-generation.md, "The model"): a biome's
# enemy pool is every enemy that names the biome, a boss pool every boss that does (`RunContent`),
# so an enemy joins runs by its own data and deleting it touches no other file.

## The biomes it fights in (`RoomBase.biome`). Empty: no run's (the dummies).
@export var biomes: Array[StringName] = []
## How it spawns in (spawn styles AS2, docs/milestones/spawn-styles.md): a style's id
## (content/spawn_styles), which wins over its room's biome's (`SpawnStyle.pick`). Empty: its room's.
@export var spawn_style: StringName = &""
## What it costs of a room's enemy budget (at least 1): the tougher, the more.
@export_range(1, 100) var cost: int = 1
## The first row of a run's map it may stand in (0: the first room on).
@export_range(0, 32) var min_depth: int = 0

## The most staffs an enemy may hold (the staff buttons).
const MAX_STAFFS: int = 4
## The registry folders an enemy's data is found in: the enemies, then the bosses (content/bosses;
## boss OB2: a run's map stands both).
const FOLDERS: Array[StringName] = [&"enemies", &"bosses"]


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).replace("_", " ").capitalize()


## Its most health with `players` in play (1 at least) at the room's scale `scale` (`Actor.stat_scale`).
func health_for(players: int, scale: float = 1.0) -> float:
	return max_health * scale * (1.0 + health_per_player * float(maxi(players, 1) - 1))


## True when it fights in biome `biome` in row `depth` of a run's map (0 the first room).
func fights_in(biome: StringName, depth: int) -> bool:
	return biomes.has(biome) and depth >= min_depth


## True when it holds at least one staff with a card.
func has_staffs() -> bool:
	for entry: StaffCards in staffs:
		if entry != null and entry.staff != null and not entry.cards.is_empty():
			return true
	return false


## The profile it plays by.
func profile_or_fallback() -> AIProfile:
	return profile if profile != null else AIProfile.fallback()


## What is wrong with the enemy's data, one line each (empty when it is fine): too many staffs,
## a staff entry's problems, a phase without a condition or with too many staffs, its stats' or a
## phase's stats' problems (`ActorStats.problems`), a phase's adds' problems (`EnemyAdds.problems`:
## whether the enemy is in the registry is `Registry`'s to know, checked by the enemy data's test), a
## health per player that is not a number, a cost below 1, a depth below 0 or a biome twice.
func problems() -> PackedStringArray:
	var found: PackedStringArray = StaffCards.list_problems(String(id), staffs, MAX_STAFFS)
	if stats != null:
		for line: String in stats.problems():
			found.append("%s: stats: %s" % [id, line])
	if music != null:
		found.append_array(music.problems(String(id)))
	if boss_intro != null:
		found.append_array(boss_intro.problems(String(id)))
	if not is_finite(health_per_player) or health_per_player < 0.0:
		found.append("%s: its health_per_player is %s; 0 or more." % [id, health_per_player])
	if cost < 1:
		found.append("%s: its cost is %d; at least 1." % [id, cost])
	if min_depth < 0:
		found.append("%s: its min_depth is %d; at least 0." % [id, min_depth])
	for at in biomes.size():
		if biomes.find(biomes[at]) != at:
			found.append("%s: biome '%s' twice." % [id, biomes[at]])
	for at in phases.size():
		var phase: EnemyPhase = phases[at]
		if phase == null:
			found.append("%s: phase %d is empty." % [id, at])
			continue
		if not phase.has_condition():
			found.append("%s: phase %d has no condition (health_below or after_seconds)." % [id, at])
		if phase.stats != null:
			for line: String in phase.stats.problems():
				found.append("%s: phase %d stats: %s" % [id, at, line])
		if phase.adds.size() > Phases.ADDS_MOST:
			found.append("%s: phase %d has %d adds entries; at most %d." % [id, at, phase.adds.size(), Phases.ADDS_MOST])
		for k in phase.adds.size():
			if phase.adds[k] == null:
				found.append("%s: phase %d adds %d are empty." % [id, at, k])
				continue
			for line: String in phase.adds[k].problems():
				found.append("%s: phase %d adds %d: %s" % [id, at, k, line])
		if phase.staffs.size() > MAX_STAFFS:
			found.append("%s: phase %d has %d staffs; at most %d." % [id, at, phase.staffs.size(), MAX_STAFFS])
		for k in phase.staffs.size():
			if phase.staffs[k] == null:
				found.append("%s: phase %d staff %d is empty." % [id, at, k])
				continue
			for line: String in phase.staffs[k].problems():
				found.append("%s: phase %d staff %d: %s" % [id, at, k, line])
	return found

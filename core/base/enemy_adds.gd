class_name EnemyAdds
extends Resource
## The adds a phase brings (boss plan OB13, docs/milestones/boss-old-broom.md, "Phase adds and
## player-count scaling"): enemies the body calls when its phase starts, then in waves while the
## phase lasts, so a boss's adds come with the boss (decision 17), never with the room. Any enemy may
## have them (an elite calling strays at half health). The `Phases` component asks for them on the
## bus (`adds_requested`); Flow stands them and lets them crumble when the body that called them
## dies. Each "per player" is for every player in play after the first, as `EnemyBase.health_per_player`.

## Where they stand.
enum At {
	## A ring round the body that calls them, each slid out from its middle against the walls.
	RING,
	## The room's enemy spawns, in turn (a ring when the room has none).
	SPAWNS,
}

## The enemy they are (an id of `EnemyBase.FOLDERS`' enemies; not a boss).
@export var enemy: StringName = &""
## How many stand as the phase starts, and how many more for each player after the first.
@export_range(0, 64) var count: int = 0
@export_range(0, 64) var per_player: int = 0
## Seconds between waves while the phase lasts (0: none), and each wave's size, as above.
@export var every: float = 0.0
@export_range(0, 64) var wave_count: int = 0
@export_range(0, 64) var wave_per_player: int = 0
## At most this many of them alive at once (0: no cap), and that many more for each player after
## the first.
@export_range(0, 256) var cap: int = 0
@export_range(0, 64) var cap_per_player: int = 0
@export var at: At = At.RING


## How many the phase's start calls with `players` in play (1 at least).
func burst_for(players: int) -> int:
	return count + per_player * _extra(players)


## How many a wave calls with `players` in play.
func wave_for(players: int) -> int:
	return wave_count + wave_per_player * _extra(players)


## The most alive at once with `players` in play; -1 for no cap.
func cap_for(players: int) -> int:
	return cap + cap_per_player * _extra(players) if cap > 0 else -1


## How many of `wanted` may stand with `alive` of them up and `players` in play (the cap's room).
func allowed(wanted: int, alive: int, players: int) -> int:
	var most: int = cap_for(players)
	return maxi(0, wanted if most < 0 else mini(wanted, most - alive))


## True when it calls waves.
func has_waves() -> bool:
	return every > 0.0 and (wave_count > 0 or wave_per_player > 0)


## What is wrong with it, one line each (empty when it is fine): no enemy, nothing called, a wave
## size with no time between waves, or a time that is not a number.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if enemy == &"":
		found.append("its enemy is not named.")
	if not is_finite(every) or every < 0.0:
		found.append("every is %s; 0 or more seconds." % every)
	if count + per_player == 0 and not has_waves():
		found.append("it calls nobody: no count and no waves.")
	if (wave_count > 0 or wave_per_player > 0) and not (every > 0.0):
		found.append("a wave of %d (+%d a player) with no time between waves (every)." % [wave_count, wave_per_player])
	return found


func _extra(players: int) -> int:
	return maxi(players, 1) - 1

extends Node
## The event bus: one autoload ("Events"), one typed signal per event.
##
## Areas never call each other; they emit and connect here. Every per-player
## event takes the player index (0-3) as its first argument. Each event has
## exactly one sender, named in its comment. Where an event has no player to
## name (for example damage dealt by an enemy), the index is NO_PLAYER.

## Player index for "no player involved", for example an enemy as the damage source.
const NO_PLAYER: int = -1

# --- Player intent from the HUD (sender: hud) -------------------------------

## The Play button was pressed. Heard by flow.
signal play_requested(player: int)
## A player asked to put the component `component_id` into spell slot `slot`. Heard by player.
signal build_change_requested(player: int, slot: int, component_id: StringName)
## A player picked reward choice number `choice`. Heard by rewards.
signal reward_pick_requested(player: int, choice: int)
## A player voted for door number `door`. Heard by flow.
signal door_vote_requested(player: int, door: int)
## A player asked to pause. Heard by run.
signal pause_requested(player: int)

# --- Devices (sender: core/input) -------------------------------------------

## Sender: core/input. `device` (ids in input_manager.gd) took the free slot `player`, by a button press or as a bot's virtual device.
signal device_joined(player: int, device: int)
## Sender: core/input. `device` left slot `player`, by a button press or an unplugged gamepad. The slot is free again.
signal device_left(player: int, device: int)

# --- Spells and combat ------------------------------------------------------

## Sender: player. A cast left the wand of `player`.
signal spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2)
## Sender: core/projectiles. A projectile fired by `player` touched `target`.
signal projectile_hit(player: int, target: Node, position: Vector2)
## Sender: combat. `player` (or NO_PLAYER) dealt `amount` damage to `target`.
signal damage_dealt(player: int, target: Node, amount: int, position: Vector2)
## Sender: combat. A status effect from `player` (or NO_PLAYER) was put on `target`.
signal status_applied(player: int, target: Node, status_id: StringName)
## Sender: combat. `enemy` died; `player` landed the last hit (or NO_PLAYER).
signal enemy_died(player: int, enemy: Node, position: Vector2)

# --- Players ----------------------------------------------------------------

## Sender: player. `player` has no health left.
signal player_downed(player: int)
## Sender: player. `player` was revived by `reviver`.
signal player_revived(player: int, reviver: int)
## Sender: coop. `player` joined the game.
signal player_joined(player: int)
## Sender: coop. `player` left the game.
signal player_left(player: int)

# --- Run and rooms ----------------------------------------------------------

## Sender: run. A run began with `player_count` players.
signal run_started(player_count: int)
## Sender: run. The run is over; `victory` is true if the players won.
signal run_ended(victory: bool)
## Sender: flow. The players entered the room `room_id`.
signal room_entered(room_id: StringName)
## Sender: flow. The room `room_id` was cleared.
signal room_cleared(room_id: StringName)
## Sender: flow. The result of a door vote: `player` voted for `door`.
signal door_voted(player: int, door: int)
## Sender: difficulty. The difficulty level changed to `level`.
signal difficulty_changed(level: float)

# --- Rewards and progression ------------------------------------------------

## Sender: rewards. These rewards were offered to the players.
signal reward_rolled(reward_ids: Array[StringName])
## Sender: rewards. The result of a pick: `player` took `reward_id`.
signal reward_taken(player: int, reward_id: StringName)
## Sender: progression. `unlock_id` was unlocked.
signal unlock_gained(unlock_id: StringName)
## Sender: progression. The balance of `currency_id` is now `amount`.
signal currency_changed(currency_id: StringName, amount: int)

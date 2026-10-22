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
## A player asked to put the component `component_id` into slot `slot` of the spell at `spell`, a path of slot indices: `[0]` is spell A, `[1]` is spell B, `[0, 0]` the spell held by A's trigger. Heard by player.
signal build_change_requested(player: int, spell: PackedInt32Array, slot: int, component_id: StringName)
## A player asked to switch between the two prepared spells. Heard by player.
signal spell_swap_requested(player: int)
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
## Sender: player. The wizard node of `player` has just cast, for visual reactions only (a squash). Sent right after `spell_cast`.
signal wizard_cast(player: int, wizard: Node)
## Sender: core/projectiles. A projectile fired by `player` touched `target`.
## `tag` is the value given to `Projectiles.spawn()`, for looking up the damage.
signal projectile_hit(player: int, target: Node, position: Vector2, tag: int)
## Sender: core/projectiles. Where and which way a projectile struck, for looks only (sparks, dust). `target` is the node it hit, sent just before `projectile_hit` for the same hit, or `null` when it ended on a wall or pillar. `player` is who fired it (or NO_PLAYER for an enemy), `position` the point it stopped at and `direction` the unit vector it was flying.
signal projectile_impact(player: int, target: Node, position: Vector2, direction: Vector2)
## Sender: core/projectiles. A projectile fired by `player` ended without a hit: its life ran out or it struck a wall. `tag` is the value given to `Projectiles.spawn()`.
signal projectile_expired(player: int, position: Vector2, tag: int)
## Sender: core/spells. A beam or a nova of `player` just fired, for looks only (they have no shot to draw). `form` is `&"beam"` (`length` is how far it got, along `direction`) or `&"nova"` (a ring of shots leaves `origin`; `length` is 0). `tint` is the colour of the spell's element (white for plain arcane).
signal form_shown(player: int, form: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color)
## Sender: player. The spell of `player` at `spell` (a path as in `build_change_requested`) was built or changed; `description` says in plain words what it does now.
signal spell_changed(player: int, spell: PackedInt32Array, description: String)
## Sender: player. A build change asked for by `player` was refused; `reason` says why in plain words.
signal build_refused(player: int, reason: String)
## Sender: player. The prepared spell `slot` (0 is A, 1 is B) of `player` now has this `recipe` (component ids by key, as `Spells.compile` reads them: `form`, `element`, `modifiers`, `trigger`, and `held` for the spell the trigger holds). Sent with `spell_changed`, so the builder can show the chain without reading the player.
signal recipe_changed(player: int, slot: int, recipe: Dictionary)
## Sender: player. The active prepared spell of `player` is now `slot` (0 is A, 1 is B). Sent when the wizard appears and after every swap, so the HUD shows which spell `cast` fires.
signal active_spell_changed(player: int, slot: int)
## Sender: player. The component ids `player` may build with, in registry order. Sent when the wizard appears and whenever the bag changes.
signal bag_changed(player: int, bag: Array[StringName])
## Sender: combat. The reaction `reaction_id` (for example &"shatter") fired for `player` (or NO_PLAYER) at `position`.
signal reaction_triggered(player: int, reaction_id: StringName, position: Vector2)
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
## Sender: coop. `player` is downed and being revived: `progress` (0 to 1) is how far the hold has got. Sent when it changes (so every frame while a revive fills or drains); 0 means the revive stopped or is done.
signal revive_progress(player: int, progress: float)
## Sender: player. The health or the whole-number mana of `player` changed, or the wizard appeared. Carries all the numbers so a listener never has to ask.
signal player_stats_changed(player: int, health: int, max_health: int, mana: float, max_mana: float)
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
## Sender: flow. Wave number `wave` (1 for the first of a run) of the room began.
signal wave_started(wave: int)
## Sender: flow. The build break between waves began and lasts `seconds`; the next wave starts when it ends, whoever is building. Follows `room_cleared`; `wave_started` ends it.
signal build_break_started(seconds: float)
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

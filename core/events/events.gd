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
## Sender: hud. `player` asked to put the card `card_id` into slot `slot` of their staff `staff` (0-3: A, X, Y, B); `&""` empties the slot. Heard by player, which applies it (staffs, docs/milestones/M2-staffs.md).
signal staff_change_requested(player: int, staff: int, slot: int, card_id: StringName)
## `player` asked to move the card in `from_slot` of staff `from_staff` to `to_slot` of staff `to_staff`, swapping with what is there; a staff of -1 means the bag. Heard by player.
signal card_move_requested(player: int, from_staff: int, from_slot: int, to_staff: int, to_slot: int)
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
## Sender: core/spells. A beam, a nova or a rain of `player` just fired, for looks only (they have no shot to draw). `form` is `&"rain"` (a telegraph: its payload falls on `origin` after `length` seconds) or `&"beam"` (`length` is how far it got, along `direction`) or `&"nova"` (a ring of shots leaves `origin`; `length` is 0). `tint` is the colour of the spell's element (white for plain arcane).
signal form_shown(player: int, form: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color)
## Sender: core/spells. `player` just cast a spell that is more than a plain shot, for looks only. `combo_class` is `&"boosted"` (modifiers only), `&"on_hit"`, `&"on_expire"` or `&"timer"` (a trigger holds a second spell), or `&"stacked"` (a trigger with two or more modifiers, or a chain of three spells); a plain cast sends nothing. `tint` is the element's colour (white for plain arcane). Sent after the cast made a shot. Heard by feel.
signal combo_cast(player: int, combo_class: StringName, origin: Vector2, direction: Vector2, tint: Color)
## Sender: player. A build change asked for by `player` was refused; `reason` says why in plain words.
signal build_refused(player: int, reason: String)
## Sender: player. The component ids `player` may build with, in registry order. Sent when the wizard appears and whenever the bag changes.
signal bag_changed(player: int, bag: Array[StringName])
## Sender: player. The staff `staff` (0-3) of `player` was built or changed. `plan` holds plain values for the builder (the cards, the casts of its cycle, wasted cards with their reasons, the numbers), as `Spells.staff_view` gives them. Heard by hud.
signal staff_changed(player: int, staff: int, plan: Dictionary)
## Sender: player. `player` cast their staff `staff` from `origin` along `direction`. Heard by feel.
signal staff_cast(player: int, staff: int, origin: Vector2, direction: Vector2)
## Sender: core/spells. A card of `player` moves the wizard: `mode` is `&"dash"`, `&"teleport"`, `&"hook"`, `&"swap"` or `&"recoil"`; `to` is where it wants to go (the wizard stops at walls), over `seconds` (0 is at once); `tag` is the card's tag. Heard by player, which answers with `caster_move_finished`. Several requests can come in one step (a scatter, a burst, `mirror`): the player adds up the `recoil` requests of a step (so `mirror · recoil` cancels) and lets a later dash, teleport, hook or swap replace an earlier one.
signal caster_move_requested(player: int, mode: StringName, to: Vector2, seconds: float, tag: int)
## Sender: player. The move asked for by `caster_move_requested` ended at `position`: the end point of a dash, teleport or hook. Heard by core/spells.
signal caster_move_finished(player: int, mode: StringName, position: Vector2, tag: int)
## Sender: core/spells. A card of `player` (swap) moves `target` to `to`. Heard by ai.
signal target_move_requested(player: int, target: Node, to: Vector2)
## Sender: core/spells. A card of `player` (blast, a payload's fallback) hits everything in the circle at `position` of `radius`, the caster included, with the hit profile of `tag`. Heard by combat.
signal area_hit_requested(player: int, position: Vector2, radius: float, tag: int)
## Sender: core/spells. A card of `player` makes an entity of `kind` (`&"decoy"`, `&"familiar"`) at `position` that lasts `seconds` (INF, or 0 or less: until `entity_end_requested`, the room or the run ends); `tag` is the card's tag. Heard by ai.
signal entity_spawn_requested(player: int, kind: StringName, position: Vector2, seconds: float, tag: int)
## Sender: core/spells. The entities of `player` made by the card with `tag` end now (a `hold` switched off, or its staff rebuilt). Heard by ai, which answers with `entity_ended` for each.
signal entity_end_requested(player: int, tag: int)
## Sender: ai. The entity of `player` of `kind` with `tag` ended at `position` (a decoy died, a familiar left). Heard by core/spells (its end point).
signal entity_ended(player: int, kind: StringName, position: Vector2, tag: int)
## Sender: ai. The familiar of `player` with `tag` casts its payload from `position` along `direction`. Heard by core/spells.
signal familiar_cast_requested(player: int, position: Vector2, direction: Vector2, tag: int)
## Sender: core/spells. Mana of `player` comes back (siphon). Heard by player.
signal mana_refund_requested(player: int, amount: float)
## Sender: core/spells. `amount` of the mana of `player` is now held by sustained cards (`hold`); 0 when none is on. Heard by player and hud.
signal mana_reserved(player: int, amount: float)
## Sender: core/projectiles. A shot of `player` with `tag` stopped an enemy shot at `position` with one of its shield charges. Heard by core/spells and feel.
signal shot_blocked(player: int, position: Vector2, tag: int)
## Sender: combat. The reaction `reaction_id` (for example &"shatter") fired for `player` (or NO_PLAYER) at `position`.
signal reaction_triggered(player: int, reaction_id: StringName, position: Vector2)
## Sender: combat. A discharge of `player` jumped from `from` (the enemy struck) to `to` (an enemy zapped), both in world pixels; one is sent for each enemy zapped, next to its `reaction_triggered` `discharge`. Heard by feel, which draws the arc.
signal discharge_arc(player: int, from: Vector2, to: Vector2)
## Sender: combat. `player` (or NO_PLAYER) dealt `amount` damage to `target`.
signal damage_dealt(player: int, target: Node, amount: int, position: Vector2)
## Sender: combat. A status effect from `player` (or NO_PLAYER) was put on `target`.
signal status_applied(player: int, target: Node, status_id: StringName)
## Sender: combat. `enemy` died; `player` landed the last hit (or NO_PLAYER).
signal enemy_died(player: int, enemy: Node, position: Vector2)

## Sender: combat. A barrier on the wizard `player` (shield charges from the card with `tag`) stopped a hit at `position`. Heard by core/spells and feel.
signal shield_blocked(player: int, position: Vector2, tag: int)
## Sender: combat. A hit of `player` with `tag` killed `target` at `position`. Heard by core/spells (on kill).
signal kill_landed(player: int, target: Node, position: Vector2, tag: int)
## Sender: combat. The wizard `player` took `amount` damage at `position` from a hit with `tag` (0 for an enemy's hit) of kind `kind` (`&"shot"`, `&"ray"`, `&"burst"`, `&"reaction"`, `&"status"`; a burn tick is not a hit, so it is not sent here). Heard by core/spells (on hurt), feel and hud.
signal wizard_hurt(player: int, amount: int, position: Vector2, tag: int, kind: StringName)
## Sender: combat. A hit of `player` with `tag` on `target` at `position` set off the reaction `reaction_id`. Heard by core/spells (on reaction); feel keeps `reaction_triggered`.
signal reaction_landed(player: int, reaction_id: StringName, target: Node, position: Vector2, tag: int)
## Sender: core/spells. The wizard `player` gets a barrier of `charges` blocked hits for `seconds` (shield on a dash, a teleport or the caster); the card has `tag`. Heard by combat.
signal wizard_shield_requested(player: int, charges: int, seconds: float, tag: int)
## Sender: core/spells. A card of `player` (magnet) pulls every enemy within `radius` of `position` toward it at `strength` pixels per second; the card has `tag`. Heard by combat.
signal pull_requested(player: int, position: Vector2, radius: float, strength: float, tag: int)
## Sender: combat. Just before `damage_dealt`: the hit of `player` on `target` for `amount` is of `kind` (`&"shot"`, `&"ray"`, `&"burst"`, `&"reaction"`, `&"status"`, and `&"heal"` for a heal). A wizard's contact hit counts as `&"shot"`. A wizard hit by their own spell has `player` equal to their index. Heard by feel.
signal hit_landed(player: int, target: Node, amount: int, position: Vector2, kind: StringName)
## Sender: combat. A heal hit of `player` gave the wizard `target` `amount` health at `position`. Heard by player and feel.
signal heal_dealt(player: int, target: Node, amount: int, position: Vector2)
## Sender: core/projectiles. A shot of `player` with `tag` passed through the teammate `ally` at `position`. Heard by core/spells (relay, on ally).
signal ally_passed(player: int, ally: Node, position: Vector2, tag: int)

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

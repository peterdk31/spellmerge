extends Node
## The event bus: one autoload ("Events"), one typed signal per event.
##
## Areas never call each other; they emit and connect here. Each event has exactly one
## sender, named in its comment. Two kinds of first argument (actors G3b,
## docs/milestones/M2-actors.md, "Events"):
##
## - `caster` (or `actor`): an actor id (`core/actors`), for what an actor does or has done to
##   it: spells, shots, hits, moves. A wizard and an enemy are named the same way; who it is
##   (its seat, team, colour) is the actor table's to say. NO_PLAYER (`Actors.NONE`) only where
##   no actor did it.
## - `player`: a seat (0-3), a human: HUD intent, devices, the builder, stats, downed and
##   revived, joined and left, and the casts the wizard announces for the HUD and Feel.

## "No actor" (`Actors.NONE`): the world, where no actor did it. Also "no seat".
const NO_PLAYER: int = -1

# --- Player intent from the HUD (sender: hud) -------------------------------

## The Play button was pressed. Heard by flow.
signal play_requested(player: int)
## Sender: hud. `player` asked to put the card `card_id` into slot `slot` of their staff `staff` (0-3: A, X, Y, B); `&""` empties the slot. Heard by player, which applies it (staffs, docs/milestones/M2-staffs.md).
signal staff_change_requested(player: int, staff: int, slot: int, card_id: StringName)
## `player` asked to move the card in `from_slot` of staff `from_staff` to `to_slot` of staff `to_staff`, swapping with what is there; a staff of -1 means the bag. Heard by player.
signal card_move_requested(player: int, from_staff: int, from_slot: int, to_staff: int, to_slot: int)
## Sender: hud. `player` asked to set every slot of their staff `staff` at once: `cards` holds the card ids by slot (`&""` for an empty slot), as many as the staff has slots or fewer (the rest are emptied). The radial builder sends it for a push-right insert, a take-out that closes the gap, an undo and a clear, so each is one change. Heard by player.
signal staff_cards_requested(player: int, staff: int, cards: Array[StringName])
## A player picked reward choice number `choice`. Heard by rewards.
signal reward_pick_requested(player: int, choice: int)
## A player voted for door number `door`. Heard by flow.
signal door_vote_requested(player: int, door: int)
## A player asked to pause. Heard by run.
signal pause_requested(player: int)
## Sender: hud. The "Effect slots" slider in the pause menu (Settings) moved: how many effects
## (the glowing flares of casts, impacts, rings and dashes) may show at once. Heard by feel.
signal effect_slots_changed(slots: int)
## The Sandbox button was pressed (only shown in `dev` and `preview` builds). Heard by flow, which starts the sandbox (staffs B7).
signal sandbox_requested(player: int)
## `player` picked a sandbox action on the pause menu's sandbox page: `imp_wave` or `reset_dummies`. Heard by flow (staffs B7).
signal sandbox_action_requested(player: int, action: StringName)

# --- Devices (sender: core/input) -------------------------------------------

## Sender: core/input. `device` (ids in input_manager.gd) took the free slot `player`, by a button press or as a bot's virtual device.
signal device_joined(player: int, device: int)
## Sender: core/input. `device` left slot `player`, by a button press or an unplugged gamepad. The slot is free again.
signal device_left(player: int, device: int)

# --- Spells and combat ------------------------------------------------------

## Sender: player. A cast left the wand of the seat `player`'s wizard (seat-keyed: for the HUD and Feel).
signal spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2)
## Sender: the actor kit (`Caster`). The actor `caster` (its node `actor`) has just cast, any actor, for visual reactions only (Feel's squash). For a seat's actor it comes right after `spell_cast`.
signal actor_cast(caster: int, actor: Node)
## Sender: the actor kit (`Caster`). The actor `caster` (its node `actor`) put another of its staffs on show, `staff` (living staffs H4: a press of a different staff button; the personality swap), before that press casts. For visual reactions only (Feel's poof).
signal staff_shown(caster: int, actor: Node, staff: int)
## Sender: core/projectiles. A projectile fired by the actor `caster` touched `target`.
## `tag` is the value given to `Projectiles.spawn()`, for looking up the damage.
signal projectile_hit(caster: int, target: Node, position: Vector2, tag: int)
## Sender: core/projectiles. Where and which way a projectile struck, for looks only (sparks, dust). `target` is the node it hit, sent just before `projectile_hit` for the same hit, or `null` when it ended on a wall or pillar. `caster` is the actor who fired it (NO_PLAYER for a shot of no actor), `position` the point it stopped at and `direction` the unit vector it was flying.
signal projectile_impact(caster: int, target: Node, position: Vector2, direction: Vector2)
## Sender: core/projectiles. A projectile fired by the actor `caster` ended without a hit: its life ran out or it struck a wall. `tag` is the value given to `Projectiles.spawn()`. Heard by core/spells (on expire) and feel (a small pop where a life ran out).
signal projectile_expired(caster: int, position: Vector2, tag: int)
## Sender: core/spells. A beam, a nova or a rain of the actor `caster` just fired, for looks only (they have no shot to draw). `form` is `&"rain"` (a telegraph: its payload falls on `origin` after `length` seconds) or `&"beam"` (`length` is how far it got, along `direction`) or `&"nova"` (a ring of shots leaves `origin`; `length` is 0) or `&"dash"` (the wizard dashes from `origin` along `direction` for `length` pixels, as far as the walls let it). `tint` is the colour of the spell's element (white for plain arcane) and `look` its packed look kinds (`CompiledSpell.look`), so the cue shows its cards.
signal form_shown(caster: int, form: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int)
## Sender: player. A build change asked for by `player` was refused; `reason` says why in plain words.
signal build_refused(player: int, reason: String)
## Sender: player. The component ids `player` may build with, in registry order. Sent when the wizard appears and whenever the bag changes.
signal bag_changed(player: int, bag: Array[StringName])
## Sender: player. The staff `staff` (0-3) of `player`'s own wizard was built or changed (never another actor's the seat drives). `plan` holds plain values for the builder (the cards, the casts of its cycle, wasted cards with their reasons, the numbers), as `Spells.staff_view` gives them. Heard by hud.
signal staff_changed(player: int, staff: int, plan: Dictionary)
## Sender: player. `player` cast their staff `staff` from `origin` along `direction`. Heard by feel.
signal staff_cast(player: int, staff: int, origin: Vector2, direction: Vector2)
## Sender: core/spells. A card of the actor `caster` moves it: `mode` is `&"dash"`, `&"teleport"`, `&"hook"`, `&"swap"` or `&"recoil"`; `to` is where it wants to go (the body stops at walls), over `seconds` (0 is at once); `tag` is the card's tag. Heard by player (a wizard's actor) and ai (an enemy's), each for its own actor id, which answer with `caster_move_finished`. Several requests can come in one step (a scatter, a burst, `mirror`): the body adds up the `recoil` requests of a step (so `mirror · recoil` cancels) and lets a later dash, teleport, hook or swap replace an earlier one.
signal caster_move_requested(caster: int, mode: StringName, to: Vector2, seconds: float, tag: int)
## Sender: player (a wizard's move) and ai (an enemy's; staffs F8c). The move the actor `caster` was asked for by `caster_move_requested` ended at `position`: the end point of a dash, teleport or hook. Heard by core/spells and feel (where a dash lands).
signal caster_move_finished(caster: int, mode: StringName, position: Vector2, tag: int)
## Sender: core/spells. A card of the actor `caster` (swap) moves `target` to `to`. Heard by ai.
signal target_move_requested(caster: int, target: Node, to: Vector2)
## Sender: core/spells. A card of the actor `caster` (blast, a payload's fallback) hits everything in the circle at `position` of `radius`, the caster included, with the hit profile of `tag`. Heard by combat.
signal area_hit_requested(caster: int, position: Vector2, radius: float, tag: int)
## Sender: core/spells. A card of the actor `caster` makes an entity of `kind` (`&"decoy"`, `&"familiar"`) at `position` that lasts `seconds` (INF, or 0 or less: until `entity_end_requested`, the room or the run ends); `tag` is the card's tag. `anchor` is what a familiar circles: -1 the caster's body, a `core/projectiles` slot for the shot whose trigger made it, or -2 the point `position` (that shot is gone). Heard by ai.
signal entity_spawn_requested(caster: int, kind: StringName, position: Vector2, seconds: float, tag: int, anchor: int)
## Sender: core/spells. The entities of the actor `caster` made by the card with `tag` end now (a `hold` switched off, or its staff rebuilt). Heard by ai, which answers with `entity_ended` for each.
signal entity_end_requested(caster: int, tag: int)
## Sender: ai. The entity of the actor `caster` of `kind` with `tag` ended at `position` (a decoy died, a familiar left). Heard by core/spells (its end point).
signal entity_ended(caster: int, kind: StringName, position: Vector2, tag: int)
## Sender: ai. The familiar of the actor `caster` with `tag` casts its payload from `position` along `direction`. Heard by core/spells.
signal familiar_cast_requested(caster: int, position: Vector2, direction: Vector2, tag: int)
## Sender: core/spells. Mana of the actor `caster` comes back (siphon). Heard by player and ai, each for its own actor.
signal mana_refund_requested(caster: int, amount: float)
## Sender: core/spells. `amount` of the mana of the seat `player`'s actor is now held by sustained cards (`hold`); 0 when none is on. Sent only for an actor a seat drives (every actor's Caster reads `Spells.reserved_mana`). Heard by nobody yet.
signal mana_reserved(player: int, amount: float)
## Sender: core/projectiles. A shot of the actor `caster` with `tag` stopped another team's shot at `position` with one of its shield charges. Heard by core/spells and feel.
signal shot_blocked(caster: int, position: Vector2, tag: int)
## Sender: combat. The reaction `reaction_id` (for example &"shatter") fired for the actor `caster` (or NO_PLAYER) at `position`.
signal reaction_triggered(caster: int, reaction_id: StringName, position: Vector2)
## Sender: combat. A discharge of the actor `caster` jumped from `from` (the body struck) to `to` (a body zapped), both in world pixels; one is sent for each body zapped, next to its `reaction_triggered` `discharge`. Heard by feel, which draws the arc.
signal discharge_arc(caster: int, from: Vector2, to: Vector2)
## Sender: combat. The actor `caster` (or NO_PLAYER) dealt `amount` damage to `target`.
signal damage_dealt(caster: int, target: Node, amount: int, position: Vector2)
## Sender: combat. A status effect from the actor `caster` (or NO_PLAYER) was put on `target`.
signal status_applied(caster: int, target: Node, status_id: StringName)
## Sender: combat. `enemy` died; the actor `killer` landed the last hit (or NO_PLAYER).
signal enemy_died(killer: int, enemy: Node, position: Vector2)

## Sender: combat. A barrier on the actor `actor` (shield charges from the card with `tag`) stopped a hit at `position`. Heard by core/spells and feel.
signal shield_blocked(actor: int, position: Vector2, tag: int)
## Sender: combat. A hit of the actor `caster` with `tag` killed `target` at `position`. Heard by core/spells (on kill).
signal kill_landed(caster: int, target: Node, position: Vector2, tag: int)
## Sender: combat. The actor `actor` took `amount` damage at `position` from a hit with `tag` (a spell's tag, whose `SpellTag.caster_of` is the actor that cast it; 0 for contact damage and a reaction's damage) of kind `kind` (`&"shot"`, `&"ray"`, `&"burst"`, `&"reaction"`, `&"status"`; a burn tick is not a hit, so it is not sent here). Heard by core/spells (on hurt: the hurt actor's own carriers fire).
signal actor_hurt(actor: int, amount: int, position: Vector2, tag: int, kind: StringName)
## Sender: combat. A hit of the actor `caster` with `tag` on `target` at `position` set off the reaction `reaction_id`. Heard by core/spells (on reaction); feel keeps `reaction_triggered`.
signal reaction_landed(caster: int, reaction_id: StringName, target: Node, position: Vector2, tag: int)
## Sender: core/spells. The actor `caster` gets a barrier of `charges` blocked hits for `seconds` (shield on a dash, a teleport or the caster); the card has `tag`. Heard by combat.
signal wizard_shield_requested(caster: int, charges: int, seconds: float, tag: int)
## Sender: core/spells. A card of the actor `caster` (magnet) pulls every enemy within `radius` of `position` toward it at `strength` pixels per second; the card has `tag`. Heard by combat.
signal pull_requested(caster: int, position: Vector2, radius: float, strength: float, tag: int)
## Sender: core/spells. A carrier of the actor `caster` with `possess` hit the actor `target` (an actor id): the caster's controller is to drive it for `seconds`; the card has `tag`. One per cast. Heard by actor (the Possession rule).
signal possess_requested(caster: int, target: int, seconds: float, tag: int)
## Sender: actor. The controller of the actor `caster` (the body that cast `possess`) now drives the actor `actor`; the caster's body stands with no controller. Heard by feel (a ring in the caster's ramp and the sound `possess`).
signal possess_started(caster: int, actor: int)
## Sender: actor. The possession of the actor `actor` by the controller of the actor `caster` ended (time up, a body down or dead, a newer possession); each controller is home again. Heard by feel (a ring going out).
signal possess_ended(caster: int, actor: int)
## Sender: combat. Just before `damage_dealt`: the hit of the actor `caster` on `target` for `amount` is of `kind` (`&"shot"`, `&"ray"`, `&"burst"`, `&"reaction"`, `&"status"`, and `&"heal"` for a heal). A wizard's contact hit counts as `&"shot"`. A wizard hit by their own spell has `caster` equal to their own actor id. Heard by feel.
signal hit_landed(caster: int, target: Node, amount: int, position: Vector2, kind: StringName)
## Sender: combat. A heal hit of the actor `caster` gave the wizard `target` `amount` health at `position`. Heard by player and feel.
signal heal_dealt(caster: int, target: Node, amount: int, position: Vector2)

# --- Players ----------------------------------------------------------------

## Sender: player. `player` has no health left.
signal player_downed(player: int)
## Sender: player. `player` was revived by `reviver`.
signal player_revived(player: int, reviver: int)
## Sender: coop. `player` is downed and being revived: `progress` (0 to 1) is how far the hold has got. Sent when it changes (so every frame while a revive fills or drains); 0 means the revive stopped or is done.
signal revive_progress(player: int, progress: float)
## Sender: player. The health or the whole-number mana of `player`'s own wizard changed (also while the seat drives another actor or an enemy drives the wizard), or the wizard appeared. Carries all the numbers so a listener never has to ask.
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
## Sender: flow. A run started in the sandbox (`on` true) or out of it (false), or the sandbox run ended (false). Heard by hud, whose pause menu shows its Sandbox entry only while it is on.
signal sandbox_changed(on: bool)
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

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

## Commands (online-ready N2, docs/milestones/online-ready.md): the HUD's `*_requested` events the
## simulation hears (`InputFrame.COMMAND_NAMES`: the builder's, the sandbox page's,
## rewards and doors) apply at the start of the next tick, never in the middle of one. The
## HUD sends them as before; the bus hands each to `command_sink` (the frames service,
## core/sim/frames.gd, the autoload "Frames"), which puts it into its seat's next input frame and
## applies it with `apply_command` when that tick starts, so a replay (and later the network) gives
## the same command at the same tick. With no sink (a test's own bus) a command applies as it is
## sent. The simulation hears a command through `listen`, never by connecting to its signal (that
## would hear it as it is sent); the HUD and tests may still connect to see it sent. The requests
## that start a run (`play_requested`, `sandbox_requested`, `hub_requested`) are not commands: a
## replay's header says how its run started.
##
## "No actor" (`Actors.NONE`): the world, where no actor did it. Also "no seat".
const NO_PLAYER: int = -1
## The kinds of number `damage_number_shown` tells (props W5): a hit, a heal, and a hit that took
## nothing (an invincible actor). Its sender and its listener both name them from here.
const NUMBER_HIT: StringName = &"hit"
const NUMBER_HEAL: StringName = &"heal"
const NUMBER_SPARED: StringName = &"spared"

# --- Player intent from the HUD (sender: hud) -------------------------------

## A run of waves, at once, for `player`: the automated runs (the bots, the stress run), the tests and
## the online spike's Host/Join send it (the main menu's Play sends `hub_requested` since online-lobby
## L1). Heard by flow. A run's start, not a command.
signal play_requested(player: int)
## Sender: hud. `player` asked to put the card `card_id` into slot `slot` of their staff `staff` (0-3: A, X, Y, B); `&""` empties the slot. Heard by player, which applies it (staffs, docs/milestones/M2-staffs.md).
signal staff_change_requested(player: int, staff: int, slot: int, card_id: StringName)
## Sender: hud. `player` asked to set every slot of their staff `staff` at once: `cards` holds the card ids by slot (`&""` for an empty slot), as many as the staff has slots or fewer (the rest are emptied). The radial builder sends it for a push-right insert, a take-out that closes the gap, an undo and a clear, so each is one change. Heard by player.
signal staff_cards_requested(player: int, staff: int, cards: Array[StringName])
## A player picked reward choice number `choice`. Heard by rewards.
signal reward_pick_requested(player: int, choice: int)
## A player voted for door number `door`. Heard by flow.
signal door_vote_requested(player: int, door: int)
## Sender: hud. The "Effect slots" slider in the pause menu (Settings) moved: how many effects
## (the glowing flares of casts, impacts, rings and dashes) may show at once. Heard by feel.
signal effect_slots_changed(slots: int)
## Sender: hud. The "Screen shake" switch in the pause menu (Settings) flipped, or the saved choice was loaded when the menu was bound. Heard by feel, which sets `shake_enabled`.
signal screen_shake_changed(enabled: bool)
## Sender: hud. The "Damage numbers" switch in the pause menu (Settings) flipped, or the saved choice was loaded when the menu was bound (props W5). Heard by feel, which shows or hides every actor's damage numbers. The view's only: it changes nothing in the game.
signal damage_numbers_changed(on: bool)
## Sender: hud. The "Max shots" slider in the pause menu (Settings) moved, or a saved choice was loaded when the menu was bound: this machine's cap on live shots (`ShotCap` in core/settings). Heard by core/sim (the Tick), which keeps it for the next run (`SessionRules.machine()`, online-ready N11); a run playing changes only by `shot_cap_requested`.
signal projectile_cap_changed(cap: int)
## Sender: hud. `player` moved the "Max shots" slider while a run plays: the run's cap on live shots from the next tick on (a command, recorded with the tick; online-ready N11). Heard by core/sim (the Tick), which sets `sim.rules.shot_cap` and hands it to core/projectiles (`set_cap`: the shots in the air end).
signal shot_cap_requested(player: int, cap: int)
## Sender: hud. The "Particles" slider in the pause menu (Settings) moved, or a saved choice was loaded when the menu was bound: how many motes may be in the world at once (`MoteCap` in core/settings; 0 is off). Heard by feel, which remakes its mote ring (the motes in the air end).
signal mote_cap_changed(cap: int)
## Sender: hud. The "Particle amount" slider in the pause menu (Settings) moved, or a saved choice was loaded when the menu was bound: the share of its count every moment's motes are thrown at (`MoteDensity` in core/settings; 0 throws none). Heard by feel, which hands it to its mote ring.
signal mote_density_changed(density: float)
## Sender: hud. The "Floor marks" switch in the pause menu (Settings) flipped, or a saved choice was loaded when the menu was bound: whether the room keeps its floor marks (`FloorMarks` in core/settings). Heard by feel, which makes or frees its mark layer (the marks so far go).
signal floor_marks_changed(on: bool)
## Sender: hud. The "Spell light" switch in the pause menu (Settings) flipped, or a saved choice was loaded when the menu was bound: whether shots light the world round them (`SpellLightSetting` in core/settings). Heard by feel, which makes or frees its light buffer.
signal spell_light_changed(on: bool)
## Sender: hud. The "Tailless motes" dev slider in the pause menu (Settings) moved, or a saved choice was loaded when the menu was bound: the spark pool the shots' births share while the tails are off (`TaillessMotes` in core/settings; S5 step 4). Heard by core/projectiles (`tailless_particle_cap`) and feel (`Motes.frame_rows`, `TaillessMotes.frame_rows_of`).
signal tailless_motes_changed(pool: int)
## The Sandbox button was pressed (in every build). Heard by flow, which starts the sandbox (staffs B7).
signal sandbox_requested(player: int)
## Sender: hud. The main menu's Play was pressed: everyone goes to the hub, the island where players
## join and start a run from the teleporter stone (docs/milestones/online-lobby.md, L1). Heard by
## flow, which starts it, and core/input, which joins the keyboard first. A run's start, as
## `sandbox_requested` is (`Replay.STARTS`), not a command.
signal hub_requested(player: int)
## Sender: hud. `player` pressed A (`accept`) with no menu open while the hub's teleporter stone was
## lit (`start_stone_changed`): start the run (online-lobby L1). A command: heard by flow at the next
## tick's start, which starts the run of waves if the stone is still lit then.
signal run_requested(player: int)
## `player` picked a sandbox action on the pause menu's sandbox page: `reset_dummies` or `clear_enemies`. Heard by flow (staffs B7; the enemy arena, enemy AI AI8).
signal sandbox_action_requested(player: int, action: StringName)
## Sender: hud. `player` asked the enemy arena (the sandbox page, enemy AI AI8) for `count` enemies of the registry's `enemy_id`. Heard by flow.
signal sandbox_spawn_requested(player: int, enemy_id: StringName, count: int)
## Sender: hud. The sandbox page's "AI view" switch flipped: each enemy shows what its AI is doing. Heard by ai (enemy AI AI8).
signal ai_view_changed(on: bool)
## `player` opened (`on` 1) or closed (`on` 0) the pause menu: offline the game stops while it is
## open (online-ready N4). A command: heard by the Tick (core/sim/tick.gd, `Sim.stop`), which pauses
## the tree for the picture once the game stands stopped.
signal pause_requested(player: int, on: int)

# --- Playing online (netcode spike S4, docs/milestones/netcode-spike.md) --------
# The main menu's Host and Join. The HUD knows no network: it sends what its player asked and
# shows what comes back. None is a command (no run plays yet; the run they start is a replay's
# start, as Play's is).

## Sender: hud. `player` pressed Host: this machine makes a code for the other player. Heard by net.
signal online_host_requested(player: int)
## Sender: hud. `player` pressed Join and gave the host's code `code` (pasted text: untrusted, checked by net before anything uses it). Heard by net, which answers with this machine's own code.
signal online_join_requested(player: int, code: String)
## Sender: hud. The host's `player` gave the code `code` the joining player sent back (pasted text, as above). Heard by net.
signal online_answer_requested(player: int, code: String)
## Sender: hud. `player` pressed A (`accept`) with no menu open while their wizard stood on the hub's multiplayer altar (`altar_changed`): open this party to other machines (online-lobby L2). Not a command: the simulation never knows a network exists. Heard by net, which opens a room and says its code (`online_changed`); nothing connects anywhere before this.
signal online_open_requested(player: int)
## Sender: hud. `player` gave up hosting or joining before the run began. Heard by net.
signal online_leave_requested(player: int)
## Sender: net. A run will start soon that cannot wait at its start: do the work that must be ready before a room now (behind the loading screen, `loading_started` to `loading_finished`), so the run starts on the tick it is asked for. Two machines that start one run together must: a load takes each its own time. Heard by flow (its `play_tasks`); with nothing to load, nothing happens.
signal play_load_requested()
## The phases of `online_changed`, by name.
const ONLINE_OFF: StringName = &"off"
const ONLINE_MAKING: StringName = &"making"
const ONLINE_CODE: StringName = &"code"
const ONLINE_LINKING: StringName = &"linking"
const ONLINE_LINKED: StringName = &"linked"
const ONLINE_PLAYING: StringName = &"playing"
const ONLINE_ENDED: StringName = &"ended"
const ONLINE_FAILED: StringName = &"failed"
## Sender: net. Where Host or Join stands: `phase` is `&"off"` (nothing asked, or given up), `&"making"` (this machine's code is being made), `&"code"` (`code` is this machine's code, for the other player), `&"linking"` (both codes given, the machines look for each other), `&"linked"` (they found each other; the run starts in a moment), `&"playing"` (the run plays), `&"ended"` (the other machine left a run that played) or `&"failed"`. `note` says in plain words what the player should know (why it failed, a code refused). Heard by hud (the main menu, the online line).
signal online_changed(phase: StringName, code: String, note: String)
## Sender: net. One line of text about the run played online (its counters), about once a second while it plays; `""` clears it. Heard by hud, which shows it as it is.
signal online_line_changed(line: String)

# --- Devices (sender: core/input) -------------------------------------------

## Sender: core/input. `device` (ids in input_manager.gd) took the free slot `player`, by a button press or as a bot's virtual device.
signal device_joined(player: int, device: int)
## Sender: core/input. `device` left slot `player`, by a button press or an unplugged gamepad. The slot is free again.
signal device_left(player: int, device: int)

# --- Seats (sender: core/sim, the frames service) -----------------------------

## Sender: the frames service (core/sim/frames.gd). The seat `player` plays from now on: the
## simulation's join (Coop hears it), never a device's. Offline as its device joins; while a replay
## plays (a file, or an online client's live one), at the start of the tick whose frame says so.
signal seat_joined(player: int)
## Sender: the frames service. The seat `player` plays no more (as `seat_joined`).
signal seat_left(player: int)

# --- Spells and combat ------------------------------------------------------

## Sender: player. A cast left the wand of the seat `player`'s wizard (seat-keyed: for the HUD and Feel).
signal spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2)
## Sender: the actor kit (`Caster`). The actor `caster` (its node `actor`) has just cast, any actor, for visual reactions only (its body's movement is its carrier's `staff_pose`, drawn by its look from Spells). For a seat's actor it comes right after `spell_cast`. Heard by nobody in the game yet (tests count casts with it).
signal actor_cast(caster: int, actor: Node)
## Sender: the actor kit (`Caster`). The actor `caster` (its node `actor`) put another of its staffs on show, `staff` (living staffs H4: a press of a different staff button; the personality swap), before that press casts. For visual reactions only (Feel's poof).
signal staff_shown(caster: int, actor: Node, staff: int)
## Sender: core/projectiles. A projectile fired by the actor `caster` touched `target`.
## `tag` is the value given to `Projectiles.spawn()`, for looking up the damage. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
## Every hit, of every sender (shots, rays, sweeps, blasts), is this one event, sent as it lands: there is no batched path. A listener that wants to share work across a frame's hits keeps what each asks for and does it once in its own step (owner, 2026-11-07: DECISIONS, "Bundled hit events dropped").
signal projectile_hit(caster: int, target: Node, position: Vector2, tag: int, shot: int)
## Sender: core/projectiles. Where and which way a projectile struck, for looks only (sparks, dust). `target` is the node it hit, sent just before `projectile_hit` for the same hit, or `null` when it ended on a wall or pillar. `caster` is the actor who fired it (NO_PLAYER for a shot of no actor), `position` the point it stopped at and `direction` the unit vector it was flying.
signal projectile_impact(caster: int, target: Node, position: Vector2, direction: Vector2)
## Sender: core/projectiles. A projectile fired by the actor `caster` ended without a hit: its life ran out or it struck a wall. `tag` is the value given to `Projectiles.spawn()`. Heard by core/spells (on expire) and feel (a small pop where a life ran out). `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal projectile_expired(caster: int, position: Vector2, tag: int, shot: int)
## Sender: core/spells. A carrier of the actor `caster` just showed itself, for looks only (they have no shot to draw). `carrier_card` names the carrier card whose looks show (Feel plays its `shown_cue` here): `&"beam"` (`length` is how far it got, along `direction`) or `&"dash"` (the wizard dashes from `origin` along `direction` for `length` pixels, as far as the walls let it) or `&"slam"` (its strike at `origin`, `length` its ring) or a teleport's card (it leaves `origin` along `direction` for `length` pixels), a swap's (one end of its trade, at `origin`, the other `length` pixels along `direction`; sent for each end), a decoy's or a familiar's (it appears at `origin`); or a modifier that shows itself, named by its card in the same place: a zap (`Spells.ZAP_CARD`, the Zap modifier's id; `length` its arc). `tint` is the colour of the spell's element (white for plain arcane) and `look` its packed look kinds (`CompiledSpell.look`), so the cue shows its cards.
signal carrier_shown(caster: int, carrier_card: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int)
## Sender: core/spells. A carrier of the actor `caster` with no shot to end it ended at `at`, for looks only: a teleport or dash where its body landed (the carrier's end point), a slam where it struck. `carrier_card` names its carrier card (Feel plays the card's `end_cue` there), `direction` the way it went, `size` how big in pixels (a slam's ring, its card's radius), `tint` and `look` as `carrier_shown`'s.
signal carrier_ended(caster: int, carrier_card: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int)
## Sender: core/spells (a `blast` going off: the cue its card names, `ModifierBase.cue`), and anything else with a moment to show (an exploding barrel: `&"fireball"`; a prop's look, the cue of the state it enters, props W7; S6 item 13: flow `wave_start` and `stone_lit` (the hub's stone lighting, as no actor), player `revive`, combat `shield_block` and `pull`). Play the cue `cue` (a `CueBase`, `content/cues/<cue>.tres`; an unknown one shows nothing) at `at`, for looks and feel only (the hits are sent apart: each body a blast catches is a `projectile_hit` of its carrier). `caster` is the actor it is of (NO_PLAYER for none), `direction` the way it faces (zero for none), `size` how big in pixels (an explosion's radius, a ground strike's reach; what a part's `reach` is times), `tint` its element's colour (white for plain) and `look` its packed look kinds (`CompiledSpell.look`; 0 for none). Heard by gameplay/feel (`Feel.play_cue`).
signal cue_shown(caster: int, cue: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int)
## Sender: player. A build change asked for by `player` was refused; `reason` says why in plain words.
signal build_refused(player: int, reason: String)
## Sender: player. The component ids `player` may build with, in registry order. Sent when the wizard appears and whenever the bag changes.
signal bag_changed(player: int, bag: Array[StringName])
## Sender: player. The staff `staff` (0-3) of `player`'s own wizard was built or changed (never another actor's the seat drives). `plan` holds plain values for the builder (the cards, the casts of its cycle, wasted cards with their reasons, the numbers), as `Spells.staff_view` gives them. Heard by hud.
signal staff_changed(player: int, staff: int, plan: Dictionary)
## Sender: player. `player` cast their staff `staff` from `origin` along `direction`. Heard by feel.
signal staff_cast(player: int, staff: int, origin: Vector2, direction: Vector2)
## Sender: core/spells. A card of the actor `caster` moves it: `mode` is `&"dash"`, `&"teleport"`, `&"pull"`, `&"swap"` or `&"recoil"`; `move` is the way and the distance (the body stops at walls), over `seconds` (0 is at once); `tag` is the card's tag. Heard by player (a wizard's actor) and ai (an enemy's), each for its own actor id, which answer each with `caster_move_finished`. Every move adds up (rules R4 F1): several requests in one step (a scatter, a burst, `mirror`) or while one runs all move the body, each over its own time.
signal caster_move_requested(caster: int, mode: StringName, move: Vector2, seconds: float, tag: int)
## Sender: player (a wizard's move) and ai (an enemy's; staffs F8c). A move the actor `caster` was asked for by `caster_move_requested` ended at `position` (every move is answered once). Heard by core/spells (the end point of a dash, teleport or pull) and feel (where a dash lands).
signal caster_move_finished(caster: int, mode: StringName, position: Vector2, tag: int)
## Sender: core/spells. A card of the actor `caster` (swap) moves `target` to `to`. Heard by ai.
signal target_move_requested(caster: int, target: Node, to: Vector2)
## Sender: core/spells. A card of the actor `caster` makes an entity of `kind` (`&"decoy"`, `&"familiar"`) at `position` that lasts `seconds` (INF, or 0 or less: until `entity_end_requested`, the room or the run ends); `tag` is the card's tag. `anchor` is what a familiar circles: -1 the caster's body, -3 - id the body of the actor `id` whose payload made it (a decoy's: `SpellRuntime.body_caster`), a `core/projectiles` slot for the shot whose trigger made it, or -2 the point `position` (that shot is gone). Heard by ai, which names the actor it made for a decoy in `Spells.entity_body` while this is sent.
signal entity_spawn_requested(caster: int, kind: StringName, position: Vector2, seconds: float, tag: int, anchor: int)
## Sender: core/spells. The entities of the actor `caster` made by the card with `tag` end now (a `hold` switched off, or its staff rebuilt). Heard by ai, which answers with `entity_ended` for each.
signal entity_end_requested(caster: int, tag: int)
## Sender: ai. The entity of the actor `caster` of `kind` with `tag` ended at `position` (a decoy died, a familiar left). Heard by core/spells (its end point); ai names the entity's key in `Spells.entity_key` while this is sent, so only that entity's timers leave.
signal entity_ended(caster: int, kind: StringName, position: Vector2, tag: int)
## Sender: core/spells. Mana of the actor `caster`'s staff `staff` (the staff whose shot hit) comes back (siphon). Heard by every actor's Caster, each for its own actor.
signal mana_refund_requested(caster: int, staff: int, amount: float)
## Sender: core/spells. A cast of the actor `caster`'s staff `staff` that wound up has left, and costs `amount` mana now (docs/milestones/cast-timing.md: checked at the press, paid as it leaves). Heard by every actor's Caster, each for its own actor.
signal mana_spend_requested(caster: int, staff: int, amount: float)
## Sender: core/spells. A press of the actor `caster`'s staff `staff` found no cast left in its cycle that its mana pays: each was skipped, the cycle ended there and its cooldown runs (docs/milestones/cast-timing.md, T3). Heard by nobody yet (a fizzle's look and sound come with the corner panel's part, T5).
signal cast_fizzled(caster: int, staff: int)
## Sender: core/spells. A cast of the actor `caster`'s staff `staff` started winding up (docs/milestones/cast-timing.md): its first carrier is the carrier card `carrier_card`, from `origin` along `direction` (the aim follows the caster until it leaves), for `seconds` (a chill or a freeze stretches it; `Spells.is_winding` says when it is over), in its element's `tint` with its packed `look`, under `tag`. `cue` is the staff's own wind-up look (`StaffBase.wind_cue`: a barrel's fuse), `&""` for the card's. Heard by gameplay/feel, which plays `cue`, else the card's `wind_cue` (an enemy's telegraph: only for a caster not on the players' team).
signal cast_winding(caster: int, staff: int, carrier_card: StringName, origin: Vector2, direction: Vector2, seconds: float, tint: Color, look: int, tag: int, cue: StringName)
## Sender: core/spells. A cast of the actor `caster`'s staff `staff` leaves now: at once for a cast that does not wind up, else as its wind-up ends; sent just before its shots start, so what the caster becomes as its cast leaves is what they meet (props W6: a barrel's fuse burns out, it is rubble, its blast goes off); a cast that then finds no room for any shot (every one inside a wall) was told all the same. Heard by the actor kit (a prop's `PropStateTriggers`, for its `cast` triggers).
signal cast_left(caster: int, staff: int)
## Sender: core/spells. `amount` of the mana of staff `staff` of the seat `player`'s actor is now held by sustained cards (`hold`); 0 when none is on. Sent only for an actor a seat drives (every actor's Caster reads `Spells.reserved_mana`). Heard by nobody yet.
signal mana_reserved(player: int, staff: int, amount: float)
## Sender: core/projectiles. A shot of the actor `caster` with `tag` stopped another team's shot at `position` with one of its shield charges (or a carrier's own shield did: `Projectiles.impact_carrier` is then that carrier's id while this is sent: its own `id()` (`swing`, `beam`, `slam`, `dash`, `teleport`, `decoy`, ...), a chain jump's `beam` as a ray's; a swing's is a parry). Heard by core/spells and feel. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal shot_blocked(caster: int, position: Vector2, tag: int, shot: int)
## Sender: core/projectiles. The carrier with `tag` of the actor `caster` (a deflecting shot, a swing or a beam) deflected another team's shot at `position`: it turned, sped up and is `caster`'s now (melee I3). The deflected shot is `shot`. Heard by core/spells (`on block`: a deflect is a block, owner 2026-10-29) and feel (the deflect's flash). `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal shot_deflected(caster: int, position: Vector2, tag: int, shot: int)
## Sender: combat. The reaction `reaction_id` (for example &"shatter") fired for the actor `caster` (or NO_PLAYER) at `position`. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal reaction_triggered(caster: int, reaction_id: StringName, position: Vector2, shot: int)
## Sender: combat. A discharge of the actor `caster` jumped from `from` (the body struck) to `to` (a body zapped), both in world pixels; one is sent for each body zapped, next to its `reaction_triggered` `discharge`. Heard by feel, which draws the arc.
signal discharge_arc(caster: int, from: Vector2, to: Vector2)
## Sender: combat. The actor `caster` (or NO_PLAYER) dealt `amount` damage to `target`.
signal damage_dealt(caster: int, target: Node, amount: float, position: Vector2)
## Sender: combat. A status effect from the actor `caster` (or NO_PLAYER) was put on `target`.
signal status_applied(caster: int, target: Node, status_id: StringName)
## Sender: actor (a prop's `PropStateTriggers`, props W6). The prop `actor` entered its state `state` (`PropState.state_id`), by one of its triggers. For other areas: the prop's own look hears its component's `entered` directly, as an actor's parts hear its body. Heard by nobody in the game yet (tests).
signal prop_state_changed(actor: int, state: StringName)
## Sender: flow (its hub rules, `HubRules`, props W8c). The prop `actor` is asked to enter its state `state` from outside its triggers (the hub's `run_start` stone, lit while every wizard stands on it), during the tick, as a trigger's `then` would. Heard by actor (that prop's `PropStateTriggers`, which enters it at once; a state it lacks, or one it is in, changes nothing). Not a command: the simulation asks itself.
signal prop_state_requested(actor: int, state: StringName)
## Sender: core/spells. A carrier that hits nothing gives `target` a status (a portal's infusion on
## the bodies that go through it): Combat applies it as `apply_status` does, with no hit.
signal status_requested(caster: int, target: Node, status_id: StringName, duration: float, strength: float)
## Sender: combat. `enemy` died; the actor `killer` landed the last hit (or NO_PLAYER). `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal enemy_died(killer: int, enemy: Node, position: Vector2, shot: int)

## Sender: combat. A barrier on the actor `actor` (shield charges from the card with `tag`) stopped a hit at `position`. Heard by core/spells and feel.
signal shield_blocked(actor: int, position: Vector2, tag: int)
## Sender: combat. The barrier on the actor `actor` changed: it now blocks `charges` more hits for `seconds` more (0 and 0: it is gone), from the card with `tag`. `way` is the way the hit a block stopped flew (zero when no block changed it: given, grown, run out or cleared), `radius` the actor's hurt circle. For looks only (feel draws the barrier). Heard by feel.
signal barrier_changed(actor: int, charges: int, seconds: float, tag: int, way: Vector2, radius: float)
## Sender: combat. A hit of the actor `caster` with `tag` killed `target` at `position`. Heard by core/spells (on kill). `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal kill_landed(caster: int, target: Node, position: Vector2, tag: int, shot: int)
## Sender: combat. The actor `actor` took `amount` damage at `position` from a hit with `tag` (a spell's tag, whose `SpellTag.caster_of` is the actor that cast it; 0 for contact damage and a reaction's damage) of kind `kind` (`&"shot"`, `&"ray"`, `&"swing"`, `&"burst"`, `&"reaction"`, `&"status"`; a burn tick is not a hit, so it is not sent here). Heard by core/spells (on hurt: the hurt actor's own carriers fire).
signal actor_hurt(actor: int, amount: float, position: Vector2, tag: int, kind: StringName)
## Sender: combat. A hit of the actor `caster` with `tag` on `target` at `position` set off the reaction `reaction_id`. Heard by core/spells (on reaction); feel keeps `reaction_triggered`. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal reaction_landed(caster: int, reaction_id: StringName, target: Node, position: Vector2, tag: int, shot: int)
## Sender: core/spells. The actor `caster` gets a barrier of `charges` blocked hits for `seconds` (shield on a dash, a teleport or the caster); the card has `tag`. Heard by combat.
signal wizard_shield_requested(caster: int, charges: int, seconds: float, tag: int)
## Sender: core/spells. A card of the actor `caster` (magnet) pulls every enemy within `radius` of the line from `position` to `to` toward its nearest point on it at `strength` pixels per second (a shot's: `to` is `position`; a beam's: one piece of its path); the card has `tag`. Heard by combat.
signal pull_requested(caster: int, position: Vector2, radius: float, strength: float, tag: int, to: Vector2)
## Sender: core/spells. A carrier of the actor `caster` with `possess` hit the actor `target` (an actor id): the caster's controller is to possess it for `seconds`; the card has `tag`. One per hit. Heard by actor (the Possession rule).
signal possess_requested(caster: int, target: int, seconds: float, tag: int)
## Sender: actor. A controller now possesses the actor `actor` (it drives it, or a puppet copies it); `caster` is that controller's home body (the body that cast `possess` when it has none). Heard by feel (a ring in the caster's ramp and the sound `possess`).
signal possess_started(caster: int, actor: int)
## Sender: actor. The possession of the actor `actor` by the controller whose home body is `caster` ended (time up, the actor down or dead, a newer possession); the actor has its own controller back. Heard by feel (a ring going out).
signal possess_ended(caster: int, actor: int)
## Sender: combat. Just before `damage_dealt`: the hit of the actor `caster` on `target` for `amount` is of `kind` (`&"shot"`, `&"ray"`, `&"swing"`, `&"burst"`, `&"reaction"`, `&"status"`, and `&"heal"` for a heal). A wizard's contact hit counts as `&"shot"`. A wizard hit by their own spell has `caster` equal to their own actor id. Heard by feel. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal hit_landed(caster: int, target: Node, amount: float, position: Vector2, kind: StringName, shot: int)
## Sender: combat. A heal hit of the actor `caster` gave `target` (any actor, friend or foe) `amount` health at `position`. Heard by player and feel.
signal heal_dealt(caster: int, target: Node, amount: float, position: Vector2)
## Sender: actor (its `DamageNumbers` look, props W5). A hit on the actor `actor` shows its number: `amount` rising `rise` pixels from `position` (world pixels, above its hurt shape) for `seconds`, at `size` times the plain text. `kind` is `NUMBER_HIT` (in the colour of the element `element`, white for `&""`), `NUMBER_HEAL`, or `NUMBER_SPARED` (a hit that took nothing: an invincible actor, the hub). View only; heard by feel, which draws every actor's numbers in one place.
signal damage_number_shown(actor: int, position: Vector2, amount: float, element: StringName, kind: StringName, rise: float, seconds: float, size: float)

# --- Players ----------------------------------------------------------------

## Sender: player. `player` has no health left.
signal player_downed(player: int)
## Sender: player. `player` was revived by `reviver`.
signal player_revived(player: int, reviver: int)
## Sender: coop. `player` is downed and being revived: `progress` (0 to 1) is how far the hold has got. Sent when it changes (so every frame while a revive fills or drains); 0 means the revive stopped or is done.
signal revive_progress(player: int, progress: float)
## Sender: player. The health of `player`'s own wizard, the whole-number mana of its staff on show (`Caster.current`; every staff has its own pool), or which staff is on show changed (also while the seat drives another actor or an enemy drives the wizard), or the wizard appeared. Carries all the numbers so a listener never has to ask.
signal player_stats_changed(player: int, health: float, max_health: float, mana: float, max_mana: float)
## Sender: player. The whole-number mana of staff `staff` (0-3) of `player`'s own wizard changed, or the wizard appeared: that staff's own pool (owner, 2026-11-01). Heard by the builder (the viewed staff's bar and mana shares).
signal staff_mana_changed(player: int, staff: int, mana: float, max_mana: float)
## Sender: coop. `player` joined the game.
signal player_joined(player: int)
## Sender: coop. `player` left the game.
signal player_left(player: int)

# --- Run and rooms ----------------------------------------------------------

## Sender: run. A run began with `player_count` players.
signal run_started(player_count: int)
## Sender: run. The run is over; `victory` is true if the players won.
signal run_ended(victory: bool)
## Sender: flow. The room just made, in world pixels (from (0, 0), `RoomPlaces.size`: what its
## camera's limits are), sent just before `room_entered`. Heard by coop: the party's view stays
## inside it, with no camera read (online-ready N9).
signal room_laid_out(bounds: Rect2)
## Sender: flow. The players entered the room `room_id`.
signal room_entered(room_id: StringName)
## Sender: coop. The part of the world (world pixels) the party's shared view holds, worked out on
## the tick from where the wizards stand, and `party`, the box round them inside it; sent when
## either changes. Heard by feel, whose party
## camera eases towards the view as it is drawn, keeping `party` in the picture, so the simulation
## never reads the camera (online-ready N3, N9).
signal view_fitted(view: Rect2, party: Rect2)
## Sender: core/loading. Work before playing has begun behind the loading screen (`Loading.run`;
## Flow runs `play_tasks` on Play). Heard by hud, which shows the screen until `loading_finished`.
signal loading_started()
## Sender: core/loading. `done` of the load's `total` units are done (the screen's bar). Heard by hud.
signal loading_progressed(done: int, total: int)
## Sender: core/loading. The load is over (done, or cancelled). Heard by hud.
signal loading_finished()
## Sender: flow. The room `room_id` was cleared.
signal room_cleared(room_id: StringName)
## Sender: flow. A run started in the sandbox (`on` true) or out of it (false), or the sandbox run ended (false). Heard by hud, whose pause menu shows its Sandbox entry only while it is on.
signal sandbox_changed(on: bool)
## Sender: flow. In the hub (online-lobby L1): `standing` of the `wizards` there stand on the
## teleporter stone (a prop of the role `run_start`, where its area is; `HubRules`); `lit` while all of them do (and at least one is there),
## when any seat's A starts the run (`run_requested`). Sent as the hub starts and whenever it
## changes; (0, 0, false) when the hub is left. Heard by hud (the stone line; A on the lit stone).
## The stone's look is the prop standing on it, which flow puts in its state `lit` or `unlit`
## (props W8, `prop_state_requested`), so feel needs no word of it.
signal start_stone_changed(standing: int, wizards: int, lit: bool)
## Sender: flow. The party entered the hub (`in_hub` true: a run in the hub room began) or left it (a run of waves from the stone, the game stopped). Sent when it changes. Heard by net (a machine may join a party only while it is in the hub); the simulation never reads it back.
signal hub_changed(in_hub: bool)
## Sender: flow. In the hub (online-lobby L2): the seats whose wizards stand on the multiplayer altar (a prop of the role `party_altar`, where its area is), a bit each; 0 when the hub is left. Sent whenever it changes. Heard by hud (A on the altar asks to open the room, `online_open_requested`).
signal altar_changed(seats: int)
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


## Where a command goes when it is sent, as `(name, args)` with the seat first in `args`: the frames
## service sets it. Unset, a command applies at once (`apply_command`).
var command_sink: Callable = Callable()
## The simulation's listeners per command, by name (`listen`).
var _listeners: Dictionary = {}


func _init() -> void:
	for command: StringName in InputFrame.COMMAND_NAMES:
		if has_signal(command):
			_listeners[command] = []
			connect(command, _on_command.bind(command))


## `callable` hears the command `command` (one of `InputFrame.COMMAND_NAMES` with a signal here) when
## it applies, with the signal's arguments: at the next tick's start, or at once with no sink.
func listen(command: StringName, callable: Callable) -> void:
	if not _listeners.has(command):
		push_error("Events: %s is not a command (InputFrame.COMMAND_NAMES)." % command)
		return
	var listeners: Array = _listeners[command]
	for at in range(listeners.size() - 1, -1, -1):
		if not (listeners[at] as Callable).is_valid():
			listeners.remove_at(at)
	listeners.append(callable)


## Apply the command `command` now: every listener hears `args` (the seat first), in the order
## they listened. A listener whose object is gone is skipped.
func apply_command(command: StringName, args: Array) -> void:
	for callable: Callable in _listeners.get(command, []):
		if callable.is_valid():
			callable.callv(args)


func _on_command(...args: Array) -> void:
	var command: StringName = args.pop_back()
	if command_sink.is_valid():
		command_sink.call(command, args)
	else:
		apply_command(command, args)

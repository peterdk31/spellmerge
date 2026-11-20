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
## simulation hears (`InputFrame.COMMAND_NAMES`: the builder's, the pause menu's,
## the hub's, the items', rewards and doors) apply at the start of the next tick, never in the middle of one. The
## HUD sends them as before; the bus hands each to `command_sink` (the frames service,
## core/sim/frames.gd, the autoload "Frames"), which puts it into its seat's next input frame and
## applies it with `apply_command` when that tick starts, so a replay (and later the network) gives
## the same command at the same tick. With no sink (a test's own bus) a command applies as it is
## sent. The simulation hears a command through `listen`, never by connecting to its signal (that
## would hear it as it is sent); the HUD and tests may still connect to see it sent. The requests
## that start a run (`play_requested`, `hub_requested`) are not commands: a
## replay's header says how its run started.
##
## "No actor" (`Actors.NONE`): the world, where no actor did it. Also "no seat".
const NO_PLAYER: int = -1
## The rooms of a world (connected biomes CB3, "Room events"): `room_entered`, `room_left`,
## `room_cleared`, `room_built` and `room_items_placed` name the room by number, a biome's by its
## place in the map (`BiomeMap`: 0 its start room; a bridge numbered after the rooms), the hub's
## FIRST_ROOM (its one room). FIRST_ROOM entered is a new world:
## what a listener keeps of the world (decoys, revives, the camera, the ground's items) starts over
## then, and only then. ALL_ROOMS: every room of the world at once (`room_left` as the world goes).
const FIRST_ROOM: int = 0
## `item_picked_up`'s kind for a reward item's offer taken (not an `ItemKinds` kind: the reward item
## on the floor, gameplay/rewards).
const PICKUP_REWARD: StringName = &"reward"
## `shelf_changed`'s and `shelf_near_changed`'s view kind for a shop's reroll sign (not an item kind).
const SHELF_SIGN: StringName = &"shelf_sign"
const ALL_ROOMS: int = -1
## The kinds of number `damage_number_shown` tells (props W5): a hit, a heal, and a hit that took
## nothing (an invincible actor). Its sender and its listener both name them from here.
const NUMBER_HIT: StringName = &"hit"
const NUMBER_HEAL: StringName = &"heal"
const NUMBER_SPARED: StringName = &"spared"

# --- Player intent from the HUD (sender: hud) -------------------------------

## A run of rooms, at once, for `player`: the automated runs (the bots, the stress run), the tests and
## the online spike's Host/Join send it (the main menu's Play sends `hub_requested` since online-lobby
## L1). Heard by flow. A run's start, not a command.
signal play_requested(player: int)
## Sender: hud. `player` asked to put the card `card_id` into slot `slot` of their staff number `staff` (its number in the inventory, on a hand or in the bag: `owned_staff_changed`; items I3); `&""` empties the slot. Counted: the card comes out of the card bag, the one it replaces goes back. `body` is the key of the body the menu showed (`Actor.key`, from `inventory_announced`; items I8): a request for a body the seat no longer shows is refused, so a late one never changes another body's staff of that number. Heard by player, which applies it (staffs, docs/milestones/M2-staffs.md).
signal staff_change_requested(player: int, staff: int, slot: int, card_id: StringName, body: int)
## Sender: hud. `player` asked to set every slot of their staff number `staff` (as `staff_change_requested`'s) at once: `cards` holds the card ids by slot (`&""` for an empty slot), as many as the staff has slots or fewer (the rest are emptied). The radial builder sends it for a push-right insert, a take-out that closes the gap, an undo and a clear, so each is one change. `body` as `staff_change_requested`'s. Heard by player.
signal staff_cards_requested(player: int, staff: int, cards: Array[StringName], body: int)
## Sender: hud. `player` asked, in the inventory (items I7), to put their staff number `staff` (as `staff_change_requested`'s) on hand `hand` (0-3: RB, RT, LB, LT): from the bag, the staff on that hand goes into the bag; from another hand, the two change places. `hand` -1 takes it off into the staff bag. `body` as `staff_change_requested`'s. A command: heard by player at the next tick's start, which applies it or says `inventory_refused`.
signal staff_hand_requested(player: int, staff: int, hand: int, body: int)
## Sender: hud. `player` asked, in the inventory (items I7), to drop one thing on the ground: their staff number `staff` (as `staff_change_requested`'s; `bag` and `id` are then the staff bag's and its id), or with `staff` -1 one copy of `id` from the bag `bag` (one of `ItemKinds.BAGS`). A command: heard by player at the next tick's start; the inventory lets it go (`item_drop_requested`, which the Items area lays beside the body) or player says `inventory_refused`. `body` as `staff_change_requested`'s.
signal bag_drop_requested(player: int, bag: StringName, id: StringName, staff: int, body: int)
## Sender: hud (the inventory, the owner's of 2026-11-19). A command: `player` drinks (uses) one `id`
## of `bag` (a potion), from the body its menu showed (`body`, `Actor.key`). Heard by player, which
## takes one and does what it does (`PotionBase`: through Combat, `health_gift_requested`), or
## refuses it (`inventory_refused`).
signal bag_use_requested(player: int, bag: StringName, id: StringName, body: int)
## Sender: hud (the reward menu, connected biomes CB10). `player` picked choice number `choice` of
## their reward offer number `offer` (`reward_rolled`'s; naming the offer, so a pick sent as another
## offer arrives never takes that one's). A command: heard by rewards at the next tick's start,
## which gives it (`reward_taken`) or keeps the offer unspent (no room in the bag, an offer gone).
signal reward_pick_requested(player: int, offer: int, choice: int)
## Sender: hud (the reward menu's X; the owner, 2026-11-19). `player` asked to spend a reward reroll
## (`RerollBase.REWARD`) on their reward offer number `offer`: every choice rolled again. A command:
## heard by rewards at the next tick's start, which rerolls it (`reward_rerolled`) or refuses it
## (`reward_reroll_refused`: none held).
signal reward_reroll_requested(player: int, offer: int)
## Sender: hud (A on the open Y map; the owner, 2026-11-19). `player` asked to teleport its own wizard
## to the biome's room `room`, picked on the map from the rooms it was told it may go to
## (`teleport_rooms_shown`). A command: heard by flow at the next tick's start, which teleports the
## wizard there alone (`wizard_teleported`) when it still may (the room cleared, the wizard standing
## and in no fight); else nothing happens.
signal map_teleport_requested(player: int, room: int)
## Sender: hud (the open Y map's pick, the owner's of 2026-11-19). The room seat `player` has picked
## on its open map to teleport to (`room`; -1: none, the map shut). For the view only. Heard by feel
## (the pick drawn on that player's map).
signal map_pick_changed(player: int, room: int)
## A player voted for door number `door`. Heard by flow.
signal door_vote_requested(player: int, door: int)
## Sender: hud. The "Effect slots" slider in the pause menu (Settings) moved: how many effects
## (the glowing flares of casts, impacts, rings and dashes) may show at once. Heard by feel.
signal effect_slots_changed(slots: int)
## Sender: hud. The "Screen shake" switch in the pause menu (Settings) flipped, or the saved choice was loaded when the menu was bound. Heard by feel, which sets `shake_enabled`.
signal screen_shake_changed(enabled: bool)
## Sender: hud. The "Split screen" setting in the pause menu (Settings, Interface) changed, or the saved choice was loaded when the menu was bound: how this machine's screen splits once its players part (`SplitScreenSetting` in core/settings: DYNAMIC, the Voronoi split, or EQUAL, equal panes). Heard by feel, which lays its split views out that way. The view's only: it changes nothing in the game.
signal split_screen_changed(mode: int)
## Sender: feel. Where each seat's HUD sits on this machine's screen changed (the equal split's panes, the owner, 2026-11-20): by seat, a spot `quarter * 2 + inner` (quarter 0 top left, 1 top right, 2 bottom left, 3 bottom right; inner 1: the quarter's side toward the screen's middle line, 0: the screen's edge). Unsplit, each seat's is its own corner's (`seat * 2`). Heard by hud, which moves the seat's corner panel, builder, inventory and reward menu there by whole pixels. The view's only: nothing in the game hears it.
signal hud_corners_changed(corners: PackedInt32Array)
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
## Sender: hud. The "Dynamic lighting" switch in the pause menu (Settings, Graphics; "Spell light" before the atmosphere's settings, the name kept here and in the save) flipped, or a saved choice was loaded when the menu was bound: whether shots and the room's lights light the world round them (`SpellLightSetting` in core/settings). Heard by feel, which makes or frees its light buffer (and with it the shadows and the mist).
signal spell_light_changed(on: bool)
## Sender: hud. The "Shadows" switch in the pause menu (Settings, Graphics) flipped, or a saved choice was loaded when the menu was bound: whether walls and pillars block the light and bodies cast shadows (`ShadowsSetting` in core/settings; atmosphere C; only while the light is on). Heard by feel, which makes or frees its shadow batch and hands the light its blockers or none.
signal shadows_changed(on: bool)
## Sender: hud. The "Ambient particles" switch in the pause menu (Settings, Graphics) flipped, or a saved choice was loaded when the menu was bound: whether a room's air gives off its dust (`AmbientParticles` in core/settings; atmosphere B; only while the light is on). Heard by feel.
signal ambient_particles_changed(on: bool)
## Sender: hud. The "Fog" switch in the pause menu (Settings, Graphics) flipped, or a saved choice was loaded when the menu was bound: whether a room's floor mist is drawn (`FogSetting` in core/settings; atmosphere F; only while the light is on). Heard by feel, which makes or frees its mist.
signal fog_changed(on: bool)
## Sender: hud. The "Environment interaction" switch in the pause menu (Settings, Graphics) flipped, or a saved choice was loaded when the menu was bound: whether the room's lights, cover, dust and mist take notice of the shots and blasts (`EnvironmentInteraction` in core/settings; atmosphere E). Heard by feel, which turns its stirs on or off (off: what was stirred eases back to rest).
signal environment_interaction_changed(on: bool)
## Sender: hud. The "Ambience volume" slider in the pause menu (Settings, Audio) moved, or a saved choice was loaded when the menu was bound: how loud the room's sound is, in percent (`AmbienceVolume`, `AudioVolumes` in core/settings; atmosphere D). Heard by core/audio, which eases its `Ambience` bus to it.
signal ambience_volume_changed(percent: int)
## Sender: hud. The "Music volume" slider in the pause menu (Settings, Audio; sound plan AU8) moved, or a saved choice was loaded when the menu was bound, in percent (`AudioVolumes` in core/settings). Heard by core/audio, which eases its `Music` bus to it.
signal music_volume_changed(percent: int)
## Sender: hud. The "Sound volume" slider in the pause menu (Settings, Audio) moved, or a saved choice was loaded when the menu was bound, in percent (`AudioVolumes`). Heard by core/audio, which eases its `SFX` bus to it.
signal sound_volume_changed(percent: int)
## Sender: hud. The "UI volume" slider in the pause menu (Settings, Audio) moved, or a saved choice was loaded when the menu was bound, in percent (`AudioVolumes`). Heard by core/audio, which eases its `UI` bus to it.
signal ui_volume_changed(percent: int)
## Sender: hud (sound plan AU8; the ids are `UiSounds`', hud/widgets/ui_sounds.gd). A menu wants its sound `id` heard (a move, a choice, back, a refusal, a card placed or removed): the HUD never plays a sound itself. Heard by core/audio, which plays it on its UI voices, at most once an id a frame.
signal ui_sound_requested(id: StringName)
## Sender: hud. The "Tailless motes" dev slider in the pause menu (Settings) moved, or a saved choice was loaded when the menu was bound: the spark pool the shots' births share while the tails are off (`TaillessMotes` in core/settings; S5 step 4). Heard by core/projectiles (`tailless_particle_cap`) and feel (`Motes.frame_rows`, `TaillessMotes.frame_rows_of`).
signal tailless_motes_changed(pool: int)
## Sender: hud. The main menu's Play was pressed: everyone goes to the hub, the island where players
## join and start a run from the teleporter stone (docs/milestones/online-lobby.md, L1). Heard by
## flow, which starts it, and core/input, which joins the keyboard first. A run's start, as
## `play_requested` is (`Replay.STARTS`), not a command.
signal hub_requested(player: int)
## Sender: hud. `player` picked "Main menu" in the pause menu: this machine leaves what it plays and
## shows the main menu again (online lobby, docs/milestones/online-lobby.md: a machine whose host
## left joins another room from there). This machine's own, never a command: a recorded command
## would take every machine of an online party out. Heard by flow (the run stops, its world goes),
## core/sim (the frames service: what it records or plays ends), net (whatever it holds online
## is let go: the other machines see this one leave) and hud (the main menu is shown). None of
## them asks another.
signal main_menu_requested(player: int)
## Sender: hud. `player` picked "Leave game" in the pause menu (items I2: it replaced the `leave`
## action): that seat lets its device go (a seat waiting for its unplugged gamepad too). Not a command itself: heard by
## core/input, whose `device_left` puts the seat's LEAVE in its next frame, so the seat goes at
## that tick on every machine and in a replay.
signal seat_leave_requested(player: int)
## Sender: hud. `player` pressed A (`accept`) with no menu open while the hub's teleporter stone was
## lit (`start_stone_changed`): start the run (online-lobby L1). A command: heard by flow at the next
## tick's start, which starts the run if the stone is still lit then.
signal run_requested(player: int)
## Sender: hud. `player` pressed A (`take`: F or Enter on the keyboard, never Space, which casts) with no menu open while the item
## `item` lay in reach of the body they drive (`item_near_changed`; the lit stone comes first, the
## altar after): take it (items I6). A command: heard by items at the next tick's start, which takes
## it if it still lies in reach and its bag has room; no room says `item_refused`, an item gone
## meanwhile (taken by a seat before it in that tick) or out of reach by then says nothing.
signal item_take_requested(player: int, item: int)
## Sender: hud. `player` pressed A (`take`, as `item_take_requested`) with no menu open while shop
## item `item` lay in reach of their own wizard (`shelf_near_changed`; a ground item in reach comes
## first, the altar and a waiting reward after): buy it (connected biomes CB11, the owner's answer of
## 2026-11-19). A command: heard by rewards at the next tick's start, which sells it to the first seat
## (seat order) that still stands at it, can pay and has room; a refused buy says `shelf_refused`, an
## item gone meanwhile or out of reach by then says nothing.
signal shelf_buy_requested(player: int, item: int)
## Sender: hud. `player` pressed A on page `page` of the boss's intro, written out on their screen
## (docs/milestones/boss-intro.md, rule 2): the next page for everyone, or past the last the fight.
## Any seat on any machine moves it on (decision 1). A command: heard by flow at the next tick's
## start, whose intro (`BossIntroHold`) turns the page only while `page` is still the page, so two
## seats pressing on one tick turn one page.
signal boss_intro_next_requested(player: int, page: int)
## Sender: hud (the cheat code, `hud/widgets/cheat_code.gd`; owner, 2026-11-19). `player` typed the
## cheat code on the keyboard or pressed it on their gamepad: that seat's wizard in the hub, and no other, gets every card. A command: heard by flow at
## the next tick's start, which fills their card bags only while the hub runs.
signal all_cards_requested(player: int)
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
## Sender: net. Where Host or Join stands: `phase` is `&"off"` (nothing asked, or given up), `&"making"` (this machine's code is being made), `&"code"` (`code` is this machine's code, for the other player), `&"linking"` (both codes given, the machines look for each other), `&"linked"` (they found each other; the run starts in a moment), `&"playing"` (the run plays), `&"ended"` (the other machine left a run that played) or `&"failed"`. `reason` says why, as one of `OnlineWhy`'s names (`core/events/online_why.gd`; `&""`: nothing to say), with its few `facts` (numbers, yes or no, names, a room's code): why it failed, why a code was refused, who left. Never a sentence: net names it and the HUD alone words it (online-lobby L5b), so another way to link machines says the same names. Heard by hud (the main menu, the online line).
signal online_changed(phase: StringName, code: String, reason: StringName, facts: Dictionary)
## Sender: net. The line about the run played online, about once a second while it plays: `facts` say what stands (`OnlineWhy`'s `LINE_` keys: an open room's code and the machines in it, catching up, the machines' games parted), worded by the HUD; `counters` is the run's counters in a developer's shorthand, shown as it is. Both empty clears the line. Heard by hud, and by feel (the open room's code, drawn over the hub's altar).
signal online_line_changed(facts: Dictionary, counters: String)

# --- Devices (sender: core/input) -------------------------------------------

## Sender: core/input. `device` (ids in input_manager.gd) took the free slot `player`, by a button press or as a bot's virtual device.
signal device_joined(player: int, device: int)
## Sender: core/input. `device` left slot `player` (the pause menu's "Leave game"; an unplugged gamepad keeps its slot, `pad_wait_requested`). The slot is free again.
signal device_left(player: int, device: int)
## Sender: core/input. Seat `player`'s gamepad was unplugged (`on` 1) or the seat has one again
## (`on` 0): the seat keeps its wizard, and the game stops for everyone while it waits (owner,
## 2026-11-13). A command: heard by coop at the next tick's start (`Sim.stop`, a reason a seat), so
## it stops at one tick on every machine and in a replay.
signal pad_wait_requested(player: int, on: int)
## Sender: coop. The seats the game stands stopped for because their gamepad is unplugged, a bit
## each (0: none), sent whenever a seat starts or stops waiting. Heard
## by hud (the line that says whose controller is gone; the pause menu).
signal pad_wait_changed(seats: int)

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
## `tag` is the value given to `Projectiles.spawn()`, for looking up the damage. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage, or a merged hit whose shot's slot was taken back at the cap before it was sent): read the shot from it while the event is sent.
## Every hit, of every sender (shots, rays, sweeps, blasts), is this one event. A shot's hits are merged (the one hit model, the owner, 2026-11-17; hit batch A3b): a step's hits of one caster's spell on one body go out after the projectile manager's hit pass as one `projectile_hit`, its `impact_count` the hits it stands for (a shot with a hit profile of its own alone); a ray's, a sweep's or a strike's are sent as they land. A listener that wants to share work across a frame's hits keeps what each asks for and does it once in its own step.
signal projectile_hit(caster: int, target: Node, position: Vector2, tag: int, shot: int)
## Sender: core/projectiles. Where and which way a projectile struck, for looks only (sparks, dust). `target` is the node it hit, sent just before `projectile_hit` for the same hit, or `null` when it ended on a wall or pillar. `caster` is the actor who fired it (NO_PLAYER for a shot of no actor), `position` the point it stopped at and `direction` the unit vector it was flying.
signal projectile_impact(caster: int, target: Node, position: Vector2, direction: Vector2)
## Sender: core/projectiles, while its hit pass merges a step's shot hits (hit batch A2). A shot
## hit `target`, and the pass has not asked of it since its last event: Combat fills `room` at once
## (`HitRoom`: whether hits take its health, how much it has, its hex, its barrier's charges and the
## spell it spares), so the manager stops spending shots on a body its pass has already killed.
## Heard by combat; heard by nobody, `room` stays unknown (every shot hits as it comes). An ask with
## its answer: its handlers only read (the manager keeps the answer until its next event).
signal hit_room_asked(target: Node, room: HitRoom)
## Sender: core/projectiles, with `hit_room_asked` (hit batch A2). A shot tagged `tag` (slot `shot`)
## hit a body, and the pass has not asked of its spell since its last event (a shot that hits alone
## asks for itself): Combat fills `answer` at once (`HitDamage`: one hit's damage before the body's
## hex). Heard by combat; heard by nobody, it stays 0. An ask with its answer: its handlers only read.
signal hit_damage_asked(tag: int, shot: int, answer: HitDamage)
## Sender: core/projectiles. A projectile fired by the actor `caster` ended without a hit: its life ran out or it struck a wall. `tag` is the value given to `Projectiles.spawn()`. Heard by core/spells (on expire) and feel (a small pop where a life ran out). `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal projectile_expired(caster: int, position: Vector2, tag: int, shot: int)
## Sender: core/spells. A carrier of the actor `caster` just showed itself, for looks only (they have no shot to draw). `carrier_card` names the carrier card whose looks show (Feel plays its `shown_cue` here): `&"beam"` (`length` is how far it got, along `direction`) or `&"dash"` (the wizard dashes from `origin` along `direction` for `length` pixels, as far as the walls let it) or `&"slam"` (its strike at `origin`, `length` its ring) or a teleport's card (it leaves `origin` along `direction` for `length` pixels), a swap's (one end of its trade, at `origin`, the other `length` pixels along `direction`; sent for each end), a decoy's or a familiar's (it appears at `origin`); or a modifier that shows itself, named by its card in the same place: a zap (`Spells.ZAP_CARD`, the Zap modifier's id; `length` its arc), or a siphon's mana coming back (`Spells.SIPHON_CARD`: from a hit at `origin` along `direction` to its caster's staff tip, `length` pixels away). `tint` is the colour of the spell's element (white for plain arcane) and `look` its packed look kinds (`CompiledSpell.look`), so the cue shows its cards.
signal carrier_shown(caster: int, carrier_card: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int)
## Sender: core/spells. A carrier of the actor `caster` with no shot to end it ended at `at`, for looks only: a teleport or dash where its body landed (the carrier's end point), a slam where it struck. `carrier_card` names its carrier card (Feel plays the card's `end_cue` there), `direction` the way it went, `size` how big in pixels (a slam's ring, its card's radius), `tint` and `look` as `carrier_shown`'s.
signal carrier_ended(caster: int, carrier_card: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int)
## Sender: core/spells (a `blast` going off: the cue its card names, `ModifierBase.cue`), and anything else with a moment to show (an exploding barrel: `&"fireball"`; a prop's look, the cue of the state it enters, props W7; S6 item 13: flow `room_start` and `stone_lit` (the hub's stone lighting, as no actor), player `revive`, combat `shield_block` and `pull`). Play the cue `cue` (a `CueBase`, `content/cues/<cue>.tres`; an unknown one shows nothing) at `at`, for looks and feel only (the hits are sent apart: each body a blast catches is a `projectile_hit` of its carrier). `caster` is the actor it is of (NO_PLAYER for none), `direction` the way it faces (zero for none), `size` how big in pixels (an explosion's radius, a ground strike's reach; what a part's `reach` is times), `tint` its element's colour (white for plain) and `look` its packed look kinds (`CompiledSpell.look`; 0 for none). Heard by gameplay/feel (`Feel.play_cue`).
signal cue_shown(caster: int, cue: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int)
## Sender: player. A build change asked for by `player` was refused; `reason` says why in plain words.
signal build_refused(player: int, reason: String)
## Sender: player. A request of `player`'s inventory menu (`staff_hand_requested`, `bag_drop_requested`; items I7) was refused; `reason` says why in plain words. Heard by hud (the inventory's note).
signal inventory_refused(player: int, reason: String)
## Sender: player. Everything the body `player`'s HUD shows holds is said anew right after (every bag, every staff it owns, its hands; items I7): what was said of an earlier body of that seat (a possession began or ended, items I8; a run ended, the hub begun again) is gone, so a staff only it owned is forgotten. `body` is that body's key (`Actor.key`), which the menus send back with their requests. Sent each time the body the seat's HUD shows changes. Heard by hud (the builder, the inventory, the panels).
signal inventory_announced(player: int, body: int)
## Sender: player. What the bag `bag` (one of `ItemKinds.BAGS`) of `player`'s own wizard holds now (items I3): the ids of its stacks in the order they came, with the copies of each (`counts`, as long as `ids`; a card with none left is not there), and its `capacity` in copies (-1: no limit). Sent for every bag when the wizard appears and for a bag whenever it changes. Heard by hud (the builder reads the card bag).
signal bag_changed(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, capacity: int)
## Sender: player. The staff number `staff` of `player`'s own wizard (its number in the inventory, stable while it owns it; on a hand or in the bag) was built or changed: `plan` as `staff_changed`'s, empty when the staff is no longer owned (items I3). Sent for every staff when the wizard appears. Heard by hud (the builder: every staff it builds).
signal owned_staff_changed(player: int, staff: int, plan: Dictionary)
## Sender: player. Which staff is on which hand of `player`'s own wizard: by button (0 RB, 1 RT, 2 LB, 3 LT) the number of the staff on it, -1 for an empty hand (items I3). Sent when the wizard appears and whenever it changes. Heard by hud (the builder's strip of staffs).
signal hands_changed(player: int, hands: PackedInt32Array)
## Sender: player. The staff on hand `staff` (0-3: RB, RT, LB, LT) of `player`'s own wizard was built or changed (never another actor's the seat drives). `plan` holds plain values for the builder (the cards, the casts of its cycle, wasted cards with their reasons, the numbers), as `Spells.staff_view` gives them; empty for an empty hand. Heard by hud (the corner panel).
signal staff_changed(player: int, staff: int, plan: Dictionary)
## Sender: player. `player` cast their staff `staff` from `origin` along `direction`. Heard by nobody now: Feel sounds every actor's cast on `cast_left` instead.
signal staff_cast(player: int, staff: int, origin: Vector2, direction: Vector2)
## Sender: core/spells. A card of the actor `caster` moves it: `mode` is `&"dash"`, `&"teleport"`, `&"pull"`, `&"swap"` or `&"recoil"`; `move` is the way and the distance (the body stops at walls), over `seconds` (0 is at once); `tag` is the card's tag. Heard by player (a wizard's actor) and ai (an enemy's), each for its own actor id, which answer each with `caster_move_finished`. Every move adds up (rules R4 F1): several requests in one step (a scatter, a burst, `mirror`) or while one runs all move the body, each over its own time.
signal caster_move_requested(caster: int, mode: StringName, move: Vector2, seconds: float, tag: int)
## Sender: player (a wizard's move) and ai (an enemy's; staffs F8c). A move the actor `caster` was asked for by `caster_move_requested` ended at `position` (every move is answered once). `walled` is true when a wall ended it there: a dash stopped head on, or one whose carried body was pinned (Plow; boss plan OB10-OB12), so its card's `on wall` fires. Heard by core/spells (the end point of a dash, teleport or pull).
signal caster_move_finished(caster: int, mode: StringName, position: Vector2, tag: int, walled: bool)
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
## Sender: core/spells. A press of the actor `caster`'s staff `staff` found no cast left in its cycle that its mana pays: each was skipped, the cycle ended there and its cooldown runs (docs/milestones/cast-timing.md, T3). Heard by a prop's state triggers (props W9c: a trigger's cast refused `dry`).
signal cast_fizzled(caster: int, staff: int)
## Sender: core/spells. A cast of the actor `caster`'s staff `staff` started winding up (docs/milestones/cast-timing.md): its first carrier is the carrier card `carrier_card`, from `origin` along `direction` (the aim follows the caster until it leaves), for `seconds` (a chill or a freeze stretches it; `Spells.is_winding` says when it is over), in its element's `tint` with its packed `look`, under `tag`. `cue` is the staff's own wind-up look (`StaffBase.wind_cue`: a barrel's fuse), `&""` for the card's. Heard by gameplay/feel, which plays `cue`, else the card's `wind_cue` (an enemy's telegraph: only for a caster not on the players' team).
signal cast_winding(caster: int, staff: int, carrier_card: StringName, origin: Vector2, direction: Vector2, seconds: float, tint: Color, look: int, tag: int, cue: StringName)
## Sender: ai (boss plan OB14, decision 26). The AI driving the actor `caster` stopped following its target with the cast of staff `staff` it winds up (its profile's `aim_lock`): the cast leaves along the aim it has now. Only for a caster that warns (not on the players' team). Heard by gameplay/feel, which gives the cast's lane a beat (a flash).
signal aim_locked(caster: int, staff: int)
## Sender: core/spells. A cast of the actor `caster`'s staff `staff` leaves now: at once for a cast that does not wind up, else as its wind-up ends; sent just before its shots start, so what the caster becomes as its cast leaves is what they meet (props W6: a barrel's fuse burns out, it is rubble, its blast goes off); a cast that then finds no room for any shot (every one inside a wall) was told all the same. While it is sent, `Spells.leaving_cast()` is the cast. Heard by the actor kit (a prop's `PropStateTriggers`, for its `cast` triggers) and Feel (the staff's own `cast_cue`, else the cast's carrier sounds and infusion hints, `gameplay/feel/cast_sounds.gd`).
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
## Sender: core/spells, and the cover area (ground cover GC5, rule 4: the status of the cover a body
## stands in, burning grass's burn, by NO_PLAYER). Something that hits nothing gives `target` a status
## (a portal's infusion on the bodies that go through it; burning grass on whoever stands in it):
## Combat applies it as `apply_status` does, with no hit, by its own rules (resist and all).
signal status_requested(caster: int, target: Node, status_id: StringName, duration: float, strength: float)
## Sender: flow. The enemy or boss body `enemy` (an `Actor` with its data, not yet in the tree) is
## about to stand in the room (run generation RG5). Heard by difficulty, which scales its numbers to
## the room's (`Actor.stat_scale`) before its data is applied.
signal enemy_standing(enemy: Node)
## Sender: actor (a body's `Phases`, boss plan OB13). The body `actor` calls the adds `adds` (an
## `EnemyAdds` of its phase in play): the phase's burst as it starts, or one of its waves (`wave`).
## `key` says which of its entries they are (`Phases.adds_key`), for the count of those alive under
## the entry's cap. Heard by flow, which stands them (none for a body it did not stand).
signal adds_requested(actor: int, adds: EnemyAdds, key: int, wave: bool)
## Sender: flow (boss plan OB13). The body `actor` dies with no hit and nobody's kill: an add whose
## caller died crumbles. Heard by combat, which takes its health and tells its death as any other
## (`enemy_died` with NO_PLAYER for a foe of the wizards).
signal crumble_requested(actor: int)
## Sender: rewards (connected biomes CB11: a fountain's draw) and player (a potion drunk from the
## inventory, `bag_use_requested`; the owner, 2026-11-19). The actor `actor`
## gains `more_most` most health (and as much health, unless it is down) and is then healed `heal`.
## Heard by combat, which keeps an actor's health: it changes the body's Health and tells a heal as
## any other (`heal_dealt`, by nobody).
signal health_gift_requested(actor: int, heal: float, more_most: float)
## Sender: actor (a boss body's `BossPresence` look, boss plan OB16). The boss `actor` entered play:
## `boss_name` its name for people (`EnemyBase.shown_name`: its `display_name`, else its id in words), `lore` its one line, `marks`
## each phase's health share (`EnemyPhase.health_below`, largest first; none for a phase by time).
## `has_intro` whether its data has an intro (`EnemyBase.boss_intro`, docs/milestones/boss-intro.md):
## then the bar waits for `boss_intro_closed`, and no banner shows.
## Sent once each time its body enters the tree; `boss_health_changed` follows at once. View only:
## heard by the HUD (the boss bar and the entrance banner) and feel (the `boss_intro` cue).
signal boss_shown(actor: int, boss_name: String, lore: String, marks: PackedFloat32Array, has_intro: bool)
## Sender: flow (`BossIntroHold`, docs/milestones/boss-intro.md, rule 2). The boss `actor`'s intro is
## open: the game stands stopped on the room's tick until its last page is turned. `boss_name` and
## `lore` as `boss_shown`'s, `intro` its data, `page` the page it is on. `fresh` true as it opens (the
## HUD plays the timeline from the start), false when a snapshot restored it open (the HUD shows that
## page already revealed). View only; heard by the HUD and feel.
signal boss_intro_opened(actor: int, boss_name: String, lore: String, intro: BossIntro, page: int, fresh: bool)
## Sender: flow (`BossIntroHold`). The open intro turned to page `page` (a seat's A,
## `boss_intro_next_requested`). View only; heard by the HUD.
signal boss_intro_paged(page: int)
## Sender: flow (`BossIntroHold`). The boss `actor`'s intro closed: its last page was turned (the game
## goes on from this tick), its boss left, the last seat left or the run ended; `actor` NO_PLAYER after a
## snapshot restored with none open (whatever the HUD shows closes). View only; heard by the HUD (the
## overlay goes, the boss bar comes) and feel.
signal boss_intro_closed(actor: int)
## Sender: actor (`BossPresence`, boss plan OB16). The shown boss `actor` has `health` of
## `max_health` now (a hit, a heal, a player joining or leaving, a snapshot put back). View only;
## heard by the HUD.
signal boss_health_changed(actor: int, health: float, max_health: float)
## Sender: actor (`BossPresence`, boss plan OB16). The shown boss `actor` is out of play: it died
## (its `died`, beside combat's `enemy_died`) or its body left the tree (the room or the run ended).
## Once for each `boss_shown`. View only; heard by the HUD.
signal boss_hidden(actor: int)
## Sender: combat. `enemy` died; the actor `killer` landed the last hit (or NO_PLAYER). `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent.
signal enemy_died(killer: int, enemy: Node, position: Vector2, shot: int)
## Sender: actor (hub rework HR-H2, docs/milestones/hub-rework.md, "Holes" 4). The actor `actor` (its
## id) ended a move over a hole and falls now, for `HoleRules.FALL_SECONDS` (`Actor.fall_left`); while
## it falls it is down to everything that asks. Heard by nobody in the game yet (Feel draws a fall from
## the body's state, `FallLook`, so a machine that joins mid-fall draws it); tests hear it.
signal body_fell(actor: int)
## Sender: actor (HR-H2). The wizard `actor` (its id) came back from a fall at `at` (its last ground),
## having paid its fall's cost (Combat). Anything else that falls dies instead (`enemy_died` for a
## foe). Heard by nobody in the game yet; tests hear it.
signal body_returned(actor: int, at: Vector2)

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
## Sender: core/spells (Plow, boss plan OB11). The body `target`, which a carrier of the actor `caster`'s card `tag` carried, is no longer carried: `pinned` against a wall (it takes the pin its hit armed, and `carrier`, the actor id of the body that carried it, or -1 for a shot, ends its dash there), or let go with a shove along `way` (zero: none, it slipped off or was dropped). One per carry. Heard by combat (the pin and the shove) and actor (the carrier's Mover, for its own id).
signal carry_ended(caster: int, target: Node, carrier: int, way: Vector2, pinned: bool, tag: int)
## Sender: actor. A controller now possesses the actor `actor` (it drives it, or a puppet copies it); `caster` is that controller's home body (the body that cast `possess` when it has none). Heard by feel (a ring in the caster's ramp and the sound `possess`).
signal possess_started(caster: int, actor: int)
## Sender: actor. The possession of the actor `actor` by the controller whose home body is `caster` ended (time up, the actor down or dead, a newer possession); the actor has its own controller back. Heard by feel (a ring going out).
signal possess_ended(caster: int, actor: int)
## Sender: combat. Just before `damage_dealt`: the hit of the actor `caster` on `target` for `amount` is of `kind` (`&"shot"`, `&"ray"`, `&"swing"`, `&"burst"`, `&"reaction"`, `&"status"`, and `&"heal"` for a heal). A wizard's contact hit counts as `&"shot"`. A wizard hit by their own spell has `caster` equal to their own actor id. Heard by feel. `shot` is the projectile manager's row of the shot it is about (`Projectiles` slot), -1 for none (a ray, a strike, contact damage): read the shot from it while the event is sent. `card` is the carrier card whose hit it is (`HitProfile.card`, so Feel sounds a carrier's own `hit_sound`), `&""` for a hit of none (contact, a fall, a reaction, a status, a heal, a blast's strike, a zap's arc).
signal hit_landed(caster: int, target: Node, amount: float, position: Vector2, kind: StringName, shot: int, card: StringName)
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
## Sender: flow. A run of the run definition `run_id` (content/runs) begins, on the run's fresh
## state (its seed dealt; run generation RG3), for `players` players (the seats joined at its start,
## the same on every machine and in every replay; RG5). Heard by run, which makes the run's biome map
## (connected biomes CB8) and answers with `run_room_filled` for every room, then `run_biome_chosen`.
signal run_begun(run_id: StringName, players: int)
## Sender: run, in answer to `run_begun` (connected biomes CB8). Room `room` of the run's biome map
## (by number, 0 the start room) holds the fight `enemies` (enemy and boss ids, one per body; none: no
## fight), `scale` times harder than the run's first room with one player (run generation RG5: its
## depth and the run's players, the run definition's `scaling`), its enemies coming in groups of
## `group` cost (0: the whole list at once), the next when the cost still standing or spawning in the
## room drops to `refill_at` or below, the bodies of a group `stagger` seconds apart (enemy spawning
## EA4: plain costs, the run works them out from its biome's `SpawnRules` shares at the room's scaled
## budget). `elites` (connected biomes CB11, decision 24), by the same index as `enemies`: the card
## an elite enemy gets in its staff, empty for one that is no elite (an empty list: none is). Sent for
## every room before `run_biome_chosen`. Heard by flow (the room's `RoomFight`).
signal run_room_filled(room: int, enemies: Array[StringName], scale: float, group: int, refill_at: int, stagger: float, elites: Array[StringName])
## Sender: run, in answer to `run_begun`, after every room's `run_room_filled` (connected biomes
## CB8). The run's biome map, `map`: a `BiomeMap` (gameplay/run; typed here as what it extends, since
## core names no area's class), a copy of the run's own. Heard by flow, which keeps a copy as its
## world's state and lays it. None comes when the map could not be made.
signal run_biome_chosen(map: RefCounted)
## Sender: flow. The room a fight of the biome stands in is `scale` times harder than the run's first
## room with one player (`run_room_filled`'s scale), sent before each enemy of the room's fight
## stands (two fights at once each stand at their own). Heard by difficulty, which scales every enemy
## and boss that stands then (`enemy_standing`).
signal run_room_scaled(scale: float)
## Sender: flow. The depth level of the room whose enemy is about to stand (`BiomeMap.level_of`: its
## scale with one player, by its depth only; the owner, 2026-11-19), sent with `run_room_scaled`.
## Heard by difficulty, which keeps it on each enemy (`Actor.room_level`) for its aim (`AimTuning`).
signal run_room_leveled(level: float)
## Sender: run (connected biomes CB10, "Run stats"). The run's own changes of the run stats
## (`RunStats`: its definition's rule changes of the `RUN_STAT` target whose flags the run's
## unlocks hold, in order; empty for none), as a run begins (`run_begun`), before its rooms' fights
## (`run_room_filled`). Every player's stats are these, then their relics'. Heard by rewards.
signal run_stats_ruled(changes: Array[StatChange])
## Sender: flow. The world's room `room` goes, before anything of it goes: what was cast in it ends
## quietly with it. Heard by core/spells (`leave_room`: carriers, holds, waiting launches and moves
## end; builds stay). A biome's party never leaves a room as a whole, so it is sent only as a
## world goes, for ALL_ROOMS (connected biomes CB3); the hub's is FIRST_ROOM.
signal room_left(room: int)
## Sender: flow. The players entered the room `room_id` (its template), the world's room `room`
## (`FIRST_ROOM`, ...): the hub's room, a biome's each room the first time a wizard steps into
## it (its start room as the biome starts). Entering FIRST_ROOM is entering a new world (see
## FIRST_ROOM); never sent by a restore.
signal room_entered(room_id: StringName, room: int)
## Sender: flow (`_lay_out`, ground cover GC2; a biome's pieces as `BiomeWorld` lays them, connected
## biomes CB3: every room and bridge, `room` its number, FIRST_ROOM first). The room `room_id` was
## laid out: `layout_root` is the
## layout the game shows, built and read but not yet in the tree, its placements and zones still in it
## (the cover's fields). Sent whenever a room is laid out: a run's start, each room entered, and a
## snapshot restored into another room (`Flow.rebuild_derived`); a restore into the room shown sends
## nothing. Heard at once, before the placements and zones are taken out: a listener works out what it
## needs from it then (`CoverLayout.of`) and keeps neither the node nor anything in it. It changes no
## state. Heard by the cover area and feel (GC3, GC5). One listener draws onto it: Feel's ground
## (connected biomes CB4, gameplay/feel/ground/ground_layout.gd) puts the ground drawn from the room's
## shape on its `Floor` (textures) and makes its rims' and drips' mote lines again; so no listener reads
## the `Floor`'s art or its mote lines here (they read the walls, holes and places, which it leaves).
## In a biome the layout is placed where the piece stands (its `position`, and its mirroring's meta,
## `PieceShape.GROUND_MIRROR_META`), and one room's cover is played (Cover's, FIRST_ROOM's; CB3).
signal room_built(room_id: StringName, room: int, layout_root: Node)
## Sender: core/spells (ground cover GC5, rule 5). An element of a spell touched the floor: `element`
## (a card id, &"fire") within `radius` of `at`, by the actor `caster` (NO_PLAYER for none). Sent
## where a blast or a pulse's ring goes off, as a pool lies and on each of its ticks
## (`SpellLimits.POOL_TICK`), and where a shot ends (a hit that spends it, its life, a wall); never
## by a shot in flight (decision 1). One event per element of the spell, in its infusions' order.
## Heard by the cover area, which queues it and fires the `element` triggers of the cells inside the
## circle at its next step. Spells knows nothing of cover.
signal floor_touched(caster: int, element: StringName, at: Vector2, radius: float)
## Sender: the cover area (ground cover GC5, rule 6). The cells `cells` of the cover of room `room`
## (the piece's number, as `room_built` gave it: connected biomes CB3b; its `CoverLayout`'s cell
## indices) are now in the states `states` (each an index in its kind's
## `CoverKind.states`; 0 at rest), one event a tick with that tick's changes; after each
## `room_built`, every cell not at rest once (a machine that joins mid-fire draws the fire), and after
## a restore every cell whose state the view was last told otherwise. Read the arrays while it is
## sent; they are reused. Heard by feel (the tufts' look, `cover.gd`).
signal cover_changed(room: int, cells: PackedInt32Array, states: PackedInt32Array)
## Sender: ai (an actor's brain; ground cover GC7, rule 8). The actor `actor` looks at where the floor
## within `reach` of `at` would harm a body standing on it: the cover area fills `sight` at once
## (`CoverSight`: a window of the room's cover cells, each marked where its state gives a status, as
## burning grass does). Heard by the cover area; heard by nobody, or in a room with no cover, `sight`
## stays empty (every cell safe). An ask with its answer, so the AI never calls the cover area.
signal cover_danger_looked(actor: int, at: Vector2, reach: float, sight: CoverSight)
## Sender: core/loading. Work before playing has begun behind the loading screen (`Loading.run`;
## Flow runs `play_tasks` on Play). Heard by hud, which shows the screen until `loading_finished`.
signal loading_started()
## Sender: core/loading. `done` of the load's `total` units are done (the screen's bar). Heard by hud.
signal loading_progressed(done: int, total: int)
## Sender: core/loading. The load is over (done, or cancelled). Heard by hud.
signal loading_finished()
## Sender: flow. The room `room_id` (the world's room `room`) was cleared: every enemy the run stood in it is down (boss OB2a: no waves). In a biome each fight room's own (connected biomes CB3), sent once; the boss's room cleared opens the portal home (CB7).
signal room_cleared(room_id: StringName, room: int)
## Sender: flow (connected biomes CB11). The biome's room `room` was cleared and its kind rewards a
## clear: each player rolls a reward from the table `table` (`RoomKind.rewards`, content/rewards),
## however its foes left it (the owner, 2026-11-19: a possessed foe killed elsewhere too). Sent right
## after `room_cleared`, once a room. `type`: the room's reward type (`RewardType.to_row`: item kind,
## card kind, element; empty names for any), a reward room's decided as its biome was made (the
## owner's ask of 2026-11-19), every other room's any. `spots`: where each seat's reward item lies
## (by seat, world pixels, on clear ground apart from the room's things; the owner's ask of
## 2026-11-19: a reward is an item in the room, opened with A at it). Heard by rewards.
signal room_rewards_due(room: int, table: StringName, type: PackedStringArray, spots: PackedVector2Array)
## Sender: flow (connected biomes CB11, decisions 19 and 20). The biome's room `room` of a special
## fill (`RoomKind.FILL_SHOP`, `FILL_FOUNTAIN`) was entered for the first time: `table` the shop's
## shelf table (`RoomKind.shelf`; empty for a fountain), `area` the fountain's pool in world pixels
## (its template's zone `fountain`, else round the room's middle), `spots` where a shop's items lie
## (its zones `shelf`, in order, else spots round its middle), `board` where a shop's reroll sign
## stands (its zone `shelf_sign`, else under its shelf; the owner's ask of 2026-11-19). Sent once a
## room, never by a restore. Heard by rewards, which stocks the shelf and fills the pool.
signal special_room_opened(room: int, fill: StringName, table: StringName, area: Rect2, spots: PackedVector2Array, board: Vector2)
## Sender: flow (connected biomes CB9). The party's map of the biome: `seen[room]` for each room by
## its number (0 unseen, 1 shown on the map but never entered, 2 entered; `PartyMap`), a copy. Sent as
## a biome starts and whenever a room is seen; empty as the biome goes; `again` after a restore (what
## it says is drawn as it stands, not played in: a machine that joined mid-run learns the map so).
## For the view only. Heard by feel (the dark over the unvisited rooms, the held Y map).
signal rooms_seen(seen: PackedByteArray, again: bool)
## Sender: flow. In the hub (online-lobby L1): `standing` of the `wizards` there stand on the
## teleporter stone (a prop of the role `run_start`, where its area is; `HubRules`); `lit` while all of them do (and at least one is there),
## when any seat's A starts the run (`run_requested`). Sent as the hub starts and whenever it
## changes; (0, 0, false) when the hub is left. Heard by hud (the stone line; A on the lit stone).
## The stone's look is the prop standing on it, which flow puts in its state `lit` or `unlit`
## (props W8, `prop_state_requested`), so feel needs no word of it.
signal start_stone_changed(standing: int, wizards: int, lit: bool)
## Sender: flow. The party is departing (`departing` true): for a run from the hub's stone (A was
## pressed on it while lit, and the run starts Departure.TICKS later), or for the hub at the run's
## end (lost or won; true until the hub stands); or no longer is (the next world stands, or will
## not, or the game left for the main menu). Sent when it changes. Heard by hud (the loading screen
## covers the game while the next world is made); the simulation never reads it back.
signal run_departure_changed(departing: bool)
## Sender: flow. The party entered the hub (`in_hub` true: a run in the hub room began) or left it (a run from the stone, the game stopped). Sent when it changes. Heard by net (a machine may join a party only while it is in the hub); the simulation never reads it back.
signal hub_changed(in_hub: bool)
## Sender: flow. In the hub (online-lobby L2): the seats whose wizards stand on the multiplayer altar (a prop of the role `party_altar`, where its area is), a bit each; 0 when the hub is left. Sent whenever it changes. Heard by hud (A on the altar asks to open the room, `online_open_requested`).
signal altar_changed(seats: int)
## Sender: flow. In the hub: whether a multiplayer altar stands (`standing`), and `at`, the top middle of the first one's area in room pixels (where something drawn over it sits). Sent as it changes; (false, zero) when the hub is left. For the view only. Heard by feel (the room's code drawn over the altar, online-lobby L5c).
signal altar_placed(standing: bool, at: Vector2)
## Sender: flow. In a biome (connected biomes CB7): gather door `door` (the doors of the biome's gated
## rooms, by number, then the portal home after them), its `rule` (`RoomKind.DOOR_GATHER`,
## `DOOR_GATE`, or `portal` for the portal home), its `area` in world pixels (a door's mouth, the
## portal's floor), how many standing wizards are `gathered` at it of the `standing` there are,
## `held` while a gate stays shut for a sealed fight that holds a wizard, and `open` once it opened.
## Sent as it changes; door -1 (the rest empty): every door forgotten (the biome left; a restore, with
## `open` true: what is told next is drawn as it stands, not played in).
## For the view only. Heard by feel (the door's bars, its lamps, the portal).
signal gather_door_shown(door: int, rule: StringName, area: Rect2, gathered: int, standing: int, held: bool, open: bool)
## Sender: flow (connected biomes CB11; CB12 made its look). In a biome: key door
## `door` (by number), its `area` in world pixels (its mouth), `open` once a key opened it. Sent as
## it changes; door -1 (the rest empty): every key door forgotten (the biome left; a restore, with
## `open` true: what is told next is drawn as it stands, not played in). For the view only. Heard by
## feel (its padlock turning and falling, its bars sinking: `lock_looks.gd`).
signal key_door_shown(door: int, area: Rect2, open: bool)
## Sender: flow (connected biomes CB11; CB12 made its look). In a biome: secret rock
## `rock` (by number), its `area` in world pixels (the cracked rock), the `element` that breaks it (a
## card id, &"fire"; its crack's tint), `broken` once it broke. Sent as it changes; rock -1 (the rest
## empty): every secret rock forgotten (as `key_door_shown`'s -1). For the view only. Heard by feel
## (its crack's tint, brightening as its element touches near it, and its breaking in stages).
signal secret_rock_shown(rock: int, area: Rect2, element: StringName, broken: bool)
## Sender: flow (connected biomes CB11, decision 21). In a biome: key `key` (by number, one a key
## door) lies on the floor at `at` (`lying`), or does no more (taken into the bag of the body that
## reached it; the biome left). After a snapshot is restored, said again for every key (key -1 first: every key
## forgotten). For the view only. Heard by feel (`special_room_looks.gd`).
signal key_shown(key: int, at: Vector2, lying: bool)
## Sender: flow (the owner, 2026-11-19: keys are each body's own). Seat `player`'s body stands at a
## shut key door, its mouth's middle at `at` (world pixels), with no key in its own bag (`needed`), or
## no more (`needed` false: it left, got a key, or the door opened). Sent as it changes; false for
## every seat as the biome is left and after a snapshot is restored. For the view only. Heard by hud
## (the hint over the door: "Needs a key").
signal key_needed_shown(player: int, at: Vector2, needed: bool)
## Sender: flow (the owner, 2026-11-19). The rooms seat `player`'s own wizard may teleport to from
## the Y map now (`rooms`, the biome's room numbers, every cleared room but the one it stands in; empty
## while it may not: in a fight, sealed in, down, driving another body, or out of a biome) and each
## one's middle (`at`, world pixels, the same order). Sent as it changes; empty for every seat as the
## biome is left and after a snapshot is restored, then told again. For the view only. Heard by hud
## (the map's picker).
signal teleport_rooms_shown(player: int, rooms: PackedInt32Array, at: PackedVector2Array)
## Sender: flow. Seat `player`'s wizard teleported from the Y map (`map_teleport_requested`): it left
## `from` and stands at `to` (world pixels), materializing there (`Actor.spawn`). Heard by feel (the
## stepped vanish where it left).
signal wizard_teleported(player: int, from: Vector2, to: Vector2)
## Sender: flow (the owner, 2026-11-19). Seat `player` joined while the run cannot be joined (`held`:
## a player has left the biome's start room), so it has no wizard until the run ends; or no more
## (it got one, or it left). Sent as it changes; false for every seat as a run ends, and as it
## stands after a snapshot is restored. For the view only. Heard by hud (its corner panel says why).
signal join_held(player: int, held: bool)
## Sender: flow. The room `room_id` a run is in was stood (items I6): the items its scene places
## (`ItemStandIn`'s data, each a `StaffItem` or anything `ItemKinds.stack_of` makes a stack of) and
## where each lies, in the scene's order. Sent for every room as a world is made, at the run's start.
## Heard by items, which lays them on the ground (or, the run taking along what lay on that room's
## ground, `Frames.next_run_ground`, that instead). `room`: the world's room (Events.FIRST_ROOM...);
## only FIRST_ROOM's clears what lay on the ground before (a new world): a biome's later rooms add
## theirs, at their places in the world (connected biomes CB3: what was left on a floor stays).
signal room_items_placed(room_id: StringName, room: int, items: Array[Resource], at: PackedVector2Array)
## Sender: an actor's Inventory (gameplay/actor). Lay `stack` (gone from the inventory already) on
## the ground beside the actor `actor` (items I6: a card given back to a full bag). Heard by items,
## which finds the spot; heard by nobody, the stack is lost.
signal item_drop_requested(actor: int, stack: ItemStack)
## Sender: ai (an actor's brain; items I9). The actor `actor` looks at what lies within `reach` of
## its feet at `feet`: the Items area fills `sight` at once (`GroundSight`: the nearest first, each
## with whether the pickup rule's reach takes it). Heard by items; heard by nobody, `sight` stays
## empty. An ask with its answer, so the AI never calls the Items area.
signal ground_looked(actor: int, feet: Vector2, reach: float, sight: GroundSight)
## Sender: ai (items I9). The actor `actor` takes the item `item` off the ground: heard by items,
## which gives it to the actor's Inventory at once as a seat's `item_take_requested` does (it must
## still lie in reach, and the pickup rule must find room); nothing is said when it cannot. Not a
## command: the simulation asks it of itself, during the tick.
signal actor_take_requested(actor: int, item: int)
## Sender: items. The item `item` (its number on the ground, never handed out again in a run) lies at
## `at` as `view` says, or (an empty `view`) is gone: taken, or the ground cleared at a run's start. `view` is plain
## values for the looks (`Items.view_of`): `kind`, `id`, `name`, `icon` (a Texture2D or null), and
## for a staff `head` (its head sheet), `slots`, `cooldown`, `max_mana`, `mana_regen` and `cards`
## (card ids by slot). Sent as each one is laid and as it goes. Heard by feel (the look on the ground).
signal ground_item_changed(item: int, at: Vector2, view: Dictionary)
## Sender: items. The item in reach of the body `player` drives now is `item`, lying at `at` as
## `view` says (`ground_item_changed`'s), or none (-1, an empty view). Sent when it changes, and
## (-1) when the ground is cleared at a run's start. Heard by hud (the hint and its tooltip; A takes it,
## `item_take_requested`).
signal item_near_changed(player: int, item: int, at: Vector2, view: Dictionary)
## Sender: items. `player` asked for the item `item` and its bag has no room (items I6): nothing was
## taken. Heard by hud (the hint's red shake; it names no bag).
signal item_refused(player: int, item: int)
## Sender: flow. The result of a door vote: `player` voted for `door`.
signal door_voted(player: int, door: int)
## Sender: difficulty. The difficulty setting's level changed to `level` (M3; 1 at normal), which the
## enemies' skill follows (enemy AI AI10). Not the room's scale (`run_room_scaled`) either,
## which changes no aim: an enemy's aim follows the room's depth level (`run_room_leveled`). Not sent yet.
signal difficulty_changed(level: float)

# --- Rewards and progression ------------------------------------------------

## Sender: rewards (connected biomes CB10). Seat `player`'s own roll on a room's clear: the offer
## numbered `offer` (handed out once a run), its `choices` (the views of what each gives:
## `kind` (an item kind, `ItemKinds.RULES`: every reward is an inventory item), `id`, `count`, and the
## item's own `name`, `icon` and `description` (`ItemLooks`); as many as the player's
## `reward_choices`, fewer when the table runs out of different ones), and whether the player's wizard was in the room (`here`: the menu opens at
## once; a player who was not there finds it as an unspent reward, DESIGN rule 4). Heard by hud.
signal reward_rolled(player: int, offer: int, choices: Array[Dictionary], here: bool)
## Sender: rewards. The result of a pick (`reward_pick_requested`): `player` took choice `choice`
## of their offer `offer`, which gave what `reward` says (a view, as `reward_rolled`'s). Heard by
## nobody yet (tests; later Feel's sound).
signal reward_taken(player: int, offer: int, choice: int, reward: Dictionary)
## Sender: rewards. A pick of `player`'s offer `offer` could not be given (no room in its item's bag,
## no wizard): the offer stays unspent. Heard by hud (the reward
## menu opens on it again, saying why).
signal reward_refused(player: int, offer: int)
## Sender: rewards. `player`'s offer `offer` was rerolled (`reward_reroll_requested`): one reward
## reroll spent, its new `choices` (views, as `reward_rolled`'s). Heard by hud (the reward menu turns
## its cards over to the new ones).
signal reward_rerolled(player: int, offer: int, choices: Array[Dictionary])
## Sender: rewards. A reward reroll of `player`'s offer `offer` was refused (no reward reroll held, or
## nothing to roll): nothing spent, the offer as it was. Heard by hud (the menu's title says why).
signal reward_reroll_refused(player: int, offer: int)
## Sender: rewards. Seat `player`'s offers not yet picked, oldest first (`offers`: each a dictionary
## of `offer`, `here` and `choices`, as `reward_rolled` says), whenever they change, at a run's
## start (none) and after a snapshot is restored. Heard by hud (the unspent count on the corner
## panel; the reward menu shows the oldest).
signal rewards_waiting_changed(player: int, offers: Array[Dictionary])
## Sender: rewards (connected biomes CB10, decision 18). The coin numbered `coin` lies at `at`
## (`lying`), or is gone from there (taken, or the world went). After a snapshot is restored, said
## again for every coin (and gone for those no longer lying). Heard by feel (the coins' look).
signal coin_changed(coin: int, at: Vector2, lying: bool)
## Sender: rewards (a coin walked over, a shelf item bought, a reward taken), items (a ground item
## taken) and flow (a key taken; the owner's ask of 2026-11-19). The actor `actor` picked up an item
## of kind `kind` (an `ItemKinds` kind, or `PICKUP_REWARD` for a reward item's offer taken) and id
## `id` at `at` (world pixels). For the view only: heard by feel (each kind's pickup sound, from the
## rooms this machine's wizards are in, CB12's Ears).
signal item_picked_up(actor: int, kind: StringName, id: StringName, at: Vector2)
## Sender: rewards (connected biomes CB11, decision 19). Shop item `item` (numbered once a run) lies on
## its shelf at `at` (`lying`), `choice` what it is (an item, as a reward choice's view: `kind`, `id`,
## `count`, `name`, `icon`, `description`) and `price` its price in coins (the run's own `price_scale`; a buyer's relics may
## change theirs), or is gone (bought, or the world went). After a snapshot is restored, said again
## for every item (and gone for those no longer there). For the view only. Heard by feel.
signal shelf_changed(item: int, at: Vector2, choice: Dictionary, price: int, lying: bool)
## Sender: rewards. The shop item in reach of seat `player`'s own standing wizard now is `item`,
## lying at `at`, `view` what it is (`shelf_changed`'s choice, with its `price` for this player), or
## none (-1, an empty view). Sent when it changes, at a run's start (-1) and after a snapshot is
## restored. Heard by hud (the hint; A buys it, `shelf_buy_requested`). A shop's reroll sign is one
## of its shelf's things, numbered with its items (the owner's ask of 2026-11-19): its view's `kind`
## is `SHELF_SIGN`, its `price` the next reroll's, and A at it rerolls the shelf.
signal shelf_near_changed(player: int, item: int, at: Vector2, view: Dictionary)
## Sender: rewards (the owner's ask of 2026-11-19). Seat `player`'s reward offer `offer` lies as an
## item at `at` (world pixels) in the room whose clear rolled it (`lying`), or lies there no more
## (picked, or the world went: it waits on the player's corner panel then). After a snapshot is
## restored, said again for every one (and gone for those no longer lying). For the view only.
## Heard by feel (the reward item's look).
signal reward_item_changed(player: int, offer: int, at: Vector2, lying: bool)
## Sender: rewards. Seat `player`'s own reward item in reach of the standing body it drives is offer
## `offer`, lying at `at`, or none (-1). Sent when it changes, at a run's start (-1) and after a
## snapshot is restored. Heard by hud (the hint; A opens that offer's reward menu).
signal reward_near_changed(player: int, offer: int, at: Vector2)
## Sender: rewards. `player` asked to buy shop item `item` and could not: too few coins in their own
## coin stack (their wizard's currency bag), or no room for it. Nothing changed. Heard by hud (the hint's red shake).
signal shelf_refused(player: int, item: int)
## Sender: rewards (connected biomes CB11, decision 20). The fountain of room `room`, its pool at
## `area` (world pixels), holds `left` of its `most` healing: as it is filled, as a hurt wizard draws
## on it, and after a snapshot is restored; room -1 (the rest empty): every fountain forgotten (the
## world went; a restore, before each is said again). For the view only. Heard by feel.
signal fountain_changed(room: int, area: Rect2, left: float, most: float)
## Sender: rewards (connected biomes CB11's follow-up). Seat `player`'s run stats now (`stats`: every
## `RunStats` row by name, its value for this player: the base, the run's changes, its relics): at a
## run's start, as the run's changes come (`run_stats_ruled`), as the seat's wizard comes, and after a
## snapshot is restored. For the view only (a player's own map: `secret_sense`). Heard by feel.
signal run_stats_told(player: int, stats: Dictionary)
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

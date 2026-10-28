# M2 rework: actors (one body for wizards and enemies)

**Goal:** a wizard and an enemy are the same kind of thing: an **actor**, a body built from components, driven by one **controller**. A wizard is an actor with a player controller and a seat (its HUD, its builder, being downed and revived); an enemy is an actor with an AI controller and no seat. Everything can hurt everything. Taking control of an enemy is moving a controller node, and a card does it: **possess**.

**Status (2026-10-28):** approved by the owner ("Yes just go ahead"); the owner's decisions are in "Owner decisions". Phase G of M2, after phase F (enemy staffs) and before D3 (the stress run and C2), so C2 is asked on the new bodies. An owner exception like phase F's (docs/ROADMAP.md).

**Why:** phase F gave enemies staffs in ten PRs, most of them spent teaching core that a caster can be something other than "player 0–3". The player index meant four things at once (below), so every system was sized and keyed by it, and enemies were added as a second identity beside it (caster rows 4+, `NO_PLAYER` in events with the real caster hidden in the tag). The code shows it:

- the caster kit (dash, teleport, hook, swap, recoil), mana and aiming are written twice, in `gameplay/player/player.gd` and `gameplay/ai/ai.gd`;
- Combat keeps two body models: enemies by node (`register_enemy`, `apply_status`, `speed_factor`, found with a list scan on every hit) and wizards in four fixed slots (`register_player`, `apply_wizard_status`, `wizard_speed_factor`, ...), with every status and reaction rule written once for each, and some of them already apart by accident (see "Combat: one rule");
- core asks "is this caster below 4?" about 25 times to answer four different questions: which side, which colour, whether a human is there, and which budget pays.

**Done when:**

1. Every part in "Parts" is merged and `ci/build/build.sh --quick --tests` is green.
2. `gameplay/player/player.gd` and `gameplay/ai/ai.gd` are controllers: no body, health, mana, staff or move code left in either.
3. Combat has one body model, indexed by actor id; no `wizard_` API is left.
4. Core has no "player or enemy" test and no sides: damage asks nothing, aiming asks a team, colours a ramp, HUD events a seat, limits a budget.
5. The `possess` card works on every actor, both ways, with tests and combo files.
6. The stress run at the web cap is no slower than before phase G (numbers in `docs/DECISIONS.md`).

## The four things "player" meant

| Question | Today | After |
| --- | --- | --- |
| **Seat:** is a human here, which device and HUD panel? | the player index 0–3 | `seat` (-1 or 0–3), on the controller; only a seat sends HUD events |
| **Side:** whose shots hit me, whom do mine hit? | `caster < 4` → hit layer | **gone.** Every spell hits every actor (self-harm included). A **team** says only whom to *aim* at (below) |
| **Look:** which colour ramp draws my spells? | player index; enemy ramp by flag | `ramp` (0–3 the hat colours, 4 Blight ochre), on the actor |
| **Budget:** whose share of the shared limits do I spend? | 4 seats + 1 shared enemy pool | the seat's budget when a seat drives the actor, else the shared pool |

The identity itself becomes the **actor id**, one number for every actor, used by every system as the row in its arrays. No code may assume that an actor id is a seat (tests open wizards at ids other than 0–3 to make sure of it).

## Everything hurts everything; teams only aim

The owner, 2026-10-28: "Everything should be able to damage everything. So there should be no sides." The Friendly fire and Enemy fire settings go (both always on), and a spell's damage, statuses, reactions, pushes and area hits never ask who cast it. Self-harm already worked that way for a wizard; it now holds for every actor (an enemy's own blast hurts it).

Something still has to choose targets, or a wizard's homing shot would curve into a teammate. That is the **team**, and it is used **only for aim**:

- **Who aims by team:** the AI's target, homing, chain and arc jumps, familiars' targets, decoys' lure, static discharge's arcs (to the victim's other-team actors), shields' "whose shots do I stop" (every shot but its own caster's). Nothing that decides whether a hit lands.
- **Two teams now:** `WIZARDS` and `ENEMIES`. The table holds a team per actor; more are possible later.
- **The team follows the controller.** An actor's team is its controller's: a seat's controller is on the wizards' team, an enemy's AI on the enemies'. While a wizard possesses an imp, the imp aims at enemies and enemies aim at it; while an enemy possesses a wizard, that wizard aims at the other wizards. When the controller goes home, the team goes with it.
- **Infighting:** an AI that was hurt by another actor of its own team (a stray blast) may turn on it: it targets its last attacker for a while (`GRUDGE_TIME`, 3 s), then goes back to its team's targets. So a crowd that hits itself fights itself, and an imp a wizard possessed is chased by its kin.

## Components and systems

The owner's direction (2026-10-28): a component architecture: an actor is a node with Health, Hurt, Hit and Controller components; a wizard and an enemy differ only in which ones they have.

One rule keeps it fast: **components hold configuration, cold state and behaviour; the systems keep the hot state.** Combat ticks statuses and knockback for 200 enemies, Spells keeps every caster's staffs and cooldowns, and the projectile manager moves every shot, all in packed arrays; that stays. Those arrays become indexed by actor id (Combat's `_enemies.find(node)` scans on every hit go away). A component is the node-side face of an actor in those systems: it registers the actor, configures it, and turns what the system says back into the body's behaviour.

And one rule keeps it deterministic: **only the actor runs `_physics_process`.** It steps its components in a fixed order (below), as `step(delta)`, so tests drive actors with fixed deltas as they drive wizards and enemies today, and a crowd costs one callback per actor, not one per component.

### The tree

```
Wizard (Actor, CharacterBody2D)          EmberImp (Actor, CharacterBody2D)
├─ CollisionShape2D                      ├─ CollisionShape2D
├─ Health          max 100               ├─ Health          from EnemyBase
├─ Hurtbox         r 8, offset (0,-12)   ├─ Hurtbox         r 11, offset (0,-12)
├─ Mover           90 px/s               ├─ Mover           from EnemyBase
├─ Caster          4 staffs, mana 100    ├─ Caster          1 staff, from EnemyBase
├─ Downed          (revive rules)        ├─ Contact         from EnemyBase
├─ PlayerController  seat 0-3            ├─ AIController    chase, windup, telegraph
├─ WizardLook      strips, hat, ghosts   ├─ CreatureLook    poses, flash
└─ Sprite / Sprite/Hat                   ├─ Telegraph       (Sprite2D, shader)
                                         └─ Sprite, AnimationPlayer
```

A wizard possessing the imp: the imp's `AIController` is put aside, the wizard's `PlayerController` (with its seat) drives the imp, and the wizard's body has no controller: it stands where it is and can be hit. Nothing else in either tree changes.

### The actor (`gameplay/actor/actor.gd`)

The root script of every actor scene (`CharacterBody2D`).

- **Identity:** opens its id in the actor table (`core/actors`, below) when it enters the tree, with its `ramp` (an export; an enemy's data may override it) and its controller's team, and closes it when it leaves. `id`, `ramp`, `team()`, `seat()` (both from the controller driving it; -1 seat when none).
- **Finds its components once** in `_ready` (typed child lookup, at most one of each kind; none is required). Components reach their siblings only through the actor (`actor.health`, `actor.caster`, ...), never by node path.
- **The controller:** `home_controller` (the one in its scene, or none) and `controller` (the one driving it now). `drive(controller)` hands it a guest controller (possess); `release()` gives the guest back. Every change updates the actor table's team and seat at once.
- **The body's points:** `body_offset` (the hurt circle's centre and the orbit anchor, (0, -12) for both scenes now), `aim_pivot()`, `muzzle_position()` (aim pivot plus `staff_reach` along the aim; an imp's reach is 0, so its spells start at its body as now), `aim` (unit length).
- **Intent:** a small typed object the controller writes each step and the components read: `move` (walk direction, length ≤ 1), `aim`, and per staff `pressed` (a new press) and `held`. Nothing else crosses from controller to body. With no controller the intent is empty: the body stands, aims where it last aimed and casts nothing.
- **The step**, in this order: controller `think(delta)` → Caster `step` (mana back, anchor and aim to the systems, casts from intent) → Mover `step` (walk, the card's move, recoil, knockback, statuses' pace → `velocity`) → looks `step` (read only). Then `move_and_slide()`.
- **Data:** `data` (an `EnemyBase`, or a wizard's resource later) is applied to the components before `_ready` finishes: health, speed, contact damage, staff, cards and mana. A new enemy type stays a folder with a sprite, a scene and a `.tres`, no code (phase F's promise).
- **Down and out:** `is_down()` (a Downed component says so) and `die(killer)` (no Downed: the actor sends `actor_died` and frees itself; today Combat does this for enemies).

### The components

All in `gameplay/actor/`, except the wizard rules in `gameplay/player/` and the AI's in `gameplay/ai/`.

| Component | Holds | Talks to | Replaces |
| --- | --- | --- | --- |
| **Health** | `max_health`, `health`, protection time (`protect`); `take(amount)`, `heal(amount)`; local signals `changed`, `depleted` | nobody: Combat calls it | player.gd health and `take_damage`/`heal`/`protect`; Combat's `_health` array for enemies |
| **Hurtbox** | radius, offset | Combat (`register_actor`) and Projectiles (a target every spell can hit, owned by the actor id); off while down | flow's `register_player`, ai's `register_enemy`, Combat's two target paths |
| **Contact** (the "Hit" component) | contact damage | Combat (touching another actor's hurtbox hurts it; aimed by team, so an imp walking through imps hurts none) | Combat's enemy-only `_touch_players` |
| **Mover** | walk speed; the card's move (dash, teleport, hook, swap: one implementation), recoil pushes, swap-as-target | Combat (`pace(id)`, `consume_knockback(id, delta)`), Projectiles (walls), Events (`caster_move_requested`/`_finished`, `target_move_requested`, by actor id) | both copies of the caster kit; `wizard_speed_factor`/`speed_factor`, the two knockback calls |
| **Caster** | staff count (1–4), the `StaffBase`, each staff's cards, mana pool, regen, reserved, refunds; `cast(staff)`, `set_staff(staff, cards)`, `cards_of`, `next_cast_mana`/`_reach`/`_radius`, `cast_ready(within)`; local signals `cast_done`, `staff_built` | Spells (installs its staffs under the actor id, casts), Projectiles (anchor) | player.gd's staffs and mana; ai.gd's caster row, mana, `_compiled` cache (now shared by every caster, keyed by staff and cards) |
| **Controller** (one drives) | its team; writes the intent; `think(delta)` | whatever it reads | the input and decision halves of player.gd and ai.gd |
| ↳ **PlayerController** (`gameplay/player`) | the seat 0–3 and its input: move, aim (stick, mouse, hold), press counting, the buffer, the `hold` rule, overlays capturing input. It is **the seat**: it turns the driven actor's local signals into the seat's events (`player_stats_changed`, `staff_cast`, `spell_cast`, `wizard_cast`, `staff_changed`, `bag_changed`, `build_refused`, `mana_reserved`) and the builder's requests (`staff_change_requested`, ...) into `Caster.set_staff`; the bag | `PlayerInput`, Events | player.gd's `step` input part, `_update_aim`, the seat half of player.gd |
| ↳ **AIController** (`gameplay/ai`) | targeting (the nearest actor of another team that is not down, from the projectile manager's target grid, or its grudge), chase, windup gated on `cast_ready`, recovery, decoy lure | Entities (lure), the actor | ai.gd's state machine |
| **Downed** (`gameplay/player`) | catches `depleted`: downed instead of dead, revive with 50 health, `player_downed`/`player_revived` (by the seat of the actor's home controller), the revive ring's progress | Events | player.gd's downed and revive |
| **WizardLook** (`gameplay/player`) | strips, hat by ramp, bob, idle sequence, dash stretch and ghosts, staff and reticle, rings, the possessed look | reads the actor | player.gd's drawing |
| **CreatureLook** + **Telegraph** (`gameplay/ai`) | idle, windup and hurt poses, the flash, the possessed look; the telegraph sprite | reads the actor and its AIController | ai.gd's drawing |

**The HUD follows the seat.** A seat's panel shows whatever its controller drives: the imp's health, mana and staff while possessing it. The builder edits the actor the seat drives; a possessed enemy's staff can be rebuilt for the possession's length (its type's compiled staff is not changed: the edit compiles a staff of its own for that actor, and the actor's own one comes back when the possession ends).

**Colours have one home.** The four hat colours and the enemy ramp live in the projectile manager's ramp table (by `ramp`, not player); player.gd's and Feel's copies of `PLAYER_COLORS` go. A possessed actor keeps its own ramp (an imp's spells stay ochre in a wizard's hands), and wears a ring in its driver's seat colour, so everyone sees who drives it.

**Decoys and familiars** stay in Entities as they are (pooled rows, not nodes: a decoy is a target, a familiar an orbit), but keyed by their owner's actor id, with the cap by seated or not instead of player or enemy (G8). Making them actors themselves is "Later".

**The training dummy** becomes an actor with Health, Hurtbox and no controller, plus its own small component for what it shows; its separate script goes.

## Possess (a card)

The owner, 2026-10-28: "Make this a card! A possess card, possess enemies hit for x seconds." And: an enemy with it takes over a wizard by the same rule.

- **A modifier:** the next carrier's hits possess the actor they hit, for the card's `seconds` (tuned in G9; a first guess 3 s, with a high mana cost). A carrier that hits several actors possesses the first; one possession per cast.
- **What happens:** the caster's controller (and with it its seat, HUD and builder, or its AI) drives the hit actor; the hit actor's own controller is put aside; the caster's body has no controller and stands, vulnerable. Team and seat follow the controller.
- **It ends** when its time is up, when the possessed actor dies or is downed, or when the caster's body is downed or dies: the controller goes home at once, the possessed actor's own controller comes back (an AI picks a fresh target; its windup starts over).
- **Possessing the possessed:** a newer possession of an actor ends the older one first. A driver who possesses again from a possessed body moves on; each possession sends its controller home when it ends, so they unwind in order.
- **An enemy with possess** takes a wizard: its AI drives the wizard for the time (the wizard's player sees their panel marked possessed with the time left), and the enemy stands. Its telegraph is the cast's, like every enemy spell. An enemy's possession of a wizard is capped at the card's time like any other; nothing special.
- **Events:** `possess_requested(caster, target, seconds, tag)` from Spells on the hit; `possess_started(driver_actor, actor)` and `possess_ended(driver_actor, actor)` from the actor kit, for Feel and the HUD.
- **Content:** `content/spells/possess/` with its icon, lore, look (a ring in the caster's ramp round the possessed), sound id, and two combo files, like every card (phase C's rules).

## Core: the actor table and one caster number

### `core/actors/actors.gd` (autoload `Actors`)

The one place an actor's id, team, look and seat are known, so core never infers them from a number. Packed arrays sized `ACTORS` (512: four seats, 256 enemies today, room to grow), a free list, no nodes stored except a weak lookup for `node_of`.

- `open(team, ramp, seat := -1) -> int` (-1 when full), `close(id)`, `is_open(id)`.
- `team_of(id)`, `ramp_of(id)`, `seat_of(id)`, `set_driver(id, team, seat)` (a controller change), `actor_of_seat(seat)` (the actor a seat drives now), `node_of(id)`.
- `budget_of(id)`: the seat (0–3) when a seat drives it, else `SHARED` (4): phase F's fairness rule (enemies never take a player's slot) becomes "actors no seat drives share one budget".
- `ACTORS`, `SHARED`, `NONE` (-1: no actor, the world; replaces `NO_PLAYER` where a caster is meant).

Spells, the projectile manager and Combat take it as an injected service, like the others (tests set it).

### Layers

One layer for every actor's hurtbox (the old players' and enemies' layers merge), walls and projectiles as before. A spell's `hit_layers` stop depending on its caster. Bodies still don't collide with each other (wizards walk through wizards, enemies through enemies, as now).

### Tags

One caster field instead of two bits for a player plus a row for an enemy: 9 bits, the actor id. Proposed layout (G2 settles it): staff 0–1, generation 2–4, node 5–13, caster 14–22, `FLAG` 23, under `LIMIT` 1 << 29 as before (Combat's shield tags stay int32). `make(caster, staff, generation, node)`, `caster_of(tag)`. `player_of`, `row_of`, `make_enemy`, `make_for`, `is_enemy_tag`, `ENEMY_BIT` and `FIRST_ENEMY_CASTER` go.

### Events

- **Caster-keyed events carry the actor id** (`projectile_hit`, `projectile_impact`, `form_shown`, `combo_cast`, `caster_move_*`, `target_move_requested`, `area_hit_requested`, `entity_*`, `familiar_cast_requested`, `damage_dealt`, `hit_landed`, `status_applied`, `reaction_*`, `kill_landed`, `heal_dealt`, `shot_blocked`, `ally_passed`): the parameter is renamed `caster` in `events.gd`. `NONE` only where no actor did it. Listeners stop reading the caster out of the tag.
- **Victim-keyed events name the actor hit:** `wizard_hurt` becomes `actor_hurt(actor, amount, tag)`, so `on hurt` triggers work on an enemy's staff too (today they never fire there); `shield_blocked` likewise. Combat's wizard discharge stops reusing `reaction_triggered` with the victim's index.
- **Seat events stay seat-keyed** and are sent only by a PlayerController (and coop, flow, the HUD as now): the HUD's feed, the builder, downed and revive, joined and left, device events. The HUD keeps binding by seat and never sees an actor id.
- **Deaths:** `enemy_died` becomes `actor_died(killer, actor_node, team, position)`, sent by the actor; flow counts the enemies' team for the wave.
- **Gone:** `friendly_fire_requested`/`_changed`, `enemy_fire_requested`/`_changed` (G3c).

## Combat: one rule

Combat keeps its packed arrays, one row per actor id (sized `ACTORS`), and loses the wizard slots. One `register_actor(actor)` (from the Hurtbox), one `apply_status`, `status_left`, `has_status`, `chill_stacks`, `pace`, `consume_knockback`, `give_shield`, `shield`, `pull`, `downed_note`; health through the actor's Health. Every hit goes through one path, and none asks who cast it.

Merging the two copies brought out where they differ today. Following the owner's rule that a card behaves by one core rule with no special cases (2026-10-27), each becomes one rule; the owner chose the recommended set (2026-10-28):

| Rule | On an enemy today | On a wizard today | One rule |
| --- | --- | --- | --- |
| **Shock** | the next spell hit jumps to the nearest other enemy | the next hit of any kind does extra damage | the enemy's: the next spell hit jumps to the nearest other actor |
| **Static discharge** | only a wizard's spell sets it off; arcs to other *static* enemies; spent only if something was hit | any hit sets it off (touch and enemy shots too); arcs to every enemy in range; always spent | any hit sets it off; arcs to the victim's other-team actors in range; always spent |
| **Hex** | the hit pulls the enemy toward it | the hit still pushes the wizard away | the enemy's: the hit pulls |
| **Pull** (magnet, ...) | pulls enemies | wizards are never pulled | pulls every actor |
| **Shields** (`shield` card on the caster) | an enemy has none | wizards have barrier charges | every actor |
| **Later statuses** | applied per matching element | applied even without a matching element (a longer loop) | the wizard's (the complete loop) |
| **Burn ticks** | quiet (no events unless it kills) | each tick sends `damage_dealt` | quiet for everyone; the HUD hears the health change from the seat |

## Things that change for players

Each is listed in DECISIONS when its part lands:

- **Friendly fire is always on** and **enemies always hurt each other**; the two settings and their pause-menu rows go (G3c). `docs/DESIGN.md`'s spell rule now says so ("Everything hurts everything", changed in G1 at the owner's word).
- Every actor's own spells can hurt it (self-harm, as a wizard's always could); an enemy's blast at its feet hurts it.
- Enemies hurt by their own kind may turn on the one who hurt them (infighting).
- The Combat rules above.
- `on hurt` triggers fire on enemies' staffs; enemies can carry shields (decision 6 of phase F asked for it).
- The `possess` card, both ways.
- Scatter, teleport and dash randomness is seeded by the caster's id, so a replay with the same seed differs once from before phase G.
- Enemy casts get the cast squash in Feel (it was keyed by `wizard_cast`, which only wizards sent).

## Performance

- **Nodes:** a wizard gains about seven component nodes, an enemy about six: 1,200 more nodes for 200 enemies, none with a process callback. Memory, not frame time; measured in G6.
- **Frame time:** one `_physics_process` per actor, as now. Combat's per-hit `_enemies.find` scans (several per hit, over every enemy) become array reads by id; order-preserving `remove_at` on 23 arrays per death becomes freeing a row. Expected faster; measured.
- **Enemy fire always on** means more hits per frame in a crowd (an imp's bolt can now stop on the imp in front). Measured in G3c at the web cap; if it costs, the answer is in the hit path, not a setting.
- **No per-frame allocations:** the intent object is made once per actor; components never allocate in `step`.
- **The stress run at the web cap** before G2 and after G8, numbers in DECISIONS.

## Layering

`gameplay/actor/` is a new gameplay sub-area: **the shared body kit**. It may use `core/` and the Combat autoload's actor API (as player.gd and ai.gd do today); `gameplay/player` and `gameplay/ai` build on it (their controllers, Downed, looks), and `content/` scenes put the components together. The rule "areas never call each other directly" gains its one stated exception, the same shape as core's: every area may use the actor kit's public scripts. `docs/ARCHITECTURE.md`, `gameplay/README.md` and AGENTS.md's "No single the player" line change to say: everything that acts takes an actor id; a seat (0–3) is a human, and only HUD, input and co-op rules take seats.

## Parts

### Phase G: actors (owner, 2026-10-28)

Owner sessions, one PR each, in this order: G1; G2; G3a, G3b, then G3c; G4 (may run beside G3); G5 after G3 and G4; G6; G7; G8; G9; G10. Each PR keeps the game and every test working; the bot's daily work avoids `gameplay/player`, `gameplay/ai` and `gameplay/combat` from G5 to G8 so rebases stay small. Before D3.

| # | Part | Area | Delivers |
| --- | --- | --- | --- |
| G1 | **The plan** | `docs/` | This document; ROADMAP's exception line; NEXT; DECISIONS (the owner's decisions below); DESIGN.md's spell rule ("Everything hurts everything") |
| G2 | **The actor table and tags** | `core/actors` (new), `core/spells/spell_tag.gd` | `Actors` with ids, team, ramp, seat, budget; the one-caster tag layout. Spells' `open_enemy_caster`/`close_enemy_caster` open and close actor ids underneath (callers unchanged for now). Tests: open/close/free list, `budget_of`, `actor_of_seat`, `set_driver`, tag round trips for ids 0–511, below 2²⁹ |
| G3a | **The projectile manager by actor** | `core/projectiles` | One hurtbox layer; homing, passes and shields' aim by `team_of`; batches and looks by `ramp_of`; buckets by `budget_of`; `PLAYER_COLORS` becomes the ramp table; caster-keyed events with the actor id. Tests: every `test_projectiles*` with wizards opened at non-seat ids |
| G3b | **Spells by actor** | `core/spells`, `core/events` | `_foes` gone (every spell hits every actor); `_budget`, `_delay`, `_start_beam`, `_relay`, `_on_hurt`, `_send_reserved` by budget, team and seat; events renamed `caster` and carrying the id; `actor_hurt`; listeners (player, ai, entities, feel, combat) updated mechanically. Tests: `test_spells_enemy_casters` becomes `test_spells_actors`; a four-player staff unchanged |
| G3c | **No more fire settings** | `core/settings`, `gameplay/coop`, `gameplay/ai` (Entities), `hud/menus/pause`, `core/events` | Friendly fire and Enemy fire removed (settings, events, menu rows, tests); the stress run at the web cap with enemies hitting each other |
| G4 | **The actor kit** | `gameplay/actor` (new) | `actor.gd`, the intent, Health, Hurtbox, Contact, Mover, Caster, the controller base, `drive`/`release`; not used by the game yet. Tests: each component alone with a test controller; the caster kit's moves (ported from `test_player_caster` and `test_ai_moves`); a controller change updates team and seat |
| G5 | **Combat by actor** | `gameplay/combat` | One body model by actor id; `register_actor`; health through Health; the one rules above; `actor_died`. Tests: `test_combat*` on actors, a test per changed rule |
| G6 | **Enemies are actors** | `gameplay/ai`, `content/enemies`, `gameplay/flow` | `AIController` (with grudges), `CreatureLook`, `Telegraph`; the imp, the shooting dummy and the training dummy as actor scenes; flow spawns them as actors; ai.gd is the controller. Tests: `test_ai*`, infighting, the dummies, the waves; node count and the stress run |
| G7 | **Wizards are actors** | `gameplay/player`, `content/wizard`, `gameplay/flow`, `gameplay/coop` | `PlayerController` (the seat), Downed, `WizardLook`; wizard.tscn as an actor; flow and coop by actor and seat; player.gd is the controller. Tests: `test_player*`, coop, the builders, the 4-bot smoke test |
| G8 | **Feel and Entities by actor** | `gameplay/feel`, `gameplay/ai` (Entities) | No `players` group or `index` reads: actor, ramp and seat; entity rows by owner actor, capped by seated or not; the cast squash for every actor; the last `NO_PLAYER` branches gone |
| G9 | **Possess** | `core/spells`, `gameplay/actor`, `content/spells/possess`, `hud/` | The card and its rule (above): `possess_requested`, `drive`/`release` timed, the HUD following the seat with a possessed mark and time, the driver's ring, the builder on a possessed actor. Tests: a wizard possesses an imp and casts its staff from the seat's buttons; an imp possesses a wizard and the AI drives it; every way it ends; nested possessions unwind; two combo files |
| G10 | **The docs** | READMEs, `docs/ARCHITECTURE.md`, `AGENTS.md`, `CONTRIBUTING.md` | The new contracts, the actor-id rule, the example to copy for a new enemy and a new component; the stress numbers in DECISIONS |

## Owner decisions (2026-10-28)

1. **A component architecture:** actors made of components (Health, Hurt, Hit, Controller, ...); a wizard and an enemy differ only in which they have.
2. **Combat:** one rule each, the recommended set (the table in "Combat: one rule").
3. **No sides:** everything can damage everything. Friendly fire and enemy fire are always on; both settings go.
4. **Teams for aim only:** targeting (the AI, homing, chain and arc, familiars, lure) aims at another team; damage ignores teams.
5. **Possess is a card:** the next carrier's hit possesses the actor for x seconds. The caster's body stands, vulnerable, meanwhile.
6. **Enemies may possess wizards,** by the same rule.

## Later (in `docs/BACKLOG.md`)

- Decoys and familiars as actors (a decoy: Health, Hurtbox, no controller; a familiar: a Caster and an orbiting controller), if Entities' pooled rows start to need the kit.
- AI teammates for fewer than four players, and bosses a player can take over: a controller each, nothing new in the body.
- More teams (enemy factions that fight each other) and more ramps than five: the table has room; the shader's ramp field grows from two bits and a flag.

## Self-critique against docs/DESIGN.md

- **Nobody waits for anybody:** a seat drives one actor at a time and is never shared. **One risk:** an enemy's possess takes a player's control away for its seconds, which is the nearest thing in the game to making a player wait. It is a status like freeze (which also stops a wizard), it is telegraphed, and it is capped by the card; the owner chose it. The playtest in D3 asks about it explicitly.
- **Spell rules:** DESIGN.md said "Hurting other players stays an option"; at the owner's word it now says "Everything hurts everything" (G1).
- **Readable chaos, telegraphs:** the telegraph stays the AI's promise; a possessed actor wears a ring in its driver's seat colour and keeps its own spell ramp, so it reads as "that imp is player 2's now". A seat-driven enemy shows no telegraph (a human casts when they like).
- **Deep spell building, one rule per card:** strengthened: every card works the same on every actor, Combat loses its second copy of every rule, and possess adds a card whose combos (possess · nova, possess · chain) nobody designed.
- **Quality, performance:** the hot paths stay data-oriented; the risks are churn in about 6,000 lines of tests (paid part by part, each PR green) and more hits per frame with enemy fire always on (measured in G3c).

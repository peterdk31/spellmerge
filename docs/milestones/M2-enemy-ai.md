# M2 rework: an enemy AI that plays whatever staffs it holds

**Goal:** one AI for every enemy, minion, boss and test bot. It **reads what its staffs will cast next** and plays them in any situation, so designing an enemy means designing its staffs and a few numbers, never code. Bosses add more staffs, other numbers and **phases**. Enemies **dodge**, **channel** sustained casts, and **look like they work together**.

**Status (2026-11-01):** designed with the owner in one session (the decisions are in "Owner decisions"). An owner exception like phases F, G and H (docs/ROADMAP.md): it is the **baseline** enemies are built on later. Designing actual new enemies and bosses on it stays M3 and later.

**Why:** today's `AIController` (gameplay/ai/ai.gd) presses staff 0 and nothing else. Its numbers (`attack_range`, `windup_time`, `recover_time`) are exports in each enemy's scene, so enemies differ by hand-tuned constants, not by what they cast. The test bot (tests/bots/bot.gd) has its own state machine and its own rule that "RB is the dash staff". The owner's earlier rule "no AI knows what it casts next" (DECISIONS, 2026-11-01) was there to stop hard-coding like `if dash.is_next(): do_dash()`. This design keeps that goal by a different route: the AI knows **what a cast does** (numbers and yes/no answers), never **which card** it is.

**Done when:**

1. Every part in "Parts" is merged and `ci/build/build.sh --quick --tests` is green.
2. No file under `gameplay/ai/` or `tests/bots/` names a card or carrier id (a test checks it).
3. Every combo file (`content/spells/combos/*.json`) put on an enemy in the AI fixture is cast at least once in a scripted fight, never wound into a wall when aimed, and never kills its caster with its own blast.
4. Swapping an enemy's staffs mid-fight changes its behaviour (a kiter becomes a rusher) with no other change.
5. The enemy arena spawns any enemy (one or more) from a list, in the sandbox, from the pause menu and from tests.
6. The test bots fight on the same AI; the 4-bot run passes.
7. The stress run and the horde run are no slower than before.

## Owner decisions (2026-11-01)

1. **The AI may know what it casts next.** It reads a summary of the next cast (`CastSense`), never card ids. Replaces "no AI knows what it casts next".
2. **The next cast,** not the whole staff: it matches the telegraph.
3. **Bosses are built from the same parts:** cool staffs make the behaviour; a profile of numbers (speed, size, accuracy, ...) and more staffs make it harder; **phases** swap the staffs, the profile and the look. No `.gd` per boss: a new mechanic goes into the shared AI, so every enemy gains it.
4. **Bots use the same AI.**
5. **A baseline:** this builds the engine and moves today's strays onto it; new enemies come later.
6. **Hold cards are usable by the AI** (the channel, below).
7. **Dodging shots is part of the baseline.**
8. **Difficulty scales the profile** (one multiplier set, with the player count).
9. **Enemies should look like they work together;** coop cards (heal an ally, shield an ally) come later, so adding a behaviour must be easy. **Behaviours are files** (replaces the enum-and-`match` rule for the AI; DECISIONS).
10. **Some randomness** in the profile, seeded per enemy.
11. **A visible "call"** before a group attack.
12. **A phase changes the sprite, face and size,** not the whole scene; the change is an invulnerable pause.
13. **An arena for enemies:** one arena with a picker, spawning one or more enemies from a list, used both to play against an enemy and to test and tune it.

## The picture

```
 world ──────► Perception ─┐   (target, allies, threats, walls: AISight, the target grid,
                           │    the shot query, the TeamBoard)
 own staffs ─► CastSense ──┼──► Behaviours (each: want(), act()) ──► Executor ──► ActorIntent
                           │    the highest want wins, with           (windup, channel,
 AIProfile ────────────────┘    a bonus for the one running)          recover, move, aim)
```

- **Perception** is read on the profile's `reaction` timer (staggered per enemy, like today's retarget), never every frame.
- **Behaviours** are scored on the same timer. The executor runs every step and is cheap.
- **The executor** is the only code that writes the intent. A behaviour asks for a target (an actor, a point), a staff (or none) and a way to move.

## What the AI knows of a cast: `CastSense` (core/spells)

One small read-only object per compiled cast (`CompiledCast.sense`), made once by the compiler. Compiled staffs are cached per staff and cards for every caster, so it costs nothing per enemy or per frame. Read with `Spells.next_cast_sense(actor, staff)` and `Caster.next_cast_sense(at)`; refreshed by the AI on `Caster.staff_built`.

| Field | What it says | From |
| --- | --- | --- |
| `reach` | How far it goes along the aim (0: not aimed) | the carriers' `reach_of` (as the telegraph) |
| `radius` | Its hit width | the first carrier |
| `damage` | Expected damage of the whole cast (shots × repeats × hit) | the hit profiles |
| `blast` | Radius of an explosion at its end (it can hurt its caster closer than this) | `BLAST` behaviour |
| `area` | Hits round a point or the caster rather than along a line (nova, ring, rain, rune) | `RING`, `OUTWARD`, `CARRIES_PAYLOAD` |
| `speed` | Shot speed (for leading a moving target; 0 for instant) | the first carrier |
| `homing` | It steers itself | `homing_range` |
| `moves_caster` | It moves the caster (dash, teleport) | `MOVES_CASTER` |
| `blocks` | It stops shots: a wall, a shield, a deflect | `BLOCKS` (new trait), `SHIELD`, `DEFLECT` |
| `spawns` | It makes a decoy or a familiar | `SPAWNS` (new trait) |
| `heals` | Its hits heal | the hit profile's `heal` |
| `status` | Its hits apply a status | the hit profile |
| `sustained` | It stays on until pressed again (`hold`) | `HOLD` behaviour |
| `repeats_held` | Holding the button keeps casting it (rain, swing, beam) | `REPEATS_HELD`, `HOLDS_STAFF` |
| `mana`, `delay` | Its cost and its delay | `CompiledCast` |

**No card ids.** Two traits are added so the summary needs no id: `BLOCKS` (a carrier that stands in the world and stops other actors' shots: wall) and `SPAWNS` (decoy, familiar). The card-rules test already checks that every carrier answers its traits. A test reads every script under `gameplay/ai/` and `tests/bots/` and fails on any card or carrier id, so the AI can only know a card through what the card does.

## The profile: `AIProfile` (core/base, a `.tres`)

Shared presets live as files (`content/enemies/profiles/*.tres`); an enemy names one or has its own sub-resource.

| Field | Range | What it changes |
| --- | --- | --- |
| `aggression` | 0–1 | How far inside its reach it fights; how readily it closes in |
| `caution` | 0–1 | When it evades or guards: health, being crowded, shots coming |
| `accuracy` | 0–1 | Aim error (1: exact) |
| `lead` | 0–1 | How far it aims ahead of a moving target |
| `reaction` | seconds | How often it looks and decides (also how late it notices a shot) |
| `dodge` | 0–1 | How well it dodges (0: never; the horde's swarmers) |
| `windup_scale` | × | Every telegraph |
| `rest_scale` | × | The recovery after a cast |
| `track_speed` | °/s | How fast a held cast turns after its target (0: locked, as today) |
| `channel_max` | seconds | Longest it holds a cast |
| `commitment` | 0–1 | Bonus for the behaviour running now (no flicker; decisive or hesitant) |
| `randomness` | 0–1 | Sometimes the second-best choice, a late dodge (seeded per enemy, so tests repeat) |
| `teamwork` | 0–1 | How much it staggers fire, spreads round a target and calls attacks |

**Difficulty** (gameplay/difficulty, when built): one multiplier set from `difficulty_changed`, held by the TeamBoard (one listener, not one per enemy). It scales `reaction`, `accuracy`, `dodge` and `windup_scale` of every profile.

**Fair telegraphs by rule:** a windup lasts `base + k × danger` × `windup_scale`, where danger comes from the cast's `damage` and `area`. A big spell telegraphs longer without hand-tuning, so "every attack has a readable telegraph" holds for staffs nobody checked by hand. A floor keeps any harmful cast above a minimum windup.

## The enemy's data (core/base)

```
EnemyBase
├─ max_health, move_speed, contact_damage, scene, boss      (as now)
├─ size: float = 1.0                                         (body and sprite scale)
├─ staffs: Array[StaffCards]   1–4 (StaffCards = staff + cards)   replaces staff/cards
├─ profile: AIProfile
└─ phases: Array[EnemyPhase]   optional
     EnemyPhase
     ├─ health_below: float (fraction), after_seconds: float   (first that holds)
     ├─ staffs: Array[StaffCards]   (empty: keep)
     ├─ profile: AIProfile          (null: keep)
     ├─ look: PhaseLook             (null: keep: texture, face style, glow, size)
     └─ transition: float           (seconds invulnerable, with its own telegraph)
```

The scene keeps only the body: no AI numbers in the `.tscn` any more. A data check (validator) refuses: an unknown card, more cards than the staff has slots (today's Rime Crook: `frost, pull, bolt` on 2 slots, so the bolt is cut silently), more than 4 staffs, a phase with no condition.

**Phases** are a component (`gameplay/actor/phases.gd`, `Phases`), so they follow the body whoever drives it (a wizard possessing a boss still sees it change). On the condition it protects the body (`Health.protect(transition)`), installs the phase's staffs (`Caster.set_staffs`), sends the local signal `phase_changed(index)`; the AI swaps its profile and stands in a TRANSITION step; the look (CreatureLook, Face) swaps texture, style, glow and size.

## Behaviours (gameplay/ai/behaviours/)

Each is one file extending `AIBehaviour`, holding no state (one shared copy for every enemy; per-enemy memory is in the controller's fields, so nothing is allocated). Two functions:

- `want(brain: AIBrain) -> float`: how much it wants to act now (0 = not at all).
- `act(brain: AIBrain) -> void`: writes a plan into the brain: `plan_target` (node or point), `plan_staff` (-1 for none), `plan_move` (a mode: toward, away, strafe, a direction), `plan_urgent`.

The brain asks every behaviour on its timer, keeps the highest `want` (the running one gets `commitment` as a bonus; `randomness` sometimes takes the second), and calls its `act`. The list is a fixed list of preloads in `behaviours.gd`: **a new behaviour is one new file and one line.**

**Baseline behaviours:**

| Behaviour | `want` is high when… | What it plans |
| --- | --- | --- |
| **Fight** | a staff's next cast damages and its reach covers the target (or it hits round itself and the target is close), the line is clear, it is ready | that staff at the target; stand |
| **Flank** | a fight is possible but a wall is in the line | walk `AISight.detour` (today's REPOSITION) |
| **Close in** | it is farther than its range band; a `moves_caster` cast is ready and the target is far | dash at it, else walk in |
| **Keep range** | it is nearer than its band (it has reach and caution) | step back or strafe |
| **Dodge** | a shot will hit it soon (`Projectiles.threat`), times `dodge` | step off the line; urgent: a `moves_caster` cast, or a `blocks` cast |
| **Guard** | hurt recently or under fire, a `blocks` cast is ready, times `caution` | cast it toward the threat |
| **Evade** | low health or crowded, times `caution` | away: a `moves_caster` cast if ready, else to `AISight.cover` |
| **Open** | a `spawns` or `area` cast is ready and nothing of it is up | cast it once (summon, zone) |
| **Chase** | always a little | walk to the target (the only one for an enemy with no staffs) |

**The range band** comes from its staffs now: the best damaging `reach` it has, times `aggression` (the band is `reach × (1 - 0.6 × aggression)` to `reach × 0.95`), and at least its blast radius plus a margin. A bolt makes a kiter, a swing or touch a rusher, and a new staff changes it at once.

**Later behaviours, one file each** (not built now): *Heal ally* (an ally on the TeamBoard is hurt and a `heals` cast is ready: target the ally), *Shield ally*, *Focus fire* (join the attack on a nearly dead target), *Cover a caster* (stand between the players and a teammate in a long windup). The baseline makes them possible: **a target can be anyone**, and the TeamBoard knows who is hurt.

## The executor

The only writer of the intent. Its steps:

- **MOVE:** walk the plan's way (`Mover`), aim at the target.
- **WINDUP:** the chosen staff, only when `Caster.cast_ready(windup)`, so a telegraph is always followed by its cast (as now). The aim locks at the start; with `accuracy` < 1 a seeded error is added once; with `lead` the aim goes ahead of a moving target by the cast's `speed`.
- **The cast:** `intent.press(staff)`.
- **CHANNEL** (a cast that `repeats_held`, or `sustained`): after the windup it keeps holding while the target is in the lane (its `radius` and `reach`), its free mana is above a reserve, and it has held less than `channel_max`; the aim turns toward the target at `track_speed`. A `sustained` cast (hold card) is switched on by a press and off by another press when the behaviour that chose it no longer wants it.
- **RECOVER:** stand; `rest_scale` × a time from the cast's delay; the aim stays locked.
- **TRANSITION:** a phase change: stand, nothing cast.
- **Urgent moves:** when the plan is urgent and some staff's next cast `moves_caster` and is ready, it presses it once and the dash goes the way it walks (the bot's "dashing emerges", now shared).
- Timers slow by `Combat.pace` (freeze stops an attack), as now.

**The telegraph** is drawn for the chosen staff: `ActorController.telegraph_staff()` (0 in the base), read by `CreatureLook` with `Caster.next_cast_reach(at)` and `next_cast_radius(at)`.

## Dodging: `Projectiles.threat` (core/projectiles)

`threat(point, radius, team, out)`: of the live shots that are not its team's and will pass within `radius` of `point`, the one that hits soonest: its time to hit and the way off its line. It walks the shots near the point only (the manager's grid), so it costs about what `nearest_target` costs. Called on the reaction timer, only by enemies whose profile has `dodge` > 0 (the horde's swarmers have 0, so 500 of them cost nothing).

## Working together: the TeamBoard (gameplay/ai)

One per team (kept by `Entities`, the AI area's autoload), refreshed on a timer, never per hit:

- who on the team is hurt, and how badly (for heal and shield behaviours later);
- how many teammates are on each target, and on which side (Fight and Close in prefer a target or a side with fewer: **spreading round a target**);
- when a teammate last started a windup (Fight waits a short, seeded beat if one did: **a barrage reads as a sequence**, not one flash);
- **the call:** an enemy about to start a windup while teammates are near may first glance at the nearest one (the Face looks at it, brows raised, `CALL_TIME`), and those within reach that can fight follow within a beat. Scaled by `teamwork`.

## Bots (tests/bots)

The bot keeps building staffs and pressing virtual buttons (it tests the real input path), but its decisions come from the same brain: an `AIBrain` with a bot profile fills an `ActorIntent`, and the bot turns that into `PlayerInput.send_virtual`. Its own state machine and the "RB is the dash" rule go: it finds its dash through `moves_caster`.

## The enemy arena

The sandbox room, grown: the pause menu's sandbox page gets an **Enemy** row (a picker over every enemy in the registry, found by folder, so a new enemy appears by itself), a **count** (1–8), **Spawn** and **Clear enemies**. `sandbox_spawn_requested(player, enemy_id, count)` is heard by Flow, which places them at the room's enemy spawns. Tests use the same Flow call (`spawn_in_sandbox(id, count)`), so an enemy's tuning test and a person playing against it see the same room. An **AI view** toggle on the same page draws over each enemy its behaviour and step (`Fight · WINDUP`), its range band and its target line, for tuning.

## Performance

- The brain decides on the `reaction` timer (0.2–0.5 s, staggered), behaviours read only floats and booleans (≤ 4 staffs, ≤ 10 behaviours): about 40 calls per enemy per decision.
- The executor runs every step with today's cost.
- `CastSense` is made once per compiled cast and cached; `threat` runs only for dodgers; the TeamBoard refreshes on a timer.
- Nothing is allocated per step; behaviours are shared and stateless.

## Parts

| # | Part | Paths | Delivers |
| --- | --- | --- | --- |
| AI1 | **The plan** | `docs/` | This document, the DECISIONS entry, the roadmap exception, the tasks |
| AI2 | **What a cast does** | `core/spells` | `BLOCKS` and `SPAWNS` traits; `CastSense` made by the compiler; `Spells.next_cast_sense`; `Caster.next_cast_sense`; the no-card-id test |
| AI3 | **Shots coming** | `core/projectiles` | `threat` and its test |
| AI4 | **Enemy data** | `core/base`, `gameplay/actor`, `content/enemies` | `StaffCards`, `AIProfile`, `EnemyPhase`, `PhaseLook`; `EnemyBase.staffs`, `profile`, `phases`, `size`; the actor fills 1–4 staffs; every enemy moved (Rime Crook fixed); the data check |
| AI5 | **The brain** | `gameplay/ai` | `AIBrain`, `AIBehaviour` and the baseline behaviours, the executor (windup, channel, recover, urgent moves, aim error and lead), the telegraph per staff, the range band; `AIController` on it |
| AI6 | **The TeamBoard** | `gameplay/ai` | Spreading, staggered fire, the call (Face glance) |
| AI7 | **Phases** | `gameplay/actor`, `gameplay/ai` | `Phases` component, transition, look swap; a test boss in tests only |
| AI8 | **The enemy arena** | `gameplay/flow`, `hud/menus/pause`, `core/events` | Picker, count, spawn, clear, the AI view; `spawn_in_sandbox` |
| AI9 | **Bots on the brain** | `tests/bots` | The bot's decisions from the brain; the 4-bot run |
| AI10 | **Difficulty** | `gameplay/ai` | The TeamBoard hears `difficulty_changed` and scales the profiles (once difficulty sends it) |

## Self-critique against docs/DESIGN.md

- **Readable chaos:** every harmful cast still has a telegraph, and its length now grows with the danger by rule; the call and staggered fire make a group's attacks read as a sequence.
- **Deep, combinable spells:** enemies use the same player cards and now use all of their staffs; a boss is a showcase of combos the players can learn from.
- **1–4 co-op, nobody waits:** targets are any actor of another team; spreading round a target shares the pressure between players.
- **Risk:** a smart AI can feel unfair. `randomness`, `reaction`, `dodge` and difficulty keep it beatable; the arena is where we tune it.

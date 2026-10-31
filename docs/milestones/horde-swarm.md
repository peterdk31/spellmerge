# Horde swarm: 500+ enemies at 60 FPS

Part of [horde.md](horde.md). H1 measured that the horde cannot go past about 200–250 enemies on desktop (80–100 on web) at 60 FPS while every enemy is a full actor: at 600 one physics step costs about 31 ms against 16.7 allowed. This document proposes **the swarm**, a cheaper body for the horde's touch-only enemies, so the horde reaches 500+. It changes nothing for wizards, staff enemies or any other mode, and it lives with the horde, so it is removed with it.

## Where the time goes (H1, 600 enemies, one physics step)

| Part | ms | Per enemy | What the swarm does with it |
|---|---|---|---|
| Looks (`CreatureLook`, `Face`) | 6.5 | a node tree and scripts drawing | **gone:** one MultiMesh draws every swarmer |
| AI `think` | 6.0 | a controller each | **gone:** one shared chase step |
| Mover and `move_and_slide` | 3.2 | a physics body each | **gone:** one step moves every swarmer, walls as the arena's rect plus a coarse grid, spacing by a spatial hash |
| Projectile target grid | 5.0 | a hurt circle each | stays (every swarmer can still be hit by everything), made cheaper in S5 |
| Combat | 1.7 | a row each | stays as it is |
| Spells and the rest | ~8 | | unchanged |

Expected at 600: about 12–15 ms per step on desktop before S5. **Target (owner, 2026-10-31: aim higher):** 1,000 on desktop and 500 on web, measured by the stress run (S4); the caps are set to what it holds.

## The idea: a light node per swarmer, everything else in rows

Every rule in the game finds a body by its node: shots hit target nodes, `strike` and `nearest_target` return nodes, `enemy_died` carries the node, statuses and knockback are Combat rows found by node or id. Taking the node away would mean rewriting the hit pipeline in core. So a swarmer **keeps one bare `Node2D`**: no children, no script, never drawn. Nothing else is per swarmer.

- **Combat:** each swarmer is registered as a **plain body** (Combat's `BODY_PLAIN`, which exists for bodies without the actor kit): health, hurt circle, touch damage and team in Combat's rows; it opens the actor id. So every hit, status, reaction, shock jump, static, hex, pull, barrier and touch rule applies to a swarmer exactly as to any actor (the rules pass: one rule, no special cases).
- **The swarm** (`gameplay/horde/swarm.gd`, owned by the director): packed arrays by swarm row: node, actor id, kind, velocity, target, flash time, animation phase. One `step(delta)` for all: chase the nearest wizard (target grid query staggered as the AI does), times `Combat.pace` (chill and freeze), plus `consume_knockback`, spacing from a spatial hash so they do not stack, stopped by the arena's walls; then writes each node's `position`. Nothing is allocated per step.
- **The look: identical to a full enemy** (owner, 2026-10-31: a simpler look is not fine). Drawn in batches, one `MultiMeshInstance2D` per layer and kind (body, eyes, brows), with per-instance transform and custom data and a small shader that picks the atlas frame, but showing everything a full stray shows: CreatureLook's hop while walking and bob while standing, the hurt pose for HURT_TIME, Feel's hit flash and squash, and the whole `Face` (eyes in the nine look directions and the blink, brows by mood: worried on a hit, the stray's own idle habits from a per-row seed, the follow-through lag of eyes and brows behind the body). The rules are the same numbers as `creature_look.gd`, `face.gd` and Feel's (read from their constants, not copied), so a change there changes both. Statuses keep their look from Feel, which draws by node position as for any body. **Parity test:** a full `crypt_mite` and a swarm `crypt_mite` play the same scripted second (walk, stop, a hit, a status) side by side and their frames are compared pixel for pixel, within a small tolerance.
- **Death:** Combat kills a plain body as any other (`enemy_died`, then frees the node); the swarm drops the row when the node leaves (row found by node; O(1) swap-remove).
- **Kinds:** `crypt_mite` and `bone_husk` get a `swarm: true` flag in their EnemyBase (or a small `SwarmKind` resource next to them): the director spawns a kind with that flag into the swarm, and everything else as a full actor, as now.

## Where a rule needs a full actor: promotion

Some cards act on what only a full actor has: `possess` takes over a body's controller. The rule "no silent no-ops" holds by **promotion**: when a swarmer hears something that needs the actor kit (today only `possess_requested` for its id), the swarm replaces it in the same step by the full actor scene of its kind, at its place, with its health, statuses and knockback carried over (same Combat row moved, or re-registered with the same numbers), and that actor takes the request. A promoted swarmer stays a full actor. The card-rules test gets a case: every card played on a swarmer does what it does on a full actor of the same kind.

**Built (S3, 2026-10-31).** A request is kept and the swarmer promoted at the start of Combat's next step (`Combat.stepping`: no hit is being dealt then, so the hit that asked is dealt whole to the swarmer, and the full actor stands before any touch is checked) or of the swarm's step. The actor takes the swarmer's actor id (`Actor.take_id`) and Combat row (`row_state`, `carry_row_state`: health, every status with its time, strength and stacks, barrier, push, armed slam, waits, last attacker), its place, aim, velocity, name, parent (the director counts it as before) and grudge. `body_replaced(actor, old, new)` tells whatever keeps the old node: the projectile manager (its target entry in place, homing targets, hit memories, stuck shots, payload skips), Spells (chain memories, the jump queue, each carrier's struck lists: swing, slam, dash, beam, teleport) and Feel (status looks, effects that follow). tests/core/test_card_rules_swarm.gd plays every card on every carrier on standing swarmers and on full mites: the traces are equal (possess promotes). Still not the same: the body's look restarts (hop phase, blink, flash, hurt pose: the actor's own CreatureLook and Face start fresh), swarmers push each other apart (spacing) where full actors walk through each other, and a homing dash steering on a swarmer (the Mover's own `Homing`) loses it.

## Parts

| # | Part | Paths | Delivers |
|---|---|---|---|
| S1 | **The swarm step** | `gameplay/horde/swarm.gd`, tests | Rows, chase, pace, knockback, spacing, walls, plain-body registration, death clean-up |
| S2 | **The swarm look** | `gameplay/horde/swarm_look.gd`, its shader | Batched body, eyes and brows per kind with every pose, flash, squash and face habit of a full enemy; the parity test |
| S3 | **Promotion** | `gameplay/horde/` | Possess (and any later actor-only rule) promotes a swarmer; card-rules case |
| S4 | **Scale and caps** | `tests/benchmark/`, the curve | The horde stress scenarios on the swarm; the caps raised to what holds 60 FPS (target 1,000 desktop, 500 web) |
| S5 | **Cheaper targets** | `core/projectiles` | The target grid's per-target cost, measured before and after; no rule changes |

S1, S2 and S5 are built in parallel (S2 reads the rows S1 defines, below); S3 after S1; S4 last.

## The rows S1 gives S2

`Swarm` (in `swarm.gd`) keeps, by row 0 to `count - 1` (packed arrays, rows swap-removed on death): `nodes` (the bare Node2D), `kinds` (index into `kinds_list`, each a `SwarmKind`: enemy id, the full scene to promote to, the body texture and the stray face style read from that scene), `positions`, `velocities`, `aims` (the look direction), `seeds` (per-row, for idle habits), `hurt_left` (seconds of the hurt pose left, set on `damage_dealt`), `down` (never true for a swarmer today), and `moved` (the step after which the look reads them). The look never writes them.

## S4: scale (2026-10-31)

Measured with `stress.gd -- --horde-swarm` (headless Linux under WSL, 24 threads, otherwise idle; game logic only, no rendering): four bots with heavy builds, the shot cap (500) kept full with filler shots, the swarm with its look, staff enemies as full actors. `--profile` adds a tree profile (`tests/benchmark/tree_profile.gd`: every processing node timed by script, the engine's own time apart; `--profile-signals` also times the hot events' listeners), `--swarm=N --staff=M` sets the counts, and `tests/benchmark/swarm_step.gd` times the swarm and its look alone.

**Where the time went (before; the run asked for 1,000 swarmers and 50 staff enemies).** The probe's "physics step avg 30 ms" was not a step: Godot's `TIME_PHYSICS_PROCESS` monitor is the longest step of each second, refreshed once a second. The real steps took about 13 ms, run 1.7 times a frame:

| Part | ms | |
|---|---|---|
| Projectile manager | 3.8-4.4 a step | target refresh 0.7, hit tests 2.2, the hit events: a spell hit's reactions and bursts strike dozens of packed swarmers (1.3 reactions a step at about 2.6 ms each), every damage about 30 us with its listeners (Feel's juice about 16, Combat's own about 10, the swarm 2.5); each shot hit's `projectile_impact` about 10 us (Feel 8) |
| Swarm | 3.7 a step | rows 1.8 (three calls into Actors and Combat per row), spacing 1.8, walls 0.6, node writes 0.2 |
| 50 staff enemies and 4 wizards | about 4 a step | 74 us an actor (AI, caster, looks, mover, `move_and_slide`) |
| Spells, Combat | 1.0-1.2, 0.9 a step | |
| The engine | about 1.2 a step | physics server, message queue, frees |
| Process scripts | about 6 a frame | the runner 3.7 (the bots 0.7; the rest were spawns the full actor table refused, below), shot drawing 2.0, Feel 0.8, HUD 0.2 |

Found: 1,000 swarmers + 50 staff enemies + 4 wizards is more than the actor table's 1,024, so every frame the runner tried about 30 spawns that Combat refused, each making and freeing a node (about 70 us each). The scenario now asks for 1,000 + 16, and a web-size one, 500 + 25, was added. The look was missing (the runner built its own swarm); it is in now and timed apart: 1.25 ms a step and 0.6 ms a frame at 1,000. Peak nodes about 3,200: the 1,000 bare swarmer nodes, about 950 in the actors (sprites, components), about 800 in the HUD (buttons, glyphs, labels) and about 270 in Feel; only the actors process per frame.

**Changed:** the swarm step asks for every row's stop, pace and push once (`Actors.spend_holds`, `Combat.own_paces_and_pushes`), folds the move into the spacing hash and the push, floor, walls and node writes into one pass, and walks the neighbour cells without a `match`. Every swarmer moves exactly as before (`tests/gameplay/horde/test_swarm_steps.gd`: a fingerprint recorded before). The swarm alone at 1,000: 4.45 to 3.29 ms a step (`swarm_step.gd`, medians). The probe now times every step's scripts itself.

**After** (frame avg, two runs each):

| Scenario | Before | After |
|---|---|---|
| 1,000 swarmers + 16 staff | 153 ms (a step 17.6 ms: 8 steps a frame) | 90-155 ms (a step 15.0-18.3 ms): not 60 FPS |
| 600 + 16 | | 15.0-18.7 ms |
| 500 + 25 (web size) | 19.7 ms (a step 12.5) | 13.8-14.6 ms (a step 11.5): 60 FPS |

A step costs about 6.4 ms, plus 9-11 us a swarmer (swarm 3.3-3.8, look 1.2-1.3, Combat, more hits), plus 33-43 us a full actor: a full actor costs about five swarmers. 60 FPS holds while a step stays under about 12 ms (process about 3.5 ms and the engine about 1.3 ms come on top). **Web** (an estimate: scripts there run roughly 2-3x slower): at 500 + 25 a step would take 23-35 ms. The crowd's own share is about 3.5 ms on desktop (7-10 on web); the rest is the four bots' spells and 500 shots, so this load does not hold 60 FPS on the web at any crowd.

**Caps:** the director's one cap counts swarmers and full actors alike, and the curve's last point is about 41% full actors. At that mix 225 holds 60 FPS on desktop (frames 11.4-14.2 ms; 250 sits on the line at 13.7-19.0; 300 is over at 17.5-19.1), and 150 costs what the old web cap's 100 full actors did (8.5-8.7 against 8.2-9.0 ms). So MAX_ALIVE_DESKTOP goes from 200 to 225 (and the curve's last point), and MAX_ALIVE_WEB from 100 to 150. For 500+ the full actors must be counted for what they cost: a cap per kind or a cost per kind (a full actor counts as 4-5 swarmers: about 600 swarmer-units on desktop, 300 on the web), with the late curve mostly swarmers.

**Left** (shared areas, or bigger than S4):
- Every damage's listeners: Feel starts a sound, reads the camera and shows an effect per hit, about 2 ms a step here. A hit sound once per sound per step, and the camera read once a frame, would cut it without a visible change.
- A full actor's step (AI, looks, mover).
- The projectile manager reads every swarmer's node for its place each step (0.7 ms at 1,000); it could take the swarm's rows instead.
- Spacing (1.25 ms at 1,000) and the look (1.2 us a row) are near what GDScript does.
- Single steps of 25-55 ms when the bots' heavy builds cast (the p95).
- Past 1,020 bodies the actor table must grow (SpellTag's caster bits, as H1 did).

## Merged (2026-10-31)

S1, S2, S3, S4 and S5 merged together on main. Measured after the merge (S3 removed Feel's flash cap; `stress.gd -- --horde-swarm`, headless desktop, idle machine):

| Scenario | Frame avg | p95 | A physics step's scripts |
|---|---|---|---|
| 500 swarmers + 25 staff enemies | 7.5 ms | 17.3 ms | 8.6 ms |
| 1,000 swarmers + 16 staff enemies | 35 ms | 91 ms | 14.1 ms (2.1 steps a frame: it falls behind) |

Caps: 225 alive on desktop, 150 on the web, one count for swarmers and full actors alike.

## Next (owner, 2026-10-31: plan saved, not started)

Two parts, in this order. Each is one branch and one PR; both are measured with `stress.gd -- --horde-swarm` (and `--swarm=N --staff=M` sweeps) before and after, and neither changes a rule or a result (every equivalence and fingerprint test still passes).

### S6: a cost budget instead of a head count

The director's cap counts heads, so the full actors in the late curve (about 41 %) set the limit. Count what each enemy costs instead.

- **Cost per kind.** Each enemy kind gets a cost in swarmer units: a swarmer 1, a full actor its measured share (S4: about 4-5). Read from data, not a table in code: a field on `SwarmKind` for swarm kinds, and a default for full actors that the stress run measures and the director reads (`HORDE_FULL_ACTOR_COST`, one named constant, changed only with a measurement).
- **The budget.** `MAX_ALIVE_DESKTOP` / `MAX_ALIVE_WEB` become `BUDGET_DESKTOP` / `BUDGET_WEB` in units: about 600 on desktop and 300 on the web to start (S4's estimate), set from the sweep. The director spawns while the alive cost plus the next enemy's cost fits; a draw that does not fit waits (deferred, never dropped; the weights stay as written).
- **The curve.** Its late points move to mostly swarmers (staff enemies as the spice, not the bulk), so 500+ bodies stand at once on desktop. The curve's numbers stay a first guess, tuned by playing.
- **HUD.** `horde_status`'s `alive` stays the head count; nothing new on screen.
- **Tests:** a full actor and N swarmers fill the budget the same; a draw that does not fit waits and comes later; the web budget is used on the web; the curve reaches 500+ heads on desktop at its last point.
- **Done when:** the late horde stands at 500+ on desktop with the frame p95 under 16.7 ms in the sweep at the curve's late mix, and the web budget costs no more than the web cap of 150 heads does today.

### S7: 1,000 swarmers at 60 FPS on desktop

Today a step's scripts take 14 ms at 1,000; 60 FPS needs about 10-12 (process and the engine come on top). From S4's list, biggest first:

1. **Feel's per-hit juice (about 2 ms a step).** A hit sound starts once per sound per step (not once per hit), and Feel reads the camera once a frame, not per hit. The same sounds and effects show; a test that 200 hits in one step start one sound each and every effect.
2. **The projectile manager's target refresh (0.7 ms at 1,000).** A body owner that keeps positions in packed rows (the swarm) hands them over in bulk, and the manager skips the node reads for those targets. S5 measured a bulk push as a small win then; measure again now that the rest is cheaper, keep it only if it wins.
3. **Spikes (single steps of 25-55 ms, the p95).** Profile the bots' heavy casts (`--profile --profile-signals`): which card's work lands in one step. Spread it over steps (deferral, as the fire budget does), never drop it.
4. **Hit events in packed crowds.** A reaction or burst striking dozens of swarmers costs about 2.6 ms: look at what each strike's listeners do per body (Combat, Feel, the swarm) and batch what can be batched.
5. **The actor table.** 1,000 swarmers plus the full actors and wizards is past 1,020: grow `Actors.ACTORS` to 2,048 and the spell tag's caster to 11 bits (`FLAG` to bit 25), as H1 did for 1,024.
6. **Then** spacing (1.25 ms) and the look (1.2 us a row) are near what GDScript does; if still short, halve spacing's work again (a quarter of the rows a step at four times the push) and measure that it looks the same.

- **Done when:** `--horde-swarm` at 1,000 swarmers + 16 staff enemies holds a frame average under 16.7 ms and a p95 under 25 ms on desktop headless, over two runs; the web-size scenario does not get slower. Then S6's desktop budget is raised to what the sweep holds.

## Owner answers (2026-10-31)

1. A simpler look is not fine: swarmers look exactly like full enemies.
2. Aim higher than 600 desktop / 300 web; the measurement decides.

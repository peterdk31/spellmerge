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

## Owner answers (2026-10-31)

1. A simpler look is not fine: swarmers look exactly like full enemies.
2. Aim higher than 600 desktop / 300 web; the measurement decides.

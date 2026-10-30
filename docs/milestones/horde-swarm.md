# Horde swarm: 500+ enemies at 60 FPS (draft, for the owner)

Part of [horde.md](horde.md). H1 measured that the horde cannot go past about 200–250 enemies on desktop (80–100 on web) at 60 FPS while every enemy is a full actor: at 600 one physics step costs about 31 ms against 16.7 allowed. This document proposes **the swarm**, a cheaper body for the horde's touch-only enemies, so the horde reaches 500+. It changes nothing for wizards, staff enemies or any other mode, and it lives with the horde, so it is removed with it.

## Where the time goes (H1, 600 enemies, one physics step)

| Part | ms | Per enemy | What the swarm does with it |
|---|---|---|---|
| Looks (`CreatureLook`, `Face`) | 6.5 | a node tree and scripts drawing | **gone:** one MultiMesh draws every swarmer |
| AI `think` | 6.0 | a controller each | **gone:** one shared chase step |
| Mover and `move_and_slide` | 3.2 | a physics body each | **gone:** one step moves every swarmer, walls as the arena's rect plus a coarse grid, spacing by a spatial hash |
| Projectile target grid | 5.0 | a hurt circle each | stays (every swarmer can still be hit by everything); a later pass can make it cheaper |
| Combat | 1.7 | a row each | stays as it is |
| Spells and the rest | ~8 | | unchanged |

Expected at 600: about 12–15 ms per step on desktop. Web runs scripts about two to three times slower, so web's realistic swarm is about 250–300. Both are estimates; the stress run decides (S4).

## The idea: a light node per swarmer, everything else in rows

Every rule in the game finds a body by its node: shots hit target nodes, `strike` and `nearest_target` return nodes, `enemy_died` carries the node, statuses and knockback are Combat rows found by node or id. Taking the node away would mean rewriting the hit pipeline in core. So a swarmer **keeps one bare `Node2D`**: no children, no script, never drawn. Nothing else is per swarmer.

- **Combat:** each swarmer is registered as a **plain body** (Combat's `BODY_PLAIN`, which exists for bodies without the actor kit): health, hurt circle, touch damage and team in Combat's rows; it opens the actor id. So every hit, status, reaction, shock jump, static, hex, pull, barrier and touch rule applies to a swarmer exactly as to any actor (the rules pass: one rule, no special cases).
- **The swarm** (`gameplay/horde/swarm.gd`, owned by the director): packed arrays by swarm row: node, actor id, kind, velocity, target, flash time, animation phase. One `step(delta)` for all: chase the nearest wizard (target grid query staggered as the AI does), times `Combat.pace` (chill and freeze), plus `consume_knockback`, spacing from a spatial hash so they do not stack, stopped by the arena's walls; then writes each node's `position`. Nothing is allocated per step.
- **The look:** one `MultiMeshInstance2D` per swarmer kind: per instance a transform and custom data (hit flash, facing, frame). Hit flash from `damage_dealt` (one bus listener for the whole swarm, row found by node in a dictionary). Statuses keep their look from Feel, which draws by node position as for any body.
- **Death:** Combat kills a plain body as any other (`enemy_died`, then frees the node); the swarm drops the row when the node leaves (row found by node; O(1) swap-remove).
- **Kinds:** `crypt_mite` and `bone_husk` get a `swarm: true` flag in their EnemyBase (or a small `SwarmKind` resource next to them): the director spawns a kind with that flag into the swarm, and everything else as a full actor, as now.

## Where a rule needs a full actor: promotion

Some cards act on what only a full actor has: `possess` takes over a body's controller. The rule "no silent no-ops" holds by **promotion**: when a swarmer hears something that needs the actor kit (today only `possess_requested` for its id), the swarm replaces it in the same step by the full actor scene of its kind, at its place, with its health, statuses and knockback carried over (same Combat row moved, or re-registered with the same numbers), and that actor takes the request. A promoted swarmer stays a full actor. The card-rules test gets a case: every card played on a swarmer does what it does on a full actor of the same kind.

## Parts

| # | Part | Paths | Delivers |
|---|---|---|---|
| S1 | **The swarm step** | `gameplay/horde/swarm.gd`, tests | Rows, chase, pace, knockback, spacing, walls, plain-body registration, death clean-up |
| S2 | **The swarm look** | `gameplay/horde/swarm_look.gd`, the swarmers' art | MultiMesh per kind, hit flash, facing, a two-frame walk in the art |
| S3 | **Promotion** | `gameplay/horde/` | Possess (and any later actor-only rule) promotes a swarmer; card-rules case |
| S4 | **Scale and caps** | `tests/benchmark/`, the curve | The horde stress scenarios on the swarm; the caps raised to what holds 60 FPS (target 600 desktop, 300 web) |
| S5 | *(if S4 asks)* **Cheaper targets** | `core/projectiles` | The target grid's per-target cost |

S1 and S2 can be built in parallel (S2 reads the rows S1 defines); S3 after S1; S4 last.

## Questions for the owner

1. Is a swarmer that looks simpler than a full enemy fine (no separate face, a two-frame walk in its sprite)?
2. Web target: is about 300 on web acceptable, with 600 on desktop?

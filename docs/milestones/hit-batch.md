# Hit batch and the room grid: two refactors after the performance pass

**Status: proposed on 2026-11-17, waiting for the owner.** Asked by the owner on 2026-11-17 ("Consider if a refactor is worth doing. Maybe something is much too cluttered now. Can we think of a better architecture?"), after the performance pass of 2026-11-16 and 2026-11-17 (docs/DECISIONS.md, the entries of those days). Two parts, each its own PRs: **A, the hit batch** (one hit model, out of the projectile manager) and **B, the room grid** (walls, holes and footprints as a core service of their own). Neither changes what a player sees or how a hit lands beyond what the merged hits already do; both make the code smaller where today's bugs came from. The decisions they need are at the end ("For the owner").

## Why

Facts from the branch of the performance pass (2026-11-17):

- **The hit path has two modes.** The merged hits (`ProjectileManager.merge_hits`) were added on top of a model where every hit sends its events at once and the listeners change the world in the middle of the pass. Making that model batch took the hit-work budget, the merge table, spent shots ended at the pass's end (`F_SPENT`, `_end_spent`), slots held until their hits are sent (`_mh_freed`, `_take_back_slot`), the health ask (`hit_room_asked`) and the native fast path (`HitPass::merge_hits`). The merge's state is named 162 times in `projectile_manager.gd` and reaches 15 of its functions, `_kill`, `_expire`, `_spawn_row`, `_drop_one` and `_caster_position` among them.
- **Most of the reviews' findings were there.** Of the defects the reviews of that day found, about fifteen were in that machinery (the free list at the cap, an end before its hit, the count leaking into nested hits, relay profiles, barriers, invincible bodies, a clear mid-send). A design that needs that many guards is fighting its own model.
- **Two modes, two sets of tests.** The game merges; the recordings (`test_projectiles_step_exact.gd`, `test_projectiles_targets.gd`) and the tests of the hits one by one run unmerged (`merges_hits`, a test switch). So part of the suite tests a mode the game no longer plays.
- **The health ask is a hand-back.** The first hit of a spell on a body each pass goes back to GDScript to ask Combat (`hit_room_asked`): about 84 of the 169 hand-backs a tick in the desktop stress run. The rest are the shots' ends, which send events and stay GDScript.
- **The projectile manager is 7,519 lines and 340 members**, mirrored by a 2,429-line kernel. One part of it is not about shots at all: the grid of walls, holes and footprints that bodies slide on (`slide_body`), the AI looks through (`line_clear`, `ground_clear`, `walk_clear`, `clear_run`), items and Flow place things on (`nearest_ground`, `circle_blocked`), and Feel and the casters clip to (`clip_to_walls`, 19 callers outside the manager). Every one of those areas depends on the projectile manager to see a wall.

## Goals

- **One hit model:** a pass's shot hits are found, each shot is spent, pierces and ends as it hits, and the hits go out merged after the pass. No mode, no switch, no second path.
- **The batch is one class.** Everything the merge keeps between a hit and its event lives in `HitBatch` (`core/projectiles/hit_batch.gd`), not in the manager's members, and the manager tells it only "shot S hit target T at point P".
- **No hand-back for a hit the kernel can resolve:** what decides whether a body is dead in the pass (health, barrier charges, a hit's damage) is handed to the batch before the pass, so the native hit pass resolves every hit but those of shots alone (relays) and hands back only ends, walls and sticks.
- **The grid of the room is its own core service**, read by shots, bodies, the AI, items and Flow alike, with the same answers to the bit.
- **The native contract holds** (native/README.md): every kernel method has its GDScript twin, compared byte for byte; the editor runs without the module.
- **The determinism rules hold** (T1-T5, docs/milestones/shot-scale.md, "Determinism"; core/sim/README.md).

## Not goals

- No gameplay change beyond today's merged hits. The game already merges; A removes the unmerged mode. What a player sees and what a hit deals is today's merged game's, checked by the damage hashes.
- The other prototypes of 2026-11-17 (the staggered think, looks once a drawn frame) are not part of this plan; keeping or dropping them is a decision of its own (DECISIONS, 2026-11-17).
- Not the body table (hot per-body data in packed arrays, for an enemy step kernel): it is larger, touches most of `gameplay/`, and waits for real-hardware numbers (below, "Later").

## A: the hit batch

### The model

A pass's hits in three phases, each over the whole pass, in slot order:

1. **Find** (the hit pass, GDScript or the kernel): each shot flies its path, meets walls and ends as today, and for each body its path meets (`_cand_*`, nearest first) asks the batch whether the body still takes a hit (`HitBatch.takes(target)`: not dead in this pass). If it does, the shot is spent or pierces and the hit is counted (`HitBatch.add(slot, target, at, heading)`). A spent shot is marked and handed to the batch.
2. **End** (GDScript): the batch ends its spent shots in the order they were spent (their tails where they were spent), their slots held for their hits.
3. **Send** (GDScript): one `projectile_impact` and one `projectile_hit` for each caster, body and spell (a shot alone: its own), in the order of their first hits, with `impact_count`; then the slots freed and the ends sent (`shot_ended`).

Nothing a listener does reaches the pass's own hits: phase 1 sends no event of a hit. Events of the shots' ends and walls (`projectile_expired`, `wall_met`, a wall's `projectile_impact`) still go out during phase 1, as today; their handlers can spawn, block or remove shots, which the batch already guards (held slots, the take-back at the cap, a spent shot a handler ended).

### What moves where

- **Into `HitBatch` (RefCounted, owned by the manager, DERIVED: emptied within a step):** the merge table by target (`_mh_head`, `_mh_next`, and each entry's caster, tag, slot, sequence, point, heading, count, look), the per-target tallies (health, damage counted, charges and charges used), the spent shots (`_mh_used`), the held slots (`_mh_freed`), the ends kept (`_mh_ended`), and the functions that read them (`_merge_hit`, `_spend_room`, `_killed_this_pass`, `_end_spent`, `_take_back_slot`, `_send_merged`). About 30 members and 400 lines leave the manager.
- **Stays in the manager:** the shots (their arrays, the pool, the free list), the hit test, the passes, `_kill` and `_expire`. `_kill` asks the batch whether to hold a slot (`HitBatch.hold(slot)`), the one place the manager knows a batch exists besides `_pass_hits`.
- **Gone:** `merge_hits`, `merges_hits` (the switches), the unmerged branches of `_register_hit`, `_kill`, `_expire`, `_hit_slot`, `_hit_candidates` and `_test_deferred`, and `_merging` (the batch is open for the pass, and only the pass adds to it).

### The rooms, asked once a pass

Today Combat answers `hit_room_asked` at the first hit of each spell on each body. A hit's damage depends on the spell (its profile, the caster's power) and the body (a hex adds to it; a Barrier card spares one spell), so the answer splits in two, both asked before or outside the hit pass:

- **The bodies' rooms, once a pass** (`hit_rooms_asked(rooms: HitRooms)`, Combat's): for every target of the pass, by the manager's target index, the health left, whether hits take any (an invincible body never dies by them), the barrier's charges and the spell it spares, and the hex's extra share. Packed arrays the batch holds and the kernel reads. A body Combat does not know keeps an unknown room (INF), as today.
- **A spell's damage, once a pass per spell** (`hit_damage_asked(caster, tag, shot, answer)`): one hit's damage before the body's share, at the first hit of that spell in the pass (the `shot` for a profile of its own: a shot alone asks for itself). The kernel hands back that first hit only; every hit after it, on any body, is the kernel's.
- **Then a hit counts** `damage × (1 + hex share)` off the body's health, or one charge when the spell meets its barrier, as `_spend_room` does today.

Cost to check in A2: filling the rooms for every target once a pass is about one call a target (200 in the desktop stress run); today's asks are about 84 hand-backs a tick at about 10 us each. If filling every target costs more than it saves, the rooms are filled at a body's first hit instead (one hand-back a body a pass, not one a spell and body).

### Native

The kernel's fast path (`HitPass::merge_hits`) grows to the whole of phase 1 for a shot: it adds a new entry to the batch (no ask: the rooms and the spell's damage are there), counts the damage with the body's hex share, and spends charges. It hands back a shot only for its end, a wall, a stick, a shot alone, a spell's first hit of the pass (its damage) and a hit memory that must grow. It reads the batch's arrays from the batch (`HitBatch`, handed by the manager), with its own field table (`BATCH_FIELDS`, checked by `check_fields` as `MANAGER_FIELDS` is).

### The recordings

`test_projectiles_step_exact.gd` and `test_projectiles_targets.gd` hold the shots to recordings made one by one. With one model they are recorded again, once, on the reference GDScript of the merged model at the commit before A3 (their own rule: never from the code under test), and the PR lists every changed trace with its reason. What they guard (the passes' order, the grid's answers) is unchanged.

### Parts

| # | Part | Delivers |
|---|---|---|
| A1 | **`HitBatch`, extracted** | The merge's members and functions move into the class; the manager calls it. Byte for byte the same (the native side-by-side test, the merged tests, every recording as today). The unmerged mode is still there. |
| A2 | **The rooms once a pass** | `hit_rooms_asked` and `hit_damage_asked` replace `hit_room_asked`; Combat answers both. The same hits, damage and order as A1 (the stress run's and shot scale's damage hashes, `test_merged_hits.gd`). Measured: the hand-backs a tick and the tick. |
| A3 | **One model** | The unmerged mode, its branches and the switches are gone; the two recordings recorded again (owner's word, Q2); the tests of the hits one by one become tests of the merged model where they test something it keeps, and go where they test the unmerged order. |
| A4 | **The kernel takes new hits** | The native fast path adds entries itself; the side-by-side test steps its scene with spells hitting many bodies and shots alone; a mutated line fails it. Measured: hand-backs a tick (expected: about the ends alone, 85 of 169 at the desktop stress run) and the tick. |

## B: the room grid

### What moves

The grid of the room's cells (`WALL_CELL`, 8 px): the room's walls (`set_walls`, `add_wall_body`, `clear_walls`), its holes (`set_holes`, `add_hole_body`, `set_holes_outside`, `is_hole`, `touches_hole`, `has_holes`), the bodies' footprints (`set_footprint`, `footprint_of`), the solid shots' stones (the Wall card's, marked by the manager), and the queries (`clip_to_walls`, `line_clear`, `ground_clear`, `walk_clear`, `clear_run`, `circle_blocked`, `nearest_ground`, `slide_body`, `wall_image`, and the manager's own `_wall_hit` and `_way_hit`).

### Where to

A core service of its own, `core/room_grid/` (`RoomGrid`), made by the projectile manager and handed to who asks (`Projectiles.grid()`) in B1, an autoload of its own in B2 (Q4). Its state (holes, footprints, the solid stones) is state as today, walked and restored by the snapshot under its own name; the cells worked out from the room are DERIVED and set up again in `rebuild_derived`. Shots mark their stones through it (`mark_solid`, `lift_solid`). The kernels read its arrays from it: `ShotKernel` (the hit pass's walls) with a field table of its own, `BodyKernel` as today (handed the arrays).

### Parts

| # | Part | Delivers |
|---|---|---|
| B1 | **`RoomGrid`, extracted** | The cells, walls, holes, footprints and queries move into the class; the manager keeps one-line forwards, so no caller changes. Byte for byte the same (every test as it is, the native side-by-side tests with the kernel reading the grid). |
| B2 | **The callers ask the grid** | Bodies, the AI, items, Flow and Feel ask the room grid, not the manager (about 70 call sites outside the manager, tests included); the forwards go. An autoload (`RoomGrid`) if the owner agrees (Q4); else the manager's `grid()`. |

## Order

B1 first (it is mechanical and changes no result), then A1, A2, A3, A4, then B2. Each part is one PR, measured before and after with the stress run's tick parts and the shot scale crowd, with an independent review. A1 and B1 can be reviewed side by side: neither changes a result, and the tests say so.

## Tests

- **Same results, where nothing should change** (A1, B1, B2, A2): the full suite, the native side-by-side tests merged on one and four threads, `test_merged_hits.gd`, the determinism and snapshot suites, and the damage hashes of the stress run and shot scale (`DAMAGE:`), compared before and after.
- **A2:** a body hit by two spells, one hexed and one barriered, counted dead by the rooms as by today's asks; an invincible body never dead; a body a handler adds during the pass (no room: unknown).
- **A3:** the recordings recorded again with their reasons; every test of the hits one by one kept as a merged test or removed with its reason in the PR.
- **A4:** the side-by-side scene with spells hitting many bodies, hexed and barriered bodies and shots alone, so every new branch runs; a mutated line of the C++ fails it.
- **B1:** a test that every query of the grid answers as the manager did, over the rooms of `test_wall_slide.gd`.

## Numbers to beat

The desktop stress run after the performance pass (2026-11-17, the cloud machine): a tick of about 16.8 ms, of it the projectile manager about 7 ms and 169 hand-backs a tick. A4 is expected to bring the hand-backs to about the ends and the tick down by about 1 ms; A1, A3, B1 and B2 by nothing (they are cleaner code, not faster). Each PR prints its numbers; a part that is slower by more than the machine's noise (about 15%) is looked at before it merges.

## For the owner

- **Q1: one hit model.** The game would only merge hits, as it does now; the unmerged mode goes. This finally replaces the decision of 2026-11-07 against bundled hits (DECISIONS), already reversed in practice by the prototype of 2026-11-17. If the owner wants hits one by one back instead, A is not done and the merge is removed.
- **Q2: the recordings.** May the two recordings be recorded again once, on the merged model's reference GDScript before A3?
- **Q3: the prototypes.** The staggered think and the looks once a drawn frame are separate from this plan: keep, change or drop each.
- **Q4: an autoload for the room grid**, or keep it reached through the projectile manager?

## Later

- **The body table** (hot per-body data in packed arrays in `core/actors`, a field at a time, aim and position first), which makes an enemy step kernel and the AI's perception in one batch clean (about 3 to 4 ms a tick at the desktop stress run, estimated). Only if real-hardware numbers (the Web Test export's `--stress` and `--storm` in a browser, the desktop build on the target PC) show the frame still needs it.
- **30 ticks a second**, the largest single lever, only if the budget is still missed.

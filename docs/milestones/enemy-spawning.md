# Enemy spawning: a room's enemies come in groups, and each one is seen coming

**Status (2026-11-17): EA1–EA5 done (every non-boss enemy spawns in, a mark, then the body rising out of it; a room's enemies come in groups by cost as the room gets quiet, at the crypt's starting numbers). EA6, tuning the numbers in the owner's playtest, is to come. The owner answered its four questions (the end of this document).** The owner asked: "A room should not spawn every enemy at once. And we need an animation when an enemy spawns in."

This changes one line of decision 30 (docs/milestones/boss-old-broom.md: "A room starts with its enemies standing"). The rest of decision 30 stays: there are still no waves. A room still holds a fixed list of enemies that the run's map picks, and it is cleared when the last of them is down. The only change is that they come in over the fight instead of all standing at the start. Nothing grows, and nothing comes after the list is used up.

## Why

- **Readable chaos (pillar 4).** With `room_budget = 16` in the crypt (content/runs/crypt.tres, then scaled up by depth and players), a deep room can have a dozen bodies standing at its spawns in the first frame. Groups keep the number on screen readable, and the spawn look gives each new body a short warning before it can act.
- **Smooth (docs/STYLE.md, "Smooth").** Today an enemy pops in, which the Smooth rule doesn't allow: "nothing on screen changes its look in one jump". Its spawn plays frames (at least 3 a stage, by whole pixels, with no fade).
- **Nobody waits (pillar 2).** The next group comes as soon as the room gets quiet (the owner, 2026-11-17: only then, no timer). A party that fights slowly isn't punished by a flood, and a fast party never stands in an empty room waiting: the next group is already rising as the last bodies fall.

## How it plays

1. The room starts. The run's map has already picked its enemies (`run_room_chosen`, in the fill's order, which comes from the run's seed). Flow splits them into **groups**. The first group starts spawning while the room is being built, in the same tick the room starts, together with the room's start cue.
2. **A spawn** (about 0.8 s, `SPAWN_SECONDS`): first a mark grows on the floor where the body will stand. Then the body comes up out of the floor. While it spawns in it is *not there yet*:
   - it can't be hurt, targeted or possessed;
   - it neither touches nor is touched;
   - it doesn't think, move, cast or step its phases;
   - spells pass through it.

   It does count as one of the room's enemies, so the room can't be cleared while it is spawning.
3. **The next group** starts spawning when the cost of the enemies still standing (or spawning) drops to `refill_at` or below. There is no timer (the owner, 2026-11-17).

   A group takes enemies from the front of the list until its cost reaches `group`. It always takes at least one enemy, so an enemy that costs more than a group still comes. This also caps the floor: at most `refill_at + group` of cost stands at once (plus one enemy past the group's cost), so no separate cap is needed.
4. **Where:** at the room's enemy spawns, as now (`stacked_position`), but a group uses the spawns **farthest from every standing wizard** first. A body never starts spawning on top of a player (as built: no spawn within 64 px of a standing wizard is used, unless every spawn is that near, when the farthest alone is). If a wizard walks onto the mark, the body still lands there, and the mark is the warning (contact damage starts only once it has landed).
5. **Cleared:** when the list is used up and nothing is standing or spawning. The exits light as today.

**Scaling** uses the measure the run already has: the spawn numbers are **shares of the room's scaled budget** (`RunScaling.scaled_budget`, which is a multiplication by the room's scale from depth and players). A bigger party therefore gets bigger groups in the same proportion as its bigger room, with no extra per-player fields.

### What doesn't change

- **A boss stands at once and doesn't spawn in.** Any body whose data is a boss (`EnemyBase.FOLDERS`' boss folder) skips both the queue and the spawn. It is stood in the room's setup as now, so the boss intro (`_open_boss_intro`, docs/milestones/boss-intro.md) opens on a body that is there and drawn. Its **phase adds** (`EnemyAdds`, `RoomAdds`) keep the timing the phases give them, but each add plays the spawn look (question 3).
- **The hub's placements** (dummies, props: `RoomContents`) stand as laid. They aren't enemies of a fight.
- **Mid-run joiners** are placed as now (`_joiner_spawn`, away from the enemies standing).
- **Difficulty** is still told about each body before it is added to the tree (`enemy_standing`), so scaling doesn't change. It is told when the body starts spawning.

## The design in code

Three pieces, one area each. They talk through `core/` events and the actor's state, never by calling each other.

### 1. The data and how it reaches Flow (core/base, gameplay/run)

- `core/base/spawn_rules.gd`, a `Resource`. A biome's `MapRules` gets a `spawning: SpawnRules` field, so each biome of a run sets its own pace in content/runs/*.tres. If it is null, the whole list spawns in at once (with the look), which is today's pace without the pop.

  | Field | Starting value | Meaning |
  | --- | --- | --- |
  | `group_share` | 0.35 | the cost of one group, as a share of the room's scaled budget |
  | `refill_share` | 0.15 | the cost still standing that calls the next group, as a share of the room's scaled budget |
  | `stagger` | 0.15 s | the time between two bodies of one group starting to spawn in, so a group ripples in instead of all popping at once |

  It has `problems()`, as `EnemyAdds` does: shares outside 0 to 1, a non-finite or negative `stagger`, or a refill share not below the group share. The run definition's validator reports them (RG1's validators).
- **The run hands Flow plain numbers**, not the Resource. A new event, `run_room_paced(group: int, refill_at: int, stagger: float)` (core/events), is sent by the run just before `run_room_chosen`, the same way `run_room_scaled` already is. The run works out `group` and `refill_at` in cost from the shares and the room's scaled budget. Flow keeps them as its own numbers. Nothing in Flow reads the run's map, and no sub-resource sits in state. As built (EA4): the generator works each room's numbers out as it fills the room, where it already has the scaled budget (`RunGenerator._pace`), and keeps them on the room's map node (`RunNode.group`, `refill_at`, `stagger`, plain state like its `scale`); the run sends them as the party enters the room, after `run_room_scaled`. The costs are `SpawnRules.group_cost(budget)` (rounded, 1 at least) and `refill_cost(budget)` (rounded, and clamped below the group's cost, so rounding in a small room can never make a group call the next at once). With no spawns all three are 0, which Flow reads as the whole list at once.

### 2. The simulation: spawning is a state of the actor (gameplay/actor)

This works like a fall (hub rework HR-H2), which already has the same shape: a timer that is state, `is_down()` while it runs, and Feel drawing it from the state. A spawn, though, holds the body still, which a fall doesn't.

- `Actor.spawn_left: float` (state), set by `Actor.spawn(seconds)`. Flow calls it **inside `_stand_enemy`, before `add_child`**, so the Hurtbox never registers the body, or its contact damage, on its first tick (`Hurtbox.attach`).
- `is_spawning()` and `spawn_share()` (0 to 1, for the look).
- `is_down()` is also true while it spawns in. Combat's hits, the AI's targets (`brain.gd`) and possession (`Possession.can_start`) already ask `is_down()`. The other half of touching is checked explicitly: in `Actor._touch`, a body neither tells nor is told `touched` while either of them is spawning.
- In `step`, while `spawn_left > 0`:
  - the timer counts down, and the Hurtbox follows `is_down()` as it does every step, so it is unregistered throughout and registers on the tick the spawn ends;
  - then it returns before phases, possession, the controller, the caster and the mover (`intent.clear()`, `velocity` zero; its looks still step).
  - The tick its timer runs out it steps as a standing body: its controller thinks and its hurt shape registers in that same step (as built, EA1).

  `tick_step` skips `move()` while spawning, so there is no slide and no ground check, and a spawn can't turn into a fall. A spawn over a hole is already a room problem (`RoomContents._check_ground` reports one for placements; the spawn spawn pick skips a spawn whose circle touches a hole, `ProjectileManager.touches_hole`, as the adds' ring does).
- No `enemy_spawned` event until something needs one. The state hash and snapshots cover the new state member already (an enemy has a controller, so it is never "at rest" and is always hashed in full).

This stays on `Actor` instead of becoming a component so that it sits right next to the fall it mirrors, and because `is_down()` is the one question every system already asks. A component would need the same hooks in `Actor` anyway.

### 3. Pacing: `RoomSpawning` (gameplay/flow, new)

`gameplay/flow/room_spawning.gd`, a `RefCounted` that Flow holds, like `RoomAdds`. Flow is already 1,500 lines, so the rules live here and Flow only calls them. It is pure rules with no nodes, so it is tested without a world.

- **State** (all saved in snapshots):
  - `waiting: Array[StringName]`: the ids not yet called, with their costs;
  - `group`, `refill_at`, `stagger`: the numbers from `run_room_paced`;
  - `stagger_left`, `group_left`: the time to the group's next body, and the bodies of the current group still to start;
  - `placed: int`, `order`: as built, the spawn counter is the current group's (reset as each group starts), and `order` the spawns in the order the group takes them.
- `begin(ids, costs, ...)`; `next(delta, standing_cost) -> StringName` (the next id to stand this tick, or `&""`); `is_done()`; `left()`; `take_all()` (for `stand_all_now`); `clear()`.
- As built, the plan's `pick_spawn` is two parts: `static rank(spawns, wizards, touches_hole) -> PackedInt32Array`, the spawns farthest from every wizard first, ties broken by index, those over a hole left out (unless every one is), and `spawn_for(spawns, wizards, touches_hole, stack)`, which ranks them as a group's first body is placed and gives each body of the group the next in turn, stacked (`stacked_position`) where one is used again within the group. Ranking once a group keeps the bodies of one group off each other's spawn as the wizards move during its ripple. A spawn within `RoomSpawning.NEAR` (64 px) of a standing wizard is left out too (unless every one is: then the farthest alone), so a group bigger than the far spawns stacks on them rather than spilling onto the spawns by the party (a deep four-player room's group of about 11 crypt mites over arena_01's 6 spawns). Each stacked spot is moved to the nearest clear ground (`ProjectileManager.nearest_ground`), so a deep stack never stands in a wall or over a hole's edge. A boss is stood at the spawns in turn as before, and the ranking does not know it: no room holds both a boss and a queue today (a boss room's fill is its boss alone); one that does would want the boss's spawn left out. Places only, so it gives the same answer on every machine.

In Flow:

- `_stand_room_enemies` stands the bosses at once (as today, it does not spawn in). It hands the rest to `spawn_queue.begin(...)` and calls `spawning.next(0, ...)` until it returns `&""`, so the first group starts in the room's setup, before `_open_boss_intro` and `_check_room_won`. As built: the first group's bodies are stood just after the room's walls and holes reach the projectile manager (`_set_walls`, then `_call_spawning(0)`), still in the room's setup and the same tick, because the spawn pick's hole check needs the room's own holes, which used to be laid after the enemies stood.
- `step` calls `spawning.next(delta, _standing_cost())` each tick and stands what it returns with `_stand_enemy(..., spawn_in = true)`. `_standing_cost()` is the cost of every one of the room's enemies standing or spawning, a phase's adds too. **Then it calls `_check_room_won()` every tick the queue is open.** An id that fails to stand (no data for it in the registry, or no spawns) is dropped from the queue, so a room can't get stuck uncleared.
- `_check_room_won` also requires `spawning.is_done()`.
- `_on_adds_requested` stands adds with `spawn_in = true` (unless question 3 says otherwise).
- `_forget_enemies` calls `spawn_queue.clear()`. The `spawn_queue` member is Flow's state, not `DERIVED`.
- `enemies_left()` counts the queue too, so callers keep its meaning: enemies still to beat.
- `stand_all_now()` (for tests) calls the rest of the queue at once; the shared helper's `Spawning.land(flow)` calls it before landing the bodies.

### 4. The look: `SpawnLook` (gameplay/feel, new)

`gameplay/feel/spawn_look.gd`, `VIEW_ONLY`. Each frame Feel steps it over the open bodies, and it draws each spawning body from `spawn_share()` alone, so a machine that joins mid-spawn, or a restored snapshot, shows it at the right point. It follows the way `FallLook` is driven, not the way it is drawn: `FallLook` scales and fades, which the Smooth rule doesn't allow here.

- **0 to 0.4, the mark:** a ring on the floor at the body's footprint, in the room's floor colours (`RoomBase.floor_colors()`, the shadow colour darkened so it reads as a hole, with the light one as a rim; half as high as wide, since it lies on the floor), drawn in 4 frames from a dot to the footprint's width. This is the warning players read.
- **0.4 to 1, the rise:** the body comes up out of the mark. It is drawn shifted down by whole pixels, from its full height to 0 over at least 5 frames (snapped), and cut off at the mark's line. As built (EA2): the body's own root is the clip parent (`CanvasItem.clip_children`), its canvas item drawing one rect above the feet's line as the mask, and each of its direct drawn children is drawn shifted (`RenderingServer.canvas_item_set_transform`, each frame); no node is added round the parts. The root itself is never moved: a shifted root would be y-sorted as if its feet were lower and draw over a wizard standing just in front of the mark (the review caught it; checked on screen). That makes it one clip for any body, layered (`BodyPart`) or not, with no per-part work. Dust motes come off the mark through the cue's motes part, within their limits. The cut is made just before each frame is drawn (`RenderingServer.frame_pre_draw`), so a body added after Feel's step is never drawn whole for a frame, and its line is the art's lowest row (a frame may reach a pixel or two under the feet), so nothing appears in one jump at the landing. The mark closes in its last 3 frames (from 0.92; 3, not 2, for the Smooth rule's 3 frames a stage) as the feet land, so the rise ends where standing begins (Smooth, "Stages hand over").
- No fade and no blur. The body keeps its own sprite and pose the whole time.
- A sound cue `enemy_spawn` (soft, played no more than every 0.1 s, so a group doesn't stack it), through the existing cue plan. As built: the cue (content/cues/enemy_spawn.tres) holds the dust motes too and plays for every body as its rise starts; between two sounds it is played unweighted (dust only).
- **Risk, checked first in EA2:** the clip has to work with the body's draw order in the world (y-sort) and the room's light pass. If a clip parent breaks y-sort, the fallback is a per-sprite `region_rect` cut, done in the look (each sprite's own rows, still whole pixels). Checked on a virtual display with the game's renderer (compatibility): a clipped body whose parts are shifted keeps its place among y-sorted siblings (behind one standing just in front of it), and a screen-reading pass drawn over the world (the light pass's way) shades it like any body, so the fallback was not needed.

Later, an enemy could pick its own look (`EnemyBase.spawn_style`, for example an imp that drops in from above). That is out of scope here: v1 has one look for every enemy.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| EA1 | **Spawning as a state:** `Actor.spawn`, `spawn_left`, `is_spawning`, `spawn_share`, `is_down` while spawning, the step and the move held, touches both ways. Tests: can't be hurt, targeted, touched or possessed; doesn't think, cast, move or call its phases' adds; contact damage only after landing; ends on time; snapshot mid-spawn; determinism | gameplay/actor, tests |
| EA2 | **The look:** `SpawnLook` in Feel (the y-sort and light check first), the mark and the rise, motes, the cue. Tests: at least 3 frames per stage, whole pixels, drawn from state alone (a restored snapshot mid-spawn), nothing allocated per frame | gameplay/feel, audio, tests |
| EA3 | **Every non-boss enemy spawns in:** `_stand_enemy(..., spawn_in)`, room enemies and adds spawn in (still all at once), bosses don't. This removes the pop before the pacing lands. Tests: the boss stands at once and its intro opens (test_boss_intro_hold.gd); the flow tests step past the spawn (the shared helper `tests/support/spawning.gd`) | gameplay/flow, tests |
| EA4 | **The rules:** `SpawnRules`, `MapRules.spawning`, `problems()` and the run validator, `run_room_paced` sent by the run, the crypt's numbers | core/base, core/events, gameplay/run, content/runs, tests |
| EA5 | **Groups:** `RoomSpawning`, Flow's queue, the far-spawn pick, room cleared only when the queue is empty, a failed id dropped. Tests: group sizes by cost and scale, the quiet trigger (and no group while the floor is busy, however long), an expensive enemy still comes, snapshot between groups and mid-spawn, cleared only at the end, never stuck | gameplay/flow, tests |
| EA6 | **Tune** in the owner's playtest: the numbers in content/runs/crypt.tres only | content/runs |

EA1 to EA3 can ship as one PR (the look, with no pacing change). EA4 and EA5 are a second PR.

**As built (EA4–EA5):** tests `tests/core/test_spawn_rules.gd` (the costs, every problem, the map rules reporting and copying them, the crypt's), `tests/gameplay/run/test_run.gd` (the pace told between the scale and the room, bigger for four players), `tests/gameplay/flow/test_room_spawning.gd` (the pure rules: group sizes by cost, an enemy dearer than a group, the quiet trigger and ten minutes of a busy room with no group, the stagger, a group waiting for the one before to start, a pace of 0, the far-spawn rank with holes and with spawns near a wizard), `tests/gameplay/flow/test_flow_spawning.gd` (on the real autoloads: the first group in the setup, no group in a busy room, cleared only after the last group, a dropped id, the far spawn as a wizard moves, a hole laid over the far spawn, `stand_all_now`) and `tests/core/test_snapshot_spawning.gd` (a paced arena snapshotted mid-spawn with groups to come (the group's ripple goes on in the restored game), and between groups (the restored queue keeps holding), resumed in a fresh game: every tick agrees; it fails when the queue is left out of state). A frame-time check on a virtual display (software GL, so only relative): with sixteen bodies spawning at once over the room's own, about 21 ms a frame against 16 ms once they landed; groups keep far fewer clipping at once than EA3's whole room. Each step updates the README of its area (gameplay/actor, gameplay/feel, gameplay/flow, gameplay/run, content/runs, core/events) and Flow's class doc.

## Tests that need a look

- `tests/gameplay/flow/test_flow*.gd`, `test_flow_adds.gd`, `tests/gameplay/run/test_run.gd`: these damage, kill or count enemies right after a room starts, and will hit bodies that are still spawning. They get a shared test helper that steps the world past `SPAWN_SECONDS` (and, after EA5, calls the rest of the queue: `Flow.stand_all_now()`, for tests only).
- `test_snapshot_game.gd` snapshots about 3 s into a pinned run that has no `SpawnRules`, so it covers neither mid-spawn nor between groups. EA1 and EA5 add their own snapshot tests for those moments, and `test_snapshot_game.gd` keeps checking that it still passes as it is.
- `test_content_determinism.gd` plays every enemy twice. It should pass as it is, because the spawn is deterministic state.
- The online bots (`tools/online_*.sh`) clear rooms by playing them. They only take longer.

## The owner's answers (2026-11-17)

1. **The pace:** only when the room gets quiet. No timer.
2. **Group size:** by cost, the measure the room's budget already uses.
3. **Boss adds:** they play the spawn too, so nothing pops in.
4. **The look:** a mark on the floor, then the body rising out of it.

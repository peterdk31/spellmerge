# Enemy arrivals: a room's enemies come in groups, and each one is seen coming

**Status (2026-11-17): a plan; the owner answered its four questions (the end of this document).** The owner asked: "A room should not spawn every enemy at once. And we need an animation when an enemy spawns in."

This changes one line of decision 30 (docs/milestones/boss-old-broom.md: "A room starts with its enemies standing"). The rest of decision 30 stays: there are still no waves. A room still holds a fixed list of enemies that the run's map picks, and it is cleared when the last of them is down. The only change is that they come in over the fight instead of all standing at the start. Nothing grows, and nothing comes after the list is used up.

## Why

- **Readable chaos (pillar 4).** With `room_budget = 16` in the crypt (content/runs/crypt.tres, then scaled up by depth and players), a deep room can have a dozen bodies standing at its spawns in the first frame. Groups keep the number on screen readable, and the arrival look gives each new body a short warning before it can act.
- **Smooth (docs/STYLE.md, "Smooth").** Today an enemy pops in, which the Smooth rule doesn't allow: "nothing on screen changes its look in one jump". Its arrival plays frames (at least 3 a stage, by whole pixels, with no fade).
- **Nobody waits (pillar 2).** The next group comes as soon as the room gets quiet (the owner, 2026-11-17: only then, no timer). A party that fights slowly isn't punished by a flood, and a fast party never stands in an empty room waiting: the next group is already rising as the last bodies fall.

## How it plays

1. The room starts. The run's map has already picked its enemies (`run_room_chosen`, in the fill's order, which comes from the run's seed). Flow splits them into **groups**. The first group starts arriving while the room is being built, in the same tick the room starts, together with the room's start cue.
2. **An arrival** (about 0.8 s, `ARRIVE_SECONDS`): first a mark grows on the floor where the body will stand. Then the body comes up out of the floor. While it arrives it is *not there yet*:
   - it can't be hurt, targeted or possessed;
   - it neither touches nor is touched;
   - it doesn't think, move, cast or step its phases;
   - spells pass through it.

   It does count as one of the room's enemies, so the room can't be cleared while it is arriving.
3. **The next group** starts arriving when the cost of the enemies still standing (or arriving) drops to `refill_at` or below. There is no timer (the owner, 2026-11-17).

   A group takes enemies from the front of the list until its cost reaches `group`. It always takes at least one enemy, so an enemy that costs more than a group still comes. This also caps the floor: at most `refill_at + group` of cost stands at once (plus one enemy past the group's cost), so no separate cap is needed.
4. **Where:** at the room's enemy spawns, as now (`stacked_position`), but a group uses the spawns **farthest from every standing wizard** first. A body never starts arriving on top of a player. If a wizard walks onto the mark, the body still lands there, and the mark is the warning (contact damage starts only once it has landed).
5. **Cleared:** when the list is used up and nothing is standing or arriving. The exits light as today.

**Scaling** uses the measure the run already has: the arrival numbers are **shares of the room's scaled budget** (`RunScaling.scaled_budget`, which is a multiplication by the room's scale from depth and players). A bigger party therefore gets bigger groups in the same proportion as its bigger room, with no extra per-player fields.

### What doesn't change

- **A boss stands at once and doesn't arrive.** Any body whose data is a boss (`EnemyBase.FOLDERS`' boss folder) skips both the queue and the arrival. It is stood in the room's setup as now, so the boss intro (`_open_boss_intro`, docs/milestones/boss-intro.md) opens on a body that is there and drawn. Its **phase adds** (`EnemyAdds`, `RoomAdds`) keep the timing the phases give them, but each add plays the arrival look (question 3).
- **The hub's placements** (dummies, props: `RoomContents`) stand as laid. They aren't enemies of a fight.
- **Mid-run joiners** are placed as now (`_joiner_spawn`, away from the enemies standing).
- **Difficulty** is still told about each body before it is added to the tree (`enemy_standing`), so scaling doesn't change. It is told when the body starts arriving.

## The design in code

Three pieces, one area each. They talk through `core/` events and the actor's state, never by calling each other.

### 1. The data and how it reaches Flow (core/base, gameplay/run)

- `core/base/arrival_rules.gd`, a `Resource`. A biome's `MapRules` gets an `arrivals: ArrivalRules` field, so each biome of a run sets its own pace in content/runs/*.tres. If it is null, the whole list arrives at once (with the look), which is today's pace without the pop.

  | Field | Starting value | Meaning |
  | --- | --- | --- |
  | `group_share` | 0.35 | the cost of one group, as a share of the room's scaled budget |
  | `refill_share` | 0.15 | the cost still standing that calls the next group, as a share of the room's scaled budget |
  | `stagger` | 0.15 s | the time between two bodies of one group starting to arrive, so a group ripples in instead of all popping at once |

  It has `problems()`, as `EnemyAdds` does: shares outside 0 to 1, a non-finite or negative `stagger`, or a refill share not below the group share. The run definition's validator reports them (RG1's validators).
- **The run hands Flow plain numbers**, not the Resource. A new event, `run_room_paced(group: int, refill_at: int, stagger: float)` (core/events), is sent by the run just before `run_room_chosen`, the same way `run_room_scaled` already is. The run works out `group` and `refill_at` in cost from the shares and the room's scaled budget. Flow keeps them as its own numbers. Nothing in Flow reads the run's map, and no sub-resource sits in state.

### 2. The simulation: arriving is a state of the actor (gameplay/actor)

This works like a fall (hub rework HR-H2), which already has the same shape: a timer that is state, `is_down()` while it runs, and Feel drawing it from the state. An arrival, though, holds the body still, which a fall doesn't.

- `Actor.arrive_left: float` (state), set by `Actor.arrive(seconds)`. Flow calls it **inside `_stand_enemy`, before `add_child`**, so the Hurtbox never registers the body, or its contact damage, on its first tick (`Hurtbox.attach`).
- `is_arriving()` and `arrive_share()` (0 to 1, for the look).
- `is_down()` is also true while it arrives. Combat's hits, the AI's targets (`brain.gd`) and possession (`Possession.can_start`) already ask `is_down()`. The other half of touching is checked explicitly: in `Actor._touch`, a body neither tells nor is told `touched` while either of them is arriving.
- In `step`, while `arrive_left > 0`:
  - the timer counts down, and the Hurtbox follows `is_down()` as it does every step, so it is unregistered throughout and registers on the tick the arrival ends;
  - then it returns before phases, possession, the controller, the caster and the mover (`intent.clear()`, `velocity` zero).

  `tick_step` skips `move()` while arriving, so there is no slide and no ground check, and an arrival can't turn into a fall. A spawn over a hole is already a room problem (`RoomContents._check_ground` reports one for placements; the arrival spawn pick skips a spawn whose circle touches a hole, `ProjectileManager.touches_hole`, as the adds' ring does).
- No `enemy_arrived` event until something needs one. The state hash and snapshots cover the new state member already (an enemy has a controller, so it is never "at rest" and is always hashed in full).

This stays on `Actor` instead of becoming a component so that it sits right next to the fall it mirrors, and because `is_down()` is the one question every system already asks. A component would need the same hooks in `Actor` anyway.

### 3. Pacing: `RoomArrivals` (gameplay/flow, new)

`gameplay/flow/room_arrivals.gd`, a `RefCounted` that Flow holds, like `RoomAdds`. Flow is already 1,500 lines, so the rules live here and Flow only calls them. It is pure rules with no nodes, so it is tested without a world.

- **State** (all saved in snapshots):
  - `waiting: Array[StringName]`: the ids not yet called, with their costs;
  - `group`, `refill_at`, `stagger`: the numbers from `run_room_paced`;
  - `stagger_left`, `group_left`: the time to the group's next body, and the bodies of the current group still to start;
  - `placed: int`: the spawn counter, which today is a local in `_stand_room_enemies`.
- `begin(ids, costs, ...)`; `next(delta, standing_cost) -> StringName` (the next id to stand this tick, or `&""`); `is_done()`; `clear()`.
- `static pick_spawn(spawns, wizards, placed, touches_hole) -> Vector2`: the spawn farthest from every wizard, ties broken by index, then `stacked_position` for a spawn used again. It uses state only, so it gives the same answer on every machine.

In Flow:

- `_stand_room_enemies` stands the bosses at once (as today, no arrival). It hands the rest to `arrivals.begin(...)` and calls `arrivals.next(0, ...)` until it returns `&""`, so the first group starts in the room's setup, before `_open_boss_intro` and `_check_room_won`.
- `step` calls `arrivals.next(delta, _standing_cost())` each tick and stands what it returns with `_stand_enemy(..., arrive = true)`. **Then it calls `_check_room_won()` every tick the queue is open.** An id that fails to stand (no data for it in the registry, or no spawns) is dropped from the queue, so a room can't get stuck uncleared.
- `_check_room_won` also requires `arrivals.is_done()`.
- `_on_adds_requested` stands adds with `arrive = true` (unless question 3 says otherwise).
- `_forget_enemies` calls `arrivals.clear()`. The `arrivals` member is Flow's state, not `DERIVED`.
- `enemies_left()` counts the queue too, so callers keep its meaning: enemies still to beat.

### 4. The look: `ArriveLook` (gameplay/feel, new)

`gameplay/feel/arrive_look.gd`, `VIEW_ONLY`. Each frame Feel steps it over the open bodies, and it draws each arriving body from `arrive_share()` alone, so a machine that joins mid-arrival, or a restored snapshot, shows it at the right point. It follows the way `FallLook` is driven, not the way it is drawn: `FallLook` scales and fades, which the Smooth rule doesn't allow here.

- **0 to 0.4, the mark:** a ring on the floor at the body's footprint, in the room's floor colours (`RoomBase.floor_colors()`, the shadow colour, with the light one as a rim), drawn in 4 frames from a dot to the footprint's width. This is the warning players read.
- **0.4 to 1, the rise:** the body comes up out of the mark. It is drawn shifted down by whole pixels, from its full height to 0 over at least 5 frames (snapped), and cut off at the mark's line by a clip rect on a `CanvasGroup`/clip parent round the body's drawn parts. That makes it one clip for any body, layered (`BodyPart`) or not, with no per-part work. Dust motes come off the mark through the motes, within their limits. The mark closes in its last 2 frames as the feet land, so the rise ends where standing begins (Smooth, "Stages hand over").
- No fade and no blur. The body keeps its own sprite and pose the whole time.
- A sound cue `enemy_arrive` (soft, played no more than every 0.1 s, so a group doesn't stack it), through the existing cue plan.
- **Risk, checked first in EA2:** the clip has to work with the body's draw order in the world (y-sort) and the room's light pass. If a clip parent breaks y-sort, the fallback is a per-sprite `region_rect` cut, done in the look (each sprite's own rows, still whole pixels).

Later, an enemy could pick its own look (`EnemyBase.arrival`, for example an imp that drops in from above). That is out of scope here: v1 has one look for every enemy.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| EA1 | **Arriving as a state:** `Actor.arrive`, `arrive_left`, `is_arriving`, `arrive_share`, `is_down` while arriving, the step and the move held, touches both ways. Tests: can't be hurt, targeted, touched or possessed; doesn't think, cast, move or call its phases' adds; contact damage only after landing; ends on time; snapshot mid-arrival; determinism | gameplay/actor, tests |
| EA2 | **The look:** `ArriveLook` in Feel (the y-sort and light check first), the mark and the rise, motes, the cue. Tests: at least 3 frames per stage, whole pixels, drawn from state alone (a restored snapshot mid-arrival), nothing allocated per frame | gameplay/feel, audio, tests |
| EA3 | **Every non-boss enemy arrives:** `_stand_enemy(..., arrive)`, room enemies and adds arrive (still all at once), bosses don't. This removes the pop before the pacing lands. Tests: the boss stands at once and its intro opens (test_boss_intro_hold.gd); the flow tests step past the arrival | gameplay/flow, tests |
| EA4 | **The rules:** `ArrivalRules`, `MapRules.arrivals`, `problems()` and the run validator, `run_room_paced` sent by the run, the crypt's numbers | core/base, core/events, gameplay/run, content/runs, tests |
| EA5 | **Groups:** `RoomArrivals`, Flow's queue, the far-spawn pick, room cleared only when the queue is empty, a failed id dropped. Tests: group sizes by cost and scale, the quiet trigger (and no group while the floor is busy, however long), an expensive enemy still comes, snapshot between groups and mid-arrival, cleared only at the end, never stuck | gameplay/flow, tests |
| EA6 | **Tune** in the owner's playtest: the numbers in content/runs/crypt.tres only | content/runs |

EA1 to EA3 can ship as one PR (the look, with no pacing change). EA4 and EA5 are a second PR. Each step updates the README of its area (gameplay/actor, gameplay/feel, gameplay/flow, gameplay/run, content/runs, core/events) and Flow's class doc.

## Tests that need a look

- `tests/gameplay/flow/test_flow*.gd`, `test_flow_adds.gd`, `tests/gameplay/run/test_run.gd`: these damage, kill or count enemies right after a room starts, and will hit bodies that are still arriving. They get a shared test helper that steps the world past `ARRIVE_SECONDS` (and, after EA5, calls the rest of the queue: `Flow.stand_all_now()`, for tests only).
- `test_snapshot_game.gd` snapshots about 3 s into a pinned run that has no `ArrivalRules`, so it covers neither mid-arrival nor between groups. EA1 and EA5 add their own snapshot tests for those moments, and `test_snapshot_game.gd` keeps checking that it still passes as it is.
- `test_content_determinism.gd` plays every enemy twice. It should pass as it is, because the arrival is deterministic state.
- The online bots (`tools/online_*.sh`) clear rooms by playing them. They only take longer.

## The owner's answers (2026-11-17)

1. **The pace:** only when the room gets quiet. No timer.
2. **Group size:** by cost, the measure the room's budget already uses.
3. **Boss adds:** they play the arrival too, so nothing pops in.
4. **The look:** a mark on the floor, then the body rising out of it.

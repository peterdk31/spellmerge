# Enemy arrivals: a room's enemies come in groups, and each one is seen coming

**Status (2026-11-17): a plan, waiting for the owner's answers to the questions at the end.** The owner asked: "A room should not spawn every enemy at once. And we need an animation when an enemy spawns in."

This changes one line of decision 30 (docs/milestones/boss-old-broom.md: "A room starts with its enemies standing"). The rest of decision 30 stays: there are still no waves. A room still holds a fixed list of enemies that the run's map picks, and it is cleared when the last of them is down. The only change is that they come in over the fight instead of all standing at the start. Nothing grows, and nothing comes after the list is used up.

## Why

- **Readable chaos (pillar 4).** With `room_budget = 16` in the crypt (content/runs/crypt.tres), a deep room can have a dozen bodies standing at its spawns in the first frame. Groups keep the number on screen readable, and the arrival look gives each new body a short warning before it can act.
- **Smooth (docs/STYLE.md, "Smooth").** Today an enemy pops in, which the Smooth rule doesn't allow: "nothing on screen changes its look in one jump". Its arrival plays frames (at least 3, by whole pixels, with no fade).
- **Nobody waits (pillar 2).** The next group comes when the room gets quiet **or** when a timer runs out, whichever is first. A party that fights slowly isn't punished by a flood, and a fast party never stands in an empty room waiting.

## How it plays

1. The room starts. The run's map has already picked its enemies (`run_room_chosen`, in the fill's order, which comes from the run's seed). Flow splits them into **groups**, and the first group starts arriving right away, together with the room's start cue.
2. **An arrival** (about 0.8 s, `ARRIVE_SECONDS`): first a mark grows on the floor where the body will stand. Then the body comes up out of the floor, feet last, with a few motes. While it arrives it is *not there yet*: it can't be hurt or targeted, it doesn't touch anyone, it doesn't think, move or cast, and spells pass through it. It does count as one of the room's enemies, so the room can't be cleared while it is arriving.
3. **The next group** starts arriving when either of these happens first:
   - the cost of the enemies still standing (or arriving) drops to `refill_at` or below, or
   - `gap` seconds have passed since the last group started.

   A group takes enemies from the front of the list until its cost reaches `group_budget`. It always takes at least one enemy, so an enemy that costs more than the budget still comes. Nothing arrives if that would put more than `on_floor` cost on the floor, unless the floor is empty (so the list always runs out).
4. **Where:** at the room's enemy spawns, as now (`stacked_position`), but a group uses the spawns **farthest from every standing wizard** first. A body never arrives on top of a player. The order of the spawns is worked out from state only, so it is the same on every machine.
5. **Cleared:** when the list is used up and nothing is standing or arriving. The exits light as today.

All the numbers scale with players the way the room's budget already does: a base plus a share for each player after the first, as `EnemyAdds` does.

### What doesn't change

- **A boss** stands at once, as now, and its intro (docs/milestones/boss-intro.md) opens on it. A boss room's own list is just the boss. **Phase adds** (`EnemyAdds`, `RoomAdds`) keep their own timing (the boss's phases call them), but each add plays the same arrival look (question 3).
- **The hub's placements** (dummies, props: `RoomContents`) stand as laid. They aren't enemies of a fight.
- **Mid-run joiners** are placed as now (`_joiner_spawn`, away from the enemies standing).
- **Difficulty** is still told about each body before it is added to the tree (`enemy_standing`), so scaling doesn't change. It is told when the body starts arriving, not when the room starts.

## The design in code

Three pieces, one area each. They talk through the actor's state and `core/` events, never by calling each other.

### 1. The data: `ArrivalRules` (core/base, new)

`core/base/arrival_rules.gd`, a `Resource`. A biome's `MapRules` gets an `arrivals: ArrivalRules` field, so each biome of a run sets its own pace in content/runs/*.tres. If it is null, everything arrives at once with the look, which is today's pace without the pop.

| Field | Starting value | Meaning |
| --- | --- | --- |
| `group_budget`, `group_per_player` | 5, +2 | the cost of one group |
| `refill_at`, `refill_per_player` | 2, +1 | the cost still standing that calls the next group |
| `on_floor`, `on_floor_per_player` | 8, +3 | the most cost standing or arriving at once |
| `gap` | 8 s | the longest time between two groups |
| `stagger` | 0.15 s | the time between two bodies of one group starting to arrive, so a group ripples in instead of all popping at once |

It has `problems()`, as `EnemyAdds` does: negative or non-finite numbers, or `on_floor` below `group_budget`. The run definition's validator reports them (RG1's validators).

### 2. The simulation: arriving is a state of the actor (gameplay/actor)

This works like a fall (hub rework HR-H2), which already has the same shape: a timer that is state, `is_down()` while it runs, and Feel drawing it from the state.

- `Actor.arrive_left: float` (state) and `Actor.arrive(seconds)`, called by whoever stands the body, before it enters the tree.
- `is_arriving()` and `arrive_share()` (0 to 1, for the look).
- `is_down()` is also true while it arrives. That one change keeps the body out of hurt shapes, casting, touches, AI targets and revives, because all of those already ask `is_down()`. In `step`, an arriving body counts down its timer, its Hurtbox follows it down (unregistered from the first tick, as a downed body's is), and then it returns: no think, no move, no cast. When the timer ends, it tells `enemy_arrived(actor)` (core/events, new) and plays like any other body.
- The state hash and snapshots already cover a new state member. `rest_leaf` treats an arriving body as not at rest, as it does a falling one.

This stays on `Actor` instead of becoming a component so that it sits right next to the fall it mirrors, and because `is_down()` is the one question every system already asks. A component would need the same hook in `Actor` anyway.

### 3. Pacing: `RoomArrivals` (gameplay/flow, new)

`gameplay/flow/room_arrivals.gd`, a `RefCounted` that Flow holds, like `RoomAdds`. Flow is already 1,500 lines, so the rules live here and Flow only calls them:

- State: `waiting: Array[StringName]` (ids not yet called), `gap_left: float`, `stagger_left: float`, `group_left: int` (bodies of the current group still to start).
- `begin(ids, rules, players)`, `step(delta, standing_cost) -> StringName` (returns the next id to stand this tick, or `&""`), `is_done()`, `clear()`. It is pure rules with no nodes, so it is tested without a world.
- `pick_spawn(spawns, wizards, used)`: the spawn farthest from every wizard, ties broken by index. It is a static function, used by Flow's `_stand_enemy` for arrivals.

In Flow:

- `_stand_room_enemies` no longer stands the whole list. It hands the list to `arrivals.begin(...)`.
- `step` asks `arrivals.step(...)` each tick, and stands what it returns with `_stand_enemy(...)`, then `enemy.arrive(ARRIVE_SECONDS)`. Adds go through the same `_stand_enemy`, so they arrive too.
- `_check_room_won` also needs `arrivals.is_done()`.
- `_forget_enemies` clears it. It goes into Flow's state (not `DERIVED`), so a snapshot taken between groups resumes the same queue.

### 4. The look: `ArriveLook` (gameplay/feel, new)

`gameplay/feel/arrive_look.gd`, `VIEW_ONLY`, made like `FallLook`. Each frame it goes over the open bodies and draws each arriving one from `arrive_share()` alone, so a machine that joins mid-arrival, or a restored snapshot, shows it at the right point.

- **0 to 0.4, the mark:** a ring on the floor at the body's footprint, in the biome's floor-mark colour (`RoomBase.floor_mark_colors`, which already exists for the crypt), drawn in 4 frames from a dot to the footprint's width. This is the warning players read.
- **0.4 to 1, the rise:** the body is drawn from its feet up, clipped by whole pixel rows, so its head shows first above the mark and its feet last, in 5 or more frames. Dust motes come off the mark (through the motes, within their limits). The mark closes in its last 2 frames as the feet land, so the rise ends where standing begins (Smooth, "Stages hand over").
- No fade and no blur. The body keeps its own sprite and pose the whole time.
- A sound cue `enemy_arrive` (a soft one, played no more than every 0.1 s so a group doesn't stack it), through the existing cue plan.

Later, an enemy could pick its own look (`EnemyBase.arrival`, for example an imp that drops in from above). That is out of scope here: v1 has one look for every enemy.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| EA1 | **Arriving as a state:** `Actor.arrive`, `arrive_left`, `is_arriving`, `arrive_share`, `is_down` while arriving, the step held, `enemy_arrived`; tests: can't be hurt, targeted or touched, doesn't think, ends on time, snapshot mid-arrival, determinism | gameplay/actor, core/events, tests |
| EA2 | **The look:** `ArriveLook` in Feel, the mark and the rise, motes, the cue; tests: at least 3 frames per stage, whole pixels, drawn from state alone (a restored snapshot mid-arrival), nothing allocated per frame | gameplay/feel, tests |
| EA3 | **Every enemy arrives:** Flow's `_stand_enemy` makes room enemies and adds arrive (still all at once). This removes the pop before the pacing lands | gameplay/flow, tests |
| EA4 | **The rules:** `ArrivalRules`, `MapRules.arrivals`, `problems()` and the run validator; the crypt's numbers | core/base, content/runs, tests |
| EA5 | **Groups:** `RoomArrivals`, Flow's queue, the far-spawn pick, room cleared only when the queue is empty; tests: group sizes by cost and players, refill and timer, the floor cap, an expensive enemy still comes, snapshot between groups, cleared only at the end; `test_snapshot_game`'s room check updated | gameplay/flow, tests |
| EA6 | **Tune** in the owner's playtest: the numbers in content/runs/crypt.tres only | content/runs |

EA1 to EA3 can ship as one PR (the look, with no pacing change). EA4 and EA5 are a second PR. Each step updates the README of its area (gameplay/actor, gameplay/feel, gameplay/flow, content/runs) and Flow's class doc.

## Tests that may need a look

- `tests/gameplay/flow/test_flow*.gd`, `tests/gameplay/run/test_run.gd`: these read `enemies_left()` or kill every enemy right after a room starts. They will need to step past the arrival, or kill the queue too. A test helper `Flow.stand_all_now()` (tests and bots only) calls the rest of the queue at once and ends every arrival.
- `test_snapshot_game.gd` ("a wave in every room"), `test_content_determinism.gd`: these should keep passing as they are. A run of them mid-arrival is the coverage we want.
- The online bots (`tools/online_*.sh`) clear rooms by playing them. They only take longer.

## Questions for the owner

1. **The pace:** the next group comes when the room gets quiet *or* after `gap` seconds (8 s), whichever is first (recommended). Or only when the room gets quiet?
2. **Groups by cost or by count?** By cost (recommended): an imp counts for more than a mite, the same measure the room's budget already uses. By count is simpler to read in the data.
3. **Adds and the arrival:** should a boss's phase adds play the arrival too (recommended: yes, so nothing pops)? Or should they stand at once, as a burst?
4. **The look:** a mark on the floor, then the body rising out of it (recommended, it fits the crypt). Or something else you have in mind, such as a crack, a summoning circle or a drop from above?

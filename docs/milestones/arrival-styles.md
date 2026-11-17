# Arrival styles: each biome (or enemy) names how its enemies arrive

**Status (2026-11-17): a plan, waiting for the owner's answers to the questions at the end.** The owner asked whether it is easy to change the arrival animation or add new ones in other biomes, then asked for this plan.

Today (enemy arrivals EA1–EA5, docs/milestones/enemy-arrivals.md) the arrival has one look. A mark grows on the floor, then the body rises out of it. The look is written in `gameplay/feel/arrive_look.gd`:
- its timing is constants there (`MARK_END`, `CLOSE_FROM`, the frame counts);
- its length is `Actor.ARRIVE_SECONDS`;
- its dust and sound are the one cue `enemy_arrive`.

Its colours already follow each room's floor, and its pacing is per-biome data (`ArrivalRules`). A different animation for a biome or an enemy, though, means editing that file.

This plan makes the look **data a biome or an enemy names**, as cards name their behaviour. A new biome's arrival becomes a `.tres` (and art, if it wants), and a new kind of motion becomes a small piece of code in Feel, written once and used by any style.

## What a style is

`ArrivalStyle` (`core/base/arrival_style.gd`, a `Resource`) is one folder per style, `content/arrivals/<id>/`: the `.tres`, its art if any, and an `assets.json`. Styles are found by folder, so there is no central list.

| Field | Meaning |
| --- | --- |
| `id` | the style's id, which the registry keys it by; it must match the folder's name (the validator checks) |
| `motion` | the kind of motion: `rise` (out of the floor, today's look) or `drop` (from above, AS3); one of `ArrivalStyle.MOTIONS`, a list of names in core (Feel maps each name to its code, and a test checks the two match, as `ModifierBase.RULES` is split) |
| `seconds` | how long the arrival lasts (simulation: the body can't be hurt and can't act for this long), 0.3 to 2 s |
| `mark_end`, `close_from` | where the mark stage ends and where the mark starts to close, as shares of the arrival (today's 0.4 and 0.92) |
| `mark_frames`, `close_frames` | the frames the mark grows in and closes in (today's 4 and 3) |
| `mark_strip` | the mark's look: empty for the ring drawn from the floor's colours (today's look), or an art strip played over the mark stage (AS4) |
| `cue` | the cue played as the body starts to move (today's `enemy_arrive`); a biome's own dust and sound |
| `biomes` | the biomes it is the arrival of (as an enemy names its `biomes`) |

`problems()` checks it, as `ArrivalRules` and `EnemyAdds` do:
- an id that isn't its folder's name;
- a motion `MOTIONS` doesn't have;
- `seconds` outside 0.3 to 2 s. The length decides how long a body can't be hurt, and content/ is open to contributors, so it has an upper bound too;
- the shares out of order;
- a stage too short for its frames at 60 fps (`ArrivalStyle.CHECK_FPS`), with at least 3 frames a stage (docs/STYLE.md, "Smooth"). Today's close stage is (1 - 0.92) × 0.8 s = 64 ms, about 3.8 frames, so a shorter `rise` must close earlier;
- a cue or art that doesn't exist.

Across all styles, no two may name the same biome (`ArrivalStyle.all_problems`, as `run_problems` does across runs), so no style wins silently by sort order. A test checks every style file and the set. No registration is needed: the registry's scan finds `content/arrivals/`.

**Which style an enemy gets** (`ArrivalStyle.pick(registry, enemy, biome)`, a pure static function):
1. the enemy's own (`EnemyBase.arrival`, a style id, empty by default: an imp that always drops in);
2. else the first style by id that names the room's biome (`RoomBase.biome`);
3. else `rise`, the default.

`pick` lives in core/base, is pure and never names Feel, so Flow picking a style doesn't couple Flow to Feel. Today's look moves into `content/arrivals/rise/`, with the same numbers, so nothing changes on screen. `Actor.ARRIVE_SECONDS` goes, and the length is always the style's.

## How it is built

- **The simulation knows only the length and the id.** Flow picks the style as it stands a body (it has the registry, the room and the enemy's data) and calls `Actor.arrive(style.seconds, style.id)`. `Actor.arrive_style: StringName` becomes state next to `arrive_seconds`, so every machine, a snapshot and a player who joins mid-arrival all draw the same style. Nothing in the simulation branches on the id. If no style is found at all (the `rise` folder deleted), Flow uses `rise`'s numbers kept as `ArrivalStyle.DEFAULT`, and a test pins them to `content/arrivals/rise/`.
- **Feel draws from the id.** `ArriveLook` keeps what every style shares: walking the arriving bodies, the marks, the cue's spacing and the put-back. It hands each body to its style's motion:
  - `gameplay/feel/arrive_motions/`, one small `RefCounted` per motion, keyed in a `MOTIONS` table (motion is engine work, like a card's behaviour: `ModifierBase.RULES`);
  - each motion answers `apply(body, share, style)` and `put_back(body)`. `apply` runs in `cut()`, at `frame_pre_draw`, where today's cut already runs; `step()` only lays the marks and plays the cue;
  - **an id it doesn't know** (a style missing on another machine, an old snapshot, a deleted folder) draws as `rise`, so a body is never drawn whole mid-arrival;
  - Feel hands `ArriveLook` a style lookup (the registry, or a Callable), and `play_cue` takes the cue's id: `play_cue(cue, at, weighted)`. Today feel.gd plays the fixed `ArriveLook.CUE`;
  - the mark's colours (`_fill`, `_rim`, one pair today) become per style before AS4.
  - **`rise`** is today's code moved, unchanged: the clip parent and the shifted parts.
  - **`drop`** needs no clip at all, so it is also the cheaper look: no extra render pass per body (see the arrival cost benchmark, branch bench/arrive-cost).
    - The mark is the body's shadow growing.
    - The body falls in **from above the top of the view**, which Feel knows (the simulation never does), so it slides in through the screen's edge instead of appearing out of nothing (Smooth: no pop). It falls by whole pixels and lands with dust.
    - While in the air it is drawn above the walls and the other bodies, as a thing in the air is. It takes its place in the y-sort as it lands, the same frame its feet touch the mark.
- **The mark** is the ring drawn from the floor's colours by default. A style may instead give an art strip, played frame by frame over the mark stage and closed in its last frames, so a forest biome can have roots or a frost biome rime, as art.
- **Tests:**
  - every style file (`problems()`);
  - every style on every enemy and the boss's adds, in the way `test_card_rules.gd` plays every card on every carrier: each arrives, lands on time, draws at least 3 frames a stage by whole pixels, and is drawn from state alone after a snapshot;
  - the picker's order;
  - determinism with two styles in one room.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| AS1 | **The data, with no change on screen:** `ArrivalStyle`, `MOTIONS`, `DEFAULT`, `content/arrivals/rise/` with today's numbers, `ArriveLook` reading the style's timings and cue instead of its constants, the `rise` motion moved into `arrive_motions/`, the validator and its test. The look's static helpers (`rise_shift`, `mark_radius`) take the style's numbers, so the 21 references in test_arrive_look.gd, test_arrive.gd, test_flow.gd and test_bot.gd are updated | core/base, content/arrivals, gameplay/feel, tests |
| AS2 | **Picked per body:** `ArrivalStyle.pick`, `EnemyBase.arrival`, `Actor.arrive(seconds, style)` and `arrive_style` as state, Flow picking as it stands a body; tests for the picker, snapshots and determinism | core/base, gameplay/actor, gameplay/flow, tests |
| AS3 | **A second motion, to prove it:** `drop` (question 1), with its own cue; the every-style-on-every-enemy test | gameplay/feel, content/arrivals, content/cues, tests |
| AS4 | **Art strips for the mark** (question 2) | gameplay/feel, content/arrivals, tests |

Each step updates the README of the areas it touches, and `content/arrivals/README.md` (new) is the guide: copy `rise/`, change the numbers, name your biome.

## Questions for the owner

1. **The second motion, built to prove the system:** `drop` (from above, with a shadow growing first; recommended, as it is also the cheaper look), or none yet (only the system, with `rise` as its one style)?
2. **The mark:** allow art strips (AS4; recommended, so a biome's mark can be its own art), or only the drawn ring with numbers?
3. **Build it now** in sessions, merged automatically as before (recommended), or keep the plan until a second biome is planned?

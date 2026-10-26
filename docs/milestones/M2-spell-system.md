# M2: Spell system

**Goal:** make spell building the heart of the game (docs/DESIGN.md, pillar 1: few components, many combinations). The 18 starting components (5 forms, 4 elements, 6 modifiers, 3 triggers) are built as data on small base classes. A spell is assembled from them as form → element → modifiers → trigger, and a trigger holds another spell. A complexity budget keeps every spell inside the performance limits. Each player builds in their own corner panel and nobody waits for anyone (pillar 2). The stress benchmark starts gating the daily build, and the owner picks the game's look from Claude's style samples.

**Status (2026-10-21):** started by the owner ("Start milestone 2"), which is the **go** verdict at C1 (#97) after two iterate rounds. M1's done-when items that are still open carry into M2 (see "Carried over from M1"), the way M0's dry runs carried into M1.

**Status (2026-10-23):** all parts are built and no known crash or blocker is left. Done-when item 3 is **not yet met**: the web physics step with rendering off is 7.6 ms with the cap of 500 (docs/DECISIONS.md, 2026-10-23), but the web run with rendering still warns (p95 56.5 ms, in the CI browser without a GPU). That is carried to the owner's C2 verdict together with the real-GPU frame rate.

**Status (2026-10-25):** the owner answered the C2 checkpoint (#235) with **iterate**, so the milestone is in progress again with rework tasks (docs/NEXT.md): the clip recorder and Spell atlas (#245), spell visuals (#244), Lightning as a fifth element (#243), in that order. Its next end is a new C2 checkpoint.

**Status (2026-10-26):** the iterate round is built (see "Checkpoint C2, second round") and no known crash or blocker is left. M2 is done and waits for the owner's second C2 verdict; done-when item 3 is still open on the real-GPU frame rate.

**Done when:**

1. **Validators pass:** every component `.tres` and the reaction table pass the content validator (`core/spells/validator.gd`), run by `tests/content/spells/test_validators.gd` in `ci/build/build.sh --quick --tests`. A broken fixture of each kind fails it with a message that names the file, the field and the fix.
2. **20+ combos work:** `tests/content/spells/test_combos.gd` builds at least 20 named spells from the combo catalogue (below), casts each in a headless test arena, and checks the behaviour each one promises. Every one of the 18 components appears in at least two passing combos that are not refusal checks.
3. The **stress benchmark** runs in the daily build and is within budget: 4 players, 100 enemies and 500 projectiles on web (1,000 until the first web run, docs/DECISIONS.md, 2026-10-23), 200 and 3,000 on desktop, full effects, game-logic frame time under 16.7 ms on the runner. Over budget it prints a warning with the numbers and likely fixes, never a failure (docs/PLAN.md, "Gates are sparse"); this done-when item is met when the warning is gone, which is a task, not a gate.
4. The **4-bot smoke test** passes natively and on web with built spells: bots 1–3 each fight with a random valid spell, and bot 4 stays in its builder (full view in the breaks, the quick view during waves) while the others progress.
5. M1's carried-over items are done (below).
6. The **stabilisation phase** is over: no known crash or blocker in M2's scope.
7. Checkpoint **C2** has a verdict (below).

## Carried over from M1

The owner said go at C1 on 2026-10-21 while these were still open. They are not dropped; they are part of M2's done-when (item 5):

- The web 4-bot run and web load time (#93, #91): the owner-only `ci/` change is PR #98, waiting for the owner's merge.
- The WASM projectile timing runner (game side, Claude's): folded into part 25, the stress benchmark in the exports.
- The Style Guide page and starter kit zip (#95): also in PR #98.
- M0's dry runs and 3 daily releases in a row ([M0's list](M0-foundation.md#dry-runs); owner-run, results in `docs/LOG.md`).

## Who builds what

- **Claude** builds everything in bot-maintained paths: `core/`, `gameplay/`, `hud/`, `content/`, `art/`, `tests/`, `project.godot`, `export_presets.cfg`, and `docs/` except the owner-only `docs/DESIGN.md`, `docs/SECURITY-CHECKLIST.md` and `docs/SETUP-APP.md`. One part is one session and one PR.
- **The owner** makes the changes in owner-only paths: the stress benchmark step and its 7-day trend warning in `ci/build/build.sh` (part 25), calling the validator from `tools/check.sh` if wanted (part 9), merging PR #98, picking the art direction (part 27), locking it in `docs/DESIGN.md` (part 27), and the C2 verdict. Each is asked as one `owner` issue with the exact change when its part starts. The queue goes on meanwhile.
- **Players** report bugs and share ideas (new components, combos, feedback on the look) in Issues and Discussions. The daily intake schedules them or puts them on the backlog; Claude makes every component, story text, icon and sound itself.
- **The weekly owner playtest** goes on. From the first Sunday after the builder works (part 20), the "Playtest of the week" asks about building, not only feel.

## Design decisions for M2

These fill in what the plan leaves open (also recorded in `docs/DECISIONS.md`).

### Components are data on four small base classes

- `core/base/` gets `SpellComponent` (`id`, `demo`, `display_name`, `complexity`, `icon`) and four subclasses: `FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`. A component is a `.tres` on one of them, in its own folder under `content/spells/forms/`, `elements/`, `modifiers/` or `triggers/`. It needs a `.gd` only for behaviour the base class can't express with its fields. Of the starting 18, at most the five forms and three of the modifiers should need one.
- **Ids are unique across all four kinds,** because the registry keys everything under `spells` by id. The validator checks it.
- **Form** (bolt, beam, nova, rune, orbit): how shots leave the caster. Fields: `base_damage`, `mana_cost`, `cooldown`, `speed`, `lifetime`, `radius`, `shots`, `spread`, `motion` (straight, still, orbit), `pierce`. Beam is a ray, not a moving shot (see `core/projectiles` below).
- **Element** (fire, frost, storm, void): what a hit does besides damage. Fields: `status_id`, `status_duration`, `status_strength`, `damage_scale`, `tint` (a palette colour from docs/STYLE.md). The reactions an element takes part in live in the reaction table, not on the element.
- **Modifier** (split, pierce, homing, chain, bigger, faster): changes the compiled numbers or adds a behaviour. Fields: multipliers and adds on the form's numbers (`damage_mult`, `speed_mult`, `radius_mult`, `cooldown_mult`, `mana_mult`, `shot_mult`, `extra_pierce`), plus a `behaviour` flag. Behaviours are `homing` (the projectile manager), and `chain` and `split` (the spell runtime).
- **Trigger** (on hit, on expire, timer): when the held spell fires. Fields: `event` (hit, expire, timer), `interval` (timer only), `max_fires` per shot.
- **Spell shape:** at most one form, one element, three modifiers and one trigger. The trigger holds one more spell of the same shape. A modifier may appear more than once (split + split). The element is optional: no element means plain arcane damage, so a fresh player can cast before choosing one. The form is required.
- **There is no cast time.** A spell's cooldown is its cast time. The builder shows "cooldown", which is the plan's "cast time" stat.

### Provisional complexities

The budget is 12 per spell, counting the spell its trigger holds. These are first numbers, which the combo test and playtests retune:

| Kind | Complexity |
| --- | --- |
| Forms | bolt 1, beam 2, nova 2, rune 2, orbit 2 |
| Elements | fire 1, frost 1, storm 1, void 1 |
| Modifiers | split 2, homing 2, chain 2, pierce 1, bigger 1, faster 1 |
| Triggers | on hit 1, on expire 1, timer 2 |

Every combo in the catalogue below fits under 12 with these numbers. Its largest entry, combo 17 at depth 3, totals 11.

### The spell runtime lives in `core/spells/`

- The runtime is a new core service, `core/spells/` (autoload `Spells`). It belongs in `core/` because content components may depend only on `core/`, and the player may read no spell field.
  - It **compiles** a recipe (component ids per slot) into a `CompiledSpell`: a `RefCounted` with the final numbers, the complexity and a short description for the builder.
  - It **casts** the compiled spell through `Projectiles`.
  - It **runs triggers**: it listens to `projectile_hit` and the new `projectile_expired`, and fires held spells from the shot's position.
- The player keeps calling one method: `Spells.cast(player, slot, origin, direction, mana) -> float`. The contract is M1's `SpellBase.cast`: the mana spent, or `REFUSED`. Bots call the same method.
- The field-read test stays and is widened to the new classes. It fails when a script outside `content/spells/`, `core/base/` and `core/spells/` reads a spell field.
- Each player owns their own compiled spells and cooldowns. This removes M1's problem of one shared resource holding everyone's cooldowns. Component `.tres` files are shared and read-only at run time.
- Held spells that a trigger fires send no `spell_cast`, because no player cast them. `spell_cast` stays the player's event for a cast from the staff. Feel reacts to the hits and reactions they cause.
- `core/spells/` is not in the plan's folder layout, which lists events, registry, input, ui_focus, save, base, projectiles and pools under `core/`. Adding it is a detail inside `core/`, which Claude maintains. It is recorded in `docs/DECISIONS.md` and the core README.

### Tags: how a hit finds its spell

- Every shot carries an int `tag` (as in M1). In M2 the tag encodes player (0–3), slot (A, B), depth (0–2) and a **generation** (0–7, a ring that advances on each build change of that slot). `Spells` keeps a profile per tag (damage, knockback, element, status, trigger, chain left) and a count of live shots per tag.
- A shot still in the air after a swap or a build change keeps hitting with its old profile. A generation's profile is freed when its last shot ends. If all 8 generations of a slot are live at once, which takes eight rebuilds within one shot's life, the oldest generation's shots are dropped, not mis-profiled.
- Part 5 tests this: a rebuild mid-flight, four players at once, and the ring wrapping round.

### Hits, statuses and reactions

- `gameplay/combat` stays the only place damage happens (docs/PLAN.md: combat applies status effects and element reactions). On `projectile_hit` it asks `Spells.hit_profile(tag)` for damage, knockback, element and status. Gameplay calling core is the allowed direction. This replaces M1's per-spell profile table. `hit_tag()`, `hit_damage()` and `hit_knockback()` go away with `SpellBase` in part 11.
- **Statuses** (one per element):
  - **burn** (fire): damage over time.
  - **chill** (frost): slow; at 3 stacks, a short freeze.
  - **shock** (storm): the next hit on the target also jumps to one neighbour.
  - **hex** (void): a light pull toward the hit point, and more damage taken.
- Statuses live in `combat` as packed arrays per enemy, like its health, with no per-frame allocation. Player spells give wizards no statuses in M2 (friendly fire stays damage only), so no status has to be designed for a downed friend.
- **Reactions** are data in `content/spells/reactions.tres`, on `core/base/reaction_table.gd`. When a hit of element B lands on a target with status A, the reaction runs instead of B's own status. Each reaction picks one of four **effect kinds** that `combat` implements once:
  - `burst`: area damage.
  - `consume`: remove the status for bonus damage.
  - `extend`: a longer or stronger status.
  - `spread`: copy the status to neighbours.
- A new element is new files plus rows in the table. It needs a change in `combat` only if it needs a new effect kind. The table has no `id`: the registry skips it as a component, and `combat` loads it by its literal path.
- **All six pairs react,** so each element has three interactions (docs/DESIGN.md asks for at least two per component). The names are generic and original:
  - **Shatter** (frost + storm): consume chill for a big single hit; frozen targets take double.
  - **Thaw** (fire + frost): consume, then a burst of steam around the target.
  - **Flare** (fire + storm): a wide, weak burst.
  - **Kindle** (fire + void): spread burn to neighbours.
  - **Stillness** (frost + void): extend chill into a long freeze.
  - **Rift** (storm + void): a burst that pulls.
  - The numbers are tuning, set in part 7 and retuned by playtest.
- **Neighbours** (shock jump, spread, burst, Rift, chain) come from the projectile manager's target grid through the new queries below. `combat` never loops over every enemy.
- Reaction and status feedback goes through the existing `status_applied` event and a new `reaction_triggered(player, reaction_id, position)` event (sender `combat`). `feel` hears them for a flash, a number and a sound by id, silent until Audio adds the sounds.

### `core/projectiles` grows only what the forms and modifiers need

- **`projectile_expired(player, position, tag)`**: sent when a shot's life ends or it hits a wall. On-expire triggers and the wall-hit spark (backlog) both use it. It is sent from the same packed loop, with no allocation.
- **Motion modes per shot:**
  - `straight`: today's motion.
  - `still`: the rune. Zero velocity; it waits for a target to enter.
  - `orbit`: circles the owner at a radius. `player` pushes the owner's position each step into a per-player anchor array, so the manager never looks up a node.
- **Homing** is a per-shot turn rate toward the nearest target. It is checked every 4th step to keep the cost bounded. On a beam, homing aims the ray at the nearest target within 30° of the aim, since a ray cannot turn.
- **Target queries**, the public face of the existing private grid:
  - `nearest_target(point, radius, layers, exclude) -> Node2D`
  - `targets_in(point, radius, layers, out)`, which fills a reused array.
  - Chain, homing, the shock jump and the area reactions all use them.
- **`ray(player, origin, direction, length, pierce, layers, tag) -> float`** for the beam. It walks the target grid and the wall grid along the ray, sends `projectile_hit` for up to `pierce + 1` targets, and returns how far the ray got. `feel` draws the beam as a short-lived line of that length. A beam holds no row in the pool.
- **Chain** is not in the manager. On a hit by a chain shot, `Spells` spawns one new shot from the hit point toward `nearest_target` within 96 px, excluding the target just hit, with one fewer chain left.
- **Split** is the spell runtime multiplying the shots in a fan at cast time. A split shot is an ordinary shot.
- The hit-work budget (`WORK_PER_STEP`) and the caps stay. Homing and orbit rows count toward the step's work, so a screen full of homing shots degrades the same graceful way.

### How a held spell fires

- **Origin:** the shot's position. For on hit, the hit point. For on expire, where the shot ended. For a wall, just in front of the wall.
- **Direction:** the shot's velocity. For an orbit or still shot (no useful velocity), outward from the caster through the shot. For a beam's on-hit trigger, the beam's direction.
- **The target that fired an on-hit trigger is excluded** from that held spell's hits for 0.1 s, so a held spell always reaches something new instead of hitting its source again.

### The spell limits are the performance limits

- **Complexity budget:** 12 per spell, including the spell its trigger holds (complexities above). The builder shows it as a bar and refuses a change over the budget, with the reason. Relics that raise the budget are M3.
- **Shots per cast:** at most **24** from one cast, after split, nova and `shot_mult` multiply. The compiler clamps the count and says so in the description.
- **Trigger depth:** a trigger may hold a spell whose own trigger holds another, at most **2** levels below the cast (depth 3 in all). The builder offers no deeper slot.
- **Trigger fires per player per step:** at most **32**. Extra fires in that step are dropped, not queued, so an on-hit cascade can never snowball across frames. Each trigger also has `max_fires` per shot; a timer fires at most 4 times.
- **The global projectile cap** is 500 on web (1,000 until the first web run, docs/DECISIONS.md, 2026-10-23) and stays 3,000 on desktop, and drops the oldest shot of whoever owns the most. At the cap, effects degrade (fewer particles per hit) instead of lagging. `feel` keeps its `PARTICLE_LIMIT`; components declare no particles in M2, so the validator has no particle count to check yet.
- These numbers are first guesses for the stress benchmark (part 25) to confirm or lower. They are constants in `core/spells/limits.gd`. Tests check that a spell at every limit still compiles and that one over a limit is refused or clamped.

### Building spells, without anyone waiting

- **Two prepared spells per player** (slots A and B). The new input action `swap` switches between them in combat, and `cast` casts the active one. This is the "swap prepared spells" quick action from docs/PLAN.md.
- **The bag:** in M2, every player's bag holds all components found in the registry (a test bench). Collecting components is the job of `rewards` in M3, which fills the bag per player instead. The bag is a per-player list in `player`, so M3 changes who fills it, not the builder.
- **The full builder** (`hud/builder/`) is opened from the overlay's "Build" entry.
  - It expands the player's corner panel toward the middle of the screen and never covers another panel. Alone, it may fill the screen.
  - It shows the slot chain (form → element → modifiers → trigger → held spell), the bag filtered to what fits the selected slot, and live stats: damage, mana, cooldown, shots and the complexity bar.
  - It shows a code-drawn mini-preview of the shot pattern (fan, ring, orbit circle, ray, rune) and the selected component's one-line description from Story.
  - It is driven by gamepad or keys only, through `core/ui_focus`. The mouse acts only on P1's panel.
- **When the full builder is used:** in a cleared room, which in M2 means the break between waves (docs/PLAN.md: "full builder: cleared rooms and the hub"). During a wave, combat allows quick actions only.
- **The break between waves becomes a build break of fixed length** (`BUILD_BREAK`, a first guess of 12 s, replacing M1's 3 s `NEXT_WAVE_DELAY`). The HUD shows a countdown. The next wave starts when the timer ends, whoever is still building. Nobody's choice holds it back or speeds it up, so no player waits on another and none decides for the others (co-op rules 1 and 2).
- When the wave starts, an open full builder folds into the **quick view**: the slot chain and the "drop component" action, with the choices so far kept. The wave is never paused, and a player in a builder stands still and can be hit, as in M1's overlay. The HUD shows a hammer icon on a building player's panel, as a display only.
- **The quick action in combat:** the overlay (and the quick view) get "Drop component". It puts one component from the bag into a free slot of the active spell (a free modifier slot, or the empty element slot) without the full builder.
- **Intent and result:**
  - The HUD sends `build_change_requested(player, spell, slot, component_id)` and `spell_swap_requested(player)`. The `spell` argument, new in M2, is a `PackedInt32Array` path: `[0]` is spell A, `[1]` is B, and `[0, 0]` is the spell held by A's trigger, and so on.
  - `player` checks the change with `Spells.compile`, then applies or refuses it. It announces `spell_changed(player, spell, description)` or `build_refused(player, reason)`. The HUD shows only what those say.
  - These are new or changed events in `core/events`, one sender each.
- Builds last for the session only. Saving belongs to `core/save` in M5.

### The fire bolt migrates

- `content/spells/forms/bolt/` becomes a `FormBase` `.tres`, and `content/spells/elements/fire/` holds fire. A player's starting spell A is bolt + fire, which plays like M1's Fire Bolt plus burn. Spell B starts as a bolt with no element.
- `gameplay/flow` stops holding a `SpellBase`. `spell_id_to_play` becomes `start_recipe_a` and `start_recipe_b` (component ids). `_spawn_players` and `_add_wizard` hand the recipes to `player`, which compiles them through `Spells`. `docs/ARCHITECTURE.md`'s "where each change goes" table is updated to match.
- `SpellBase` and its tests are removed in part 11, once nothing uses them. The spells README's example moves to the new bolt.

### Validators

- `core/spells/validator.gd` checks every component and the reaction table:
  - required fields are set, and numbers are in range (each range is documented next to its field);
  - `id` equals the folder name and is unique across all kinds;
  - the icon is present and listed in the manifest;
  - no unknown status or effect kind appears;
  - no reaction row names an element that doesn't exist;
  - each component's `complexity` fits the budget on its own.
- It returns its problems as rule, file, field and fix (the same shape as `tools/check.sh`), so a session's agent can act on them.
- The registry runs it at start in debug builds and pushes a warning per problem. The test fails on any problem.
- Calling it from `tools/check.sh` is an owner question asked in part 9. Until then, sessions run `ci/build/build.sh --quick --tests`.

### The combo catalogue

- `content/spells/combos.json` lists named combos. Each has a recipe (ids per slot), what it should do in plain words, and the check the combo test runs (for example: kills N imps, triggers reaction X, never exceeds K shots).
- It doubles as the start of the codex (docs/DESIGN.md, "Discovery"), which is `progression`'s job in M5. In M2 it is only data and a test.
- There are at least 20 combos by the end of M2, with each component in at least two. Every new component comes with a combo row; the spells README says so.

### Story starts with words the game shows

- Claude writes `docs/STORY.md` (canon and tone, short) before the first lore: a self-aware, slightly comic magic world with real stakes (docs/DESIGN.md, pillar 3).
- The first story content is a one-line **description per component**, in `content/story/lore/components/<id>.json`.
  - Fields: `id`, `refers_to` (`spell:<component id>`), `title` and `text`. `text` has at most 60 characters, so it fits the builder's three-line note.
  - The builder shows it.
  - A validator checks the fields, the length, and that `refers_to` names real content.
- Dialogue and in-run events stay empty until a later milestone has a place to show them.

### Art and the art direction

- Each component gets a 16×16 placeholder icon: hand-written SVG following docs/STYLE.md (rects only, palette only). Each element gets a shot tint from the palette. Forms that draw something new (the beam line, rune circle, orbit trail and nova ring) get a placeholder sprite in `art/vfx/`. All are listed in `art/manifest.json` as `ai`, tier `placeholder`.
- **The art direction choice** (docs/PLAN.md, "Who sets the direction"):
  - Claude draws two or three style samples itself (a wizard, a crypt tile and one spell icon each, in the palette and on the grid) and puts them on one screenshot sheet.
  - It asks the owner in an `owner` issue to pick one, or to commission an artist. The owner may first ask players for feedback in Discussions; the intake reads it like any other post.
  - The chosen files become the golden examples in `docs/STYLE.md` and `art/kit/golden.json`. The owner locks the choice in `docs/DESIGN.md` ("Art direction (locked)").
  - Replacing the placeholders with the chosen style is spread over later milestones, not done in M2.

### Bots build spells

- `tests/bots/bot.gd` gets a builder. In the first break, a fighter bot builds a random spell that compiles, using the same `build_change_requested` events a person sends. The build is seeded, so a failure can be replayed.
- Bot 4 of the 4-bot test opens the full builder and stays in it: the full view in breaks, the quick view during waves. This is the test docs/PLAN.md asks for ("one bot that idles in the builder while the others must still progress").
- A new `tests/bots/test_spell_fuzz.gd` compiles and casts a few hundred random recipes in the test arena. It fails on any error line, a broken limit or a frame over budget.
- Balance reports from bot runs stay M3's.

## Parts, in build order

Each part ends with tests and a green `tools/check.sh` and `ci/build/build.sh --quick --tests`, and is sized for one session and one PR. `docs/NEXT.md` holds the parts as tasks.

| # | Part | Delivers |
| --- | --- | --- |
| 1 | **Component base classes:** `core/base` | `SpellComponent`, `FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`, `ReactionTable`, with documented fields and ranges; tests. `SpellBase` stays until part 11 |
| 2 | **Events for M2:** `core/events` | `projectile_expired`, `reaction_triggered`, `spell_changed`, `build_refused`, `spell_swap_requested`; `build_change_requested` gets the `spell` path; the events table and area READMEs fixed to match; the `swap` input action |
| 3 | **Projectile manager, part 1:** `core/projectiles` | `projectile_expired` (end of life and walls), the target queries `nearest_target` and `targets_in`, the `still` motion; tests; the timing test still within budget |
| 4 | **Projectile manager, part 2:** `core/projectiles` | `orbit` with per-player anchors, homing on the grid every 4th step, `ray()` for the beam; the timing test extended with homing, orbit and rays; the hit-work budget still bounds a step |
| 5 | **The compiler and limits:** `core/spells` | `limits.gd`, `CompiledSpell`, `Spells.compile(recipe)` with the complexity, shot and depth limits, clamping and a plain description; the tag scheme with generations; tests at and over every limit |
| 6 | **Casting and triggers:** `core/spells` | `Spells.cast(player, slot, ...)` with per-player cooldowns, split at cast, triggers on hit, expire and timer with the per-step fire cap, held-spell origin, direction and exclusion, chain on hit, `hit_profile(tag)`; tests with four players and a rebuild mid-flight |
| 7 | **The four elements and statuses:** `content/spells/elements/`, `gameplay/combat` | Fire, frost, storm and void as `.tres` with tints and icons; burn, chill and freeze, shock and hex as packed arrays per enemy in `combat`; `status_applied`; `combat` reads `Spells.hit_profile`; the AI respects slow and freeze; tests |
| 8 | **Reactions:** `content/spells/reactions.tres`, `gameplay/combat` | The four effect kinds, the six reactions, `reaction_triggered`; feel reacts (flash, number, sound by id); tests per reaction |
| 9 | **The validator:** `core/spells/validator.gd` | Checks for all component kinds and the reaction table, a broken fixture of each, `test_validators.gd`, warnings from the registry in debug; the owner question about `tools/check.sh` |
| 10 | **The five forms:** `content/spells/forms/` | Bolt (migrated), beam, nova, rune and orbit as `.tres` (plus a `.gd` where needed), placeholder vfx, manifest lines; a test per form |
| 11 | **Player and flow on the new runtime:** `gameplay/player`, `gameplay/flow` | Two prepared spells, `swap`, the per-player bag from the registry, `build_change_requested` checked and applied, `spell_changed` and `build_refused`; flow's start recipes instead of a spell id; `SpellBase` removed; the field-read test widened; ARCHITECTURE.md updated; the 4-bot test still green |
| 12 | **The six modifiers:** `content/spells/modifiers/` | Split, pierce, homing, chain, bigger and faster, with icons; tests per modifier |
| 13 | **The three triggers:** `content/spells/triggers/` | On hit, on expire and timer, with icons; tests including depth 3 and the fire cap |
| 14 | **The combo catalogue and test:** `content/spells/combos.json`, `tests/content/spells/test_combos.gd` | The test arena fixture and the first 12 combos passing |
| 15 | **Spells README and example** | The README rewritten for the component classes (fields, ranges, complexity, the combo row rule), with the bolt, frost, split and on hit as examples |
| 16 | **Builder, part 1:** `hud/builder` | The expanded corner panel, the slot chain and the bag, per-player focus through `core/ui_focus`, opened from the overlay; sends `build_change_requested`; tests with four builders open at once |
| 17 | **Builder, part 2:** `hud/builder` | Live stats, the complexity bar, the refusal reason, the mini-preview and the descriptions (empty until part 23); screenshot shots for 1 and 4 players |
| 18 | **The quick view and quick actions:** `hud/builder`, `hud/panels`, `gameplay/player` | The builder folds into the quick view when a wave starts; swap shown on the corner panel (active spell A or B); "Drop component" in the overlay and the quick view; tests |
| 19 | **The build break:** `gameplay/flow`, `hud/panels` | `BUILD_BREAK` instead of `NEXT_WAVE_DELAY`, the countdown, the hammer icon (display only); tests that the wave starts on time with one, two and four players, whoever is building |
| 20 | **Bots build spells:** `tests/bots` | Seeded random builds, bot 4 staying in its builder in the 4-bot test, `test_spell_fuzz.gd`; **the weekly playtest asks about building from here** |
| 21 | **Combos to 20+:** `combos.json` | At least 20 combos passing, each component in two non-refusal combos; done-when item 2 |
| 22 | **Story canon:** `docs/STORY.md` | Canon and tone, short; listed in `llms.txt` |
| 23 | **The first lore:** `content/story/lore/components/` | One description per component, its validator, the Story README's example and schema; the builder shows them |
| 24 | **Stress scene:** `tests/benchmark` | The stress scene (4 bots with built spells, 100 or 200 enemies, 500 or 3,000 shots, full effects) in the editor run, `BENCH:` lines, `STRESS OK` |
| 25 | **Stress in the exports and the limits:** `tests/benchmark`, `core/spells/limits.gd` | The stress run and M1's WASM projectile timing runner in the Linux Test and Web Test exports (a node the main menu adds on `--stress` or `--projectile-timing`, like the 4-bot runner); the limits confirmed or lowered from the numbers; the `ci/` step (a warning over budget, not a gate) asked as an owner issue |
| 26 | **Component icons and art pass:** `art/`, `content/spells/` | Icons for all 18, element shot tints and the vfx checked together in one screenshot sheet against docs/STYLE.md; whatever falls short becomes Claude's own replacement task in `docs/NEXT.md` |
| 27 | **Art direction choice** | Claude drafts the style samples itself and asks the owner in one `owner` issue to pick one (optionally after asking players for feedback in Discussions) and to lock it in DESIGN.md; nothing in the game waits on it |
| 28 | **Stabilisation and C2** | Only bug fixing, polish and performance until no known crash or blocker remains; then the C2 issue with a build link, bot data (fuzz and stress numbers, which recipes bots build), Claude's honest assessment and questions |

- Parts 1–6 are the engine, 7–15 the content, 16–19 the builder, and 20–25 the proof.
- The Spells README and examples come at part 15, after all four kinds and the validator exist; the Story README's example at part 23.
- The art direction choice (part 27) only needs the game's current look, so a session with spare room may do it earlier.

## Combo catalogue (first draft)

The combo test (parts 14 and 21) starts from these. Each line is a recipe (complexity in brackets) and what it must do. "→" is a trigger holding the next spell.

1. **Bolt + fire** [2]: M1's fire bolt plus burn; an imp keeps losing health after the hit.
2. **Bolt + frost, then bolt + storm on the same imp** [2 each]: Shatter.
3. **Nova + fire + bigger** [4]: one ring hits every imp within reach around the caster.
4. **Beam + storm + pierce** [4]: a ray through three imps in a line.
5. **Rune + frost + timer → nova + frost** [8]: a frost rune that pulses a frost nova every 0.5 s; imps standing round it freeze on the third pulse.
6. **Orbit + void** [3]: circling shots hex every imp that crosses the orbit.
7. **Bolt + split + homing** [5]: three homing bolts that find three different imps.
8. **Bolt + storm + chain** [4]: a hit jumps to the next imp (chain); that imp is now shocked, so the next hit on it jumps once more.
9. **Bolt + on expire → nova + fire** [5]: a blast where the bolt ends, also when it ends at a wall.
10. **Bolt + faster + pierce** [3]: a fast line through the room that hits every imp on it.
11. **Beam + frost + bigger** [4]: a wide ray that chills a lane.
12. **Orbit + fire + timer → bolt + fire + split** [9]: a ring that throws a fan of three fire bolts outward every half second.
13. **Nova + void + on hit → bolt + fire** [6]: each hexed imp throws a fire bolt onward; Kindle spreads burn through the crowd.
14. **Rune + storm + chain** [5]: a mine whose hit jumps between imps.
15. **Bolt + frost + on hit → beam + storm** [6]: a hit fires a ray onward from the target, through the imps behind it.
16. **Nova + split + split** [6]: 8 × 3 × 3 shots, clamped to 24, with the reason in the description (a refusal check: counts for no component's two).
17. **Nova + fire + on hit → nova + fire + on hit → nova + fire** [11]: depth 3 runs, and no depth-4 slot is offered.
18. **Orbit + frost + pierce** [4]: a frost ring that chills everything it passes.
19. **Beam + void + homing** [5]: the ray aims at the nearest imp within 30° of the aim.
20. **Two players: bolt + fire on an imp, then bolt + storm + timer → nova + storm** [2; 7]: the pulsing bolt's storm nova sets off Flare on the burning imp.
21. **Rune + fire + bigger + on expire → nova + frost** [8]: a fire trap that ends in a frost nova; Thaw on every burning imp.
22. **Nova + storm + faster** [4]: a quick ring of shock that recharges fast.
23. **Bolt + homing + frost + on expire → nova + frost** [8]: a bolt that finds its target and ends in a frost burst.
24. **Four players, four elements on one imp** [2 each]: reactions fire from every pair that meets, and the per-step trigger cap holds.

## Checkpoint C2

The question is: **is building spells fun and deep, with surprising combos?**

- The owner decides, with Claude's assessment from bot data (which recipes bots and players build, the fuzz and stress numbers), the weekly playtest answers and player feedback.
- Verdicts: **go** (M3 starts), **iterate** (rework the weak parts, at most 2 rounds) or **pivot**.
- The owner has 7 days to answer. Without an answer, Claude defaults to iterate (docs/PLAN.md, "Go/no-go checkpoints").

### Checkpoint C2, second round (2026-10-26)

**What was reworked** (the owner's iterate, #235, in the order they asked):
- **#245, the clip recorder and the Spell atlas.** `tests/clips/record.gd` records clips of spells, combos and reactions as frames (the format `ci/smbot/clips.py` reads); the Spell atlas data is in `tools/`. The owner can judge visuals from animations. GIF encoding and publishing are `ci/` work, built by the owner (#246).
- **#244, spell visuals,** in parts: element looks, form bodies in flight (rune diamond, orbit beads, shaped bodies drawn at 0.62), reactions as bursts bigger than a hit (ring, particles, hit-stop, shake, power per reaction), tinted enemy looks for burn, chill, freeze, shock and hex, then a polish pass over 51 clips (the flame body fixed).
- **#243, Lightning,** the fifth element: the `static` status and the discharge to nearby charged enemies, two new reactions (Overload, Superconduct), three new combos and a drawn discharge arc. The extensibility report is in its PR.
- Also: the quick view's and overlay's drop lists scroll, so a twelfth component no longer breaks the layout.

**Numbers** (`ci/build/build.sh --quick --tests`, headless, game logic only; everything passes): 26 combos in `combos.json`, all passing `test_combos`; `test_validators` passes; the fuzz test compiled 244 of 300 random recipes (slowest mean step 0.66 ms, slowest step 2.5 ms, most live shots 456); the stress run is OK; the 4-bot smoke test cleared the room in 9.3 game seconds. Renderer numbers are not measured by a session; the web frame rate on a real GPU is still unread (BACKLOG).

**Assessment.** Building is deeper than at the first C2: five elements, 26 combos, and every cast now reads on screen, so a surprise is visible and not only in a log. Known weak spots: reactions differ mostly by colour (a colour-blind item is in the backlog), some clips are still plain (thin storm bolt, two-player clips, speckled orbit beads), there are four reaction flash slots, the reaction sounds do not exist yet (silent by design), and components are still given, not found (M3). Whether it is fun needs people: the weekly playtest has no building questions yet, and the clips are the first thing the owner can judge without playing.

**Recommendation: go.** The spell system does what the milestone promised and the rework closed the visible gap the owner named. Open for the owner: the real-GPU web frame rate (item 3) and the reaction sounds. If another round is wanted, the first candidates are the backlog's visual items and a building question in the weekly playtest.

## Out of scope

- **M3:** collecting components through rewards; relics (including ones that change components or the budget); staffs and their basic attacks; several rooms; the door rule; the run lifecycle; the pause menu; enemy scaling by player count; balance reports.
- **M4 onward:** replacing placeholder art with the chosen style, beyond the golden examples.
- **M5:** saving builds and the codex screen.
- **A later milestone:** dialogue and in-run story events, once there is a place to show them.
- **Not planned:** spell effects on wizards beyond friendly-fire damage.
- **Backlog:** cross-player spell linking.

## Self-critique against docs/DESIGN.md

An independent review with fresh context checked this document before it merged. Its findings and what changed are in `docs/DECISIONS.md` ("M2 design review").

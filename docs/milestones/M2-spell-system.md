# M2: Spell system

**Goal:** make spell building the heart of the game (docs/DESIGN.md, pillar 1: few components, many combinations). The 18 starting components (5 forms, 4 elements, 6 modifiers, 3 triggers) are built as data on small base classes, a spell is assembled from them as form → element → modifiers → trigger with a trigger holding another spell, and a complexity budget keeps every spell inside the performance limits. Each player builds in their own corner panel and nobody waits for anyone (pillar 2). The stress benchmark starts gating the daily build, the art direction call picks the game's look, and the Spells and Story areas open to contributors.

**Status (2026-10-21):** started by the owner ("Start milestone 2"), which is the **go** verdict at C1 (#97) after two iterate rounds. M1's done-when items that are still open carry into M2 (see "Carried over from M1"), the way M0's dry runs carried into M1.

**Done when:**

1. **Validators pass:** every component `.tres` and the reaction table pass the content validator (`core/spells/validator.gd`), run by `tests/content/spells/test_validators.gd` in `ci/build/build.sh --quick --tests`. A broken fixture of each kind fails it with a message that names the file, the field and the fix.
2. **20+ combos work:** `tests/content/spells/test_combos.gd` builds at least 20 named spells from the combo catalogue (below), casts each in a headless test arena with four players, and checks the behaviour each one promises (for example "frost bolt, then storm bolt on the same imp: shatter"). Every one of the 18 components appears in at least two passing combos.
3. The **stress benchmark** runs in the daily build and is within budget: 4 players, 100 enemies and 1,000 projectiles on web, 200 and 3,000 on desktop, full effects, game-logic frame time under 16.7 ms on the runner. It prints `STRESS OK` (the gate is wired by the owner in `ci/`).
4. The **4-bot smoke test** passes natively and on web with built spells: bots 1–3 each fight with a random valid spell, and bot 4 idles in the full builder while the others progress.
5. M1's carried-over items are done (below).
6. The **stabilisation phase** is over: no known crash or blocker in M2's scope.
7. Checkpoint **C2** has a verdict (below).

**Opens for PRs:** Spells and Story, from the part that publishes each area's example (parts 11 and 21), not before, so no contributor copies a shape that is about to change. Art and Audio stay open. All other areas stay closed.

## Carried over from M1

The owner said go at C1 on 2026-10-21 while these were still open. They are not dropped; they are part of M2's done-when (item 5):

- The web 4-bot run and web load time (#93, #91): the owner-only `ci/` change is PR #98, waiting for the owner's merge.
- The WASM projectile timing runner (game side, Claude's): folded into part 22, the stress benchmark, which runs in the `Web Test` export the same way.
- The Style Guide page and starter kit zip (#95): also in PR #98.
- M0's dry runs and 3 daily releases in a row ([M0's list](M0-foundation.md#dry-runs), owner-run, results in `docs/LOG.md`).

## Who builds what

- **Claude** builds everything in bot-maintained and open paths: `core/`, `gameplay/`, `hud/`, `content/`, `art/`, `tests/`, `docs/`, `project.godot`, `export_presets.cfg`. One part is one session and one PR.
- **The owner** makes the changes in owner-only paths: the stress benchmark gate and its 7-day trend in `ci/build/build.sh` (part 22), merging PR #98, posting the art direction call in Discussions if the bot cannot (part 24), picking the art direction and locking it in `docs/DESIGN.md` (part 24), and the C2 verdict. Each is asked as one `owner` issue with the exact change when the part before it starts; the queue goes on meanwhile.
- **The community** adds spell components and story text once those areas open, plus art and sound. The weekly planning run turns the milestone's needs (component icons, element sounds, component descriptions) into `now` issues with a "Brief for your AI".
- **Weekly owner playtest** goes on: from the first Sunday after the builder works (part 18), the "Playtest of the week" asks about building, not only feel.

## Design decisions for M2

These fill in what the plan leaves open (also recorded in `docs/DECISIONS.md`).

### Components are data on four small base classes

- `core/base/` gets `SpellComponent` (`id`, `demo`, `display_name`, `complexity`, `icon`) and four subclasses: `FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`. A component is a `.tres` on one of them, in its own folder under `content/spells/forms/`, `elements/`, `modifiers/` or `triggers/`. A component needs a `.gd` only for behaviour the base class can't express with its fields; the starting 18 aim for at most the five forms and three of the modifiers having one.
- **Form** (bolt, beam, nova, rune, orbit): how shots leave the caster. Fields: `base_damage`, `mana_cost`, `cooldown`, `speed`, `lifetime`, `radius`, `shots`, `spread`, `motion` (straight, orbit, still), `pierce`. Beam is a ray, not a moving shot (see core/projectiles below).
- **Element** (fire, frost, storm, void): what a hit does besides damage. Fields: `status_id`, `status_duration`, `status_strength`, `damage_scale`, `tint` (a palette colour from docs/STYLE.md), plus the reactions it takes part in, which live in the reaction table, not on the element.
- **Modifier** (split, pierce, homing, chain, bigger, faster): changes the compiled numbers or adds a per-shot behaviour. Fields: multipliers and adds on the form's numbers (`damage_mult`, `speed_mult`, `radius_mult`, `cooldown_mult`, `mana_mult`, `extra_shots`, `extra_pierce`), and flags for the three behaviours the projectile manager supports (`homing`, `chain`, `split` on spawn).
- **Trigger** (on hit, on expire, timer): when the held spell fires. Fields: `event` (hit, expire, timer), `interval` (timer only), `max_fires` per shot.
- A spell has at most **one form, one element, up to three modifiers and one trigger**, and the trigger holds one more spell of the same shape. The element is optional (no element = plain arcane damage, so a fresh player can cast before choosing one); the form is required.

### The spell runtime lives in `core/spells/`

- New core service `core/spells/` (autoload `Spells`), because content components may depend only on `core/` and the player may read no spell field. It **compiles** a recipe (component ids per slot) into a `CompiledSpell` (a `RefCounted` with the final numbers, its complexity and a short description for the builder), **casts** it through `Projectiles`, and **runs triggers**: it listens to `projectile_hit` and the new `projectile_expired` and fires held spells from the shot's position.
- The player keeps calling one method: `Spells.cast(player, slot, origin, direction, mana) -> float`, the same contract as M1's `SpellBase.cast` (mana spent, or `REFUSED`). Bots call the same. The test that fails when a script outside `content/spells/`, `core/base/` and `core/spells/` reads a spell field stays and is widened to the new classes.
- Each player owns their own compiled spells and cooldowns, so the M1 problem of one shared resource holding everyone's cooldowns goes away. Component `.tres` files are shared and read-only at run time.
- `core/spells/` is not in the plan's folder layout (`core/` lists events, registry, input, ui_focus, save, base, projectiles, pools). Adding it is a detail inside `core/`, which Claude maintains; it is recorded in `docs/DECISIONS.md` and the core README.

### Hits, statuses and reactions

- `gameplay/combat` stays the only place damage happens (docs/PLAN.md: combat applies status effects and element reactions). On `projectile_hit` it asks `Spells.hit_profile(tag)` (gameplay calls core, the allowed direction) for damage, knockback, element and status, instead of the M1 per-spell profile table. `hit_tag()`, `hit_damage()` and `hit_knockback()` on `SpellBase` go away when the bolt is migrated (part 9); the field-read test moves with them.
- **Statuses** (one per element): burn (fire, damage over time), chill (frost, slow; at 3 stacks a short freeze), shock (storm, the next hit on the target jumps to one neighbour), hex (void, pulls lightly toward the hit point and takes more damage). Statuses live in `combat` as packed arrays per enemy, like its health, with no per-frame allocation. Wizards are not given statuses by player spells in M2 (friendly fire stays damage only), so a status never has to be designed for a downed friend.
- **Reactions** are data in `content/spells/reactions.tres` (on `core/base/reaction_table.gd`): when a hit of element B lands on a target with status A, the reaction runs instead of B's own status. Each reaction picks one of a few **effect kinds** that `combat` implements once: `burst` (area damage), `consume` (remove the status for bonus damage), `extend` (longer or stronger status), `spread` (copy the status to neighbours). A new element is new files plus rows in the table; it never needs a change in `combat` unless it needs a new effect kind.
- The six pairs all react, so every element has three interactions (docs/DESIGN.md asks for at least two per component): frost + storm **Shatter** (consume chill, big single hit; frozen targets take double), fire + frost **Thaw** (consume, a burst of steam around the target), fire + storm **Flare** (burst, wide and weak), fire + void **Kindle** (spread burn to neighbours), frost + void **Stillness** (extend chill into a long freeze), storm + void **Rift** (burst that pulls). Names are generic and original. The numbers are tuning, set in part 7 and retuned by playtest.
- Reaction and status feedback goes through the existing `status_applied` event and a new `reaction_triggered(player, reaction_id, position)` event (sender `combat`), heard by `feel` for a flash, a number and a sound by id (silent until Audio adds them).

### `core/projectiles` grows only what the forms and modifiers need

- **`projectile_expired(player, position, tag)`** event when a shot's life ends or it hits a wall, so on-expire triggers and the wall-hit spark (backlog) both have a source. Sent from the same packed loop, no allocation.
- **Motion modes per shot:** straight (today), `still` (rune: zero velocity, waits for a target to enter), `orbit` (circles the owner at a radius; the owner's position is pushed each step by `player` through a per-player anchor array, so the manager never looks up a node). **Homing** is a per-shot turn rate toward the nearest target in the spatial grid, checked every 4th step to keep the cost bounded.
- **`ray(player, origin, direction, length, pierce, layers, tag) -> int`** for the beam: walks the spatial grid and the wall grid along the ray, sends `projectile_hit` for up to `pierce + 1` targets, and returns how far it got. A beam is drawn by `feel` as a short-lived line from the returned length; it holds no row in the pool.
- **Chain** is not in the manager: on a hit by a chain shot, `Spells` spawns one new shot from the hit point toward the nearest other target within 96 px (a grid query the manager already offers), with one fewer chain left. **Split** is the spell runtime spawning extra shots in a fan at cast time; a split shot is an ordinary shot.
- The hit-work budget (`WORK_PER_STEP`) and the caps stay. Homing and orbit rows count toward the step's work, so a screen of homing shots degrades the same graceful way.

### The spell limits are the performance limits

- **Complexity budget:** each component has a `complexity` (1–4); a spell, including the spell its trigger holds, may total at most **12**. The builder shows it as a bar and refuses a change over the budget with the reason. Relics that raise the budget are M3.
- **Shots per cast:** at most **24** from one cast after split, nova and extra shots multiply (the compiler clamps and says so in the description).
- **Trigger depth:** a trigger may hold a spell whose own trigger holds another, at most **2** levels below the cast (depth 3 in all). The builder offers no deeper slot.
- **Trigger fires per player per step:** at most **32**; extra fires that step are dropped, not queued, so an on-hit cascade can never snowball across frames. Each trigger also has `max_fires` per shot (a timer fires at most 4 times).
- **The global projectile cap** stays 1,000 web and 3,000 desktop, dropping the oldest shot of whoever owns the most. At the cap, effects degrade (fewer particles per hit) instead of lagging; `feel` already has the particle limit.
- These numbers are first guesses for the stress benchmark (part 22) to confirm or lower. They are constants in `core/spells/limits.gd` with tests that a spell at every limit still compiles and one over it is refused or clamped.

### Building spells, without anyone waiting

- **Two prepared spells per player** (slots A and B). The new input action `swap` switches between them in combat; `cast` casts the active one. This is the "swap prepared spells" quick action from docs/PLAN.md.
- **The bag:** in M2 every player's bag holds all components found in the registry (a test bench). Collecting components is the job of `rewards` in M3, which fills the bag per player instead; the bag is a per-player list in `player`, so M3 changes who fills it, not the builder.
- **Full builder** (`hud/builder/`): opened from the overlay's "Build" entry. It expands the player's corner panel toward the middle of the screen, never over another panel; alone it may fill the screen. It shows the slot chain (form → element → modifiers → trigger → held spell), the bag filtered to what fits the selected slot, live stats (damage, mana, cooldown, shots, complexity bar) and a code-drawn mini-preview of the shot pattern (fan, ring, orbit circle, ray, rune), plus the component's one-line description from Story. Gamepad and keys only through `core/ui_focus`; the mouse acts only on P1's panel.
- **When the full builder may be used:** at any time, but it never stops the game. Between waves (the 3 s break after a clear in M1's wave pacing) the next wave **waits for players in the full builder for up to 20 s**, then starts anyway with their choices kept; the HUD shows a hammer icon on a waiting player's panel. This is M3's door rule ("players still building are waited for up to 20 seconds, then carried along") applied to the one room M2 has; M3's `flow` replaces it with the real door rule. During a wave, a player in the full builder stands still and can be hit, as in M1's overlay.
- **Quick action in combat:** the overlay gets "Drop component": pick one component from the bag into a free slot of the active spell (a free modifier slot, or the empty element slot), without the full builder.
- **Intent and result:** the HUD sends `build_change_requested(player, spell, slot, component_id)` (the M1 signature gets a `spell` argument: A, B or a held spell, by path) and `spell_swap_requested(player)`; `player` checks the change with `Spells.compile`, applies it or refuses it, and announces `spell_changed(player, spell, description)` or `build_refused(player, reason)`. The HUD shows only what those say. These are new or changed events in `core/events`, one sender each.
- Builds last for the session only; saving belongs to `core/save` in M5.

### The fire bolt migrates

- `content/spells/forms/bolt/` becomes a `FormBase` `.tres` and a new `content/spells/elements/fire/` holds fire. A player's starting spell A is bolt + fire, which plays like M1's Fire Bolt plus burn; spell B starts as bolt with no element. `SpellBase` and its tests are removed in part 9, once nothing uses them, and the spells README's example moves to the new bolt.

### Validators

- `core/spells/validator.gd` checks every component and the reaction table: required fields set, numbers in range (documented next to each field), `id` equal to the folder name, the icon present and in the manifest, no unknown status or effect kind, no reaction row naming an element that doesn't exist, and a `complexity` that fits the budget even alone. It returns a list of problems as rule, file, field and fix (the same shape as `tools/check.sh`), so a contributor's agent can act on it.
- The registry runs it at start in debug builds and pushes a warning per problem; the test fails on any. Asking the owner to call it from `tools/check.sh` (owner path) is a question in part 10; until then contributors run `ci/build/build.sh --quick --tests`.

### The combo catalogue

- `content/spells/combos.json` lists named combos: a recipe (ids per slot), what it should do in plain words, and the check the combo test runs (kills N imps in a row, hits a target behind a wall corner, triggers reaction X, never exceeds K shots). It doubles as the start of the codex (docs/DESIGN.md, "Discovery"), which is `progression`'s in M5; in M2 it is only data and a test.
- At least 20 combos by the end of M2, each component in at least two; contributors add a combo row with every new component (the spells README says so).

### Story opens with words the game shows

- `docs/STORY.md` (canon and tone, short) is written by Claude before the area opens: a self-aware, slightly comic magic world with real stakes (docs/DESIGN.md, pillar 3).
- The first story content is a one-line **description per component**, in `content/story/lore/components/<id>.json` with the fields `id`, `refers_to` (`spell:<component id>`), `title` and `text` (at most 90 characters, so it fits a corner panel). The builder shows it. A validator checks the fields, the length and that `refers_to` names real content. Dialogue and in-run events stay empty until a later milestone has a place to show them.

### Art and the art direction call

- Each component gets a 16×16 placeholder icon (hand-written SVG on the 32×32 rules of docs/STYLE.md, rects only, palette only) and each element a shot tint from the palette; forms that draw something new (beam line, rune circle, orbit trail, nova ring) get a placeholder sprite in `art/vfx/`. All listed in `art/manifest.json` as `ai`, tier `placeholder`.
- **The art direction call** (docs/PLAN.md, "Who sets the direction"): Claude writes the call (what to submit: a wizard, a crypt tile and one spell icon, in the palette and on the grid; the deadline; how voting works) and asks the owner to post it in Discussions if the bot app has no Discussions access. The community votes, the owner picks or commissions; the winner's files become the golden examples in `docs/STYLE.md` and `art/kit/golden.json`, and the owner locks the choice in `docs/DESIGN.md` ("Art direction (locked)"). Replacing the placeholders with the chosen style is spread over later milestones, not done in M2.

### Bots build spells

- `tests/bots/bot.gd` gets a builder: before a fight a fighter bot builds a random spell that compiles (seeded, so a failure can be replayed) and sends the same `build_change_requested` events a person would. Bot 4 of the 4-bot test idles in the **full builder** instead of the overlay, which is the test docs/PLAN.md asks for ("one bot that idles in the builder while the others must still progress").
- A new `tests/bots/test_spell_fuzz.gd` compiles and casts a few hundred random recipes in the test arena and fails on any error line, a broken limit or a frame over budget. Balance reports from bot runs stay M3's.

## Parts, in build order

Each part ends with tests and a green `tools/check.sh` and `ci/build/build.sh --quick --tests`, and is sized for one session and one PR. `docs/NEXT.md` holds them as tasks.

| # | Part | Delivers |
| --- | --- | --- |
| 1 | **Component base classes:** `core/base` | `SpellComponent`, `FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`, `ReactionTable` with documented fields and ranges; tests. `SpellBase` stays until part 9 |
| 2 | **Events for M2:** `core/events` | `projectile_expired`, `reaction_triggered`, `spell_changed`, `build_refused`, `spell_swap_requested`; `build_change_requested` gets the `spell` argument; the events table and area READMEs fixed to match; the `swap` input action |
| 3 | **Projectile manager additions:** `core/projectiles` | `projectile_expired` (life end and walls), per-shot motion (straight, still, orbit with per-player anchors), homing on the grid every 4th step, `ray()` for the beam; timing test extended with homing and orbit rows; the hit-work budget still bounds a step |
| 4 | **Spell limits and the compiler:** `core/spells` | `limits.gd`, `CompiledSpell`, `Spells.compile(recipe)` with complexity, shot and depth limits, clamping and a plain description; tests at and over every limit |
| 5 | **Casting and triggers:** `core/spells` | `Spells.cast(player, slot, ...)` with per-player cooldowns, split at cast, trigger runs on hit, expire and timer with the per-step fire cap, chain on hit, `hit_profile(tag)`; tests with four players |
| 6 | **Statuses in combat:** `gameplay/combat` | Burn, chill and freeze, shock, hex as packed arrays per enemy; `status_applied`; combat reads `Spells.hit_profile`; the AI respects slow and freeze; tests |
| 7 | **Reactions:** `content/spells/reactions.tres`, `gameplay/combat` | The four effect kinds, the six reactions, `reaction_triggered`; feel reacts (flash, number, sound by id); tests per reaction |
| 8 | **The five forms:** `content/spells/forms/` | Bolt (migrated), beam, nova, rune, orbit as `.tres` (plus `.gd` where needed), placeholder vfx, manifest lines; a test per form |
| 9 | **Player on the new runtime:** `gameplay/player` | Two prepared spells, `swap`, the per-player bag from the registry, `build_change_requested` checked and applied, `spell_changed` and `build_refused`; `SpellBase` removed; the field-read test widened; the 4-bot test still green |
| 10 | **The four elements and their validator:** `content/spells/elements/`, `core/spells/validator.gd` | Fire, frost, storm, void with tints and icons; the validator for all component kinds and the reaction table, with a broken fixture of each; `test_validators.gd`; the owner question about `tools/check.sh` |
| 11 | **Spells README and example; Spells opens** | The README rewritten for the component classes (fields, ranges, complexity, the combo row rule) with the bolt and frost as examples; the weekly run may now open `now` issues for spells |
| 12 | **The six modifiers:** `content/spells/modifiers/` | Split, pierce, homing, chain, bigger, faster, with icons; tests per modifier |
| 13 | **The three triggers:** `content/spells/triggers/` | On hit, on expire, timer, with icons; tests including depth 3 and the fire cap |
| 14 | **The combo catalogue and test:** `content/spells/combos.json`, `tests/content/spells/test_combos.gd` | The test arena fixture, the first 12 combos passing |
| 15 | **Builder, part 1:** `hud/builder` | The expanded corner panel, the slot chain and the bag, per-player focus through `core/ui_focus`, opened from the overlay; sends `build_change_requested`; tests with four builders open at once |
| 16 | **Builder, part 2:** `hud/builder` | Live stats, the complexity bar, the refusal reason, the mini-preview, the descriptions (empty until part 21); screenshot shots for 1 and 4 players |
| 17 | **Quick actions in combat:** `hud/panels`, `gameplay/player` | Swap shown on the corner panel (active spell A/B), "Drop component" in the overlay; tests |
| 18 | **Waiting for builders between waves:** `gameplay/flow`, `hud/panels` | The next wave waits up to 20 s for players in the full builder, then starts; hammer icon on the panel; tests with one, two and four players, one of them building; **the weekly playtest asks about building from here** |
| 19 | **Bots build spells:** `tests/bots` | Seeded random builds, bot 4 idling in the full builder in the 4-bot test, `test_spell_fuzz.gd` |
| 20 | **Combos to 20+:** `combos.json` | At least 20 combos passing, every component in two; done-when item 2 |
| 21 | **Story: `docs/STORY.md`, the first lore, Story opens** | STORY.md (canon and tone), one description per component in `content/story/lore/components/`, its validator, the Story README's example and schema; the builder shows them |
| 22 | **Stress benchmark:** `tests/benchmark` | The stress scene (4 bots with built spells, 100/200 enemies, 1,000/3,000 shots, full effects) in the editor, the Linux Test and the Web Test exports (this includes M1's WASM projectile timing runner), `BENCH:` lines and `STRESS OK`; the limits in `limits.gd` confirmed or lowered from its numbers; the `ci/` gate asked as an owner issue |
| 23 | **Component icons and art pass:** `art/`, `content/spells/` | Icons for all 18, element shot tints and the vfx checked together in one screenshot sheet against docs/STYLE.md; Art `now` issues for replacements |
| 24 | **Art direction call** | The call text, the owner issue to post it and to lock the winner in DESIGN.md; nothing in the game waits on it |
| 25 | **Stabilisation and C2** | Only bug fixing, polish and performance until no known crash or blocker remains; then the C2 issue with a build link, bot data (fuzz and stress numbers, which combos bots pick), Claude's honest assessment and questions |

Parts 1–5 are the engine, 6–14 the content, 15–18 the builder, 19–22 the proof. Spells opens at part 11, after the classes, the validator and the example exist; Story opens at part 21. The art call (24) can be done earlier if a session has spare room, since it only needs the game's current look.

## Combo catalogue (first draft)

The combo test (parts 14 and 20) starts from these; each line is a recipe and what it must do.

1. **Bolt + fire:** the M1 fire bolt plus burn; an imp keeps losing health after the hit.
2. **Bolt + frost, then bolt + storm on the same target:** Shatter.
3. **Nova + fire + bigger:** one ring hits every imp around the caster.
4. **Beam + storm + pierce:** a ray through three imps in a line.
5. **Rune + frost + on hit → nova + frost:** a trap that freezes a crowd (Stillness only with void; here two chills stack).
6. **Orbit + void:** circling shots hex anything that touches the wizard.
7. **Bolt + split + homing:** five homing bolts that find five imps.
8. **Bolt + chain + storm:** a hit jumps to the next imp, and shock jumps once more.
9. **Bolt + on expire → nova + fire:** a delayed blast where the bolt ends, also at a wall.
10. **Bolt + faster + pierce:** a sniper line through the room.
11. **Beam + frost + bigger:** a wide ray that chills a lane.
12. **Orbit + fire + timer → bolt + fire:** a ring that throws fire bolts outward every half second.
13. **Nova + void + on hit → bolt + fire:** Kindle spreads burn through a hexed crowd.
14. **Rune + storm + chain:** a mine whose blast jumps between imps.
15. **Bolt + frost + on hit → beam + storm:** a hit that fires a ray from the target (Shatter on the chilled one).
16. **Bolt + split + split + bigger:** refused or clamped by the shot limit, with the reason.
17. **Nova + fire + on hit → nova + fire + on hit → nova + fire:** depth 3 runs, depth 4 is not offered.
18. **Orbit + frost + pierce:** a frost shield that chills everything it passes.
19. **Beam + void + homing:** the ray bends toward the nearest imp.
20. **Bolt + storm + timer → nova + storm:** a bolt that pulses shock along its path (Flare when a burning imp is near).
21. **Rune + fire + bigger + on expire → nova + frost:** a fire trap that ends in a Thaw burst.
22. **Four players, four elements on one imp:** every reaction can fire, nothing breaks the per-step trigger cap.

## Checkpoint C2

The question is: **is building spells fun and deep, with surprising combos?** The owner decides, with Claude's assessment from bot data (which recipes bots and players build, the fuzz and stress numbers), the weekly playtest answers and player feedback. Verdicts: **go** (M3 starts), **iterate** (rework the weak parts, at most 2 rounds) or **pivot**. The owner has 7 days to answer; without an answer Claude defaults to iterate (docs/PLAN.md, "Go/no-go checkpoints").

## Out of scope

Collecting components through rewards, relics (including ones that change components or the budget), staffs and their basic attacks, several rooms, the door rule, the run lifecycle and the pause menu (M3); enemy scaling by player count and balance reports (M3); spell effects on wizards beyond friendly-fire damage; saving builds and the codex screen (M5); replacing placeholder art with the chosen style beyond the golden examples (M4 onward); dialogue and in-run story events (a later milestone with a place to show them). Cross-player spell linking stays in the backlog.

## Self-critique against docs/DESIGN.md

An independent review (fresh context) checked this document before it merged; its findings and what changed are in `docs/DECISIONS.md` ("M2 design review").

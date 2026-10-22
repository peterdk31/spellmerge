# Decisions

Why things were decided, so they aren't reversed by accident. Newest first.

## 2026-10-22: The stress scene (M2 part 24)

- **Real game, topped-up shots.** The scene is the real Flow, Combat, spell runtime and Feel with four bots, not a stand-in. Spells alone never make 1,000 or 3,000 shots, so each physics step the runner adds plain filler shots (fixed seed, owned by the players in turn) up to the target; the manager's cap is set to the target, so dropping the oldest shot is part of the load. Enemies are added whenever fewer than the target stand, with 120 health instead of the imp's 20, so the crowd lasts. Wizards stay protected with full mana: it is a stress scene, not a balance test.
- **Pass means the load was real, not fast.** `STRESS OK` needs enemies and shots at 90% of the target, every bot casting, no refused build and no logged error. Frame time only prints (`BENCH WARNING:` past 16.7 ms p95), as PLAN says ("Gates are sparse"). The build runs a short version (`test_stress.gd`); the full one is `stress.gd`. Part 25 puts it in the exports.

## 2026-10-22: The first lore (M2 part 23)

- **One JSON file per component** (`lore/components/<id>.json`, keys `id`, `about`, `text`) rather than one big file: contributors add content as new files and conflicts cannot happen. `about` is there so relic, item and enemy lore can share the schema later without a new folder rule.
- **The registry reads the lore** (it is the one script allowed to load from computed paths); `Spells.component_description` asks it, so the HUD still reads no component field. Invalid lore files are never given out.
- **Validator in `core/story/`**, not in the spells validator: story belongs to its own area. It runs in tests and as debug-build warnings (`tools/check.sh` is owner-protected, see #140). A missing lore file for any spell component is reported as `missing-lore` in the debug-build warnings, but the test does not fail on it: a Spells PR must not fail CI for a rule outside its area. The builder shows an empty note and Story or Claude fills the gap; `content/spells/README.md` lists the file as a step.
- **Descriptions state the real numbers only where they are fixed** (eight shots, three orbs, up to twice, every half second, up to four times); other effects are said in words so a retune does not make them lie.

## 2026-10-22: Story canon (M2 part 22)

- **Short, with seven fixed points.** `docs/STORY.md` fixes only what the game already shows or needs (the wizards as guild apprentices, the build-from-parts magic, the four elements' characters, the crypt, imps, the stakes, relics). Biomes after the crypt, bosses, hub and dialogue are left open, so later writing and contributors add canon instead of fighting it.
- **Tone reading of pillar 3:** dry rather than silly, with the danger never made small. Descriptions follow the 60-character limit that part 23 validates.
- **Component names are quoted from the registry** (Bolt, Frost, On Hit, ...), so lore and builder agree.

## 2026-10-22: Combos to 20+ (M2 part 21)

- **Nine rows added, two changed from the draft.** Draft row 13 (nova + void, on hit → fire *bolt*) became a fire *nova*: a held bolt starts inside the hexed imp and, since the 0.1 s exclusion ends before it has crossed the imp, hits it again and is used up, so it never reached the imps behind (the known issue in `docs/BACKLOG.md`). Draft row 21 (fire rune that ends in a frost nova, Thaw) became a fire rune that bursts into a fire nova on expiry: a rune has no pierce, so its first hit uses it up and it never expires on a target. A rune that expires needs imps standing just outside its reach, which the nova then burns. Both stay faithful to the pillar (small parts, deep results) and avoid pinning a bug.
- **Two drafts are not rows yet.** Draft rows 16 (clamp refusal) and 17 (depth 3) stay with `test_spells_cast.gd` and `test_triggers.gd`, which already cover them; rows 20 to 24 beyond the two-player one are not needed for the two-per-component rule. More rows can be added any time.
- **The two-per-component rule is a test.** `test_every_component_is_in_two_combos` reads a `COMPONENTS` list in the test; a new component is added to it together with its rows, as the spells README asks; a second test compares the list with the registry, so a missed component fails. Rows for chain, pierce, faster and on expire also have a control: the same row without that component must fail a check. The control showed that a bolt that hits ends by hit, not by expiry, so "Seeking frost burst" now pierces and bursts where its flight ends.

## 2026-10-22: The build break

**Decided by:** Claude (M2 part 19).
- **`BUILD_BREAK` (12 s) replaces `NEXT_WAVE_DELAY`.** Flow's timer is fixed: no builder, open overlay or build request holds the next wave back or brings it forward, for 1, 2 or 4 players (co-op rules 1 and 2). 12 s is the design's first guess, tuned at C2.
- **New event `build_break_started(seconds)`, sender `flow`, listener `hud`,** sent right after `room_cleared`. The HUD may only show what events say and `Flow.build_break_left()` is not an event, so the HUD counts down by itself from `seconds` in `_process`. It is display only: if it drifts, the wave still starts on Flow's clock. `wave_started` ends the line.
- **The hammer is drawn in code** (`hud/widgets/hammer_icon.gd`), not an art file: no asset, no manifest line; the art pass (part 26) may replace it.
- **The break line is drawn over the builders,** on a dark backing: four open builders cover the whole top middle, and the countdown is the one thing that must stay visible.

## 2026-10-22: The quick view and quick actions

**Decided by:** Claude (M2 part 18).
- **A wave is "in progress" from `wave_started` to `room_cleared`.** `panels.gd` folds every builder into the quick view on `wave_started` and unfolds it on `room_cleared`, `run_started` and `run_ended`. No new event: the break between waves is exactly the time after `room_cleared` until the next `wave_started`, which part 19 (`BUILD_BREAK`) makes longer without changing this.
- **New event `active_spell_changed(player, slot)`, sender `player`.** The HUD may only show what events say, and `swap` changed a private variable. The wizard sends it when it appears and after each swap; the corner panel shows "Spell A"/"Spell B" from it, and the quick view and overlay follow it.
- **The HUD turns `swap` presses into `spell_swap_requested`** in `panels.gd` (like the `overlay` toggle, from the press counter). Presses are dropped, not kept, when the player is in a menu (`swap` is captured there like `cast`), down, not joined or outside a room. At most two requests per poll.
- **Drop component offers the empty element slot and the first free modifier slot only** (`hud/widgets/drop_choices.gd`, shared by the overlay and the quick view). The form and the trigger need the full builder; the design says "a free modifier slot, or the empty element slot". It always acts on the active spell, level 0, with `build_change_requested(player, [active], slot, id)`; `player` checks it like every request.
- **The quick view keeps the slot chain read only and hides tabs, held levels, bag and info panel.** It follows the active spell. Its drop list has no icons and tighter rows, and the overlay's list is two columns that replace the three buttons while it is shown, so the longest list (spell B: four elements and six modifiers) fits each player's quarter of 640×360. Tested with four players.
- **`Build` pressed during a wave opens the quick view.** The full builder is for the break, as in the design.
- Left for later: the hammer icon on a building player's panel is part 19.

## 2026-10-22: The M1 fire bolt moves to `legacy/fire_bolt`; the new bolt takes the id `bolt`

**Decided by:** Claude (M2 part 10).
**Decision:** The M2 form `bolt` lives in `content/spells/forms/bolt/` with id `bolt` (the id equals the folder, and the design's recipes say `bolt`). The M1 `SpellBase` bolt, which `flow` hands to the wizards and `combat` profiles until part 11, moved to `content/spells/legacy/fire_bolt/` with id `fire_bolt`; `Flow.DEFAULT_SPELL_ID` and the tests that named it follow. Part 11 deletes the `legacy/` folder with `SpellBase`.
**Why:** two resources cannot share an id (the registry keeps one), and migrating the bolt in place would have broken the playable game for a whole task.
**Forms' numbers (first tuning, from the M2 design table):** bolt 1 complexity (damage 5, 5 mana, 0.35 s), the others 2: beam (4 damage, pierce 1, reach 240, 0.8 s), nova (8 shots of 3 over 360°, reach about 60 px, 1 s), rune (8 damage, waits 8 s, radius 14, 1.2 s), orbit (3 orbs of 3 damage at 36 px turning 4 rad/s for 3 s, pierce 4, 3.5 s). The stress benchmark and playtests will retune them.
**Not seen in the game yet:** the beam's `lifetime = 0.15` is the time the drawn beam stays on screen (the hit itself is instant), for the part-26 art pass. The four vfx sprites in `art/vfx/` (beam, nova ring, rune, orbit orb) are not wired to anything yet, so nobody should expect them in the game.

## 2026-10-21: Gates are sparse; hard gates notify the owner

**Decided by:** the owner ("Gating should in general be sparse. Development should be prioritized to continue instead of gating stuff. Of course a hard gate can happen, in that case I should be notified").
**Decision:** written into docs/PLAN.md, "Gates are sparse".
- The hard gates are a broken build (build, tests, smoke tests, error lines) plus the security and copyright rules. Each one already mentions the owner when it trips: a broken build's Daily log post, a failed revert, and the alarm issues.
- Budgets warn with likely fixes: web load time (above), download size (`build.sh` no longer fails over 40 MB or 300 MB), frame time and the M2 stress benchmark (a warning, not a gate, when part 25 adds it). The 10% frame-time regression no longer reverts.
- The stable channel still promotes only builds that are within budget. Nightly builds always ship.
**Consequence:** a budget can be broken for a while. The warning in the build log, and a task once it repeats, are what bring it back.

## 2026-10-21: A slow web load warns, it never fails the build

**Decided by:** the owner ("loosen up a bit on the load timing. It should not hinder development ... it should just give warnings and potential fixes").
**Decision:** `smbot.websmoke --warn-load 10` prints `WEB LOAD: N s` and, over 10 s, a `::warning::` that lists likely fixes: the zip size, big new assets, work at start (autoloads, `Registry.scan`), trimming demo content, and a slow runner. The web smoke test still fails on errors, exceptions and a missing expected line. `--max-load` is gone. The 10 s load in docs/PLAN.md stays a target, not a gate.
**Consequence:** a slow web start shows up in the daily build log and never reverts a merge. Acting on the warning is a normal task, filed when it repeats.

## 2026-10-22: Reactions (M2 part 8)

**Decided by:** Claude.

- **Six reactions, twelve rows.** The table is looked up by (status on the target, element of the hit), so each pair has a row for each direction and both carry the same `reaction_id`. In the other direction the reaction works on the other status: Shatter eats shock when frost hits a shocked enemy, Kindle spreads hex when fire hits a hexed one. Without that, a pair would only react one way round.
- **Two new row fields:** `pull` (Rift) and `consume_status` (Thaw uses the burn up). The design's "consume, then a burst" for Thaw is a BURST with `consume_status`, so no fifth effect kind. A burst includes the struck enemy.
- **Order:** the reaction is picked from the statuses the target had when the shot arrived (first of burn, chill, shock, hex with a row for that element); the hit's damage lands first; the reaction runs only if the enemy lived, and replaces the hit's own status. A frozen enemy counts as chilled. A shock is still spent by the hit, so the shock jump and a shock reaction can both happen.
- **No chains:** reaction damage and spread statuses go through `hit` and `apply_status`, never through `projectile_hit`, so a reaction can't set off another one.
- **Stillness** freezes a chilled enemy for 2 s and lengthens a freeze by 2 s (a long freeze, as designed); on hex it adds 2 s and +25 %.
- **Limits (review fix).** Flare, Rift, Kindle and Stillness leave the status on the target, so without a limit every later hit of that element would react again. Decided: each enemy reacts at most once per `REACTION_WAIT` (0.5 s); a hit inside the wait does its own status instead. A per-enemy wait rather than consuming the status, because Kindle must keep the burn it spreads and Stillness must keep the freeze it extends. EXTEND is capped (`MAX_FREEZE` 4 s; other statuses 8 s; hex and shock extra damage 100 %; burn rate 20), so rapid fire cannot freeze for ever or stack hex without end. Shatter doubles whenever the target is frozen (not only on the chill row) and then ends the freeze. Feel plays a reaction's sound and shake at most once per 0.3 s per id, and skips a name already rising within 40 px.
- **Numbers** (Shatter 6, doubled when frozen; Thaw 3 in 40 px; Flare 2 in 56 px; Rift 2 in 48 px with a 120 px/s pull; Kindle 48 px) are first tuning for the playtest.
- **Feel** gets a flash, a burst, the reaction's name as a rising label and the sound `reaction_<id>` from the preset (`reaction_colors`, `reaction_sound_prefix`). The "number" is the name: the damage already shows through `damage_dealt`.

## 2026-10-22: The validator (M2 part 9)

**Decided by:** Claude.

- **It is a class of static functions fed with resources** (`SpellValidator`), not a scanner. The registry is the only script that loads from computed paths, so it hands the validator what it found (`validate_spells()`); a test can hand it any fixture the same way.
- **Known statuses are a list in the validator** (burn, chill, shock, hex), because `core/` may not depend on `gameplay/combat`. A test compares it with combat's `REACTING_STATUSES`. `freeze` is left out: no element sets it.
- **Duplicate ids are seen through the registry,** which keeps the first file and used to only warn; it now also remembers the duplicates under `spells`, and the validator reports them. Ids are unique across all four kinds because they share the `spells` folder.
- **Beyond the design's list,** a form must have the number its motion uses (speed, orbit radius or ray length), an element with a status needs a duration, a homing or chain modifier needs a strength and a timer trigger needs an interval: a component that does nothing is a mistake, not a choice. Reaction rows get ranges of their own (`REACTION_RANGES`), wide sanity bounds like the component ones.
- **Resources in `spells` that are not components** (M1's `SpellBase` bolt, until part 10) are skipped.
- **`tools/check.sh`:** asked of the owner (issue #140). The validator already runs in `ci/build/build.sh --quick --tests`; `check.sh` needs only git and Python, and Godot may only be run through `build.sh`.

## 2026-10-21: Spell component base classes (M2 part 1)

**Decided by:** Claude.

- **The ranges live in code.** Each class has `ranges()`, and `SpellComponent.range_problems()` checks them. The validator (part 9) and the docs then read the same numbers, so they can't drift from a separate table. The ranges are wide sanity bounds, not balance.
- **The beam is a fourth motion, `RAY`,** next to `STRAIGHT`, `STILL` and `ORBIT`, with the extra fields `ray_length` and `orbit_radius`, each used by one motion only. The alternative, deriving the ray length from speed × lifetime, hid a meaning in two unrelated fields.
- **Split is `shot_mult`, not a behaviour.** The `Behaviour` enum is only `NONE`, `HOMING` and `CHAIN`, the two that need code at run time; `behaviour_strength` is the turn rate or the number of jumps.
- **Reactions are sub-resource rows (`ReactionRow`) in one `ReactionTable`.** Neither has an `id`, so the registry never registers them, which a test checks.

## 2026-10-21: M1 closes on the owner's go; M2 starts

**Decided by:** owner ("Start milestone 2", in a session on 2026-10-21).
**Context:** C1 (#97) had two iterate rounds; the second (2026-10-20) queued a round-2 playtest report. Still open from M1's done-when: the web 4-bot run (#93, in the owner's PR #98), M0's dry runs and 3 daily releases in a row. The Claude-side WASM projectile timing runner was also unfinished.
**Decision:** the C1 verdict is **go**. M1 is closed and M2 starts with its design document. The open items are not dropped: they carry into M2's done-when (item 5), as M0's carried into M1. The WASM runner is folded into M2 part 25. The two round-2 playtest tasks are dropped from the queue; the weekly playtest goes on and asks about building from part 20.
**Consequence:** the web 4-bot run is still unproven while M2 is built, until PR #98 merges.

## 2026-10-21: M2 design choices the plan left open

**Decided by:** Claude (details in `docs/milestones/M2-spell-system.md`).

- **The spell runtime is a new core service, `core/spells/` (autoload `Spells`),** not in the plan's `core/` list. Content may depend only on `core/` and the player may read no spell field, so compile, cast and triggers must sit in core. `combat` asks `Spells.hit_profile(tag)` (gameplay → core).
- **Tags carry player, slot, depth and a generation ring of 8,** so shots in flight keep their old profile after a rebuild.
- **Six reactions from four effect kinds in a data table;** every element reacts with the three others, more than DESIGN.md's "at least 2 interactions".
- **Limits:** complexity 12 per spell (with the table of provisional costs), 24 shots per cast, trigger depth 3, 32 trigger fires per player per step. The stress benchmark confirms or lowers them.
- **The bag holds every component in M2;** `rewards` (M3) fills it per player instead.
- **The full builder is used in the break between waves, which becomes a fixed `BUILD_BREAK` (12 s)** with a countdown. When a wave starts, an open builder folds into a quick view. Nothing waits for a builder (see the review below).
- **Spells opens at part 15** (all four kinds, the validator and the example exist), **Story at part 23.**

## 2026-10-21: M2 design review

**Decided by:** Claude, after an independent review with fresh context against `docs/DESIGN.md` (docs/PLAN.md, "Autonomy").
**Findings and changes:**

- **Blocking, fixed:** the first draft held the next wave up to 20 s for a player in the full builder. That made the others wait on one player (pillar 2) and borrowed M3's door rule. Now the break has a fixed length, the wave never waits, and the hammer icon is a display only.
- The full builder was allowed during waves, against PLAN ("cleared rooms and the hub"; quick actions in combat). Now it is used in breaks and folds into a quick view in a wave.
- The draft relied on a nearest-target query that `core/projectiles` doesn't have. Part 3 now adds `nearest_target` and `targets_in`.
- Elements came after the parts that need them. They now come right after casting (part 7), and the validator is its own part.
- `flow` holds a `SpellBase`. Part 11 now moves it to start recipes and updates ARCHITECTURE.md.
- Tag lifetime after a rebuild, the type of the `spell` path (`PackedInt32Array`), and the origin, direction and source exclusion of held spells are now specified. Triggered spells send no `spell_cast`.
- Combos 5, 6, 8, 15, 19 and 20 promised things the rules don't do; they are reworded or changed. Combos 22 and 23 and a split in 12 make every component appear twice. Provisional complexities are given, and every combo fits under 12.
- Spells opened before modifiers and triggers existed; it now opens at part 15.
- The path-tier wording now leaves out the owner-only docs. The projectile manager and the stress parts are each split in two. Nits fixed: modifiers may repeat, ids are unique across kinds, the reaction table has no id, cooldown is the cast time, and there are no particle counts to validate yet.

## 2026-10-21: Animated torches, 2.5D pillars and impact particles (owner `/claude` on #4)

**Decided by:** Claude, on the owner's four requests.

- **Torches: engine animation, no script.** Rooms carry no scripts, so a torch is a scene (`content/rooms/crypt/decals/torch.tscn`) of a bracket, an `AnimatedSprite2D` flame (4 frames, played in an 8-step order, 5 fps) and an additive glow made of a static disc plus an `AnimatedSprite2D` core (3 sizes, 9-step order, 6 fps). The two `SpriteFrames` are shared by all eight torches; the room only sets `speed_scale` (0.85 to 1.25) and a start `frame` per instance, so no two torches share both. STYLE gives animated tiles 4 fps; the flame runs at 5 because 4 fps looked like a slideshow in the sheet. Looked at in the `crypt_pillars_torches` screenshot: the flame is small at game scale but reads as a flame; further tuning waits for a human playtest. The glow is two flat stepped discs at low opacity, per STYLE's "one or two flat rings"; no `PointLight2D` (it costs a lighting pass per torch for the same look). 16 animated sprites cost the engine's animation step and a redraw per frame change.
- **Other decals: nothing else to animate.** The crypt room has no braziers or candles; skulls, rubble and doors are floor or wall detail that does not move. Braziers or candles, when they are added, copy `torch.tscn`.
- **Pillars: split sprite, no y-sort.** The world is a plain `Node2D` with the room, wizards and enemies as siblings, so y-sorting would also have sorted the floor, walls and rubble against the wizards (the room's floor decals would pop over a walking wizard). Instead the pillar is two 32×32 sprites: the base (shaft's lower half and plinth) on the footprint in `Pillars` at z 0 and in tree order under the characters, and the top (capital and upper shaft) one tile higher in `PillarTops` at z 5, over every character. A wizard behind the pillar is covered by the top; one in front is drawn over the base. The cost is that a wizard behind the pillar is covered yet still targetable, so `PillarTops` is 60% opaque (`modulate`): in the `crypt_pillar_walk_behind` screenshot the wizard behind it shows through and the top still reads as a capital. A wizard beside the pillar can still have its head slightly under the top. Feel's bursts sit at z 19 (above the tops, below the flashes) because Feel draws before the room; a refused shot born inside a wall shows no impact, and an impact only aims the damage that follows in the same physics frame. Collision is unchanged (one tile). The pillar sprites left `Walls` because the test there ties every sprite to a collision rectangle of the same size.
- **Impact event: one signal, `projectile_impact(player, target, position, direction)`.** The hit burst needs the shot's direction, and `projectile_hit` (read by `combat`) and `damage_dealt` carry none; changing their signatures would have touched their listeners and tests. A new event sent by `core/projectiles` just before `projectile_hit` carries it, and the same event with `target = null` reports a shot ending on a wall (`Feel` cannot reach into the manager). `Feel` keeps the latest character impact and uses it for the `damage_dealt` of the same target that follows at once, then forgets it; damage with no impact (contact hits) stays the old round puff.
- **Spray numbers (all in the preset; seen in the `impact_*` screenshots, not yet by a human playtest).** Cone 35° to each side, 1.4× the puff's speed, 8 particles (a burst is still 8, so `PARTICLE_LIMIT` 48 holds), size ±6% per damage point from 5 (the bolt), clamped to 0.7 to 1.6. Ember for enemies, the wizard's reticle colour for a wizard (the node in group `players` with an `index`, so `Feel` names no player script). A kill keeps the hit's burst and its colour.
- **Wall impact numbers.** One burst of stone chips (`#a39fb8`, 60° cone back off the surface, wall-normal not known so it is the reverse of the shot's heading) and one spark sprite in the shot's colour (4 extra sprites, 0.1 s). Chips only start while fewer than 4 of the 6 bursts are in use, so four players firing at a wall never take the last two bursts from hits on characters.
## 2026-10-21: Enemy shots shrink to radius 3.5 (owner `/claude` on #4)

**Decided by:** Claude, on the owner's request.

- `attack_radius` goes 5 to 3.5. One number sets both the hit circle and the drawn size, so sprite and collision stay matched. The orb is about 10 px wide, readable at 32 px scale, and smaller than a wizard's default bolt (radius 4). A wizard's hit circle is 8, so a 12 px sidestep clears the shot; the telegraph lane narrows with it. Each shot is checked against all players the same way, so co-op dodging is unchanged. Not playtested by a human: This partly undoes the bigger hit circles of the 2026-10-20 hit-box fix (#5) for enemy shots only: the wizard's circle of 8 plus the shot's 3.5 is still a body-sized hit. The 10 px orb inside its quad was not checked by eye. The next playtest report should ask whether shots feel like they pass through the wizard.

## 2026-10-20: Foundation review: data over constants (owner `/claude` on #5)

**Decided by:** Claude, from the owner's request to make the foundation solid, easy to extend and art easy to swap.

- **The review found the layering sound** (events, registry, dependency direction, content by folder, art in scenes) and three spots where a change would have needed a code edit: `Feel` loaded three art files by path, `Flow` fixed the room, enemy, spell and wizard scene as constants, and the wizard's art contract was not tested. Fixed those only; no restructuring.
- **Art paths live in data.** `FeelPreset` has `spark_texture`, `bolt_texture` and `hostile_texture` (defaults preloaded, so a preset that sets nothing still draws). A re-skin is a preset. Scenes already held every other texture.
- **`Flow` takes ids and the wizard scene as fields** (`room_id_to_play`, `enemy_id_to_play`, `spell_id_to_play`, `wizard_scene`), defaulting to the M1 content. A room picker or loadout sets them; unknown ids start no run, as before. The old `ROOM_ID`, `ENEMY_ID` and `SPELL_ID` consts became `DEFAULT_*`.
- **Not done, on purpose:** wave data on rooms, splitting `player.gd`, enemy attack patterns, the M2 spell components. Each is large and belongs to the feature that needs it (`docs/BACKLOG.md`, "Foundation"); doing them now would be guessing the shape.
- **Tests do not check looks** (already the rule in `tests/README.md`): the art tests check strip sizes and wiring only, so a redraw cannot break them. The feel test that compared against fixed art files was replaced by one that swaps the preset's textures.

## 2026-10-20: Hit circles sit on the body, and are bigger (owner `/claude` on #5)

**Decided by:** Claude, on the owner's bug report: hitboxes too small, shots seem to pass through sprites.

- Cause: sprites are drawn 14 px above the node origin (the feet), but every hit circle was centred on the origin, so a shot through the drawn body at body height was up to 14 px from the circle's centre and often missed. Radii were also small (imp 8, wizard 6, shots 4).
- Fix: `Projectiles.add_target` takes an `offset`; `Combat.register_enemy`/`register_player` pass it on. Both the imp (`Ai.hurt_offset`) and the wizards (`Flow.PLAYER_HIT_OFFSET`) use (0, -12). Radii: imp 8 to 11, wizard 6 to 8, bolt 4 to 5, imp shot 4 to 5. The imp's shot and telegraph now start at its body, not its feet. Contact damage compares the hit circles too (each node's origin plus its offset), so it is consistent with the shots. With both at (0, -12) the offsets cancel and the contact range is only the larger radii: 14 px (6 + 8) became 19 px (8 + 11), about 36% more. The balance tests did not need new `BALANCE:` numbers.
- Not changed: the shot's drawn size (3x its radius) and the walls (still a point check). Tuning by feel waits for the playtest.

## 2026-10-20: Art direction before M2, and tests that break one at a time

**Decided by:** Claude, from the owner's `/claude` on #102 (art first, smaller isolated tests).

- **Art stays inside M1** (one enemy, one room); nothing from M2 was started. The final style is still the M2 art direction call; these are better placeholders under the same rules in `docs/STYLE.md`.
- **Depth without new colours.** The floor is darkened by the scene (`modulate` on the `Floor` sprite) and soft shadows are `Polygon2D` strips in the scene, not baked into art, so the art keeps the palette rule (no partial transparency). The top and bottom walls get a new tile with a lit top face; the side walls keep the old brick tile, because a lit cap repeated down a side wall would look like steps.
- **Telegraph.** The line is dashed by a repeating 8×8 tile, with a `Lane` strip (16 px wide, the shot's hit width plus margin) and a `Tip` arrowhead, all children of `Telegraph` so one `modulate` fades them together. `ai.gd` fits them to the shot's real reach, so the picture still shows where the shot goes. Width range 4-8 px (was 3-6).
- **Tests.** Every new test script extends `tests/support/suite.gd`: each `test_*` method is its own test, with its own setup, so one failure names one behaviour and cannot hide or break the next. Tests check behaviour and wiring, not how things look (no pixel colours, no count of decorations): an art or tuning change should not need a test change unless a rule is broken. `test_svg_art.gd` is the one place that checks the look rules (style rules for SVGs, manifest entries), data-driven over every file, so new art is covered without writing a test. Old test files are moved to the new shape when they are touched, not in one go (a mass rewrite would be a large, risky change with no new coverage); the list is in `docs/BACKLOG.md`.
- **Tests I did not move out of `test_ai.gd`:** chase, target choice, knockback, the damage test: they still work and are not coupled to art.

## 2026-10-19: Muzzle flash: size 0.5 (a small flare, not a blast)

**Decided by:** Claude, from the owner's bug report on #102.

- `muzzle_flash_size` goes from 2.4 to 0.5 (the `@export_range` minimum was already 0.1). With the 32 px `hit_spark.svg`, `MUZZLE_STRETCH` 1.8 and the 1.5× growth while it fades, the flash is 29 px long at the start and 43 px at its largest, about the size of the 32 px wizard. Before it was 138 px growing to 207 px.
- The stretch stays, so the flash still reads along the aim. The death puff has its own size (`death_puff_size`) and is unchanged.
- `test_feel.gd` fails if the `punchy` muzzle flash is longer than 48 px at any step.

## 2026-10-18: Wave pacing: waves in the same room, +2 enemies a wave, downed wizards stand up between waves

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **Growth is +2 enemies per wave, capped at 24** (`WAVE_GROWTH`, `WAVE_MAX`). Wave 1 stays the fixed 8-imp list the balance and 4-bot tests were tuned on; later waves carry on round the room's spawns (stacked with the existing diagonal offset). Linear, because the bots (which never dodge) already struggle with 1 and 2 players at wave 1; faster growth would end runs at wave 2. The cap keeps the enemy count (and the shot count) inside the performance budgets. Real scaling by player count and level belongs to `difficulty` in M3.
- **3 s between a clear and the next wave** (`NEXT_WAVE_DELAY`): enough to see the clear, not long enough to idle. The world, the wizards and their positions are kept (a "same room" feel); only the shots in flight are cleared.
- **Downed wizards are back up at the start of the next wave** (with `revive`, 50 health, plus the 2 s join protection for everyone), so one mistake does not leave a player watching for the rest of the run, and nobody waits (pillar). Health is otherwise not refilled: a wave is a real cost. If this proves too hard, a heal belongs to rewards (M4), not here.
- **Quick restart: `RESTART_DELAY` 2.0 s to 1.5 s.** A lost room goes back to wave 1. The restart still builds a new world and sends `room_entered`; the wave counter restarts with `wave_started(1)`.
- **New event `wave_started(wave)`** (sender `flow`, heard by `hud`), so the HUD never reads `flow`. `room_entered` is not repeated for a new wave; `room_cleared` is sent for every wave.
- **HUD:** a plain "Wave N" label at the top middle (between the P1 and P2 panels), shown from the first `wave_started`, hidden when a run ends. Not tuned by playing (not possible here).

## 2026-10-18: Enemy readability: shape and brightness, a second draw batch, a hit never cancels a windup

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **Enemy shots get their own batch, not a second texture in one.** A multimesh has one texture; an atlas needs a shader and per-instance data. A second `MultiMeshInstance2D` (one layer above) costs a second buffer of the same size and no extra loop. Enemy shots are untinted so they stay the brightest thing on screen; the player's comet keeps its 45% tint. Shape differs (round and spiked against a comet with a tail), so colour is not the only signal (docs/STYLE.md, "Readability").
- **Poses are textures, not new frames in `idle.svg`.** STYLE says one strip per animation, named by it. `ai.gd` swaps `Sprite.texture` and `hframes` and pauses the `AnimationPlayer` for the pose; the exports `windup_texture` and `hurt_texture` are optional, so another enemy without them behaves as before.
- **A hit does not cancel the windup.** Stun-locking would let one fast shooter cancel every imp, and the telegraph would stop meaning "a shot comes". The imp still has knockback (Combat) and Feel's flash; the hurt pose shows on top for 0.25 s and the telegraph line stays.
- **The windup flips by progress², not by time.** The pose slows at the start and speeds up, so "about to fire" is readable without a number. It is 5 flips-worth before the last 20%, where the bright frame is held (with the brighter colour), so the flash never goes above about 5 bright-dark cycles a second, however many imps wind up at once.
- **Cost of the second batch.** The enemy batch reserves `cap` instances and uploads its whole buffer when any enemy shot exists (Godot's `MultiMesh.buffer` takes all of it, like the player batch), so memory for draws doubles and a frame with enemy shots writes up to about 144 KB more on desktop. Accepted: the earlier decision showed the bulk write is cheap; a smaller enemy cap or a sliced upload is a later option if the web build needs it.
- **Not done:** no sound cue (audio is not in M1), no windup frames for the other directions (the imp is drawn from the front).

## 2026-10-18: Revive is automatic proximity in `coop`: 2 s hold, 48 px, 1.5 s protection

**Decided by:** Claude (owner `/claude` on #102, C1 round 2 task 1).
**Context:** `Player.revive(reviver)` existed but nothing called it, so a downed wizard stayed down until the room restarted. The earlier decision gave "how" to `coop`.
**Decision:** `coop` runs the revive (`step_revive`, from `_process`). No button: a standing wizard who stays within `REVIVE_RANGE` (48 px, centre to centre) of a downed one fills that wizard's progress in `REVIVE_HOLD_TIME` (2 s). "Holding" is staying put; it works the same on every device and needs no input action, and the reviver can still dodge or fire from there. Per downed wizard: the nearest standing wizard in range is the reviver, and a second helper does not speed it up (simple and predictable; two revives of different wizards run at the same time, for any indices 0-3). When nobody is in range the progress drains at twice the fill rate, so a quick step away to dodge costs a little and walking off loses all of it. A downed wizard never revives another. Leaving or a new room clears the progress.
**Numbers and why:** 2 s is long enough to be a decision (a wave of imps fires about that often, so reviving in the open is a risk the team must accept) and short enough that a downed player is not left out for long (pillar: nobody waits). 48 px is a body and a half (32 px sprite) so the reviver must really be beside the body, but a dodge (220 px/s) crosses it in 0.2 s so help is easy to give. 1.5 s of protection (the dodge's is 0.125 s, a joiner's 2 s) is enough to get out of the shot that downed the wizard; 2 s+ would let a revived wizard walk through fire. Revive health stays 50.
**How the downed player sees it:** a new event `revive_progress(player, progress)` (sender `coop`, heard by `player`), sent when the progress changes (0 when it stops or is done). The wizard draws a ring over its hat: a dark ring with an empty track and an arc that sweeps clockwise from the top, with a white cross in the middle. Progress reads from the arc length, not the colour (the arc is also in the player colour). The HUD may not look at wizards, and an event keeps `coop` from touching the wizard's drawing.
**Deliberate exception:** `coop` preloads `gameplay/player/player.gd` to read `index` and `is_downed()` and to call `revive`/`protect` on typed wizards, not just by `has_method`. This is the one direct link between two gameplay areas, kept because revive is the one place `coop` must act on a specific wizard every frame; everything else still goes through events.
**Consequence:** the numbers are untested by play (no person here); tune `REVIVE_*` in `coop.gd`. A team that wants a pause for revive-while-fighting will find the 2 s costly with many enemies, which is the intended tension. Co-op remains playable: there is no way to be blocked by another player.

## 2026-10-18: Juice leftovers: a `wizard_cast` event, a copied sprite for deaths, a vignette read from health

**Decided by:** Claude (owner `/claude` on #102, the "C1 juice, leftovers" task).
**Context:** The four things left from the juice pass each needed a node or a position that Feel may not look up.
**Decision:** (1) A new event `wizard_cast(player, wizard)`, sent by `player` right after `spell_cast`, hands Feel the caster node, so the squash needs no lookup. It is a second event rather than a changed `spell_cast`, which `combat` and the bots already use. The squash is thin and tall (the opposite of a hit's) for 0.1 s, 15%, without the white flash. (2) The muzzle flash gets rotation, a 1.8× stretch along the aim and the player's light colour from a table in `feel.gd` that repeats the reticle colours (`docs/STYLE.md` is the source). (3) The enemy is still freed at once (`combat` and `flow` depend on it); on `enemy_died` Feel copies the dead node's `Sprite` (texture, frames, region, offset, flip, world scale) into one of 8 pooled sprites, white, that widens, collapses and fades over 0.25 s. A full set takes the oldest slot. (4) The vignette lives in the HUD and is driven by a drop in `player_stats_changed` health, not by `damage_dealt`, because that event names a node, not a player index, and the HUD must not look nodes up. It is one shared overlay (one screen, four wizards) that is strongest toward the hurt wizard's corner, so "who" is shown by position and not by colour alone (the panel's HP number also falls).
**Review round (same day), after looking at crops of each effect at 4× from the screenshot script:** the muzzle flash was a thin blue sliver that was gone in 2 frames, so it is now 0.1 s at 2.4× (it still reads small beside the bolt in a still taken on a slow software renderer; at 60 FPS the first frames are larger). The big death puff (2.5×) hid the imp, so it is 1.6× for 0.14 s and the white death copy is drawn above it. The cast squash is 20% for 0.12 s (visible on the 32 px wizard). The vignette, shared by up to four wizards, adds per hit `0.7 × (share of max health lost / 0.25, 0.2 to 1) / √players`, so a four-player brawl peaks well under the limit (tested), the corner bias is 0.15 to 1 (was 0.45 to 1) and the middle of the screen is clear; the `enabled` flag turns it off for comfort. The death copy starts at the sprite's rest scale, and a cast during a dodge makes no squash because the dash look owns the scale then.
**Consequence:** a new enemy dies with the animation if its sprite node is named `Sprite`. Values are in `feel_preset.gd` (defaults, not `punchy.tres`, which sets none of these); nobody could play it in this session. If the cast squash feels too strong, lower `cast_squash` in `punchy.tres` only. The vignette numbers are constants in `vignette.gd` (the HUD may not read a gameplay preset).

## 2026-10-18: Juice lives in Feel and reaches sprites only through the event's target

**Decided by:** Claude (owner `/claude` on #102).
**Context:** The owner wants punchier hits, casts and deaths. Feel may not call other areas, and `damage_dealt` carries the hit node.
**Decision:** Feel flashes and squashes the `Sprite` child of the `damage_dealt` target (the same convention `ai.gd` and `player.gd` already use), with a shared white shader material it removes again. Feel stores instance ids, because a typed or plain array cannot hold an enemy freed in the same frame. Casts get a muzzle flash and a camera kick from `spell_cast`; the caster's own squash was left out, since the event has no node and a lookup would break the area rule. Hit-stop keeps the defaults (0.04 s hit, 0.15 s rest, so about 21% of real time slowed in a four-player fight, under the 30% test limit); extra punch comes from flash, squash and shake. Deaths stop 0.09 s. Everything else is tuned in `punchy.tres`.
**Consequence:** a new enemy gets the flash and squash if its sprite node is named `Sprite`. Flash and squash replace `Sprite.material` for 0.08 s, so a scene must not rely on a material there. Feel multiplies its squash onto the scale it finds; if the owner sets `scale` meanwhile (the dash look), Feel adopts that as the base and returns to it. Past 16 sprites reacting at once, a hit skips its flash and squash.

## 2026-10-18: Placeholder animation uses fewer frames than the table, and the staff is drawn by the game

**Decided by:** Claude (owner `/claude` on #102).
**Context:** The owner asked for readable placeholders, a visible staff and simple idle, walk and dash frames "if it fits in one session". `docs/STYLE.md` lists 4 idle, 6 walk and 4 dodge frames, but "use fewer frames rather than more", and a session that cannot run scripts has to write every pixel rect by hand.
**Decision:** idle 2 frames (2 fps), walk 4 (8 fps), dash 3 (16 fps, plays once, the last frame is held), imp idle 2. The strips are placeholders (tier `placeholder`); M2 replaces them. The staff is not in the wizard strips: the shots start at the muzzle along the aim, so a staff painted into the sprite pointed the wrong way for any aim but one. `staff.svg` is drawn from the hand, turned along the aim (the pixel art is rotated at runtime, which is only acceptable for a placeholder). Frames are composed with whole-number `translate` on rects, which `docs/STYLE.md` allows, so one hat or body is shifted per frame instead of redrawn.
**Consequence:** the playback speeds are constants in `player.gd` (`IDLE_FPS`, `WALK_FPS`, `DASH_FPS`), not set in the scene, and differ from the table (idle 2 fps, walk 8 fps); they move to the scene with the final art. The frame counts in the table are targets for final art, not checked. `player.gd` reads the frame count from the strip's width, so a better strip with more frames works with no code change.

## 2026-10-17: C1 changes no wave or feel value (M1 part 25)

**Decided by:** Claude.
**Context:** The task says to tune from bot logs and playtest answers. There are no playtest answers, no owner feedback and no open bug. The only data is the new `tests/bots/test_wave_balance.gd` run: bots that never dodge clear the wave of 8 imps alone with 20 of 100 health left, and with four players lose 20 health each.
**Decision:** keep every value (imp health 20, bolt damage 5 and cooldown 0.35, mana, move and dodge numbers, `WAVE`). One bot run does not say how moving, dodging and casting feel, which is the C1 question; a change made from it would be a guess, and player scaling is `difficulty`'s job in M3. The probe stays so the next round (iterate) starts from numbers.
**Consequence:** the owner's playtest answer decides what to tune; the C1 issue asks for it.

## 2026-10-17: The web 4-bot test starts from the page config, in a `Web Test` export (M1 part 23)

**Decided by:** Claude.
**Context:** Web has no command line and `JavaScriptBridge` is banned, so the game can't read a URL query. The shipped `Web` preset excludes `tests/*`.
**Decision:** a fifth preset `Web Test` (copy of `Web`, no exclusion, `build/web-test/`, never packaged), kept in step by `test_export_presets.gd`. The start argument comes from the `args` entry of the page's `GODOT_CONFIG`, which `websmoke.py` can inject when it serves `index.html`. The main menu now looks for `--four-bot` in `OS.get_cmdline_user_args()` and `OS.get_cmdline_args()`, because the web config may not include a `--` separator. The `ci/` change is asked as an `owner` issue.
**Consequence:** unverified in a browser until the owner makes the change; the task is reported blocked until then.

## 2026-10-17: The projectile caps are not validated; the draw code stays (M1 part 22)

**Decided by:** Claude.
**Context:** The task required timing `spawn`, `update_draw` and `_hit_test` at the cap before relying on 1,000 (web) and 3,000 (desktop). The numbers are in `docs/LOG.md`.
**Decision:** `update_draw` stays: spawning at the cap (about 1 µs) and the draw copy (0.3 and 0.9 ms) are cheap, and `multimesh.buffer` is one bulk write, so uploading only the first `drawn` instances would save nothing measurable. The hit test is different. In a hostile scene (fast shots, all piercing and starting inside 100 packed targets, each hit sending a signal) one step costs about 50 ms at 1,000 shots and 150 ms at 3,000, natively, and still 25 ms and 75 ms once the targets are remembered. Real play is far from that (the 4-bot run peaks at 10 shots), but the caps cannot be called safe. The caps are left as they are for now only because nothing in M1 gets near them; the work to bound the hit test and set the caps from the numbers is queued in `docs/NEXT.md`, with the rule that the web cap drops if the WASM step is over 8 ms. The probe prints and gates nothing, as the task said.
**Consequence:** the caps are provisional, not validated, on native or WASM; the queued tasks decide them.

## 2026-10-17: The 4-bot test runs in a separate `Linux Test` export (M1 part 21)

**Decided by:** Claude.
**Context:** The shipped presets exclude `tests/*`, so the exported game has no `four_bot_smoke.gd`. Dropping the exclusion would put test scripts in every release.
**Decision:** a fourth preset, `Linux Test`, in `export_presets.cfg` (Claude-maintained) with no exclusion and its own path `build/linux-test/`; the release presets are unchanged. It is a copy of `Linux` (including `custom_features="full"`, so the test runs the same feature set as the shipped desktop build) and must stay one: `tests/smoke/test_export_presets.gd` fails if the two differ in anything but name, `runnable`, `exclude_filter` and `export_path`. The step that exports it and runs the test is in `ci/build/build.sh` (owner-only), so it is asked as an `owner-change` owner question with the exact lines. The step greps the run's log for `SMOKE OK`, so a release template that ignores `--script` fails the step instead of passing without running the test.
**Consequence:** until the owner adds the step, the test runs only through `build.sh --quick --tests`. If the exported binary refuses `--script`, the fallback is an autoload reading a user argument (`-- --four-bot`), a game-side change.

## 2026-10-17: The export starts the 4-bot test from the main menu (#80)

The `Linux Test` binary hangs on `--script` while the autoloads start, so it can't run a `SceneTree` script. The checks are now a node (`tests/smoke/four_bot_runner.gd`); the main menu adds it when the user argument `--four-bot` is given and `ResourceLoader.exists` finds the file. Why the menu and not an export-only autoload: autoloads live in `project.godot`, shared by every export, and a missing autoload script would break the normal builds. The menu holds a literal-path `load` behind that check, and `tests/*` is excluded from every shipped export, so there the argument only logs a warning. Cost: a small hook in `hud/` that mentions `tests/`.

## 2026-10-17: The owner inbox

**Decided by:** owner.
**Context:** Questions for the owner were written into `docs/BACKLOG.md` ("Needs an owner decision"). Nothing notified the owner, there was no clear way to answer, and sessions never learned the answer.
**Decision:** a session that needs the owner puts the question in `owner_questions` in its structured output (development, revision and weekly planning). The publish step opens one issue per question, labelled `owner-question` (plus `owner-change` when the answer needs an owner-only change, with the exact change), mentioning the owner, with the options, Claude's recommendation and what happens meanwhile; a question already open under the same title isn't asked again. The owner answers with `/claude <answer>` in the issue; the next session carries it out and its PR says `Closes #N`. The Daily log lists the open questions. Sessions still decide everything they can themselves (docs/PLAN.md, "Never waiting for humans").
**Consequence:** `docs/BACKLOG.md` no longer holds owner questions. Its four open ones were answered in the same change (below).

## 2026-10-17: Unit tests run through `build.sh --tests`

**Decided by:** owner.
**Context:** Sessions were refused when they ran the Godot binary directly, and `build.sh` ran only the boot smoke test, so no unit test had ever run.
**Decision:** `ci/build/build.sh --quick --tests` runs every `tests/**/test_*.gd` in its own Godot process after the import and smoke test, and fails if any test fails or logs an error. Sessions may run exactly that command, the only way they run Godot. `--quick` alone is unchanged, because the implement job runs it before Claude starts. The daily build doesn't run the tests yet: a first run passed 5 of 17, so making them pass is first in the queue, and the bot asks the owner to make the daily build run them once they all pass.

## 2026-10-17: The bot app's Client ID

**Decided by:** owner. The workflows mint the bot's token with `client-id: Iv23lirdyRvc0KC6625s` (public, from the app's settings page) instead of the deprecated `app-id`. The `BOT_APP_ID` secret is no longer read; it can stay until `setup.sh` stops checking for it.

## 2026-10-17: Opening web links, narrowly

**Decided by:** owner.
**Context:** The feedback button and the main menu's Contribute button need `OS.shell_open`, a banned API.
**Decision:** it is allowed in one file only, `core/links/links.gd` (bot-maintained, closed to outside PRs). There the rules check allows `OS.shell_open(URLS[key])` and nothing else, requires `URLS` to be a `const`, refuses any change to it at run time, and refuses any address that isn't the project's own (`github.com/peterdk31/spellmerge`, `peterdk31.github.io/spellmerge`, `peterdk31.itch.io/spellmerge`). Everywhere else, and for every other process call, the ban stays.

## 2026-10-17: HUD theme and player panels (M1 part 18)

**Decided by:** Claude (details the plan left open).

- **One new event, `player_stats_changed(player, health, max_health, mana, max_mana)`, sender `player`.** The HUD may only show what events say, and no event carried health or mana. It is sent when a wizard appears, on a health change, and when mana crosses a whole number (about 10 a second per regenerating player, none when nothing changes). Rejected: the HUD reading the wizard nodes (a direct call into gameplay), and a per-frame event.
- **"Downed" is derived from health 0**, not from `player_downed`/`player_revived`, so a restart that builds new full-health wizards clears it with no extra event.
- **The panels are an autoload scene `Hud`** (a `CanvasLayer`), so neither `flow` nor the menu has to add them and areas keep not calling each other. They show for a joined player after `room_entered`. Rejected: `flow` adding the HUD to its world.
- **The theme is the project theme** (`gui/theme/custom`), so every control, including the main menu, uses it. Player colours are theme type variations, not per-control overrides. Rejected: a theme set on each scene root.
- **No information by colour alone:** the panel says "P1".."P4", "HP"/"MP" with numbers, and the words "DOWN" and "MENU". Health uses Fire and mana Spark from `docs/STYLE.md`; no new colour was invented.
- **The corner panels are display-only.** They take no input; "on `core/ui_focus`" means they show `UIFocus.opened`/`closed` as the "MENU" word. The overlay that uses `UIFocus` to take input is part 19.

## 2026-10-17: Co-op (M1 part 17)

**Decided by:** Claude (details the task left open).

- **`flow` adds and removes the wizards; `coop` only announces.** Coop turns `device_joined` / `device_left` into `player_joined` / `player_left` (once per real change) and flow, which owns the world and the wizards, listens. This keeps "areas never call each other"; the events table lists `flow` as a listener of both.
- **Friendly fire lives in `core/projectiles` as a flag** (`Projectiles.friendly_fire`, default off, set by `Coop.set_friendly_fire`), because spells (content) fix their own hit mask and must not read gameplay settings. A player's shot spawned while it is on also hits `LAYER_PLAYER`; targets carry an `owner` (`add_target(..., owner)`, set by `combat`) so a wizard is never hit by its own shot. Damage is the same pipeline as any hit. In memory only until `core/save`.
- **Camera:** `coop` drives the world's `Camera2D` (found after `room_entered`): centre of all wizards' bounding box, zoom out (never in past 1, never out past 0.5) until all fit with 48 px of margin, easing at 6 per second. Downed wizards count, so a body can be found. `flow` sets the camera's limits to the room, and `coop` makes the zoom agree with them: the zoom never goes below `max(view.x / room.x, view.y / room.y)` and the centre is clamped the way Godot does, so the shot never shows empty space. In `arena_01` (640×384 for a 640×360 view) that means no zoom-out at all: the view is pushed in from the edges instead (a wizard at the top or bottom wall may sit up to 12 px from the view's edge). Padding the limits was rejected, since it would show void beyond the walls. Each frame the zoom is also lowered, if needed, so everyone is inside a view centred where the camera is now, not where it is heading (zooming out is immediate, zooming in is eased). Mid-run joiners spawn on the free spawn farthest from enemies and wizards and are invulnerable for `Player.JOIN_PROTECTION` (2 s). Shake only touches `offset`, so the two do not clash.
- **Coop no longer listens to `player_downed`** (the old README line): the camera fits downed wizards too, so there was nothing to do with it. It listens to `room_entered` instead.
- **Revive is not part of this task** and stays in the backlog (nothing calls `Player.revive` yet).
- A player leaving when the only standing wizard remains while the rest are down starts flow's restart timer; one joining while all are down cancels it. With nobody left the run just waits.

## 2026-10-17: Feel (M1 part 16)

**Decided by:** Claude (details the task left open).

- **One autoload, `Feel`, listening to three events and sending none.** It cannot change damage: it never calls `Combat` or a wizard (tested by running the same hits with and without it).
- **Hit-stop is `Engine.time_scale`** dropped to 0.05 (not 0, so physics still steps) for 0.04 s on a hit and 0.07 s on a death or a downed wizard, counted in real time from `Time.get_ticks_usec()` (not delta divided by the time scale, so other uses of `time_scale` cannot skew it; `Feel` resets it to 1.0 when it leaves the tree). The longest stop wins, so four players hitting in one frame never stack. Same numbers for every player: the event's player index is ignored.
- **Hit-stop rest (review fix):** after a plain hit's stop, plain hits cannot stop the game again for 0.15 s (`hit_stop_rest`), so a four-player bolt fight spends about 21% of real time slowed, not most of it (a test holds it under 30%). Deaths and downed wizards ignore the rest: they are rarer and are the moments worth a punch.
- **Particle limit:** `PARTICLE_LIMIT = 48` live hit particles in total, as 6 pooled `CPUParticles2D` bursts of 8 (`core/pools`). With the pool empty, a hit burst is skipped (degrade by dropping, like the projectile cap), but a death takes over the burst closest to ending. A killing blow sends `damage_dealt` then `enemy_died` at one spot: the death upgrades the hit's burst (1.6x speed, life and size) and cuts the hit sound, so a kill costs one slot and one sound and looks bigger than a hit. The downed event carries no position, so a downed wizard gets stop, shake and sound but no burst.
- **Where bursts live (review fix):** under the `Feel` node, `top_level` so they sit in world space. Not under the current scene: `Flow` frees the world on Play and on every restart, which would have killed the pool.
- **Shake** is a trauma value (0–1, squared into pixels, 6 px at most) on the current `Camera2D`'s `offset` (looked up again whenever a shake starts; the old camera is put back at rest), so the co-op camera (part 17) can move the camera's position freely. The setting `Feel.shake_enabled` is kept in memory only: the hard rules ban file loading and saving calls, so saving it waits for `core/save`, and so does the settings screen that flips it. Hit-stop is not part of that setting.
- **Sounds:** `hit`, `enemy_death` and `player_downed` by id from the registry, 8 voices round-robin, silent on `null`. `player_downed` was added to "Audio needs" in the backlog.
- **Presets** are `FeelPreset` resources in `gameplay/feel/presets/`; the first is `punchy.tres` (the script's defaults). Feel also sets `Projectiles.texture` to `art/vfx/fire_bolt.svg` if nothing set it (DECISIONS part 13 left this to feel).
- Values are first guesses to tune at C1. No Godot binary in the session: the test has not run.

## 2026-10-17: Arena glue (M1 part 15)

**Decided by:** Claude (details the task left open).

- **Flow builds the whole world and makes it the current scene.** The menu only sends `play_requested(0)`; flow adds one `Arena` node (room scene, `Camera2D`, wizards, enemies), makes it `current_scene` and removes the menu at once. A restart removes the old world from the tree at once (so its enemies leave `Combat` in the same frame) and frees it.
- **Wizards: one per player slot with a device.** If Play is pressed by the mouse and slot 0 is free, the keyboard joins as P1. A request from another slot with nobody joined starts nothing (with a warning). Joining mid-run is `coop`'s job (part 17).
- **Flow reaches `Combat`, `Projectiles` and `PlayerInput` through the autoload nodes**, as the AI does, since `core/events` has no event for "register this wizard"; it sets bounds for the projectiles and clears them on a run. Flow preloads `content/wizard/base/wizard.tscn` by a literal path: the wizard has no registry resource yet. The room, the enemy and the bolt come from the registry by id (`arena_01`, `ember_imp`, `bolt`).
- **The wave:** 8 imps at the six enemy spawns (two spawns used twice, the repeat 14 px along the diagonal), a constant in `flow.gd`. 8 × 20 health is 32 bolt hits; it is a first guess for C1.
- **Restart after 2 seconds** from the last wizard going down (`RESTART_DELAY`, under the 3 s limit); a revive cancels it; a cleared room never restarts. After `room_cleared` nothing happens yet (no reward or next room until M3); listed in the flow README.
- **A second `play_requested` during a run is ignored.** `stop_run()` returns flow to idle (tests; later the run area).

## 2026-10-17: Work resumes when a usage limit resets; late scheduled runs don't repeat

**Decided by:** owner.
**Context:** On 2026-10-17 a usage limit stopped development at 03:28 with a reset at 05:10, but GitHub's hourly schedule didn't fire again until hours later, so no session ran. The same night the daily run was started by the catch-up at 04:55, and GitHub then fired the 03:00 schedule at 07:35, so it built and released twice.
**Decision:** when the develop gate or a session's finish job sees a back-off, it starts `resume.yml`, which waits until just after the reset and starts `develop`. `daily.yml` and `weekly.yml` skip a scheduled run when another run since their due time is running or succeeded.
**Consequence:** work stops only as long as the limit lasts. A waiting `resume` run shows in the Actions list; a newer request replaces it.

## 2026-10-17: The room (M1 part 14)

**Decided by:** Claude (details the task left open).

- The room is built from repeated `Sprite2D` tiles plus one `StaticBody2D`, not a `TileMapLayer`: a tilemap needs a `TileSet` resource and packed cell data that cannot be written or checked without Godot in a session. Rejected: a hand-encoded tilemap, which would likely fail to load unseen. Revisit when a tileset resource exists (M3).
- 20×12 tiles (640×384 px): the camera frame is 640×360, and part 17's shared camera zooms out for four players. Six single-tile pillars give cover. The two centre pillars touch at a corner and form a diagonal block; the test flood-fills the 32 px grid to check that every spawn can be reached (it does not measure lane widths).
- Spawn positions live twice, as `Marker2D` nodes in the scene and as arrays in the `.tres` (the base class fields); the test checks they match. `flow` reads the `.tres`.
- One entry (bottom, next to the players) and one exit (top) door; the doors are markers only, closed doors are the wall. Door logic is M3.

## 2026-10-17: The fire bolt (M1 part 13)

**Decided by:** Claude (details the task left open).

- **`bolt.tres` uses `bolt.gd`, a script that extends `SpellBase`,** so everyone who loads it gets a `SpellBase`, but the firing code is content, not `core/base`. It reaches only `Projectiles` (a `core/` autoload; tests set `projectiles`), looked up once and kept. **Content never calls `gameplay/`** (the spells and combat READMEs agree): the bolt answers `hit_tag()`, `hit_damage()` and `hit_knockback()` (new `SpellBase` methods), and `Combat` reads them through `core/registry` the first time it hears `spell_cast` for that spell id and sets the hit profile itself. A spell that is cast without `spell_cast` (nothing sends it today but the player) has no profile, so its hits do nothing; the test covers this. `_fire()` now returns `bool`; `false` (no projectile manager, or `spawn` returned -1) makes `cast()` return `REFUSED` with no mana taken and no cooldown started.
- **No separate `core/pools` pool for shots.** The projectile manager's packed arrays are already a fixed-size pool (a free-slot list, no allocation per spawn), so wrapping it in `Pool` would add a layer for nothing. `Pool` stays for node-based things (hit sparks, part 16).
- **The tag is `BOLT_TAG = 1`** (the imp's attack tags start at 1000). The hit profile is set by `Combat` on the first `spell_cast` of the bolt, with knockback 120 px/s. The values (5 mana, 0.35 s cooldown, 5 damage, 220 px/s, 1.2 s) are first guesses for C1 tuning: four bolts kill a 20-health imp.
- **The "no field reads" test is a text scan** of every `.gd` outside `content/spells/`, `core/base/` and `test_*.gd` files (tests build fixtures by setting fields): a variable named like a spell followed by a field name, or `.mana_cost`, `.cooldown`, `.lifetime`, `.display_name`. It is a heuristic; a self-check in the test makes sure the scanner still catches what it should.
- The bolt has no texture yet: the projectile manager draws tinted quads. Setting `Projectiles.texture` to `art/vfx/fire_bolt.svg` belongs to feel (part 16), where `docs/NEXT.md` lists it.
- **Cooldowns are on the shared resource.** `Registry` hands out one `bolt.tres`, so all holders share its cooldowns (kept per player index, so four players do not clash). `flow` (part 15) calls `reset_cooldowns()` on a new run. A restarted `Combat` simply learns the profile again on the next `spell_cast`. A test shows two holders of the shared resource block each other until `reset_cooldowns()`.
- `Registry` finds the bolt as `spells` / `bolt` (a folder is a direct child of `content/`; the `.tres` may be at any depth below); the test checks it.

## 2026-10-17: The enemy and its AI (M1 part 12)

**Decided by:** Claude (details the task left open).

- **`ai.gd` is the script on the enemy scene's root** (a `CharacterBody2D`), as the wizard scene does with `player.gd`; `gameplay/` stays script-only. The spawner sets `data` (the `EnemyBase`) before adding the node. The scene does not point back to the `.tres` (that would be a resource cycle), so speed and health come from `data` and the attack numbers are exports on the root. The exports are scene-level, set in the enemy's `.tscn`, not per spawn.
- **The attack is a shot**, not a lunge: Combat's contact damage is always on, so it cannot be telegraphed. The imp has `contact_damage = 0` and its damage is `attack_damage` (an export in `ai.gd`) through a hit profile for the enemy's `attack_tag`, set by the AI in `_ready` as 1000 plus a number from `data.id` and `attack_damage` (so another enemy type, or the same one with another damage, does not overwrite the profile; two ids could still collide by chance, which Combat's tag-changed warning would show, and the spawner (part 15) may take over the tags). The shot belongs to `Events.NO_PLAYER` and uses `LAYER_PLAYER`. The telegraph is a 0.75 s windup standing still, a flash and a `Telegraph` line as long as the shot's real reach (`attack_speed * attack_lifetime`) that grows wider and brighter with progress (2 to 4 px, alpha 0.5 to 1; placeholders, to check at 640×360 with four players in the part 25 playtest); the aim is locked at the start, so stepping aside works. First guesses, for the C1 tuning.
- **The AI talks to `Combat` and `Projectiles` through the autoload nodes** (found by path, replaceable in tests, as `player.gd` does with `Events`), not through events: `core/events` has no event for "register this enemy" or "spawn a shot", and the part 11 design already has the mover add `consume_knockback_step`. Revisit if a spawner (`flow`, part 15) should register enemies instead. Leaving the tree unregisters the enemy from `Combat` (so a room swap leaves no hidden target); it is not registered again on re-entry, so spawn a new enemy instead.
- **Targets:** every node in the `players` group (`player.gd` joins it in `_ready`), or an explicit `targets` list; the nearest one that is not downed, rechecked every 0.5 s (staggered by instance id), at once when the current target is lost, and at once on `player_downed` only for enemies whose target was that player (the others keep their stagger, so a death is not a one-frame spike). With no target (all downed, nobody joined) it still looks only every 0.5 s. The group read allocates a small array twice a second per enemy; if 200 enemies show it in the part 22 probe, share one list refreshed by `flow`.
- Combat's `register_player` now also adds the wizard as a projectile target (see the part 11 notes).

## 2026-10-17: Combat (M1 part 11)

**Decided by:** Claude (details the task left open).

- **Combat owns the tag table.** The earlier note said the spawner keeps the table from `tag` to damage and `combat` looks it up there. Combat keeps the table (changed in part 13: the bolt does not call `Combat`; Combat fills the table from the spell's `hit_tag()` etc. after `spell_cast`, see "The fire bolt"). Tag 0 stays "no tag".
- **Enemy health lives in combat,** in packed rows, not on the enemy node: `register_enemy(node, health, hurt_radius, contact_damage)`; the AI (part 12) and the enemy scene hold no health. Death sends `enemy_died` and frees the node.
- **Wizards decide their own damage.** Combat sends `damage_dealt` and the wizard takes it. It skips the event (no hit-stop or shake for nothing) when the wizard answers `is_invulnerable()` or `is_downed()`, found by `has_method` on registered wizard nodes. Wizards are not knocked back in M1; the player owns its movement.
- **Contact damage** is a distance check per enemy row and registered wizard (4 at most), once per `CONTACT_COOLDOWN` (1 s) per wizard, since wizards have no invulnerability after a hit. First guesses, for the C1 tuning.
- `damage_dealt` carries the requested amount, not the health actually removed (overkill is not trimmed).
- Knockback speed is `direction * strength` (a hit overwrites any earlier push) and falls by `KNOCKBACK_DECAY` per second; Combat never moves the enemy: it only keeps the velocity (`get_knockback`), and the node that moves the enemy (AI or enemy base, part 12) adds `consume_knockback_step(enemy, delta)` to its own `move_and_slide()` each physics frame, which also fades it. That way walls and parent transforms are respected and only one node owns the enemy's movement.
- **(Part 12 addition.)** `register_player` also makes the wizard a projectile target on `LAYER_PLAYER` (and `unregister_player` removes it); without that an enemy shot could never hit a wizard. Part 11 left this out.
- Re-registering an enemy also updates its projectile target radius. A freed enemy is dropped in `step()`; the projectile manager prunes its own freed targets (tested). Contact hits are sent after the enemy loop and `hit()` re-finds its row after `damage_dealt`, so listeners may change registrations. A tag whose profile changes is replaced with a warning; the spawner picks the tags.

## 2026-10-17: Player health, mana, downed and cast (M1 part 10)

**Decided by:** Claude (details the task left open).

- **One cast method, no fields read.** `SpellBase.cast(player, origin, direction, mana)` returns the mana spent, or `REFUSED` (-1) if it is cooling down or too costly; the player subtracts what it returns. The spell keeps its own cooldown per player index (a 4-slot array), run by `tick(player, delta)` each step, so one spell resource can be shared by four players. The event id comes from the method `spell_id()`, not the field. Part 13 overrides `_fire()`; its test checks that nobody outside `content/spells/` and `core/base/` reads a field.
- **Cast is held, not tapped:** while `cast` is held the spell's cooldown sets the rate. A player with an overlay open is captured, so `cast` is hidden and nothing fires.
- **Numbers (placeholders to tune in part 25):** 100 health, 100 mana, 10 mana per second, 50 health after a revive. A downed wizard does not regenerate mana, cannot move, dodge or cast, and ignores later hits; its dodge and spell cooldowns freeze too. A revived wizard gets no invulnerability window (a hit on the same frame can down it again); `coop` (part 17) may add one. Hits during a dodge's invulnerability do nothing.
- **Revive is a method, `revive(reviver)`:** who revives and how (standing next to a body) belongs to `coop` (part 17). The player sends `player_revived`.
- **Damage:** the player listens to `damage_dealt` and takes it when `target` is itself; `combat` (part 11) decides when to send it.
- **Sound:** the `AudioStreamPlayer` is made once in `_ready()` (only inside the tree); the stream is looked up by id at each cast and `null` plays nothing. Only the silent path is tested (no `.ogg` can be made in a session).

## 2026-10-17: Placeholder art (M1 part 4)

**Decided by:** Claude (details the task left open).

- Four wizard files, one per player colour (`wizard_p1_idle.svg` to `wizard_p4_idle.svg`), not one file tinted in code: a tint multiplies colours, so the result would leave the palette. `wizard.tscn` lists the four textures in `textures` and `player.gd` shows `textures[index]` on `Sprite` in `_ready()`. The files differ only in the three ramp colours.
- Filtering off: Godot's texture importer has no filter option, so the `.import` files keep the defaults. Filtering is set by the project (`rendering/textures/canvas_textures/default_texture_filter=0`, nearest) and the wizard's `Sprite` also sets `texture_filter` to nearest. Size is exact because the SVG is 32×32 and `svg/scale` is 1.0.
- The `.import` files and their uids were written by hand (the session had no Godot, and the md5 in each `path` follows Godot's rule: the md5 of the `res://` path). Godot rewrites them if they differ.
- SVGs are written rect by rect, with outlines inside the grid, as `docs/STYLE.md` asks. The session could not run scripts or render, so the pictures were checked by reading the rects, not by eye; the no-overlap rule and the look (a screenshot) are still unchecked. The crypt floor uses the darkest stone as its base so it reads apart from the wall.
- The wizard staff carries a Spark gem (light source) and the imp uses only Fire, Bone and Spark, so no player colour appears on an enemy. The floor tile is flat; the wall tile has the lit and shaded edges.
- Sounds are not made here: `cast`, `hit` and `enemy_death` are under "Audio needs" in the backlog.

## 2026-10-17: Pools and the projectile manager (M1 part 7)

**Decided by:** Claude (details the task left open).

- **Pool:** GDScript has no generics, so a pool is typed by its factory Callable and the caller casts `acquire()`. It makes all objects up front and never grows: at capacity `acquire()` returns `null` and the caller degrades. A growing pool would allocate mid-frame, which the budgets forbid.
- **Projectiles are rows in packed arrays** (struct of arrays), simulated in `_physics_process` and drawn by one `MultiMeshInstance2D`, tinted by player colour (STYLE.md base colours; enemy shots Fire). A texture can be set later for the real bolt art.
- **Targets are registered, not searched for:** `add_target(node, radius, layer)`. The manager reads their positions each step into a grid of 64 px cells, so it depends on no gameplay class and `core/` keeps its dependency direction. Hit layers (`LAYER_ENEMY`, `LAYER_PLAYER`) let enemy shots hit players and player shots hit enemies, and a shot's owner can be `NO_PLAYER`. Friendly fire (part 17) means a player shot with `LAYER_PLAYER` in its mask.
- **Hits test the path, not the point:** each step's segment against the target circle. The grid cells searched are those the segment touches, widened by the shot's radius and the largest target radius, so neither fast shots nor big targets (bosses) are missed. Among the targets a segment touches, the nearest along the path is hit first and the event carries the closest point on the path. A piercing shot remembers its last 3 hit targets, so overlapping enemies are hit once each (a fourth overlapping one could be hit again; accepted).
- **The cap degrades by dropping, never by refusing:** at the cap, the oldest projectile of whoever owns the most is dropped. A refused shot would feel like a broken button; dropping the oldest of the richest means a player who floods the screen loses only their own old shots, and nobody is starved (pillar 2). The default cap is the PLAN budget per platform (1,000 on the web, 3,000 on desktop); `set_cap` changes it. Dropping is O(1): each owner has a list of its slots in spawn order, so a flooding player cannot cause a scan. Projectiles deliberately do not use `core/pools`: they are rows with their own slot free list, and `Pool` is for nodes and effects (enemies, damage numbers).
- **A hit carries an opaque `tag`:** `spawn(..., pierce, tag)` stores an int per projectile and `projectile_hit(player, target, position, tag)` sends it back unread (the event changed from part 1 for this). The manager still knows nothing about damage: the spawner (the bolt, part 13) keeps its own table from tag to damage and effects, and `combat` (part 11) looks the tag up there. An int, not a Variant, so it stays a packed array row. Default 0 means "no tag".
- **Piercing shots hit up to 3 targets per step** (`HIT_MEMORY`), nearest first, so a fast piercing shot through a crowd hits all of them; a shot that would pierce more than 3 targets in one step (very rare) hits the rest on later steps only if they are still on its path. It remembers the last 3 targets hit and forgets the oldest after that.
- **Draw cost is unmeasured.** `step` and `update_draw` loop over all slots in GDScript and `update_draw` writes the whole cap-sized buffer. Part 22 must time `spawn` at the cap and `update_draw` with a full cap before these caps are relied on; if slow, upload only the first `drawn` instances and lower the web cap.
- Removing a target or spawning a projectile inside a `projectile_hit` handler is safe: removal waits for the next step and new shots start moving on the next step.

## 2026-10-17: Per-player focus (M1 part 6)

**Decided by:** Claude (details the task left open).

- One autoload, `UIFocus`. A panel is opened for one player with an ordered list of controls; only that player's input moves it. It reads `PlayerInput` by index, never `Input`, and never calls `grab_focus`, so Godot's single global focus plays no part and the mouse cannot steal a panel.
- Navigation uses the gameplay actions, no new ones: up/left and down/right step through the controls (wrapping), `cast` activates, `dodge` cancels. Cancel only sends `cancelled`; the panel decides whether to close. The `overlay` action that opens panels is handled by the overlay (M1 part 19).
- It detects presses with a press counter added to `PlayerInput` (`get_press_count`), compared with the value seen at the last poll. A first version compared `is_action_pressed` between polls and lost a tap released within one frame (bots do that with `send_virtual`); `is_action_just_pressed` is tied to one frame and also needs the caller in `_process`. The counter loses nothing and works from any call. Presses from before the panel opened (the button that opened it) are ignored.
- An open panel captures its owner's gameplay input: `PlayerInput.set_captured(player, true)` makes `get_move`, `get_strength`, `is_action_pressed` and `is_action_just_pressed` answer "nothing" for move, `cast` and `dodge` (not `overlay`, so the overlay can close itself). Gameplay needs no check, nothing is paused, and the other players are untouched. The alternative, separate `ui_*` actions, would need a second binding set for every device. Capture ends on close and when the device leaves.
- Focus is re-checked every frame and before each activation: a control that was disabled, hidden (also through a hidden parent, when in the tree) or freed loses focus to the next usable one, and the press that found it stale activates nothing. `focus_mode` is ignored, since Godot's focus is never used. A panel opens only for a joined player, and opening over an open panel sends `closed` then `opened`.
- Results are signals with the player first (`opened`, `closed`, `focus_changed`, `activated`, `cancelled`); widgets check that the player is their owner. A panel closes when its player's device leaves. Nothing is paused.

## 2026-10-17: Input devices and join (M1 part 5)

**Decided by:** Claude (details the task left open).

- One autoload, `PlayerInput`, routes every input event by device to a player index and keeps per-player action state. Gameplay asks it by index and never reads `Input` directly, so one global action map serves all four players.
- A gamepad takes the lowest free index. The keyboard and mouse count as one device that may only take index 0, matching "P1 keyboard or gamepad, P2–P4 gamepads"; if a gamepad already holds P1, the keyboard cannot join.
- `join` (Enter, Space, gamepad A or Start) and `leave` (Backspace, gamepad Back) are actions. An unplugged gamepad leaves; plugging one in never joins without a button press.
- Bots use virtual devices, ids 1000 + index. They send `InputEventAction`s through the same `handle_event` path as real events, so bot tests exercise the real input code.
- The device events are `device_joined(player, device)` and `device_left(player, device)`, sent by `core/input`; `coop` (M1 part 17) turns them into `player_joined` and `player_left`.

## 2026-10-17: The provisional palette and style rules (M1 part 3)

**Decided by:** Claude (details the plan left open).
**Decision:** `docs/STYLE.md` fixes a 31-colour palette: outline `#14121f` plus ten 3-shade materials (stone, bone, fire, spark, wood, skin and one ramp per player: blue, rose, green, purple). Player ramps are used only for players. Animations are horizontal strips of 32 px frames with fixed counts per animation type. Placeholder SVGs use only `<rect>`s with whole-number coordinates, palette fills and `shape-rendering="crispEdges"`.
**Reason:** Part 4 and outside Art PRs need concrete values to check against. Rects-only SVG guarantees no antialiasing. The style is provisional: the M2 art direction call may replace it (the plan already says so), and then the palette changes in one file.

## 2026-10-17: Event lists in the READMEs are final (M1 part 2)

**Decided by:** Claude (details the plan left open).
**Decision:** `core/events/events.gd` is the source of truth for event names and senders. The "Events at a glance" table in `gameplay/README.md` and every area's event list match it, and the "provisional" marks are gone. `play_requested` (sender: HUD, listener: `flow`) joins the HUD's player-intent requests, so the HUD sends five events. This completes the 2026-10-16 entry "Entry script names, event names and file types", which expected the marks to go once the bus was built.
**Reason:** The bus exists, so the lists can be checked against code and later parts can rely on the names.

## 2026-10-16: Event signatures and base class shapes (M1 part 1)

**Decided by:** Claude (details the plan left open).
**Decision:** `Events` signals take the player index as an `int` named `player`, first. Events with no player (`run_started(player_count)`, `run_ended(victory)`, `room_entered(room_id)`, `room_cleared(room_id)`, `difficulty_changed(level)`, `reward_rolled(reward_ids)`, `unlock_gained(unlock_id)`, `currency_changed(currency_id, amount)`) don't. `damage_dealt`, `status_applied`, `enemy_died` and `projectile_hit` name the source player, or `Events.NO_PLAYER` (-1) when an enemy is the source. `door_voted` and `reward_taken` carry the voting or picking player, as the results of the matching request events. Base resources use `PackedVector2Array` positions for spawns and doors and have only the M1 fields, plus `id: StringName` and `demo: bool`.
**Reason:** Typed signals with a fixed shape let tests and later parts rely on them; -1 avoids a fake player index for enemy damage. M2 and M3 may change the base fields and event arguments; part 2 and those milestones update the docs with them.

## 2026-10-16: M1 design choices the plan left open

**Decided by:** Claude (details the plan left open), in `docs/milestones/M1-core-loop.md`.
**Decision:**
- The ten `gameplay/` sub-areas, `content/spells` and `content/wizard` don't allow `.tscn` (`hud/`, `content/enemies` and `content/rooms` do), so M1 scenes live with their content (`content/wizard/base`, which gets `.tscn` in its README, `content/enemies`, `content/rooms`, `hud/`); `gameplay/` stays script-only and gets scenes through `core/registry`. Rejected: allowing `.tscn` in `gameplay/`, because the Areas table in `docs/PLAN.md` lists only `.gd` and `.tres` for it. The allowed-files paragraph of `gameplay/README.md`, which left this open for M1, is rewritten to say so (part 9).
- The main menu starts the arena only through a new HUD intent event, `play_requested(player)`, that `flow` listens to; areas never call each other.
- Sounds are the Audio contributors' job. Gameplay code asks `core/registry` for a sound by id; the registry (the one place that loads by a computed path) returns `null` for a missing one and nothing plays, so a missing sound is silent and the literal-path rule holds.
- M1 is 25 parts: input, the player, combat with the enemy, and the HUD are each split in two so a task fits one session.
- The player and bots only call one cast method and read no spell fields, so M2 can replace the fire bolt.
- The registry scans folders at start; the build-time manifest waits until content is large.
- The one spell is a fire bolt on a small base class that M2 replaces; nothing else may depend on its fields.
- A minimal slice of `flow` (load the room, spawn the wave, restart) is built in M1 instead of M3, so the loop is playable. M3 replaces it. There is no pause menu in M1.
- Placeholder art is hand-written SVG, since sessions have no image tools. The web 4-bot run and the Style Guide page and kit zip need small owner-only changes in `ci/smbot/`, which their tasks file in `docs/BACKLOG.md`.

**Reason:** each keeps M1 small, inside the path rules, and playable for the first checkpoint.

## 2026-10-16: M1 starts before M0's dry runs

**Decided by:** owner.
**Context:** All seven M0 parts are built, and the bot now develops, reviews and merges its own PRs. M0's done-when also asks for 3 daily releases in a row and 15 dry runs. GitHub hasn't fired the daily schedule yet (the catch-up in `develop.yml` covers it from now on), and most dry runs need a second GitHub account or a deliberately broken build, so the bot's queue was empty with nothing it could do.
**Decision:** M0 is closed early and M1 starts now. The dry runs and the 3-release streak are not dropped: they carry into M1 and are part of M1's done-when, so M1 can't finish without them. The first M1 task is the M1 design document, which goes through the normal review before any M1 code. Art and Audio open for PRs with M1, as planned.
**Consequence:** the pipeline's end-to-end checks (rule-breaking PRs auto-closed, CLA, votes, quarantine, kill switch, token alarm, revert of a broken build) are still unproven while M1 is built and Art and Audio take outside PRs. The owner runs them during M1.

## 2026-10-16: llms.txt uses relative links and lists maintainer prompts as Optional

**Decided by:** Claude (details the plan left open).
**Context:** The llms.txt convention expects absolute URLs, but the repo may be forked or renamed, and agents read it from a checkout.
**Decision:** `llms.txt` at the repo root uses repo-relative paths. The `.github/maintainer/` prompts go under "Optional" since contributors rarely need them. Any PR that adds or removes a doc updates `llms.txt`.

## 2026-10-16: Entry script names, event names and file types in the code-area READMEs

**Decided by:** Claude (details the plan left open).
**Context:** docs/PLAN.md gives `combat/combat.gd` as an example entry script but doesn't list the rest, and the event bus doesn't exist yet.
**Decision:** Each gameplay sub-area's entry script is `gameplay/<area>/<area>.gd`. `core/events` owns the event definitions; each README only lists the events its area sends (each event has one sender) and listens to, marked **provisional** until the event bus is built in M1, when the READMEs are updated. The HUD's sent events are the player-intent requests from "The HUD sends player-intent events": `build_change_requested` (listener `player`), `reward_pick_requested` (`rewards`), `door_vote_requested` (`flow`) and `pause_requested` (`run`), all in the table in `gameplay/README.md`. Text shared by all sub-areas lives in `gameplay/README.md`. Gameplay PRs allow `.gd` and `.tres` only, as in the plan's Areas table. `core/` services get their entry scripts and sections when built.

## 2026-10-16: The bot can merge its own approved PRs

**Decided by:** owner.
**Context:** The `main` ruleset had "Require approval of the most recent reviewable push", which needs an approving review from someone other than the last pusher. The bot pushes its own PRs and can't approve them, and the merge script never approves anything, so GitHub refused every automated merge ("the base branch policy prohibits the merge") and every bot PR waited for the owner.
**Decision:** `require_last_push_approval` is off (`ci/settings/rulesets/main.json`, and on GitHub). Owner-only paths still need the owner's code-owner review, and the merge script still merges only the exact reviewed commit, after the required checks and the hard rules pass.
**Consequence:** the bot's PRs merge the same day, as the plan intends. What contributor PRs may change is unaffected: the hard rules and the code-owner review still apply.

## 2026-10-16: develop also runs on every push to main

**Decided by:** owner.
**Context:** GitHub never fired this repository's schedule: no scheduled run of any workflow on its first day, through two cron changes and turning the workflow off and on. When a session chain stops (an error, a usage limit, an empty queue), nothing started it again.
**Decision:** a push to `main` (any merge, by the bot or the owner) runs a small `kick` job in `develop.yml`. If no develop run is running or queued, it starts one with `workflow_dispatch`; otherwise the running chain carries on by itself. The kick job runs no Claude step, because `claude-code-action` doesn't accept `push` events, and it sits outside the `develop` concurrency group, so it never waits behind a session. The hourly schedule stays for when GitHub does fire it.

## 2026-10-16: Sessions don't wait for each other or for the owner

**Decided by:** owner.
**Context:** The next session started only after a merge, and only within 2 hours of the first. Any PR that didn't merge (a failed review, a blocked task, a merge GitHub refused) ended the chain, and work waited for the next hourly check. A stuck task also stayed at the top of the queue, so the next session tried it again.
**Decision:**
- When a session ends, the next one starts right away if the session made progress (it merged, opened or updated a PR, or reported the task blocked), the budget allows it, and there is a task. There is no time cap; the pacing budget limits usage. The chain stops on an error, a usage limit, nothing to do, or paused merging, and the hourly check starts it again.
- A task that can't move without someone else is parked in the state's `task_failures` and skipped, so the next task goes first: for 7 days when it failed review twice or was reported blocked, and for 1 day when its approved PR wasn't merged. Afterwards it is picked up again, and its open PR is continued.
**Consequence:** Work only waits on the owner for things only the owner can do, and even then other tasks go ahead. A task that failed review once is still retried straight away, with the review's problems.

## 2026-10-16: The HUD sends player-intent events

**Decided by:** owner.
**Context:** The plan said "The HUD only listens." But the spell builder, reward picks, door votes and the pause menu are all HUD scenes whose choices must reach gameplay. With a listen-only HUD, that input would have to go through direct calls into gameplay, which principle 2 forbids.
**Decision:** The HUD may send events, but only player-intent events: a request carrying the player index (0–3), such as a builder change, a reward pick, a door vote or opening the pause menu. Gameplay owns all state. It checks each request, applies it or refuses it, and announces the result as a normal state event. The HUD shows only what those state events say, never its own guess of the outcome. It still never calls gameplay directly, and other areas never call into the HUD.
**Consequence:** Plan principle 2 now says this. Event names are settled when the event bus is built in M1; intent events are named as requests, so they can't be mistaken for state events.

## 2026-10-16: Content READMEs name no field or file layout before the example exists

**Decided by:** Claude, within the plan.
**Decision:** The content area READMEs describe the contract as "the base class (arrives in milestone X)" and point to an example that arrives with Claude's first content, instead of inventing field names. Sub-folder `.gitkeep` files (spells, wizard, story) stay because those sub-folders have no README.
**Reason:** The base classes don't exist yet; documenting invented names would contradict the code later. Each README gets the real example path when its area opens.

## 2026-10-16: Claude never holds a write token where it has a shell

**Decided by:** Claude, after reviewing the session design.
**Context:** The implementing and revising sessions can effectively run code: through git, file commands, or Godot running scripts they wrote. If a prompt injection ever reached them (say, from a merged contribution's comments), a write token on that runner could be stolen and used to merge.
**Decision:**
- Those sessions get a read-only app token and commit only locally. Their commits leave the runner as a git bundle, which is plain data.
- A `publish` job on a fresh runner fetches the bundle into a clean checkout of `main` (with git hooks disabled), pushes only to a `claude/...` branch, and opens or updates the PR from Claude's structured output. It also records usage and posts `/ask` answers, only on issues where the owner asked.
- Claude is also denied edits under `.git/`, `.github/`, `ci/` and `tools/`, and gets only specific `git` subcommands.
- Sessions without shell or file-writing tools (rating, review, digest) still mint a write token after Claude finishes, because they can't run code.
**Residual risk:** a session could still leak its read-only token or its Claude token over the network. The next hardening step would be an egress firewall on those runners (see `docs/BACKLOG.md`).

## 2026-10-16: How the weekly planning run works

**Decided by:** Claude, within the plan.

- **`weekly.yml`** runs on Sundays at 06:00 UTC, in the same concurrency group as development, so the two never overlap.
- **Untrusted community text** (Discussions, spell ideas, bug reports) is read only by a digest session with read-only tools (`Read`, `Glob`, `Grep`; no shell) and no write token. Its structured output (verdicts, short replies, neutral bug restatements) is all the planning session sees, and only as data.
- **Replies to ideas** are posted by script with the workflow token, because the bot app has no Discussions permission and the plan keeps it to three. They are limited to about 1,200 characters, with no @mentions and no links outside this repository.
- **The planning session** is a normal work session (`session.yml`, mode `plan`), with the same critique, revision, final review and scripted merge as development. It edits the plan files, and writes the next milestone's design once the current milestone is done. Its structured output becomes the devlog post (Discussions, Announcements), contributor task issues (the fixed template with a "Brief for your AI", at most 10 open per area), owner issues (milestone start, checkpoints) and, from M1 on, the playtest of the week.
- **`session.yml`** holds the implement, critique, revise, final review, merge and finish chain for both `develop.yml` and `weekly.yml`.

## 2026-10-16: How the contribution pipeline works

**Decided by:** Claude, within the plan and the owner's CLA decision.

- **Triage** (daily, script): the hard rules are re-run from `main` against each PR head, with no PR code run. Closing comments list rule, file, line and fix. After 2 closed PRs in a day, an author's further PRs that day are closed. Unsigned authors get one CLA reminder, and the PR closes after 7 days. Area and skill labels come from the changed paths.
- **CLA records:** new signatures go into `docs/cla-signatures.json` through an `automated` bot PR that the merge step merges after checks. `automated` PRs may only change that file, or, for a quarantine, the reported asset and the manifests.
- **Rating:** one fresh Claude session per PR (matrix job, at most 8 a day). It has read-only tools and a read-only token, and the PR's files are checked out without being run. A script holds Claude's decision to the plan's thresholds (merge needs an average of at least 3.5 and no criterion below 2) and posts the comment, with a marker recording the rated SHA. A push means a new rating.
- **Merging:** the rated SHA must still be the head. Votable PRs (art, audio, gameplay, spells) wait for the vote, and the rating comment's vote line is updated daily. Candidates are test-merged in score order on a local `staging` branch, with the quick build after each, in a job without secrets. Then the merge script merges each one (checks, hard rules, `--match-head-commit`). On a conflict, the higher-rated PR wins and the other gets a rebase request.
- **Follow-ups:** the rating's fix-ups for merged PRs become the next development session's task, crediting the contributor. They are treated as suggestions, not instructions.
- **Broken daily build:** in a job without secrets, the day's merges are reverted newest first until the build passes. The culprits are then reverted on `main` through bot PRs, with a comment on each, and the daily run starts again once (no second round of reverts).
- **Claims:** `/claim` (anyone) assigns an issue labelled `now`, hourly. A reminder comes after 1 day and the claim is released after 2 days without a PR that mentions the issue.
- **No-git submissions:** issue forms for art, sound and writing. In a job without secrets, the file is downloaded only from GitHub's attachment hosts. PNGs are fully decoded and re-encoded (only pixels survive) and OGG is re-encoded by ffmpeg. Then a privileged job checks that both agreement boxes were ticked and that only the author edited the issue, and opens a bot PR (label `submission`, contributor as co-author) that is rated like any outside PR.
- **Copyright reports:** the reported asset is replaced by a same-size placeholder (audio is removed) and marked `quarantined` in the manifest, through an `automated` PR merged before the build. The owner is notified.
- **Votes:** the thresholds, window, eligibility phases and coordinated-vote discount are implemented in `ci/smbot/votes.py`. They are dormant while there are 0–2 active voters.

## 2026-10-16: How a development session works

**Decided by:** Claude, within the plan.

- **The flow:** `develop.yml` runs hourly, as implement, critique, revise, final review, merge, finish. Each Claude step runs in its own job on a fresh runner, so a session with a shell can't tamper with its reviewers or with the merge script. The merge job runs no AI and uses only scripts from a clean checkout of `main`.
- **Reviewers** (`review.yml`) get a read-only app token and read-only tools (`gh pr view/diff`, `git diff/log/show`). Their verdict is structured JSON. A PR merges only with `approve` and no blocker or major problems, and only after the required checks and the hard rules (re-run from `main`) pass, pinned to the reviewed commit.
- **The implementer** gets a curated command list: git, `gh pr`, `gh issue view/comment`, `tools/check.sh`, `ci/build/build.sh --quick`, and basic file commands. No `curl`, `wget`, Python, web fetch or web search. Secrets are scrubbed from its subprocesses where the action supports it. Prompts are in owner-only `.github/maintainer/`.
- **One critique and one revision round** per session. If the final review rejects, the PR stays open, and the next session sees the problems and continues. After the second failed attempt, the task is marked blocked, with the reason, and work moves on.
- **Continuous work:** after every session that made progress, the next one starts with `workflow_dispatch` while there is a task and budget (see "Sessions don't wait for each other or for the owner"). One session at a time, through the `develop` concurrency group.
- **Usage accounting** reads each step's execution file. Cache reads count a tenth, because they cost far less quota. A usage-limit message starts the back-off; a rejected token opens the token alarm, and the alarm closes after the next good run.

## 2026-10-16: How the control gate, owner commands and pacing work

**Decided by:** Claude, within the plan.

- **The gate:** every run starts with `ci/smbot/control.py`. Nothing runs unless the `AUTOMATION_ENABLED` variable is `true` and the Control panel (issue #4) allows it.
- **Panel trust:** values come from GitHub's edit history (each `userContentEdits` entry holds the full body of that revision), from the newest revision whose editor is the owner's numeric ID. A newer edit by anyone else is ignored and reported in the Daily log with a mention of the owner. If no owner revision exists, the gate fails closed.
- **Owner commands:** processed only by the hourly run, so two runs never act on one command. `/pause` pauses development and PR merging; releases continue, because only the kill switch stops releases. `/merge` refuses if the PR head was pushed after the command, judged by when GitHub started that commit's checks run, since commit dates can be faked. `/priority`, `/claude` and `/ask` are queued for the next Claude session.
- **Merge method:** squash for every merge, so each PR is one commit that one `git revert` undoes. The PR author stays the commit author.
- **State:** bookkeeping lives in `state.json` on the `automation-state` branch: token usage, back-off, processed commands and alarm issues. Writes use the file's SHA, so concurrent runs can't silently overwrite each other. It is never trusted for security decisions.
- **Pacing:** each run records its tokens for the Daily log. Runs are not gated by estimated quota: learning the window size from token counts disagreed with the real usage (it stopped at an estimated 104% when the account showed 69%), so `DEV_INTENSITY`, `WEEKLY_SHARE` and the 30% review cap were removed (2026-10-22). When Claude reports a usage limit, runs back off until the reset it names.
- **Schedule:** the hourly run starts at minute 35, away from the busy top of the hour.
- **Alarms:** each alarm is an issue labelled `alarm` that mentions the owner, opened once and closed automatically when the problem is resolved.
- The bot app's token is minted with `app-id`, which is deprecated in favour of `client-id` (see `docs/BACKLOG.md`).

## 2026-10-16: How builds and releases work

**Decided by:** Claude, within the plan.

- **Engine:** Godot 4.7.2-stable is pinned in `ci/build/godot.env`. The editor and export templates are checked against Godot's own SHA-512 sums. Only the checked downloads are cached; Godot is unpacked fresh on every run, so a tampered cache can't supply a binary.
- **Display:** a 640×360 viewport with integer scaling for crisp 32×32 pixel art, the Compatibility renderer, and a single-threaded web export (no special server headers needed on GitHub Pages or itch.io).
- **Smoke tests every build must pass:** the main scene in the editor, the exported Linux binary, and the exported web build in headless Chrome (`ci/smbot/websmoke.py`). Any engine or script error in the logs fails the build. Windows builds can't be run on Linux runners.
- **Channel:** decided before the build. A build that passes every test is stable unless an issue labelled `crash` or `blocker` is open, in which case it is nightly. Failing tests stop the release entirely. The benchmark joins the gate in M2.
- **Releases:** tagged `v0.YYYYMMDD` (`.2`, `.3` for extra runs on the same day). The assets are attached to a draft, which is then published, so the immutable release is complete. Nightlies are pre-releases; stable releases are marked latest.
- **Pages:** `/play/` serves the latest stable web build, `/nightly/` today's build, and `/` a landing page until the Contribute page exists.
- **itch.io:** pushed with butler 15.31.0 (hash-pinned) once the `ITCH_TARGET` variable (for example `peterdk31/spellmerge`) is set. Stable builds go to the `web`, `windows` and `linux` channels, nightlies to `*-nightly`.
- Only `core/` and `tests/` may load files dynamically. Tests are never exported.

## 2026-10-16: How the hard rules check works

**Decided by:** Claude, within the plan's rules.

- The check is `ci/smbot/rules.py`, Python 3 standard library only, so nothing is installed in jobs that hold secrets. `tools/check.sh` runs the same code locally.
- The owner-only paths are read from `.github/CODEOWNERS`, so there is one list. `addons/` was added, because the plan allows third-party addons only from the owner. `project.godot` and `export_presets.cfg` are bot-maintained, because they can register autoload scripts and change export settings.
- In CI, the rules and `ci/config.json` come from a checkout of `main`, never from the PR. The fixed identities (owner and bot, with numeric IDs) live in owner-only `ci/config.json` rather than in repository variables, because the check must also work for fork PRs.
- Untyped GDScript is a warning for outside contributors, since the review stance has Claude fix it after merging, and an error for the bot's own PRs. `project.godot` therefore reports untyped code as a warning, not an error, so a contributor's untyped code can't break the build.
- Size limits: 1 MB for `.png` and `.svg`, 5 MB for `.ogg`, as in the plan, and 1 MB for any other file, against abuse.
- Banned in `.gd`, `.tscn` and `.tres`, beyond the plan's list, because each can hide a banned call: calling singletons by name (`OS.call`, `Engine.get_singleton`), creating code at runtime (`GDScript.new`, `Expression`, `set_script`), `@tool` and editor plugins, and loading from a computed or `user://` path outside `core/`.
- Also rejected: symbolic links, submodules, binaries disguised as `.png` or `.ogg` (the magic bytes are checked), and SVGs with scripts or external links. Dependabot PRs may only change GitHub Actions files.
- The owner's own PRs get warnings only.
- The required `rules` status alone is never trusted, because a PR could rewrite `checks.yml`. Such a PR needs the owner's review, and the merge script re-runs the check from `main` before merging.

## 2026-10-16: Own CLA check instead of CLA Assistant; no lawyer review

**Decided by:** owner.
**Context:** cla-assistant.io keeps an OAuth token for the owner's account with `repo:status`, `write:repo_hook` and `gist` scopes on all repos. The owner account is what the whole security model protects.
**Decision:**
- `CLA.md` is adapted from the Apache Individual CLA v2.2, because a standard, widely used text is the safest choice without a lawyer.
- Contributors sign by commenting `I have read the CLA and I agree to it.` on their PR. For no-git submissions, the issue-form checkbox counts.
- The daily run records signatures in the bot-maintained `docs/cla-signatures.json` by numeric user ID and CLA version.
- Unsigned PRs get a how-to-sign comment and are closed only if still unsigned after 7 days, because a signature is only seen at the next daily run. They are never merged unsigned.
- The plan's "short lawyer review before selling" item is dropped entirely.

## 2026-10-16: PRs merge into `main`; `staging` is only a test branch

**Decided by:** owner.
**Context:** The plan had approved PRs merged into `staging`, with `main` fast-forwarded at release. A `main` ruleset that requires PRs and code-owner review would only allow that if the bot were a bypass actor, and then the bot could also push owner-only paths past CODEOWNERS.
**Decision:** The bot is never a bypass actor. The merge script merges candidates together on a throwaway `staging` branch and runs the content validators there, then merges each passing PR into `main` with `gh pr merge --match-head-commit <reviewed SHA>`. A broken daily build is fixed with revert PRs that the bot opens and merges itself. The release tags `main`.
**Consequence:** Every protection that GitHub enforces stays in place for the bot. `main` can briefly hold a merge that the daily smoke test later reverts, but releases are cut only from a tested `main`.

## 2026-10-16: Code license is GPL-3.0-or-later

**Decided by:** owner. Assets stay CC-BY-SA-4.0. Recorded in `REUSE.toml` and `LICENSE`.

## 2026-10-16: Setup, security docs and REUSE.toml are owner-only

**Decided by:** owner. `setup.sh`, `REUSE.toml`, `docs/SECURITY-CHECKLIST.md` and `docs/SETUP-APP.md` join the owner-only tier, so the bot can't weaken the security setup or its checklist, or change the license that every file falls under. Repository settings data lives in `ci/settings/`, which is owner-only already.

## 2026-10-16: The project board is user-owned and follows labels

**Decided by:** owner.
**Context:** GitHub Apps can't access projects owned by a personal account; that needs a classic personal access token, which the plan rules out.
**Decision:** The board stays under `peterdk31`. GitHub's built-in auto-add workflow fills it, and views filter by label. The bot keeps issue labels correct and never edits the board itself.

## 2026-10-16: Names chosen during setup

**Decided by:** Claude (details the plan left open).

- The protected environment is called `automation`. Its secrets are `BOT_APP_ID`, `BOT_APP_PRIVATE_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and `BUTLER_API_KEY` (the name itch.io's `butler` tool reads).
- The repository variables are `AUTOMATION_ENABLED` (the kill switch), `OWNER_ID` (the owner's numeric user ID) and `BOT_LOGIN`.
- The required PR status check is the `checks.yml` job named `rules`, pinned to the GitHub Actions app.
- Only GitHub-owned actions plus `anthropics/claude-code-action` and `oven-sh/setup-bun` are allowed, all pinned by SHA (`ci/settings/allowed-actions.json`). claude-code-action uses `oven-sh/setup-bun` internally, pinned by SHA in its own `action.yml`.

## 2026-10-17: Registry shape (M1 part 8)

**Decided by:** Claude (details the plan left open).

- Sounds are found by file name under `audio/` only (any depth), as the task says; item sounds in `content/` are not indexed yet. A sound id is the file name without `.ogg`.
- Content is any `.tres` with an `id` below `content/<folder>/`, so M2 components need no registry change; the first in sorted path order wins a duplicate id.
- `demo_only` is a runtime variable set from the `demo` feature tag, so tests and the web build share one code path.
- `scan()` takes roots and a sound extension list so tests can use a fixture: a valid `.ogg` cannot be written in a session, so the fixture sound is an `AudioStreamWAV` `.tres`.

## 2026-10-17: Player movement and dodge (M1 part 9)

**Decided by:** Claude (details the plan left open).

- The wizard is a `CharacterBody2D` in floating mode on physics layer 2, colliding only with walls (layer 1): wizards walk through each other, so nobody blocks a teammate.
- The values are binary fractions (walk 90 px/s, dodge 220 px/s for 0.25 s, invulnerable the first 0.125 s, cooldown 0.625 s) so fixed-step tests add up exactly; tune them at C1.
- A dodge is detected with `get_press_count`, not `is_action_just_pressed`, so a tap released within a frame is not lost. A press made while the dodge is not ready, or while the player's input is captured by an overlay, is dropped, never queued.
- The scene was built before the part 4 sprite existed, with an empty `Sprite` node; part 4 fills it in rather than part 9 inventing art. Part 9 ran before part 4 because the session picked it; it needs no art, and parts 10–12 build on the script. Part 4's done-when now asks for a visible sprite per player index.
- Opening an overlay ends a dash in progress (cooldown stays), so a captured player is fully frozen.
- Physics layers: 1 walls, 2 players, 3 enemies, 4 projectiles and hit boxes (in the player README); `core/` is asked to name them in `project.godot`.

## 2026-10-17: The overlay (M1 part 19)

- The `overlay` action is read in `hud/panels/panels.gd` from `PlayerInput.get_press_count`, not by each overlay, so one place owns the toggle and a tap released within a frame is not lost. Everything after opening goes through `UIFocus`; the overlay ignores every signal that names another player.
- An overlay opens only for a joined player and only if that player's `UIFocus` panel is free, so it never replaces another panel. Closing comes from Resume, `dodge`, the `overlay` action, or the device leaving (`UIFocus` closes it).
- The stub button sends `build_change_requested(player, 0, &"stub")` and nothing else; the `player` area has no listener yet and will refuse unknown ids. The overlay never pauses and never changes `Engine.time_scale`.
- The overlay is made visible before `UIFocus.open`, because `UIFocus` only focuses controls that are shown; it is hidden again if opening fails.
- An overlay opens only while a room is active (`room_entered` seen, no `run_started`/`run_ended` since), so a press on the menu does nothing and the player's input is not captured there. It closes on `run_started`, `run_ended` and when its owner goes down. A downed player cannot open it (they would be frozen and the team would lose sight of who needs a revive); the panel word keeps DOWN above MENU.
- The overlay offset is not a fixed number: `panels.gd` derives it from the panel's minimum height plus a 4 px edge margin and a 2 px gap (under the panel in the top corners, over it in the bottom ones), and again when that height changes. `test_overlay` checks the rectangles at 640×360.
- Focus is shown with a "> " text mark because Godot's own focus is unused (`UIFocus` decision), and state is never colour alone.


## 2026-10-17: Unfinished sessions keep their work

**Decided by:** the owner ("work should not be thrown out").

- A session that stops before it is done (usage limit, error, timeout, or no result) but has commits pushes them to its task's branch in a draft PR titled `Unfinished: <task>`, with a note saying why. It is not reviewed or merged; the next session for the task finds the PR by its branch and continues it, and the PR becomes ready for review when that session finishes.
- An unfinished revision is pushed to its PR with the same note, and the final review is skipped, so the next session continues the PR.
- The implement job may run 4 hours (its Claude step stops at 200 minutes) and the revise job 3 hours (150 minutes), so a step that runs too long still leaves time to package and keep its commits.
- Triage already skips draft PRs, so an unfinished PR is never rated as a contribution.

## 2026-10-17: The bot may push main's workflow changes, never its own

**Decided by:** the owner.

- GitHub refuses a push from the bot app when any pushed commit changes a file in `.github/workflows/`, even a merge that only takes in main's version. Run #103 lost a finished session this way: it merged main after #67 had changed `session.yml`.
- The push tokens in `session.yml` ask for `workflows: write`, and the bot app has that permission.
- Before every push, `publish` checks each file under `.github/`: it must match main or the branch as already pushed, or nothing is pushed. So the bot can take in the owner's workflow changes, but it can't make its own.

## 2026-10-17: Making the unit tests pass

- **Unit tests wait one frame** (`await process_frame` first in `_initialize`): in Godot 4.7 the root is not in the scene tree during `_initialize`. The rules for tests are in `tests/README.md`.
- **Sorting `StringName`:** `Array.sort()` orders StringNames by address, not by letters. The registry sorts ids and folders by their text.
- **Pool:** a pooled object is held as a `Variant` until checked, since assigning a freed object to an `Object` variable is an error.
- **AI:** a freed target reads as `null`, so the AI keeps the target's instance id to know it was lost and looks again at once, as documented.
- **Feel:** a plain hit never starts or extends a hit-stop while one runs; before, four players hitting every frame froze the game for ever. A kill still lengthens a shorter stop.
- **Flow:** a failed restart is a `push_warning`, not a `push_error`: the run ends cleanly, a test provokes it, and the build fails on `ERROR:` lines. The 4-bot smoke test (M1 part 20) must therefore also fail on the warning text "the restart failed".
- **Mid-run joiners** take the free spawn farthest from enemies and wizards (part 17), so the coop test checks "a player spawn", not the one numbered like the slot.
- **`player.gd` and `combat.gd`** read absolute autoload paths only inside the tree (tests build them outside it).

## 2026-10-17: HUD panels 60% translucent, fonts unchanged (replaces the entry below on sizes)

Still no display in sessions, so decided from sizes, not from a screenshot, and text legibility over the floor is NOT verified (no contrast was computed or seen). Only the translucency was added; fonts stay 12/14 px at 640×360 (integer-scaled ×2); no licensed pixel font is in the repo, so none was added. An opaque 112×55 corner panel can hide a wizard or enemy in a room corner (at Coop zoom 0.5 it covers 224×110 world px), so the panel background alpha is now 0.6; border and text stay opaque and state stays in words. If a real screenshot shows text hard to read over bright floor, raise the alpha to 0.75 in `hud/theme/spellmerge_theme.tres`; the four `panel_p1`–`panel_p4` styleboxes there hold the same literal and must change together (the test only checks the range 0.4 to below 1). The real screenshot stays in `docs/BACKLOG.md`.

## 2026-10-17: HUD sizes unchanged for now, visual check still open

The HUD screenshot cannot be taken in a session (no display, `docs/BACKLOG.md`), so no HUD size or font was changed. This is not a finding that they are fine. The four 112×55 panels are screen-space corners: a wizard or enemy standing in a corner can be hidden by one, and the Coop camera moves and zooms (0.5–1.0), so a paper check at one camera position says little. The legibility of the smooth default font at 12/14 px on the 640×360 canvas is unverified, and the design calls for pixel art, so a pixel font may be wanted (side note: a font file would need a licence entry). Decide on panel size, a translucent background and the font after the display run; tracked in `docs/NEXT.md` ("HUD screenshot and legibility check").

## 2026-10-17: the 4-bot smoke test

- The test is `tests/smoke/four_bot_smoke.gd`; `tests/smoke/test_four_bot_smoke.gd` only extends it, because `build.sh` runs `test_*.gd` and sessions may not edit `ci/`. Part 21 decides how the export runs it.
- A downed bot 4 is not a failure (it only idles); its overlay closing while it is not downed is, and so is zero `spell_cast` events. The logger (`tests/smoke/error_log.gd`) is unit-tested with hand-fed calls and starts after the autoloads load, so startup errors are not covered.
- Errors are caught by a `Logger` (`OS.add_logger`), not by reading a log file, so the test works the same in the editor and in an export. A warning counts as a failure only for "the restart failed" (see "Flow" above).
- Bots call nothing on a spell (a deliberate deviation from "calling only the cast method" in the old NEXT.md wording): they hold the `cast` action and the wizard calls the cast method. "Alive or revived" is checked as "not down at the end"; revive itself is still in `docs/BACKLOG.md`.
- Game time runs at `Engine.time_scale` 2 with a limit of 120 game seconds, since no real-time wait is wanted.

## 2026-10-17: The daily build runs the unit tests and takes screenshots

**Decided by:** the owner (#72: "make the daily build run the unit tests and fail when one fails"; and screenshots "posted somewhere").

- The full `ci/build/build.sh` (the daily build) runs every unit test. A failing test fails the build, which then goes through the usual find-and-revert of the merge that broke it.
- `ci/build/build.sh --quick --screenshots`, also part of the full build, runs every `tests/screenshots/shot_*.gd` under `xvfb-run` with the OpenGL renderer (Mesa's software renderer on the runners). The shots save 640×360 PNGs to `user://screenshots/`, and the script copies them to `build/screenshots/`. The first shot script, `shot_m1.gd`, takes the main menu and the arena with four wizards.
- **Where they are posted:**
  - The daily build publishes a gallery at `/screenshots/` on the Pages site.
  - Every bot PR gets a comment with the screenshots of its latest commit. The images are stored on the orphan `screenshots` branch under `pr-<N>/<sha7>/` and linked by commit.
  - The game code that takes the PR's shots runs in a job with no secrets and a read-only token. A separate job posts the images and accepts only plain PNGs under 1 MB.
- Sessions may run `--screenshots` and open the PNGs with Read, so Claude can see what it built.

## 2026-10-17: Translucent player panels (replaces the 60% entry above)

**Decided by:** the owner ("it's generally fine [that the HUD covers imps]... but the HUD could be transparent").

- A corner panel may sometimes cover a wizard or an enemy; that is accepted, not something to design around.
- The four player panels in `hud/theme/spellmerge_theme.tres` are translucent: background alpha 0.4, border 0.8, and the bar backs 0.7, so whatever is behind a panel shows through. `panel_plain`, the default panel for menus and overlays, stays opaque.
- The values were checked on the `arena_four_wizards` screenshot: the imps in the top corners show through and the labels stay legible.

## 2026-10-17: Hit work is budgeted per step; the projectile caps stay

- `ProjectileManager.step` spends at most `WORK_PER_STEP` (8,000) units of hit-test work a step: 1 per target examined, `HIT_WORK` (40) per hit. Counting examined targets as well as hits bounds both costs the benchmark found (a hit limit alone would not bound the crowd scans of the steady state). The budget is work, not time, so tests stay deterministic.
- When it runs out, the remaining shots still move and are not tested; the next step starts from the first untested slot, so a flood cannot starve high slots. The price: in a crowd at the caps a shot can hit a step late, and a very fast one can skip a target. Real play (about 10 shots) never gets near it.
- With the work bounded, the hostile step no longer grows with the number of shots, only plain movement does (0.2 ms at 1,000, 0.6 ms at 3,000). Measured 2.8 and 3.1 ms natively. A first try with 16,000 gave 6.5 and 7.4 ms, 81-93% of the 8 ms target: too close when WASM may be 2-4x slower, so the budget was halved. At 4x, 2.8 ms is still about 11 ms, so the web task re-checks it in WASM and lowers `WORK_PER_STEP`, then `DEFAULT_CAP_WEB`, if needed. The caps stay 1,000 web / 3,000 desktop: the budget, not the cap, now sets the hostile cost.
- The budget is per `step` call, not per frame: catch-up physics steps in one frame (up to 8 by default) each get their own. Slot order is not player-fair, so in a flood the player whose shots sit in the starved slots hits a step late; the resume point moves on each step, so it evens out over a few steps. Tested with piercing shots that never die (`_test_spent_budget_resumes_at_the_first_untested_shot`).
- Not done: a per-layer grid and cheaper overlapping-target handling. The budget alone met the target; they stay options.

## 2026-10-17: Starter kit sources live in `art/kit/`; golden examples are existing art

- The kit sources are in `art/kit/` with a `.gdignore`, so Godot neither imports nor ships them, and they have no manifest entries (templates and lists, not game assets).
- `.gpl` is not an allowed file type (hard rule 2), so the GIMP palette is `spellmerge.gpl.txt`; the kit zip ships it as `spellmerge.gpl`. Binary palettes (Aseprite, Photoshop, Krita) can't be written by sessions; the hex list and the `.gpl` cover those editors' import functions.
- The golden example candidates are not copies. A second wizard would duplicate `content/wizard/base/wizard_p1_idle.svg`, so `art/kit/golden.json` lists the six best existing placeholder files by path with what each shows, and the zip build copies them. The M2 art direction call confirms or replaces them.
- The checklist's source stays `docs/STYLE.md`; `art/kit/checklist.md` is its one-page export, kept in step by hand until the site build generates it.

## 2026-10-17: Aim is separate from walking (C1 iterate round 1)

**Decided by:** the owner ("iterate a bit more on the basics like aiming etc. And also a bit on the graphics", #97); the details are Claude's.

- Before, shots went the way the wizard last walked, so it could not shoot one way and retreat the other. Now `player.gd` has `aim`: the right stick, else (keyboard player only) the mouse once it has moved 8 pixels (a brush does not count), else the walk direction. The stick aim holds 0.6 s after release so a flick still shoots where it pointed; then it follows the walk again, so a player who never touches the right stick keeps the one-stick behaviour.
- The mouse is only a flag in `core/input` (`is_mouse_aiming`); the wizard turns it into a direction with the world mouse position. The J key switches the keyboard player back to walk-direction aim.
- Aim assist toward enemies is not done: it needs the wizard to look at enemies, which crosses areas; decide with playtest answers.
- Graphics, small and code-drawn (no new art files): the sprite flips toward the aim (with a 0.3 band either side against flicker; the flip also mirrors the painted light, accepted for the placeholder art), a soft ground shadow, and a chevron reticle in the player's light ramp colour with a 1 px outline. Shots still start at the wizard's feet, in line with the shadow.

## 2026-10-18: Weekly planning, M1 stays open

**Decided by:** Claude (weekly run). The digest was empty; the owner gave no instructions and no focus.

- M1 is not complete: C1 (#97) has no verdict, and the web 4-bot run (#93) and the Style Guide site step (#95) wait on the owner. No M2 design is written; the 7-day default for C1 is iterate on 2026-10-24.
- No task added. Shots keep starting at the feet, in line with the shadow, as decided on 2026-10-17; that is revisited only with a feel-check answer or the C1 verdict, not on a re-read of the code.

## 2026-10-18: Playtest fixes: shots at the staff, visible, and a dash look

**Decided by:** Claude, on the owner's `/claude` in #102 (playtest) and #97 (C1).

- **Shots start at the staff tip, reversing the 2026-10-17 "feet" choice.** The owner asked for it and could not see the shots anyway. `muzzle_position()` is hand height (10 px) plus 14 px along the aim; the same point goes out in `spell_cast`. The staff is drawn in code, not a sprite part, so it works for every player colour and aim angle until real art arrives (M2).
- **No aim assist.** The owner does not want it; a "homing" spell modifier is the planned way, so nothing is added to `player` for it.
- **Projectile visibility lives in `core/projectiles`.** The batch is drawn at `z_index` 50 (above room and wizards) with a `custom_aabb` over the bounds, and drawn at 3x the hit circle with a 45% tint. Reason: the bugs were in how the batch is drawn, not in spells or the player.
- **Dash look is code-drawn** (stretch along the dash axis, lean, three ghosts at the wizard's last three positions with the same stretch and lean), no frames: no art files are needed and it works for all four colours. Real animation is M2 art. The staff and reticle are drawn by a child node above the sprite, the shadow and ghosts below it.
- **Known limit: shots can start behind a wall.** The muzzle is 14 px out and 10 px up, and projectiles do not collide with room geometry in M1, so a wizard pressed to a wall can fire from the far side. Fixed on 2026-10-18, see "Shots stop at walls" below.
- **Shot colours.** At 4 players the five shot colours (players 0-3 and the enemy) all differ and none is dark (`test_projectiles.gd`). Enemy orange and player pink are the closest pair; enemy shots are also told apart by where they come from. The 3x draw size against the hit circle is a feel value for the C1 round: if shots look bigger than they hit, lower `DRAW_SCALE`.
- Not decided here: controller and 4-player feel (the owner has not tried them); they stay in the C1 round.

## 2026-10-18: Shots stop at walls (C1 round 2, task 2)

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **No bouncing.** A shot that meets a wall ends there, piercing shots included (`pierce` is for targets). A bouncing modifier is a spell-design question for M2+, not decided here; when it comes, it belongs in `core/projectiles` as a per-shot bounce count, using the same wall grid.
- **Own wall grid, not physics queries.** The manager rasterises the room's solid rectangles into 8 px cells and walks the cells a step crosses. A physics ray per shot would cost thousands of queries a step against the 1,000 web / 3,000 desktop budgets. Walls are rounded out to whole cells (exact for the 32 px tiles); the shot is a point, not a circle, so its 4 px radius can overlap a wall by that much. The wall check is not charged to `WORK_PER_STEP`; its walk is capped at 64 cells a shot instead, and a path not fully walked counts as a hit (a shot never crosses a wall it did not check).
- **Walls cut the step, they do not pre-empt it.** The step is shortened to the wall and the hit test runs on that part, so a fast shot still hits a target in front of a wall (a target behind it is not hit). Checking the wall first and dropping the whole step had lost those hits.
- **Only rectangles.** `add_wall_body` reads `RectangleShape2D` shapes (turned ones as their bounding box) and ignores the rest. Rooms with other wall shapes need `set_walls` rects or a new case.
- **Who tells it.** `core/` does not know rooms, so `flow` finds the static bodies on physics layer 1 in the room scene after it is in the tree and calls `add_wall_body`. `set_bounds` clears the walls, so a new run starts empty.
- **Clip from the feet.** The wizard clips the segment from its feet (always outside a wall: the body collides) to the staff tip, and casts from the clipped point. A shot from a tip behind a wall therefore starts at the wall and ends on it at the next step; the cast still spends mana and cooldown, as a swing at a wall does, but `spawn` refuses a shot that starts inside a wall, so it takes no pool slot and evicts no one. Refusing the cast instead (no mana) was tried: the 4-bot smoke failed four runs in a row with it, so it stays a spent cast. The hand point could be inside a wall for a wizard against a top wall, so it is not the start.
- **Wall hits are silent for now.** `wall_hits` is a counter; no event, spark or sound (backlog).
- **Bots.** The wave bots hold fire without a line of sight and strafe along the wall instead of walking at it. Reason: with walls they fired into pillars and the 4-bot smoke failed.

## 2026-10-18: Dodge and cast feel (C1 round 2, task 3)

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **Buffer 0.15 s for both.** A press made while the action is not yet possible counts if it becomes possible within 0.15 s (about 9 frames at 60 FPS: long enough to forgive a mistimed tap, short enough that nobody dodges "by surprise" after the cooldown). One buffered press is used once and a new press restarts the window. Pressing in an overlay, being downed or a captured wizard clears it, as before for the dodge press itself. A held `cast` is unchanged; the buffer matters for taps.
- **Invulnerability look is one rule for every kind of protection** (dodge, join 2 s, revive 1.5 s): the sprite is 55% opaque and a ring in the player colour closes over the time (full for join and revive protection until the last `INVULNERABLE_TIME`). Shape and opacity, not colour alone. The sprite's `material` stays free for the hit flash in `Feel`; only `modulate` is used.
- **Cast rate and mana cost: no change.** The fire bolt costs 5 mana at a 0.35 s cooldown: 2.9 casts a second would use 14.3 mana a second against 10 regenerated, so from a full 100 mana a wizard who holds fire without a break runs dry after about 23 s and then fires at the regeneration rate (2 a second). The bots in `test_wave_balance` fire 1 to 1.5 casts per player-second (they walk, and hold fire without a line of sight), so mana never limits them and the cost is not what decides the fight. Five damage per hit against 20 imp health is four hits. With no person's playtest on the cast rate and the bots too crude to tell (they never dodge, which is why the 1 and 2 player runs are lost), changing a number would be a guess; revisit with a playtest answer.

## 2026-10-20: C1 verdict iterate, playtest report first

**Decided by:** the owner (verdict on #97); Claude (the queue).

- The verdict is iterate. The next work is a human playtest of round 2, then the top items from its answers, not more guessing from code and bot logs: round 2's feel values are still unverified by a human.
- The plan allows at most 2 iterate rounds, counted by the owner's iterate requests on #97, not by the "round N" labels in `docs/NEXT.md` (those number batches of work: aiming, playtest fixes, art, juice and the six tasks). Round one was the owner's first `/claude` on #97 (aiming and graphics, then the 2026-10-18 playtest fixes); round two was the six tasks and their summary. This verdict, given on that summary, closes round two. After it the next checkpoint must be go or pivot, and the next assessment must say so in plain words.
- Controller and 4-player feel are still untried by a human; the playtest questions ask for them.

## 2026-10-17: Panels may hide the wizards at zoom 0.5; walls are tested

**Decided by:** the owner (#87: "It's fine as it is").

- At the widest Coop zoom (0.5), each corner panel may cover its player's wizard. The panels stay as they are: translucent at alpha 0.4.
- The staged screenshot is now named `staged_zoom_half_wizards_placed_outside_room`, because `shot_m1.gd` places the wizards outside the one-screen room to force the zoom-out, and the old name looked like gameplay. A new test, `tests/gameplay/flow/test_walls_hold.gd`, has four wizards walk and dodge into the walls through the real input path and checks that none leaves the room.

## 2026-10-21: Events for M2 (M2 part 2)

**Decided by:** Claude, following the M2 design ("Intent and result", "Projectile manager").

- `build_change_requested(player, spell, slot, component_id)`: `spell` is a `PackedInt32Array` path, as the design says. The overlay's stub sends `[0]` (spell A).
- New events: `spell_swap_requested(player)` (HUD, heard by `player`), `projectile_expired(player, position, tag)` (`core/projectiles`), `spell_changed(player, spell, description)` and `build_refused(player, reason)` (`player`), `reaction_triggered(player, reaction_id, position)` (`combat`). Each has one sender; the senders arrive in parts 3, 8 and 11, so their listeners are "none yet" in the table until then.
- `build_refused` has exactly `(player, reason)`, as in the design: the HUD shows only the reason in plain words.
- The `swap` action is bound to Q and the left shoulder, which were free. It is in `CAPTURED_ACTIONS`, so a player in the overlay or builder does not swap spells by accident.

## M2 part 3: projectile manager, part 1

- `projectile_expired` is sent only when a shot's life runs out or it ends on a wall, after the shot is removed (a handler may spawn at that spot). A hit, leaving the bounds and a cap drop send nothing: an on-expire trigger should not fire for a shot that did its job or was evicted.
- `still` is a `motion` argument at the end of `spawn` (velocity ignored), so part 4's `orbit` fits the same argument.
- The queries count a target when its hit circle overlaps the query circle (the rule of a hit) and return the nearest by centre distance. They read the grid of the latest step; `add_target` and `remove_target` outside a step mark it stale and the next query refills it. A target freed since the last step is skipped.

## M2 part 4: projectile manager, part 2

**Decided by:** Claude, following the M2 design ("`core/projectiles` grows only what the forms and modifiers need").

- Orbit and homing are separate calls, not more `spawn` arguments: `spawn_orbit(player, orbit_radius, angle, angular_speed, lifetime, ...)` and `set_homing(slot, turn_rate)`. `spawn` already takes nine arguments, and an orbit needs three more numbers. `spawn` still refuses `MOTION_ORBIT`.
- An orbit shot ignores walls (its caster holds it, and a wizard against a wall would lose the half of the ring in the wall) and ends quietly when its owner's anchor is cleared, so a wizard who leaves or falls drops their ring. A player with no anchor cannot spawn one.
- Homing keeps the speed and only turns it, toward the point found by the last search (every `HOMING_PERIOD` = 4th step, staggered by slot so a full cap does not search all at once). Range `HOMING_RANGE` = 160 px. It skips the shooter's own body and targets the shot remembers hitting; the search costs 1 work unit per target examined, so a spent budget only delays the next search. Only straight shots can home.
- `ray()` has one more optional argument than the design, `width`, so "bigger" can widen a beam. It returns the pixels reached (to the last target when `pierce + 1` were hit, else the wall or the length) and sends `projectile_impact` before each `projectile_hit`; a beam that ends on a wall sends a wall impact (not counted in `wall_hits`, which counts shots). At most `RAY_MAX_HITS` = 64 targets. Hits are found first and sent after, so a handler may free targets or fire a ray itself (an on-hit beam trigger): scratch is kept per nesting level, up to `RAY_MAX_DEPTH` = 4, deeper returns 0.
- `homing_aim(player, origin, direction, max_angle, layers)` is the beam's homing: it returns the direction bent to the nearest target in the cone, for the spell runtime to call before `ray`.
- Review of part 4: an orbit shot is an ordinary piercing shot. `pierce` is how many hits it survives (0 ends it on its first touch) and it remembers only its last `HIT_MEMORY` = 3 targets, so a ring over more than 3 enemies hits some again. There is no once-per-revolution rule: a per-target timer would need memory per shot and target, which the pool has no room for, and the orbit form (part 10) can pick `pierce` for the effect it wants. The test `_test_orbit_ring_over_a_crowd` pins this.
- Homing (shots and `homing_aim`) never picks a `LAYER_PLAYER` target, even with friendly fire on: a seeking shot should not curve into a teammate. A freed target is skipped.
- `ray()` cuts `length` to `RAY_MAX_LENGTH` = 360 px (what the 64-cell wall walk covers on a diagonal) and is not charged to the hit-work budget; the spell runtime's fire cap (part 6) bounds how many rays a spell and its nested handlers fire.
- `set_homing` returns true whenever the rate was applied, 0 included; false only for a refusal.

## M2 part 5: the compiler and limits

**Decided by:** Claude, following the M2 design ("The spell runtime lives in `core/spells/`", "Tags", "The spell limits are the performance limits").

- A recipe is a plain Dictionary (`form`, `element`, `modifiers`, `trigger`, `held`), so it can come from JSON (the combo catalogue) and from the builder alike; ids may be Strings or StringNames. `compile` never errors: bad input gives `valid == false` with a reason in plain words.
- Refused (nothing can fix it by clamping): no form, unknown id, wrong kind in a slot, more than 3 modifiers, a held spell without a trigger, nesting below depth 2, complexity over 12. Clamped and said in the description: shots over 24; speed, radius, pierce and the cooldown floor are clamped silently to the form ranges. A trigger with nothing held is valid (it costs complexity and fires nothing), so the builder can place a trigger before the spell it holds.
- Number rules: damage is form x element scale x modifier multipliers, rounded, at least 1; mana, cooldown, speed and radius multiply; shots multiply and pierce adds; homing keeps the largest turn rate; chain jumps add. More than one shot with no spread of its own opens a 30 degree fan (`SPLIT_SPREAD`), except an orbit.
- Tag layout: bit 8 is always set so no tag is 0 (combat treats 0 as "no tag"), then player (2 bits), slot (1), depth (2) and generation (3). A built spell registers its held spells at depth 1 and 2 under the same generation.
- Ring wrap: when the generation about to be reused still has live shots, its tags go into `revoked_tags` and its counts are cleared before the new spell takes the tag; the caller removes those shots. `Projectiles` gets no remove-by-tag in this part; part 6, the first caller, adds it (queued in `docs/NEXT.md`).
- Review fix: live shots are counted per generation across all depths, and a generation's profiles are freed together, because a shot that fires a held spell on its hit needs the depth 1 and 2 profiles after the rebuild. Part 6 starts a child's shot before it ends the parent's, and removes the shots of `revoked_tags` before the next `begin_generation` or `shot_ended`. New limits in `SpellLimits`: chain jumps 6, timer interval 0.1 to 10 s, lifetime 0.05 to 20 s. A malformed recipe field (wrong type) is refused with a reason. The compiled spell keeps its form and element display names, so the description needs no second registry look-up.
- `Spells.registry` can be set to a stand-in with `get_resource(folder, id)`, so the tests need no content files.

## M2 part 6: casting and triggers

**Decided by:** Claude, following the M2 design ("How a held spell fires", "Tags", "Hits, statuses and reactions").

- **The end of a shot is a signal of the manager, not an event.** `Projectiles.shot_ended(tag)` is sent for every tagged shot that ends, after its `projectile_hit` or `projectile_expired` handlers, so a held spell is started before its parent is counted out (the order part 5 asked for). It is not on the bus (`core/events` is for areas talking to each other; this is core talking to core) and it needs no change in the events table. `remove_by_tag` is the one silent removal, because the caller revoked those tags.
- **Per-shot state lives in `Spells`, keyed by projectile slot.** The manager keeps no spell data. `Spells` has packed arrays (fires left, chain left, previous target, timer clock) indexed by slot and valid only while the shot's spawn number (`get_seq_of`) matches; the manager sets `event_slot` while a hit or expiry event is sent so the handler knows which shot it is. The record is written back before any child is spawned, because a child can take the slot of a shot that just ended.
- **A beam is one shot, fired and ended inside the call.** Its context (tag, direction, fires left) is kept in fields while `ray()` runs and restored afterwards, so a held beam fired from a hit handler nests. A beam's chain jumps do not nest: `ray()` allows only 4 levels but a chain may have 6 jumps (and split or pierce beams jump from several hits), so a jump is put in a fixed 64-entry queue and the outermost beam casts the queue, in order, after its own `ray()` returns. A full queue drops the jump and counts it in `chains_dropped`. A beam whose `ray()` did nothing fires no on-expire spell. A beam fires an on-expire spell at its end, has no timer, and passes the target that fired it to `ray(..., exclude)` instead of waiting 0.1 s.
- **Where a held spell goes.** From the hit point (expiry: 2 px back along the path, so a shot that died on a wall fires in front of it; timer: the shot's place); along the shot's velocity, or outward from the caster's anchor for an orbit or still shot; the source target is excluded for 0.1 s (`Projectiles.exclude`, one target per shot).
- **Fire cap.** `MAX_FIRES_PER_STEP` (32) is per player and counts held spells fired, from every slot and depth. The window is one `Spells.step` to the next (hits of the projectile step in between count). A dropped fire consumes nothing: the shot keeps its fires and a timer waits its next interval.
- **Chain** picks the nearest other target within 96 px that is neither the one just hit nor the one before it, so two enemies are not bounced between. The chain shot is a plain straight shot of the same tag (speed at least 300 px/s) that carries the trigger's fires left.
- **`hit_profile(tag)` returns a `HitProfile`** (damage, knockback, element, status) made once per compiled spell, so a hit allocates nothing and `combat` reads no spell field. Knockback is one constant (120, M1's value) until a form or modifier needs its own. `combat` is switched over in part 7; M1's table stays until then.
- **`install` is the call for a build.** `begin_generation` stays as in part 5; `install` also removes the revoked shots, so no caller can forget to.

## M2 part 7: elements and statuses

**Decided by:** Claude, following the M2 design ("Hits, statuses and reactions").

- **Status numbers are in the element, the rules are in `combat`.** `status_strength` means: burn damage per second; the percent of speed chill takes (capped at 90%); the percent of the hit's damage a shock jump deals; the percent of extra damage a hex adds. First values: fire burn 2/s for 3 s, frost chill 40% for 3 s, storm shock 75% for 4 s, void hex 25% for 4 s. All elements keep `damage_scale` 1.0 until the combo test retunes them.
- **Stacking.** Burn, shock and hex refresh their time and keep the stronger number; they do not add up. Chill adds a stack; the third freezes for 1 s (`FREEZE_TIME`) and clears the chill; a frozen enemy takes no more chill, so hitting it cannot extend the freeze (Stillness, part 8, extends it on purpose).
- **Order in one hit:** hex raises the damage and turns the knockback into a half-strength pull toward the hit; a shock is used up and jumps after the damage (also when the hit kills); then the hit's own status goes on, only if the target survived. So the hit that applies a status never feels it itself.
- **The jump** goes to the nearest other enemy within 64 px, deals the damage times the share (at least 1), pushes nothing and puts on no status, so shock cannot chain forever. The neighbour comes from the projectile manager's target grid, rebuilt each step: an enemy that joined this frame is found next frame.
- **Burn** deals whole points of damage (a fraction is carried) through the same pipeline as `hit()`, so a hex raises it and the caster gets the kill credit. It is quiet: a tick that leaves the enemy alive sends no `damage_dealt`, so Feel's hit-stop, shake, spray and sound and the AI's hurt pose do not fire twice a second per burning enemy. The tick that kills sends `damage_dealt` and `enemy_died` as any kill does.
- **A frozen enemy still hurts on contact.** Freeze stops it moving and attacking with shots, not touching; a wizard must not stand in it. Tested.
- **A shock is spent only by a hit that counted.** Burn is collected during the status loop and sent after it, as contact hits are.
- **The AI is slowed by `Combat.speed_factor(enemy)`** (1 free, less when chilled, 0 frozen), applied to walking and to the windup and recover timers, so a frozen imp's telegraph stops where it is and the warning stays honest. Knockback is not scaled.
- **Players get no statuses** from player spells (friendly fire is damage only), as the design says.
- **Tints and icons use palette colours only** (STYLE.md has no ice or storm colour): fire is Fire base, frost is Player 1 light blue, storm is Spark gold, void is Player 4 light purple. Frost and void are close in hue to players 1 and 4, which STYLE.md warns about for base colours; the art pass (M2 part 26) checks this on one sheet and may ask for new palette entries (an owner decision).

## M2 part 11: player and flow on the new runtime

**Decided by:** Claude, following the M2 design ("Building spells, without anyone waiting", "The fire bolt migrates").

- **Slot numbers in `build_change_requested`.** The design left the meaning of `slot` open. It is the position in a spell's chain: 0 form, 1 element, 2 to 4 modifiers, 5 trigger; an empty `component_id` clears the slot. Modifiers stay in a compact list: a new one goes in the first free place, clearing one closes the gap. Clearing the trigger drops the held spell with it, as a held spell without a trigger does not compile.
- **A held spell is reached by the path** (`[0, 0]`), and the held part is created by the first request that names it (it still needs a trigger, or the compile refuses it).
- **A change is made on a copy of the recipe** and kept only if `Spells.compile` accepts the whole thing, so a refusal changes nothing and the old spell keeps casting. The bag and the component's `kind()` are checked first, each with its own reason.
- **`spell_changed` always names the prepared spell** (`[0]` or `[1]`), also when the change was made in a held spell, because the whole chain is recompiled and its description covers it.
- **`player` reads no field of a compiled spell except `valid`, `reason` and `description`**, which are the answer to a compile. `spell_cast` now carries the form id of the recipe (what M1 sent as the spell id).
- **The bag is every visible component in the registry** (so the web demo offers only demo components), filled when the wizard enters the tree. M3's rewards change who fills it.
- **Cooldowns belong to `Spells`,** per player and slot, and tick on the autoload's physics step. The wizard ticks nothing, so a downed wizard's cooldown now runs on (it cannot cast anyway). A rebuild does not reset its slot's cooldown. `Flow` calls `Spells.clear()` on a new run, after `Projectiles.clear()` (which ends every counted shot), so a restart forgets all builds and cooldowns.
- **Start recipes are in `flow`:** `start_recipe_a` = bolt + fire (M1's bolt plus burn) and `start_recipe_b` = bolt, as the design says. Flow checks that both compile before it starts a run (a missing component or a refused recipe logs a warning and keeps flow idle, as a missing room does) and hands each wizard a copy. A player who leaves and rejoins mid-run gets the start spells again; builds last for a run and are not kept per slot yet (saving is `core/save`, M5).
- **The orbit anchor is the player's job** (as the M2 design says): each step the wizard calls `Projectiles.set_anchor(index, body position)`, and `clear_anchor` when it is downed or leaves the tree. The body offset is the hit circle's.
- **`SpellBase` and the legacy bolt are removed** together with `Combat`'s learning of hit profiles from `spell_cast` (every player shot now carries a tag that `Spells.hit_profile` knows). Combat keeps `set_hit_profile` for enemy shots. The scan that no script reads a spell field moved to `tests/core/test_spell_field_reads.gd` and covers the component classes and `CompiledSpell`; `HitProfile` is left out because combat reads it by design. The registry test fixtures became `FormBase` resources.
- **No event for a swap yet.** Part 18 (the corner panel shows A or B) needs one; `core/events` gets it then, with `player` as the sender.

## M2 part 12: the six modifiers

- **The modifiers are plain `ModifierBase` `.tres` files with an icon, no scripts.** Split's fan, pierce's extra targets, homing's turn and chain's jumps are all expressed by fields the compiler and the runtime already read. First numbers (the combo test and playtests retune them): split ×3 shots, ×0.5 damage, ×1.5 mana, complexity 2; pierce +2 pierce, ×0.9 damage, complexity 1; homing 3 rad/s, ×0.9 damage, complexity 2; chain 2 jumps, ×0.8 damage, complexity 2; bigger ×1.6 radius, ×1.3 damage, ×0.85 speed, ×1.15 cooldown, complexity 1; faster ×1.5 speed, ×0.75 cooldown, ×0.85 damage, complexity 1 (a review found faster free at first; the damage cost leaves it about 13% more damage per second, and two stack to about 28%). Every modifier that adds power costs something (split: damage per shot and mana; homing and chain: damage; bigger: speed and cooldown; faster: damage), so none makes another obsolete. Complexities are the design table's.
- **Owner answer on #140: option 1, no change.** `tools/check.sh` stays free of Godot; the spell validator keeps running in `ci/build/build.sh --quick --tests`, which AGENTS.md already asks contributors to run.
- **The icons are placeholders** drawn as non-overlapping SVG rects like the forms' and elements'; the part-26 art pass looks at all 18 together.

## M2 part 13: the three triggers

- **The triggers are plain `TriggerBase` `.tres` files with an icon, no scripts;** the runtime already fires them from the fields. Ids `on_hit`, `on_expire` and `timer`. First numbers from the design table (the combo test and playtests retune them): on hit and on expire fire once per shot (`max_fires` 1), complexity 1 each; timer every 0.5 s (the combos' "every half second") with `max_fires` 4, the limit, complexity 2.
- **A rune dropped by an on-hit trigger on a living target is used up on it** (it does not pierce, and the 0.1 s source exclusion ends), so a pulsing rune works best where its target moved or died. Left as is; the combo test (part 14) will show whether runes need a longer ignore time for their own source.
- **The icons are placeholders** drawn as rects like the other components'; the part-26 art pass looks at all 18 together.

## M2 part 14: the combo catalogue and test

- **The catalogue is data, the checks are a few kinds.** A row in `content/spells/combos.json` holds the recipe(s), the imps' positions, the seconds to run and a list of checks (`damaged`, `status`, `status_count`, `keeps_burning`, `reaction`, `max_shots`). One data-driven test runs every row, so a new combo (part 21, and contributors) needs a JSON row and no code, unless it needs a new check kind.
- **The arena is the real thing, not a mock:** `tests/content/spells/combo_arena.gd` wires the real registry, projectile manager, spell runtime and combat, and steps them in `project.godot`'s order. Imps are plain `Node2D`s with 400 health, so no combo kills one by accident.
- **Two draft combos reworded to what the runtime does.** "Three homing bolts that find three different imps" is now "bend toward imps well off the aim" (each shot picks the nearest target, so they may share one; a control test shows a plain fan misses those imps), and "a wide ray that reaches an imp a plain ray misses" is now "chills the imp in its lane" (the widening is about a pixel, a tuning number not worth a test).
- **The first 12 are the design's draft rows 1-12.** "Blast at the end" runs in open space; the wall case stays with `test_spells_cast.gd`. Part 21 adds the rest and makes sure each component is in two combos.

## M2 part 15: Spells opens

- **Spells is open for PRs from this part.** The README states that every new component needs at least one combo row (the combo test runs it without new test code), so the catalogue grows with the content. The ROADMAP row said "from part 11, Story from part 21", left over from before the design review; it now matches the design (15 and 23).

## M2 part 16: the builder, part 1

- **The builder sits beside the corner panel, not over it.** The design says it "expands the corner panel toward the middle"; a panel under or over the corner panel would leave about 120 px of height in a four-player quarter, too little for the chain and the bag. Beside it (about 200×170 px) a player keeps seeing their health and mana while building, and four builders and four panels fit 640×360 without touching (tested).
- **Two new events, `recipe_changed(player, slot, recipe)` and `bag_changed(player, ids)`, both from `player`.** The HUD may only show what events say, and `spell_changed` carries a description, not the chain. Sending the recipe next to `spell_changed` keeps `spell_changed` as the design has it and each event with one sender. `bag_changed` is sent when the wizard appears, so M3's rewards change who fills the bag without changing the builder.
- **Names, icons and kinds come from `Spells`** (`component_name`, `component_icon`, `component_kind`). `test_spell_field_reads.gd` rightly forbids the HUD reading a component's fields; a small accessor set in the runtime keeps that rule and gives the builder what the design asks it to show.
- **One linear focus list, with focus helping.** `core/ui_focus` moves through a plain list, so the builder lists tabs, slots, held buttons, bag rows and Close in that order, moves focus to the bag after a slot is chosen and back to the slot on `dodge`. Rows that cannot be used are disabled or hidden, and UIFocus skips them.
- **A modifier slot opens only in the first free place,** as `player` fills modifiers (a new one goes in the first free place; clearing one closes the gap). A held spell's form must be chosen first, since the compiler refuses a held spell without one; the refusal reason is shown from part 17.
- **The builder opens at any time for now.** Part 18 folds it into the quick view and part 19 makes the break between waves, as the design says.

## M2 part 17: the builder, part 2

- **The info panel sits in the quarter's free strip, not in the builder.** The builder (about 190×168) already fills the space beside the corner panel, but the strip at the screen edge under (P1, P2) or over (P3, P4) the corner panel was empty. A 112×112 panel there keeps all builders, corner panels and info panels apart (tested at 640×360). It is a top-level child of the builder, so it shows and hides with it and the builder's own layout is unchanged.
- **`Spells.builder_view` gives plain values.** `test_spell_field_reads.gd` forbids the HUD reading a `CompiledSpell`; the view returns a Dictionary (complexity of the whole spell, numbers and shot pattern of the spell at the shown level), so the compiler can change without touching the HUD. It compiles the recipe on each render (on events and key presses, never per frame).
- **The refusal reason is text and lasts until the next try.** It comes from `build_refused` for the owner only and clears on the next request, the next successful change or the next opening. It shares one text line with the component description; the reason wins while it is set.
- **Descriptions are empty until part 23:** `Spells.component_description(id)` returns "" for now; part 23 reads Story there.

## Owner: a web preview after each merge

- **`preview.yml` builds main after each merge and puts the web build at `/preview/`.** The owner wanted to see progress more often than once a day. Sessions merge about hourly, so that is about one preview an hour, and only when something changed; a newer merge cancels a build still running. It runs the same `build.sh` as the daily run (tests and smoke tests included, about 4 minutes), with no release, no itch.io, no AI and no secrets. Public-repo Actions minutes cost nothing.
- **`/nightly/` and `/play/` stay the daily releases.** Pages replaces the whole site on each deploy, so the preview rebuilds it (`smbot.site --preview`): `/nightly/` from the newest release, `/play/` from the latest stable one. The daily run puts its build at `/preview/` too, and both Pages jobs share one concurrency group so deploys never overlap.

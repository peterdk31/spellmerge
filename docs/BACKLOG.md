# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). Players' ideas wait as issues labelled `backlog` (the daily intake puts them there); this file holds Claude's own. The weekly planning run moves items from both into the work queue or `docs/NEXT.md` when their milestone comes.

## Carrier traits and card needs (owner, 2026-10-30)

Since 2026-10-30 a carrier answers yes/no questions about itself (`CarrierTraits`), each kind of card says what it needs from one (`ModifierBase.NEEDS`, `TriggerBase.NEEDS`), and `Spells.card_waste(card_id, carrier)` answers "does this card do anything on this carrier, and why not" before it is placed (docs/CARRIERS.md). What that opens, by milestone:

- **Builder: say it before the drop (M2 polish).** The builder greys a card out once it sits on a carrier where it does nothing; with `card_waste` it can mark the cards in the bag that would do nothing on the carrier being built on, while choosing.
- **Reward hints and offers (M3 rewards).** "Works with" hints on a reward from the player's own staffs ("Bounce: works on 2 of your carriers"; docs/PLAN.md's "Works with: Split, Chain"), and offers that lean away from cards that would do nothing on any carrier the player holds.
- **Bots and enemy staffs (M2–M3).** Test bots and enemies that build staffs from cards pick pairs that do something, with `card_waste`, instead of trying them.
- **Category tags on cards (M3 relics).** A designer's labels on each card (fire, melee, movement, defence...), for relics, rewards and builder filters to target ("fire cards cost no mana", "melee carriers get +1 pierce"). Rule: a tag nothing a player can see uses is removed.
- **Granted traits (M3 relics, staff types).** A relic or staff type that adds a trait to carriers ("every carrier on this staff stays in the world", so arc and magnet work on a swing; the "zaps count as hits" idea below is one). Rule: only a trait whose behaviour the runtime already runs on that carrier can be granted, and `test_card_rules` must play the card with the relic on, or the game would say a card works where it does nothing.

## From the staffs rework (pivot at C2, 2026-10-26)

For later milestones; see `docs/milestones/M2-staffs.md`, "Later".


- **Card visuals on three carriers (found 2026-10-30).** A teleport, a decoy and a familiar show none of their cards' visual styles (`look_layer`: fire's embers, frost's sparkles...): a teleport draws nothing of its own, a decoy looks like its caster, a familiar is drawn as a plain orb (`Entities`, `look_color(..., 0)`). Their blasts still show. Every other carrier draws its cards' styles.
- **More melee carriers (owner 2026-10-29, after `swing` has been played).** `lunge` (a short step forward with a hit at its end), `whirl` (a 360° sweep round the caster) and `saw` (tiny repeated hits at the tip, close to 0 mana and delay; `hold · saw`, `siphon · saw`). See M2-staffs.md, "Phase I".
- **Staff types (M3).** An always-cast slot, a shuffle staff (random order), built-in recoil, cheaper `hold`; staffs found in runs with other slot counts, delays and recharges.
- **Arc zaps and `on hit` (M3 staffs or relics, owner 2026-10-27).** For now an `arc` zap is a hit like any other, so it sets off `on hit` payloads and chains. Later that should not be the card's default but something a build earns: either an implicit mod on a staff type ("zaps count as hits") or a relic. Then the plain arc zap stops setting off `on hit`.
- **Staff spread (M3, owner 2026-10-27).** Found staffs have a `spread`: either rolled at random, or starting high and upgradable to lower values. The runtime and `spread_mult` (Sniper) are in since 2026-10-27; the dev and starter staffs aim true.
- **Relics on cards (M3).** Explosion immunity (hit kind `burst`), self-damage refunded as mana, immunity to one element, triggers that fire twice.
- **Enemy cards as rewards (M3–M4).** Elites and bosses with dearer staffs, whose cards can drop as rewards. Enemies casting from staffs moved into M2 (owner, 2026-10-27; M2-staffs.md phase F).
- **Elements on the room (M3 rooms).** Fire lights grass, frost freezes water into floor, lightning electrifies water, void breaks weak walls.
- **A map view, and other uses for A, X and Y (task, owner 2026-10-26).** The staffs moved to the shoulders, so A, X and Y do nothing in play (B opens the builder). The owner's first idea is a map view (the room sequence and where the players are, once M3 has rooms and doors); A, X and Y get their jobs then.
- **Codex of discoveries (M5).** The first time a reaction, a combo or an unknown chain happens, the game notes it (with a short clip if the recorder can do it cheaply).
- **Superseded by the pivot:** "Spell visuals round 2, part 2" (a burst per combo row) and the combo marks per combo class are replaced by the layered shot look (staffs B6); keep what still reads well.
- **Beams longer than the beam shader holds (owner, 2026-10-29).** `shot_beam.gdshader` takes 80 path points; a live beam with more (a homing beam with 9 or more pierce, a beam bouncing about 78 times) keeps its ends and sharpest turns and drops gentle curve points (`Feel._thin_beam`), so it is only lossy past 78 real turns. The full fix, if a build ever gets there: draw a long beam as consecutive meshes of up to 80 points each, with a shader flag so only the beam's true ends get flares; the shader stays the same size (a bigger uniform array is not an option: WebGL's limits and the owner's GPU, #400). The same applies to fissures: each leg of a bouncing fissure takes one of the player's 24 beam cue slots (`FORMS_PER_PLAYER`), so a fissure with more legs, or several at once, ends its oldest legs' look early.
- **The `rain` cue (from B2c).** Feel draws only `beam` and `nova` cues; the `rain` cue (`form_shown`, `length` = seconds until it falls) needs a look (B6b).

## From the actors rework (phase G, 2026-10-28)

- **Decoys and familiars as actors** (a decoy: Health and Hurtbox, no controller; a familiar: a Caster and an orbiting controller), if Entities' pooled rows start to need the actor kit.
- **AI teammates** for fewer than four players, and **bosses a player can take over**: a controller each, nothing new in the body.
- **More teams** (enemy factions that fight each other) and more than five ramps: the actor table has room; the shot shader's ramp field grows from two bits and a flag.

## From the spell visuals (owner `/claude` on #244)

- **More animation for advanced combinations (task).** The owner wants many more animations for combined spells (triggers, held spells, chains and modifiers together). Plan it after part 3 (reactions and statuses) as its own queue task: one look per combo row in `combos.json`, data-driven, with the clips `combo_*` as the proof. Also check, once the owner has seen the smaller bodies, whether `SHAPE_SCALE` is right (0.8 since #244 round 2, part 1). Part 1 of that work is done; the rest is the NEXT.md task "part 2".

## From the clip polish (#244 rework, last task)

Found by looking at all 51 clips and the four-player sheets at 1x (a clip frame is 320x180).

- **Storm bolt is thin in grey (task).** The zigzag core is one pixel wide at 12 px, so it nearly vanishes in the greyscale strip and on a busy floor. Try a two-pixel core or a brighter edge.
- **The coop clips show two players, not four (task).** `reaction_*_coop` cannot show the four-player load; add a four-player clip of the busiest combo (fan, chain, orbit) to judge readability and `Feel.PARTICLE_LIMIT` together.
- **Orbit bodies speckle at 1x (task).** The beads of `combo_fire_fan_orbit` look noisy beside the flame body, because each is a few pixels in the owner's edge and the element colour. Try a solid bead with a one-pixel light centre.
- **Shots are hard to find in the four-wizard arena sheet (task).** `arena_four_wizards` has no shots in flight; stage a four-player volley sheet for the next look.

## From the clip recorder (#245, part 1)

- **Hit sprays are not in the clips (task).** Feel's bursts are `CPUParticles2D`, which advance by each frame's real time, so the recorder (`tests/clips/stage.gd`, `HIT_SPRAYS = false`) leaves them out to keep two takes identical. The spell visuals tasks (#244) will want particles in the clips: either make a burst advance by the stage's own steps (a burst Feel steps itself, or sprites in a pool), or record at a fixed engine frame time. Then turn `HIT_SPRAYS` on and record every clip twice again (`diff -rq`).
- **Hit-stop is not played in clips.** The stage runs Feel without `Engine.time_scale`, so a clip shows a hit without its freeze. A clip could repeat frames for the stop's length.

## From the HUD and Builder usability walkthrough (owner `/claude` on #4, point 2)

- **Glyphs where the game still tells the player what to press (task, owner `/claude` on #4).** The builder's hint line now shows glyphs (`hud/widgets/hint_line.gd`). Still to do: when the overlay and the Bag list get a hint line they use the same widget; the "how to open the overlay" item below becomes a glyph of `overlay`; the main menu and any "press to join" text use the `join` glyph. Mouse clicks on the builder show nothing yet.
- **A player cannot hand their slot to another device (task, owner `/claude` on #4).** The glyphs follow a player's device live, but a device only changes through leave and join (the keyboard joins only as P1). "Pick up the keyboard while holding an Xbox pad" does nothing today. A handover rule needs a design: for a single joined player, `join` from the other family could move the slot, and a second player's pad would still join as P2. Decide with the owner before building it.
- **Glyph art is drawn in code (task).** `action_glyph.gd` draws key caps, round buttons and PlayStation symbols with 8 px text, so it is not pixel art in style N. Replace it with 10 px SVG sprites per family when the art direction has a glyph set (add them to `art/manifest.json`).
- **Stick and d-pad glyphs are missing (task).** The face buttons, the shoulders and triggers, Start, Join and Leave have glyphs; move hints would need a stick and a WASD group.
- **The pause menu has the plain focus look and no hint line (task).** Give it the `BuilderButtonFocus` look and a hint line (A to pick, B back).
- **The refusal text says "(F)" (task).** "Pick a form (F) first" comes from `gameplay/player/player.gd`; the slot is now named "Form" in the builder, so drop the letter there.
- **Long descriptions are cut at three lines (task).** The note under the info panel ends in "..." for several components. Shorten the texts, or give the note more room by dropping the stats line when a description is long.
- **What " *" means (task).** The bag marks the current component with " *". Try "(in slot)" or a check mark glyph, if it fits the 80 px row.
- **The quick view does not say the full builder returns (task).** Add "Full builder after the wave" under the quick view's chain, if the quarter has room.
- **No hint for how to open the builder or the pause menu (task).** A new player has to know B and Start. Show the glyphs once in the corner panel after the first room, or on the main menu (a one-glyph job with `ActionGlyph`).

## From the web stress frame

- **Real-GPU web frame rate (playtest question).** The web numbers so far come from a browser without a GPU (software rendering). Ask web players in the weekly playtest how a busy room feels (frame rate in a four-player fight in Chrome and Firefox on real hardware), and put what they say next to the stress run's `frame parts` lines. If the weekly run does not ask, ask the owner to add a line to `.github/maintainer/plan.md`.

## From the reactions walkthrough

- **One shape for all six flashes (task).** Reactions differ by colour and name only. Give each its own shape (a ring for Shatter, drops for Thaw, ...) so colour-blind players also read them at a glance; same flash slots. Colour alone is weak for the hue-confusable pairs: Kindle (red) and Thaw (green), Thaw (green) and Flare (yellow); Rift and Stillness are also close (RGB distance about 0.48).
- **Dark names on the dark floor (task).** The Kindle (red) and Stillness (blue) names at 8 px are dim; try a lighter outline or a pale halo.
- **Four reaction flashes at once (task).** `REACTION_SLOTS` is 4, so a fifth reaction inside a quarter second takes over the oldest flash and name. Check in a four-player fight whether 6 reads better.

## From M2 part 29 (the builder walkthrough)

- **The mouse (task).** The builder, the overlay and the quick view ignore the mouse. Add a mouse for P1's panel only: hover mark (a "> " or an outline, not colour alone), click to activate, a click outside the builder closes nothing. Needs the hover to go through `UIFocus` so the owner's device still wins. M4 polish.
- **Picking modifiers is still one slot at a time (task).** A form and an element are four presses; each modifier is about three (dodge, move to its slot, cast, move to the row, cast). Try advancing through the modifier slots too, or a "next free slot" shortcut, once a real playtest says what players do.
- **No hint on a disabled slot or button (task).** A greyed modifier slot or "Held >" says nothing about why (needs the slot before it filled, needs a trigger). Show it in the note when focus rests on it (it skips disabled controls today, so this needs a way to read them: a `UIFocus` change, too big for the quick view walkthrough).
- **The held-spell levels are two small buttons (task).** "Held >" and "< Up" at 10 px are easy to miss; the title says "held 1" but not which trigger holds it. Show the holding trigger's name in the title.
- **Refusals name no slot for a held spell (task).** "Pick a form (F) first." is shown for the held spell too, where the title says "held 1"; the note could start with "Held spell:" when `level() > 0`.

## From M2 part 16 (the builder)

- The builder ignores the mouse; docs/milestones/M2-spell-system.md wants the mouse to work on P1's panel only. Add it with part 17 or in M4's polish, with a hover mark that is not colour alone.
- The builder gives `UIFocus` a fresh control list (and restores focus) when a bag that grows while it is open needs more rows; `UIFocus` has no "replace controls" call, so this re-opens the panel quietly. Give `UIFocus` one if M3's rewards make it flicker.
- `Flow.stop_run()` leaves open overlays and builders as they are (only `run_ended` closes them), so a stopped run in a test or a screenshot needs the owner to close them first.
- The builder panel is as translucent as the corner panels (the game shows through); if it reads badly over busy rooms, give it an opaque `PanelContainer` variation in the theme.

## From M2 part 7

- Nothing shows a status on an enemy (no tint, icon or sound). Part 8 adds a flash, a number and a sound by id through `Feel`; a lasting look (blue while chilled, flames while burning) is not planned yet.
- `Combat` status reads (`speed_factor`, `status_left`, `chill_stacks`, `apply_status`) each do a linear `_enemies.find`, and the AI calls `speed_factor` per imp per step: O(n²) at 100–200 enemies. Native `find` is probably fine; measure it in the M2 part 24 stress scene, and if it shows, let the enemy cache its row or id.
- `Combat.speed_factor` is the one reader of slow and freeze. M3's enemy base should multiply walking and attack timers by it once, so every enemy type respects it.

## From M2 part 20

- **Building questions in the weekly playtest.** Nothing makes the weekly run ask about building; it writes from what changed. If the next weekly playtest has no building questions (is the builder readable, are refusals clear), ask the owner to add a line to `.github/maintainer/plan.md`.

## Questions for the owner

Not kept here any more: each question is an issue labelled `owner-question` (docs/DECISIONS.md, "The owner inbox").

## Needs an owner decision

(none: the web 4-bot run, the web load time and the Style Guide page were added in an owner session on 2026-10-17; the WASM projectile timing and the stress run now have their runners (`--projectile-timing`, `--stress`); the web projectile timing step already exists in `build.sh` and waits for `TIMING OK`, which the runner prints, but it has not been run yet; only the `--stress` step is missing, asked in #166)

## Audio needs

Sounds the game asks for by id and does not have yet. A missing sound is silent (`Registry.get_sound` returns `null`), never an error. Claude makes each one itself (synthesised from code) or the owner commissions it; a player's suggestion for one comes in through the intake. Files are `.ogg` in `audio/`, listed in `audio/manifest.json`; the id is the file name without the extension.

- **`cast`** (M1 part 10). The sound of a wizard releasing a spell: a short, soft whoosh, under 0.5 s. Heard every cast, from up to four players, so it must not tire the ear.
- **`hit`** (M1 part 16). A projectile or spell landing on an enemy: a short, dry impact, under 0.3 s. Heard many times a second in a fight.
- **`enemy_death`** (M1 part 16). An enemy dying: a small burst or fizz, under 0.6 s, clearly different from `hit`.
- **`player_downed`** (M1 part 16). A wizard going down: a low, soft thud or sigh, under 0.8 s, calm rather than alarming.

- **`reaction_discharge`, `reaction_overload`, `reaction_superconduct`** (#243 part 2). Feel asks for each by id when the reaction fires and nothing plays until the `.ogg` is in `audio/sfx/`. Same family as the six older `reaction_<id>` sounds (none exists yet): short (under 0.4 s), a crackle for the discharge, a dull thump for overload, a glassy ping for superconduct. Heard in every fight with lightning, so they must not tire.
- **`possess`** (actors G9). A possession starting: Feel plays it on `possess_started` (`POSSESS_SOUND`), and the `possess` card names it; silent until the `.ogg` exists. A short, eerie swell or reversed whoosh, under 0.5 s, that says "someone else drives this body now", clearly apart from `cast` and `hit`. Rare (a dear card, one possession per cast), so it may stand out more than the cast sound.

## Foundation

Weak spots found in the architecture review of 2026-10-20 (docs/ARCHITECTURE.md). Each is fixed by the feature that needs it, not ahead of it.

- **The wave is a constant in `flow`.** `WAVE`, its growth and the one enemy id are consts, so a second enemy type or a room with its own waves means editing `flow.gd`. M3 should move the wave to data on the room (a `WaveSet` resource: enemy ids and counts per wave) and let `Flow` read it.
- **`player.gd` does too much (750 lines).** Movement, the dodge, the animation strips, the dodge ghosts, the staff overlay and revive all live in it. Split the look (strips, ghosts, staff) into a child node the script drives when a second player-like body (a ghost, a pet) or a different wizard art style needs it.
- **`ai.gd` has one attack.** The windup, telegraph and shot are one pattern in one script. A second enemy needs an attack as a small resource or script that `ai.gd` runs; do this with the second enemy, not before.
- **`flow.gd` preloads the default wizard scene from `content/`.** A lower layer names a higher one. Move the default into a registry folder or a setting when a character picker needs it.
- **Sounds and effects by id only in `feel`.** Other areas that want a sound (HUD clicks, UI) have no shared way yet; add one when the HUD needs it.

## Spell runtime (found in M2 part 6)

- **Held spells of a rune start inside their target.** A held rune (or any slow shot) born on a hit overlaps the target that fired it, and the 0.1 s exclusion ends before a slow shot has left it, so it hits the source after all (pinned by `test_a_slow_excluded_shot_still_hits_its_source_after_the_time`; change that test when this is fixed). Part 10's rune form should be tuned (or the exclusion made "until clear of the target") when the forms exist.
- **A held bolt does the same (found in part 21).** A fast shot born on a hit at the contact point also crosses the target and hits it again within the first 0.2 s (a nova or bolt on hit holding a bolt never reaches the imp behind). Making the exclusion "until clear of the target" would fix both; the combo "Hexed fire burst" uses a held nova to avoid it.
- **A beam has no timer trigger and no exclusion in time.** A ray is instant, so its timer never ticks; an on-expire trigger fires at the beam's end. Fine for the first combos; revisit if a combo wants a beam that "keeps firing".
- **`tests/bots/test_wave_balance.gd` is timing-dependent.** The 1-player bot cleared the room in 39 s in one run and was not done after 120 game seconds (37 casts) in another, on unchanged gameplay code. It follows real frame time; make it deterministic (seeded, fixed step) in part 20.
- **`player` must feed `Projectiles.set_anchor` every physics step** for orbit spells to cast (part 11); `Spells.cast` refuses an orbit with no anchor.

## Later milestones

- **A downed mid-run joiner.** A joiner has 2 s of protection; once downed they are revived like anyone else (`coop`).

- **Egress firewall for Claude's shell sessions.** Allow only GitHub and the Anthropic API from the implement and revise runners (for example with iptables and GitHub's published IP ranges), so a misled session can't send its read-only or Claude token anywhere else. This needs care, because the action installs Claude Code at start-up.
- **Manifest validator (M1).** Every asset needs a line in `art/manifest.json` or `audio/manifest.json`, but nothing checks it yet, and a PR could change other assets' records by mistake. A validator should require an entry for every asset and allow only changed entries for files the PR adds or changes.
- **llms.txt link check.** A small check (in `tools/` or `ci/`, so owner-added) that every relative link in `llms.txt` exists and every `README.md` in the repo is listed, so the index can't drift. Until then, a PR that adds or removes a doc updates `llms.txt` by hand.
- Cross-player spell linking (one player's frost plus another's storm), asynchronous, with no waiting (docs/PLAN.md, "Co-op rules").
- Windows code signing, before Steam (M7).
- GUT test framework as an owner-added addon, when game code needs unit tests (M1).
- **Feedback and Contribute buttons** (docs/PLAN.md): opening web pages is allowed only in `core/links/links.gd`, through its constant `URLS` table of the project's own addresses (docs/DECISIONS.md, "Opening web links, narrowly").

- **Wave announcement.** A new wave is shown only by the small "Wave N" line in the HUD; there is no pop, flash or sound, the 3 s gap between waves is silent, and imps appear at once with no spawn telegraph. Add a short "Wave N" pop and a spawn flash, then retune the wave numbers by play.
- **Wall hit sound and bot dodging.** A shot that ends on a wall now shows chips and a spark (`projectile_impact`) but still makes no sound; add one when the audio ids exist. The wave bots (`tests/bots/bot.gd`) now check the line of sight and strafe around pillars, but still never dodge, so the `BALANCE:` lines for 1 and 2 players often end in a loss.

- **Move the big test files to `tests/support/suite.gd`.** Old scripts (`test_projectiles.gd` 760 lines, `test_feel.gd`, `test_coop.gd`, `test_input.gd`, `test_ui_focus.gd`, `test_overlay.gd`, `test_panels.gd`, `test_player_*`, `test_flow.gd`, `test_combat.gd`, `test_fire_bolt_m1.gd`, which part 11 deletes with `legacy/`) run every check in one `_initialize` and share one `_failures` list, so a failure in a setup step hides the rest. When a task touches one, split it into `test_*` methods on the suite with a small fixture (see `tests/gameplay/ai/ai_fixture.gd`), one behaviour each, and drop checks of tuning numbers and looks. Do not rewrite them in one go.
- **Pillar tops are 60% opaque.** `PillarTops` is drawn translucent so a wizard standing behind a pillar still shows through, but a head under a half-transparent capital can look like a rendering fault and weakens the 2.5D look. After a human playtest, revisit: for example fade the top only while a character overlaps it, and draw it fully opaque otherwise.
- **Telegraph dash on the lane.** The dash texture is a plain 8×8 tile; if the owner wants a different look (a pulsing ring at the end, an animated dash), it needs art with more frames, not code.

## From M2 part 18 (quick view walkthrough)

- **A swap needs the menu closed (task).** `swap` is ignored inside the quick view (a menu holds input), so a player closes it, swaps and opens it again (four presses). Consider a swap that works there, or a "Swap" button, once a playtest says whether players build mid-wave.
- **The drop list names no slot (task).** It lists components only; a short heading ("Element" / "Modifier M1") would help, but the longest list of ten fills the quarter already.
- **Read-only slots look like disabled ones (task).** The quick view greys the chain because it is read only; next to the one live button it reads as broken. Needs a non-grey read-only look (a theme variation).

## From #243 part 1 (Lightning)

- **The quick drop list and the overlay's list cap at 11 rows (task).** Each new element or modifier adds a row to the longest list; at 12 px rows and 8 px text 11 rows fit a player's quarter at 640×360, a 12th does not. Needs a list that scrolls or pages (UIFocus must follow it), or two columns in the quick view. Do it before the next element or modifier is added.
- **Shader kinds are a number scheme (task).** Shapes, trail marks and form bodies share one 0–15 kind in the shot's custom data, and adding a shape moves the others. A table in the manager (kind per shape and form) would make the next shape one line.

## From #243 part 2 (extensibility proposals, not built)

- **Statuses as data (proposal).** A new status needs code in `gameplay/combat/combat.gd` (two or more parallel arrays, an apply, a tick, a remove and a `match` line in five places), `core/spells/spells.gd` and `core/spells/validator.gd`. A status table (a resource per status: duration, strength, whether it ticks, what it changes) would make a status with no special behaviour new files only. Static's discharge would stay a script.
- **Reaction look in the row (proposal).** A reaction's colour and power live in the Feel preset by id, so a new reaction edits `gameplay/feel/presets/feel_preset.gd` and the colour test's count. `ReactionRow` could carry `color` and `power` and Feel read them from the table.
- **Element shape and status look as fields (proposal).** `shape` numbers are drawn in the shader and the manager; the status look is a preset dictionary. An element that names a palette ramp and an overlay colour would not need the Feel preset or the STYLE palette edited for a look that reuses existing ones.
- **A colour-distance check on the table, not a hand count (task).** `test_feel_reactions.gd` asserts the number of colours (nine); it should read the reaction ids from `reactions.tres` plus `discharge` so a new reaction fails only if its colour is missing or too close.
- **The discharge arc is a straight-segment zigzag (polish).** At the clip's 2x scale it reads as bracket-like corners; a thinner line with more corners, or a short flicker (two frames of a different jag), would look more like lightning.
- **The Shield icon fails `test_svg_art` (found 2026-10-29).** `content/spells/modifiers/shield/icon.svg` uses `<path>` (only `<rect>` is allowed) and has gaps in its outline; redraw it with rects like the Blast icon.

## Ideas from the community

- **Ring multicast (owner, 2026-10-30, idea).** A multicast that fires the carrier's shots in a full circle round the caster, like nova does for a bolt, so any carrier can be a ring. Not scheduled.

- **Relic idea: The Nuke (#416, p3, idea).** For M3, when relics arrive: no mana regeneration, every cast spends all current mana, a full refill every X seconds. Open: how a cast scales with the mana spent, and the refill interval.

- **Card rules R3, rule 2 checks.** `tests/core/test_card_rules.gd` does not yet check that a card's effect survives a bounce, a chain jump, an echo and a payload firing (M2-rules.md, "R3", last bullet). Add probes that compare the second leg's trace. Schedule it before the C2 checkpoint (it is the check for the "nothing takes a card away" rule of #453); it is not in `docs/NEXT.md` because R3 itself is done and nothing else waits on it. R4 only adds cards that turn W into ✓, so the work does not change, but each new ✓ needs a probe.

- **Summonable pet that draws enemy fire (#208, p3, idea).** Kept on the backlog on 2026-10-23, not scheduled; deferred until M3's design is written (reasoning in `docs/DECISIONS.md`). Prefer a spell route (a "familiar" form or modifier) over a pet system; decide in M3 (relics, run rewards) and M5 (unlock). Needs: an enemy targeting rule in `gameplay/ai` that can prefer a decoy, and health for a shot-like target in `gameplay/combat`.

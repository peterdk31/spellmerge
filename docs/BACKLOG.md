# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). Players' ideas wait as issues labelled `backlog` (the daily intake puts them there); this file holds Claude's own. The weekly planning run moves items from both into the work queue or `docs/NEXT.md` when their milestone comes.

## From the HUD and Builder usability walkthrough (owner `/claude` on #4, point 2)

- **Glyphs where the game still tells the player what to press (task, owner `/claude` on #4).** The builder's hint line now shows glyphs (`hud/widgets/hint_line.gd`). Still to do: when the overlay and the Bag list get a hint line they use the same widget; the "how to open the overlay" item below becomes a glyph of `overlay`; the main menu and any "press to join" text use the `join` glyph. Mouse clicks on the builder show nothing yet.
- **A player cannot hand their slot to another device (task, owner `/claude` on #4).** The glyphs follow a player's device live, but a device only changes through leave and join (the keyboard joins only as P1). "Pick up the keyboard while holding an Xbox pad" does nothing today. A handover rule needs a design: for a single joined player, `join` from the other family could move the slot, and a second player's pad would still join as P2. Decide with the owner before building it.
- **Glyph art is drawn in code (task).** `action_glyph.gd` draws key caps, round buttons and PlayStation symbols with 8 px text, so it is not pixel art in style N. Replace it with 10 px SVG sprites per family when the art direction has a glyph set (add them to `art/manifest.json`).
- **Stick, d-pad and trigger glyphs are missing (task).** Only the face buttons, left shoulder, Join and Leave have glyphs; move hints would need a stick and a WASD group.
- **The overlay menu and the Bag list still have the faint focus and no hint (task).** Give `widgets/drop_choices.gd` and the overlay the `BuilderButtonFocus` look and a hint line.
- **The refusal text says "(F)" (task).** "Pick a form (F) first" comes from `gameplay/player/player.gd`; the slot is now named "Form" in the builder, so drop the letter there.
- **Long descriptions are cut at three lines (task).** The note under the info panel ends in "..." for several components. Shorten the texts, or give the note more room by dropping the stats line when a description is long.
- **What " *" means (task).** The bag marks the current component with " *". Try "(in slot)" or a check mark glyph, if it fits the 80 px row.
- **The quick view does not say the full builder returns (task).** Add "Full builder after the wave" under the quick view's chain, if the quarter has room.
- **No hint for how to open the overlay (task).** A new player has to know the `overlay` button. Show it once in the corner panel after the first room, or on the main menu (now a one-glyph job with `ActionGlyph`).

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

## Ideas from the community

- **Summonable pet that draws enemy fire (#208, p3, idea).** Kept on the backlog on 2026-10-23, not scheduled (reasoning in `docs/DECISIONS.md`). Prefer a spell route (a "familiar" form or modifier) over a pet system; decide in M3 (relics, run rewards) and M5 (unlock). Needs: an enemy targeting rule in `gameplay/ai` that can prefer a decoy, and health for a shot-like target in `gameplay/combat`.

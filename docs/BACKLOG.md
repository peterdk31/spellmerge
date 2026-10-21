# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). The weekly planning run triages Discussions ideas into this file and moves items into `docs/NEXT.md` when their milestone comes.

## Questions for the owner

Not kept here any more: each question is an issue labelled `owner-question` (docs/DECISIONS.md, "The owner inbox").

## Needs an owner decision

(none: the web 4-bot run, the web load time and the Style Guide page were added in an owner session on 2026-10-17; the WASM projectile timing waits only on the runner in `docs/NEXT.md`)

## Audio needs

Sounds the game asks for by id and does not have yet. A missing sound is silent (`Registry.get_sound` returns `null`), never an error. The weekly run opens one `now` issue per line for Audio contributors. Files are `.ogg` in `audio/`, listed in `audio/manifest.json`; the id is the file name without the extension.

- **`cast`** (M1 part 10). The sound of a wizard releasing a spell: a short, soft whoosh, under 0.5 s. Heard every cast, from up to four players, so it must not tire the ear.
- **`hit`** (M1 part 16). A projectile or spell landing on an enemy: a short, dry impact, under 0.3 s. Heard many times a second in a fight.
- **`enemy_death`** (M1 part 16). An enemy dying: a small burst or fizz, under 0.6 s, clearly different from `hit`.
- **`player_downed`** (M1 part 16). A wizard going down: a low, soft thud or sigh, under 0.8 s, calm rather than alarming.

## Foundation

Weak spots found in the architecture review of 2026-10-20 (docs/ARCHITECTURE.md). Each is fixed by the feature that needs it, not ahead of it.

- **The wave is a constant in `flow`.** `WAVE`, its growth and the one enemy id are consts, so a second enemy type or a room with its own waves means editing `flow.gd`. M3 should move the wave to data on the room (a `WaveSet` resource: enemy ids and counts per wave) and let `Flow` read it.
- **`player.gd` does too much (750 lines).** Movement, the dodge, the animation strips, the dodge ghosts, the staff overlay and revive all live in it. Split the look (strips, ghosts, staff) into a child node the script drives when a second player-like body (a ghost, a pet) or a different wizard art style needs it.
- **`ai.gd` has one attack.** The windup, telegraph and shot are one pattern in one script. A second enemy needs an attack as a small resource or script that `ai.gd` runs; do this with the second enemy, not before.
- **`SpellBase` is the M1 shape.** One set of numbers and `_fire()`. M2 replaces it with components; keep the callers on `cast()`, `hit_tag()`, `hit_damage()` and `hit_knockback()` only (a test already fails when anyone reads a field).
- **`flow.gd` preloads the default wizard scene from `content/`.** A lower layer names a higher one. Move the default into a registry folder or a setting when a character picker needs it.
- **Sounds and effects by id only in `feel`.** Other areas that want a sound (HUD clicks, UI) have no shared way yet; add one when the HUD needs it.

## Later milestones

- **A downed mid-run joiner.** A joiner has 2 s of protection; once downed they are revived like anyone else (`coop`).

- **Egress firewall for Claude's shell sessions.** Allow only GitHub and the Anthropic API from the implement and revise runners (for example with iptables and GitHub's published IP ranges), so a misled session can't send its read-only or Claude token anywhere else. This needs care, because the action installs Claude Code at start-up.
- **Manifest validator (M1).** Outside PRs may add lines to `art/manifest.json` and `audio/manifest.json`, so a PR could also change other assets' records. A validator should allow only entries for files the PR adds.
- **llms.txt link check.** A small check (in `tools/` or `ci/`, so owner-added) that every relative link in `llms.txt` exists and every `README.md` in the repo is listed, so the index can't drift. Until then, a PR that adds or removes a doc updates `llms.txt` by hand.
- Cross-player spell linking (one player's frost plus another's storm), asynchronous, with no waiting (docs/PLAN.md, "Co-op rules").
- Windows code signing, before Steam (M7).
- GUT test framework as an owner-added addon, when game code needs unit tests (M1).
- **Feedback and Contribute buttons** (docs/PLAN.md): opening web pages is allowed only in `core/links/links.gd`, through its constant `URLS` table of the project's own addresses (docs/DECISIONS.md, "Opening web links, narrowly").

- **Wave announcement.** A new wave is shown only by the small "Wave N" line in the HUD; there is no pop, flash or sound, the 3 s gap between waves is silent, and imps appear at once with no spawn telegraph. Add a short "Wave N" pop and a spawn flash, then retune the wave numbers by play.
- **Wall hit sound and bot dodging.** A shot that ends on a wall now shows chips and a spark (`projectile_impact`) but still makes no sound; add one when the audio ids exist. The wave bots (`tests/bots/bot.gd`) now check the line of sight and strafe around pillars, but still never dodge, so the `BALANCE:` lines for 1 and 2 players often end in a loss.

- **Move the big test files to `tests/support/suite.gd`.** Old scripts (`test_projectiles.gd` 760 lines, `test_feel.gd`, `test_coop.gd`, `test_input.gd`, `test_ui_focus.gd`, `test_overlay.gd`, `test_panels.gd`, `test_player_*`, `test_flow.gd`, `test_combat.gd`, `test_bolt.gd`) run every check in one `_initialize` and share one `_failures` list, so a failure in a setup step hides the rest. When a task touches one, split it into `test_*` methods on the suite with a small fixture (see `tests/gameplay/ai/ai_fixture.gd`), one behaviour each, and drop checks of tuning numbers and looks. Do not rewrite them in one go.
- **Pillar tops are 60% opaque.** `PillarTops` is drawn translucent so a wizard standing behind a pillar still shows through, but a head under a half-transparent capital can look like a rendering fault and weakens the 2.5D look. After a human playtest, revisit: for example fade the top only while a character overlaps it, and draw it fully opaque otherwise.
- **Telegraph dash on the lane.** The dash texture is a plain 8×8 tile; if the owner wants a different look (a pulsing ring at the end, an animated dash), it needs art with more frames, not code.

## Ideas from the community

(none yet)

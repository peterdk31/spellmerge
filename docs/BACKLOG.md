# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). The weekly planning run triages Discussions ideas into this file and moves items into `docs/NEXT.md` when their milestone comes.

## Questions for the owner

Not kept here any more: each question is an issue labelled `owner-question` (docs/DECISIONS.md, "The owner inbox").

## Needs an owner decision

- **Run the 4-bot test in the Linux export (M1 part 21).** `export_presets.cfg` has a new preset, `Linux Test` (same as `Linux` but `exclude_filter=""`, exported to `build/linux-test/`), because the shipped presets exclude `tests/*` and the test must not be shipped. `ci/build/build.sh` is owner-only, so the owner adds this at the end of `export_all()`, after the "Boot smoke test (exported Linux build)" step (`package()` zips only web, windows and linux, so the test build is never released):

  ```bash
  step "4-bot test (exported Linux build with tests)"
  rm -rf build/linux-test && mkdir -p build/linux-test
  godot_checked export-linux-test "$GODOT" --headless --path . --export-release "Linux Test" build/linux-test/Spellmerge.x86_64
  [[ -s build/linux-test/Spellmerge.x86_64 ]] || { echo "::error::Linux Test export produced no binary"; exit 1; }
  godot_checked four-bot-linux build/linux-test/Spellmerge.x86_64 --headless --script res://tests/smoke/four_bot_smoke.gd
  ```

  Not verified: no session may run the export, so it is untested that an exported binary accepts `--script` and that the `Linux Test` preset exports. If `--script` is refused, the fallback is a user argument read by an autoload (`-- --four-bot`), which is a game-side change for a later session.

## Audio needs

Sounds the game asks for by id and does not have yet. A missing sound is silent (`Registry.get_sound` returns `null`), never an error. The weekly run opens one `now` issue per line for Audio contributors. Files are `.ogg` in `audio/`, listed in `audio/manifest.json`; the id is the file name without the extension.

- **`cast`** (M1 part 10). The sound of a wizard releasing a spell: a short, soft whoosh, under 0.5 s. Heard every cast, from up to four players, so it must not tire the ear.
- **`hit`** (M1 part 16). A projectile or spell landing on an enemy: a short, dry impact, under 0.3 s. Heard many times a second in a fight.
- **`enemy_death`** (M1 part 16). An enemy dying: a small burst or fizz, under 0.6 s, clearly different from `hit`.
- **`player_downed`** (M1 part 16). A wizard going down: a low, soft thud or sigh, under 0.8 s, calm rather than alarming.

## Later milestones

- **Gate the daily build on the unit tests.** `ci/build/build.sh --tests` passes now, but the daily build does not run it, so regressions could return unnoticed. The workflow lives under `.github/`, so the owner makes the change; it is asked as an owner question in the PR #71 session.

- **A screenshot of `arena_01` with four wizards.** `ci/build/build.sh` runs Godot with `--headless`, which has no renderer, so no screenshot can be taken there. It needs a display (for example `xvfb-run` and the editor binary) in a script the owner adds under `ci/`; the HUD screenshot check in `docs/NEXT.md` waits for the same thing.

- **A downed mid-run joiner.** A joiner has 2 s of protection but, like everyone, cannot come back once downed until the revive rule below exists.
- **Revive by standing next to a downed wizard.** `Player.revive(reviver)` exists and `DECISIONS.md` gave the "how" to `coop`, but the co-op task (M1 part 17) listed only join/leave, friendly fire and the camera. Nothing calls `revive` yet; decide the rule (hold time, range, a short invulnerability window after a revive) when playtests show the need.

- **Egress firewall for Claude's shell sessions.** Allow only GitHub and the Anthropic API from the implement and revise runners (for example with iptables and GitHub's published IP ranges), so a misled session can't send its read-only or Claude token anywhere else. This needs care, because the action installs Claude Code at start-up.
- **Manifest validator (M1).** Outside PRs may add lines to `art/manifest.json` and `audio/manifest.json`, so a PR could also change other assets' records. A validator should allow only entries for files the PR adds.
- **llms.txt link check.** A small check (in `tools/` or `ci/`, so owner-added) that every relative link in `llms.txt` exists and every `README.md` in the repo is listed, so the index can't drift. Until then, a PR that adds or removes a doc updates `llms.txt` by hand.
- Cross-player spell linking (one player's frost plus another's storm), asynchronous, with no waiting (docs/PLAN.md, "Co-op rules").
- Windows code signing, before Steam (M7).
- GUT test framework as an owner-added addon, when game code needs unit tests (M1).
- **Feedback and Contribute buttons** (docs/PLAN.md): opening web pages is allowed only in `core/links/links.gd`, through its constant `URLS` table of the project's own addresses (docs/DECISIONS.md, "Opening web links, narrowly").

- **Invalid UIDs with a 9.** Godot's UID alphabet is a-y and 0-8. Fix the digit 9 in: `tests/gameplay/combat/test_combat.gd.uid`, `tests/gameplay/player/fixtures/counting_spell.gd.uid`, `tests/gameplay/player/test_player_move.gd.uid`, `tests/core/test_spell_base.gd.uid`, `tests/core/test_registry.gd.uid`.

## Ideas from the community

(none yet)

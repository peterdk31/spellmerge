# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). The weekly planning run triages Discussions ideas into this file and moves items into `docs/NEXT.md` when their milestone comes.

## Questions for the owner

Not kept here any more: each question is an issue labelled `owner-question` (docs/DECISIONS.md, "The owner inbox").

## Needs an owner decision

- **Web load time and WASM projectile timing (M1 part 22 follow-up).** Two changes in `ci/`: (1) in `ci/smbot/websmoke.py`, print `WEB LOAD: N s` (page start to the "main menu ready" line) and fail above 10 s; (2) in `ci/build/build.sh`, after the Web export, run `tests/benchmark/test_projectile_timing.gd` in the exported Web build under headless Chrome (the main menu would need a start argument like `--four-bot`, no `JavaScriptBridge`) and print the hostile `step` time at 1,000 shots. Claude then lowers `DEFAULT_CAP_WEB` if it is over 8 ms. Asked as an `owner-question`.

Also: the owner-only `build.sh` step for the 4-bot test (M1 part 21) is an `owner-question` issue, not a line here.

## Audio needs

Sounds the game asks for by id and does not have yet. A missing sound is silent (`Registry.get_sound` returns `null`), never an error. The weekly run opens one `now` issue per line for Audio contributors. Files are `.ogg` in `audio/`, listed in `audio/manifest.json`; the id is the file name without the extension.

- **`cast`** (M1 part 10). The sound of a wizard releasing a spell: a short, soft whoosh, under 0.5 s. Heard every cast, from up to four players, so it must not tire the ear.
- **`hit`** (M1 part 16). A projectile or spell landing on an enemy: a short, dry impact, under 0.3 s. Heard many times a second in a fight.
- **`enemy_death`** (M1 part 16). An enemy dying: a small burst or fizz, under 0.6 s, clearly different from `hit`.
- **`player_downed`** (M1 part 16). A wizard going down: a low, soft thud or sigh, under 0.8 s, calm rather than alarming.

## Later milestones

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

# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). The weekly planning run triages Discussions ideas into this file and moves items into `docs/NEXT.md` when their milestone comes.

## Needs an owner decision

- **Opening web links from the game.** The plan's feedback button ("What was fun?" opens a pre-filled GitHub Discussion) and the main menu's Contribute button need `OS.shell_open`, which is a banned API. One option: allow it in a single `core/` file that only opens a fixed list of `github.com/peterdk31/spellmerge` and itch.io URLs, checked by the rules script. Needed in M1 at the earliest.
- **Bot app Client ID.** `actions/create-github-app-token` now prefers `client-id` over the deprecated `app-id`. The Client ID is on the app's settings page; adding it to `ci/config.json` would make the `BOT_APP_ID` secret unnecessary.

- **Run the unit tests in CI.** `ci/build/build.sh` only runs `tests/smoke/boot_smoke.gd`. The tests in `tests/core/` (run by hand with `godot --headless --path . --script res://tests/core/<name>.gd`) need a step in `ci/build/build.sh` that runs every `tests/**/test_*.gd` and fails on a non-zero exit. `ci/` is owner-only.

## Later milestones

- **Egress firewall for Claude's shell sessions.** Allow only GitHub and the Anthropic API from the implement and revise runners (for example with iptables and GitHub's published IP ranges), so a misled session can't send its read-only or Claude token anywhere else. This needs care, because the action installs Claude Code at start-up.
- **Manifest validator (M1).** Outside PRs may add lines to `art/manifest.json` and `audio/manifest.json`, so a PR could also change other assets' records. A validator should allow only entries for files the PR adds.
- **llms.txt link check.** A small check (in `tools/` or `ci/`, so owner-added) that every relative link in `llms.txt` exists and every `README.md` in the repo is listed, so the index can't drift. Until then, a PR that adds or removes a doc updates `llms.txt` by hand.
- Cross-player spell linking (one player's frost plus another's storm), asynchronous, with no waiting (docs/PLAN.md, "Co-op rules").
- Windows code signing, before Steam (M7).
- GUT test framework as an owner-added addon, when game code needs unit tests (M1).

## Ideas from the community

(none yet)

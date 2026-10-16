# Backlog

Ideas and future work outside the current milestone (docs/PLAN.md, "Planning system"). The weekly planning run triages Discussions ideas into this file and moves items into `docs/NEXT.md` when their milestone comes.

## Needs an owner decision

- **Opening web links from the game.** The plan's feedback button ("What was fun?" opens a pre-filled GitHub Discussion) and the main menu's Contribute button need `OS.shell_open`, which is a banned API. One option: allow it in a single `core/` file that only opens a fixed list of `github.com/peterdk31/spellmerge` and itch.io URLs, checked by the rules script. Needed in M1 at the earliest.
- **Bot app Client ID.** `actions/create-github-app-token` now prefers `client-id` over the deprecated `app-id`. The Client ID is on the app's settings page; adding it to `ci/config.json` would make the `BOT_APP_ID` secret unnecessary.

## Later milestones

- Cross-player spell linking (one player's frost plus another's storm), asynchronous, with no waiting (docs/PLAN.md, "Co-op rules").
- Windows code signing, before Steam (M7).
- GUT test framework as an owner-added addon, when game code needs unit tests (M1).

## Ideas from the community

(none yet)

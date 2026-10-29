# Contributing to Spellmerge

Thanks for wanting to help! Spellmerge is built by Claude, an AI, and shaped by the people who play it. You can report bugs and share ideas, and you can send your own work: code, art or sound. Claude reads everything once a day and answers each post.

## Ways to help

| You want to | Where |
| --- | --- |
| Report a bug | The **[Report a bug](https://github.com/peterdk31/spellmerge/issues/new/choose)** form |
| Suggest a spell, an enemy, a relic, anything | The **Spell idea** form, or [Discussions → Ideas](https://github.com/peterdk31/spellmerge/discussions/categories/ideas) |
| Share art or sound you made | [Discussions → Art submissions](https://github.com/peterdk31/spellmerge/discussions/categories/art-submissions): attach the PNG or OGG and say what it's for |
| Send code or content | A pull request against `main` (see below) |
| Show off a combo, give feedback | [Discussions](https://github.com/peterdk31/spellmerge/discussions) |
| Raise a copyright concern | The **Report a copyright concern** form |

The more exact a bug report, the faster it gets fixed: the build version (on the main menu), how many players, and the steps.

## What happens next

Once a day (03:00 UTC), Claude reads every new issue, discussion and pull request and answers each one:

- **Scheduled:** it goes into Claude's work queue, by priority (crashes and blockers first). An issue is closed by the pull request that fixes it, so you are notified.
- **Backlog:** good, but for later. The weekly planning schedules it when it fits a milestone.
- **Needs info:** Claude asks for what's missing. Reply in the same place, and it reads it again the next day.
- **Answered, duplicate or declined:** with a reason, in plain words.

You can see the work queue ([`scheduled`](https://github.com/peterdk31/spellmerge/issues?q=is%3Aopen+label%3Ascheduled)) and the [`backlog`](https://github.com/peterdk31/spellmerge/issues?q=is%3Aopen+label%3Abacklog) at any time. Every bot action is listed in the day's [Daily log](https://github.com/peterdk31/spellmerge/issues?q=label%3Adaily-log).

## Sending your own work

**Sign the CLA once.** Before your work can be used, post this exact comment on your pull request or discussion:

> I have read the CLA and I agree to it.

In short ([CLA.md](CLA.md)): you keep the copyright, the project may use and relicense your work (for example for Steam), and you confirm it's yours to give.

**Pull requests.** When Claude schedules your PR, it doesn't rewrite it: a development session builds on your commits (your name stays on them), reviews and finishes the work, and sends it through the same reviews as its own changes. When that merges, your PR is closed with credit. Before it can be scheduled, the `rules` check must pass:

1. Don't change `.github/`, `ci/`, `tools/`, `setup.sh`, `docs/DESIGN.md` or the license files.
2. Allowed files: `.png` and `.svg` images (up to 1 MB), `.ogg` audio (up to 5 MB), Godot text files (`.tscn`, `.tres`, `.gdshader`, `.gdshaderinc`, `.import`, `.uid`) and typed GDScript. No binaries.
3. No code that starts programs, uses the network, calls JavaScript or loads code at runtime.
4. Only your own work, or work under a compatible license, and no names or art from other games or films.

Run `tools/check.sh` to check these yourself, and `ci/build/build.sh --quick --tests` to run the game's tests. Using a coding agent? Point it at [AGENTS.md](AGENTS.md).

**Art and sound in Discussions.** Attach the PNG or OGG to your post in Art submissions and say what it's for. If Claude takes it, the file is checked and re-encoded, and a development session puts it in the game (or asks you for changes), with you credited in the asset manifest. [docs/STYLE.md](docs/STYLE.md) has the art rules: 32×32 grid, the palette, light from the top-left.

AI-made work is welcome if you say so, with the tool and the prompt; prompts may not name living artists or existing franchises.

## Credit

Contributors, and players whose bug reports or ideas made it into the game, are on the in-game credits screen, and the most helpful may name a spell. The web version stays free forever; the Steam version funds development.

## Code of conduct

Be kind and constructive. Critique work, not people. Claude and the owner may close or lock anything that isn't.

## Security

Report security problems privately through [Security advisories](https://github.com/peterdk31/spellmerge/security/advisories/new), not in a public issue.

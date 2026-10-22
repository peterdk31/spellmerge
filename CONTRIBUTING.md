# Contributing to Spellmerge

Thanks for wanting to help! Spellmerge is built by Claude, an AI, together with anyone who wants to join: coders, pixel artists, musicians, sound designers and writers. Contributing should be easy. The few hard rules exist only for security and copyright; everything else is guidance, and Claude polishes good-but-imperfect contributions itself.

Using a coding agent? Point it at [AGENTS.md](AGENTS.md): same rules, written for agents.

## Ways to help

| You are | You can | How |
| --- | --- | --- |
| A coder | Spells, enemies, relics, gameplay systems, UI | A pull request (see below) |
| A pixel artist | Sprites, tiles, icons, effects | A pull request, or the **Submit art** form (no git needed) |
| A musician or sound designer | Music, sound effects | A pull request, or the **Submit sound** form (no git needed) |
| A writer | Lore, dialogue, item descriptions | A pull request, or the **Submit writing** form (no git needed) |
| A player | Bug reports, ideas, feedback | The **Report a bug** form, [Discussions](https://github.com/peterdk31/spellmerge/discussions), the feedback button after a run |

Areas open over time, milestone by milestone (see [docs/ROADMAP.md](docs/ROADMAP.md)). Art and Audio are open. M2 (the spell system) has started: Spells opens once the component classes and their example exist, and Story once `docs/STORY.md` and the first descriptions exist.

## Finding something to do

- Issues labelled **`now`** are wanted now. The [project board](https://github.com/users/peterdk31/projects) has a view for each skill.
- Each task says exactly what's needed, where the file goes, the specs, an example to copy, and when it counts as done.
- Comment `/claim` on the issue to make it yours. A claim lasts 2 days; open a pull request (a draft is fine) that mentions the issue to keep it.

## The rules (checked automatically)

1. Only change the area you're contributing to. Infrastructure, `core/`, and Claude's plan and docs files are protected.
2. Allowed files: `.png` and `.svg` images (up to 1 MB), `.ogg` audio (up to 5 MB), and Godot text files and GDScript. No binaries.
3. No code that starts programs, uses the network, calls JavaScript or loads code at runtime. The game must be safe for everyone who plays it.
4. Only your own work, or work under a compatible license. Code: GPL-3.0-or-later (the default), MIT, BSD, Apache-2.0. Assets: CC-BY-SA-4.0 (the default), CC-BY-4.0, CC0. No ripped game assets, no fan art of other games or films, no names from other works.
5. Sign the [CLA](CLA.md) once: comment `I have read the CLA and I agree to it.` on your first pull request (or tick the box in a submission form). You keep the copyright; the project may use and relicense your work, for example for Steam.

Run `tools/check.sh` before opening a pull request to check rules 1–4 yourself. Every problem it finds says what to fix. Then run `ci/build/build.sh --quick --tests`: it downloads the pinned Godot once, imports the project, and runs the smoke test and every unit test, including the spell validator.

## Using AI tools

AI-made code, art and sound are welcome, provided you say so. Mark the asset origin as `ai` in the pull request (or the form), with the tool and the prompt. The tool's terms must allow commercial use, and prompts may not name living artists or existing franchises. Steam requires the project to disclose AI content, so this matters.

## How your contribution is reviewed

1. **Hard rules first** (instant and free). If something breaks a rule, the pull request is closed with an exact list of what to fix; fix it and reopen.
2. **Claude rates it** in the next daily run (03:00 UTC), from 1 to 5 on fit, fun, quality, value, performance, risk and scope. An average of 3.5 or more, with nothing below 2, means merge. The review is open and helpful: a good idea with rough edges is a merge, and Claude fixes small things (naming, a missing test, a wrong folder) itself in a follow-up that credits you.
3. **The community votes** on art, audio and gameplay: 👍 or 👎 on the pull request, for 24 hours. The number of 👍 needed grows with the community (2 votes at first, never more than 25).
4. **A script merges it**, after a test build with the other contributions of the day. Your work is in the next day's build.

If changes are requested, you get at most 3 concrete points. Push your fixes to the same branch, and it's rated again.

## Credit

Every merged contributor is on the in-game credits screen, gets a free Steam key when the game is on Steam, and top contributors may name a spell. The web version stays free forever; the Steam version funds development.

## Code of conduct

Be kind and constructive. Critique work, not people. Claude and the owner may close or lock anything that isn't.

## Questions

Ask in [Discussions](https://github.com/peterdk31/spellmerge/discussions) or in the issue you're working on. Report security problems privately through [Security advisories](https://github.com/peterdk31/spellmerge/security/advisories/new), and copyright concerns with the **Report a copyright concern** form.

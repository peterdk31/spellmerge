# Spellmerge

*Merge spells. Cause chaos. Together.* · *Every spell is a merge request.*

A 2D top-down roguelite about building deep, combinable spells, for 1–4 local co-op players. Assemble spells from a form, an element, modifiers and triggers (a trigger holds another spell), find relics that bend the rules, and fight through rooms with up to three friends on one screen, with nobody ever waiting for anybody.

**Play:** [in the browser](https://peterdk31.github.io/spellmerge/play/) · [today's nightly](https://peterdk31.github.io/spellmerge/nightly/) · [latest preview](https://peterdk31.github.io/spellmerge/preview/) (rebuilt after each merge) · [Windows and Linux downloads](https://github.com/peterdk31/spellmerge/releases)

**Status:** milestone M2, the spell system. The infrastructure (M0) and the core loop prototype (M1) are in place; spell components, the spell builder and the spell limits are being built. See the [roadmap](docs/ROADMAP.md).

## Built by an AI, in the open

Claude, an AI by Anthropic, writes the code and the assets and ships a new build every day, all on GitHub's servers. The owner (@peterdk31) sets the vision in [docs/DESIGN.md](docs/DESIGN.md) and controls the protected infrastructure. Every AI change is made by the **spellmerge-bot** account, so it's always visible as such, and every bot action is listed in that day's **Daily log** issue (label [`daily-log`](../../issues?q=label%3Adaily-log)).

Players shape the game: [report a bug](../../issues/new/choose) or share an idea in [Discussions](../../discussions). Claude reads and answers every post within a day, schedules bugs and good ideas, and the PR that does one closes its issue. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Free on the web forever

The web version and the daily desktop builds stay free; the Steam version (later) funds development. No ads, no microtransactions.

## License

Code: [GPL-3.0-or-later](LICENSE). Assets: CC-BY-SA-4.0, unless a file says otherwise (see [REUSE.toml](REUSE.toml)). A copyright concern? Use the **Report a copyright concern** issue form; taking the asset out is scheduled first while it's checked. GitHub's DMCA process also applies.

## For maintainers

- [docs/PLAN.md](docs/PLAN.md): the full plan
- [docs/NEXT.md](docs/NEXT.md): what Claude works on next
- [docs/DECISIONS.md](docs/DECISIONS.md): why things are the way they are
- `tools/check.sh`: the hard rules on your local changes; `ci/build/build.sh`: a full local build

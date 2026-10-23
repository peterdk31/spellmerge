# Next

The ordered task queue for the current milestone, M0. The first unchecked task under "Queue" is next. Bug reports go above features. Each task is one session and one PR; a session that runs short stops at a task boundary and writes what is left as a new task here. Claude keeps this file up to date; only tasks in paths Claude may change belong here (docs/PLAN.md, "Path tiers").

## Queue

{{GAME}} was started on {{DATE}} from the owner's idea in `docs/DESIGN.md`.

- [ ] **Draft the design (M0 part 1).** (`docs/DESIGN.md`) `docs/DESIGN.md` holds only the owner's idea. Write the vision and the pillars (3 to 5, each a rule that decides between two designs), who it is for, the core loop, what makes it different, the scope of a first release and what is out of scope, all grown from the idea; where the idea is silent, choose and say why in the PR. Copy nothing from other works and name no other games. Keep "Art direction (locked)" as "Not chosen yet".
- [ ] **Plan the game (M0 part 2).** (`docs/PLAN.md`, `docs/ROADMAP.md`, `docs/milestones/`, `AGENTS.md`, `README.md`) From the accepted `docs/DESIGN.md`: fill the game sections of `docs/PLAN.md` ("Overview", "Game design", "Codebase architecture and areas", "Performance", "Roadmap") and rewrite what the other sections say about another game; write the milestones in `docs/ROADMAP.md` and `docs/milestones/M0-foundation.md`; rewrite `AGENTS.md` and `README.md` for this game; and fill this queue with M0's next tasks (the folder layout and area READMEs, the test runner, a first playable screen). Tests that must run in the exported builds (a bot playtest, a stress run) go in `tests/build.json`, started by the first screen on their argument.

## Blocked

## Done recently

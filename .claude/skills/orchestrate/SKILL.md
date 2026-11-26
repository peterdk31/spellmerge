---
name: orchestrate
description: Run Spellmerge as the orchestrator. Start each task in its own child cloud session, merge the PRs one at a time, ask the owner's questions, and show the owner the screenshots. Use when the owner says "orchestrate", "be the orchestrator", or asks to run several tasks through sessions.
---

# Spellmerge orchestrator

You don't write the game yourself. You hand each task to a child session, merge what comes back, and keep the owner informed. The owner talks only to you.

## Start
1. Make a log in your scratchpad, `orchestration.md`. Write every merge (PR number and full sha), every owner answer (with the date) and every session id in it. After a context summary, read the log again before you act.
2. `git fetch origin main` and look at what is open: the open PRs, and your own child sessions (`list_sessions` with `children: true`). Pick up where the last orchestrator left off. Its log is gone, so ask the owner if it isn't clear.

## A task becomes a session
- **One task, one PR, one fresh session.** Never give a second PR to a session that has finished one. Its context only grows, and every step re-reads all of it. A session that ran all day over five PRs cost about $74; a session with one PR costs $8–17.
- Start it with `create_session` (`source_url` = the repo). Its prompt is a short brief plus [footer.md](footer.md), copied verbatim.
- The brief says the goal and the owner's words, with the date. It names the files and functions to start from, says what is ruled out, and sets the limits, such as no `ci/` or `.github/` edits. The fewer files a session has to search for, the cheaper it is.
- Use `model: "sonnet"` for mechanical work: renames, moves, doc trims, merging main. Use the default model for design work, engine work and anything in `core/` or `native/`.
- Run sessions in parallel only when they don't touch the same files. Two that both edit `core/README.md` or `projectile_manager.gd` go one after the other.

## When a session reports
Its message arrives as a notification: call ReadNotifications.
1. Fetch its screenshots from `shots/<branch>` into the scratchpad with `git show`, and send them with SendUserFile and a one-line caption.
2. Its open questions:
   - A question about the game (design, look, feel) goes to the owner with **AskUserQuestion**, never as plain text (CLAUDE.md). Each question must stand on its own; put the recommended option first.
   - A purely technical question you decide yourself. Log it, and tell the owner in one line.
3. Pass the answers back with `send_message`.

## Merging (only you merge)
A PR merges when all of these hold:
- its checks are green on the head sha: `rules`, `ci-tests` and `godot-tests` (the whole unit suite);
- the branch contains the current `origin/main`;
- one fresh-context review was done;
- the owner's open questions are answered, or are only refinements.

Then:
- `merge_pull_request` with method `merge` and `expectedHeadSha` set to the full 40-character sha.
- Merge one PR at a time, and log the merge.
- Tell every other running session the new main sha, and that it should merge origin/main before its PR. godot-tests reruns on its next push, so no local full run is needed.
- Archive a session (`archive_session`) as soon as its PR is merged.

## Owner-only paths
`.github/`, `ci/`, `.claude/`, `addons/`, `LICENSE`, `CLA.md` and the rest of AGENTS.md hard rule 1.
- A child session refuses an owner-only or security-rule edit when the approval reaches it only through your message. That's correct.
- When the owner approves such an edit directly to you, make it yourself on your own branch and open a small PR (examples: #925, #953, #959).
- Never loosen a hard rule without the owner's explicit words.

## Waiting
- Don't busy-wait. It slows the machine.
- Wait in the background with `python3 -c "import time;time.sleep(N)"` (`run_in_background`), or end your turn; a notification wakes you.
- Before a long wait, tell the owner in one line what you are waiting for.

## Watching the owner's builds
- **The web preview** (`preview.yml`) builds and deploys in about 4 minutes after each merge. Its screenshots run beside it, and a second deploy adds the gallery about 15 minutes later.
- **"I can't find X in the preview":** check that the preview run for a merge with X finished, with `list_workflow_runs` for `preview.yml`. Check its jobs before blaming the game.
- **Cheat code:** `allcards` in the hub gives every card in the registry.

## Keep it cheap
- No full `tools/ptest.sh` in sessions; CI runs the suite.
- One review subagent per PR, on Sonnet, given the diff and only the files the diff touches.
- Screenshots only for work the owner can see.
- Area READMEs are short contracts, with history in `docs/history/`. Keep briefs pointing at the contract, not the history.

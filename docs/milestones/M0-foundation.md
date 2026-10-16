# M0: Foundation

**Goal:** the complete infrastructure that lets an AI-run community project work, before any gameplay (docs/PLAN.md, "Infrastructure first"). The game stays an empty shell: a main menu with the build version.

**Done when:** 3 daily releases in a row work, and every pipeline part passes its dry run.

**Status:** closed early by the owner on 2026-10-16 (docs/DECISIONS.md, "M1 starts before M0's dry runs"). All seven parts are built. The dry runs below and the 3-release streak carry into M1 and are part of M1's done-when.

## Who builds what

Most of M0 lives in owner-only paths (`.github/`, `ci/`), which the bot can't change, because its app has no Workflows permission and CODEOWNERS requires the owner's review. So M0's infrastructure is built in interactive sessions with the owner and merged by the owner. The bot takes over the parts in bot-maintained paths (area READMEs, `llms.txt`, plan files) through its normal development loop, which is how that loop gets its first real test.

## Parts, in order

| # | Part | Status |
| --- | --- | --- |
| 1 | **Security:** rules check, protected paths, custom app, protected environment, REUSE licence check | Built (#2) |
| 2 | **Build and release:** CI, daily release (web demo and desktop), smoke tests, nightly/stable channels | Built (#3) |
| 3 | **Autonomy:** plan files, hourly development sessions, Daily log, stall and token alarms | Built (#6, #7) |
| 4 | **Owner control:** Control panel and owner commands | Built (#6) |
| 5 | **Contribution pipeline:** PR rating and merging, CLA, PR and issue templates, no-git submission forms, claims, labels, project board | Built (#8) |
| 6 | **Community:** scaling community voting (dormant until there are voters), Discussions categories, copyright report form and quarantine, bug report form | Built (#8, #10); Discussions categories are created by hand |
| 7 | **Onboarding:** AGENTS.md, CLAUDE.md, llms.txt, CONTRIBUTING.md, area READMEs, local check script, Contribute page | In progress: area READMEs and llms.txt are Claude's first tasks in docs/NEXT.md |

## Dry runs

Every part is verified end to end before M0 counts as done. Results go to `docs/LOG.md`.

- [ ] A fake PR that edits an owner-only path is auto-closed with a reason.
- [ ] A fake PR that uses a banned API is auto-closed.
- [ ] A fake PR that adds a binary or a disallowed file type is auto-closed.
- [ ] A PR whose head changes after rating is not merged.
- [ ] Prompt-injection text in a PR gets the normal rating and no extra action.
- [ ] A fake vote counts correctly and shows the state in the PR comment.
- [ ] A fake copyright report quarantines the asset.
- [ ] A fake bug report is labelled and lands in `docs/NEXT.md` above features.
- [ ] An unsigned PR gets the CLA comment, is recorded after signing, and is closed after 7 days if never signed.
- [ ] An owner command from another account is ignored; each owner command works.
- [ ] A Control panel edit by another account is ignored and reported.
- [ ] The kill switch stops a run before it does anything.
- [ ] An invalid Claude token opens the token alarm, and the scripted build and release still ship.
- [ ] A broken build is not released, and the culprit merge is reverted.
- [ ] 3 daily releases in a row.

## Out of scope

Anything that needs a working game: the Style Guide page and starter kit (M1), the stress benchmark and art direction call (M2), bot playtesting (M3), the Steam page (M6).

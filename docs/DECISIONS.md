# Decisions

Why things were decided, so they aren't reversed by accident. Newest first.

## 2026-10-16: Own CLA check instead of CLA Assistant; no lawyer review

**Decided by:** owner.
**Context:** cla-assistant.io keeps an OAuth token for the owner's account with `repo:status`, `write:repo_hook` and `gist` scopes on all repos. The owner account is what the whole security model protects.
**Decision:**
- `CLA.md` is adapted from the Apache Individual CLA v2.2, because a standard, widely used text is the safest choice without a lawyer.
- Contributors sign by commenting `I have read the CLA and I agree to it.` on their PR. For no-git submissions, the issue-form checkbox counts.
- The daily run records signatures in the bot-maintained `docs/cla-signatures.json` by numeric user ID and CLA version.
- Unsigned PRs get a how-to-sign comment and are closed only if still unsigned after 7 days, because a signature is only seen at the next daily run. They are never merged unsigned.
- The plan's "short lawyer review before selling" item is dropped entirely.

## 2026-10-16: PRs merge into `main`; `staging` is only a test branch

**Decided by:** owner.
**Context:** The plan had approved PRs merged into `staging`, with `main` fast-forwarded at release. A `main` ruleset that requires PRs and code-owner review would only allow that if the bot were a bypass actor, and then the bot could also push owner-only paths past CODEOWNERS.
**Decision:** The bot is never a bypass actor. The merge script merges candidates together on a throwaway `staging` branch and runs the content validators there, then merges each passing PR into `main` with `gh pr merge --match-head-commit <reviewed SHA>`. A broken daily build is fixed with revert PRs that the bot opens and merges itself. The release tags `main`.
**Consequence:** Every protection that GitHub enforces stays in place for the bot. `main` can briefly hold a merge that the daily smoke test later reverts, but releases are cut only from a tested `main`.

## 2026-10-16: Code license is GPL-3.0-or-later

**Decided by:** owner. Assets stay CC-BY-SA-4.0. Recorded in `REUSE.toml` and `LICENSE`.

## 2026-10-16: Setup, security docs and REUSE.toml are owner-only

**Decided by:** owner. `setup.sh`, `REUSE.toml`, `docs/SECURITY-CHECKLIST.md` and `docs/SETUP-APP.md` join the owner-only tier, so the bot can't weaken the security setup or its checklist, or change the license that every file falls under. Repository settings data lives in `ci/settings/`, which is owner-only already.

## 2026-10-16: The project board is user-owned and follows labels

**Decided by:** owner.
**Context:** GitHub Apps can't access projects owned by a personal account; that needs a classic personal access token, which the plan rules out.
**Decision:** The board stays under `peterdk31`. GitHub's built-in auto-add workflow fills it, and views filter by label. The bot keeps issue labels correct and never edits the board itself.

## 2026-10-16: Names chosen during setup

**Decided by:** Claude (details the plan left open).

- The protected environment is called `automation`. Its secrets are `BOT_APP_ID`, `BOT_APP_PRIVATE_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and `BUTLER_API_KEY` (the name itch.io's `butler` tool reads).
- The repository variables are `AUTOMATION_ENABLED` (the kill switch), `OWNER_ID` (the owner's numeric user ID) and `BOT_LOGIN`.
- The required PR status check is the `checks.yml` job named `rules`, pinned to the GitHub Actions app.
- Only GitHub-owned actions plus `anthropics/claude-code-action` are allowed, all pinned by SHA (`ci/settings/allowed-actions.json`).

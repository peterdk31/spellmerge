# Setting up the Spellmerge Bot GitHub App

This is setup step 5 in `docs/PLAN.md` and takes about 5 minutes. Run `./setup.sh` first, because the secrets below go into the `automation` environment that it creates.

## Why a custom app

Claude never uses your personal account or a personal access token. Every commit, PR, comment and merge the bot makes goes through this app, so:

- Bot actions always show as **spellmerge-bot[bot]**, never as you.
- The app can only reach this one repository.
- The app has exactly three permissions. It has **no Workflows permission**, so GitHub itself refuses any bot commit that touches `.github/workflows/`, whatever the bot is told.
- Commits made with the app's token trigger other workflows. Commits made with the default workflow token don't.
- You can cut the bot off at once by suspending or uninstalling the app (see [Emergency stop](#emergency-stop)).

## 1. Create the app

1. Open **https://github.com/settings/apps/new**. You must be signed in as `peterdk31`.
2. Fill in the form:

   | Field | Value |
   | --- | --- |
   | GitHub App name | `Spellmerge Bot`. Names are unique across GitHub, so if it's taken use something like `Spellmerge Bot peterdk31` and note the name. |
   | Description | `Claude's maintainer bot for peterdk31/spellmerge.` |
   | Homepage URL | `https://github.com/peterdk31/spellmerge` |
   | Callback URL | Leave empty |
   | Expire user authorization tokens | Leave the default |
   | Request user authorization (OAuth) during installation | **Off** |
   | Enable Device Flow | **Off** |
   | Setup URL | Leave empty |
   | Webhook → Active | **Off** (untick it; the bot polls on a schedule and needs no webhook) |

3. Under **Permissions → Repository permissions**, set exactly these and leave everything else at **No access**:

   | Permission | Access |
   | --- | --- |
   | Contents | **Read and write** |
   | Issues | **Read and write** |
   | Pull requests | **Read and write** |
   | Metadata | Read-only (GitHub makes this mandatory and sets it automatically) |

   Check that these in particular stay at **No access**: Workflows, Administration, Actions, Secrets, Variables, Environments, Pages, Projects, Commit statuses, Checks, Deployments.

4. **Organization permissions** and **Account permissions**: leave all at **No access**.
5. **Subscribe to events**: leave all unticked.
6. **Where can this GitHub App be installed?** Choose **Only on this account**.
7. Click **Create GitHub App**.

## 2. Note the app ID and create a private key

1. On the app's settings page (you land there after creating it), copy the **App ID** (a number).
2. Scroll down to **Private keys** and click **Generate a private key**. Your browser downloads a `.pem` file.

The `.pem` file is the bot's password. Don't commit it, paste it into an issue or chat, or keep it in the repo folder. (`.gitignore` blocks `*.pem` as a safety net.)

## 3. Install the app on the repository

1. In the app's settings, open **Install App** in the left sidebar and click **Install** next to `peterdk31`.
2. Choose **Only select repositories** and pick **spellmerge**. Never pick "All repositories".
3. Click **Install**.

## 4. Store the secrets in the protected environment

Run these from the repo folder. Replace `123456` with the App ID and the path with your downloaded `.pem` file:

```sh
gh secret set BOT_APP_ID          --env automation --repo peterdk31/spellmerge --body 123456
gh secret set BOT_APP_PRIVATE_KEY --env automation --repo peterdk31/spellmerge < ~/Downloads/spellmerge-bot.*.private-key.pem
```

Always use `--env automation`. A secret stored at repository level (without `--env`) could be read by any workflow on any branch. `./setup.sh --check` fails if any repository-level secret exists.

Then delete the local key file:

```sh
shred -u ~/Downloads/spellmerge-bot.*.private-key.pem
```

You don't need a backup: if the key is ever needed again, generate a new one (see [Rotating the key](#rotating-the-key)).

## 5. Record the bot's login

The rules script uses the bot's login to recognise the bot's own PRs, which are the only PRs allowed to change bot-maintained paths. If you used a different app name, replace `spellmerge-bot` with your app's slug, which is the last part of the app's public URL, `https://github.com/apps/<slug>`.

```sh
gh variable set BOT_LOGIN --repo peterdk31/spellmerge --body 'spellmerge-bot[bot]'
```

## 6. The other secrets in the same environment

Setup steps 6 and 7 store their secrets the same way, in the same environment:

```sh
claude setup-token        # prints a long-lived token for your Claude Pro subscription
gh secret set CLAUDE_CODE_OAUTH_TOKEN --env automation --repo peterdk31/spellmerge
# paste the token when prompted, so it never lands in your shell history

gh secret set BUTLER_API_KEY --env automation --repo peterdk31/spellmerge
# paste the itch.io API key from https://itch.io/user/settings/api-keys
```

## 7. Verify

```sh
./setup.sh --check
```

All four secrets and `BOT_LOGIN` should show a green tick. Then work through `docs/SECURITY-CHECKLIST.md`.

## How the workflows use the app

This is for reference, for whoever writes the workflows. Jobs that need the bot mint a short-lived installation token (valid for 1 hour) with the GitHub-owned `actions/create-github-app-token` action, pinned by SHA:

```yaml
jobs:
  develop:
    if: github.ref == 'refs/heads/main'
    environment: automation          # the only place the secrets exist
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - id: app-token
        uses: actions/create-github-app-token@<full commit SHA> # vX.Y.Z
        with:
          app-id: ${{ secrets.BOT_APP_ID }}
          private-key: ${{ secrets.BOT_APP_PRIVATE_KEY }}
          # Request only what this job needs, never more than the app has.
          permission-contents: write
          permission-pull-requests: write
```

Rules for every workflow (also in the checklist):

- Only `schedule` and `workflow_dispatch` jobs on `main` may use `environment: automation`. Never `pull_request_target`, `issue_comment`, `workflow_run` or any other event triggered by outside users. Those run in the context of `main` too, so the environment's branch policy alone would not stop them.
- Each job asks for the smallest set of `permission-*` inputs it needs.
- The Claude steps that read outside text (the intake's decide step) and the PR reviewers use a read-only token (`permission-contents: read`, and for the reviewers also `permission-pull-requests: read` and `permission-issues: read`); a separate scripted step applies their decisions or posts the verdict.

## Rotating the key

Rotate if a key may have leaked, or once a year as a habit:

1. On the app's settings page, **Generate a private key** (the old one keeps working for now).
2. `gh secret set BOT_APP_PRIVATE_KEY --env automation --repo peterdk31/spellmerge < new-key.pem`, then `shred -u new-key.pem`.
3. Back on the app page, **Delete** the old key.

## Emergency stop

From fastest to most drastic:

1. Untick **Automation enabled** in the Control panel issue, or set the repo variable `AUTOMATION_ENABLED=false`.
2. Disable the workflows in the repo's **Actions** tab.
3. **Suspend** the app installation: **https://github.com/settings/installations** → Spellmerge Bot → Configure → **Suspend**. Its tokens stop working at once. Unsuspend to resume.
4. Delete all private keys on the app page, or uninstall the app.

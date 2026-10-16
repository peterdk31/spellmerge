#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Creates peterdk31/spellmerge and applies every repository setting as code
# (docs/PLAN.md, "Setup steps", step 4). Safe to re-run: each step converges
# the live setting to the value defined here or in ci/settings/.
#
#   ./setup.sh           create the repo if needed, then apply all settings
#   ./setup.sh --check   verify the live settings only; changes nothing
#
# Afterwards: docs/SETUP-APP.md (the bot app and secrets), then
# docs/SECURITY-CHECKLIST.md.

set -euo pipefail

OWNER="peterdk31"
REPO_NAME="spellmerge"
REPO="$OWNER/$REPO_NAME"
ENV_NAME="automation"          # protected environment that holds every secret
RELEASE_BRANCH="main"          # the only branch allowed to use $ENV_NAME
PROJECT_TITLE="Spellmerge"
SETTINGS="ci/settings"
DESCRIPTION="Merge spells. Cause chaos. Together. A 1-4 player co-op roguelite built by Claude and the community."
HOMEPAGE="https://$OWNER.github.io/$REPO_NAME/"
ENV_SECRETS=(BOT_APP_ID BOT_APP_PRIVATE_KEY CLAUDE_CODE_OAUTH_TOKEN BUTLER_API_KEY)

cd "$(dirname "$0")"

WARNINGS=()
FAILURES=()

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; WARNINGS+=("$*"); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAILURES+=("$*"); }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

api() { gh api -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }

# Read a value for --check; never aborts the script. Prints JSON null when the
# setting can't be read, so the jq filters below still run.
get() { api "$@" 2>/dev/null || echo null; }

# run <description> <command...>: abort the script if the command fails.
run() {
  local what=$1; shift
  "$@" >/dev/null
  ok "$what"
}

# try <description> <command...>: warn instead of aborting. Used for newer
# endpoints that may not exist on every account yet.
try() {
  local what=$1 err; shift
  if err=$("$@" 2>&1 >/dev/null); then ok "$what"; else warn "$what: ${err##*$'\n'}"; fi
}

# expect <description> <actual> <wanted>
expect() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (is '$2', want '$3')"; fi
}

# ---------------------------------------------------------------------------

preflight() {
  bold "Preflight"
  local cmd login twofa scopes
  for cmd in gh git jq; do
    command -v "$cmd" >/dev/null || die "'$cmd' is not installed"
  done
  gh auth status --hostname github.com >/dev/null 2>&1 || die "gh is not logged in: run 'gh auth login'"

  login=$(api user --jq .login)
  [[ "$login" == "$OWNER" ]] || die "gh is logged in as '$login', expected '$OWNER'"
  ok "gh is logged in as $OWNER"

  twofa=$(api user --jq '.two_factor_authentication | if . == null then "unknown" else tostring end')
  case "$twofa" in
    true)  ok "2FA is on" ;;
    false) die "2FA is off for $OWNER: turn on 2FA or a passkey first (setup step 1)" ;;
    *)     warn "could not read 2FA status: confirm it at https://github.com/settings/security" ;;
  esac

  scopes=$(api -i user | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes" {print $2}')
  if [[ -n "$scopes" ]]; then
    [[ ",${scopes// /}," == *",repo,"* ]] \
      || die "gh token lacks the 'repo' scope: run 'gh auth refresh -h github.com -s repo'"
    [[ ",${scopes// /}," == *",project,"* ]] \
      || die "gh token lacks the 'project' scope: run 'gh auth refresh -h github.com -s project'"
    ok "gh token scopes: $scopes"
  else
    warn "could not read gh token scopes; continuing"
  fi

  for f in "$SETTINGS/labels.json" "$SETTINGS/allowed-actions.json" "$SETTINGS"/rulesets/*.json; do
    jq empty "$f" || die "$f is not valid JSON"
  done
}

ensure_repo() {
  bold "Repository"
  if api "repos/$REPO" >/dev/null 2>&1; then
    ok "$REPO exists"
    return
  fi
  [[ "$MODE" == check ]] && die "$REPO does not exist yet: run ./setup.sh first"

  if [[ ! -d .git ]]; then
    run "initialised local git repo" git init --initial-branch=main
  fi
  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    git add -A
    run "created initial commit" git commit -m "Initial commit: M0 repo structure and setup"
  fi
  run "created public repo $REPO and pushed main" \
    gh repo create "$REPO" --public --description "$DESCRIPTION" --source . --remote origin --push
}

apply_repo_settings() {
  bold "Repository settings"
  run "description, homepage, issues, projects, Discussions" \
    api -X PATCH "repos/$REPO" -f description="$DESCRIPTION" -f homepage="$HOMEPAGE" \
      -F has_issues=true -F has_projects=true -F has_discussions=true
  try "secret scanning and push protection" \
    api -X PATCH "repos/$REPO" --input - <<<'{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'
  try "Dependabot alerts" api -X PUT "repos/$REPO/vulnerability-alerts"
  try "Dependabot security updates" api -X PUT "repos/$REPO/automated-security-fixes"
  try "private vulnerability reporting" api -X PUT "repos/$REPO/private-vulnerability-reporting"
}

apply_actions() {
  bold "GitHub Actions"
  run "only selected actions, pinned by full commit SHA" \
    api -X PUT "repos/$REPO/actions/permissions" --input - \
      <<<'{"enabled":true,"allowed_actions":"selected","sha_pinning_required":true}'
  jq '{github_owned_allowed: true, verified_allowed: false, patterns_allowed: .}' \
    "$SETTINGS/allowed-actions.json" \
    | run "allowed actions: GitHub-owned + ci/settings/allowed-actions.json" \
        api -X PUT "repos/$REPO/actions/permissions/selected-actions" --input -
  run "default workflow token is read-only and cannot approve PRs" \
    api -X PUT "repos/$REPO/actions/permissions/workflow" --input - \
      <<<'{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
  try "fork PRs from accounts new to GitHub need approval to run" \
    api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --input - \
      <<<'{"approval_policy":"first_time_contributors_new_to_github"}'
}

apply_environment() {
  bold "Protected environment '$ENV_NAME'"
  run "environment exists with custom branch policy" \
    api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - \
      <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'

  local policies id
  policies=$(api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies")
  if ! jq -e --arg b "$RELEASE_BRANCH" \
      'any(.branch_policies[]; .name == $b and .type == "branch")' <<<"$policies" >/dev/null; then
    run "allowed branch: $RELEASE_BRANCH" \
      api -X POST "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
        -f name="$RELEASE_BRANCH" -f type=branch
  else
    ok "allowed branch: $RELEASE_BRANCH"
  fi
  # Nothing but the release branch may deploy to the environment.
  for id in $(jq -r --arg b "$RELEASE_BRANCH" \
      '.branch_policies[] | select(.name != $b or .type != "branch") | .id' <<<"$policies"); do
    run "removed extra branch policy $id" \
      api -X DELETE "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies/$id"
  done
}

apply_variables() {
  bold "Repository variables"
  local owner_id
  owner_id=$(api "users/$OWNER" --jq .id)
  run "OWNER_ID=$owner_id (numeric ID that Control panel and owner commands trust)" \
    gh variable set OWNER_ID --repo "$REPO" --body "$owner_id"
  # Never overwrite the kill switch: re-running setup must not re-enable a stopped bot.
  if api "repos/$REPO/actions/variables/AUTOMATION_ENABLED" >/dev/null 2>&1; then
    ok "AUTOMATION_ENABLED left as is ($(api "repos/$REPO/actions/variables/AUTOMATION_ENABLED" --jq .value))"
  else
    run "AUTOMATION_ENABLED=true (the kill switch)" \
      gh variable set AUTOMATION_ENABLED --repo "$REPO" --body true
  fi
}

apply_rulesets() {
  bold "Rulesets"
  local file name id
  for file in "$SETTINGS"/rulesets/*.json; do
    name=$(jq -r .name "$file")
    id=$(api "repos/$REPO/rulesets" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
    if [[ -n "$id" ]]; then
      run "updated ruleset '$name'" api -X PUT "repos/$REPO/rulesets/$id" --input "$file"
    else
      run "created ruleset '$name'" api -X POST "repos/$REPO/rulesets" --input "$file"
    fi
  done
}

apply_releases_and_pages() {
  bold "Releases and Pages"
  try "immutable releases" api -X PUT "repos/$REPO/immutable-releases"
  if api "repos/$REPO/pages" >/dev/null 2>&1; then
    run "Pages builds from GitHub Actions" api -X PUT "repos/$REPO/pages" -f build_type=workflow
  else
    run "Pages enabled, built from GitHub Actions" api -X POST "repos/$REPO/pages" -f build_type=workflow
  fi
  try "Pages enforces HTTPS" api -X PUT "repos/$REPO/pages" -F https_enforced=true
}

apply_labels() {
  bold "Labels"
  local name color desc
  while IFS=$'\t' read -r name color desc; do
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
  done < <(jq -r '.[] | [.name, .color, .description] | @tsv' "$SETTINGS/labels.json")
  ok "$(jq length "$SETTINGS/labels.json") labels from $SETTINGS/labels.json"
}

apply_project() {
  bold "Project board"
  local num
  num=$(gh project list --owner "$OWNER" --format json --limit 200 \
    | jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title == $t) | .number' | head -n1)
  if [[ -z "$num" ]]; then
    num=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json | jq -r .number)
    ok "created project '$PROJECT_TITLE' (#$num)"
  else
    ok "project '$PROJECT_TITLE' exists (#$num)"
  fi
  try "project linked to $REPO" gh project link "$num" --owner "$OWNER" --repo "$REPO"
  run "project is public" gh project edit "$num" --owner "$OWNER" --visibility PUBLIC \
    --description "What is wanted now, what is coming next, and who is working on what."
}

# ---------------------------------------------------------------------------

check_all() {
  bold "Repository"
  local repo; repo=$(get "repos/$REPO")
  expect "visibility" "$(jq -r .visibility <<<"$repo")" public
  expect "Discussions enabled" "$(jq -r .has_discussions <<<"$repo")" true
  expect "secret scanning" "$(jq -r '.security_and_analysis.secret_scanning.status' <<<"$repo")" enabled
  expect "push protection" "$(jq -r '.security_and_analysis.secret_scanning_push_protection.status' <<<"$repo")" enabled
  if api "repos/$REPO/vulnerability-alerts" >/dev/null 2>&1; then ok "Dependabot alerts"; else fail "Dependabot alerts are off"; fi
  expect "private vulnerability reporting" "$(get "repos/$REPO/private-vulnerability-reporting" --jq .enabled)" true

  bold "GitHub Actions"
  local perms; perms=$(get "repos/$REPO/actions/permissions")
  expect "allowed actions" "$(jq -r .allowed_actions <<<"$perms")" selected
  expect "SHA pinning required" "$(jq -r .sha_pinning_required <<<"$perms")" true
  local sel; sel=$(get "repos/$REPO/actions/permissions/selected-actions")
  expect "verified-creator actions not blanket-allowed" "$(jq -r .verified_allowed <<<"$sel")" false
  expect "allowed action patterns" "$(jq -c '.patterns_allowed | sort' <<<"$sel")" \
    "$(jq -c 'sort' "$SETTINGS/allowed-actions.json")"
  local wf; wf=$(get "repos/$REPO/actions/permissions/workflow")
  expect "default workflow token" "$(jq -r .default_workflow_permissions <<<"$wf")" read
  expect "workflows may approve PRs" "$(jq -r .can_approve_pull_request_reviews <<<"$wf")" false
  expect "fork PR approval policy" \
    "$(get "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy)" \
    first_time_contributors_new_to_github

  bold "Secrets and environment"
  expect "repository-level secrets (all secrets belong in '$ENV_NAME')" \
    "$(get "repos/$REPO/actions/secrets" --jq .total_count)" 0
  expect "Dependabot secrets" "$(get "repos/$REPO/dependabot/secrets" --jq .total_count)" 0
  local env; env=$(get "repos/$REPO/environments/$ENV_NAME")
  expect "'$ENV_NAME' uses a custom branch policy" \
    "$(jq -r '.deployment_branch_policy.custom_branch_policies' <<<"$env")" true
  expect "'$ENV_NAME' deployable only from" \
    "$(get "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
        --jq '[.branch_policies[] | "\(.type):\(.name)"] | join(",")')" "branch:$RELEASE_BRANCH"
  local have s
  have=$(get "repos/$REPO/environments/$ENV_NAME/secrets" --jq '[.secrets[].name] | join(" ")')
  for s in "${ENV_SECRETS[@]}"; do
    if [[ " $have " == *" $s "* ]]; then ok "secret $s is set in '$ENV_NAME'"; else warn "secret $s is not set yet (docs/SETUP-APP.md)"; fi
  done

  bold "Variables"
  expect "OWNER_ID" "$(get "repos/$REPO/actions/variables/OWNER_ID" --jq .value)" "$(get "users/$OWNER" --jq .id)"
  local kill; kill=$(get "repos/$REPO/actions/variables/AUTOMATION_ENABLED" --jq .value)
  case "$kill" in
    true)  ok "AUTOMATION_ENABLED=true" ;;
    false) warn "AUTOMATION_ENABLED=false: the kill switch is engaged" ;;
    *)     fail "AUTOMATION_ENABLED is missing or invalid ('$kill')" ;;
  esac
  local bot; bot=$(get "repos/$REPO/actions/variables/BOT_LOGIN" --jq .value)
  if [[ "$bot" == *"[bot]" ]]; then ok "BOT_LOGIN=$bot"; else warn "BOT_LOGIN is not set yet (docs/SETUP-APP.md)"; fi

  bold "Rulesets and CODEOWNERS"
  local file name id live
  for file in "$SETTINGS"/rulesets/*.json; do
    name=$(jq -r .name "$file")
    id=$(get "repos/$REPO/rulesets" | jq -r --arg n "$name" '.[]? | select(.name == $n) | .id')
    if [[ -z "$id" ]]; then fail "ruleset '$name' is missing"; continue; fi
    live=$(get "repos/$REPO/rulesets/$id")
    expect "ruleset '$name' enforcement" "$(jq -r .enforcement <<<"$live")" active
    expect "ruleset '$name' bypass actors" "$(jq -c '[.bypass_actors[] | {actor_id, actor_type, bypass_mode}]' <<<"$live")" \
      "$(jq -c '.bypass_actors' "$file")"
    expect "ruleset '$name' rules" "$(jq -c '[.rules[].type] | sort' <<<"$live")" "$(jq -c '[.rules[].type] | sort' "$file")"
  done
  expect "main requires code-owner review" \
    "$(get "repos/$REPO/rules/branches/$RELEASE_BRANCH" --jq 'any(.[]; .type == "pull_request" and .parameters.require_code_owner_review)')" true
  if api "repos/$REPO/contents/.github/CODEOWNERS" >/dev/null 2>&1; then
    expect "CODEOWNERS errors" "$(get "repos/$REPO/codeowners/errors" --jq '.errors | length')" 0
  else
    fail ".github/CODEOWNERS is not on $RELEASE_BRANCH"
  fi

  bold "Releases and Pages"
  expect "immutable releases" "$(get "repos/$REPO/immutable-releases" --jq .enabled)" true
  expect "Pages build type" "$(get "repos/$REPO/pages" --jq .build_type)" workflow

  bold "Labels and project"
  local labels missing
  labels=$(gh label list --repo "$REPO" --limit 500 --json name --jq '.[].name' 2>/dev/null || true)
  missing=$(jq -r '.[].name' "$SETTINGS/labels.json" | grep -vxF -f <(printf '%s\n' "$labels") || true)
  if [[ -z "$missing" ]]; then ok "all labels exist"; else fail "missing labels: $(paste -sd, <<<"$missing")"; fi
  if gh project list --owner "$OWNER" --format json 2>/dev/null \
      | jq -e --arg t "$PROJECT_TITLE" 'any(.projects[]; .title == $t)' >/dev/null; then
    ok "project '$PROJECT_TITLE' exists"
  else
    fail "project '$PROJECT_TITLE' is missing"
  fi
}

manual_steps() {
  bold "Do these by hand (no API exists for them)"
  cat <<EOF
  1. Discussions categories: Ideas, Spell combos, Art feedback
     https://github.com/$REPO/discussions/categories
  2. Project board: turn on the built-in "Auto-add to project" workflow for
     $REPO, and create the views from docs/PLAN.md ("Project board views").
     https://github.com/users/$OWNER/projects
  3. Continue with docs/SETUP-APP.md, then docs/SECURITY-CHECKLIST.md.
EOF
}

summary() {
  bold "Summary"
  if ((${#FAILURES[@]})); then
    printf '  \033[31m%d failed\033[0m:\n' "${#FAILURES[@]}"; printf '    - %s\n' "${FAILURES[@]}"
  fi
  if ((${#WARNINGS[@]})); then
    printf '  \033[33m%d warnings\033[0m:\n' "${#WARNINGS[@]}"; printf '    - %s\n' "${WARNINGS[@]}"
  fi
  ((${#FAILURES[@]} + ${#WARNINGS[@]})) || ok "everything matches"
  ((${#FAILURES[@]} == 0))
}

# ---------------------------------------------------------------------------

case "${1:-}" in
  "")       MODE=apply ;;
  --check)  MODE=check ;;
  -h|--help) sed -n '5,13p' "$0"; exit 0 ;;
  *)        die "unknown option '$1' (try --help)" ;;
esac

preflight
ensure_repo
if [[ "$MODE" == apply ]]; then
  apply_repo_settings
  apply_actions
  apply_environment
  apply_variables
  apply_rulesets
  apply_releases_and_pages
  apply_labels
  apply_project
  manual_steps
fi
bold "Verifying"
check_all
summary

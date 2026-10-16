#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the same hard rules as CI on your changes (committed, uncommitted and
# new files), compared with origin/main. Needs git and Python 3.10 or newer.
#
#   tools/check.sh
#
# Every problem is reported with the rule, file, line and how to fix it.
set -eu
cd "$(dirname "$0")/.."

if git remote get-url origin >/dev/null 2>&1; then
  git fetch --quiet origin main || echo "warning: could not fetch origin/main; using the local copy" >&2
fi

PYTHONPATH=ci exec python3 -m smbot.rules --base origin/main --worktree "$@"

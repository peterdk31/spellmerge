#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Start a new game from this repository's automation: asks a few questions, then sets up the
# repository, its bot app and the first development session (ci/smbot/bootstrap.py).
set -euo pipefail
cd "$(dirname "$0")"
PYTHONPATH=ci exec python3 -m smbot.bootstrap "$@"

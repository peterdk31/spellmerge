#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Pushes a release to itch.io with butler (docs/PLAN.md, "Daily run", step 7).
#
#   BUTLER_API_KEY=... ci/build/itch.sh <itch user/game> <version> <stable|nightly> <dist dir>
#
# Stable builds go to the default channels (web, windows, linux); nightly builds
# go to web-nightly, windows-nightly and linux-nightly.
set -euo pipefail

TARGET=$1 VERSION=$2 CHANNEL=$3 DIST=$4
cd "$(dirname "$0")/../.."
# shellcheck source=SCRIPTDIR/godot.env
source ci/build/godot.env

[[ -n "${BUTLER_API_KEY:-}" ]] || { echo "::warning::BUTLER_API_KEY is not set; skipping itch.io"; exit 0; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl --fail --location --silent --show-error --retry 3 -o "$work/butler.zip" \
  "https://broth.itch.zone/butler/linux-amd64/$BUTLER_VERSION/archive/default"
echo "$BUTLER_SHA256  $work/butler.zip" | sha256sum --check --quiet
unzip -q "$work/butler.zip" -d "$work/butler"
chmod +x "$work/butler/butler"

suffix=""
[[ "$CHANNEL" == stable ]] || suffix="-nightly"
for platform in web windows linux; do
  "$work/butler/butler" push --userversion "$VERSION" \
    "$DIST/spellmerge-$platform-$VERSION.zip" "$TARGET:$platform$suffix"
done

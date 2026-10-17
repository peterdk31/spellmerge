#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds, smoke-tests and packages the web demo and the Windows and Linux
# builds (docs/PLAN.md, "Daily run", step 6). Used by daily.yml and locally.
#
#   ci/build/build.sh [--version v0.20261017] [--channel nightly] [--commit SHA]
#   ci/build/build.sh --quick     import and editor smoke test only (for development)
#   ci/build/build.sh --quick --tests   the same, then every tests/**/test_*.gd unit test
#
# Downloads the pinned Godot editor and export templates into $GODOT_CACHE
# (default ~/.cache/spellmerge-godot) and refuses them if a hash differs. Only
# the checked downloads are cached; Godot is unpacked fresh into build/ on every
# run, so a tampered cache can never supply an unchecked binary.
# Output: dist/ with one zip per platform and SHA256SUMS.
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source=SCRIPTDIR/godot.env
source ci/build/godot.env

VERSION="dev"
CHANNEL="dev"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
QUICK=0
TESTS=0
while (($#)); do
  case "$1" in
    --quick)   QUICK=1; shift ;;
    --tests)   TESTS=1; shift ;;
    --version) VERSION=$2; shift 2 ;;
    --channel) CHANNEL=$2; shift 2 ;;
    --commit)  COMMIT=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

CACHE="${GODOT_CACHE:-$HOME/.cache/spellmerge-godot}"
TOOLS="$PWD/build/godot"
# Keep Godot's settings, data and export templates inside build/, not in $HOME.
export XDG_DATA_HOME="$TOOLS/xdg/data" XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache"
TEMPLATES_DIR="$XDG_DATA_HOME/godot/export_templates/${GODOT_VERSION}.stable"
BASE_URL="https://github.com/godotengine/godot/releases/download/$GODOT_RELEASE"
EDITOR_ZIP="Godot_v${GODOT_RELEASE}_linux.x86_64.zip"
TEMPLATES_TPZ="Godot_v${GODOT_RELEASE}_export_templates.tpz"
GODOT="$TOOLS/Godot_v${GODOT_RELEASE}_linux.x86_64"

# Budgets from docs/PLAN.md, "Performance": compressed download sizes.
WEB_BUDGET=$((40 * 1000 * 1000))
DESKTOP_BUDGET=$((300 * 1000 * 1000))

step() { printf '\n==> %s\n' "$*"; }

fetch_verified() { # fetch_verified <file> <sha512>
  local file=$1 sum=$2
  if [[ ! -f "$CACHE/$file" ]] || ! echo "$sum  $CACHE/$file" | sha512sum --check --status; then
    curl --fail --location --silent --show-error --retry 3 -o "$CACHE/$file.part" "$BASE_URL/$file"
    mv "$CACHE/$file.part" "$CACHE/$file"
  fi
  echo "$sum  $CACHE/$file" | sha512sum --check --quiet || { echo "hash mismatch for $file" >&2; exit 1; }
}

setup_godot() {
  step "Godot $GODOT_RELEASE (hash-checked)"
  mkdir -p "$CACHE"
  fetch_verified "$EDITOR_ZIP" "$GODOT_EDITOR_SHA512"
  fetch_verified "$TEMPLATES_TPZ" "$GODOT_TEMPLATES_SHA512"
  rm -rf "$TOOLS" && mkdir -p "$TOOLS" "$TEMPLATES_DIR"
  unzip -oq "$CACHE/$EDITOR_ZIP" -d "$TOOLS"
  unzip -oq "$CACHE/$TEMPLATES_TPZ" -d "$TOOLS"
  mv "$TOOLS/templates/"* "$TEMPLATES_DIR/"
  "$GODOT" --version
}

# Runs Godot and fails if it exits non-zero or logs any error.
godot_checked() { # godot_checked <log name> <args...>
  local log="build/logs/$1.log"; shift
  local status=0
  "$@" >"$log" 2>&1 || status=$?
  cat "$log"
  if ((status != 0)); then
    echo "::error::$(basename "$log" .log) exited with status $status"
    return 1
  fi
  if grep -nE '^(SCRIPT )?ERROR:' "$log"; then
    echo "::error::$(basename "$log" .log) logged errors (see above)"
    return 1
  fi
}

reset_build_info() {
  echo '{ "version": "dev", "channel": "dev", "commit": "" }' > core/base/build_info.json
}

stamp() {
  step "Stamping build info: $VERSION $CHANNEL ${COMMIT:0:7}"
  printf '{ "version": "%s", "channel": "%s", "commit": "%s" }\n' "$VERSION" "$CHANNEL" "$COMMIT" \
    > core/base/build_info.json
}

import_and_smoke() {
  step "Importing"
  godot_checked import "$GODOT" --headless --path . --import

  step "Boot smoke test (editor)"
  godot_checked smoke-editor "$GODOT" --headless --path . --script res://tests/smoke/boot_smoke.gd
}

# Each unit test is its own SceneTree script that quits with a non-zero code on failure,
# so each needs its own Godot process. Runs them all and then fails if any failed.
unit_tests() {
  local test failed=()
  while IFS= read -r test; do
    step "Unit test $test"
    godot_checked "unit-$(basename "$test" .gd)" "$GODOT" --headless --path . --script "res://$test" \
      || failed+=("$test")
  done < <(find tests -name 'test_*.gd' -not -path '*/fixtures/*' | sort)
  if ((${#failed[@]})); then
    echo "::error::${#failed[@]} unit test(s) failed: ${failed[*]}"
    return 1
  fi
  step "All unit tests passed"
}

export_all() {
  for preset in Web Windows Linux; do
    step "Exporting $preset"
    local out
    out=$(sed -n "/^name=\"$preset\"\$/,/^export_path=/s/^export_path=\"\(.*\)\"\$/\1/p" export_presets.cfg)
    rm -rf "$(dirname "$out")"
    mkdir -p "$(dirname "$out")"
    godot_checked "export-${preset,,}" "$GODOT" --headless --path . --export-release "$preset" "$out"
    [[ -s "$out" ]] || { echo "::error::$preset export produced no $out"; exit 1; }
  done

  step "Boot smoke test (exported Linux build)"
  godot_checked smoke-linux build/linux/Spellmerge.x86_64 --headless --quit-after 300

  step "Boot smoke test (web build in headless Chrome)"
  local status=0
  PYTHONPATH=ci python3 -m smbot.websmoke build/web --expect "main menu ready" \
    --screenshot build/logs/web.png || status=$?
  if ((status == 2)) && [[ -z "${CI:-}" ]]; then
    echo "warning: Chrome is not installed, so the web build was not smoke-tested"
  elif ((status != 0)); then
    return 1
  fi
}

zip_dir() { # zip_dir <dir> <zip>: sorted entries, fixed timestamps, file modes kept
  python3 - "$1" "$2" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            info = zipfile.ZipInfo(os.path.relpath(path, src), date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = (os.stat(path).st_mode & 0o777 | 0o100000) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as fh:
                zf.writestr(info, fh.read())
PY
}

package() {
  step "Packaging"
  rm -rf dist && mkdir -p dist
  local name
  for platform in web windows linux; do
    name="spellmerge-$platform-$VERSION.zip"
    zip_dir "build/$platform" "dist/$name"
  done
  (cd dist && sha256sum ./*.zip | sed 's| \./| |' > SHA256SUMS)
  cat dist/SHA256SUMS

  step "Size budgets"
  local size ok=1
  size=$(stat -c %s "dist/spellmerge-web-$VERSION.zip")
  echo "web: $((size / 1000)) kB of $((WEB_BUDGET / 1000)) kB"
  ((size <= WEB_BUDGET)) || { echo "::error::web download is over its 40 MB budget"; ok=0; }
  for platform in windows linux; do
    size=$(stat -c %s "dist/spellmerge-$platform-$VERSION.zip")
    echo "$platform: $((size / 1000)) kB of $((DESKTOP_BUDGET / 1000)) kB"
    ((size <= DESKTOP_BUDGET)) || { echo "::error::$platform download is over its 300 MB budget"; ok=0; }
  done
  ((ok))
}

mkdir -p build
touch build/.gdignore # keeps Godot from importing the exported files as game assets
setup_godot
mkdir -p build/logs
if ((QUICK)); then
  import_and_smoke
  ((TESTS)) && unit_tests
  step "Quick check passed"
  exit 0
fi
stamp
trap reset_build_info EXIT
import_and_smoke
export_all
package
step "Done: dist/"

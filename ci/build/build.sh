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
#   ci/build/build.sh --quick --screenshots   the same, then every tests/screenshots/shot_*.gd
#                                     on a virtual display (xvfb-run, or $DISPLAY without it), up to
#                                     8 at once; PNGs in build/screenshots/, and shots.txt there
#                                     saying which script made each one.
#                                     SHOTS_ONLY="shot_a shot_b" runs only those scripts;
#                                     SHOT_JOBS=1 runs them one at a time.
#   ci/build/build.sh --quick --clips   the same, then the clip recorder (tests/clips/record.gd)
#                                     on a virtual display; one folder of frames per clip in
#                                     build/clips/ (format: ci/smbot/clips.py), and atlas.json
#                                     from tools/atlas.py. CLIPS_ONLY="id_a id_b" records only
#                                     those clips. A failed recording warns; it never fails.
#
# --screenshots and --clips can be given together.
#
# A full build runs the unit tests and takes the screenshots too.
#
# Downloads the pinned Godot editor and export templates into $GODOT_CACHE
# (default ~/.cache/pinned-godot) and refuses them if a hash differs. Only
# the checked downloads are cached; Godot is unpacked fresh into build/ on every
# run, so a tampered cache can never supply an unchecked binary.
# Output: dist/ with one zip per platform and SHA256SUMS.
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source=SCRIPTDIR/godot.env
source ci/build/godot.env
# The game's name (project.godot, the export paths) and slug (the zips), from ci/config.json.
GAME_NAME=$(PYTHONPATH=ci python3 -m smbot.config get game.name)
SLUG=$(PYTHONPATH=ci python3 -m smbot.config get game.slug)
READY_LINE=$(PYTHONPATH=ci python3 -m smbot.config ready)

VERSION="dev"
CHANNEL="dev"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
QUICK=0
TESTS=0
SHOTS=0
CLIPS=0
while (($#)); do
  case "$1" in
    --quick)   QUICK=1; shift ;;
    --tests)   TESTS=1; shift ;;
    --screenshots) SHOTS=1; shift ;;
    --clips)   CLIPS=1; shift ;;
    --version) VERSION=$2; shift 2 ;;
    --channel) CHANNEL=$2; shift 2 ;;
    --commit)  COMMIT=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

CACHE="${GODOT_CACHE:-$HOME/.cache/pinned-godot}"
TOOLS="$PWD/build/godot"
# Keep Godot's settings, data and export templates inside build/, not in $HOME.
export XDG_DATA_HOME="$TOOLS/xdg/data" XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache"
TEMPLATES_DIR="$XDG_DATA_HOME/godot/export_templates/${GODOT_VERSION}.stable"
BASE_URL="https://github.com/godotengine/godot/releases/download/$GODOT_RELEASE"
EDITOR_ZIP="Godot_v${GODOT_RELEASE}_linux.x86_64.zip"
TEMPLATES_TPZ="Godot_v${GODOT_RELEASE}_export_templates.tpz"
GODOT="$TOOLS/Godot_v${GODOT_RELEASE}_linux.x86_64"

# Budgets from docs/PLAN.md, "Performance": compressed download sizes.
WEB_BUDGET=$(($(PYTHONPATH=ci python3 -m smbot.config budget web_mb) * 1000 * 1000))
DESKTOP_BUDGET=$(($(PYTHONPATH=ci python3 -m smbot.config budget desktop_mb) * 1000 * 1000))
# docs/PLAN.md target: the web build loads in under 10 s (here from a local server, so no
# download). Over it the web smoke test warns with likely fixes; it never fails the build.
WEB_LOAD_WARN=$(PYTHONPATH=ci python3 -m smbot.config budget web_load_s)

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

# Each shot script saves PNGs to user://screenshots/ (scripts may only write to user://),
# which is Godot's data folder for the project under $XDG_DATA_HOME; every script gets a data
# folder of its own, so up to SHOT_JOBS of them (default: the cores, at most 8) run at once,
# each on its own virtual display (`--auto-servernum` started several at once can pick the same
# number, so each job is given one). --fixed-fps makes each frame 1/60 s of game time however
# slow it is to draw, so a script sees the same game whether it runs alone or beside seven others.
screenshots() {
  step "Screenshots (virtual display)"
  local virtual=1
  if ! command -v xvfb-run >/dev/null; then
    if [[ -n "${CI:-}" ]]; then
      echo "::error::xvfb-run is not installed (sudo apt-get install xvfb)"
      return 1
    elif [[ -z "${DISPLAY:-}" ]]; then
      echo "warning: xvfb-run is not installed and there is no display, so no screenshots were taken"
      return 0
    fi
    echo "xvfb-run is not installed, so the screenshots are drawn on the display $DISPLAY"
    virtual=0
  fi
  local runs="$PWD/build/screenshot-runs" script name png display=() scripts=() failed=()
  local cores; cores=$(nproc)
  local parallel="${SHOT_JOBS:-$((cores < 8 ? cores : 8))}"
  rm -rf build/screenshots "$runs" && mkdir -p build/screenshots "$runs"
  : > build/screenshots/shots.txt
  while IFS= read -r script; do
    name=$(basename "$script" .gd)
    if [[ -n "${SHOTS_ONLY:-}" && " $SHOTS_ONLY " != *" $name "* ]]; then continue; fi
    scripts+=("$script")
    while (($(jobs -rp | wc -l) >= parallel)); do wait -n || true; done
    if ((virtual)); then
      display=(xvfb-run --server-num=$((100 + ${#scripts[@]})) --server-args="-screen 0 1280x720x24")
    fi
    (XDG_DATA_HOME="$runs/$name" godot_checked "shot-$name" "${display[@]}" "$GODOT" --path . \
      --rendering-driver opengl3 --audio-driver Dummy --fixed-fps 60 --script "res://$script" \
      || touch "$runs/$name.failed") &
  done < <(find tests/screenshots -name 'shot_*.gd' 2>/dev/null | sort)
  wait
  for script in "${scripts[@]}"; do
    name=$(basename "$script" .gd)
    [[ -f "$runs/$name.failed" ]] && failed+=("$script")
    for png in "$runs/$name/godot/app_userdata/$GAME_NAME/screenshots"/*.png; do
      [[ -f "$png" ]] || continue
      cp "$png" build/screenshots/
      echo "$name $(basename "$png")" >> build/screenshots/shots.txt
    done
  done
  ls -l build/screenshots
  if ((${#failed[@]})); then
    echo "::error::${#failed[@]} screenshot script(s) failed: ${failed[*]}"
    return 1
  fi
}

# The recorder saves one folder per clip to user://clips/ (the format is in ci/smbot/clips.py);
# the ids to record are its user arguments, none meaning every clip. The clips are build output
# for the atlas and the PR comments, so a recorder that fails or is missing only warns.
clips() {
  step "Clips (virtual display)"
  rm -rf build/clips && mkdir -p build/clips
  if [[ ! -f tests/clips/record.gd ]]; then
    echo "warning: there is no tests/clips/record.gd yet, so no clips were recorded"
    return 0
  fi
  if ! command -v xvfb-run >/dev/null; then
    echo "::warning::xvfb-run is not installed (sudo apt-get install xvfb), so no clips were recorded"
    return 0
  fi
  local saved="$XDG_DATA_HOME/godot/app_userdata/$GAME_NAME/clips" id words=() ids=()
  read -ra words <<<"${CLIPS_ONLY:-}"
  for id in "${words[@]}"; do
    if [[ "$id" =~ ^[a-z0-9_]{1,60}$ ]]; then ids+=("$id"); else echo "skipping clip id '$id'"; fi
  done
  if [[ -n "${CLIPS_ONLY:-}" && ${#ids[@]} -eq 0 ]]; then
    echo "no valid clip ids in CLIPS_ONLY, so no clips were recorded"
    return 0
  fi
  rm -rf "$saved"
  godot_checked clips timeout 1500 xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
    "$GODOT" --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/clips/record.gd \
    -- "${ids[@]}" \
    || echo "::warning::the clip recorder failed (build/logs/clips.log); the clips it saved are kept"
  if [[ -d "$saved" ]]; then
    cp -r "$saved"/. build/clips/
  fi
  if [[ -f tools/atlas.py ]]; then
    python3 tools/atlas.py build/clips/atlas.json \
      || echo "::warning::tools/atlas.py failed, so the atlas lists the clips without their descriptions"
  fi
  echo "$(find build/clips -name meta.json | wc -l) clip(s) in build/clips"
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
  godot_checked smoke-linux build/linux/"$GAME_NAME".x86_64 --headless --quit-after 300

  # The shipped presets leave tests/ out; "Linux Test" is the Linux preset with tests, never
  # packaged. An exported build can't run a --script, so the game starts each test runner on its
  # user argument. The runs are the game's own (tests/build.json, which the bot maintains:
  # for Spellmerge the 4-bot test, the stress run and the projectile timing); none skips this.
  local runs name arg label linux_ok web_ok web_timeout
  runs=$(PYTHONPATH=ci python3 -m smbot.config runs)
  if [[ -n "$runs" ]]; then
    rm -rf build/linux-test && mkdir -p build/linux-test
    godot_checked export-linux-test "$GODOT" --headless --path . --export-release "Linux Test" build/linux-test/"$GAME_NAME".x86_64
    [[ -s build/linux-test/"$GAME_NAME".x86_64 ]] || { echo "::error::Linux Test export produced no binary"; exit 1; }
    while IFS=$'\t' read -r name arg label linux_ok web_ok web_timeout; do
      step "$label (exported Linux build with tests)"
      godot_checked "$name-linux" timeout 300 build/linux-test/"$GAME_NAME".x86_64 --headless -- "$arg"
      grep -q -- "$linux_ok" "build/logs/$name-linux.log" \
        || { echo "::error::$label did not print '$linux_ok' in the Linux Test export"; exit 1; }
    done <<<"$runs"
  fi

  step "Boot smoke test (web build in headless Chrome)"
  local status=0
  PYTHONPATH=ci python3 -m smbot.websmoke build/web --expect "$READY_LINE" --warn-load "$WEB_LOAD_WARN" \
    --screenshot build/logs/web.png || status=$?
  if ((status == 2)) && [[ -z "${CI:-}" ]]; then
    echo "warning: Chrome is not installed, so the web build was not smoke-tested"
    return 0
  elif ((status != 0)); then
    return 1
  fi

  # "Web Test" is the Web preset with tests/, never zipped or deployed. The game reads the run's
  # argument from the page's start config, which websmoke fills in. The logs go to build/logs like
  # the Linux ones, so the Daily log can quote them (smbot.summary).
  [[ -n "$runs" ]] || return 0
  rm -rf build/web-test && mkdir -p build/web-test
  godot_checked export-web-test "$GODOT" --headless --path . --export-release "Web Test" build/web-test/index.html
  [[ -s build/web-test/index.html ]] || { echo "::error::Web Test export produced no index.html"; exit 1; }
  while IFS=$'\t' read -r name arg label linux_ok web_ok web_timeout; do
    step "$label (exported web build with tests, headless Chrome)"
    PYTHONPATH=ci python3 -m smbot.websmoke build/web-test --page-args="$arg" --expect "$web_ok" \
      --timeout "$web_timeout" 2>&1 | tee "build/logs/$name-web.log"
  done <<<"$runs"
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
    name="$SLUG-$platform-$VERSION.zip"
    zip_dir "build/$platform" "dist/$name"
  done
  (cd dist && sha256sum ./*.zip | sed 's| \./| |' > SHA256SUMS)
  cat dist/SHA256SUMS

  # Budgets warn, with likely fixes; they never fail the build (docs/PLAN.md, "Gates are sparse").
  step "Size budgets"
  local size
  size=$(stat -c %s "dist/$SLUG-web-$VERSION.zip")
  echo "web: $((size / 1000)) kB of $((WEB_BUDGET / 1000)) kB"
  ((size <= WEB_BUDGET)) || echo "::warning::web download is over its $((WEB_BUDGET / 1000000)) MB budget (tests/build.json). Not a failure. Likely fixes: big textures or sounds added recently (art/manifest.json, audio/manifest.json), more content the Web preset could exclude (export_presets.cfg, the demo flag), uncompressed imports"
  for platform in windows linux; do
    size=$(stat -c %s "dist/$SLUG-$platform-$VERSION.zip")
    echo "$platform: $((size / 1000)) kB of $((DESKTOP_BUDGET / 1000)) kB"
    ((size <= DESKTOP_BUDGET)) || echo "::warning::$platform download is over its $((DESKTOP_BUDGET / 1000000)) MB budget (tests/build.json). Not a failure. Likely fixes: big textures or sounds added recently, uncompressed imports, test or source files the export should exclude"
  done
}

mkdir -p build
touch build/.gdignore # keeps Godot from importing the exported files as game assets
setup_godot
mkdir -p build/logs
if ((QUICK)); then
  import_and_smoke
  ((TESTS)) && unit_tests
  ((SHOTS)) && screenshots
  ((CLIPS)) && clips
  step "Quick check passed"
  exit 0
fi
stamp
trap reset_build_info EXIT
import_and_smoke
unit_tests
screenshots
export_all
package
step "Done: dist/"

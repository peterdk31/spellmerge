#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Puts the WebRTC extension (godotengine/webrtc-native) in addons/webrtc_native/, so the editor,
# the tests and the Linux and Windows exports have WebRTC (docs/milestones/netcode-spike.md, S3;
# the browser has its own, so the web exports leave the folder out: export_presets.cfg):
#
#   ci/build/webrtc.sh
#
# It is the project's official release, pinned in ci/build/godot.env by version and SHA-256 (the
# owner's decision 7 of 2026-11-10), downloaded once into $GODOT_CACHE (default
# ~/.cache/pinned-godot, beside the pinned Godot, which CI keeps between runs) and checked on every
# run. The folder is made fresh from the checked archive each time, so nothing a cache or an
# earlier run left is loaded.
#
# Everything about the release is known here and nowhere else (build.sh only copies what this
# leaves): what is unpacked, by exact name (the file that names the libraries, the release's own;
# the x86_64 libraries the editor, the tests and the exports load; the licenses), which libraries
# it contains (LICENSES below: a release that adds or drops one fails here, so the notice is
# looked at again), and the notice a build ships beside it, written to notices/ with the licenses.
# Nothing here is committed (addons/ is ignored by git; hard rule 2). No script loads the
# extension: the engine's WebRTCPeerConnection uses it where it is there (net/net_webrtc.gd asks).
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source=SCRIPTDIR/godot.env
source ci/build/godot.env

CACHE="${GODOT_CACHE:-$HOME/.cache/pinned-godot}"
ZIP="$CACHE/webrtc-native-$WEBRTC_VERSION.zip"
URL="https://github.com/godotengine/webrtc-native/releases/download/$WEBRTC_VERSION/$WEBRTC_ZIP"
DIR=addons/webrtc_native

# The libraries inside the release, each with the license file the archive carries for it. The
# notice below names them; update both together.
LICENSES=(LICENSE.libdatachannel LICENSE.libjuice LICENSE.libsrtp LICENSE.mbedtls LICENSE.plog
  LICENSE.usrsctp LICENSE.webrtc-native)
# Linux: the editor and the tests load the debug library, a release export the release one.
# Windows: only exported, as a release.
LIBRARIES=(libwebrtc_native.linux.template_debug.x86_64.so libwebrtc_native.linux.template_release.x86_64.so
  libwebrtc_native.windows.template_release.x86_64.dll)

mkdir -p "$CACHE"
if [[ ! -f "$ZIP" ]] || ! echo "$WEBRTC_ZIP_SHA256  $ZIP" | sha256sum --check --status; then
  # A part file of this run's own: two worktrees may fetch at once.
  curl --fail --location --silent --show-error --retry 3 -o "$ZIP.part.$$" "$URL"
  mv "$ZIP.part.$$" "$ZIP"
fi
echo "$WEBRTC_ZIP_SHA256  $ZIP" | sha256sum --check --quiet || { echo "hash mismatch for $ZIP" >&2; exit 1; }

rm -rf "$DIR"
python3 - "$ZIP" "$DIR" "${LIBRARIES[@]}" <<'PY'
import re, sys, zipfile
from pathlib import Path

archive, out, libraries = sys.argv[1], Path(sys.argv[2]), sys.argv[3:]
# Each a plain file name under the archive's addons/webrtc_native/ (so no entry can be written
# anywhere else): the extension's file, every license, the libraries asked for.
wanted = re.compile(r"addons/webrtc_native/(webrtc_native\.gdextension|(notices/)?LICENSE\.[A-Za-z0-9_-]+|lib/(%s))"
                    % "|".join(re.escape(name) for name in libraries))
with zipfile.ZipFile(archive) as zf:
    for info in zf.infolist():
        if info.is_dir() or not wanted.fullmatch(info.filename):
            continue
        name = info.filename.removeprefix("addons/webrtc_native/")
        if name.startswith("LICENSE."):
            name = "notices/" + name
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(zf.read(info))
PY

[[ -s "$DIR/webrtc_native.gdextension" ]] || { echo "the WebRTC extension's archive has no webrtc_native.gdextension" >&2; exit 1; }
for library in "${LIBRARIES[@]}"; do
  [[ -s "$DIR/lib/$library" ]] || { echo "the WebRTC extension's archive has no lib/$library" >&2; exit 1; }
done
found=$(cd "$DIR/notices" && printf '%s ' LICENSE.*)
[[ "$found" == "$(printf '%s ' "${LICENSES[@]}")" ]] || {
  echo "the WebRTC extension's licenses are not the ones the notice names (ci/build/webrtc.sh, LICENSES):" >&2
  echo "  found:    $found" >&2
  echo "  expected: ${LICENSES[*]}" >&2
  exit 1
}

# The notice a build ships with the library (build.sh copies notices/ whole). MPL-2.0
# (libdatachannel, libjuice) asks that a player is told where the source is.
cat > "$DIR/notices/README.txt" <<NOTICE
The libwebrtc_native library beside the game is the WebRTC extension for Godot
(webrtc-native $WEBRTC_VERSION), as its project released it, unchanged:
  https://github.com/godotengine/webrtc-native/releases/tag/$WEBRTC_VERSION

It is under the MIT license (LICENSE.webrtc-native) and contains these libraries, each under the
license in the file of its name here:
  libdatachannel and libjuice (MPL-2.0), libsrtp and usrsctp (BSD-3-Clause),
  mbedTLS (Apache-2.0), plog (MIT).
Where the source of each is, and the exact version built, is listed in that project's repository
at the tag $WEBRTC_VERSION:
  https://github.com/godotengine/webrtc-native/blob/$WEBRTC_VERSION/thirdparty/README.md
NOTICE
echo "==> $DIR: webrtc-native $WEBRTC_VERSION"

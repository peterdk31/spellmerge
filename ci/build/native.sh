#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the native module (native/README.md) from source for the given platforms and writes
# native/spellmerge.gdextension naming the libraries that exist, so Godot loads them:
#
#   ci/build/native.sh [linux] [web] [windows]      (default: linux)
#
# Nothing built is committed (native/bin/ and the .gdextension are ignored by git); a checkout
# that never ran this runs the GDScript the module stands for. The tools are pinned in
# ci/build/godot.env and kept in $NATIVE_CACHE (default ~/.cache/spellmerge-native): godot-cpp at
# its tag and commit, SCons from its hash-checked wheel, and for the web Emscripten at the version
# Godot's own web templates were built with (a different one makes a module the game can't load).
# A tool already in the cache at its pin is used as it is; one missing is fetched once. CI keeps
# the cache between runs (`native-*` in the workflows; only the daily build saves it, every other
# job restores it): on every run the commits and the wheel's hash are checked again, godot-cpp's
# tree is checked for edits and cleaned of everything else, and SCons is unpacked fresh. The
# toolchain emsdk installed (clang, node) is not hashed: it is trusted as emsdk downloaded it.
# Needs a C++ compiler (g++ or clang) for linux, MinGW-w64 for windows (x86_64-w64-mingw32-g++;
# on Ubuntu `apt-get install g++-mingw-w64-x86-64-posix`, as the workflows do), git, and Python 3.10+.
# Every platform asked for must build: a failure fails the script.
set -euo pipefail

cd "$(dirname "$0")/../.."
# shellcheck source=SCRIPTDIR/godot.env
source ci/build/godot.env

CACHE="${NATIVE_CACHE:-$HOME/.cache/spellmerge-native}"
GODOT_CPP="$CACHE/godot-cpp-${GODOT_CPP_TAG%-stable}"
SCONS_WHEEL="$CACHE/scons-$SCONS_VERSION-py3-none-any.whl"
# Unpacked fresh from the checked wheel on every run, inside build/, as build.sh does for Godot.
SCONS_DIR="$PWD/build/native-tools/scons-$SCONS_VERSION"
EMSDK="$CACHE/emsdk-$EMSDK_VERSION"
JOBS="${NATIVE_JOBS:-$(nproc)}"
platforms=("$@")
((${#platforms[@]})) || platforms=(linux)

mkdir -p "$CACHE"

setup_godot_cpp() {
  if [[ ! -d "$GODOT_CPP/.git" ]]; then
    git clone --quiet --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$GODOT_CPP.part"
    mv "$GODOT_CPP.part" "$GODOT_CPP"
  fi
  local head; head=$(git -C "$GODOT_CPP" rev-parse HEAD)
  [[ "$head" == "$GODOT_CPP_COMMIT" ]] || { echo "godot-cpp in $GODOT_CPP is at $head, not the pinned $GODOT_CPP_COMMIT" >&2; exit 1; }
  # A restored cache must not bring edited sources, nor anything that is not the pinned tree: the
  # tracked files are checked, and everything else (what an earlier build generated) is removed, so
  # every run builds godot-cpp from the pinned sources alone (seconds, with build_profile.json).
  git -C "$GODOT_CPP" diff --quiet HEAD || { echo "godot-cpp in $GODOT_CPP has edited files" >&2; exit 1; }
  git -C "$GODOT_CPP" clean -xdfq
}

setup_scons() {
  if [[ ! -f "$SCONS_WHEEL" ]]; then
    curl --fail --location --silent --show-error --retry 3 -o "$SCONS_WHEEL.part" "$SCONS_WHEEL_URL"
    mv "$SCONS_WHEEL.part" "$SCONS_WHEEL"
  fi
  echo "$SCONS_WHEEL_SHA256  $SCONS_WHEEL" | sha256sum --check --quiet || { echo "hash mismatch for $SCONS_WHEEL" >&2; exit 1; }
  rm -rf "$SCONS_DIR" && mkdir -p "$SCONS_DIR"
  python3 -m zipfile -e "$SCONS_WHEEL" "$SCONS_DIR"
}

setup_emsdk() {
  if [[ ! -d "$EMSDK/.git" ]]; then
    git clone --quiet --depth 1 --branch "$EMSDK_VERSION" https://github.com/emscripten-core/emsdk "$EMSDK.part"
    mv "$EMSDK.part" "$EMSDK"
  fi
  local head; head=$(git -C "$EMSDK" rev-parse HEAD)
  [[ "$head" == "$EMSDK_COMMIT" ]] || { echo "emsdk in $EMSDK is at $head, not the pinned $EMSDK_COMMIT" >&2; exit 1; }
  git -C "$EMSDK" diff --quiet HEAD || { echo "emsdk in $EMSDK has edited files" >&2; exit 1; }
  if [[ ! -f "$EMSDK/.installed-$EMSDK_VERSION" ]]; then
    "$EMSDK/emsdk" install "$EMSDK_VERSION"
    "$EMSDK/emsdk" activate "$EMSDK_VERSION"
    touch "$EMSDK/.installed-$EMSDK_VERSION"
  fi
}

scons() { # scons <args...>: the pinned SCons on native/SConstruct
  (cd native && PYTHONPATH="$SCONS_DIR" python3 -c "import SCons.Script; SCons.Script.main()" \
    godot_cpp="$GODOT_CPP" -j"$JOBS" "$@")
}

setup_godot_cpp
setup_scons
for platform in "${platforms[@]}"; do
  echo "==> native module: $platform"
  case "$platform" in
    linux) scons platform=linux target=template_release ;;
    web)
      setup_emsdk
      # shellcheck disable=SC1091
      (source "$EMSDK/emsdk_env.sh" >/dev/null 2>&1 && scons platform=web target=template_release threads=no) ;;
    windows)
      command -v x86_64-w64-mingw32-g++ >/dev/null || {
        echo "windows needs MinGW-w64 (x86_64-w64-mingw32-g++; Ubuntu: apt-get install g++-mingw-w64-x86-64-posix)" >&2
        exit 1
      }
      # The C++ runtime is linked in (godot-cpp's use_static_cpp), so the DLL needs no MinGW DLLs:
      # checked, as a player's Windows has none of them.
      scons platform=windows target=template_release arch=x86_64 use_mingw=yes
      dll=native/bin/libspellmerge.windows.template_release.x86_64.dll
      if x86_64-w64-mingw32-objdump -p "$dll" | grep -iE 'DLL Name: *(libstdc|libgcc|libwinpthread)'; then
        echo "$dll needs MinGW's runtime DLLs (above); it must link them in" >&2
        exit 1
      fi ;;
    *) echo "unknown platform $platform (linux, web, windows)" >&2; exit 2 ;;
  esac
done

# The libraries that exist, by Godot's feature tags. The editor and the exports load the release
# build: the module has no debug-only code.
{
  echo "; Written by ci/build/native.sh for the libraries built here; not committed."
  echo "[configuration]"
  echo
  echo 'entry_symbol = "spellmerge_library_init"'
  echo 'compatibility_minimum = "4.7"'
  echo "reloadable = false"
  echo
  echo "[libraries]"
  echo
  [[ -f native/bin/libspellmerge.linux.template_release.x86_64.so ]] \
    && echo 'linux.x86_64 = "res://native/bin/libspellmerge.linux.template_release.x86_64.so"'
  [[ -f native/bin/libspellmerge.web.template_release.wasm32.nothreads.wasm ]] \
    && echo 'web.wasm32 = "res://native/bin/libspellmerge.web.template_release.wasm32.nothreads.wasm"'
  [[ -f native/bin/libspellmerge.windows.template_release.x86_64.dll ]] \
    && echo 'windows.x86_64 = "res://native/bin/libspellmerge.windows.template_release.x86_64.dll"'
  true
} > native/spellmerge.gdextension
echo "==> native/spellmerge.gdextension:"
grep -E '^(linux|web|windows)' native/spellmerge.gdextension

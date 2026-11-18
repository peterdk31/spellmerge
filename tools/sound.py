#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sound tool (sound plan AU2, docs/milestones/sound.md): bake recipes into `.ogg`, hear them
on a contact sheet, and check that every generated sound is up to date.

    tools/sound.py bake [recipe or id ...]      # every recipe when none is named
    tools/sound.py sheet <recipe, id or family ...> --out DIR
    tools/sound.py check                        # no audio read, no ffmpeg: what the hash test runs

A recipe is `<id>.sound.json` in a folder of its own named `<id>` (`audio/sfx/<id>/`, or a
content item's `sounds/<id>/`). The bake renders each variant (tools/sound_synth.py), places its
loudness on its family's target (docs/STYLE.md, "Sound"), checks the peak and the ends, encodes it
with `ffmpeg -c:a libvorbis -q:a 6` and writes, in the recipe's folder only:

- a one-shot (`sfx`, `ui`): `variants/1.ogg` ... `n.ogg` and `<id>.tres`, an
  `AudioStreamRandomizer` of them with the family's pitch and volume jitter;
- a `held` sound: `<id>.ogg`, a loop (its new `.import` says `loop=true`);
- `assets.json`: one manifest entry a file, with the recipe's hash, loudness and peak.

A file whose audio is the same is not rewritten. Then it runs Godot's import, which completes the
`.import` files (`uid`, `dest_files`); an existing `.import` is never rewritten.

ffmpeg (with libvorbis, and libx264 and aac for the sheet's video) is needed by `bake` and `sheet`
only, never by `check` or a test.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound_meter  # noqa: E402
import sound_synth  # noqa: E402
from sound_synth import RATE, SoundError  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STYLE = Path("docs/STYLE.md")
PATCHES = Path("audio/patches")
SCAN = ("audio", "content")  # where sounds and their manifests are
MANIFEST = Path("audio/manifest.json")
SUFFIX = ".sound.json"
PATCH_SUFFIX = ".patch.json"
TOOL = f"tools/sound.py (procedural synthesis, generator {sound_synth.GENERATOR})"
AUTHOR = "Claude"
LICENSE = "CC-BY-SA-4.0"
WINDOW = 1.0  # LU either side of a family's target
PEAK_MARGIN = 1.0  # dB under the family's true peak limit, for Vorbis's overshoot
EDGE = 1e-3  # how near zero a one-shot's first and last samples must be
# Sounds with no recipe yet, made before the tool by a generator kept out of the repository
# (atmosphere D). AU6 remakes them as recipes, and then this list is empty and stays so.
UNRECIPED = (
    "audio/ambience/amb_crypt_air.ogg",
    "audio/ambience/amb_crypt_drip.ogg",
    "audio/ambience/amb_crypt_drip_double.ogg",
    "audio/ambience/amb_crypt_rumble.ogg",
    "audio/ambience/amb_hub_gust.ogg",
    "audio/ambience/amb_hub_void.ogg",
    "audio/ambience/amb_hub_wind.ogg",
)


class BakeError(ValueError):
    """A recipe that rendered but cannot be written: its file and what is wrong."""


# --- Families ----------------------------------------------------------------------------------

@dataclass(frozen=True)
class Family:
    name: str
    loudness: float  # LUFS
    measure: str  # "momentary" or "integrated"
    peak: float  # dBTP, the limit
    variants: int
    pitch: float  # the jitter as a share (0.04 for ±4%)
    volume: float  # the jitter in dB

    def level_of(self, samples: Sequence[float]) -> float:
        if self.measure == "integrated":
            return sound_meter.integrated(samples, RATE)
        return sound_meter.momentary_max(samples, RATE)


def families(root: Path = ROOT) -> dict[str, Family]:
    """The families of docs/STYLE.md's "Sound" table, read from there so the numbers have one home."""
    text = (root / STYLE).read_text(encoding="utf-8")
    start = text.index("## Sound")
    end = text.find("\n## ", start + 1)
    found: dict[str, Family] = {}
    row = re.compile(r"^\|\s*`(\w+)`[^|]*\|\s*(-?[\d.]+)\s+(momentary|integrated)\s*\|\s*(-?[\d.]+)\s*dBTP\s*\|"
                     r"\s*(\d+)\s*\|\s*([^|]+)\|\s*([^|]+)\|")
    for line in text[start:end].splitlines():
        m = row.match(line)
        if not m:
            continue
        pitch = re.search(r"([\d.]+)\s*%", m.group(6))
        volume = re.search(r"([\d.]+)\s*dB", m.group(7))
        found[m.group(1)] = Family(m.group(1), float(m.group(2)), m.group(3), float(m.group(4)), int(m.group(5)),
                                   float(pitch.group(1)) / 100.0 if pitch else 0.0,
                                   float(volume.group(1)) if volume else 0.0)
    if not found:
        raise ValueError(f"{STYLE}: no families in its Sound table")
    return found


# --- Recipes and their hashes ------------------------------------------------------------------

def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def load_patches(root: Path = ROOT) -> dict[str, dict]:
    found: dict[str, dict] = {}
    folder = root / PATCHES
    if folder.is_dir():
        for path in sorted(folder.glob("*" + PATCH_SUFFIX)):
            found[path.name[: -len(PATCH_SUFFIX)]] = json.loads(path.read_text(encoding="utf-8"))
    return found


def recipe_hash(recipe: dict, patches: dict[str, dict]) -> str:
    """sha256 of the recipe, every patch it names and the synth's GENERATOR."""
    named = {name: patches.get(name) for name in sound_synth.patches_named(recipe)}
    return "sha256:" + hashlib.sha256(canonical({"generator": sound_synth.GENERATOR, "recipe": recipe,
                                                 "patches": named})).hexdigest()


@dataclass(frozen=True)
class Recipe:
    path: Path  # from the repository root
    id: str
    data: dict  # as written

    @property
    def folder(self) -> Path:
        return self.path.parent

    def outputs(self, family: Family | None = None) -> list[Path]:
        """The audio files a bake writes, from the repository root."""
        if self.data.get("kind") == "held":
            return [self.folder / f"{self.id}.ogg"]
        count = self.data.get("variants", family.variants if family else 1)
        return [self.folder / "variants" / f"{i}.ogg" for i in range(1, count + 1)]


def read_recipe(path: Path, root: Path = ROOT) -> Recipe:
    """A recipe file, its path kept from the repository root (or whole, for one outside it)."""
    full = (path if path.is_absolute() else root / path).resolve()
    try:
        rel = full.relative_to(root.resolve())
    except ValueError:
        rel = full
    name = rel.name
    if not name.endswith(SUFFIX):
        raise BakeError(f"{rel}: a recipe is named <id>{SUFFIX}")
    sound_id = name[: -len(SUFFIX)]
    if rel.parent.name != sound_id:
        raise BakeError(f"{rel}: a recipe lives in a folder of its own named {sound_id}/")
    try:
        data = json.loads((root / rel).read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise BakeError(f"{rel}: not JSON ({error})") from error
    return Recipe(rel, sound_id, data)


def find_recipes(root: Path = ROOT) -> list[Recipe]:
    found: list[Recipe] = []
    for top in SCAN:
        if (root / top).is_dir():
            found += [read_recipe(p.relative_to(root), root) for p in sorted((root / top).rglob("*" + SUFFIX))]
    return found


def checked(recipe: Recipe, patches: dict[str, dict], fams: dict[str, Family]) -> tuple[dict, Family]:
    """The recipe validated (its patches merged in) and its family; raises BakeError naming the file."""
    try:
        data = sound_synth.validate(recipe.data, patches)
        family = fams.get(data["family"])
        if family is None or family.name == "music":
            raise SoundError("family", f"{data['family']!r} is not a sound family ({', '.join(f for f in fams if f != 'music')})")
        kind = data["kind"]
        if (kind == "held") != (family.name == "held") or (kind == "ui") != (family.name == "ui"):
            raise SoundError("family", f"a {kind} sound is not in the {family.name} family")
        if "gain" in data and len(data["notes"].split()) < 4:
            raise SoundError("notes", "a recipe that places its level with gain says why in its notes")
    except SoundError as error:
        raise BakeError(f"{recipe.path}: {error}") from error
    return data, family


# --- Manifests ---------------------------------------------------------------------------------

def manifest_entries(root: Path = ROOT) -> dict[str, dict]:
    """Every audio manifest entry, by its path: audio/manifest.json and every assets.json."""
    found: dict[str, dict] = {}
    files = [root / MANIFEST] + [p for top in SCAN if (root / top).is_dir() for p in sorted((root / top).rglob("assets.json"))]
    for path in files:
        if path.is_file():
            for entry in json.loads(path.read_text(encoding="utf-8")).get("assets", []):
                if isinstance(entry, dict) and isinstance(entry.get("path"), str):
                    found[entry["path"]] = entry
    return found


def check(root: Path = ROOT) -> list[str]:
    """Every problem with the generated sounds, each with its file and the command that fixes it:
    a recipe that does not validate, a file or manifest entry a recipe makes that is missing, a
    stale `recipe_hash`, and an `.ogg` that no recipe makes and no manifest entry gives another
    source (origin human, or one of UNRECIPED). Reads no audio."""
    problems: list[str] = []
    patches = load_patches(root)
    fams = families(root)
    entries = manifest_entries(root)
    made: set[str] = set()
    try:
        recipes = find_recipes(root)
    except BakeError as error:
        return [str(error)]
    for recipe in recipes:
        bake_cmd = f"run: tools/sound.py bake {recipe.path}"
        try:
            _, family = checked(recipe, patches, fams)
        except BakeError as error:
            problems.append(str(error))
            continue
        want = recipe_hash(recipe.data, patches)
        outputs = recipe.outputs(family)
        made.update(p.as_posix() for p in outputs)
        for out in outputs:
            entry = entries.get(out.as_posix())
            if not (root / out).is_file():
                problems.append(f"{out}: missing; {bake_cmd}")
            elif entry is None:
                problems.append(f"{out}: no entry in {recipe.folder / 'assets.json'}; {bake_cmd}")
            elif entry.get("recipe_hash") != want:
                problems.append(f"{out}: stale, its recipe or a patch it names changed since it was baked; {bake_cmd}")
        if recipe.data.get("kind") != "held" and not (root / recipe.folder / f"{recipe.id}.tres").is_file():
            problems.append(f"{recipe.folder / (recipe.id + '.tres')}: missing; {bake_cmd}")
        variants = root / recipe.folder / "variants"
        if variants.is_dir():
            for extra in sorted(variants.glob("*.ogg")):
                if extra.relative_to(root).as_posix() not in made:
                    problems.append(f"{extra.relative_to(root)}: a variant the recipe no longer has; {bake_cmd}")
    for top in SCAN:
        if not (root / top).is_dir():
            continue
        for ogg in sorted((root / top).rglob("*.ogg")):
            rel = ogg.relative_to(root).as_posix()
            if rel in made or rel in UNRECIPED or "/variants/" in rel:
                continue
            if entries.get(rel, {}).get("origin") != "human":
                problems.append(f"{rel}: no recipe makes it; write one beside it ({SUFFIX}), or give it a manifest "
                                "entry with origin human if it was made by hand")
    for rel in UNRECIPED:
        if rel in made:
            problems.append(f"{rel}: has a recipe now; take it off tools/sound.py's UNRECIPED")
    return problems


# --- Baking ------------------------------------------------------------------------------------

Encoder = Callable[[Sequence[float]], bytes]


def place(samples: list[list[float]], family: Family, gain: float) -> tuple[list[list[float]], list[float], list[float]]:
    """The variants scaled together onto the family's target plus `gain`, with each one's level
    and true peak after; one scale for all, so they keep their own small differences."""
    levels = [family.level_of(s) for s in samples]
    target = family.loudness + gain
    if min(levels) <= sound_meter.SILENCE:
        raise BakeError("a variant is silent")
    scale = 10.0 ** ((target - sum(levels) / len(levels)) / 20.0)
    placed = [[v * scale for v in s] for s in samples]
    shift = 20.0 * math.log10(scale)
    return placed, [lvl + shift for lvl in levels], [sound_meter.true_peak(s) for s in placed]


def render_placed(recipe: Recipe, data: dict, family: Family) -> list[tuple[list[float], float, float]]:
    """Every variant rendered, placed and checked: (samples, level, peak). Raises BakeError."""
    count = 1 if data["kind"] == "held" else data.get("variants", family.variants)
    raw = [sound_synth.render(data, i) for i in range(1, count + 1)]
    try:
        placed, levels, peaks = place(raw, family, data.get("gain", 0.0))
    except BakeError as error:
        raise BakeError(f"{recipe.path}: {error}") from error
    target = family.loudness + data.get("gain", 0.0)
    limit = family.peak - PEAK_MARGIN
    for i, (s, level, peak) in enumerate(zip(placed, levels, peaks), 1):
        name = f"{recipe.path} variant {i}"
        if abs(level - target) > WINDOW:
            raise BakeError(f"{name}: {level:.1f} LUFS {family.measure}, more than {WINDOW} LU from the others' "
                            f"{target:.1f}; make the variants less unlike (vary)")
        if peak > limit:
            raise BakeError(f"{name}: true peak {peak:.1f} dBTP at {target:.1f} LUFS, over {limit:.1f} (the "
                            f"{family.name} limit {family.peak} less {PEAK_MARGIN} for Vorbis); soften its attack "
                            "or drive, or set gain lower with a note saying why")
        if data["kind"] != "held" and (abs(s[0]) > EDGE or abs(s[-1]) > EDGE):
            raise BakeError(f"{name}: does not start and end at silence (a click)")
    return list(zip(placed, levels, peaks))


def wav_bytes(samples: Sequence[float]) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, round(v * 32767)))) for v in samples))
    return buffer.getvalue()


def need_ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if not found:
        raise BakeError("ffmpeg is not installed: bake and sheet need it with libvorbis "
                        "(apt install ffmpeg, brew install ffmpeg, or ffmpeg.org)")
    return found


def ffmpeg_encode(samples: Sequence[float]) -> bytes:
    """Vorbis at quality 6, the same bytes for the same samples (bitexact)."""
    ffmpeg = need_ffmpeg()
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp) / "in.wav", Path(tmp) / "out.ogg"
        src.write_bytes(wav_bytes(samples))
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(src), "-c:a", "libvorbis", "-q:a", "6",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", str(dst)], check=True)
        return dst.read_bytes()


def randomizer_tres(recipe: Recipe, family: Family, outputs: list[Path]) -> str:
    """`<id>.tres`: an AudioStreamRandomizer of the variants (playback_mode 0, random with no
    repeats, the default) with the family's jitter; `random_pitch` is a scale (1.04 for ±4%)."""
    lines = [f'[gd_resource type="AudioStreamRandomizer" load_steps={len(outputs) + 1} format=3]', ""]
    for i, out in enumerate(outputs, 1):
        lines.append(f'[ext_resource type="AudioStream" path="res://{out.as_posix()}" id="{i}"]')
    lines += ["", "[resource]", "playback_mode = 0",
              f"random_pitch = {1.0 + family.pitch:.4g}", f"random_volume_offset_db = {family.volume:.4g}",
              f"streams_count = {len(outputs)}"]
    for i in range(len(outputs)):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    return "\n".join(lines) + "\n"


def _write_if_changed(path: Path, data: bytes) -> bool:
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def bake(recipe: Recipe, root: Path = ROOT, encode: Encoder = ffmpeg_encode,
         say: Callable[[str], None] = print) -> list[Path]:
    """Bake one recipe; returns the files it wrote (from the repository root)."""
    patches = load_patches(root)
    data, family = checked(recipe, patches, families(root))
    rendered = render_placed(recipe, data, family)
    outputs = recipe.outputs(family)
    folder = root / recipe.folder
    written: list[Path] = []
    entries_path = folder / "assets.json"
    old = {e["path"]: e for e in json.loads(entries_path.read_text(encoding="utf-8")).get("assets", [])} if entries_path.is_file() else {}
    want = recipe_hash(recipe.data, patches)
    entries: list[dict] = []
    for out, (samples, level, peak) in zip(outputs, rendered):
        changed = _write_if_changed(root / out, encode(samples))
        if changed:
            written.append(out)
        key = out.as_posix()
        tier = old.get(key, {}).get("tier", "good")
        if changed and tier == "final":
            tier = "good"
            say(f"{out}: its audio changed, so it is back to tier good (the owner promoted the old one)")
        entries.append({"path": key, "origin": "ai", "author": AUTHOR, "license": LICENSE, "tier": tier,
                        "tool": TOOL, "prompt": recipe.path.as_posix(), "recipe_hash": want,
                        "loudness": round(level, 1), "peak": round(peak, 1)})
        importer = root / (key + ".import")
        if data["kind"] == "held" and not importer.exists():
            importer.write_text('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\n\nloop=true\n',
                                encoding="utf-8")
            written.append(Path(key + ".import"))
    # Variants the recipe no longer has go, with their .import.
    made = {o.as_posix() for o in outputs}
    if (folder / "variants").is_dir():
        for extra in sorted((folder / "variants").glob("*.ogg")):
            if extra.relative_to(root).as_posix() not in made:
                extra.unlink()
                Path(str(extra) + ".import").unlink(missing_ok=True)
                old.pop(extra.relative_to(root).as_posix(), None)
                say(f"{extra.relative_to(root)}: removed, the recipe has fewer variants")
    kept = [e for path, e in old.items() if path not in made and (root / path).is_file()]  # hand-written entries
    manifest = {"assets": sorted(entries + kept, key=lambda e: e["path"])}
    if _write_if_changed(entries_path, (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")):
        written.append(recipe.folder / "assets.json")
    if data["kind"] != "held":
        tres = recipe.folder / f"{recipe.id}.tres"
        if _write_if_changed(root / tres, randomizer_tres(recipe, family, outputs).encode("utf-8")):
            written.append(tres)
    return written


def godot() -> str | None:
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    tools = ROOT / "build/godot"
    found = sorted(tools.glob("Godot_v*_linux.x86_64")) if tools.is_dir() else []
    return str(found[0]) if found else None


def godot_import(root: Path = ROOT) -> None:
    binary = godot()
    command = [binary or "<godot>", "--headless", "--path", str(root), "--import"]
    if binary is None:
        print("Godot was not found (set GODOT, or run ci/build/build.sh --quick once); then run: "
              + " ".join(command[:2] + ["--path", ".", "--import"]))
        return
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def resolve(names: Iterable[str], root: Path = ROOT) -> list[Recipe]:
    """Recipe paths, ids, or family names into recipes."""
    every = None
    found: list[Recipe] = []
    for name in names:
        if name.endswith(SUFFIX):
            found.append(read_recipe(Path(name).resolve(), root))
            continue
        every = every if every is not None else find_recipes(root)
        hits = [r for r in every if r.id == name or r.data.get("family") == name]
        if not hits:
            raise BakeError(f"{name}: no recipe with that id or family")
        found += hits
    return found


# --- The contact sheet -------------------------------------------------------------------------

GAP = 0.4  # seconds between the sheet's parts
CROWD = (0.0, 0.023, 0.051, 0.080)  # four players casting at once, a frame or so apart


def sheet_timeline(sounds: list[tuple[str, list[list[float]]]]) -> list[float]:
    """The sheet's audio: each sound's variants in turn with a gap, then four of it at once, then
    every sound together; scaled down only if the sum would clip."""
    gap = [0.0] * round(GAP * RATE)
    out: list[float] = []

    def mix(parts: list[tuple[int, Sequence[float]]]) -> list[float]:
        size = max(start + len(p) for start, p in parts)
        buf = [0.0] * size
        for start, p in parts:
            for i, v in enumerate(p):
                buf[start + i] += v
        return buf

    for _, variants in sounds:
        for v in variants:
            out += list(v) + gap
        crowd = [(round(t * RATE), variants[i % len(variants)]) for i, t in enumerate(CROWD)]
        out += mix(crowd) + gap + gap
    if len(sounds) > 1:
        out += mix([(0, variants[0]) for _, variants in sounds]) + gap
    peak = max((abs(v) for v in out), default=0.0)
    if peak > 0.99:
        out = [v * 0.99 / peak for v in out]
    return out


def sheet(recipes: list[Recipe], out_dir: Path, root: Path = ROOT) -> list[Path]:
    """`sheet.ogg` and `sheet.mp4` (the same audio over a still card of the ids) in `out_dir`."""
    ffmpeg = need_ffmpeg()
    patches = load_patches(root)
    fams = families(root)
    sounds = []
    for recipe in recipes:
        data, family = checked(recipe, patches, fams)
        sounds.append((recipe.id, [s for s, _, _ in render_placed(recipe, data, family)]))
    audio = sheet_timeline(sounds)
    out_dir.mkdir(parents=True, exist_ok=True)
    ogg, mp4 = out_dir / "sheet.ogg", out_dir / "sheet.mp4"
    with tempfile.TemporaryDirectory() as tmp:
        wav, card = Path(tmp) / "sheet.wav", Path(tmp) / "card.txt"
        wav.write_bytes(wav_bytes(audio))
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "6", str(ogg)], check=True)
        card.write_text("Spellmerge sound sheet\n\n" + "\n".join(
            f"{i}. {sid}: variants, then four at once" for i, (sid, _) in enumerate(sounds, 1))
            + ("\n\nthen all together" if len(sounds) > 1 else "") + "\n", encoding="utf-8")
        draw = f"drawtext=textfile='{card}':fontcolor=0xf4f1ea:fontsize=28:x=60:y=60:line_spacing=12"
        command = [ffmpeg, "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x14121f:s=1280x720:r=2", "-i", str(wav),
                   "-vf", draw, "-c:v", "libx264", "-tune", "stillimage", "-pix_fmt", "yuv420p",
                   "-c:a", "aac", "-b:a", "192k", "-shortest", str(mp4)]
        if subprocess.run(command, stderr=subprocess.DEVNULL).returncode != 0:  # no drawtext: a plain card
            del command[command.index("-vf"):command.index("-vf") + 2]
            subprocess.run(command, check=True)
    return [ogg, mp4]


# --- The command -------------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("bake", help="bake recipes into .ogg (every recipe when none is named)")
    b.add_argument("names", nargs="*", help="recipe files or sound ids")
    b.add_argument("--no-import", action="store_true", help="skip Godot's import")
    s = sub.add_parser("sheet", help="a contact sheet (.ogg and .mp4) outside the repository")
    s.add_argument("names", nargs="+", help="recipe files, sound ids or a family")
    s.add_argument("--out", required=True, type=Path)
    sub.add_parser("check", help="every generated sound up to date (reads no audio)")
    args = parser.parse_args(argv)
    try:
        if args.command == "check":
            problems = check()
            for p in problems:
                print(p)
            print("sound check: " + (f"{len(problems)} problem(s)" if problems else "every generated sound is up to date"))
            return 1 if problems else 0
        if args.command == "bake":
            recipes = resolve(args.names) if args.names else find_recipes()
            written: list[Path] = []
            for recipe in recipes:
                files = bake(recipe)
                written += files
                print(f"{recipe.path}: " + (", ".join(str(f) for f in files) if files else "up to date"))
            if written and not args.no_import:
                godot_import()
            return 0
        out = args.out.resolve()
        if out == ROOT or ROOT in out.parents:
            raise BakeError(f"{args.out}: the sheet is written outside the repository, never committed")
        for path in sheet(resolve(args.names), out):
            print(path)
        return 0
    except (BakeError, SoundError) as error:
        print(f"sound: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sequencer: a music score into one buffer a layer, each exactly one loop long (sound plan
AU7, docs/milestones/sound.md, section 4).

A score (`<track>.score.json`) names its instruments (a synth layer each, usually a patch from
`audio/patches/`), its patterns (one bar each: a line of steps an instrument) and its layers (a
sound id each, playing its patterns in order, one a bar). `validate(score, patches)` checks every
key, note and length and returns the score with its instruments' patches merged in;
`render(score)` renders every layer, full scale 1.0, unplaced in level. The bake (tools/sound.py)
places the layers together on the music family's target and encodes each.

Steps: a note (`D4`, `F#3`, `Bb2`), a chord (`D3+F3+A3`), `x` (a hit at the instrument's own
pitch), `.` (a rest) and `-` (holds the note before it, across a bar too). A line's steps share
its bar evenly, so a bar of 8 is eighths in 4/4 and of 16 sixteenths.

Every layer is `bars × beats × 60 / tempo` seconds, exactly that many samples, so the layers of a
track start and stay together. It loops with no seam: a note ringing past the loop's end is heard
at its start (each note is added round the loop), and the `fx` (reverb, a low pass) run over the
loop twice through, of which the second is kept, so the room's tail at the end is heard at the
start too.

Standard library only; the synth (tools/sound_synth.py) renders each note.
"""

from __future__ import annotations

import copy
import math
import re
import zlib
from typing import Any

import sound_synth
from sound_synth import RATE, SoundError

# The sequencer's version: raised by hand whenever a change here changes what a score sounds like.
# It is in every score's hash (tools/sound.py), as GENERATOR is.
VERSION = 1
LAYERS_MOST = 4  # MusicTrack.LAYERS_MOST (core/base/music_track.gd)
STEPS = (1, 2, 3, 4, 6, 8, 12, 16, 24, 32)  # a line's steps in a bar; any other count is a typo
RING_MOST = 8.0
NOTE = re.compile(r"^([A-G])([#b]?)(-?\d)$")
SEMITONES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
ID = re.compile(r"^[a-z][a-z0-9_]*$")
NAME = re.compile(r"^[a-z][a-z0-9_]*$")

_n = sound_synth._number  # the synth's checks, so a number is checked one way everywhere
INSTRUMENT_KEYS = {"patch": lambda v, w: None, "ring": _n(0.0, RING_MOST),
                   "velocity": lambda v, w: _velocity(v, w)}
LAYER = sound_synth._object({"id": lambda v, w: _id(v, w), "play": lambda v, w: None,
                             "gain": _n(-24.0, 0.0), "notes": sound_synth._text}, ("id", "play"))
SCORE = {"version": _n(1, 1, whole=True), "tempo": _n(40.0, 240.0), "beats": _n(1, 12, whole=True),
         "bars": _n(1, 64, whole=True), "key": sound_synth._text,
         "instruments": lambda v, w: None, "patterns": lambda v, w: None, "layers": lambda v, w: None,
         "fx": sound_synth.SOUND["fx"], "gain": _n(-24.0, 24.0), "notes": sound_synth._text}


def _velocity(value: Any, where: str) -> None:
    if not isinstance(value, list) or not 1 <= len(value) <= 32:
        raise SoundError(where, "must be a list of 1 to 32 levels (0 to 1), one a step, round again")
    for i, v in enumerate(value):
        _n(0.0, 1.0)(v, f"{where}[{i}]")


def _id(value: Any, where: str) -> None:
    if not isinstance(value, str) or not ID.match(value):
        raise SoundError(where, f"{value!r} is not a sound id (lower case, digits and _)")


def hz(note: str) -> float:
    """A note's frequency, equal tempered from A4 at 440 Hz (`C4` is middle C). Raises ValueError."""
    m = NOTE.match(note)
    if not m:
        raise ValueError(note)
    semitone = SEMITONES[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)]
    midi = 12 * (int(m.group(3)) + 1) + semitone
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def tokens(line: str) -> list[str]:
    return line.split()


def loop_samples(score: dict) -> int:
    """How many samples every layer of the score has: its bars, exactly."""
    return round(score["bars"] * score["beats"] * 60.0 / score["tempo"] * RATE)


def patches_named(score: dict) -> list[str]:
    """The patches the score's instruments name, in order, once each."""
    found: list[str] = []
    instruments = score.get("instruments")
    for inst in instruments.values() if isinstance(instruments, dict) else []:
        name = inst.get("patch") if isinstance(inst, dict) else None
        if isinstance(name, str) and name not in found:
            found.append(name)
    return found


def _instrument(value: Any, where: str, patches: dict[str, dict]) -> dict:
    """An instrument checked: its synth layer (patch merged) and its own `ring` and `velocity`."""
    if not isinstance(value, dict):
        raise SoundError(where, "must be an object")
    own = {k: value[k] for k in ("ring", "velocity") if k in value}
    for key, item in own.items():
        INSTRUMENT_KEYS[key](item, f"{where}.{key}")
    layer = sound_synth.merge_patch({k: v for k, v in value.items() if k not in own}, where, patches)
    pitched = "pitch" in layer
    probe = layer if pitched or layer.get("source") == "noise" else {**layer, "pitch": 440.0}
    sound_synth.validate_layer(probe, where)
    return {"layer": layer, "pitched": pitched, "ring": own.get("ring", 0.0), "velocity": own.get("velocity", [1.0])}


def _with_pitch(pitch: Any, freq: float) -> Any:
    """The instrument's pitch moved to `freq`: a number becomes it; a curve keeps its shape, its
    `from` at `freq` (a slide down to a kick's thud stays a slide)."""
    if isinstance(pitch, dict):
        ratio = freq / float(pitch["from"])
        return {**pitch, "from": freq, "to": float(pitch.get("to", pitch["from"])) * ratio}
    return freq


def _parse_step(step: str, where: str) -> list[float] | str:
    """A step's notes' frequencies, or "." "-" "x"."""
    if step in (".", "-", "x"):
        return step
    try:
        return [hz(n) for n in step.split("+")]
    except ValueError:
        raise SoundError(where, f"{step!r} is not a step (a note such as D4, F#3 or Bb2, a chord D3+F3+A3, "
                                "x, . or -)") from None


def validate(score: Any, patches: dict[str, dict] | None = None) -> dict:
    """The score checked, its instruments' patches merged in. Raises SoundError naming the key."""
    patches = patches or {}
    sound_synth._keys(score, "", SCORE, ("version", "tempo", "beats", "bars", "instruments", "patterns",
                                         "layers", "notes"))
    out = copy.deepcopy(score)
    if not isinstance(score["instruments"], dict) or not score["instruments"]:
        raise SoundError("instruments", "must be an object of at least one instrument")
    instruments = {}
    for name, inst in score["instruments"].items():
        if not NAME.match(name):
            raise SoundError(f"instruments.{name}", "an instrument's name is lower case, digits and _")
        instruments[name] = _instrument(inst, f"instruments.{name}", patches)
    out["instruments"] = instruments
    patterns = score["patterns"]
    if not isinstance(patterns, dict) or not patterns:
        raise SoundError("patterns", "must be an object of at least one pattern")
    parsed: dict[str, dict[str, list]] = {}
    for name, pattern in patterns.items():
        where = f"patterns.{name}"
        if not isinstance(pattern, dict) or not pattern:
            raise SoundError(where, "must be an object of lines, an instrument's name to its steps")
        parsed[name] = {}
        for inst, line in pattern.items():
            at = f"{where}.{inst}"
            if inst not in instruments:
                raise SoundError(at, f"no instrument {inst!r} ({', '.join(instruments)})")
            if not isinstance(line, str):
                raise SoundError(at, "must be a line of steps")
            steps = tokens(line)
            if len(steps) not in STEPS:
                raise SoundError(at, f"has {len(steps)} steps; a bar has {', '.join(map(str, STEPS))}")
            parsed[name][inst] = [_parse_step(s, at) for s in steps]
            for s in parsed[name][inst]:
                if s == "x" and not instruments[inst]["pitched"] and instruments[inst]["layer"]["source"] != "noise":
                    raise SoundError(at, f"x plays {inst}'s own pitch, and it has none (give it a pitch or a note)")
                if isinstance(s, list) and instruments[inst]["layer"]["source"] == "noise" \
                        and instruments[inst]["layer"].get("color", "white") == "white":
                    raise SoundError(at, f"{inst} is white noise, which has no pitch: play it with x")
    out["patterns"] = parsed
    layers = score["layers"]
    if not isinstance(layers, list) or not 1 <= len(layers) <= LAYERS_MOST:
        raise SoundError("layers", f"must be a list of 1 to {LAYERS_MOST} layers (MusicTrack.LAYERS_MOST)")
    ids: set[str] = set()
    for i, layer in enumerate(layers):
        where = f"layers[{i}]"
        LAYER(layer, where)
        if layer["id"] in ids:
            raise SoundError(f"{where}.id", f"{layer['id']} is another layer's id too")
        ids.add(layer["id"])
        play = layer["play"]
        if not isinstance(play, list) or len(play) != score["bars"]:
            raise SoundError(f"{where}.play", f"must name {score['bars']} patterns, one a bar (bars), "
                                              f"not {len(play) if isinstance(play, list) else play!r}")
        for j, name in enumerate(play):
            if name not in parsed:
                raise SoundError(f"{where}.play[{j}]", f"no pattern {name!r}")
        events = _events(out, layer)
        if not events:
            raise SoundError(f"{where}.play", "plays no note")
        longest = max(e["seconds"] + instruments[e["inst"]]["ring"] for e in events)
        if longest * RATE > loop_samples(score):
            raise SoundError(where, f"a note rings {longest:.2f} s, longer than the loop; shorten its ring or hold")
    return out


def _events(score: dict, layer: dict) -> list[dict]:
    """The notes of a layer of a validated score, in order: each its instrument, its start and
    held seconds, its frequencies (None for x), its level and its key (where in which pattern, for
    its seed). A hold with no note before it in the loop is an error."""
    bar = score["beats"] * 60.0 / score["tempo"]
    events: list[dict] = []
    open_note: dict[str, dict] = {}
    for b, name in enumerate(layer["play"]):
        for inst in [i for i in open_note if i not in score["patterns"][name]]:
            del open_note[inst]  # a bar with no line for it rests it
        for inst, steps in score["patterns"][name].items():
            step = bar / len(steps)
            velocity = score["instruments"][inst]["velocity"]
            for k, s in enumerate(steps):
                if s == "-":
                    note = open_note.get(inst)
                    if note is None:
                        raise SoundError(f"patterns.{name}.{inst}", f"step {k + 1} holds no note (a hold "
                                                                     "at the layer's start or after a rest)")
                    note["seconds"] += step
                    continue
                if s == ".":
                    open_note.pop(inst, None)
                    continue
                note = {"inst": inst, "start": b * bar + k * step, "seconds": step,
                        "freqs": None if s == "x" else s, "level": velocity[k % len(velocity)],
                        "key": f"{name}/{inst}/{k}"}
                events.append(note)
                open_note[inst] = note
    return events


def _note_layer(inst: dict, freq: float | None) -> dict:
    layer = copy.deepcopy(inst["layer"])
    if freq is not None:
        layer["pitch"] = _with_pitch(layer.get("pitch", freq), freq)
    return layer


def render_layer(score: dict, index: int) -> list[float]:
    """Layer `index` of a validated score (`validate`'s result): one loop, exactly
    `loop_samples(score)` long, seamless round its end."""
    layer = score["layers"][index]
    n = loop_samples(score)
    buf = [0.0] * n
    cache: dict[tuple, list[float]] = {}
    for event in _events(score, layer):
        inst = score["instruments"][event["inst"]]
        size = round((event["seconds"] + inst["ring"]) * RATE)
        start = round(event["start"] * RATE)
        for c, freq in enumerate(event["freqs"] or [None]):
            # A pattern played again plays the same notes: its noise is the same, and it is rendered once.
            key = (event["inst"], event["key"], c, size)
            if key not in cache:
                note = _note_layer(inst, freq)
                cache[key] = sound_synth.render_layer(note, size, zlib.crc32(f"{layer['id']}/{event['key']}/{c}".encode()))
            level = event["level"]
            samples = cache[key]
            first = min(size, n - start)
            for j in range(first):
                buf[start + j] += samples[j] * level
            for j in range(first, size):  # past the loop's end: round to its start
                buf[(start + j) % n] += samples[j] * level
    gain = 10.0 ** (layer.get("gain", 0.0) / 20.0)
    fx = score.get("fx", {})
    if fx:
        buf = sound_synth.apply_fx(buf + buf, fx)[n:]
    return [v * gain for v in buf]


def render(score: dict) -> dict[str, list[float]]:
    """Every layer of a validated score, by its id, in the score's order."""
    return {layer["id"]: render_layer(score, i) for i, layer in enumerate(score["layers"])}


def mixed(layers: list[list[float]]) -> list[float]:
    """The layers played together."""
    return [math.fsum(values) for values in zip(*layers)] if layers else []

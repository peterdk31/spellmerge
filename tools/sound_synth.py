# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The synth: a sound recipe into samples (sound plan AU2, docs/milestones/sound.md, sections 1-2).

A recipe (`<id>.sound.json`) is data and this is the only code. `validate(recipe, patches)` checks
every key and number and returns the recipe with its patches merged in; `render(recipe, variant)`
renders one variant at 44.1 kHz mono, full scale 1.0. The bake (tools/sound.py) places its
loudness, measures it and encodes it.

A layer is a source (`sine`, `triangle`, `saw`, `square`, `noise`, `fm`, `partials`) shaped by an
amplitude envelope, a pitch curve, a filter, `drive`, `crush`, `gain`, `start` and `length`.
Layers are summed, then the sound's `fx` (reverb, then a low pass). Every layer starts and ends
on a ramp of at least `RAMP` seconds, so nothing clicks. A `held` sound is rendered with a tail
that is crossfaded over its start, so it loops with no seam.

Standard library only (`math`, `random.Random(seed)`).
"""

from __future__ import annotations

import copy
import math
import random
from typing import Any, Callable

RATE = 44100
# The synth's version: raised by hand whenever a change here changes what a recipe sounds like.
# It is in every recipe's hash, so the hash test then names every sound to rebake.
GENERATOR = 1
RAMP = 0.002  # the shortest fade at a layer's start and end, in seconds
KINDS = ("sfx", "held", "ui")
SOURCES = ("sine", "triangle", "saw", "square", "noise", "fm", "partials")
SHAPES = ("flat", "arch", "perc", "swell")
CURVES = ("linear", "exp", "arch")
FILTERS = ("low", "high", "band")
UI_SECONDS = 0.15
HELD_TAIL = 0.25  # a held sound's tail, folded over its start, as a share of its seconds
HELD_TAIL_MAX = 1.0
REVERB_TAIL = 0.5  # seconds of reverb tail a one-shot gets for each unit of `size`


class SoundError(ValueError):
    """A recipe that cannot be rendered: `where` is the key's path, `message` what is wrong."""

    def __init__(self, where: str, message: str) -> None:
        super().__init__(f"{where}: {message}" if where else message)
        self.where = where
        self.message = message


# --- The schema --------------------------------------------------------------------------------
# A check is a function (value, where) -> None that raises SoundError.

Check = Callable[[Any, str], None]


def _number(lo: float, hi: float, whole: bool = False) -> Check:
    def check(value: Any, where: str) -> None:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or (whole and not isinstance(value, int)):
            raise SoundError(where, f"must be {'a whole number' if whole else 'a number'}, not {value!r}")
        if not lo <= value <= hi:
            raise SoundError(where, f"{value} is out of range ({lo} to {hi})")
    return check


def _choice(options: tuple[str, ...]) -> Check:
    def check(value: Any, where: str) -> None:
        if value not in options:
            raise SoundError(where, f"{value!r} is not one of {', '.join(options)}")
    return check


def _text(value: Any, where: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise SoundError(where, "must be words")


def _keys(value: Any, where: str, known: dict[str, Check], required: tuple[str, ...] = ()) -> None:
    if not isinstance(value, dict):
        raise SoundError(where, "must be an object")
    for key, item in value.items():
        if key not in known:
            raise SoundError(f"{where}.{key}" if where else key,
                             f"unknown key (known here: {', '.join(sorted(known))})")
        known[key](item, f"{where}.{key}" if where else key)
    for key in required:
        if key not in value:
            raise SoundError(f"{where}.{key}" if where else key, "is missing")


def _object(known: dict[str, Check], required: tuple[str, ...] = ()) -> Check:
    return lambda value, where: _keys(value, where, known, required)


def _curve(lo: float, hi: float, default: str = "exp") -> Check:
    """A number, or {"from", "to", "curve"}: a value that moves over the layer's length (`curve`
    `default` when it is left out)."""
    number = _number(lo, hi)
    shape = _object({"from": number, "to": number, "curve": _choice(CURVES)}, ("from",))

    def check(value: Any, where: str) -> None:
        if isinstance(value, dict):
            shape(value, where)
            if value.get("curve", default) != "linear" and (value["from"] <= 0 or value.get("to", value["from"]) <= 0):
                raise SoundError(where, "an exp or arch curve needs from and to above 0 (or curve: linear)")
        else:
            number(value, where)
    return check


HZ = _curve(20.0, 20000.0)
AMP = _object({"attack": _number(0.0, 10.0), "decay": _number(0.0, 10.0), "sustain": _number(0.0, 1.0),
               "release": _number(0.0, 10.0), "shape": _choice(SHAPES), "power": _number(0.1, 8.0)})
FILTER = _object({"type": _choice(FILTERS), "from": _number(20.0, 20000.0), "to": _number(20.0, 20000.0),
                  "curve": _choice(CURVES), "q": _number(0.3, 30.0)}, ("type", "from"))
PARTIAL = _object({"ratio": _number(0.1, 32.0), "gain": _number(-60.0, 0.0), "decay": _number(0.005, 20.0)},
                  ("ratio",))


def _partials(value: Any, where: str) -> None:
    if not isinstance(value, list) or not 1 <= len(value) <= 32:
        raise SoundError(where, "must be a list of 1 to 32 partials")
    for i, partial in enumerate(value):
        PARTIAL(partial, f"{where}[{i}]")


# Keys every layer may have, then the keys of each source.
LAYER = {"source": _choice(SOURCES), "amp": AMP, "filter": FILTER, "drive": _number(0.0, 30.0),
         "crush": _number(2, 16, whole=True), "start": _number(0.0, 60.0), "length": _number(0.005, 60.0),
         "gain": _number(-60.0, 24.0)}
SOURCE_KEYS: dict[str, dict[str, Check]] = {
    "sine": {"pitch": HZ},
    "triangle": {"pitch": HZ},
    "saw": {"pitch": HZ},
    "square": {"pitch": HZ, "duty": _number(0.05, 0.95)},
    "noise": {"color": _choice(("white", "stepped")), "pitch": HZ},
    "fm": {"pitch": HZ, "ratio": _number(0.1, 16.0), "index": _curve(0.0, 30.0, "linear")},
    "partials": {"pitch": HZ, "partials": _partials},
}
SOURCE_NEEDS = {"sine": ("pitch",), "triangle": ("pitch",), "saw": ("pitch",), "square": ("pitch",),
                "noise": (), "fm": ("pitch", "ratio", "index"), "partials": ("pitch", "partials")}

SOUND = {"version": _number(1, 1, whole=True), "kind": _choice(KINDS), "family": _text,
         "seconds": _number(0.01, 120.0), "variants": _number(1, 16, whole=True),
         "vary": _object({"pitch": _number(0.0, 0.5), "time": _number(0.0, 0.5),
                          "seed": _number(0, 2 ** 31, whole=True)}),
         "layers": lambda value, where: None,  # checked one by one below
         "fx": _object({"reverb": _object({"mix": _number(0.0, 1.0), "size": _number(0.1, 3.0)}, ("mix",)),
                        "lowpass": _number(200.0, 20000.0)}),
         "gain": _number(-24.0, 24.0), "notes": _text}


def _merge(base: dict, top: dict) -> dict:
    """`top`'s keys over `base`'s, objects merged key by key."""
    out = copy.deepcopy(base)
    for key, value in top.items():
        out[key] = _merge(out[key], value) if isinstance(value, dict) and isinstance(out.get(key), dict) else copy.deepcopy(value)
    return out


def patches_named(recipe: dict) -> list[str]:
    """The names of the patches the recipe's layers name, in order, once each."""
    found: list[str] = []
    for layer in recipe.get("layers", []) if isinstance(recipe.get("layers"), list) else []:
        name = layer.get("patch") if isinstance(layer, dict) else None
        if isinstance(name, str) and name not in found:
            found.append(name)
    return found


def check_patch(patch: Any, where: str) -> None:
    """A patch file: {"version": 1, "layer": {...}, "notes": "..."}; its layer is one a recipe
    builds on, so it may leave out what the recipe gives (its source's needs are checked on the
    merged layer)."""
    _keys(patch, where, {"version": _number(1, 1, whole=True), "layer": lambda v, w: None, "notes": _text},
          ("version", "layer", "notes"))
    if not isinstance(patch["layer"], dict) or "patch" in patch["layer"]:
        raise SoundError(f"{where}.layer", "must be a layer object that names no patch")


def validate(recipe: Any, patches: dict[str, dict] | None = None) -> dict:
    """The recipe checked, with every layer's patch merged in (the patch's layer under the
    recipe's keys). `patches` is a patch's name to its file's object. Raises SoundError."""
    patches = patches or {}
    _keys(recipe, "", SOUND, ("version", "kind", "family", "seconds", "layers", "notes"))
    layers = recipe["layers"]
    if not isinstance(layers, list) or not 1 <= len(layers) <= 16:
        raise SoundError("layers", "must be a list of 1 to 16 layers")
    out = copy.deepcopy(recipe)
    out["layers"] = []
    for i, layer in enumerate(layers):
        where = f"layers[{i}]"
        if not isinstance(layer, dict):
            raise SoundError(where, "must be an object")
        if "patch" in layer:
            name = layer["patch"]
            if not isinstance(name, str) or name not in patches:
                raise SoundError(f"{where}.patch", f"no patch {name!r} (audio/patches/{name}.patch.json)")
            check_patch(patches[name], f"patch {name}")
            layer = _merge(patches[name]["layer"], {k: v for k, v in layer.items() if k != "patch"})
        source = layer.get("source")
        _choice(SOURCES)(source, f"{where}.source")
        _keys(layer, where, {**LAYER, **SOURCE_KEYS[source]}, ("source",) + SOURCE_NEEDS[source])
        amp = layer.get("amp", {})
        if any(k in amp for k in ("decay", "sustain", "release")) and ("shape" in amp or "power" in amp):
            raise SoundError(f"{where}.amp", "a shape takes attack and power; decay, sustain and release are an ADSR's")
        if source == "noise" and "pitch" in layer and layer.get("color", "white") == "white":
            raise SoundError(f"{where}.pitch", "white noise has no pitch (a stepped noise's pitch is its rate)")
        out["layers"].append(layer)
    kind = recipe["kind"]
    if kind == "held":
        if recipe.get("variants", 1) != 1:
            raise SoundError("variants", "a held sound has one variant (a loop that changes file mid-loop clicks)")
        if recipe.get("vary"):
            raise SoundError("vary", "a held sound has one variant, so nothing to vary")
    if kind == "ui":
        if recipe["seconds"] * (1.0 + recipe.get("vary", {}).get("time", 0.0)) > UI_SECONDS:
            raise SoundError("seconds", f"a ui sound is under {UI_SECONDS} s, its longest variant too")
        if "reverb" in recipe.get("fx", {}):
            raise SoundError("fx.reverb", "a ui sound is never reverberant")
    for i, layer in enumerate(out["layers"]):
        if layer.get("start", 0.0) >= recipe["seconds"]:
            raise SoundError(f"layers[{i}].start", "starts after the sound ends")
    return out


# --- Rendering ---------------------------------------------------------------------------------

def _along(value: Any, u: float, default_curve: str) -> float:
    """A number, or a curve's value a share `u` (0 to 1) of the way along it."""
    if not isinstance(value, dict):
        return float(value)
    start = float(value["from"])
    end = float(value.get("to", start))
    curve = value.get("curve", default_curve)
    if curve == "linear":
        return start + (end - start) * u
    if curve == "arch":
        return start * (end / start) ** math.sin(math.pi * u)
    return start * (end / start) ** u


def _envelope(amp: dict, n: int, time_scale: float) -> list[float]:
    attack = amp.get("attack", 0.0) * time_scale * RATE
    ramp = max(RAMP * RATE, 1.0)
    out = [0.0] * n
    if "shape" in amp or not any(k in amp for k in ("decay", "sustain", "release")):
        shape = amp.get("shape", "flat")
        power = amp.get("power", 1.0)
        for i in range(n):
            u = i / max(n - 1, 1)
            if shape == "arch":
                v = math.sin(math.pi * u) ** power
            elif shape == "perc":
                v = (1.0 - u) ** power
            elif shape == "swell":
                v = u ** power
            else:
                v = 1.0
            if attack > 0.0 and i < attack:
                v *= 0.5 - 0.5 * math.cos(math.pi * i / attack)
            out[i] = v
    else:
        decay = amp.get("decay", 0.0) * time_scale * RATE
        sustain = amp.get("sustain", 1.0)
        release = amp.get("release", 0.0) * time_scale * RATE
        for i in range(n):
            if i < attack:
                v = i / attack
            elif i < attack + decay:
                v = 1.0 - (1.0 - sustain) * (i - attack) / decay
            else:
                v = sustain
            left = n - 1 - i
            if release > 0.0 and left < release:
                v *= left / release
            out[i] = v
    for i in range(min(int(ramp) + 1, n)):  # the ramps no sound goes without
        w = 0.5 - 0.5 * math.cos(math.pi * min(i / ramp, 1.0))
        out[i] *= w
        out[n - 1 - i] *= w
    return out


def _blep(t: float, dt: float) -> float:
    """PolyBLEP: the step's correction near a saw's or square's jump, so they alias little."""
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def _snap(f: float, period: int) -> float:
    """`f` moved to the nearest frequency with a whole number of cycles in `period` samples (a
    held loop's length), so a steady tone ends in the phase it starts in; 0 leaves it."""
    if period <= 0:
        return f
    return max(1, round(f * period / RATE)) * RATE / period


def _source(layer: dict, n: int, pitch_scale: float, time_scale: float, rng: random.Random, period: int) -> list[float]:
    """The layer's raw source. In a held loop (`period` its length) a steady pitch, its
    partials and its FM modulator are snapped to whole cycles of the loop."""
    source = layer["source"]
    out = [0.0] * n
    last = max(n - 1, 1)
    if source == "noise":
        if layer.get("color", "white") == "white":
            return [rng.uniform(-1.0, 1.0) for _ in range(n)]
        phase, held = 1.0, 0.0
        for i in range(n):
            phase += _along(layer.get("pitch", 1000.0), i / last, "exp") * pitch_scale / RATE
            if phase >= 1.0:
                phase -= math.floor(phase)
                held = rng.uniform(-1.0, 1.0)
            out[i] = held
        return out
    pitch = layer["pitch"]
    steady = not isinstance(pitch, dict)
    if source == "partials":
        partials = layer["partials"]
        base = [_along(pitch, i / last, "exp") * pitch_scale for i in range(n)]
        for partial in partials:
            ratio = partial["ratio"]
            level = 10.0 ** (partial.get("gain", 0.0) / 20.0)
            rate = 6.907755 / (partial.get("decay", 1.0) * time_scale * RATE)  # -60 dB at `decay`
            phase = rng.random()
            fixed = _snap(base[0] * ratio, period) if steady else 0.0
            for i in range(n):
                f = fixed or base[i] * ratio
                if f < RATE * 0.45:
                    out[i] += level * math.exp(-rate * i) * math.sin(2.0 * math.pi * phase)
                phase += f / RATE
        return out
    phase = 0.0
    mod_phase = 0.0
    duty = layer.get("duty", 0.5)
    fixed = _snap(float(pitch) * pitch_scale, period) if steady else 0.0
    mod_dt = _snap(fixed * layer.get("ratio", 1.0), period) / RATE if steady else 0.0
    for i in range(n):
        u = i / last
        f = fixed or _along(pitch, u, "exp") * pitch_scale
        dt = f / RATE
        if source == "sine":
            v = math.sin(2.0 * math.pi * phase)
        elif source == "triangle":
            v = 4.0 * abs(phase - 0.5) - 1.0
        elif source == "saw":
            v = 2.0 * phase - 1.0 - _blep(phase, dt)
        elif source == "square":
            v = (1.0 if phase < duty else -1.0) + _blep(phase, dt) - _blep((phase - duty) % 1.0, dt)
        else:  # fm
            index = _along(layer["index"], u, "linear")
            v = math.sin(2.0 * math.pi * phase + index * math.sin(2.0 * math.pi * mod_phase))
            mod_phase = (mod_phase + (mod_dt or dt * layer["ratio"])) % 1.0
        out[i] = v
        phase = (phase + dt) % 1.0
    return out


def _filter(x: list[float], kind: str, cutoff: Callable[[float], float], q: float) -> list[float]:
    """A state-variable filter (the trapezoidal one, stable as its cutoff sweeps); a band pass
    has unity gain at its centre."""
    k = 1.0 / q
    s1 = s2 = 0.0
    last = max(len(x) - 1, 1)
    out = [0.0] * len(x)
    for i, v0 in enumerate(x):
        g = math.tan(math.pi * min(cutoff(i / last), RATE * 0.45) / RATE)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = v0 - s2
        v1 = a1 * s1 + a2 * v3
        v2 = s2 + a2 * s1 + a3 * v3
        s1 = 2.0 * v1 - s1
        s2 = 2.0 * v2 - s2
        out[i] = v2 if kind == "low" else k * v1 if kind == "band" else v0 - k * v1 - v2
    return out


def _layer(layer: dict, n: int, pitch_scale: float, time_scale: float, rng: random.Random,
           period: int = 0) -> list[float]:
    x = _source(layer, n, pitch_scale, time_scale, rng, period)
    if "filter" in layer:
        f = layer["filter"]
        sweep = {"from": f["from"], "to": f.get("to", f["from"]), "curve": f.get("curve", "exp")}
        x = _filter(x, f["type"], lambda u: _along(sweep, u, "exp") * pitch_scale, f.get("q", 0.707))
    drive = layer.get("drive", 0.0)
    if drive > 0.0:
        norm = math.tanh(drive)
        x = [math.tanh(drive * v) / norm for v in x]
    if "crush" in layer:
        steps = 2 ** (layer["crush"] - 1)
        x = [round(v * steps) / steps for v in x]
    level = 10.0 ** (layer.get("gain", 0.0) / 20.0)
    env = _envelope(layer.get("amp", {}), n, time_scale)
    return [v * e * level for v, e in zip(x, env)]


COMBS = (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
ALLPASSES = (556, 441, 341, 225)


def _reverb(x: list[float], mix: float, size: float) -> list[float]:
    """A small room: eight damped feedback combs in parallel, then four all-passes (Schroeder's
    and Freeverb's shape), its delays and feedback grown with `size`."""
    scale = math.sqrt(size)
    feedback = min(0.7 + 0.12 * size, 0.97)
    damp = 0.25
    n = len(x)
    wet = [0.0] * n
    for length in COMBS:
        size_n = max(1, int(length * scale))
        line = [0.0] * size_n
        pos = 0
        store = 0.0
        for i in range(n):
            y = line[pos]
            store = y * (1.0 - damp) + store * damp
            line[pos] = x[i] + store * feedback
            pos = pos + 1 if pos + 1 < size_n else 0
            wet[i] += y
    for length in ALLPASSES:
        size_n = max(1, int(length * scale))
        line = [0.0] * size_n
        pos = 0
        for i in range(n):
            y = line[pos]
            line[pos] = wet[i] + y * 0.5
            wet[i] = y - wet[i]
            pos = pos + 1 if pos + 1 < size_n else 0
    # The wet sound is scaled to the dry sound's energy, so `mix` is the share of what is heard,
    # whatever the room's size and however a tone happens to sit on the room's resonances.
    dry_energy = sum(v * v for v in x)
    wet_energy = sum(v * v for v in wet)
    gain = math.sqrt(dry_energy / wet_energy) if wet_energy > 0.0 else 0.0
    return [d * (1.0 - mix) + w * gain * mix for d, w in zip(x, wet)]


def variant_scales(recipe: dict, variant: int) -> tuple[float, float, int]:
    """Variant `variant`'s (from 1) pitch and time scales and noise seed: its own, within the
    recipe's `vary`. Variant 1 of a recipe with no `vary` is the recipe as written."""
    vary = recipe.get("vary", {})
    seed = vary.get("seed", 0) * 1000 + variant
    rng = random.Random(seed)
    pitch = 1.0 + vary.get("pitch", 0.0) * rng.uniform(-1.0, 1.0)
    time = 1.0 + vary.get("time", 0.0) * rng.uniform(-1.0, 1.0)
    return pitch, time, seed


def length_of(recipe: dict, time_scale: float = 1.0) -> int:
    """How many samples a variant's file has."""
    seconds = recipe["seconds"] * time_scale
    if recipe["kind"] != "held" and "reverb" in recipe.get("fx", {}):
        seconds += REVERB_TAIL * recipe["fx"]["reverb"].get("size", 1.0)
    return max(1, round(seconds * RATE))


def render(recipe: dict, variant: int = 1) -> list[float]:
    """One variant of a validated recipe (`validate`'s result), unplaced in level."""
    pitch_scale, time_scale, seed = variant_scales(recipe, variant)
    rng = random.Random(seed)
    n = length_of(recipe, time_scale)
    tail = 0
    if recipe["kind"] == "held":
        tail = round(min(HELD_TAIL * recipe["seconds"], HELD_TAIL_MAX) * RATE)
    total = n + tail
    mix = [0.0] * total
    for layer in recipe["layers"]:
        start = round(layer.get("start", 0.0) * time_scale * RATE)
        if "length" in layer:
            size = round(layer["length"] * time_scale * RATE)
        else:
            size = round(recipe["seconds"] * time_scale * RATE) + tail - start
        size = max(1, min(size, total - start))
        for i, v in enumerate(_layer(layer, size, pitch_scale, time_scale, rng, n if tail else 0)):
            mix[start + i] += v
    fx = recipe.get("fx", {})
    if "reverb" in fx:
        mix = _reverb(mix, fx["reverb"]["mix"], fx["reverb"].get("size", 1.0))
    if "lowpass" in fx:
        mix = _filter(mix, "low", lambda u: fx["lowpass"], 0.707)
    if recipe["kind"] == "held":
        return _fold(mix, n, tail)
    if "reverb" in fx:  # the tail fades out over its last part, so a long room is never cut
        fade = round(REVERB_TAIL * fx["reverb"].get("size", 1.0) * 0.6 * RATE)
        for i in range(min(fade, n)):
            mix[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade)
    ramp = round(RAMP * RATE)
    for i in range(min(ramp, n)):
        w = i / ramp
        mix[i] *= w
        mix[n - 1 - i] *= w
    return mix


def _fold(x: list[float], n: int, tail: int) -> list[float]:
    """A loop of `n` samples: the tail past `n` crossfaded over the start, so the end runs on into
    the start with no step. The fade keeps the power steady for how alike the two parts are
    (equal power for unlike noise, near equal gain for a tone that runs on in phase)."""
    out = x[:n]
    tail = min(tail, n)
    if tail <= 0:
        return out
    a, b = x[:tail], x[n:n + tail]
    norm = math.sqrt(sum(v * v for v in a) * sum(v * v for v in b))
    alike = max(-0.5, sum(p * q for p, q in zip(a, b)) / norm) if norm > 0.0 else 0.0
    for i in range(tail):
        angle = 0.5 * math.pi * i / tail
        fade_in, fade_out = math.sin(angle), math.cos(angle)
        gain = 1.0 / math.sqrt(1.0 + 2.0 * alike * fade_in * fade_out)
        out[i] = (a[i] * fade_in + b[i] * fade_out) * gain
    return out

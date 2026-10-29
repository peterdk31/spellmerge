# Spells

## Purpose

The **cards** players put in their staffs, in any order, and that a staff reads left to right (docs/milestones/M2-staffs.md, "Reading a staff"): **carriers** (`forms/`: bolt, beam, nova, rune, orbit, dash), what leaves the caster and ends a group; **modifiers** (`modifiers/`: split, pierce, homing, chain, bigger, faster) and **infusions** (`elements/`: fire, frost, storm, void, lightning), which change the next carrier (or land on the caster when none follows); **triggers** (`triggers/`: on hit, on expire, timer), which make the group read after the next carrier its payload; and **multicast** (`multicasts/`), which pulls more carriers into one group. Every arrangement is legal; there is no budget. Few cards, many combinations: this is the game's first pillar (docs/DESIGN.md). The class names (`FormBase`, `ElementBase`) and kinds (`form`, `element`) stay from the first design.

**Built in M2**, reworked by the staffs pivot (docs/milestones/M2-staffs.md). The new cards come one PR each (staffs phase C). The card icons are placeholders until the art pass.

## Contract

- A card is one folder, named like its `id`, holding a `.tres` on one of the five classes in `core/base/` (`FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`, `MulticastBase`, all on `SpellComponent`), a 16×16 icon, and optionally a `.gd` or an SFX. **Most components need no script:** the fields below can express them. Write a `.gd` only for behaviour no field can say.
- Content is discovered by folder through `core/registry`. Do not edit any central list.
- Components depend only on `core/`. They never call other areas; they talk through `core/` events. Every effect takes a player index 0–3; nothing assumes a single player.
- Players, bots and the HUD never read a component's fields. They call `Spells` (`compile_staff`, `install_staff`, `cast_staff`, `staff_view`) and answer to its events; `tests/core/test_spell_field_reads.gd` fails if a script outside `content/spells/`, `core/base/` and `core/spells/` reads one.
- Spawn shots only through the projectile manager (`core/projectiles`); no per-frame allocations.
- Names are original. No names from other works (write Fireball, not Hadouken).

### Fields every component has

`id` (equals the folder name, unique across all four kinds), `display_name`, `demo` (true if it is in the free web demo; leave it false for new content), `icon` (16×16, listed in `art/manifest.json`) and `complexity`.

### Name words

Every card has `name_words` (a `PackedStringArray`, the plainest word first), the words it brings to the generated name of a cast (`core/spells/spell_namer.gd`; `tests/core/test_spell_names.gd` fails on a card without them). A carrier: its noun ("Bolt", then "Dart"). An infusion: a prefix fused with the other infusions' ("Frost" → "Firefrost"). A modifier: an adjective ("Seeking"). A trigger: the word before its payload ("Sudden" → "of Sudden Novas"). A multicast: a hyphenated prefix ("Twice" → "Twice-Bolt"). Original words only, and make them fun to read out loud.

### Fields and ranges per kind

The script of each class documents every field, and its `ranges()` holds the allowed range (both ends included). `range_problems()` lists what is outside; the validator reports the same.

| Kind | Fields (range) |
| --- | --- |
| Form (`FormBase`, a carrier) | `base_damage` 1–200, `mana_cost` 0–100, `cooldown` 0.05–10 s (what the carrier adds to its staff's delay), `speed` 0–2000 px/s, `lifetime` 0.05–20 s, `radius` 1–64 px, `shots` 1–24, `spread` 0–360°, `motion` (STRAIGHT, STILL, ORBIT, RAY, DASH, and the staffs carriers TELEPORT to FAMILIAR, each run by its kit; a returning shot is the `return` modifier, not a motion), `pierce` 0–16, `orbit_radius` 0–256 px (ORBIT), `ray_length` 0–1024 px (how far a RAY, FISSURE or RAIN reaches; how far a DASH or TELEPORT moves its caster, whatever its speed), `cast_look` and `impact_look` (the cast flash on the player and the flare where its shot ends: dictionaries with `seconds`, `size`, `stretch`, `tall`, `aim`, `grow`, `ring`; see `gameplay/feel`; empty gets the plain flash and spark) |
| Element (`ElementBase`) | `status_id` (a status combat knows: burn, chill, shock, hex, static), `status_duration` 0–30 s, `status_strength` 0–100, `damage_scale` 0.1–4, `tint` (a palette colour from docs/STYLE.md; the validator does not check it, reviewers do), `look_layer` 0–14 (see "The look of a shot" below) |
| Modifier (`ModifierBase`) | `damage_mult` 0.1–4, `speed_mult` 0.1–4, `radius_mult` 0.25–4, `cooldown_mult` 0.1–4, `mana_mult` 0.1–4, `shot_mult` 1–8, `extra_pierce` 0–8, `behaviour` (NONE, HOMING, CHAIN, the staffs behaviours SHIELD to ARC, and POSSESS (actors G9: every actor the carrier hits is possessed by the caster's controller for `behaviour_strength` seconds; it drives the oldest and puppets copy it on the others; `possess_requested`, the rule in `gameplay/actor/possession.gd`), each documented in `modifier_base.gd` with what its strength means), `behaviour_strength` 0–256, `behaviour_reach` 0–360 (how far HOMING looks and ARC zaps, required for both), `look_layer` 0–14, `spread_mult` 0–4 (factor on the staff's spread for the next carrier: below 1 truer, above 1 wilder), `lifetime_mult` 0.1–4 (factor on the carrier's life; slow) |
| Trigger (`TriggerBase`) | `event` (HIT, EXPIRE, TIMER, and BLOCK to ALLY), `interval` 0–10 s (TIMER); a trigger fires every time its event happens (no fire count) |
| Multicast (`MulticastBase`) | `extra_draws` 0–4, `mode` (TOGETHER, SCATTER, BURST), `repeats` 1–8, `repeat_interval` 0–1 s, `mana_cost` 0–100, `cooldown` 0–2 s |

Multipliers multiply the carrier's numbers and adds are added, in slot order. There is no cast time: a cast's delay is its staff's delay plus every carrier's cooldown.

### The look of a shot

A shot is drawn by the shot shaders in `core/projectiles/` (core/README.md, "The shot shaders"; in flight `shot_trail.gdshader`, a rune `shot_rune.gdshader`) from its cards (staffs B6a; docs/milestones/M2-staffs.md, "The look of a shot"). Its body stays plain: a small white-hot core shaped by its carrier (a bolt or orbit shot's 3 px cross, a rune's diamond) in the palette ramp of its first infusion's `tint` (a plain shot's in its player's colours), a long tail that cools and frays and bends with the shot's path, a quarter of its pixels in the player's colour, and a soft glow round both. The cards show in what it gives off: every infusion and modifier with a `look_layer` adds a particle style, and the shot keeps a few particles alive (4 + 2 per style, at most 12), each born at a random point of its tail with a style picked at random, so one card is a trickle and many cards a mix. The styles (the `LOOK_*` constants in `core/projectiles/projectile_manager.gd`): 1 embers (fire), 2 frost flecks and a longer tail, 3 gusts and a swaying tail (storm), 4 pulled-in pixels and a dark heart (void), 5 sparks and a jagged tail (lightning), 6 rising motes, 7 glints (bigger), 8 streaks and a longer core (pierce), 9 a burst, 10 orbiting sparks, 11 a weave of the body (homing), 12 glitter, 13 hops (chain), 14 wake (faster). A new card picks one, or 0 for none; an infusion should pick one no other infusion uses, so elements read without colour. Sheets: `tests/screenshots/shot_looks.gd` (still) and `shot_moving_looks.gd` (in flight).

### No budget, engine safeguards only

There is no complexity budget and no build limit: a staff may hold any cards in any order, as many modifiers and as deep payloads as its slots allow, and the compiled numbers are not clamped. `complexity` (1–4) stays on every card as a rough measure of its power (the validator keeps it in range). What stays are the engine safeguards in `core/spells/limits.gd` and the projectile pool, which never change a build. Price a card by its mana and cooldown: a card stronger than its neighbours costs more; one that makes another obsolete needs a rebalance, not an addition.

### Reactions

Element interactions go in `reactions.tres` (a `ReactionTable` of `ReactionRow`s), so a new element needs no change in other components. One row says: a hit of `element_id` on a target with `status_id` does `effect` (BURST, CONSUME, EXTEND or SPREAD) instead of the element's own status. A pair reacts both ways, so it has two rows with the same `reaction_id` (see the eight that ship in pairs: shatter, thaw, flare, kindle, stillness, rift, overload and superconduct; the two rows of a pair may use different effects). `status_id` is the status the target has (`burn`, `chill`, `shock`, `hex`, `static`) and `element_id` the element that hits it. Feel colours and sounds a reaction by its id: add the colour to `reaction_colors` (and, if it should hit harder or softer than 1.0, `reaction_power`) in `gameplay/feel/presets/feel_preset.gd`, and make the sound `reaction_<id>` (`.ogg` under `audio/`; until it exists the reaction is silent). `tests/gameplay/feel/test_feel_reactions.gd` fails when two reaction colours are too close to tell apart and when the number of colours is not the number of reactions it lists, so a new reaction updates that count. `discharge` (lightning's static) is not a row: combat sends it, with a `discharge_arc` for each enemy zapped, and it has a colour and a sound id like the rows.

### The combo row rule

**Every new component comes with at least two combos that work**, each a file of its own in `combos/`, named like the combo's `id` (`combos/<id>.json`, one combo per file, so card PRs never edit the same list). A combo has an `id`, `name`, `does` (plain words), `casts` (`staff`, `cards`: one card id per slot, read as a staff reads them, optional `at` seconds and `player`), `imps` (`[x, y]` or `[x, y, health]` pixels from the caster, who stands at (0, 0) and aims along +x), optional `walls` (`[x, y, width, height]` rects, for cards that meet walls), `seconds` and `checks`. Example: `{"staff": 0, "cards": ["frost", "timer", "rune", "frost", "nova"]}` is a frost rune that drops a frost nova on a timer (docs/milestones/M2-staffs.md, "Reading a staff"). Check kinds: `damaged`, `status`, `status_count`, `lost_at_least`, `keeps_burning`, `reaction`, `max_shots`, `caster_moved`, `blocked`, `killed` (imps). Optional `guard` (true: the caster's own body stands at (0, 0)) and `foes` (`[x, y]`: an enemy bolt cast at the caster from there) let a combo show a shield block. Copy a file from `combos/`. `tests/content/spells/test_combos.gd` casts every combo in the test arena with the real runtime and checks that every component the registry finds is in two of them, so a new combo needs no new test code and a new component no list to edit.

### What a new element still needs outside its folder

These steps are not new files only (the report of #243, the fifth element):

- **A status of its own** (`status_id` that combat does not know): code in `gameplay/combat/combat.gd` (arrays, apply, tick, remove, `REACTING_STATUSES`), a word in `core/spells/spells.gd` and a name in `core/spells/validator.gd`. An element that reuses `burn`, `chill`, `shock`, `hex` or `static` needs none.
- **A look of its own** when no free `look_layer` kind fits: a new `LOOK_*` number in `core/projectiles/projectile_manager.gd` and its branch in `trail_particle` (`core/projectiles/shot_trail.gdshader`) and in `particle` (`core/projectiles/shot_particle.gdshaderinc`, for runes, beams and effects).
- **A colour ramp** if the palette has no free hue: `docs/STYLE.md` and `art/kit/`.
- **A look for its status** on the enemy: `status_looks` in the Feel preset.

## Allowed files

`.tres`, `.gd`, the icon (`.png` or `.svg`), SFX (`.ogg`), plus Godot's `.uid` and `.import` files and `.license` files. Limits: 1 MB per image, 5 MB per `.ogg`, 1 MB for anything else. Typed GDScript only; no banned APIs (see AGENTS.md, hard rules).

## Steps

1. Copy the example folder of the same kind into `forms/`, `elements/`, `modifiers/` or `triggers/` and rename the folder.
2. Edit the `.tres`: `id` (equal to the folder), `display_name`, `complexity` (a rough measure, 1–4) and the numbers. Write a `.gd` only if the behaviour is new.
3. Replace the icon (16×16, palette from docs/STYLE.md) and the optional SFX. List each in an `assets.json` in the component's folder, in the same shape as `art/manifest.json` (`{"assets": [{"path": "content/spells/...", "origin": ..., "author": ..., "license": ...}]}`; for AI also tool and prompt). The validator and the art test read `art/manifest.json`, `audio/manifest.json` and every `assets.json`. Commit the `.uid` and `.import` files Godot creates.
4. If it interacts with other elements, add the rows to `reactions.tres`, then the colour of each new reaction id (and optionally its `reaction_power`) to the Feel preset (see Reactions above).
5. Add its two combo files to `combos/` (the combo test fails until the component is in two).
6. Add the builder description: copy `content/story/lore/components/bolt.json` to `content/story/lore/components/<id>.json` and write one honest line (at most 60 characters; say only what the component really does). Without it the builder shows no description and a debug build warns, but nothing fails.
7. Run the checks below, then open a PR using the template.

## Examples to copy

Each is a `.tres` plus an `icon.svg`, no script.

- **Form: `forms/bolt/`.** `FormBase` with damage 5, mana 5, cooldown 0.35 s, speed 220, one STRAIGHT shot, complexity 1. A beam sets `motion` to RAY and `ray_length`: it lives its `lifetime` (0.3 s), follows its caster and hits every `SpellLimits.BEAM_TICK` (0.15 s), so held fire keeps it on; a nova raises `shots` and `spread`. The dashes (`dash` is Short Dash, `medium_dash`, `long_dash`) move a fixed `ray_length` (48, 80, 128 px) at their `speed`, 2 s delay each.
- **Element: `elements/frost/`.** `ElementBase` with `status_id = &"chill"`, 3 s, strength 40, `damage_scale` 1.0 and a palette `tint`, complexity 1. The reactions with other elements are rows in `reactions.tres`, not fields here.
- **Modifier: `modifiers/split/`.** `ModifierBase` with `shot_mult = 3`, `damage_mult = 0.5`, `mana_mult = 1.5`, complexity 2. A modifier names only the fields it changes and leaves the rest at 1; its cost in damage or mana pays for its power. Homing and chain use `behaviour` and `behaviour_strength`.
- **Trigger: `triggers/on_hit/`.** `TriggerBase` with `event = 0` (HIT), complexity 1. The timer sets `event = 2` and `interval = 0.5`.

## Validate

```sh
tools/check.sh                      # hard rules, on your changes
ci/build/build.sh --quick --tests   # import, smoke test and every unit test, including the validator and the combo test
```

The registry's check in debug builds and `tests/content/spells/test_validators.gd` report problems as rule, file, field and fix (ids, icons, ranges, complexity, reactions). Fix every one. For a gameplay-visible component, add a short GIF or video to the PR.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it create creative, surprising interactions with existing components?
- Is its power in line with its mana and cooldown?
- Does it avoid making another component obsolete?
- Does it come with a combo row that works?

# Spells

## Purpose

The spell components that players assemble into spells: **forms** (bolt, beam, nova, rune, orbit), **elements** (fire, frost, storm, void), **modifiers** (split, pierce, homing, chain, bigger, faster) and **triggers** (on hit, on expire, timer). A spell is built as form → element → up to three modifiers → trigger, and a trigger holds another spell, built from the same slots. Few components, many combinations: this is the game's first pillar (docs/DESIGN.md).

**Built in M2** (Spell system, see docs/milestones/M2-spell-system.md). All four kinds, the validator and the combo test exist since part 15. The component icons are placeholders until the art pass (part 26).

## Contract

- A component is one folder, named like its `id`, holding a `.tres` on one of the four classes in `core/base/` (`FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`, all on `SpellComponent`), a 16×16 icon, and optionally a `.gd` or an SFX. **Most components need no script:** the fields below can express them. Write a `.gd` only for behaviour no field can say.
- Content is discovered by folder through `core/registry`. Do not edit any central list.
- Components depend only on `core/`. They never call other areas; they talk through `core/` events. Every effect takes a player index 0–3; nothing assumes a single player.
- Players, bots and the HUD never read a component's fields. They call `Spells` (compile, cast) and answer to its events; `tests/core/test_spell_field_reads.gd` fails if a script outside `content/spells/`, `core/base/` and `core/spells/` reads one.
- Spawn shots only through the projectile manager (`core/projectiles`); no per-frame allocations.
- Names are original. No names from other works (write Fireball, not Hadouken).

### Fields every component has

`id` (equals the folder name, unique across all four kinds), `display_name`, `demo` (true if it is in the free web demo; leave it false for new content), `icon` (16×16, listed in `art/manifest.json`) and `complexity`.

### Fields and ranges per kind

The script of each class documents every field, and its `ranges()` holds the allowed range (both ends included). `range_problems()` lists what is outside; the validator reports the same.

| Kind | Fields (range) |
| --- | --- |
| Form (`FormBase`) | `base_damage` 1–200, `mana_cost` 0–100, `cooldown` 0.05–10 s, `speed` 0–2000 px/s, `lifetime` 0.05–20 s, `radius` 1–64 px, `shots` 1–24, `spread` 0–360°, `motion` (STRAIGHT, STILL, ORBIT, RAY), `pierce` 0–16, `orbit_radius` 0–256 px (ORBIT), `ray_length` 0–1024 px (RAY) |
| Element (`ElementBase`) | `status_id` (a status combat knows: burn, chill, shock, hex), `status_duration` 0–30 s, `status_strength` 0–100, `damage_scale` 0.1–4, `tint` (a palette colour from docs/STYLE.md; the validator does not check it, reviewers do), `shape` 0–4 (0 the plain sprite, 1 flame, 2 star, 3 zigzag, 4 ring: the silhouette, animation and trail of its shots, drawn by `core/projectiles/shot_core.gdshader`; each element needs a shape of its own so it reads without colour) |
| Modifier (`ModifierBase`) | `damage_mult` 0.1–4, `speed_mult` 0.1–4, `radius_mult` 0.25–4, `cooldown_mult` 0.1–4, `mana_mult` 0.1–4, `shot_mult` 1–8, `extra_pierce` 0–8, `behaviour` (NONE, HOMING, CHAIN), `behaviour_strength` 0–32 (turn rate for homing, jumps for chain) |
| Trigger (`TriggerBase`) | `event` (HIT, EXPIRE, TIMER), `interval` 0–10 s (TIMER), `max_fires` 1–4 |

Multipliers multiply the form's numbers and adds are added, in slot order. There is no cast time: the cooldown is the cast time.

### Complexity

Every component costs `complexity` (1–4) from a budget of **12 per spell, counting the spell its trigger holds**. The compiler refuses a spell over the budget, with a reason. Shots, speed, radius, pierce and cooldown are also clamped to the limits in `core/spells/limits.gd` (at most 24 shots, 3 modifiers, trigger depth 2). These are performance limits, so a component cannot lift them. Price a component by its power: the shipped ones cost forms 1–2 (bolt 1, the rest 2), elements 1, modifiers 1–2 (split, homing and chain 2) and triggers 1–2 (timer 2). A component stronger than its neighbours costs more; one that makes another obsolete needs a rebalance, not an addition.

### Reactions

Element interactions go in `reactions.tres` (a `ReactionTable` of `ReactionRow`s), so a new element needs no change in other components. One row says: a hit of `element_id` on a target with `status_id` does `effect` (BURST, CONSUME, EXTEND or SPREAD) instead of the element's own status. A pair reacts both ways, so it has two rows with the same `reaction_id` (see the six that ship: shatter, thaw, flare, kindle, stillness, rift). Feel colours and sounds a reaction by its id: add the colour to the preset's `reaction_colors` and the sound `reaction_<id>`.

### The combo row rule

**Every new component comes with at least one combo row** in `combos.json`; by the end of M2 each component is in at least two combos that work. A row has an `id`, `name`, `does` (plain words), `casts` (slot, `recipe`, optional `at` seconds and `player`), `imps` (`[x, y]` pixels from the caster, who stands at (0, 0) and aims along +x), `seconds` and `checks`. A recipe is `{"form": id, "element": id, "modifiers": [ids, at most 3], "trigger": id, "held": {another recipe}}`; every key is optional except `form`, and `held` is the spell the trigger fires. Example: `{"form": "rune", "element": "frost", "trigger": "timer", "held": {"form": "nova", "element": "frost"}}`. Check kinds: `damaged`, `status`, `status_count`, `keeps_burning`, `reaction`, `max_shots`. Copy a row from `combos.json`. `tests/content/spells/test_combos.gd` casts every row in the test arena with the real runtime, so a new row needs no new test code; its recipe must fit the complexity budget.

## Allowed files

`.tres`, `.gd`, the icon (`.png` or `.svg`), SFX (`.ogg`), plus Godot's `.uid` and `.import` files and `.license` files. Limits: 1 MB per image, 5 MB per `.ogg`, 1 MB for anything else. Typed GDScript only; no banned APIs (see AGENTS.md, hard rules).

## Steps

1. Copy the example folder of the same kind into `forms/`, `elements/`, `modifiers/` or `triggers/` and rename the folder.
2. Edit the `.tres`: `id` (equal to the folder), `display_name`, `complexity` and the numbers. Write a `.gd` only if the behaviour is new.
3. Replace the icon (16×16, palette from docs/STYLE.md) and the optional SFX. Add a line for each to `art/manifest.json` or `audio/manifest.json` (path, origin `human` or `ai`, author, license; for AI also tool and prompt). Commit the `.uid` and `.import` files Godot creates.
4. If it interacts with other elements, add the rows to `reactions.tres`.
5. Add the combo row(s) to `combos.json`.
6. Add the builder description: copy `content/story/lore/components/bolt.json` to `content/story/lore/components/<id>.json` and write one honest line (at most 60 characters; say only what the component really does). Without it the builder shows no description and a debug build warns, but nothing fails.
7. Run the checks below, then open a PR using the template.

## Examples to copy

Each is a `.tres` plus an `icon.svg`, no script.

- **Form: `forms/bolt/`.** `FormBase` with damage 5, mana 5, cooldown 0.35 s, speed 220, one STRAIGHT shot, complexity 1. A beam sets `motion` to RAY and `ray_length`, and is a held tick (cooldown 0.25 s, so 4 hits a second on one enemy, 4 mana a tick); a nova raises `shots` and `spread`.
- **Element: `elements/frost/`.** `ElementBase` with `status_id = &"chill"`, 3 s, strength 40, `damage_scale` 1.0 and a palette `tint`, complexity 1. The reactions with other elements are rows in `reactions.tres`, not fields here.
- **Modifier: `modifiers/split/`.** `ModifierBase` with `shot_mult = 3`, `damage_mult = 0.5`, `mana_mult = 1.5`, complexity 2. A modifier names only the fields it changes and leaves the rest at 1; its cost in damage or mana pays for its power. Homing and chain use `behaviour` and `behaviour_strength`.
- **Trigger: `triggers/on_hit/`.** `TriggerBase` with `event = 0` (HIT), `max_fires = 1`, complexity 1. The timer sets `event = 2`, `interval = 0.5` and `max_fires = 4`.

## Validate

```sh
tools/check.sh                      # hard rules, on your changes
ci/build/build.sh --quick --tests   # import, smoke test and every unit test, including the validator and the combo test
```

The registry's check in debug builds and `tests/content/spells/test_validators.gd` report problems as rule, file, field and fix (ids, icons, ranges, complexity, reactions). Fix every one. For a gameplay-visible component, add a short GIF or video to the PR.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it create creative, surprising interactions with existing components?
- Is its power in line with its complexity cost (power budget)?
- Does it avoid making another component obsolete?
- Does it come with a combo row that works?

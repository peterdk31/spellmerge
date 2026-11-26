# Spells

## Purpose

The **cards** players put in their staffs, read left to right (docs/milestones/M2-staffs.md, "Reading a staff"): **carriers** (`carriers/`), what leaves the caster and ends a group; **modifiers** (`modifiers/`) and **infusions** (`elements/`), which change the next carrier (wasted when none follows; end with **Pulse**, `carriers/pulse/`, to put them on the caster; docs/CARRIERS.md); **triggers** (`triggers/`), which make the group after the next carrier its payload; **multicast** (`multicasts/`), which pulls more carriers into one group. Every arrangement is legal; there is no budget.

## Contract

- **A card is one folder**, named like its `id`, holding everything that is the card's: a `.tres` on one of `CarrierCard`, `ElementBase`, `ModifierBase`, `TriggerBase`, `MulticastBase` (`core/base/`, all on `SpellComponent`) with its builder `description`; its icons `icon@2x.svg` (32×32) and `icon.svg` (16×16); its `assets.json`; its combos in `combos/<combo id>.json`; its own test `test_<id>.gd` (most extend `tests/support/card_rig.gd`); optionally a `.gd`, a look shader or an SFX. **Adding a card is adding the folder; taking one out is deleting the folder.**
- Do not edit any central list: the registry (`core/registry`), the combo catalogue, the atlas and the tests find cards by folder.
- **Most components need no script.** Write a `.gd` only for behaviour no field can say. A modifier names its behaviour (`behaviour_id = &"return"`); a new kind of behaviour is engine work in `core/` (its row in `ModifierBase.RULES`). A new kind of carrier is a script in `core/spells/carriers/`.
- Components depend only on `core/`; they never call other areas, only `core/` events. Every effect takes a player index 0–3; nothing assumes a single player.
- Players, bots and the HUD never read a component's fields; they call `Spells` (`compile_staff`, `install_staff`, `cast_staff`, `staff_view`) and its events (`tests/core/test_spell_field_reads.gd`).
- Spawn shots only through the projectile manager (`core/projectiles`); no per-frame allocations.
- Names are original (Fireball, not Hadouken).
- Price a card by its mana and wind-down; a card that makes another obsolete needs a rebalance, not an addition.

### Fields every component has

`id` (the folder name, unique across all kinds), `display_name`, `description` (one honest line, at most 60 characters, the tone of docs/STORY.md), `icon` (`icon@2x.svg`), `icon_small` (`icon.svg`), both listed in `assets.json`, and `complexity` (1–4, a rough measure of power).

### Fields and ranges per kind

Each class's script documents every field; its `ranges()` holds the allowed ranges (ends included) and `range_problems()`/the validator report what is outside. Carriers: `base_damage`, `mana_cost`, `wind_down`, `wind_up`, `speed`, `lifetime`, `radius`, `shots`, `spread`, `carrier` (a script name in `core/spells/carriers/`), `pierce`, `orbit_radius`, `ray_length`, `arc`, `knockback`, `staff_pose` (every carrier has one: `tests/core/test_staff_poses.gd`; `land` checked by `tests/gameplay/player/test_staff_alignment.gd`), `cast_cue`, `shown_cue`, `impact_cue`, `end_cue`. Elements: `status_id` (burn, chill, gust, hex, static, soak), `status_duration`, `status_strength`, `damage_scale`, `tint` (a docs/STYLE.md palette colour), `look_id`. Modifiers: the `*_mult`/`*_add` factors, `behaviour_id`, `behaviour_strength`, `behaviour_reach`, `look_id`, `speed_start`/`speed_end`/`speed_ease`, `move_start`/`move_end`/`move_ease`. Triggers: `event`, `wind_up`. Multicasts: `extra_draws`, `mode`, `repeats`, `repeat_interval`, `mana_cost`, `wind_down`. Multipliers multiply and adds add, in slot order.

### The look of a shot

A shot is drawn by the shot shaders in `core/projectiles/` (core/README.md, "The shot shaders") and Feel's motes. Each infusion and modifier with a `look_id` (a name in `core/base/look_names.gd`, empty for none) adds a particle style; an infusion should pick one no other infusion uses (`tests/content/spells/test_original_looks.gd`). A carrier card may name its own shader in its folder, `look_shader` (include or copy the area's plain drawing, e.g. `core/projectiles/shot_head.gdshaderinc`, or copy `carriers/pool/pool.gdshader` for a still one, `carriers/bolt/bolt.gdshader` for one that flies), plus `look_light_intensity`, `look_light_reach`, and for still cards `look_shape`, `look_open`, `look_fade`, `look_motes` (`CardMoteStream`), `look_on_floor`, `look_merges`. `tests/content/spells/test_card_looks.gd` checks it. Sharing the plain shader is the default.

### Reactions

Element interactions are rows in `reactions.tres` (`ReactionTable` of `ReactionRow`: `element_id` hitting a target with `status_id` does `effect`). **Every reaction is a pair**: two rows with the same `reaction_id`. Each reaction id needs a cue, `content/cues/reaction_<id>.tres` (copy `reaction_thaw.tres`; `tests/gameplay/feel/test_feel_reactions.gd`).

### The combo row rule

**Every new component comes with at least two combos that work**, one file each in its own `combos/`, named like the combo's `id`. Keys: `id`, `name`, `does`, `casts` (`staff`, `cards`, optional `at`, `player`), `imps`, optional `walls`, `seconds`, `checks` (`damaged`, `status`, `status_count`, `lost_at_least`, `keeps_burning`, `reaction`, `max_shots`, `caster_moved`, `blocked`, `deflected`, `killed`), optional `guard`, `foes`, `needs`. Copy a file from a card's `combos/`. `tests/content/spells/test_combos.gd` plays them all.

### What a new element still needs outside its folder

- **A status of its own**: code in `gameplay/combat/combat.gd` (gameplay/combat/README.md, "Every status is a row of one table"), a word in `core/spells/spells.gd`, a name in `core/spells/validator.gd`. Reusing an existing status needs none.
- **A look of its own**: a `LOOK_*` number and `SPARK_RATES` in `core/projectiles/projectile_manager.gd`, its name in `core/base/look_names.gd`, its branch in `core/projectiles/shot_particle.gdshaderinc`.
- **A colour ramp** if the palette has no free hue (`docs/STYLE.md`, `art/kit/`); **a status look** (`status_looks` in the Feel preset).

## Allowed files

`.tres`, `.gd` (a script, and the card's `test_<id>.gd`), icons (`.png`, `.svg`), SFX (`.ogg`), a carrier's look shader (`.gdshader`), `.json` (combos, `assets.json`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 5 MB per `.ogg`, 1 MB otherwise. Typed GDScript only; no banned APIs.

## Steps

1. Copy the example folder of the same kind and rename it.
2. Edit the `.tres`: `id`, `display_name`, `complexity`, the numbers; a carrier also its `staff_pose`.
3. Draw both icons (add the card's parts to `tools/icon_art.py` and run it), list them and any SFX in the folder's `assets.json` (shape of `art/manifest.json`). Commit the `.uid` and `.import` files.
4. New reactions: rows in `reactions.tres` and a cue per new reaction id.
5. Add two combo files.
6. Write the `description`.
7. Run the checks, then open a PR.

## Examples to copy

Carrier `carriers/bolt/`; element `elements/frost/`; modifier `modifiers/split/` (names only the fields it changes); trigger `triggers/on_hit/` (timer: `event = 2`, `wind_up`).

## Validate

`tools/check.sh` and `ci/build/build.sh --quick --tests`. The registry's debug check and `tests/content/spells/test_validators.gd` report problems as rule, file, field and fix; fix every one. Card rules: `tests/content/spells/`, `tests/core/test_cards_together.gd`, `tests/core/test_card_rules.gd`.

## Review questions

Creative interactions with existing cards? Power in line with mana and wind-down? Makes no other card obsolete? Combos that work?

History and reasons: [docs/history/content-spells-README.md](../../docs/history/content-spells-README.md).

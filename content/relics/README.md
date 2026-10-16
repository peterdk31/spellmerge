# Relics

## Purpose

Passive items found during runs. Some add a small bonus; the best change how spell components behave and so open new builds. Each relic should push a run in a direction, not just add numbers.

**Opens for PRs in M3** (Run structure; see "Opens for PRs" in docs/ROADMAP.md). **The example to copy arrives with Claude's first relic in M3**; this README is updated then with its path.

## Contract

- A relic is one folder holding a `.tres` resource on the relic base class (arrives in M3), an optional `.gd` for new behaviour and an icon. Validators reject missing or out-of-range values.
- Content is discovered by folder through `core/registry`; no central list to edit.
- A relic reacts to `core/` events and changes behaviour through the hooks `core/` provides. It never calls spells, enemies or other areas directly.
- Relics are owned per player (index 0–3). Rewards are rolled per player and never wait for anyone.
- It must be understandable from its description alone. Original name and text only.

## Allowed files

`.tres`, `.gd`, icon (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Copy the example folder and rename it.
3. Edit the `.tres` values (name, description, effect parameters). Write a `.gd` only for new behaviour.
4. Replace the icon and add its line to `art/manifest.json`.
5. Run the checks below, then open a PR using the template.

## Example to copy

Arrives with Claude's first content in M3. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Does it add build diversity, or is it a flat upgrade every build wants?
- Is it balanced: is the trade-off clear, and is it fine with 1 and with 4 players?
- Does it work with all existing spell components, without breaking the spell limits?

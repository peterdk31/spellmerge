# Spells

## Purpose

The spell components that players assemble into spells: **forms** (bolt, beam, nova, rune, orbit), **elements** (fire, frost, storm, void), **modifiers** (split, pierce, homing, chain, bigger, faster) and **triggers** (on hit, on expire, timer). A spell is built as form → element → modifiers → trigger, and a trigger holds another spell. Few components, many combinations: this is the game's first pillar (docs/DESIGN.md).

**Opens for PRs in M2** (Spell system; see "Opens for PRs" in docs/ROADMAP.md). Until then, PRs to this folder are a gamble. **The example to copy arrives with Claude's first spell content in M2**; this README is updated then with its path.

## Contract

- A component is one folder holding a `.tres` resource on the spell component base class, an optional `.gd` for new behaviour, an icon and an optional SFX. The base class and its documented fields arrive in M2; validators reject missing or out-of-range values.
- Content is discovered by folder through `core/registry`. Do not edit any central list.
- Element interactions go in `reactions.tres` (in this folder), so a new element does not need changes in other components.
- Components may depend only on `core/`. They never call other areas; they talk through `core/` events (`spell_cast`, ...).
- Every effect takes a player index 0–3. Nothing assumes a single player.
- Every component has a complexity cost. Stay within the spell limits (projectiles per cast, trigger depth, global projectile cap), which are also performance limits. Spawn projectiles through the projectile manager and use pools; no per-frame allocations.
- Names are original. No names from other works (write Fireball, not Hadouken).

## Allowed files

`.tres`, `.gd`, the icon (`.png` or `.svg`), SFX (`.ogg`), plus Godot's `.uid` and `.import` files and `.license` files. Limits: 1 MB per image, 5 MB per `.ogg`, 1 MB for anything else. Typed GDScript only; no banned APIs (see AGENTS.md, hard rules).

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Copy the example folder into the matching sub-folder (`forms/`, `elements/`, `modifiers/` or `triggers/`) and rename it.
3. Edit the `.tres` values. Write a `.gd` only if the behaviour is new.
4. Replace the icon and SFX. Add a line for each to `art/manifest.json` or `audio/manifest.json` (path, origin `human` or `ai`, author, license; for AI also tool and prompt).
5. If it interacts with other elements, add the entries to `reactions.tres`.
6. Run the checks below, then open a PR using the template.

## Example to copy

Arrives with Claude's first content in M2. Do not guess its layout before then.

## Validate

```sh
tools/check.sh                   # hard rules and content validators, on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

For a gameplay-visible component, add a short GIF or video to the PR.

## Rating questions

Besides the standard criteria (fit, fun, quality, value, performance, risk, scope):

- Does it create creative, surprising interactions with existing components?
- Is its power in line with its complexity cost (power budget)?
- Does it avoid making another component obsolete?

Spell components also need the community vote (👍/👎, 24 hours).

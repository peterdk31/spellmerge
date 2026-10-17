# Wizard

## Purpose

Everything that customises the single base wizard. **Cosmetics** (`cosmetics/`) change looks only: hat, robe, colours, staff look. **Staffs** (`staffs/`) are chosen before a run and set the basic attack and a small bonus.

**Opens for PRs in M4** (Polish and variety; see "Opens for PRs" in docs/ROADMAP.md). **The example to copy arrives with Claude's first wizard content in M4**; this README is updated then with its path.

## Contract

- There is one base wizard. No new characters or classes.
- Cosmetics are visual only and must never change gameplay or hitboxes.
- A staff is a `.tres` on the staff base class (arrives in M4) plus an optional `.gd` for a new basic attack. It reacts through `core/` events and the projectile manager, and takes a player index 0–3.
- Each of the four players must stay recognisable: respect the player colours and keep the silhouette readable at 1× with 4 wizards on screen.
- Sprites follow `docs/STYLE.md` (32×32, palette, frame counts). Content is discovered by folder through `core/registry`.

## Allowed files

`.tscn`, `.tres`, `.gd`, sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Copy the example folder into `cosmetics/` or `staffs/` and rename it.
3. Edit the `.tres` values; replace the sprites using the palette in `docs/STYLE.md`.
4. Add a line per asset to `art/manifest.json` (path, origin `human` or `ai`, author, license; for AI also tool and prompt).
5. Run the checks below, then open a PR using the template, with an image or short GIF.

## Example to copy

`content/wizard/base/wizard.tscn`, the base wizard scene (collision shape and a `Sprite` node, with `gameplay/player/player.gd` on the root). The sprite art follows from M1 part 4. Cosmetics and staffs (M4) get their own example when Claude adds the first.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Is the look or playstyle distinct from existing cosmetics and staffs?
- Does it follow the style guide (`docs/STYLE.md`) and read well at 1×?
- For staffs: is the basic attack fun, and is the bonus small enough not to dominate spells?

Art changes (sprites) also need the community vote (👍/👎, 24 hours).

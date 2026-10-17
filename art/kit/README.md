# Art starter kit sources

## Purpose

The source files of the art starter kit (docs/PLAN.md, "Art and music"): what an artist needs to start, in the editor of their choice. The website builds the Style Guide page and the kit zip from these files; the page and the zip are not made here.

## Contract

- The files are the single source of the palette. They must match the table in [docs/STYLE.md](../../docs/STYLE.md); change the table and these files together.
- `art/kit/` holds a `.gdignore`, so Godot neither imports nor ships it. Nothing in the game loads from here.
- The files are templates and lists, not game assets, so they have no manifest entries. The golden examples are existing assets listed by path in `golden.json`; they keep their manifest entries where they are.

## Files

| File | What it is |
| --- | --- |
| `spellmerge.gpl.txt` | The 31 colours as a GIMP palette (`.gpl` files can't be added to the repository, so it carries a `.txt` ending: the kit zip ships it as `spellmerge.gpl`; if you use it from the repository, rename it). Opens in GIMP, Krita, Aseprite, LibreSprite and Inkscape. |
| `palette.hex.txt` | The same colours, one lower-case hex value per line, no `#`, outline first. Imports in Lospec-style palette loaders and Photoshop-like tools that read hex lists. |
| `grid_32.svg` | A 32×32 grid template shown at 16× with the centre lines, the 1 px border and the feet line. |
| `sheet_template.svg` | Animation strip layouts at 4×: idle, walk, hurt, dodge, cast, downed, death, with the unused cells darkened. |
| `golden.json` | The golden example candidates, by path, with what each one shows. |
| `checklist.md` | The one-page checklist: the six rules, the before-you-open-the-PR list, the frame counts, the palette and the golden examples. Generated from docs/STYLE.md by hand for now: keep it in step. |

The templates are drawn at a larger scale than the art, on purpose: they are for looking at, not for exporting. Export your art without the grid at its real size.

Not here: Aseprite `.ase`, Photoshop `.aco`/`.act` and Krita `.kpl` palette files are binary, which sessions and outside contributors cannot add. Most editors read the `.gpl` palette or the hex list; the owner can add binary palettes in the zip build (docs/BACKLOG.md).

## Allowed files

`.txt`, `.md`, `.json`, `.svg` and the `.gdignore` (a `.gpl` is not an allowed type). Limit 1 MB per file.

## Steps

1. Change the palette in docs/STYLE.md first (the owner decides new colours, see docs/DESIGN.md pillar 4).
2. Update `spellmerge.gpl.txt`, `palette.hex.txt` and `checklist.md` to match.
3. Run `tools/check.sh`.

## Example to copy

`spellmerge.gpl.txt` for a palette; `grid_32.svg` for a template.

## Validate

```sh
tools/check.sh
```

Check by eye that every colour in the three palette files appears in the STYLE.md table and nowhere else.

# Wizard

## Purpose

Everything that customises the single base wizard. **Cosmetics** (`cosmetics/`) change looks only: hat, robe, colours, staff look. **Staffs** (`staffs/`) hold the wizard's cards: every wizard has four, one per button, and a staff sets how many slots it has and how fast it casts and recharges (docs/milestones/M2-staffs.md, "Staffs").

**Built in M4** (Polish and variety; see docs/ROADMAP.md). **The example to copy arrives with Claude's first wizard content in M4**; this README is updated then with its path.

## Contract

- There is one base wizard. No new characters or classes.
- Cosmetics are visual only and must never change gameplay or hitboxes.
- A staff is a `.tres` on `StaffBase` (`core/base/staff_base.gd`): `id` (the folder name), `display_name`, `slots` (1–64), `draw` (1–4), `cast_delay` (0–2 s), `recharge` (0–5 s) and `spread` (0–45°: how far each shot may leave its line, either side, at random; both staffs that ship have 0). The validator checks it (`SpellValidator.check_staff`). Two ship: `staffs/starter/` (4 slots, the normal game) and `staffs/dev/` (20 slots, the sandbox in `dev` and `preview` builds). The cards in the slots belong to the player, not the staff. Staff types found in runs are M3.
- Each of the four players must stay recognisable: respect the player colours and keep the silhouette readable at 1× with 4 wizards on screen.
- Sprites follow `docs/STYLE.md` (32×32, palette, frame counts). Content is discovered by folder through `core/registry`.

## Allowed files

`.tscn`, `.tres`, `.gd`, sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs.

## Steps

1. Copy the example folder into `cosmetics/` or `staffs/` and rename it.
2. Edit the `.tres` values; replace the sprites using the palette in `docs/STYLE.md`.
3. Add a line per asset to `art/manifest.json` (path, origin `human` or `ai`, author, license; for AI also tool and prompt).
4. Run the checks below, then open a PR using the template, with an image or short GIF.

## Example to copy

`content/wizard/base/wizard.tscn`, the base wizard scene: an actor (actors G7) whose root runs `gameplay/actor/actor.gd` (ramp, team, `hand_offset`, `staff_reach`), with the kit's components as children (Health, the hurtbox, the mover, Caster), the wizard's own (`Downed`, the `PlayerController` seat, `WizardLook`), a collision shape and a `Sprite` node with its `Hat`. Flow sets its seat, ramp, staff and start cards (`PlayerController.seat_wizard`) before adding it. Its body is style N, with no player colour: strips of 32 px frames, `wizard_idle.svg` (four poses: eyes open, eyes closed, glance left, glance right), `wizard_walk.svg` and `wizard_dash.svg` (the `WizardLook` node lists each four times in `textures`, `walk_textures` and `dash_textures`, one per ramp, and plays the one that fits what the wizard does). The hat is the only player colour: `wizard_hat_p1.svg` to `wizard_hat_p4.svg` (`hat_textures`, by ramp), shown by the `Hat` node under `Sprite`. The look makes the wizard feel alive: it orders the idle poses (`IDLE_SEQUENCE`: a blink every few seconds, a glance now and then), breathes with a 1 px bob and dips the body on the walk's stride frames and the dash (`WALK_BOB`, `DASH_BOB`); the hat goes with the body. A new look is new strips and hats with the same sizes and frame order. `staff.svg` is the staff, drawn along the aim (`staff_texture`). Cosmetics and staffs (M4) get their own example when Claude adds the first.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Is the look or playstyle distinct from existing cosmetics and staffs?
- Does it follow the style guide (`docs/STYLE.md`) and read well at 1×?
- For staffs: is the basic attack fun, and is the bonus small enough not to dominate spells?

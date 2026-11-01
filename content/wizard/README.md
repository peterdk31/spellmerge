# The player's staffs (`content/wizard`)

The folder keeps its old name: the player character was a wizard until living staffs (2026-10-28); now the wizard is the villain.

## Purpose

Everything that customises the single base player. **Cosmetics** (`cosmetics/`) change looks only: hat, robe, colours, staff look. **Staffs** (`staffs/`) hold the player's cards: every player has four, one per button, and a staff sets how many slots it has and how fast it casts and recharges (docs/milestones/M2-staffs.md, "Staffs").

**Built in M4** (Polish and variety; see docs/ROADMAP.md). **The example to copy arrives with Claude's first player content in M4**; this README is updated then with its path.

## Contract

- There is one base player character, the floating staff (living staffs H3). No new characters or classes: a new staff is a new head and personality, not a class.
- Cosmetics are visual only and must never change gameplay or hitboxes.
- A staff is a `.tres` on `StaffBase` (`core/base/staff_base.gd`): `id` (the folder name), `display_name`, `slots` (1–64), `draw` (1–4), `cast_delay` (0–2 s), `recharge` (0–5 s), `spread` (0–45°: how far each shot may leave its line, either side, at random), `max_mana` and `mana_regen` (0–1,000,000: the staff's own mana pool and what it gets back a second; owner 2026-11-01, every staff has its own pool; the starter heads 100 and 10, the `dev` staff a million each), and its look (living staffs H3): `head` (a sheet of 48×48 frames, 16 columns of directions clockwise from pointing right, 4 rows of player ramps, the grip at (24, 27); the player colour on the head only), `tip` (0–32 px from the grip to where shots leave) and the personality, `face_style` and `resting_mood` (`gameplay/actor/face.gd`). The validator checks it (`SpellValidator.check_staff`). A player holds one staff per button: the four starter heads `staffs/curl/` (RB, the Optimist), `staffs/star/` (RT, the Show-off), `staffs/moon/` (LB, the Dozer) and `staffs/crystal/` (LT, the Sergeant), each 4 slots; Play and the horde give a wizard these four; the sandbox gives it `staffs/dev/` on all four buttons (20 slots, no delay, practically infinite mana; its own head, the cog: an upright eight-tooth cog in the player colour round a gold hub, `tip` 18). Each staff file is used as it is: flow copies no numbers between staffs (owner, 2026-11-01). The cards in the slots belong to the player, not the staff. Staff types found in runs are M3.
- Each of the four players must stay recognisable: respect the player colours and keep the silhouette readable at 1× with 4 players on screen.
- Sprites follow `docs/STYLE.md` (32×32, palette, frame counts). Content is discovered by folder through `core/registry`.

## Allowed files

`.tscn`, `.tres`, `.gd`, sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs.

## Steps

1. Copy the example folder into `cosmetics/` or `staffs/` and rename it.
2. Edit the `.tres` values; replace the sprites using the palette in `docs/STYLE.md`.
3. Add a line per asset to `art/manifest.json` (path, origin `human` or `ai`, author, license; for AI also tool and prompt).
4. Run the checks below, then open a PR using the template, with an image or short GIF.

## Example to copy

`content/wizard/base/wizard.tscn`, the base player scene, a floating staff (living staffs H3): an actor whose root runs `gameplay/actor/actor.gd` (ramp, team, `hand_offset` = the grip, `staff_reach`), with the kit's components as children (Health, the hurtbox, the mover, Caster), the player's own (`Downed`, the `PlayerController` seat, `StaffLook`), a `Face`, a collision shape and the `Sprite` (the body). Flow sets its seat, ramp, staffs and start cards (`PlayerController.seat_wizard`) before adding it. The body is the head sheet of the staff on show: a staff's `head` (see Contract), drawn by `StaffLook`; the face (eyes and brows, `art/faces/`) floats over it and takes the staff's personality. The style N wizard art (`wizard_idle.svg`, `wizard_walk.svg`, `wizard_dash.svg`, the hats, `staff.svg`) is no longer the player's: it is kept for the wizard, the villain of the intro (H6). A new staff is a new folder like `staffs/star/`: its `.tres`, its `head.svg` and an `assets.json`.

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

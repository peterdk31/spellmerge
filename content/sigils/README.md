# content/sigils: sigils

A sigil is an inventory item put on a whole staff, not a card in it (docs/milestones/staff-language.md, L4; the owner, 2026-11-25): while its condition holds, the staff casts by itself, along its holder's aim, at its own cooldown and mana, and its holder may still press it. A reward (a rare line of the clear, treasure and challenge tables) or the shop's shelf puts one in the sigils bag; the inventory menu puts it on one of its holder's staffs and takes it off again (the commands `sigil_put_requested` and `sigil_take_requested`). A staff holds at most 3, no two the same, and keeps them wherever it goes (`ItemStack.sigils`). An enemy's staff entry may name some (`StaffCards.sigils`; its staff must wind up, so its telegraph warns). The registry finds each under `sigils` (`ItemKinds.SIGIL`'s row).

## Contract

- **One folder each:** `<id>/` with `<id>.tres` (a `SigilBase`, `core/base/sigil_base.gd`), its `icon@2x.svg` (32 by 32 art pixels, `icon`) and `icon.svg` (16 by 16, `icon_small` for the HUD's small cells; both drawn by `tools/icon_art.py`) and its `assets.json`. Deleting one is deleting its folder (and its lines in the reward tables and any enemy's staff entry).
- **`SigilBase`** (an `ItemContent`): `id` (the folder name), `display_name`, `description`, `icon`, `when` (a condition of `SigilBase.WHENS`: `hurt`, `close`), `amount` (a share of its holder's most health for `hurt`, pixels for `close`) and `words` (what the HUD says after "Casts by itself"). `problems()` must be empty. A new condition is a name in `WHENS` and a line in `Caster.sigil_holds`.

| Sigil | Its staff casts by itself while |
| --- | --- |
| `cast_when_hurt` | its holder is below half health |
| `cast_when_close` | a foe is within 96 px of its holder |

## Allowed files

`.tres`, `.svg` or `.png` icons, `assets.json`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file.

## Example to copy

`cast_when_hurt/`.

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'sigil|test_item_kinds|test_reward_tables'
```

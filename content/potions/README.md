# content/potions: potions

A potion is an inventory item (the owner, 2026-11-19): a reward or a shop's shelf puts it into the potions bag, and it does nothing until its player drinks it from the inventory (A on it in the Potions bag: the command `bag_use_requested`, which the player controller applies at the tick's start). The registry finds each under `potions` (`ItemKinds.POTION`'s row).

## Contract

- **One folder each:** `<id>/` with `<id>.tres` (a `PotionBase`, `core/base/potion_base.gd`), its `icon.svg` (16 by 16) and its `assets.json`. Deleting one is deleting its folder.
- **`PotionBase`** (an `ItemContent`): `id` (the folder name), `display_name`, `description` (what a reward's card and the inventory say of it), `icon`, `usable` (true: every potion is tagged, so it is drunk and binds to a d-pad arm; core/base/item_content.gd), and what a drink does: `heal` (health healed) and `more_most` (most health added, and as much health), through Combat (`health_gift_requested`). A drink that only heals is refused while the wizard is whole, so it is never wasted. `problems()` must be empty.
- A reward table names a potion by its kind and id (`kind = &"potion"`, `id = &"healing"`; content/rewards).

| Potion | A drink |
| --- | --- |
| `healing` | heals 30 |
| `small_healing` | heals 15 |
| `large_healing` | heals 60 |
| `max_health` | 10 more most health, healed too |
| `vigor` | 5 more most health and heals 20 (the owner, 2026-11-19: more potions, so a potion reward room has real choices) |

## Allowed files

`.tres`, `.svg` or `.png` icons, `assets.json`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file.

## Example to copy

`healing/`.

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_potions|test_item_kinds|test_reward_tables'
```
